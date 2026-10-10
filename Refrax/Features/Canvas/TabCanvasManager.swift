import AppKit
import Observation
import SwiftUI
import WebKit

/// A group drawn on the tab canvas as a zone that holds its member tiles.
struct CanvasZone: Identifiable, Equatable {
    let id: UUID
    let name: String
    let color: NSColor
    /// The zone's rectangle on the board.
    let frame: CGRect
    /// Nesting depth; parents are drawn first.
    let depth: Int
    /// Every tab inside the zone, including those of nested groups.
    let memberTabIDs: [Tab.ID]
}

/// A group drawn on the tab canvas as a magnet that gathers its members around a point.
struct CanvasMagnet: Identifiable, Equatable {
    let id: UUID
    let name: String
    let color: NSColor
    let anchor: CGPoint
    let memberTabIDs: [Tab.ID]
}

/// The board as seen by its manager: something that can run a gesture and report
/// whether its tiles are still moving.
@MainActor
protocol CanvasBoardDriver: AnyObject {
    /// Tiles are moving under the physics simulation.
    var isSimulating: Bool { get }
    /// Moves the opening to `progress`, 0 on the page and 1 at its end.
    func setOpeningProgress(_ progress: CGFloat)
    /// Follows a pinch at `scale` (1 at its start, smaller as the fingers close).
    func setOpeningScale(_ scale: CGFloat)
    /// Shows the desk at page size with the focused tile on the page.
    func beginPanning(focusedTile: CGRect?)
    /// Slides the desk by `delta` screen points.
    func pan(by delta: CGPoint)
    /// Settles into a tile, and the page takes over.
    func settle(on place: CanvasPanSettle)
    /// Zooms by `factor` about a point in window coordinates.
    func zoom(by factor: CGFloat, aboutWindowPoint point: CGPoint)
    /// Completes the opening, or takes it back to the page and closes the canvas.
    func finishOpening(commit: Bool)
    /// Drags a tile along an eased path until its top-left corner reaches `origin`,
    /// through the same hold-and-release path the pointer uses. With `fling` the tile
    /// is let go at full speed and slides on.
    func drag(_ tabID: Tab.ID, to origin: CGPoint, duration: TimeInterval, fling: Bool) async
}

/// Where a desk brought up from a page settles.
enum CanvasPanSettle: Equatable {
    /// The tile nearest the middle of the window.
    case nearest
    /// The tile at a point in window coordinates, or the nearest one to it.
    case tile(atWindowPoint: CGPoint)
    /// The tab the desk came up from.
    case origin
}

/// A hint about getting into or out of the canvas, shown once ever.
enum CanvasHint: String {
    /// Shown the first time a page is pinched, while it zooms.
    case enteringCanvas
    /// Shown the first time the canvas opens.
    case leavingCanvas

    var text: String {
        switch self {
        case .enteringCanvas: "Pinch in to see all your tabs"
        case .leavingCanvas: "Pinch out on a tab to open it · Esc to go back"
        }
    }

    var seenKey: String {
        "canvas.hint.\(rawValue).seen"
    }
}

/// A one-shot request for the board to fly its camera to a rectangle.
struct CanvasZoomRequest: Equatable {
    let serial: Int
    let rect: CGRect
}

/// Manages the tab canvas: a desk on which every tab of the active space is a
/// tile placed at a position of its own, zoomed out from and back into the live page.
///
/// The desk is finite. Tiles keep the position they were given (persisted on
/// ``Tab/boardFrame``), a click zooms into a tile until it fills the window and
/// the live page takes over, and dismissing zooms back out. A tile pushed past the
/// desk's edge falls off, which closes the tab.
///
/// Tab groups appear on the desk in one of two shapes. A **zone**
/// (``TabGroup/boardFrame``) is a region that is at least the claimed rectangle
/// and grows to hold its members; dragging it carries them, dropping a tile inside
/// joins the group. A **magnet** (``TabGroup/boardAnchor``) gathers its members in a
/// ring around a point and attracts tabs similar to them (``CanvasSimilarity``).
///
/// Tile content is a software snapshot of the page, captured whenever the tab is
/// switched away from and again when the canvas opens, and kept on disk, so a tile
/// is as fresh as the last time the page was looked at and survives relaunch.
///
/// Instantiated per window and injected via `RefraxEnvironment`.
@Observable
final class TabCanvasManager {
    // MARK: - Dependencies

