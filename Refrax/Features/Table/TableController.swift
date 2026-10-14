import AppKit
import QuartzCore
import SwiftUI

/// One window's view onto its space's table: which slabs show, where the view is while it
/// moves, and the commands that move it.
///
/// ## Two layers
///
/// The **rest layer** draws ``presented``, the layout as it last came to rest: the slabs of
/// the current row fully in view are live pages, the current one being the window's active
/// tab, and partly visible slabs are snapshots. It changes only when the view settles, so
/// motion never resizes or remounts a web view.
///
/// The **cover** draws every visible slab from its snapshot at ``viewpoint``. It is up while
/// the view moves and stays up after it settles until the live slabs of the new rest have
/// drawn, then fades out. Under Reduce Motion the cover holds the old view and fades over
/// the new one: a cross-fade with no slide.
///
/// ## Keeping in step
///
/// The controller follows the window: a tab opened becomes a slab right of the current one,
/// a closed tab leaves and its neighbor slides in, a tab activated anywhere becomes the
/// current slab with the least movement, and each space keeps its own table. Edits are
/// written to ``Space/table`` when the view rests and saved through the tab manager's
/// debounced save.
@MainActor
@Observable
final class TableController {
    private enum Layout {
        /// How long the cover takes to fade once the live slabs have drawn.
        static let coverFade: TimeInterval = 0.1
        /// The cover's fade under Reduce Motion, the whole of the cross-fade.
        static let reducedMotionFade: TimeInterval = 0.15
        /// The longest the cover waits for live slabs to draw.
        static let revealTimeout: TimeInterval = 0.6
        /// How long after resting the live slabs are captured again for the next motion.
        static let restCaptureDelay: TimeInterval = 0.4
        /// Recent velocity samples older than this are ignored.
        static let velocityWindow: TimeInterval = 0.08
        /// Full-size snapshots kept for the next motion.
        static let snapshotLimit = 8
    }

    /// A spring in progress from `start` to `target`.
    private struct Flight {
        var start: TableViewpoint
        var target: TableViewpoint
        var velocity: TableViewpoint
        var startTime: CFTimeInterval
    }

    private nonisolated struct SyncKey: Equatable, Sendable {
        var spaceID: UUID?
        var activeTabID: UUID?
        var tabIDs: [UUID]
    }

    // MARK: - State

    /// The layout the view is moving to, or resting on.
    private(set) var layout = TableLayout()
    /// The layout the rest layer draws: ``layout`` as of the last time the view settled.
    private(set) var presented = TableLayout()
    /// Where the cover looks onto ``layout`` while it is up.
    private(set) var viewpoint = TableViewpoint(row: 0)
    /// The cover is drawn over the rest layer.
    private(set) var showsCover = false
    /// The cover's opacity, animated to 0 as it fades.
    private(set) var coverOpacity: Double = 1
    /// The beam from the old focus to the new one after a long jump.
    private(set) var beam: BrowserBeamCues.Request?
    /// The size of the area the table fills: the window beside docked columns.
    private(set) var viewport: CGSize = .zero
    /// That area in the window's content view, top-left origin.
    @ObservationIgnored private(set) var viewportFrame: CGRect = .zero

    /// Full-size captures of slabs, newest last.
    private var captures: [UUID: NSImage] = [:]
    @ObservationIgnored private var captureOrder: [UUID] = []
    @ObservationIgnored private var capturing: Set<UUID> = []

    /// Side slabs whose page this window's table holds live.
    @ObservationIgnored private var sideLiveTabIDs: Set<UUID> = []
    /// Increments each time the view rests, so live slabs report drawing again.
    private(set) var restGeneration = 0
    @ObservationIgnored private var drawnTabIDs: Set<UUID> = []
    @ObservationIgnored private var awaitingReveal = false
    @ObservationIgnored private var revealTimeout: DispatchWorkItem?

