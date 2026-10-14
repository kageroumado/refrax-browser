import AppKit
import Observation
import SwiftUI

/// One window's view onto its space's table: the layout built from the space's groups and
/// tabs, the widths kept for them, the viewport, and the commands that move it.
///
/// ## One plane, scrolled natively
///
/// The table is a plane of live pages inside ``TableScrollView``. Motion is the scroll view's
/// own: the document moves under the window and no page is ever resized, remounted, or
/// replaced to move. The controller tells the scroll view where to go (``reveal(_:animated:)``,
/// ``step(_:)``, the overview) and learns from it where the window is (``visibleRect``,
/// ``magnification``) and when it has come to rest (``settle(pointerAt:)``), at which point the
/// slab under the pointer, or the one most in view, becomes the window's page.
///
/// ## Keeping in step
///
/// The layout follows the space: a tab opened, closed, moved, or grouped rebuilds it, and the
/// slabs already on screen keep their places. A tab activated anywhere else (the lens, the
/// island, a key) is revealed with the least movement.
@MainActor
@Observable
final class TableController {
    enum Layout {
        static let snapshotLimit = 12
        /// How long the ribbon stays after the table comes to rest.
        static let ribbonLinger: Duration = .milliseconds(400)
        /// Below this magnification slabs show their snapshots instead of live pages.
        static let liveMagnification: CGFloat = 0.5
        /// Room around the table when it is fitted into the window.
        static let overviewInset: CGFloat = 48
        /// A pinch released at or below this magnification stays in the overview.
        static let overviewCommit: CGFloat = 0.85
        static let flightDuration: TimeInterval = 0.32
        static let minimumMagnification: CGFloat = 0.05
    }

    private nonisolated struct SyncKey: Equatable, Sendable {
        var spaceID: UUID?
        var tabListVersion: UInt64
        var collapsed: [UUID: Bool]
        var docked: Set<UUID>
    }

    // MARK: - State

    /// The table, rebuilt from the space whenever it changes.
    private(set) var layout = TableLayout()
    /// Each slab's width and fill, saved on the space.
    private(set) var state = TableState()
    /// The size of the area the table fills: the window beside docked columns.
    private(set) var viewport: CGSize = .zero
    /// That area in the window's content view, top-left origin.
    @ObservationIgnored private(set) var viewportFrame: CGRect = .zero
    /// The part of the plane the window shows, in plane points.
    private(set) var visibleRect: CGRect = .zero
    private(set) var magnification: CGFloat = 1
    /// The table is scrolling or magnifying, by hand or in flight.
    private(set) var isMoving = false
    /// The ribbon is up: while moving and for a moment after.
    private(set) var showsRibbon = false
    /// The slab the ribbon names: the one under the pointer while moving, else the most visible.
    private(set) var ribbonSlab: TableLayout.Position?
    /// The tab the pinch started on; it stays current until the overview is left for another.
    @ObservationIgnored private var pinchOrigin: UUID?

    private var captures: [UUID: NSImage] = [:]
    @ObservationIgnored private var captureOrder: [UUID] = []
    @ObservationIgnored private var capturing: Set<UUID> = []
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var ribbonTask: Task<Void, Never>?
    /// The tab the table itself made current, so its activation is not revealed a second time.
    @ObservationIgnored private var activatedByTable: UUID?
    @ObservationIgnored private var spaceID: UUID?

    /// The scroll view showing the table, while one is on screen.
    @ObservationIgnored weak var scrollView: TableScrollView?

    @ObservationIgnored private unowned let windowState: WindowState
    @ObservationIgnored private unowned let tabManager: TabManager
    @ObservationIgnored private unowned let groupManager: TabGroupManager
    @ObservationIgnored private unowned let canvas: TabCanvasManager
    @ObservationIgnored private unowned let pagePool: WebPagePool