    @ObservationIgnored
    private unowned let tabManager: TabManager

    @ObservationIgnored
    private unowned let windowState: WindowState

    @ObservationIgnored
    private unowned let pagePool: WebPagePool

    @ObservationIgnored
    private unowned let groupManager: TabGroupManager

    // MARK: - Public State

    /// Whether the canvas covers the content area.
    private(set) var isActive = false

    /// Tabs on the desk, in sidebar order.
    private(set) var tabs: [Tab] = []

    /// Where each tab's tile sits, mirrored from ``Tab/boardFrame`` for observation.
    private(set) var tileFrames: [Tab.ID: CGRect] = [:]

    /// Zones derived from the space's groups and the current tile positions.
    private(set) var zones: [CanvasZone] = []

    /// Magnets derived from the space's groups.
    private(set) var magnets: [CanvasMagnet] = []

    /// Snapshot of each tab's page.
    private(set) var snapshots: [Tab.ID: NSImage] = [:]

    /// Tiles picked up by the lasso.
    private(set) var selectedTabIDs: Set<Tab.ID> = []

    /// The latest camera request; the board flies there once per serial.
    private(set) var zoomRequest: CanvasZoomRequest?

    /// Bumped by ``close()``; the board zooms back into the focused tile once per value.
    private(set) var closeRequest: Int?

    /// A pinch on the page is opening the canvas and has not been released.
    private(set) var isOpeningInteractively = false

    /// The pinch scale of an interactive opening: 1 at its start, smaller as the fingers close.
    @ObservationIgnored
    private(set) var openingScale: CGFloat = 1

    /// ⌃-scrolling on a page is sliding the desk under it.
    private(set) var isPanningFromPage = false

    /// Wheel movement that arrived before the board was on screen.
    @ObservationIgnored
    private(set) var pendingPan: CGPoint = .zero

    /// A one-time hint on screen, if any.
    private(set) var hint: CanvasHint?

    @ObservationIgnored
    private var hintTask: Task<Void, Never>?

    /// Where the live page sat when the canvas opened, in window coordinates. Tiles
    /// align to it, so the focused tile starts exactly over the page it shows.
    @ObservationIgnored
    private(set) var livePageFrame: CGRect?

    /// The tab the board zooms out from on show and back into on dismiss.
    private(set) var focusedTabID: Tab.ID?

    /// The desk for the space on screen. Tiles that leave it fall off.
    private(set) var deskSize = Layout.minimumDeskSize

    /// Tile size, matching the content area's aspect ratio so a zoomed tile lands
    /// exactly on the live page.
    private(set) var tileSize = Layout.defaultTileSize

    /// The board on screen while the canvas is open.
    @ObservationIgnored
    weak var board: (any CanvasBoardDriver)?

    @ObservationIgnored
    private var snapshotTask: Task<Void, Never>?

    @ObservationIgnored
    private var activationTask: Task<Void, Never>?

    @ObservationIgnored
    private var previousActiveTabID: Tab.ID?

    // MARK: - Constants

    /// The canvas's symbol, shared by the menu item, toolbar button, and Command Lens.
    static let symbolName = "square.grid.3x3.topleft.filled"

    enum Layout {
        /// The smallest desk; a space with more tabs gets a proportionally larger one.
        static let minimumDeskSize = CGSize(width: 4800, height: 3000)
        /// Free slots in the desk's starting grid per tab, so a space opens with room to
        /// move tiles around rather than packed edge to edge.
        static let slotsPerTab: CGFloat = 1.5
        /// Step by which the desk is scaled up until it holds the space.
        static let deskGrowthStep: CGFloat = 0.1
        static let defaultTileSize = CGSize(width: 320, height: 200)
        static let tileWidth: CGFloat = 320
        static let gap: CGFloat = 48
        /// Margin kept between the desk's edge and auto-placed tiles.
        static let deskInset: CGFloat = 120
        /// Breathing room around the tiles when zoomed to fit everything.
        static let fitInset: CGFloat = 80
        /// Width of the snapshot image; the tile is scaled from this.
        static let snapshotWidth = 800
        /// How often tiles of pages playing media are re-captured while the board is open.
        static let mediaRefreshInterval: Duration = .seconds(1)
        /// Space between a zone's edge and the tiles inside it.
        static let zonePadding: CGFloat = 24
        /// Extra room at the top of a zone for its name.
        static let zoneHeaderHeight: CGFloat = 36
        /// Room above a tile for its title.
        static let tileTitleHeight: CGFloat = 24
        /// How long a close may take before the canvas closes without the board.
        static let closeFallbackDelay: Duration = .milliseconds(1500)
        /// How long a one-time hint stays on screen.
        static let hintDuration: Duration = .seconds(4)
        /// Smallest ring a magnet lays its members on.
        static let magnetMinimumRadius: CGFloat = 260
    }