    @ObservationIgnored private var flight: Flight?
    @ObservationIgnored private var isPanning = false
    @ObservationIgnored private var panSamples: [(time: TimeInterval, delta: CGSize)] = []
    @ObservationIgnored private var stepQueue = TableStepQueue()
    @ObservationIgnored private var stepTimer: DispatchWorkItem?
    /// The focus when the current motion began, for the beam of a long jump.
    @ObservationIgnored private var motionOrigin: UUID?
    @ObservationIgnored private var beamRevision = 0
    @ObservationIgnored private var spaceID: UUID?
    @ObservationIgnored private var storedLayout: TableLayout?
    @ObservationIgnored private let clock = TableFrameClock()
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    @ObservationIgnored private unowned let windowState: WindowState
    @ObservationIgnored private unowned let tabManager: TabManager
    @ObservationIgnored private unowned let canvas: TabCanvasManager
    @ObservationIgnored private unowned let pagePool: WebPagePool

    init(windowState: WindowState, tabManager: TabManager, canvas: TabCanvasManager, pagePool: WebPagePool) {
        self.windowState = windowState
        self.tabManager = tabManager
        self.canvas = canvas
        self.pagePool = pagePool
        clock.onFrame = { [weak self] time in self?.advanceFlight(at: time) }
    }

    // MARK: - Lifecycle

    /// Starts following the window's space, tabs, and activation.
    func start() {
        let windowState = windowState
        let syncChanges = Observations {
            let space = windowState.activeSpace
            return SyncKey(
                spaceID: space?.id,
                activeTabID: windowState.activeTabID,
                tabIDs: space.map(TableController.tableTabIDs(of:)) ?? [],
            )
        }
        tasks.append(Task { [weak self] in
            for await key in syncChanges {
                self?.sync(key)
            }
        })
        let focusChanges = Observations { windowState.focusedPageID }
        tasks.append(Task { [weak self] in
            for await pageID in focusChanges {
                self?.focusedPageChanged(pageID)
            }
        })
    }

