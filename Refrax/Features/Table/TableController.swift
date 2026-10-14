import AppKit
import QuartzCore
import SwiftUI

/// One window's view onto its space's table: which slabs show, where the view is while it
/// moves, and the commands that move it.
///
/// ## Live slabs, moved by translation
///
/// Every slab within the viewport and one slab beyond it on each side, in both axes, is a
/// live page at its slab size (``TableCamera/bandSlabs(in:at:)``). Motion only changes
/// ``viewpoint``, which translates them; a slab is never resized or remounted mid-motion. A
/// slab entering that band mounts its page at once, waking it if the pool had let it go, and
/// shows its snapshot until the page has painted. The window's active tab is the current slab.
///
/// ## Free and aligned rests
///
/// A trackpad pan rests where its momentum leaves it, between rows or slabs if that is where
/// it stopped; the slab under the pointer, or else the one most in view, becomes current.
/// Wheel notches, ⌃⌘ arrows, lens jumps, and edits spring the view the least distance that
/// shows their target slab whole.
///
/// Every motion ends in a rest: gesture and momentum ends, a click, a key, ⌃ let go, the
/// window losing key, and a watchdog that settles the view when no input or frame has moved
/// it for ``Layout/watchdogQuiet``. At rest the current slab becomes the window's page.
///
/// ## Keeping in step
///
/// The controller follows the window: a tab opened becomes a slab right of the current one,
/// a closed tab leaves and its neighbor slides in, a tab activated anywhere becomes the
/// current slab with the least movement, and each space keeps its own table. Edits are
/// written to ``Space/table`` when the view rests and saved through the tab manager's
/// debounced save.
///
/// The controller also keeps full-resolution snapshots of pages as they leave view, for the
/// table's slabs and the floating cards alike.
@MainActor
@Observable
final class TableController {
    private enum Layout {
        /// Motion with no input or frame for this long is settled by force.
        static let watchdogQuiet: CFTimeInterval = 0.25
        /// How often the watchdog looks while the view is away from rest.
        static let watchdogInterval: TimeInterval = 0.1
        /// Full-resolution snapshots kept.
        static let snapshotLimit = 12
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
    /// Where the window looks onto ``layout``; ``TableViewpoint/resting(on:)`` at rest.
    private(set) var viewpoint = TableViewpoint(row: 0)
    /// The view is moving: a pan, a spring, or queued wheel steps.
    private(set) var isMoving = false
    /// The beam from the old focus to the new one after a long jump.
    private(set) var beam: BrowserBeamCues.Request?
    /// The size of the area the table fills: the window beside docked columns.
    private(set) var viewport: CGSize = .zero
    /// That area in the window's content view, top-left origin.
    @ObservationIgnored private(set) var viewportFrame: CGRect = .zero

    /// Full-resolution captures of pages, newest last.
    private var captures: [UUID: NSImage] = [:]
    @ObservationIgnored private var captureOrder: [UUID] = []
    @ObservationIgnored private var capturing: Set<UUID> = []

    /// Side slabs whose page this window's table holds live.
    @ObservationIgnored private var sideLiveTabIDs: Set<UUID> = []

    @ObservationIgnored private var flight: Flight?
    @ObservationIgnored private var isPanning = false
    @ObservationIgnored private var stepQueue = TableStepQueue()
    @ObservationIgnored private var stepTimer: DispatchWorkItem?
    @ObservationIgnored private var lastActivity: CFTimeInterval = 0
    @ObservationIgnored private var watchdog: DispatchWorkItem?
    /// The focus when the current motion began, for the beam of a long jump.
    @ObservationIgnored private var motionOrigin: UUID?
    /// The side focus last arrived from: the neighbor an edit keeps in view first.
    @ObservationIgnored private var arrivalSide = TableDirection.left
    @ObservationIgnored private var beamRevision = 0
    @ObservationIgnored private var spaceID: UUID?
    @ObservationIgnored private var storedLayout: TableLayout?
    @ObservationIgnored private let clock = TableFrameClock()
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    /// Called when the view is settled by force, so input stops treating the gesture as a slide.
    @ObservationIgnored var onForcedRest: (() -> Void)?

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
        stopMotion()
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