    init(windowState: WindowState, tabManager: TabManager, groupManager: TabGroupManager, canvas: TabCanvasManager, pagePool: WebPagePool) {
        self.windowState = windowState
        self.tabManager = tabManager
        self.groupManager = groupManager
        self.canvas = canvas
        self.pagePool = pagePool
    }

    // MARK: - Lifecycle

    /// Starts following the window's space, tabs, groups, and activation.
    func start() {
        rebuild()
        let windowState = windowState
        let tabManager = tabManager
        let canvas = canvas
        let syncChanges = Observations {
            let space = windowState.activeSpace
            return SyncKey(
                spaceID: space?.id,
                tabListVersion: tabManager.state.tabListVersion,
                collapsed: Dictionary(uniqueKeysWithValues: (space?.groups ?? []).map { ($0.id, $0.isCollapsed) }),
                docked: Set((space?.mainTabs ?? []).filter { canvas.storedFloatingPlacement(for: $0)?.isDocked == true }.map(\.id)),
            )
        }
        tasks.append(Task(name: "Follow the space's table") { [weak self] in
            for await _ in syncChanges {
                self?.rebuild()
            }
        })
        let activation = Observations { windowState.activeTabID }
        tasks.append(Task(name: "Follow the window's page") { [weak self] in
            for await tabID in activation {
                self?.activeTabChanged(tabID)
            }
        })
    }