    /// Stops following the window and any motion in flight.
    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        clock.stop()
        stepTimer?.cancel()
        revealTimeout?.cancel()
    }

    // MARK: - Reading

    /// The tabs a space's table holds, in the space's order: every non-archived tab that
    /// is not a favorite.
    static func tableTabIDs(of space: Space) -> [UUID] {
        space.mainTabs.filter { !$0.isFavorite }.map(\.id)
    }

    var camera: TableCamera {
        TableCamera(viewport: viewport)
    }

    /// Whether the window shows `tab` on the table: a tab of the window's space that is not
    /// a favorite.
    func holds(_ tab: Tab) -> Bool {
        !tab.isFavorite && tab.space?.id == windowState.activeSpaceID && !tab.isArchived
    }

    /// The image the cover and partly visible slabs draw for a tab: the newest full-size
    /// capture, or the tab canvas's snapshot.
    func snapshot(for tabID: UUID) -> NSImage? {
        captures[tabID] ?? canvas.snapshots[tabID]
    }

    /// Whether the window shows the table now: its current page is a slab.
    var isShowingTable: Bool {
        currentTab != nil
    }

    /// The window's current page while it is a slab.
    var currentTab: Tab? {
        windowState.activeTab.flatMap { holds($0) ? $0 : nil }
    }

    /// Whether the slide may start with the pointer at `point`, in window coordinates.
    func canSlide(atWindowPoint point: CGPoint) -> Bool {
        guard let window = windowState.window, let content = window.contentView,
              !windowState.showsCommandLens, !windowState.isSpaceLocked, window.attachedSheet == nil,
              !canvas.isActive, !layout.isEmpty, viewport.width > 0, viewport.height > 0,
              let tab = windowState.activeTab, holds(tab)
        else { return false }
        let local = content.convert(point, from: nil)
        let topLeft = CGPoint(x: local.x, y: content.isFlipped ? local.y : content.bounds.height - local.y)
        return viewportFrame.contains(topLeft)
    }

    // MARK: - Geometry

    /// The table view reports the area it fills.
    func updateViewport(_ frame: CGRect) {
        viewportFrame = frame
        if viewport != frame.size {
            viewport = frame.size
        }
    }

    // MARK: - Sliding

    /// A slide starts: the cover comes up over the rest layer and follows the fingers.
    func beginPan(_ delta: CGSize, at time: TimeInterval) {
        stepTimer?.cancel()
        stepTimer = nil
        stepQueue.removeAll()
        if let flight {
            viewpoint = currentViewpoint(of: flight, at: CACurrentMediaTime())
            self.flight = nil
            clock.stop()
        }
        beginMotion()
        isPanning = true
        panSamples.removeAll()
        pan(delta, at: time)
    }

    /// The slide follows a pan of `delta` points.
    func pan(_ delta: CGSize, at time: TimeInterval) {
        guard isPanning else { return }
        viewpoint = camera.panned(viewpoint, by: delta, in: layout)
        panSamples.append((time, delta))
        panSamples.removeAll { time - $0.time > Layout.velocityWindow }
    }

    /// The slide ends: the view springs to the nearest resting place, row first, then slab.
    func endPan() {
        guard isPanning else { return }
        isPanning = false
        guard let rest = camera.restingTarget(in: layout, from: viewpoint) else {
            settle()
            return
        }
        let velocity = panVelocity()
        let next = layout.resting(at: rest)
        viewpoint = camera.rebased(viewpoint, from: layout, to: next)
        layout = next
        fly(to: .resting(on: next), velocity: velocity)
    }

    /// One wheel notch or ⌃⌘ arrow: focus moves one slab or row, queued behind the steps
    /// still playing.
    func step(_ direction: TableDirection) {
        guard !isPanning, viewport.width > 0, isShowingTable else { return }
        stepQueue.push(direction, from: layout)
        guard stepTimer == nil, !stepQueue.isEmpty else { return }
        beginMotion()
        playNextStep()
    }

    // MARK: - Commands

    /// Moves the current slab past its neighbor, or into the neighboring row (⌃⌘⇧ arrows).
    func moveFocusedSlab(_ direction: TableDirection) {
        edit { $0.movingFocusedSlab(direction) }
    }

    /// Cycles the current slab's width ⅓ → ½ → ⅔ → 1 (⌃⌘R).
    func cycleWidth() {
        edit { $0.cyclingWidth() }
    }

    /// The current slab fills the width, or returns to its preset.
    func toggleFill() {
        edit { $0.togglingFill() }
    }

    /// Gives `tab`'s slab a preset width.
    func setWidth(_ width: TableWidth, of tab: Tab) {
        edit { $0.settingWidth(width, of: tab.id) }
    }

    /// Moves `tab`'s slab into a new row below its own, where it becomes current.
    func moveToNewRow(_ tab: Tab) {
        edit { $0.movingToNewRow(tab.id) }
    }

    /// Goes to row `index`, counted from 0, at the slab it remembers.
    func goToRow(_ index: Int) {
        edit { $0.focusingRow(index) }
    }

    /// The width preset of `tab`'s slab, while it is on this window's table.
    func width(of tab: Tab) -> TableWidth? {
        layout.position(of: tab.id).map { layout[$0].width }
    }

    /// Whether `tab`'s slab can leave for a row of its own.
    func canMoveToNewRow(_ tab: Tab) -> Bool {
        layout.position(of: tab.id).map { layout.rows[$0.row].slabs.count > 1 } ?? false
    }

    /// The number of rows on this window's table.
    var rowCount: Int {
        layout.rows.count
    }

    // MARK: - Live slabs

    /// A side slab took its page live, or gave it back.
    func setSideLive(_ isLive: Bool, tabID: UUID) {
        if isLive {
            sideLiveTabIDs.insert(tabID)
        } else {
            sideLiveTabIDs.remove(tabID)
        }
    }

    /// A slab of the rest layer has drawn for `generation`.
    func slabDidDraw(_ tabID: UUID, generation: Int) {
        guard generation == restGeneration else { return }
        drawnTabIDs.insert(tabID)
        revealIfDrawn()
    }

    /// Captures a slab the cover has no image for: the live page when the pool holds it,
    /// otherwise the canvas snapshot stored on disk.
    func requestSnapshot(for tab: Tab) {
        guard snapshot(for: tab.id) == nil, !capturing.contains(tab.id) else { return }
        if pagePool.existingPage(for: tab.activePage) != nil {
            Task { await capture(tab) }
            return
        }
        guard tab.space?.dataStoreMode != .private else { return }
        capturing.insert(tab.id)
        Task {
            if let data = await CanvasSnapshotStore.load(for: tab.id), let image = NSImage(data: data) {
                store(image, for: tab.id)
            }
            capturing.remove(tab.id)
        }
    }

    /// Captures the live slabs, so the cover starts from what they show now. ⌃ going down
    /// asks for this ahead of the slide it may start.
    func captureLiveSlabs() async {
        let camera = camera
        guard viewport.width > 0, !showsCover else { return }
        let live = camera.liveSlabs(in: presented).compactMap { tabManager.state.tab(for: presented[$0].tabID) }
        for tab in live {
            await capture(tab)
        }
    }

    // MARK: - Beam

    func finishBeam(_ request: BrowserBeamCues.Request) {
        if beam == request {
            beam = nil
        }
    }

    // MARK: - Private: keeping in step

    private func sync(_ key: SyncKey) {
        guard let spaceID = key.spaceID, let space = windowState.activeSpace else {
            spaceID = nil
            stopMotion()
            layout = TableLayout()
            presented = layout
            return
        }
        if spaceID != self.spaceID {
            load(space, key: key)
            return
        }
        let old = layout
        var next = layout
        let present = Set(key.tabIDs)
        let removed = old.tabIDs.filter { !present.contains($0) }
        for tabID in removed {
            next = next.removing(tabID)
        }
        let added = key.tabIDs.filter { next.position(of: $0) == nil }
        for tabID in added.reversed() where tabID != key.activeTabID {
            next = next.inserting(tabID, focus: false)
        }
        if let active = key.activeTabID, added.contains(active) {
            next = next.inserting(active, focus: true)
        }

        // A closed current slab gives way to the neighbor sliding into its gap, whichever
        // tab the window picked.
        if let previous = old.focusedTabID, removed.contains(previous), let neighbor = next.focusedTabID,
           key.activeTabID != neighbor, !(key.activeTabID.map { added.contains($0) } ?? false),
           let neighborTab = tabManager.state.tab(for: neighbor) {
            move(to: next)
            tabManager.setActiveTab(neighborTab, in: windowState, displacingPrevious: false)
            return
        }
        if let active = key.activeTabID, next.position(of: active) != nil, next.focusedTabID != active {
            next = next.focusing(active)
        }
        guard next != old else { return }
        move(to: next)
    }

    private func load(_ space: Space, key: SyncKey) {
        stopMotion()
        spaceID = space.id
        let stored = space.table
        storedLayout = stored
        var loaded = stored.reconciled(with: key.tabIDs)
        if let active = key.activeTabID {
            loaded = loaded.focusing(active)
        }
        layout = loaded
        presented = loaded
        viewpoint = .resting(on: loaded)
        restGeneration += 1
        persist()
    }

    /// A click on a live side slab makes its tab current.
    private func focusedPageChanged(_ pageID: UUID?) {
        guard let pageID, let tab = tabManager.state.webPage(for: pageID)?.tabPage.tab,
              tab.id != windowState.activeTabID, sideLiveTabIDs.contains(tab.id), holds(tab)
        else { return }
        tabManager.setActiveTab(tab, in: windowState, displacingPrevious: false)
    }

    // MARK: - Private: motion

    /// Moves the view to `next`, from wherever it shows now.
    private func move(to next: TableLayout) {
        guard viewport.width > 0, viewport.height > 0, isShowingTable || showsCover else {
            stopMotion()
            layout = next
            presented = next
            viewpoint = .resting(on: next)
            persist()
            return
        }
        let start = showsCover ? camera.rebased(currentViewpoint(), from: layout, to: next) : camera.transition(from: presented, to: next)
        let velocity = flight.map { currentVelocity(of: $0, at: CACurrentMediaTime()) } ?? TableViewpoint(row: 0)
        if !showsCover, let origin = presented.focusedTabID {
            Task { [weak self] in
                guard let self, let tab = tabManager.state.tab(for: origin) else { return }
                await capture(tab)
            }
        }
        beginMotion()
        viewpoint = start
        layout = next
        fly(to: .resting(on: next), velocity: velocity)
    }

    /// Captures the live slabs first, then applies a command's edit.
    private func edit(_ transform: @escaping (TableLayout) -> TableLayout) {
        guard !isPanning, isShowingTable else { return }
        Task { [weak self] in
            guard let self else { return }
            await captureLiveSlabs()
            let next = transform(layout)
            guard next != layout else { return }
            move(to: next)
        }
    }

    private func beginMotion() {
        revealTimeout?.cancel()
        awaitingReveal = false
        if !showsCover {
            motionOrigin = presented.focusedTabID
            viewpoint = .resting(on: presented)
        }
        showsCover = true
        coverOpacity = 1
    }

    private func playNextStep() {
        guard let step = stepQueue.next() else {
            stepTimer = nil
            if flight == nil {
                settle()
            }
            return
        }
        move(to: layout.movingFocus(step))
        let timer = DispatchWorkItem { [weak self] in self?.playNextStep() }
        stepTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + TableStepQueue.stepInterval, execute: timer)
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    private func fly(to target: TableViewpoint, velocity: TableViewpoint) {
        guard !reduceMotion else {
            flight = nil
            settle()
            return
        }
        flight = Flight(start: viewpoint, target: target, velocity: velocity, startTime: CACurrentMediaTime())
        if let view = windowState.window?.contentView {
            clock.start(in: view)
        }
    }

    private func advanceFlight(at time: CFTimeInterval) {
        guard let flight else {
            clock.stop()
            return
        }
        let elapsed = time - flight.startTime
        if TableSpring.isSettled(from: flight.start, to: flight.target, velocity: flight.velocity, elapsed: elapsed, rowHeight: viewport.height) {
            viewpoint = flight.target
            self.flight = nil
            clock.stop()
            if stepTimer == nil {
                settle()
            }
            return
        }
        viewpoint = TableSpring.interpolate(from: flight.start, to: flight.target, velocity: flight.velocity, elapsed: elapsed)
    }

    private func currentViewpoint() -> TableViewpoint {
        flight.map { currentViewpoint(of: $0, at: CACurrentMediaTime()) } ?? viewpoint
    }

    private func currentViewpoint(of flight: Flight, at time: CFTimeInterval) -> TableViewpoint {
        TableSpring.interpolate(from: flight.start, to: flight.target, velocity: flight.velocity, elapsed: time - flight.startTime)
    }

    private func currentVelocity(of flight: Flight, at time: CFTimeInterval) -> TableViewpoint {
        let elapsed = time - flight.startTime
        return TableViewpoint(
            row: TableSpring.velocity(from: flight.start.row, to: flight.target.row, velocity: flight.velocity.row, at: elapsed),
            shift: CGFloat(TableSpring.velocity(
                from: Double(flight.start.shift), to: Double(flight.target.shift), velocity: Double(flight.velocity.shift), at: elapsed,
            )),
        )
    }

    /// The pan's recent speed as a viewpoint velocity: rows and points per second.
    private func panVelocity() -> TableViewpoint {
        guard let first = panSamples.first, let last = panSamples.last, last.time > first.time, viewport.height > 0 else {
            return TableViewpoint(row: 0)
        }
        let duration = last.time - first.time
        let total = panSamples.dropFirst().reduce(CGSize.zero) { CGSize(width: $0.width + $1.delta.width, height: $0.height + $1.delta.height) }
        return TableViewpoint(
            row: -Double(total.height / viewport.height) / duration,
            shift: -total.width / CGFloat(duration),
        )
    }

    private func stopMotion() {
        flight = nil
        clock.stop()
        isPanning = false
        stepTimer?.cancel()
        stepTimer = nil
        stepQueue.removeAll()
        revealTimeout?.cancel()
        awaitingReveal = false
        showsCover = false
        coverOpacity = 1
    }

    /// The view has come to rest on ``layout``: the rest layer takes it, its current slab
    /// becomes the window's page, and the cover waits for the live slabs to draw.
    private func settle() {
        guard flight == nil, stepTimer == nil, !isPanning else { return }
        let origin = motionOrigin
        motionOrigin = nil
        presented = layout
        if !reduceMotion {
            viewpoint = .resting(on: layout)
        }
        persist()
        if isShowingTable, let focus = layout.focusedTabID, focus != windowState.activeTabID, let tab = tabManager.state.tab(for: focus) {
            tabManager.setActiveTab(tab, in: windowState, displacingPrevious: false)
        }
        lightBeam(from: origin)
        restGeneration += 1
        drawnTabIDs.removeAll()
        awaitingReveal = true
        let timeout = DispatchWorkItem { [weak self] in self?.reveal() }
        revealTimeout = timeout
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.revealTimeout, execute: timeout)
        revealIfDrawn()
    }

    private func revealIfDrawn() {
        guard awaitingReveal else { return }
        let live = Set(camera.liveSlabs(in: presented).map { presented[$0].tabID })
        guard live.isSubset(of: drawnTabIDs) else { return }
        reveal()
    }

    /// Fades the cover off the live slabs.
    private func reveal() {
        guard awaitingReveal else { return }
        awaitingReveal = false
        revealTimeout?.cancel()
        let duration = reduceMotion ? Layout.reducedMotionFade : Layout.coverFade
        let generation = restGeneration
        withAnimation(.easeOut(duration: duration)) {
            coverOpacity = 0
        } completion: { [weak self] in
            guard let self, restGeneration == generation, flight == nil, !isPanning, stepTimer == nil else { return }
            showsCover = false
            coverOpacity = 1
            viewpoint = .resting(on: presented)
        }
        let recapture = DispatchWorkItem { [weak self] in
            guard let self, restGeneration == generation else { return }
            Task { await self.captureLiveSlabs() }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.restCaptureDelay, execute: recapture)
    }

    private func lightBeam(from origin: UUID?) {
        guard let origin, let focus = layout.focusedTabID, origin != focus,
              let old = layout.position(of: origin), let new = layout.position(of: focus),
              TableCamera.isLongJump(from: old, to: new),
              let source = camera.restingFrame(of: origin, in: layout),
              let destination = camera.restingFrame(of: focus, in: layout)
        else { return }
        let bounds = CGRect(origin: .zero, size: viewport)
        let edge = CGPoint(x: min(max(source.midX, 0), bounds.maxX), y: min(max(source.midY, 0), bounds.maxY))
        let from = source.intersects(bounds) ? source.intersection(bounds) : CGRect(x: edge.x - 1, y: edge.y - 1, width: 2, height: 2)
        beamRevision += 1
        beam = BrowserBeamCues.Request(style: .guide, from: from, to: destination.insetBy(dx: 1, dy: 1), revision: beamRevision)
    }

    // MARK: - Private: storage

    private func persist() {
        guard let space = windowState.activeSpace, space.id == spaceID, storedLayout != layout else { return }
        storedLayout = layout
        space.table = layout
        tabManager.scheduleSave()
    }

    private func capture(_ tab: Tab) async {
        guard !capturing.contains(tab.id), let page = pagePool.existingPage(for: tab.activePage) else { return }
        let bounds = page.contentView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        capturing.insert(tab.id)
        defer { capturing.remove(tab.id) }
        guard let image = try? await page.snapshot() else { return }
        store(image, for: tab.id)
    }

    private func store(_ image: NSImage, for tabID: UUID) {
        captures[tabID] = image
        captureOrder.removeAll { $0 == tabID }
        captureOrder.append(tabID)
        while captureOrder.count > Layout.snapshotLimit {
            captures.removeValue(forKey: captureOrder.removeFirst())
        }
    }
}

/// Calls `onFrame` with each display frame's timestamp while started.
@MainActor
private final class TableFrameClock: NSObject {
    var onFrame: ((CFTimeInterval) -> Void)?
    private var link: CADisplayLink?

    func start(in view: NSView) {
        guard link == nil else { return }
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    @objc
    private func tick(_ link: CADisplayLink) {
        onFrame?(link.timestamp)
    }
}