    /// Whether the window shows the table now: its current page is a slab.
    var isShowingTable: Bool {
        currentTab != nil
    }

    /// The window's current page while it is a slab.
    var currentTab: Tab? {
        windowState.activeTab.flatMap { holds($0) ? $0 : nil }
    }

    /// The image a page shows until it paints, or while another surface holds it: the
    /// newest full-resolution capture, or the tab canvas's snapshot.
    func snapshot(for tabID: UUID) -> NSImage? {
        captures[tabID] ?? canvas.snapshots[tabID]
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

    /// A slide starts and follows the fingers.
    func beginPan(_ delta: CGSize) {
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
        pan(delta)
    }

    /// The slide follows a pan of `delta` points.
    func pan(_ delta: CGSize) {
        guard isPanning else { return }
        noteActivity()
        viewpoint = camera.panned(viewpoint, by: delta, in: layout)
    }

    /// The slide ends where it is: the slab under the pointer, or else the one most in view,
    /// becomes current.
    func endPan() {
        guard isPanning else { return }
        isPanning = false
        if let rest = camera.rest(at: viewpoint, in: layout, pointer: pointerInViewport()) {
            layout = rest.layout
            viewpoint = rest.viewpoint
        }
        settle()
    }

    /// The pointer in the table's coordinates, top-left origin.
    private func pointerInViewport() -> CGPoint? {
        guard let window = windowState.window, let content = window.contentView else { return nil }
        let local = content.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let topLeft = CGPoint(x: local.x, y: content.isFlipped ? local.y : content.bounds.height - local.y)
        return CGPoint(x: topLeft.x - viewportFrame.minX, y: topLeft.y - viewportFrame.minY)
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
        if direction == .left || direction == .right {
            arrivalSide = direction.opposite
        }
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

    // MARK: - Live slabs and snapshots

    /// A side slab took its page live, or gave it back.
    func setSideLive(_ isLive: Bool, tabID: UUID) {
        if isLive {
            sideLiveTabIDs.insert(tabID)
        } else {
            sideLiveTabIDs.remove(tabID)
        }
    }

    /// Captures a page at full resolution, when it has loaded. A page leaving view is
    /// captured so it can be shown again until it repaints.
    func captureSnapshot(of tab: Tab) async {
        guard !capturing.contains(tab.id), let page = pagePool.existingPage(for: tab.activePage),
              page.url != nil, !page.isLoading else { return }
        let bounds = page.contentView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return }
        capturing.insert(tab.id)
        defer { capturing.remove(tab.id) }
        guard let image = try? await page.snapshot() else { return }
        store(image, for: tab.id)
    }

    /// Fills in a slab or card with no image from the canvas snapshot stored on disk.
    func requestStoredSnapshot(for tab: Tab) {
        guard snapshot(for: tab.id) == nil, !capturing.contains(tab.id), tab.space?.dataStoreMode != .private else { return }
        capturing.insert(tab.id)
        Task {
            if let data = await CanvasSnapshotStore.load(for: tab.id), let image = NSImage(data: data), captures[tab.id] == nil {
                store(image, for: tab.id)
            }
            capturing.remove(tab.id)
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
            viewpoint = .resting(on: layout)
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
            arrivalSide = .left
        }
        if !removed.isEmpty || !added.isEmpty {
            next = next.settlingFocus(keepingNeighborOn: arrivalSide)
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
        if let active = key.activeTabID, let target = next.position(of: active), next.focusedTabID != active {
            if let focus = next.focus, focus.row == target.row {
                arrivalSide = target.slab > focus.slab ? .left : .right
            }
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
        viewpoint = .resting(on: loaded)
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
        guard viewport.width > 0, viewport.height > 0, isShowingTable || isMoving else {
            stopMotion()
            layout = next
            viewpoint = .resting(on: next)
            persist()
            return
        }
        let start = camera.rebased(currentViewpoint(), from: layout, to: next)
        let velocity = flight.map { currentVelocity(of: $0, at: CACurrentMediaTime()) } ?? TableViewpoint(row: 0)
        beginMotion()
        viewpoint = start
        layout = next
        fly(to: .resting(on: next), velocity: velocity)
    }

    /// Applies a command's edit to the layout and moves the view to it.
    private func edit(_ transform: (TableLayout) -> TableLayout) {
        guard !isPanning, isShowingTable else { return }
        let edited = transform(layout)
        let next = (edited.focusedTabID.map(edited.focusing) ?? edited).settlingFocus(keepingNeighborOn: arrivalSide)
        guard next != layout else { return }
        move(to: next)
    }

    private func beginMotion() {
        if !isMoving {
            motionOrigin = layout.focusedTabID
            isMoving = true
        }
        noteActivity()
    }

    private func playNextStep() {
        guard let step = stepQueue.next() else {
            stepTimer = nil
            if flight == nil {
                settle()
            }
            return
        }
        if step == .left || step == .right {
            arrivalSide = step.opposite
        }
        let next = layout.movingFocus(step)
        move(to: next.focusedTabID.map(next.focusing) ?? next)
        let timer = DispatchWorkItem { [weak self] in self?.playNextStep() }
        stepTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + TableStepQueue.stepInterval, execute: timer)
    }

    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// Springs the view to `target`; under Reduce Motion it lands at once.
    private func fly(to target: TableViewpoint, velocity: TableViewpoint) {
        noteActivity()
        guard !reduceMotion, let view = windowState.window?.contentView else {
            flight = nil
            clock.stop()
            viewpoint = target
            if stepTimer == nil {
                settle()
            }
            return
        }
        flight = Flight(start: viewpoint, target: target, velocity: velocity, startTime: CACurrentMediaTime())
        clock.start(in: view)
    }

    private func advanceFlight(at time: CFTimeInterval) {
        guard let flight else {
            clock.stop()
            return
        }
        noteActivity()
        let elapsed = time - flight.startTime
        if TableSpring.isSettled(from: flight.start, to: flight.target, velocity: flight.velocity, elapsed: elapsed, rowHeight: viewport.height) {
            landFlight()
            return
        }
        viewpoint = TableSpring.interpolate(from: flight.start, to: flight.target, velocity: flight.velocity, elapsed: elapsed)
    }

    private func landFlight() {
        if let flight {
            viewpoint = flight.target
        }
        flight = nil
        clock.stop()
        if stepTimer == nil {
            settle()
        }
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

    // MARK: - Private: watchdog

    private func noteActivity() {
        lastActivity = CACurrentMediaTime()
        guard watchdog == nil else { return }
        scheduleWatchdog()
    }

    private func scheduleWatchdog() {
        let check = DispatchWorkItem { [weak self] in self?.watchdogCheck() }
        watchdog = check
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.watchdogInterval, execute: check)
    }

    /// Settles motion that has gone quiet: a pan whose end never came, a spring whose frames
    /// stopped, or steps whose timer was lost.
    private func watchdogCheck() {
        watchdog = nil
        guard isMoving else { return }
        guard CACurrentMediaTime() - lastActivity >= Layout.watchdogQuiet else {
            scheduleWatchdog()
            return
        }
        Logger.debug("table watchdog settles panning \(isPanning) flight \(flight != nil) steps \(stepTimer != nil)", category: Logger.canvas)
        if isPanning {
            onForcedRest?()
            endPan()
        } else {
            stepTimer?.cancel()
            stepTimer = nil
            stepQueue.removeAll()
            landFlight()
            if flight == nil, stepTimer == nil, isMoving {
                settle()
            }
        }
        if isMoving {
            scheduleWatchdog()
        }
    }

    private func stopMotion() {
        flight = nil
        clock.stop()
        isPanning = false
        stepTimer?.cancel()
        stepTimer = nil
        stepQueue.removeAll()
        watchdog?.cancel()
        watchdog = nil
        isMoving = false
        motionOrigin = nil
    }

    /// The view has come to rest on ``layout``: its current slab becomes the window's page,
    /// and the pages in view are captured for when they next show.
    private func settle() {
        guard flight == nil, stepTimer == nil, !isPanning else { return }
        let origin = motionOrigin
        motionOrigin = nil
        isMoving = false
        watchdog?.cancel()
        watchdog = nil
        persist()
        if isShowingTable, let focus = layout.focusedTabID, focus != windowState.activeTabID, let tab = tabManager.state.tab(for: focus) {
            tabManager.setActiveTab(tab, in: windowState, displacingPrevious: false)
        }
        lightBeam(from: origin)
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