    // MARK: - Initialization

    init(tabManager: TabManager, windowState: WindowState, pagePool: WebPagePool, groupManager: TabGroupManager) {
        self.tabManager = tabManager
        self.windowState = windowState
        self.pagePool = pagePool
        self.groupManager = groupManager

        startObservingActivation()
    }

    isolated deinit {
        activationTask?.cancel()
        snapshotTask?.cancel()
    }

    // MARK: - Showing

    func toggle() {
        if isActive {
            close()
        } else {
            show()
        }
    }

    /// Leaves the canvas the way it was entered: the board zooms back into the tab it
    /// opened from, and that page takes over.
    func close() {
        guard isActive else { return }
        let request = (closeRequest ?? 0) + 1
        closeRequest = request
        // The board normally closes the canvas when its flight lands; if it cannot, the
        // canvas closes anyway rather than trapping the window on the desk.
        Task(name: "Canvas close fallback") { [weak self] in
            try? await Task.sleep(for: Layout.closeFallbackDelay)
            guard let self, isActive, closeRequest == request else { return }
            Logger.debug("close fallback after a board that never landed", category: Logger.canvas)
            dismiss(activating: nil)
        }
    }

    // MARK: - Hints

    /// Shows `hint` once ever, for a few seconds.
    func offerHint(_ hint: CanvasHint) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: hint.seenKey) else { return }
        defaults.set(true, forKey: hint.seenKey)
        self.hint = hint
        hintTask?.cancel()
        hintTask = Task(name: "Canvas hint") { [weak self] in
            try? await Task.sleep(for: Layout.hintDuration)
            guard !Task.isCancelled else { return }
            self?.hint = nil
        }
    }

    // MARK: - Interactive Opening

    /// A pinch on the page starts opening the canvas under the fingers.
    func beginInteractiveOpen() {
        guard !isActive else { return }
        openingScale = 1
        isOpeningInteractively = true
        show()
    }

    /// The pinch moved to `scale`: 1 at its start, smaller as the fingers close.
    func updateInteractiveOpen(scale: CGFloat) {
        guard isOpeningInteractively else { return }
        openingScale = scale
        board?.setOpeningScale(scale)
    }

    // MARK: - Panning from a Page

    /// ⌃-scrolling on a page brings the desk up at page size, to slide under the wheel.
    func beginPan() {
        guard !isActive else { return }
        pendingPan = .zero
        isPanningFromPage = true
        show()
    }

    /// The wheel moved by `delta` screen points.
    func pan(by delta: CGPoint) {
        guard isPanningFromPage else { return }
        if let board {
            board.pan(by: delta)
        } else {
            pendingPan.x += delta.x
            pendingPan.y += delta.y
        }
    }

    /// A mouse wheel zooms the desk brought up from a page, about the pointer.
    func zoom(by factor: CGFloat, aboutWindowPoint point: CGPoint) {
        guard isPanningFromPage else { return }
        board?.zoom(by: factor, aboutWindowPoint: point)
    }

    /// The desk brought up from a page settles into a tile and the page takes over.
    func endPan(settlingOn place: CanvasPanSettle) {
        guard isPanningFromPage else { return }
        isPanningFromPage = false
        if let board {
            board.settle(on: place)
        } else {
            dismiss(activating: nil)
        }
    }

    /// The pinch was released: the canvas finishes opening, or goes back to the page.
    func endInteractiveOpen(commit: Bool) {
        guard isOpeningInteractively else { return }
        isOpeningInteractively = false
        if let board {
            board.finishOpening(commit: commit)
        } else if !commit {
            dismiss(activating: nil)
        }
    }

    /// The live page's frame in window coordinates, while it is on screen.
    func currentLivePageFrame() -> CGRect? {
        guard let tab = windowState.activeTab,
              let view = pagePool.existingPage(for: tab.activePage)?.contentView,
              view.window != nil, !view.isHiddenOrHasHiddenAncestor
        else { return nil }
        return view.convert(view.bounds, to: nil)
    }

    /// Whether the live page is at its normal size, so a closing pinch belongs to the
    /// canvas. A WebKit page zoomed in with a pinch zooms back out first.
    var isLivePageAtNormalSize: Bool {
        guard let tab = windowState.activeTab,
              let webView = pagePool.existingPage(for: tab.activePage)?.contentView as? WKWebView
        else { return true }
        return webView.magnification <= 1.001
    }

    /// A tile is being entered: its tab becomes the active one beneath the canvas, so
    /// the page revealed as the canvas fades is that tab's.
    func prepareToEnter(_ tab: Tab) {
        focusedTabID = tab.id
        if windowState.activeTab?.id != tab.id {
            tabManager.setActiveTab(tab, in: windowState)
        }
    }

    // MARK: - Showing

    /// Opens the canvas for the active space.
    func show() {
        guard !isActive else { return }

        focusedTabID = windowState.activeTab?.id
        livePageFrame = currentLivePageFrame()
        tileSize = contentAspectTileSize()
        selectedTabIDs = []
        reloadTabs()
        isActive = true
        offerHint(.leavingCanvas)

        snapshotTask = Task(name: "Canvas snapshots") {
            await loadStoredSnapshots()
            await refreshSnapshots()
            await keepMediaTilesFresh()
        }
    }

    /// Closes the canvas, switching to `tab` first when one was chosen.
    func dismiss(activating tab: Tab?) {
        guard isActive else { return }
        if let tab {
            tabManager.setActiveTab(tab, in: windowState)
        }
        snapshotTask?.cancel()
        snapshotTask = nil
        selectedTabIDs = []
        openingScale = 1
        isPanningFromPage = false
        isOpeningInteractively = false
        isActive = false
    }

    /// Re-reads the space's tabs, places new ones, and rebuilds zones and magnets.
    private func reloadTabs() {
        tabs = windowState.activeSpaceTabs.filter { !$0.isArchived }
        loadTileFrames()
        // The desk is sized when the canvas opens and only grows while it is open, so
        // no tile is ever left beyond its edge.
        let fitted = fittedDeskSize()
        deskSize = isActive
            ? CGSize(width: max(deskSize.width, fitted.width), height: max(deskSize.height, fitted.height))
            : fitted
        placeUnplacedTabs()
        rebuildGroups()
    }

    /// The smallest desk, in the minimum desk's proportions, whose starting grid has
    /// ``Layout/slotsPerTab`` slots for every tab and that reaches past every placed tile.
    private func fittedDeskSize() -> CGSize {
        let needed = Int((CGFloat(tabs.count) * Layout.slotsPerTab).rounded(.up))
        var scale: CGFloat = 1
        var size = Layout.minimumDeskSize
        while gridSlots(on: size).columns * gridSlots(on: size).rows < needed {
            scale += Layout.deskGrowthStep
            size = CGSize(width: (Layout.minimumDeskSize.width * scale).rounded(), height: (Layout.minimumDeskSize.height * scale).rounded())
        }
        let placed = tabs.compactMap { tileFrames[$0.id] }
        if let first = placed.first {
            let extent = placed.dropFirst().reduce(first) { $0.union($1) }
            size.width = max(size.width, extent.maxX + Layout.deskInset)
            size.height = max(size.height, extent.maxY + Layout.deskInset)
        }
        return size
    }

    /// Columns and rows of the grid new tiles are placed on.
    private func gridSlots(on desk: CGSize) -> (columns: Int, rows: Int, step: CGSize) {
        let step = CGSize(width: tileSize.width + Layout.gap, height: tileSize.height + Layout.gap * 1.5)
        let columns = max(1, Int((desk.width - Layout.deskInset * 2 + Layout.gap) / step.width))
        let rows = max(1, Int((desk.height - Layout.deskInset * 2 + Layout.gap) / step.height))
        return (columns, rows, step)
    }

    // MARK: - Tiles

    /// Records where tiles came to rest, and reshapes the zones around them.
    func settleTiles(_ frames: [Tab.ID: CGRect]) {
        for (tabID, frame) in frames {
            moveTile(tabID, to: frame)
        }
        rebuildGroups()
    }

    private func moveTile(_ tabID: Tab.ID, to frame: CGRect) {
        tileFrames[tabID] = frame
        tab(for: tabID)?.boardFrame = frame
        tabManager.state.scheduleSave()
    }

    /// Settles a dropped tile: it joins the zone it landed in, or leaves the one it left.
    func finishTileDrag(_ tabID: Tab.ID) {
        defer { rebuildGroups() }
        guard let tab = tab(for: tabID), let frame = tileFrames[tabID] else { return }

        let target = zone(containing: CGPoint(x: frame.midX, y: frame.midY))
        let targetGroup = target.flatMap { group(for: $0.id) }
        guard tab.group?.id != targetGroup?.id else { return }
        // Magnet members stay with their magnet unless dropped into a zone.
        if tab.group?.isMagnet == true, targetGroup == nil { return }

        groupManager.moveTabToGroup(tab, group: targetGroup, in: windowState.activeSpace)
    }

    /// A tile pushed off the desk: the tab closes.
    func tileFellOffDesk(_ tabID: Tab.ID) {
        guard let tab = tab(for: tabID) else { return }
        tabManager.closeTab(tab)
        selectedTabIDs.remove(tabID)
        reloadTabs()
    }

    /// The tile of the focused tab, or the first tile.
    var focusedTileFrame: CGRect? {
        if let focusedTabID, let frame = tileFrames[focusedTabID] {
            return frame
        }
        return tabs.first.flatMap { tileFrames[$0.id] }
    }

    /// The smallest rectangle holding every tile and zone, with breathing room.
    var tilesBounds: CGRect {
        let frames = tabs.compactMap { tileFrames[$0.id] } + zones.map(\.frame)
        guard let first = frames.first else {
            return CGRect(origin: .zero, size: tileSize)
        }
        let union = frames.dropFirst().reduce(first) { $0.union($1) }
        return union.insetBy(dx: -Layout.fitInset, dy: -Layout.fitInset)
    }

    /// Tiles are still moving; ``tileFrames`` holds where they last came to rest.
    var isSettling: Bool {
        board?.isSimulating ?? false
    }

    /// Pairs of tiles whose collision boxes overlap. Zero on a settled desk.
    var overlappingPairCount: Int {
        let boxes = tabs.compactMap { tileFrames[$0.id] }
            .map { CanvasPhysics.collisionBox($0).insetBy(dx: CanvasPhysics.Constants.slop, dy: CanvasPhysics.Constants.slop) }
        var count = 0
        for i in boxes.indices {
            for j in (i + 1) ..< boxes.count where boxes[i].intersects(boxes[j]) {
                count += 1
            }
        }
        return count
    }

    /// Drags a tile as a pointer would, then waits for the desk to come to rest.
    /// Returns false when the canvas is not on screen or the desk never settled.
    func performDrag(_ tabID: Tab.ID, to origin: CGPoint, duration: TimeInterval, fling: Bool) async -> Bool {
        guard isActive, let board else { return false }
        await board.drag(tabID, to: origin, duration: duration, fling: fling)
        return await waitUntilSettled()
    }

    /// Waits for the physics to stop moving tiles, up to `timeout`.
    func waitUntilSettled(timeout: Duration = .seconds(10)) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while isSettling {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return true
    }

    // MARK: - Selection

    func select(_ tabIDs: Set<Tab.ID>) {
        selectedTabIDs = tabIDs.intersection(tabs.map(\.id))
    }

    func clearSelection() {
        selectedTabIDs = []
    }

    var selectedTabs: [Tab] {
        tabs.filter { selectedTabIDs.contains($0.id) }
    }

    var selectionBounds: CGRect? {
        let frames = selectedTabs.compactMap { tileFrames[$0.id] }
        guard let first = frames.first else { return nil }
        return frames.dropFirst().reduce(first) { $0.union($1) }
    }

    func zoomToSelection() {
        guard let bounds = selectionBounds else { return }
        requestZoom(to: bounds.insetBy(dx: -Layout.fitInset, dy: -Layout.fitInset))
    }

    func zoomToEverything() {
        requestZoom(to: tilesBounds)
    }

    private func requestZoom(to rect: CGRect) {
        zoomRequest = CanvasZoomRequest(serial: (zoomRequest?.serial ?? 0) + 1, rect: rect)
    }

    func closeSelected() {
        let closing = selectedTabs
        guard !closing.isEmpty else { return }
        tabManager.closeTabs(closing)
        selectedTabIDs = []
        reloadTabs()
    }

    /// Puts the selection into a new zone claiming the area the tiles occupy.
    func groupSelected() {
        let members = selectedTabs
        guard !members.isEmpty, let bounds = selectionBounds,
              let group = try? groupManager.createGroup(in: windowState.activeSpace, name: "Group", color: Self.nextGroupColor())
        else { return }

        for tab in members {
            groupManager.moveTabToGroup(tab, group: group, in: windowState.activeSpace)
        }
        group.boardFrame = bounds.insetBy(dx: -Layout.zonePadding, dy: -Layout.zonePadding)
        tabManager.state.scheduleSave()
        selectedTabIDs = []
        rebuildGroups()
    }

    /// Turns the selection into a magnet at its center, then lets it attract similar tabs.
    func makeMagnetFromSelected() {
        let members = selectedTabs
        guard !members.isEmpty, let bounds = selectionBounds else { return }

        let keys = Set(members.compactMap(CanvasSimilarity.key(for:)))
        let name = keys.count == 1 ? keys.first! : "Magnet"
        guard let group = try? groupManager.createGroup(in: windowState.activeSpace, name: name, color: Self.nextGroupColor()) else { return }

        group.boardAnchor = CGPoint(x: bounds.midX, y: bounds.midY)
        for tab in members {
            groupManager.moveTabToGroup(tab, group: group, in: windowState.activeSpace)
        }
        attractSimilarTabs(to: group)
        arrangeMembers(of: group)
        selectedTabIDs = []
        rebuildGroups()
    }

    // MARK: - Zones and Magnets

    /// Moves a zone and everything in it.
    func moveZone(_ groupID: UUID, by delta: CGPoint) {
        guard let zone = zones.first(where: { $0.id == groupID }) else { return }
        for tabID in zone.memberTabIDs {
            if let frame = tileFrames[tabID] {
                moveTile(tabID, to: frame.offsetBy(dx: delta.x, dy: delta.y))
            }
        }
        for group in groups() where group.id == groupID || descendantGroupIDs(of: groupID).contains(group.id) {
            if let claimed = group.boardFrame {
                group.boardFrame = claimed.offsetBy(dx: delta.x, dy: delta.y)
            }
        }
        rebuildGroups()
    }

    /// Moves a magnet and its ring of members.
    func moveMagnet(_ groupID: UUID, by delta: CGPoint) {
        guard let group = group(for: groupID), let anchor = group.boardAnchor,
              let magnet = magnets.first(where: { $0.id == groupID }) else { return }
        group.boardAnchor = CGPoint(x: anchor.x + delta.x, y: anchor.y + delta.y)
        for tabID in magnet.memberTabIDs {
            if let frame = tileFrames[tabID] {
                moveTile(tabID, to: frame.offsetBy(dx: delta.x, dy: delta.y))
            }
        }
        rebuildGroups()
    }

    /// Pulls in every ungrouped tab similar to the magnet's members and re-forms the ring.
    func attract(_ groupID: UUID) {
        guard let group = group(for: groupID), group.isMagnet else { return }
        attractSimilarTabs(to: group)
        arrangeMembers(of: group)
        rebuildGroups()
    }

    private func attractSimilarTabs(to group: TabGroup) {
        let memberKeys = Set(tabs.filter { $0.group?.id == group.id }.compactMap(CanvasSimilarity.key(for:)))
        guard !memberKeys.isEmpty else { return }
        for tab in tabs where tab.group == nil {
            if let key = CanvasSimilarity.key(for: tab), memberKeys.contains(key) {
                groupManager.moveTabToGroup(tab, group: group, in: windowState.activeSpace)
            }
        }
    }

    /// Lays a magnet's members on a ring around its anchor.
    private func arrangeMembers(of group: TabGroup) {
        guard let anchor = group.boardAnchor else { return }
        let members = tabs.filter { $0.group?.id == group.id }
        guard !members.isEmpty else { return }

        let circumference = CGFloat(members.count) * (tileSize.width + Layout.gap)
        let radius = max(Layout.magnetMinimumRadius, circumference / (2 * .pi))
        for (index, tab) in members.enumerated() {
            let angle = -CGFloat.pi / 2 + CGFloat(index) / CGFloat(members.count) * 2 * .pi
            let center = CGPoint(x: anchor.x + cos(angle) * radius, y: anchor.y + sin(angle) * radius)
            moveTile(tab.id, to: CGRect(
                x: (center.x - tileSize.width / 2).rounded(),
                y: (center.y - tileSize.height / 2).rounded(),
                width: tileSize.width,
                height: tileSize.height,
            ))
        }
    }

    private static let groupColors: [GroupColor] = [.pelorus, .coral, .emerald, .violet, .flamingo, .turquoise, .orchid, .avocado]
    private static var nextColorIndex = 0

    private static func nextGroupColor() -> String {
        let color = groupColors[nextColorIndex % groupColors.count]
        nextColorIndex += 1
        return color.rawValue
    }

    // MARK: - Lookup

    private func tab(for id: Tab.ID) -> Tab? {
        tabs.first { $0.id == id }
    }

    private func groups() -> [TabGroup] {
        windowState.activeSpaceGroups.filter { !$0.isArchive }
    }

    private func group(for id: UUID) -> TabGroup? {
        groups().first { $0.id == id }
    }

    private func descendantGroupIDs(of groupID: UUID) -> Set<UUID> {
        let all = groups()
        var result = Set<UUID>()
        var frontier = [groupID]
        while let current = frontier.popLast() {
            for child in all where child.parentGroupID == current && !result.contains(child.id) {
                result.insert(child.id)
                frontier.append(child.id)
            }
        }
        return result
    }

    /// The deepest zone whose rectangle contains `point`.
    private func zone(containing point: CGPoint) -> CanvasZone? {
        zones.filter { $0.frame.contains(point) }.max { $0.depth < $1.depth }
    }

    // MARK: - Placement

    private func loadTileFrames() {
        var frames: [Tab.ID: CGRect] = [:]
        for tab in tabs {
            if let frame = tab.boardFrame {
                frames[tab.id] = frame
            }
        }
        tileFrames = frames
    }

    /// Places tabs that have no tile yet in reading order across the desk's grid, after
    /// the last placed one. ``fittedDeskSize()`` sizes the desk so the grid has room.
    private func placeUnplacedTabs() {
        let unplaced = tabs.filter { tileFrames[$0.id] == nil }
        guard !unplaced.isEmpty else { return }

        let (columns, rows, step) = gridSlots(on: deskSize)
        var index = tabs.count - unplaced.count
        for tab in unplaced {
            let column = index % columns
            let row = min(index / columns, rows - 1)
            let frame = CGRect(
                x: Layout.deskInset + CGFloat(column) * step.width,
                y: Layout.deskInset + CGFloat(row) * step.height,
                width: tileSize.width,
                height: tileSize.height,
            )
            tileFrames[tab.id] = frame
            tab.boardFrame = frame
            index += 1
        }
        tabManager.state.scheduleSave()
    }

    private func contentAspectTileSize() -> CGSize {
        guard let activeTab = windowState.activeTab,
              let page = pagePool.existingPage(for: activeTab.activePage) else {
            return Layout.defaultTileSize
        }
        let bounds = page.contentView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return Layout.defaultTileSize }
        let height = (Layout.tileWidth * bounds.height / bounds.width).rounded()
        return CGSize(width: Layout.tileWidth, height: height)
    }

    // MARK: - Group Shapes

    /// Recomputes every zone and magnet from the groups and the current tile positions.
    ///
    /// A zone is the union of the group's claimed rectangle, its own tiles (padded,
    /// with room for their titles), and its child zones. Groups with neither a claim
    /// nor members have no zone. Groups with an anchor are magnets instead.
    private func rebuildGroups() {
        let all = groups()
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        var frames: [UUID: CGRect] = [:]
        var members: [UUID: [Tab.ID]] = [:]

        func depth(of group: TabGroup) -> Int {
            var depth = 0
            var parent = group.parentGroupID.flatMap { byID[$0] }
            while let current = parent {
                depth += 1
                parent = current.parentGroupID.flatMap { byID[$0] }
            }
            return depth
        }

        func resolve(_ group: TabGroup) -> CGRect? {
            if let frame = frames[group.id] { return frame }
            var rects: [CGRect] = []
            var tabIDs: [Tab.ID] = []
            if let claimed = group.boardFrame { rects.append(claimed) }
            for tab in tabs where tab.group?.id == group.id {
                if let frame = tileFrames[tab.id] {
                    var padded = frame.insetBy(dx: -Layout.zonePadding, dy: -Layout.zonePadding)
                    padded.origin.y -= Layout.tileTitleHeight
                    padded.size.height += Layout.tileTitleHeight
                    rects.append(padded)
                    tabIDs.append(tab.id)
                }
            }
            for child in all where child.parentGroupID == group.id && !child.isMagnet {
                if let childFrame = resolve(child) {
                    rects.append(childFrame.insetBy(dx: -Layout.zonePadding, dy: -Layout.zonePadding))
                    tabIDs.append(contentsOf: members[child.id] ?? [])
                }
            }
            guard let first = rects.first else { return nil }
            var union = rects.dropFirst().reduce(first) { $0.union($1) }
            union.origin.y -= Layout.zoneHeaderHeight
            union.size.height += Layout.zoneHeaderHeight
            frames[group.id] = union
            members[group.id] = tabIDs
            return union
        }

        zones = all.filter { !$0.isMagnet }.compactMap { group in
            guard let frame = resolve(group) else { return nil }
            return CanvasZone(
                id: group.id,
                name: group.name,
                color: NSColor(group.color),
                frame: frame,
                depth: depth(of: group),
                memberTabIDs: members[group.id] ?? [],
            )
        }
        .sorted { $0.depth < $1.depth }

        magnets = all.compactMap { group in
            guard let anchor = group.boardAnchor else { return nil }
            return CanvasMagnet(
                id: group.id,
                name: group.name,
                color: NSColor(group.color),
                anchor: anchor,
                memberTabIDs: tabs.filter { $0.group?.id == group.id }.map(\.id),
            )
        }
    }

    // MARK: - Snapshots

    /// Captures a tab's page as it is switched away from, so its tile shows what was last seen.
    private func startObservingActivation() {
        let getActiveTabID = { [weak windowState] in windowState?.activeTabID }
        let changes = Observations { getActiveTabID() }

        activationTask = Task { [weak self] in
            for await activeTabID in changes {
                guard let self else { return }
                if let previous = previousActiveTabID, previous != activeTabID,
                   let tab = tabManager.state.tab(for: previous) {
                    await refreshSnapshot(for: tab)
                }
                previousActiveTabID = activeTabID
            }
        }
    }

    /// Fills tiles from disk for tabs without an in-memory snapshot.
    private func loadStoredSnapshots() async {
        for tab in tabs where snapshots[tab.id] == nil {
            guard !Task.isCancelled else { return }
            if let data = await CanvasSnapshotStore.load(for: tab.id), let image = NSImage(data: data) {
                snapshots[tab.id] = image
            }
        }
    }

    /// Captures every live page. WebKit paints the snapshot in the web process from
    /// the frame's contents, so pages that are not on screen can be captured too.
    private func refreshSnapshots() async {
        for tab in tabs {
            guard !Task.isCancelled else { return }
            await refreshSnapshot(for: tab)
        }
    }

    /// Pages playing media change under their snapshot; re-capture them while the board is open.
    private func keepMediaTilesFresh() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: Layout.mediaRefreshInterval)
            for tab in tabs where pagePool.existingPage(for: tab.activePage)?.isPlayingAudio == true {
                guard !Task.isCancelled else { return }
                await refreshSnapshot(for: tab)
            }
        }
    }

    private func refreshSnapshot(for tab: Tab) async {
        guard let page = pagePool.existingPage(for: tab.activePage) else { return }
        let bounds = page.contentView.bounds
        guard bounds.width > 0, bounds.height > 0,
              let captured = try? await page.snapshot(),
              let image = captured.scaled(toWidth: CGFloat(Layout.snapshotWidth)) else { return }
        snapshots[tab.id] = image
        if let tiff = image.tiffRepresentation {
            await CanvasSnapshotStore.save(tiff: tiff, for: tab.id)
        }
    }
}