    func stop() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
    }

    // MARK: - Reading

    var geometry: TableGeometry {
        TableGeometry(viewport: viewport)
    }

    /// The window shows the table zoomed out.
    var isOverview: Bool {
        magnification < 1 - 0.001
    }

    /// Slabs draw their pages; in a deep overview they draw snapshots.
    var showsLivePages: Bool {
        magnification >= Layout.liveMagnification
    }

    var currentTab: Tab? {
        windowState.activeTab.flatMap { holds($0) ? $0 : nil }
    }

    var navigationTabID: UUID? {
        currentTab?.id
    }

    /// Whether the window shows `tab` on the table.
    func holds(_ tab: Tab) -> Bool {
        layout.position(of: tab.id) != nil
    }

    func tab(for id: UUID) -> Tab? {
        tabManager.state.tab(for: id)
    }

    /// The tab a step in `direction` reaches from the current slab.
    func destination(toward direction: TableDirection) -> Tab? {
        guard let current = currentTab else { return nil }
        let target: UUID? = switch direction {
        case .left, .right:
            layout.neighbor(of: current.id, toward: direction)
        case .up, .down:
            layout.rowIndex(from: current.id, toward: direction).flatMap { layout.slab(inRow: $0, nearest: current.id) }
        }
        return target.flatMap(tab(for:))
    }

    func width(of tab: Tab) -> TableWidth? {
        holds(tab) ? state.width(of: tab.id) : nil
    }

    /// The row and place the ribbon names, as text: "Research · 3 of 7".
    var ribbonText: String? {
        guard let position = ribbonSlab, layout.rows.indices.contains(position.row) else { return nil }
        let row = layout.rows[position.row]
        let title = row.title.isEmpty ? (windowState.activeSpace?.name ?? "") : row.title
        let place = "\(position.slab + 1) of \(row.slabs.count)"
        return title.isEmpty ? place : "\(title) · \(place)"
    }

    var ribbonColor: Color? {
        guard let position = ribbonSlab, layout.rows.indices.contains(position.row),
              let stored = layout.rows[position.row].colorString else { return nil }
        return Color.resolveStoredColor(stored)
    }

    // MARK: - Building

    /// Rebuilds the layout from the space: its loose tabs first, then a row per group in the
    /// groups' order. Favorites and docked pages are not on the table.
    private func rebuild() {
        guard let space = windowState.activeSpace else {
            layout = TableLayout()
            state = TableState()
            spaceID = nil
            scrollView?.apply(layout: layout, geometry: geometry)
            return
        }
        if spaceID != space.id {
            spaceID = space.id
            state = TableState.decode(space.tableLayoutData)
        }
        let onTable = space.mainTabs.filter { !$0.isFavorite && canvas.storedFloatingPlacement(for: $0)?.isDocked != true }
        var rows = [TableLayout.RowSource(id: space.id, tabIDs: onTable.filter { $0.group == nil }.map(\.id))]
        for group in space.groups.filter({ !$0.isArchive }).sorted(by: { $0.position < $1.position }) {
            let members = group.sortedTabs.filter { tab in onTable.contains { $0.id == tab.id } }.map(\.id)
            rows.append(TableLayout.RowSource(id: group.id, title: group.name, colorString: group.colorString, isCollapsed: group.isCollapsed, tabIDs: members))
        }
        let rebuilt = TableLayout(rows: rows, state: state)
        guard rebuilt != layout else { return }
        layout = rebuilt
        Logger.info("table rebuilt: \(rebuilt.rows.count) rows, \(rebuilt.tabIDs.count) slabs; current held: \(windowState.activeTab.map(holds) ?? false); scroll view: \(scrollView != nil)", category: Logger.table)
        scrollView?.apply(layout: layout, geometry: geometry)
        if let current = windowState.activeTab, holds(current), let frame = geometry.frame(of: current.id, in: layout),
           !geometry.isWhole(frame, at: visibleRect.origin), !isMoving {
            reveal(current.id)
        }
    }

    private func persistState() {
        guard let space = windowState.activeSpace else { return }
        state.prune(keeping: layout.tabIDs)
        space.tableLayoutData = state.encoded()
        tabManager.scheduleSave()
    }

    // MARK: - Geometry

    /// The table view reports the area it fills.
    func updateViewport(_ frame: CGRect) {
        viewportFrame = frame
        guard viewport != frame.size else { return }
        let previous = currentTab
        viewport = frame.size
        scrollView?.apply(layout: layout, geometry: geometry)
        if let previous, !isOverview {
            reveal(previous.id, animated: false)
        }
    }

    /// The scroll view reports where the window looks.
    func viewportMoved(visibleRect: CGRect, magnification: CGFloat) {
        self.visibleRect = visibleRect
        self.magnification = magnification
        if !isMoving {
            isMoving = true
        }
        showRibbon()
    }

    private func showRibbon() {
        ribbonSlab = slabUnderPointer() ?? geometry.mostVisibleSlab(in: visibleRect, of: layout)
        showsRibbon = true
        ribbonTask?.cancel()
    }

    /// The slab under the pointer, in plane coordinates, if the pointer is over the table.
    private func slabUnderPointer() -> TableLayout.Position? {
        guard let scrollView, let window = scrollView.window else { return nil }
        let point = scrollView.document.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        guard scrollView.document.bounds.contains(point) else { return nil }
        return geometry.slab(at: point, in: layout)
    }

    // MARK: - Resting

    /// The scroll view has come to rest. The slab under the pointer, or else the most visible
    /// one, becomes the window's page; the ribbon lingers a moment and fades.
    func settle() {
        isMoving = false
        ribbonTask?.cancel()
        ribbonTask = Task(name: "Fade the table ribbon") { [weak self] in
            try? await Task.sleep(for: Layout.ribbonLinger)
            guard !Task.isCancelled else { return }
            self?.showsRibbon = false
        }
        guard !isOverview else { return }
        let position = slabUnderPointer() ?? geometry.mostVisibleSlab(in: visibleRect, of: layout)
        guard let position, let tab = tab(for: layout[position].tabID) else { return }
        activate(tab)
    }

    private func activate(_ tab: Tab) {
        guard windowState.activeTabID != tab.id else { return }
        activatedByTable = tab.id
        tabManager.setActiveTab(tab, in: windowState, displacingPrevious: false)
    }

    private func activeTabChanged(_ tabID: UUID?) {
        guard let tabID, layout.position(of: tabID) != nil else { return }
        if activatedByTable == tabID {
            activatedByTable = nil
            return
        }
        if isOverview {
            enter(tabID)
        } else {
            reveal(tabID)
        }
    }

    // MARK: - Moving

    /// Moves the view the least distance that shows `tabID` whole, at reading size.
    func reveal(_ tabID: UUID, animated: Bool = true) {
        guard let scrollView, let frame = geometry.frame(of: tabID, in: layout) else {
            Logger.info("table reveal: no scroll view (\(scrollView == nil)) or frame", category: Logger.table)
            return
        }
        let origin = geometry.origin(revealing: frame, from: visibleRect.origin, in: layout)
        Logger.info("table reveal \(frame) from \(visibleRect) → \(origin); viewport \(viewport)", category: Logger.table)
        scrollView.scroll(to: origin, magnification: 1, animated: animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// Makes the neighbor in `direction` current and reveals it.
    func step(_ direction: TableDirection) {
        Logger.info("table step \(direction.rawValue): current \(currentTab?.displayTitle ?? "none"), destination \(destination(toward: direction)?.displayTitle ?? "none")", category: Logger.table)
        guard let tab = destination(toward: direction) else {
            scrollView?.nudge(direction)
            return
        }
        activate(tab)
        reveal(tab.id)
    }

    /// Leaves the overview on `tabID`: it becomes current and the table returns to reading
    /// size with it aligned.
    func enter(_ tabID: UUID) {
        guard let scrollView, let tab = tab(for: tabID), let frame = geometry.frame(of: tabID, in: layout) else { return }
        activate(tab)
        let origin = geometry.clamped(frame.origin, in: layout)
        scrollView.scroll(to: origin, magnification: 1, animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// Zooms the table out until it fits the window.
    func showOverview() {
        guard let scrollView, !layout.isEmpty else { return }
        let size = geometry.tableSize(of: layout)
        let fit = min(
            (viewport.width - 2 * Layout.overviewInset) / size.width,
            (viewport.height - 2 * Layout.overviewInset) / size.height,
            1,
        )
        let magnification = max(Layout.minimumMagnification, fit)
        let origin = CGPoint(
            x: (size.width - viewport.width / magnification) / 2,
            y: (size.height - viewport.height / magnification) / 2,
        )
        scrollView.scroll(to: origin, magnification: magnification, animated: !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    /// The overview and the current page, back and forth.
    func toggleOverview() {
        if isOverview, let current = currentTab {
            enter(current.id)
        } else {
            showOverview()
        }
    }

    /// Returns from the overview to the page the pinch began on.
    func leaveOverview() {
        guard isOverview, let tabID = pinchOrigin ?? currentTab?.id else { return }
        enter(tabID)
    }

    // MARK: - Pinching

    /// A pinch on the page zooms the table about `point`, in window coordinates.
    func pinch(to scale: CGFloat, aboutWindowPoint point: CGPoint) {
        guard let scrollView else { return }
        if pinchOrigin == nil {
            pinchOrigin = currentTab?.id
        }
        let magnification = min(1, max(Layout.minimumMagnification, scale))
        scrollView.setMagnification(magnification, centeredAt: scrollView.document.convert(point, from: nil))
    }

    /// The pinch ended: the table settles into the overview or back onto the page.
    func endPinch() {
        let origin = pinchOrigin
        pinchOrigin = nil
        if magnification <= Layout.overviewCommit {
            showOverview()
        } else if let origin {
            enter(origin)
        }
    }

    // MARK: - Editing

    /// Moves the current slab past its neighbor, or into the neighboring row at the place
    /// nearest its old horizontal center; off the top or bottom it opens a new group.
    func moveFocusedSlab(_ direction: TableDirection) {
        guard let tab = currentTab, let space = tab.space, let target = layout.moveTarget(of: tab.id, toward: direction) else { return }
        switch target {
        case let .row(rowID, index):
            let group = rowID == space.id ? nil : space.groups.first { $0.id == rowID }
            if tab.group?.id != group?.id {
                groupManager.moveTabToGroup(tab, group: group, in: space, skipReordering: true)
            }
            if let row = layout.rows.first(where: { $0.id == rowID }) {
                let others = row.slabs.map(\.tabID).filter { $0 != tab.id }
                let anchor = index < others.count ? others[index] : others.last
                if let anchor, let anchorTab = self.tab(for: anchor), let anchorIndex = space.tabs.firstIndex(of: anchorTab) {
                    let after = index >= others.count
                    tabManager.moveTab(tab, to: after ? anchorIndex : max(0, anchorIndex))
                }
            }
        case let .newRow(above):
            let name = "Group \(space.groups.filter { !$0.isArchive }.count + 1)"
            guard let group = try? groupManager.createGroup(in: space, name: name) else { return }
            groupManager.moveTabToGroup(tab, group: group, in: space, skipReordering: true)
            if !above, let last = space.groups.filter({ !$0.isArchive && $0.id != group.id }).map(\.position).max() {
                group.position = last + 1
            } else if above {
                group.position = (space.groups.filter { !$0.isArchive && $0.id != group.id }.map(\.position).min() ?? 0) - 1
            }
            tabManager.state.incrementListVersion()
            tabManager.scheduleSave()
        }
        reveal(tab.id)
    }

    func cycleWidth() {
        guard let tab = currentTab else { return }
        state.cycleWidth(of: tab.id)
        widthsChanged(revealing: tab.id)
    }

    func toggleFill() {
        guard let tab = currentTab else { return }
        state.toggleFill(of: tab.id)
        widthsChanged(revealing: tab.id)
    }

    func setWidth(_ width: TableWidth, of tab: Tab) {
        state.setWidth(width, of: tab.id)
        widthsChanged(revealing: tab.id)
    }

    /// Toggles a row's fold: a group collapsed to a band, or opened to its slabs.
    func toggleRowCollapsed(_ rowID: UUID) {
        guard let group = windowState.activeSpace?.groups.first(where: { $0.id == rowID }) else { return }
        groupManager.toggleGroupCollapsed(group)
    }

    private func widthsChanged(revealing tabID: UUID) {
        persistState()
        layout = TableLayout(rows: layout.rows.map { TableLayout.RowSource(id: $0.id, title: $0.title, colorString: $0.colorString, isCollapsed: $0.isCollapsed, tabIDs: $0.slabs.map(\.tabID)) }, state: state)
        scrollView?.apply(layout: layout, geometry: geometry, animated: true)
        reveal(tabID)
    }

    // MARK: - Snapshots

    /// The image a slab shows until its page paints, or while another surface holds it.
    func snapshot(for tabID: UUID) -> NSImage? {
        captures[tabID] ?? canvas.snapshots[tabID]
    }

    /// Captures the page after it has loaded, so the slab shows its contents when it is next
    /// seen as an image.
    func captureSnapshot(of tab: Tab) async {
        guard !capturing.contains(tab.id), let page = pagePool.existingPage(for: tab.activePage),
              page.url != nil else { return }
        capturing.insert(tab.id)
        defer { capturing.remove(tab.id) }
        let deadline = ContinuousClock.now + .seconds(10)
        while page.isLoading && ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
        }
        guard !page.isLoading else { return }
        await page.waitForPresentationUpdate()
        let bounds = page.contentView.bounds
        guard !Task.isCancelled, bounds.width > 0, bounds.height > 0,
              let image = try? await page.snapshot() else { return }
        store(image, for: tab.id)
    }

    /// Fills in a slab with no image from the snapshot stored on disk.
    func requestStoredSnapshot(for tab: Tab) {
        guard snapshot(for: tab.id) == nil, !capturing.contains(tab.id), tab.space?.dataStoreMode != .private else { return }
        let id = tab.id
        capturing.insert(id)
        Task(name: "Load table snapshot") { [weak self] in
            let data = await CanvasSnapshotStore.load(for: id)
            guard let self, !Task.isCancelled else { return }
            if let data, let image = NSImage(data: data), captures[id] == nil {
                store(image, for: id)
            }
            capturing.remove(id)
        }
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
