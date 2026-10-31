import AppKit
import Observation
import SwiftUI

/// One island on the window: a tab group, or the space's loose tabs, as a column of rows in
/// the tab list's order, with its place on the window. A group nested in the island's group
/// is a section of it, under a header that folds it.
struct Island: Identifiable, Equatable {
    let id: UUID
    var title: String
    var colorString: String?
    /// The group's icon: an SF Symbol name or an emoji.
    var iconName: String?
    var layout: IslandRowLayout
    var placement: IslandPlacement
    /// The loose tabs' island, named after the space.
    var isDefault: Bool

    /// The rows on the island: tabs and section headers.
    var rows: [IslandRow] {
        layout.rows
    }

    /// The tab rows shown, in order: what a step up or down moves through.
    var tabIDs: [UUID] {
        layout.tabIDs
    }

    /// Every tab of the island, its folded sections' included.
    var allTabIDs: [UUID] {
        layout.allTabIDs
    }

    var sections: [IslandSection] {
        layout.sections
    }
}

/// A dragged row drawn over the page at the pointer.
struct RowGhost: Equatable {
    let tabID: UUID
    var point: CGPoint
}

/// The island a dragged row makes when let go on empty space, drawn where it will land.
struct IslandGhost: Equatable {
    let tabID: UUID
    /// The island's full frame, header included, in the layer.
    var frame: CGRect
    /// The name the island will take.
    let title: String
    /// One row per tab: the row alone, or its selection.
    let rows: Int
    let iconsOnly: Bool
}

/// Where a dragged row would land: an island and the row it goes before, or the tab on that
/// island it joins as a second pane.
struct IslandDrop: Equatable {
    let island: UUID
    let row: Int
    var joins: UUID?
}

/// Where a row's drag stands against the browser window's edge.
enum RowDragExit {
    /// Within the window: a move between rows and islands.
    case inside
    /// Past the edge just now: these tabs go out as a system drag.
    case leaves([Tab])
    /// Already out, the system's drag until it ends.
    case handedOff
}

/// How a page replaces the current one.
nonisolated enum TravelStyle: Sendable {
    /// A neighbor in the same island: the pages slide in the direction of travel.
    case slide(TableDirection)
    /// Another island: the page shrinks toward its island and the next grows out of the other.
    case cross(TableDirection)
}

/// One page replacing another, for ``PageTravelView`` to animate.
struct PageTravel: Identifiable {
    let id = UUID()
    let outgoing: NSImage?
    let style: TravelStyle
}

/// A push against an island's edge that did not cross it, for the page view to show.
struct EdgeBump: Identifiable, Equatable {
    let id = UUID()
    let direction: TableDirection
}

/// An edge pushed against: a second push the same way, soon enough, crosses to the island there.
struct ArmedCrossing: Equatable {
    let direction: TableDirection
    let at: Date
}

/// One window's islands: every island built from the space's groups in the tab list's order,
/// the placements kept for them, the moves between pages, and the islands' own edits.
///
/// Rebuilt from the space whenever it changes. Membership, order, and titles are the tab
/// list and the group relation; only island placements and the tabs taken out to float as
/// cards are stored (``IslandState``, on the space).
@MainActor
@Observable
final class IslandController {
    enum Layout {
        /// Full-window renders kept in memory: the current page, the one it came from, and
        /// the pages one step away in each direction, loaded ahead of a step.
        static let snapshotLimit = 8
        /// A render landed this recently stands for the next one asked for by a load's end.
        static let captureCoalescing: TimeInterval = 2
        /// How long after a push against an edge a second push crosses it.
        static let crossingWindow: TimeInterval = 1.5
        /// The least space between two islands once one is let go over another.
        static let islandGap: CGFloat = 8
        /// The pointer this close to an island, on the page, shows the island's header.
        static let headerReach: CGFloat = 24
        /// How long the header stays after the pointer leaves the island.
        static let controlsGrace: Duration = .milliseconds(350)
        /// Where the first island of a space goes, normalized to the window.
        static let firstIslandOrigin = CGPoint(x: 0.1, y: 0.1)
        /// How far a new island lands from the one it came from, in window widths.
        static let newIslandOffset: Double = 0.26
        /// Where under its top edge a card taken out of an island hangs from the pointer.
        static let cardGrab: CGFloat = 14
        /// The share of the page's width at each side where a dragged row joins the page.
        static let sideZoneShare: CGFloat = 0.28
    }

    private nonisolated struct SyncKey: Equatable, Sendable {
        var spaceID: UUID?
        var tabListVersion: UInt64
        var activeTabID: UUID?
        /// The tabs a quick filter keeps, followed as the pages' sound and capture change.
        var filtered: Set<UUID>?
    }

    // MARK: - State

    private(set) var islands: [Island] = []
    private(set) var state = IslandState()
    /// The move under way, for the page view to animate.
    private(set) var travel: PageTravel?
    /// A step asked for while a move is under way: it runs when the move lands.
    @ObservationIgnored private var pendingStep: TableDirection?
    /// The last push against an edge that did not cross it.
    private(set) var bump: EdgeBump?
    /// The edge the last push leaned on: the next push the same way crosses.
    private(set) var armedCrossing: ArmedCrossing?
    /// The row being dragged, and where it would land: an island, the page's side, or, on
    /// empty space, a new island of its own (a card instead while the card key is held).
    var draggedTabID: UUID?
    var drop: IslandDrop?
    /// The side of the page a dragged row would join the current tab on, as a pane.
    var sideDrop: PanePosition?
    /// The island the dragged row makes if let go here, on empty space.
    var islandGhost: IslandGhost?
    /// The dragged row leaves as a live card instead, while ⇧ is held.
    var dropsAsCard = false
    /// The island just made by a drop: it stays where it was put while the others clear it.
    @ObservationIgnored private var placingIslandID: UUID?
    /// Whether the one-time hint on starting an island has been put away, for good: once
    /// dismissed, or once any island was made.
    private(set) var startHintDismissed: Bool
    @ObservationIgnored private let defaults: UserDefaults
    static let startHintKey = "islands.startHintDismissed"
    /// The row the keyboard has chosen while the islands have the keyboard.
    private(set) var keyboardCursorID: UUID?
    @ObservationIgnored private var keyboard: IslandKeyboardNavigator?
    /// The quick filter on the islands: only the tabs it matches keep their rows.
    private(set) var filter: IslandFilter?
    /// Rows chosen with ⇧ or ⌘, on one island, for actions on several tabs at once.
    private(set) var selectedTabIDs: Set<UUID> = []
    /// The row the pointer has rested on, whose page shows as a preview beside its island.
    var previewedTabID: UUID?
    /// How far each island's rows are scrolled, so a drop lands on the row under the pointer.
    @ObservationIgnored var scrollOffsets: [UUID: CGFloat] = [:]

    /// A point in an island's frame, moved into its rows' unscrolled coordinates.
    func rowPoint(_ local: CGPoint, in island: Island) -> CGPoint {
        CGPoint(x: local.x, y: local.y + (scrollOffsets[island.id] ?? 0))
    }
    /// The island being moved, drawn over the others.
    var draggedIslandID: UUID?
    /// Where each direction label sits while the key is held, in the window's content.
    @ObservationIgnored var directionLabelFrames: [TableDirection: CGRect] = [:]
    /// The island under the pointer, or the one the pointer just left; its header shows.
    private(set) var hoveredIslandID: UUID?
    /// The island the pointer is near on the page, within ``Layout/headerReach``; its header shows.
    private(set) var nearIslandID: UUID?
    /// The island whose header is in use (a rename, its menu), so it stays while the pointer is away.
    private(set) var heldControlsIslandID: UUID?
    /// The row being dragged, at the pointer, for the layer to draw.
    var rowGhost: RowGhost?
    @ObservationIgnored private var joinDwell = IslandJoinDwell()
    /// The row whose drag left the window as a system drag.
    @ObservationIgnored private var handoff = RowDragHandoff()
    /// The system drag's source, kept while the drag lasts.
    @ObservationIgnored var dragOutSource: AnyObject?
    @ObservationIgnored private var joinTask: Task<Void, Never>?
    /// A new island's name, open for editing in its controls as soon as they show.
    var renameRequest: UUID?
    @ObservationIgnored private var hoverClearTask: Task<Void, Never>?
    /// The island that just appeared, for its unfold.
    private(set) var emergingIslandID: UUID?
    /// The area the islands are placed in, in the layer's coordinates.
    private(set) var area: CGRect = .zero
    /// The whole layer, where cards are placed.
    private(set) var bounds: CGRect = .zero
    /// The page's area, for the moves that need it.
    @ObservationIgnored private(set) var viewportFrame: CGRect = .zero
    /// The last current tab of each island, where a crossing lands.
    @ObservationIgnored private var lastTab: [UUID: UUID] = [:]
    @ObservationIgnored private var captures: [UUID: NSImage] = [:]
    @ObservationIgnored private var capturedAt: [UUID: Date] = [:]
    /// Counts stored renders, so a view showing one is told when a newer one arrives.
    private var captureVersion = 0
    @ObservationIgnored private var captureOrder: [UUID] = []
    @ObservationIgnored private var capturing: Set<UUID> = []
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var spaceID: UUID?
    @ObservationIgnored private var activatedHere: UUID?
    /// The page view shows the page itself: set by the page view, false while a slab or a
    /// move's images stand in for it. A move from a live page renders it first.
    @ObservationIgnored var liveIsVisible = false

    @ObservationIgnored private unowned let windowState: WindowState
    @ObservationIgnored private unowned let tabManager: TabManager
    @ObservationIgnored private unowned let groupManager: TabGroupManager
    @ObservationIgnored private unowned let canvas: TabCanvasManager
    @ObservationIgnored private unowned let pagePool: WebPagePool

    init(
        windowState: WindowState, tabManager: TabManager, groupManager: TabGroupManager, canvas: TabCanvasManager, pagePool: WebPagePool,
        defaults: UserDefaults = .standard,
    ) {
        self.windowState = windowState
        self.tabManager = tabManager
        self.groupManager = groupManager
        self.canvas = canvas
        self.pagePool = pagePool
        self.defaults = defaults
        self.startHintDismissed = defaults.bool(forKey: Self.startHintKey)
    }

    // MARK: - Lifecycle

    func start() {
        rebuild()
        canvas.islandDrop = { [weak self] tab, point in self?.attach(tab, at: point) ?? false }
        let windowState = windowState
        let tabManager = tabManager
        let changes = Observations { [weak self] in
            SyncKey(
                spaceID: windowState.activeSpaceID, tabListVersion: tabManager.state.tabListVersion, activeTabID: windowState.activeTabID,
                filtered: self?.filteredTabIDs(),
            )
        }
        tasks.append(Task(name: "Follow the space's islands") { [weak self] in
            for await key in changes {
                self?.sync(key)
            }
        })
    }

    /// Rebuilds the islands from the space now, ahead of the observation that follows changes.
    func refresh() {
        rebuild()
    }

    /// Reloads placements restored by a browser undo operation.
    func reloadState() {
        state = IslandState.decode(windowState.activeSpace?.tableLayoutData)
        rebuild()
    }

    func stop() {
        cancelRowDrag()
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        canvas.islandDrop = nil
    }

    private func sync(_ key: SyncKey) {
        // A tab shown as the window's page is a row again, not a card.
        if let tabID = key.activeTabID, state.detached.contains(tabID) {
            state.detached.remove(tabID)
            persist()
        }
        rebuild()
        if let tabID = key.activeTabID, let island = island(holding: tabID) {
            lastTab[island.id] = tabID
        }
    }

    // MARK: - Reading

    var currentTab: Tab? {
        windowState.activeTab.flatMap { holds($0) ? $0 : nil }
    }

    var navigationTabID: UUID? {
        currentTab?.id
    }

    func holds(_ tab: Tab) -> Bool {
        island(holding: tab.id) != nil
    }

    func tab(for id: UUID) -> Tab? {
        tabManager.state.tab(for: id)
    }

    func island(holding tabID: UUID) -> Island? {
        islands.first { $0.allTabIDs.contains(tabID) }
    }

    /// The tabs taken out of their islands, floating as live cards.
    var detachedTabs: [Tab] {
        guard !windowState.isSpaceLocked, !windowState.showsCenteredLens, !windowState.isDetailTrayVisible else { return [] }
        return state.detached.compactMap(tab(for:)).filter { canvas.storedFloatingPlacement(for: $0)?.isDocked != true }
    }

    func island(_ id: UUID) -> Island? {
        islands.first { $0.id == id }
    }

    /// Whether the islands show now: held or latched by the reveal, or pinned.
    var isRevealed: Bool {
        canvas.floatingVisibility.isRevealed
    }

    /// The islands on screen now.
    var visibleIslands: [Island] {
        guard !windowState.isSpaceLocked, !windowState.showsCenteredLens, !windowState.isDetailTrayVisible else { return [] }
        return islands.filter { isRevealed || $0.placement.isPinned || $0.id == emergingIslandID || $0.id == heldControlsIslandID }
    }

    func geometry(for island: Island) -> IslandGeometry {
        IslandGeometry(iconsOnly: island.placement.iconsOnly)
    }

    /// The loose tabs' island the one-time hint stands beside: while the space has no island
    /// but that one, with tabs enough to pull one out, it shows, and no row is on its way.
    var startHintIsland: Island? {
        guard !startHintDismissed, filter == nil, draggedTabID == nil, islands.count == 1, let island = visibleIslands.first,
              island.isDefault, island.tabIDs.count >= 2 else { return nil }
        return island
    }

    /// Puts the hint away for good.
    func dismissStartHint() {
        guard !startHintDismissed else { return }
        startHintDismissed = true
        defaults.set(true, forKey: Self.startHintKey)
    }

    /// An island's frame in the layer: its corner where it was put, as a share of the area, held
    /// inside the area. The corner stays put as the island grows or shrinks.
    func frame(of island: Island) -> CGRect {
        if island.placement.iconsOnly, let rail = iconRailFrames[island.id] {
            let reserve = IslandGeometry.headerReserve
            return CGRect(x: rail.minX, y: rail.minY + reserve, width: rail.width, height: rail.height - reserve)
        }
        return titleFrame(of: island)
    }

    private func titleFrame(of island: Island) -> CGRect {
        if let frame = automaticArrangement?.frames[island.id] {
            return CGRect(origin: frame.origin, size: CGSize(width: geometry(for: island).width, height: frame.height))
        }
        let size = geometry(for: island).size(rows: island.rows.count, in: area.size)
        let top = area.minY + IslandGeometry.headerReserve
        let origin = CGPoint(
            x: min(max(area.minX, area.minX + island.placement.x * area.width), max(area.minX, area.maxX - size.width)),
            y: min(max(top, area.minY + island.placement.y * area.height), max(top, area.maxY - size.height)),
        )
        return CGRect(origin: origin, size: size)
    }

    /// The header and tab-list bounds in browser coordinates.
    func fullFrame(of island: Island) -> CGRect {
        let frame = frame(of: island)
        let reserve = IslandGeometry.headerReserve
        let width = island.placement.iconsOnly ? frame.width : max(frame.width, IslandGeometry.titleWidth)
        let x = min(frame.minX, max(area.minX, area.maxX - width))
        return CGRect(x: x, y: frame.minY - reserve, width: width, height: frame.height + reserve)
    }

    private var iconRailFrames: [UUID: CGRect] {
        guard !bounds.isEmpty else { return [:] }
        var occupied = obstacles + islands.filter { !$0.placement.iconsOnly }.map { island in
            let frame = titleFrame(of: island)
            return CGRect(x: frame.minX, y: frame.minY - IslandGeometry.headerReserve, width: frame.width, height: frame.height + IslandGeometry.headerReserve)
        }
        var frames: [UUID: CGRect] = [:]
        for island in islands where island.placement.iconsOnly {
            let geometry = geometry(for: island)
            let height = geometry.size(rows: island.rows.count, in: bounds.size).height + IslandGeometry.headerReserve
            let placement = island.placement.railPlacement ?? defaultRailPlacement(height: height)
            let frame = draggedIslandID == island.id ? placement.railFrame(in: bounds, height: height)
                : IconRailLayout.frame(placement: placement, height: height, in: bounds, obstacles: occupied)
            frames[island.id] = frame
            occupied.append(frame)
        }
        return frames
    }

    private func defaultRailPlacement(height: CGFloat) -> ControlIslandPlacement {
        let rail = windowState.controlIsland.railFrame
        var placement = ControlIslandPlacement()
        if !rail.isEmpty {
            placement.move(to: CGPoint(x: rail.minX, y: rail.maxY + Layout.islandGap), in: bounds, height: height)
        }
        return placement
    }

    private var automaticArrangement: IslandArrangement? {
        guard state.automaticallyArranged else { return nil }
        let rail = windowState.controlIsland.railFrame
        let x = rail.isEmpty || rail.midX > bounds.midX ? area.minX : max(area.minX, rail.maxX + Layout.islandGap)
        let y = max(area.minY, rail.minY + ControlIslandPlacement.pageBranchHeight + Layout.islandGap)
        let lane = CGRect(x: x, y: y, width: max(0, area.maxX - x), height: max(0, area.maxY - y))
        let items = islands.map { island in
            let size = geometry(for: island).size(rows: island.rows.count, in: area.size)
            return IslandArrangement.Item(id: island.id, size: size)
        }
        return IslandArrangement(items: items, area: lane)
    }

    var navigationInset: CGFloat {
        guard !visibleIslands.isEmpty, !canvas.isMomentaryNavigation else { return 0 }
        return automaticArrangement?.pageInset ?? 0
    }

    var pageArea: CGRect {
        viewportFrame.isEmpty ? bounds : viewportFrame
    }

    func arrangeAutomatically() {
        state.automaticallyArranged = true
        persist()
    }

    func useFreePlacement(keepingArrangement: Bool = false) {
        let frames = keepingArrangement ? automaticArrangement?.frames ?? [:] : [:]
        state.automaticallyArranged = false
        for island in islands {
            guard let frame = frames[island.id] else { continue }
            moveIsland(island.id, to: frame.origin)
        }
        persist()
    }

    // MARK: - An Island's Header

    /// Latched and pinned islands keep their names visible; other headers follow interaction.
    func showsHeader(of islandID: UUID) -> Bool {
        canvas.floatingVisibility.isLatched || island(islandID)?.placement.isPinned == true
            || hoveredIslandID == islandID || nearIslandID == islandID || heldControlsIslandID == islandID || draggedIslandID == islandID
    }

    /// The pointer moved over the page: the island it is near shows its header.
    func pointerMoved(_ point: CGPoint) {
        let near = visibleIslands.first { fullFrame(of: $0).insetBy(dx: -Layout.headerReach, dy: -Layout.headerReach).contains(point) }?.id
        if nearIslandID != near {
            nearIslandID = near
        }
    }

    /// The pointer entered or left an island. Leaving keeps the header for a grace.
    func setHovered(_ islandID: UUID, _ hovered: Bool) {
        hoverClearTask?.cancel()
        hoverClearTask = nil
        if hovered {
            hoveredIslandID = islandID
            return
        }
        hoverClearTask = Task(name: "Let an island's controls go") { [weak self] in
            try? await Task.sleep(for: Layout.controlsGrace)
            guard let self, !Task.isCancelled, hoveredIslandID == islandID else { return }
            hoveredIslandID = nil
        }
    }

    /// Keeps an island's header while it is in use, whatever the pointer does.
    func holdControls(_ islandID: UUID, _ held: Bool) {
        if held {
            heldControlsIslandID = islandID
        } else if heldControlsIslandID == islandID {
            heldControlsIslandID = nil
        }
    }

    /// The side of the page a row dragged to `point` would join the current tab on: the
    /// band at either side, when the row's tab can be its second pane.
    func sideZone(at point: CGPoint, dragging tabID: UUID) -> PanePosition? {
        guard let current = currentTab, canJoin(tabID, with: current.id) else { return nil }
        let page = pageArea
        guard page.contains(point) else { return nil }
        let width = page.width * Layout.sideZoneShare
        if point.x < page.minX + width {
            return .topLeft
        }
        if point.x > page.maxX - width {
            return .topRight
        }
        return nil
    }

    /// A single page can join a tab that has room for a second.
    func canJoin(_ tabID: UUID, with otherID: UUID) -> Bool {
        guard tabID != otherID, let source = tab(for: tabID), let target = tab(for: otherID) else { return false }
        return source.pages.count == 1 && !source.isMultiPage && target.pages.count < 2
    }

    /// A group's color; the loose tabs' island is gray, so it reads as the one without a group.
    func color(of island: Island) -> Color {
        island.colorString.map(Color.resolveStoredColor) ?? .secondary
    }

    /// Opens the Command Lens; a page it opens goes to the end of `islandID`. The lens opens
    /// on its own, since an anchored lens edits the current page's address instead.
    func addTab(to islandID: UUID) {
        guard let island = island(islandID) else { return }
        windowState.newTabIsland = WindowState.NewTabIsland(groupID: island.isDefault ? nil : island.id)
        windowState.openCommandLens()
    }

    /// The tab a step in `direction` reaches from the current row: the row above or below
    /// it. Left and right lead only to other islands.
    func destination(toward direction: TableDirection) -> Tab? {
        guard let current = currentTab, let island = island(holding: current.id),
              let index = island.tabIDs.firstIndex(of: current.id) else { return nil }
        let next: Int? = switch direction {
        case .up: index > 0 ? index - 1 : nil
        case .down: index + 1 < island.tabIDs.count ? index + 1 : nil
        case .left, .right: nil
        }
        return next.flatMap { tab(for: island.tabIDs[$0]) }
    }

    /// The island in `direction` from the current one, by their places on the window.
    func island(toward direction: TableDirection) -> Island? {
        guard let current = currentTab, let here = island(holding: current.id) else { return nil }
        return island(toward: direction, from: here)
    }

    /// The island in `direction` from `here`, by their places on the window.
    func island(toward direction: TableDirection, from here: Island) -> Island? {
        let origin = frame(of: here)
        let candidates = islands.filter { $0.id != here.id }.compactMap { island -> (Island, CGFloat)? in
            let frame = frame(of: island)
            let dx = frame.midX - origin.midX
            let dy = frame.midY - origin.midY
            let along: CGFloat = switch direction {
            case .left: -dx
            case .right: dx
            case .up: -dy
            case .down: dy
            }
            let across: CGFloat = switch direction {
            case .left, .right: abs(dy)
            case .up, .down: abs(dx)
            }
            guard along > 0, along >= across * 0.5 else { return nil }
            return (island, along + across)
        }
        return candidates.min { $0.1 < $1.1 }?.0
    }

    // MARK: - Building

    private func rebuild() {
        guard let space = windowState.activeSpace else {
            islands = []
            state = IslandState()
            spaceID = nil
            return
        }
        if spaceID != space.id {
            spaceID = space.id
            state = IslandState.decode(space.tableLayoutData)
            lastTab = [:]
            filter = nil
        }
        repairPanes(in: space)
        // Favorites, docked pages, and tabs floating as cards are not rows; a quick filter
        // keeps only the tabs it matches.
        let filtered = filteredTabIDs()
        let onIslands = space.mainTabs.filter {
            !$0.isFavorite && !state.detached.contains($0.id) && canvas.storedFloatingPlacement(for: $0)?.isDocked != true
                && filtered?.contains($0.id) != false
        }
        let current = windowState.activeTabID
        func members(of groupID: UUID) -> [UUID] {
            onIslands.filter { $0.group?.id == groupID }.map(\.id)
        }
        var sources: [(id: UUID, title: String, color: String?, icon: String?, layout: IslandRowLayout, isDefault: Bool)] = [
            (space.id, "Tabs", nil, nil, IslandRowLayout(ownTabIDs: onIslands.filter { $0.group == nil }.map(\.id)), true),
        ]
        let groups = space.groups.filter { !$0.isArchive }.sorted { $0.position < $1.position }
        let groupIDs = Set(groups.map(\.id))
        // A group nested in another is a section of its parent's island; one whose parent is
        // gone is an island of its own.
        for group in groups where group.parentGroupID.map({ !groupIDs.contains($0) }) ?? true {
            let sections = groups.filter { $0.parentGroupID == group.id }.compactMap { child -> IslandSection? in
                let tabs = members(of: child.id)
                guard !tabs.isEmpty else { return nil }
                return IslandSection(
                    id: child.id, title: child.name, colorString: child.colorString, iconName: child.iconName, tabIDs: tabs,
                    isCollapsed: child.isCollapsed,
                )
            }
            let layout = IslandRowLayout(ownTabIDs: members(of: group.id), sections: sections, currentTabID: current)
            sources.append((group.id, group.name, group.colorString, group.iconName, layout, false))
        }
        var changed = false
        var built: [Island] = []
        var nextOrigin = firstIslandOrigin
        // The loose tabs' island folds away while every tab is in a group.
        for source in sources where !source.layout.allTabIDs.isEmpty {
            if state.islands[source.id] == nil {
                state.islands[source.id] = IslandPlacement(x: nextOrigin.x, y: nextOrigin.y)
                changed = true
            }
            let placement = state.islands[source.id]!
            nextOrigin.x = min(0.9, placement.x + Layout.newIslandOffset)
            built.append(Island(
                id: source.id, title: source.title, colorString: source.color, iconName: source.icon, layout: source.layout,
                placement: placement, isDefault: source.isDefault,
            ))
        }
        let before = state
        // An island that is empty for a while keeps its place; only a group that is gone loses it.
        state.prune(tabs: space.mainTabs.map(\.id), islands: space.groups.map(\.id) + [space.id])
        if changed || state != before {
            persist()
        }
        if built != islands {
            islands = built
            resolveOverlaps()
        }
        if var keyboard {
            keyboard.sync(keyboardColumns)
            self.keyboard = keyboard
            update(\.keyboardCursorID, to: keyboard.cursor)
        }
        // An island exists: the hint has nothing left to teach.
        if !startHintDismissed, built.contains(where: { !$0.isDefault }) {
            dismissStartHint()
        }
    }

    private func persist() {
        guard let space = windowState.activeSpace else { return }
        space.tableLayoutData = state.encoded()
        tabManager.scheduleSave()
    }

    func updateArea(_ area: CGRect, in bounds: CGRect) {
        if self.area != area {
            self.area = area
        }
        if self.bounds != bounds {
            self.bounds = bounds
        }
    }

    func updateViewport(_ frame: CGRect) {
        viewportFrame = frame
    }

    // MARK: - Moving between pages

    /// Steps to the neighbor in `direction`; at the island's edge, crosses to the island that
    /// way, or pushes against nothing.
    /// A step in `direction`: to the neighbor row, or toward the next island. A scroll
    /// against the island's edge leans on it first and crosses on the second push; a click on
    /// the label that names the island, `atOnce`, crosses with the first.
    func step(_ direction: TableDirection, atOnce: Bool = false) {
        guard travel == nil else {
            pendingStep = direction
            return
        }
        if let tab = destination(toward: direction) {
            armedCrossing = nil
            travel(to: tab, style: .slide(direction))
        } else if let island = island(toward: direction), let tabID = lastTab[island.id] ?? island.tabIDs.first, let tab = tab(for: tabID) {
            // The island's edge resists: the first push leans on it, the second crosses.
            if atOnce || (armedCrossing.map { $0.direction == direction && Date.now.timeIntervalSince($0.at) < Layout.crossingWindow } ?? false) {
                armedCrossing = nil
                travel(to: tab, style: .cross(direction))
            } else {
                armedCrossing = ArmedCrossing(direction: direction, at: .now)
                pushEdge(direction, toast: "Once more to go to \(island.title)")
            }
        } else {
            armedCrossing = nil
            pushEdge(direction, toast: direction == .up || direction == .down ? "No tab \(direction.rawValue) from here." : "No tab to the \(direction.rawValue) from here.")
        }
    }

    /// A push that stays on this page: the slab bumps against the edge; a live page gets the word.
    private func pushEdge(_ direction: TableDirection, toast: String) {
        if canvas.showsPageSlab {
            bump = EdgeBump(direction: direction)
        } else {
            windowState.showToast(toast)
        }
    }

    /// The hold ended: no edge stays leaned on.
    func leaveEdges() {
        armedCrossing = nil
    }

    // MARK: - Selecting rows

    /// ⌘ toggles a row in the selection; ⇧ extends it from the last chosen row through this
    /// one on the same island; a plain choice is the row alone.
    func select(_ tabID: UUID, extending: Bool, toggling: Bool) {
        guard let island = island(holding: tabID) else { return }
        let onIsland = selectedTabIDs.filter { island.tabIDs.contains($0) }
        if toggling {
            selectedTabIDs = onIsland.symmetricDifference([tabID])
        } else if extending, let anchor = onIsland.compactMap({ island.tabIDs.firstIndex(of: $0) }).min(),
                  let end = island.tabIDs.firstIndex(of: tabID) {
            selectedTabIDs = Set(island.tabIDs[min(anchor, end) ... max(anchor, end)])
        } else {
            selectedTabIDs = [tabID]
        }
    }

    func clearSelection() {
        if !selectedTabIDs.isEmpty {
            selectedTabIDs = []
        }
    }

    /// The tabs an action on `tabID`'s row applies to: the selection when the row is in it,
    /// else the row alone.
    func actionTabs(for tabID: UUID) -> [Tab] {
        guard selectedTabIDs.contains(tabID), let island = island(holding: tabID) else { return tab(for: tabID).map { [$0] } ?? [] }
        return island.tabIDs.filter { selectedTabIDs.contains($0) }.compactMap(tab(for:))
    }

    // MARK: - Acting on rows

    /// Closes every other tab of `tabID`'s island.
    func closeOthers(than tabID: UUID) {
        guard let island = island(holding: tabID) else { return }
        tabManager.requestCloseTabs(island.allTabIDs.filter { $0 != tabID }.compactMap(tab(for:)))
    }

    /// Closes the rows above (`below == false`) or below `tabID` on its island.
    func close(below: Bool, of tabID: UUID) {
        guard let island = island(holding: tabID), let index = island.allTabIDs.firstIndex(of: tabID) else { return }
        let ids = below ? Array(island.allTabIDs[(index + 1)...]) : Array(island.allTabIDs[..<index])
        tabManager.requestCloseTabs(ids.compactMap(tab(for:)))
    }

    /// Archives `tabs`, which the archive keeps and the islands let go.
    func archive(_ tabs: [Tab]) {
        guard !tabs.isEmpty else { return }
        _ = tabManager.archiveManager.archiveBatch(tabs)
    }

    /// Takes `tabID` out of its group: it goes to the loose tabs' island.
    func removeFromIsland(_ tabID: UUID) {
        guard let tab = tab(for: tabID), let space = tab.space, tab.group != nil else { return }
        if let location = location(of: tabID) {
            registerLocationUndo(location, actionName: "Remove Tab from Island")
        }
        groupManager.moveTabToGroup(tab, group: nil, in: space, skipReordering: true)
        rebuild()
    }

    // MARK: - Acting on islands

    /// A group island's name, icon, and color; the loose tabs' island has none to edit.
    func appearance(of islandID: UUID) -> IslandAppearance? {
        group(islandID).map { IslandAppearance(name: $0.name, iconName: $0.iconName, colorString: $0.colorString) }
    }

    /// Takes in an edit of a group island's name, icon, and color: what changed is written,
    /// a blank name keeps the one there.
    func setAppearance(_ edit: IslandAppearance, of islandID: UUID) {
        guard let group = group(islandID), let current = appearance(of: islandID) else { return }
        let next = current.applying(edit)
        guard next != current else { return }
        if next.name != current.name {
            groupManager.renameGroup(group, to: next.name)
        }
        if next.iconName != current.iconName {
            groupManager.updateGroupIcon(group, to: next.iconName)
        }
        if next.colorString != current.colorString {
            groupManager.updateGroupColor(group, to: next.colorString)
        }
        rebuild()
    }

    private func group(_ islandID: UUID) -> TabGroup? {
        windowState.activeSpace?.groups.first { $0.id == islandID && !$0.isArchive }
    }

    func closeAll(in islandID: UUID) {
        guard let island = island(islandID) else { return }
        tabManager.requestCloseTabs(island.allTabIDs.compactMap(tab(for:)))
    }

    /// Removes the group; its tabs go to the loose tabs' island.
    func dissolve(_ islandID: UUID) {
        guard let space = windowState.activeSpace, let group = space.groups.first(where: { $0.id == islandID }) else { return }
        state.islands.removeValue(forKey: islandID)
        groupManager.deleteGroup(group, in: space, deleteContainedTabs: false)
        rebuild()
    }

    // MARK: - Quick filters

    /// Turns a quick filter on, or every row back with `nil`; switching spaces turns it off.
    func setFilter(_ filter: IslandFilter?) {
        guard self.filter != filter else { return }
        self.filter = filter
        clearSelection()
        rebuild()
    }

    /// Where the word on the filter stands, `size` big: beside the first island on screen, else
    /// at the islands' first place, right of the rail; `nil` while no filter is on or no
    /// island could show.
    func filterBadgeOrigin(size: CGSize, gap: CGFloat) -> CGPoint? {
        guard filter != nil, isRevealed || !visibleIslands.isEmpty, !windowState.isSpaceLocked, !windowState.isDetailTrayVisible,
              !windowState.showsCenteredLens else { return nil }
        if let island = visibleIslands.first {
            return IslandDropPlacement.hintOrigin(beside: fullFrame(of: island), size: size, gap: gap, in: area)
        }
        let rail = windowState.controlIsland.railFrame
        let x = rail.isEmpty || rail.midX > area.midX ? area.minX : rail.maxX + Layout.islandGap
        return CGPoint(x: min(x, max(area.minX, area.maxX - size.width)), y: area.minY)
    }

    /// The tabs of the space the filter keeps: those it matches and the current one; `nil`
    /// while no filter is on.
    func filteredTabIDs() -> Set<UUID>? {
        guard let filter, let space = windowState.activeSpace else { return nil }
        return filter.shown(space.mainTabs.map { ($0.id, facts(for: $0)) }, current: windowState.activeTabID)
    }

    /// What a filter reads of `tab`.
    func facts(for tab: Tab) -> IslandRowFacts {
        IslandRowFacts(state: TabMediaControl(tab: tab, pagePool: pagePool).state, isUnread: tab.isUnread)
    }

    // MARK: - The keyboard

    /// The islands on screen as the keyboard moves through them: each its shown tab rows.
    var keyboardColumns: [IslandKeyboardNavigator.Column] {
        visibleIslands.map { IslandKeyboardNavigator.Column(id: $0.id, tabIDs: $0.tabIDs) }
    }

    /// Whether the islands have the keyboard: they are latched open and a key has chosen a row.
    var hasKeyboard: Bool {
        keyboard != nil
    }

    /// Latches the islands open with the current tab's row chosen, for the arrows to move.
    func beginKeyboardBrowsing() {
        if !canvas.floatingVisibility.isLatched {
            canvas.toggleFloatingTabs()
        }
        keyboard = IslandKeyboardNavigator(current: currentTab?.id, columns: keyboardColumns)
        update(\.keyboardCursorID, to: keyboard?.cursor)
    }

    /// The keyboard goes back to the page: no row is chosen, and the preview it showed goes.
    func endKeyboardBrowsing() {
        if keyboard?.isPreviewing == true {
            previewedTabID = nil
        }
        keyboard = nil
        update(\.keyboardCursorID, to: nil)
    }

    /// Answers `key` while the islands are latched open. The first key other than Escape
    /// starts on the current tab's row. Returns whether the islands took the key; Escape with
    /// nothing chosen is left to whoever else answers it.
    @discardableResult
    func handleKey(_ key: IslandKey) -> Bool {
        if keyboard == nil {
            guard key != .leave else { return false }
            keyboard = IslandKeyboardNavigator(current: currentTab?.id, columns: keyboardColumns)
        }
        guard var navigator = keyboard else { return false }
        let effect = navigator.handle(
            key, columns: keyboardColumns,
            neighbor: { [self] id, direction in island(id).flatMap { island(toward: direction, from: $0)?.id } },
            title: { [self] id in tab(for: id)?.displayTitle ?? "" },
        )
        keyboard = navigator
        update(\.keyboardCursorID, to: navigator.cursor)
        switch effect {
        case .none, .moved:
            break
        case let .open(tabID):
            endKeyboardBrowsing()
            if let tab = tab(for: tabID) {
                open(tab)
            }
            canvas.dismissFloatingTabs()
        case let .close(tabID):
            if previewedTabID == tabID {
                previewedTabID = navigator.isPreviewing ? navigator.cursor : nil
            }
            if let tab = tab(for: tabID) {
                tabManager.requestCloseTab(tab)
            }
        case let .preview(tabID):
            if let tabID, let tab = tab(for: tabID) {
                requestStoredSnapshot(for: tab)
            }
            previewedTabID = tabID
        case .leave:
            endKeyboardBrowsing()
            canvas.dismissFloatingTabs()
        }
        return true
    }

    // MARK: - Sections

    /// Folds or unfolds the nested group `sectionID` in its island; the fold is kept on the
    /// group. A folded section keeps showing the current tab.
    func toggleSection(_ sectionID: UUID) {
        guard let group = group(sectionID), group.parentGroupID != nil else { return }
        groupManager.toggleGroupCollapsed(group)
        rebuild()
    }

    /// Nests island `islandID`'s group in island `parentID`'s, as a section of it. Groups nest
    /// one level deep: an island with sections of its own stays an island.
    func nest(_ islandID: UUID, in parentID: UUID) {
        guard let child = group(islandID), let parent = group(parentID), canNest(islandID, in: parentID) else { return }
        try? groupManager.nestGroup(child, in: parent)
        rebuild()
    }

    /// Whether island `islandID` can become a section of island `parentID`.
    func canNest(_ islandID: UUID, in parentID: UUID) -> Bool {
        guard islandID != parentID, let child = group(islandID), let parent = group(parentID) else { return false }
        let hasSections = windowState.activeSpace?.groups.contains { $0.parentGroupID == islandID } ?? false
        return child.parentGroupID == nil && parent.parentGroupID == nil && !hasSections
    }

    /// Takes the section `sectionID` out of its island: it becomes an island of its own.
    func unnest(_ sectionID: UUID) {
        guard let group = group(sectionID), group.parentGroupID != nil else { return }
        groupManager.unnestGroup(group)
        rebuild()
    }

    /// A row chosen directly: the page switches at once. Only a step moves, because only a
    /// step is a movement.
    func open(_ tab: Tab) {
        guard currentTab?.id != tab.id else { return }
        clearSelection()
        activatedHere = tab.id
        tabManager.setActiveTab(tab, in: windowState)
        if let island = island(holding: tab.id) {
            lastTab[island.id] = tab.id
        }
    }

    /// Makes `tab` current with `style`: the outgoing page leaves as its snapshot. A page
    /// still live is rendered first, through WebKit, while it stays on screen.
    private func travel(to tab: Tab, style: TravelStyle) {
        requestStoredSnapshot(for: tab)
        guard liveIsVisible, let current = windowState.activeTab else {
            start(PageTravel(outgoing: windowState.activeTab.flatMap { snapshot(for: $0.id) }, style: style), to: tab)
            return
        }
        Task(name: "Capture the page before a move") { [weak self] in
            guard let self else { return }
            let snapshot = await refreshSnapshot(of: current)
            guard !Task.isCancelled, windowState.activeTabID == current.id else { return }
            canvas.showsPageSlab = true
            start(PageTravel(outgoing: snapshot ?? self.snapshot(for: current.id), style: style), to: tab)
        }
    }

    private func start(_ move: PageTravel, to tab: Tab) {
        clearSelection()
        travel = move
        activatedHere = tab.id
        tabManager.setActiveTab(tab, in: windowState)
        if let island = island(holding: tab.id) {
            lastTab[island.id] = tab.id
        }
        prefetchNeighbourSnapshots()
    }

    /// The page view finished the move.
    func finishTravel(_ id: UUID) {
        guard travel?.id == id else { return }
        travel = nil
        if let next = pendingStep {
            pendingStep = nil
            step(next)
        }
    }

    // MARK: - Editing islands

    /// Moves the drag image and insertion point; a stationary pause arms combining. Off every
    /// island and the page's sides, the row's own island shows where it would land, or, with
    /// `asCard` (⇧ held), the row leaves as a card.
    func updateRowDrag(_ tabID: UUID, at point: CGPoint, asCard: Bool = false) {
        // Every write below re-evaluates the whole layer; a value that did not change is not written.
        update(\.draggedTabID, to: tabID)
        update(\.rowGhost, to: RowGhost(tabID: tabID, point: point))
        let reach = IslandGeometry.padding
        guard let target = visibleIslands.first(where: { frame(of: $0).insetBy(dx: -reach, dy: -reach).contains(point) }) else {
            update(\.drop, to: nil)
            let side = sideZone(at: point, dragging: tabID)
            update(\.sideDrop, to: side)
            update(\.dropsAsCard, to: side == nil && asCard)
            update(\.islandGhost, to: side == nil && !asCard ? ghost(for: tabID, at: point) : nil)
            updateJoinDwell(candidate: nil, point: point)
            return
        }
        update(\.sideDrop, to: nil)
        update(\.islandGhost, to: nil)
        update(\.dropsAsCard, to: false)
        let frame = frame(of: target)
        let local = rowPoint(CGPoint(x: point.x - frame.minX, y: point.y - frame.minY), in: target)
        let geometry = geometry(for: target)
        let count = target.rows.count(where: { $0 != .tab(tabID) })
        let candidate = geometry.joinedRow(at: local, count: target.rows.count).flatMap { index in
            target.rows[index].tabID.flatMap { canJoin(tabID, with: $0) ? $0 : nil }
        }
        updateJoinDwell(candidate: candidate, point: point)
        update(\.drop, to: IslandDrop(island: target.id, row: geometry.insertion(at: local, count: count), joins: joinDwell.ready()))
    }

    /// Writes `value` only when it differs from what is there: an observed property notifies
    /// its observers on every write, equal or not.
    private func update<Value: Equatable>(_ keyPath: ReferenceWritableKeyPath<IslandController, Value>, to value: Value) {
        if self[keyPath: keyPath] != value {
            self[keyPath: keyPath] = value
        }
    }

    private func updateJoinDwell(candidate: UUID?, point: CGPoint) {
        guard joinDwell.update(candidate: candidate, at: point) else { return }
        joinTask?.cancel()
        guard let candidate else { return }
        let beganAt = joinDwell.beganAt
        joinTask = Task(name: "Pause before combining tabs") { [weak self] in
            try? await Task.sleep(for: .seconds(IslandJoinDwell.delay))
            guard !Task.isCancelled, let self, draggedTabID != nil,
                  joinDwell.beganAt == beganAt, joinDwell.ready() == candidate else { return }
            drop?.joins = candidate
        }
    }

    /// The row is let go: into an island, onto the page's side, or, on empty space, as a new
    /// island where its ghost stood; as a card instead with `asCard` (⇧ held).
    func finishRowDrag(_ tabID: UUID, at point: CGPoint, asCard: Bool = false) {
        guard draggedTabID == tabID else { return }
        defer { cancelRowDrag() }
        if let drop {
            if let joins = drop.joins {
                join(tabID, with: joins)
            } else {
                moveTab(tabID, to: drop.row, in: drop.island)
            }
        } else if let sideDrop {
            joinPage(tabID, at: sideDrop)
        } else if asCard {
            detach(tabID, at: point)
        } else {
            makeIsland(from: tabID, at: point)
        }
    }

    /// Where a row's drag at `point` stands: still a move within the window, leaving it now
    /// with the tabs it carries out (the row, or its selection), or already the system's.
    func rowDragExit(_ tabID: UUID, at point: CGPoint) -> RowDragExit {
        if handoff.isHandedOff(tabID) {
            return .handedOff
        }
        let carried = actionTabs(for: tabID).filter(IslandRowDragOut.carriesAddress)
        guard handoff.leaves(tabID, at: point, bounds: bounds, carriesAddress: !carried.isEmpty) else { return .inside }
        cancelRowDrag()
        return .leaves(carried)
    }

    /// The system drag of a row ended, wherever it was let go.
    func endDragOut() {
        handoff.end()
        dragOutSource = nil
    }

    func cancelRowDrag() {
        joinTask?.cancel()
        joinTask = nil
        joinDwell = IslandJoinDwell()
        drop = nil
        sideDrop = nil
        islandGhost = nil
        dropsAsCard = false
        draggedTabID = nil
        rowGhost = nil
    }

    /// The island `tabID`'s row, or its selection, makes if let go at `point`: a row per tab,
    /// in the source island's shape, its first row under the pointer, held inside the area.
    func ghost(for tabID: UUID, at point: CGPoint) -> IslandGhost? {
        guard let source = island(holding: tabID) else { return nil }
        let members = actionTabs(for: tabID)
        guard let first = members.first else { return nil }
        let iconsOnly = source.placement.iconsOnly
        let frame = IslandDropPlacement.frame(
            at: point, rows: members.count, geometry: geometry(for: source), area: area, window: iconsOnly ? bounds.size : area.size,
        )
        return IslandGhost(tabID: tabID, frame: frame, title: islandName(for: first), rows: members.count, iconsOnly: iconsOnly)
    }

    /// Puts `tabID` before row `row` of island `islandID`, counted without the row itself, or
    /// after its last row: into the island's group, or the section that slot is in, moving
    /// it between groups when it came from another. A card dropped here becomes a row again.
    func moveTab(_ tabID: UUID, to row: Int, in islandID: UUID) {
        guard let target = island(islandID) else { return }
        moveTab(tabID, to: target.layout.insertion(at: row, moving: tabID), in: target)
    }

    /// Puts `tabID` after the last of island `islandID`'s own tabs, ahead of its sections.
    func moveTab(_ tabID: UUID, toEndOf islandID: UUID) {
        guard let target = island(islandID) else { return }
        moveTab(tabID, to: target.layout.endOfOwnTabs(moving: tabID), in: target)
    }

    private func moveTab(_ tabID: UUID, to slot: IslandInsertion, in target: Island) {
        guard let tab = tab(for: tabID), let space = tab.space else { return }
        if let location = location(of: tabID) {
            registerLocationUndo(location, actionName: "Move Tab")
        }
        let groupID = slot.section ?? (target.isDefault ? nil : target.id)
        let group = groupID.flatMap { id in space.groups.first { $0.id == id } }
        if tab.group?.id != group?.id {
            groupManager.moveTabToGroup(tab, group: group, in: space, skipReordering: true)
        }
        if state.detached.remove(tabID) != nil {
            windowState.clearFocusIfNeeded(for: tab.activePage.id)
        }
        tabManager.placeTab(tab, after: slot.after.flatMap(self.tab(for:)), before: slot.before.flatMap(self.tab(for:)))
        persist()
        rebuild()
    }

    /// Joins `tabID` to `otherID` as its second pane, beside it: one tab holding two pages.
    func join(_ tabID: UUID, with otherID: UUID) {
        guard canJoin(tabID, with: otherID), let source = tab(for: tabID), let target = tab(for: otherID) else { return }
        state.detached.remove(tabID)
        place(target.pages, at: .topLeft)
        tabManager.moveTabToLayout(source, into: target, at: .topRight)
        persist()
        rebuild()
    }

    /// Joins `tabID` to the current tab as a pane on `side` of the page.
    func joinPage(_ tabID: UUID, at side: PanePosition) {
        guard let current = currentTab, canJoin(tabID, with: current.id), let source = tab(for: tabID) else { return }
        state.detached.remove(tabID)
        place(current.pages, at: side == .topLeft ? .topRight : .topLeft)
        tabManager.moveTabToLayout(source, into: current, at: side == .topLeft ? .topLeft : .topRight)
        persist()
        rebuild()
    }

    /// Gives a tab's lone page its pane before a second joins it: a page without a position
    /// is not laid out at all.
    private func place(_ pages: [TabPage], at position: PanePosition) {
        guard let page = pages.first, pages.count == 1, let tab = page.tab else { return }
        page.position = position
        var config = tab.layoutConfiguration ?? LayoutConfiguration(panePositions: [:])
        config.panePositions[page.id] = position
        tab.layoutConfiguration = config
    }

    /// Tabs of two pages whose first page has no pane get one: left, or right when the other
    /// page took the left.
    private func repairPanes(in space: Space) {
        for tab in space.mainTabs where tab.pages.count > 1 {
            var config = tab.layoutConfiguration ?? LayoutConfiguration(panePositions: [:])
            let unplaced = tab.pages.filter { config.panePositions[$0.id] == nil }
            guard !unplaced.isEmpty else { continue }
            let taken = Set(config.panePositions.values)
            for page in unplaced {
                let position: PanePosition = taken.contains(.topLeft) ? .topRight : .topLeft
                page.position = position
                config.panePositions[page.id] = position
            }
            tab.layoutConfiguration = config
            tabManager.scheduleSave()
        }
    }

    /// A card goes back into its island, where its tab sits in the list.
    func returnToIsland(_ tabID: UUID) {
        guard state.detached.contains(tabID) else { return }
        if let location = location(of: tabID) {
            registerLocationUndo(location, actionName: "Return Tab to Island")
        }
        if let tab = tab(for: tabID) {
            windowState.clearFocusIfNeeded(for: tab.activePage.id)
        }
        state.detached.remove(tabID)
        persist()
        rebuild()
    }

    /// Takes `tabID` out of its island: it floats as a live card at `point`, pinned so it
    /// stays when the reveal key is up.
    func detach(_ tabID: UUID, at point: CGPoint) {
        guard let tab = tab(for: tabID), let space = tab.space else { return }
        if let location = location(of: tabID) {
            registerLocationUndo(location, actionName: "Float Tab")
        }
        var placement = canvas.storedFloatingPlacement(for: tab) ?? FloatingTabPlacement.initial(index: 0, count: 1, shape: .live)
        placement.shape = .live
        placement.isPinned = true
        placement.dock = nil
        // A card starts at the live shape's own size, whatever size the tab's last card had.
        placement.previewWidth = nil
        placement.previewHeight = nil
        let size = placement.frame(in: bounds).size
        placement.move(to: CGPoint(x: point.x - size.width / 2, y: point.y - Layout.cardGrab), in: bounds)
        canvas.updateFloatingPlacement(placement, for: tab)
        if windowState.activeTabID == tabID {
            let replacement = islands.flatMap(\.tabIDs).first { $0 != tabID }
            windowState.setActiveTabID(replacement, for: space.id, trackPrevious: false)
        }
        state.detached.insert(tabID)
        persist()
        rebuild()
    }

    private func location(of tabID: UUID) -> IslandTabLocation? {
        guard let tab = tab(for: tabID), let space = tab.space else { return nil }
        let ordered = space.mainTabs
        guard let index = ordered.firstIndex(where: { $0.id == tabID }) else { return nil }
        return IslandTabLocation(
            tabID: tabID, spaceID: space.id, groupID: tab.groupID,
            previousID: index > 0 ? ordered[index - 1].id : nil,
            nextID: index + 1 < ordered.count ? ordered[index + 1].id : nil,
            isDetached: state.detached.contains(tabID), placement: canvas.storedFloatingPlacement(for: tab),
            activeTabID: windowState.activeTabID,
        )
    }

    private func registerLocationUndo(_ location: IslandTabLocation, actionName: String) {
        let undoManager = tabManager.undoRedoManager.undoManager
        let windowState = windowState
        undoManager.registerUndo(withTarget: tabManager) { [weak windowState] manager in
            let space = manager.state.space(for: location.spaceID)
            let controller = windowState?.islandController
                ?? manager.layoutWindows(in: space).compactMap(\.islandController).first
                ?? manager.windowManager.activeWindowController?.islandController
            controller?.restoreLocation(location, actionName: actionName)
        }
        undoManager.setActionName(actionName)
    }

    private func restoreLocation(_ saved: IslandTabLocation, actionName: String) {
        guard let tab = tab(for: saved.tabID), let space = tab.space, space.id == saved.spaceID else { return }
        if windowState.activeSpaceID != space.id {
            tabManager.spaceManager.switchToSpaceSync(space, for: windowState)
            reloadState()
        }
        guard let inverse = location(of: tab.id) else { return }
        let group = space.groups.first { $0.id == saved.groupID }
        groupManager.moveTabToGroup(tab, group: group, in: space, skipReordering: true)
        tabManager.placeTab(tab, after: saved.previousID.flatMap(self.tab(for:)), before: saved.nextID.flatMap(self.tab(for:)))
        windowState.floatingPlacements[tab.id] = saved.placement
        if space.dataStoreMode != .private {
            tab.floatingPlacement = saved.placement
        }
        if saved.isDetached {
            state.detached.insert(tab.id)
        } else {
            state.detached.remove(tab.id)
            windowState.clearFocusIfNeeded(for: tab.activePage.id)
        }
        windowState.setActiveTabID(saved.activeTabID, for: space.id, trackPrevious: false)
        persist()
        rebuild()
        registerLocationUndo(inverse, actionName: actionName)
    }

    /// A card released at `point` over an island goes in as a row there.
    private func attach(_ tab: Tab, at point: CGPoint) -> Bool {
        guard state.detached.contains(tab.id), let target = dropTarget(at: point, reach: 0) else { return false }
        moveTab(tab.id, to: target.row, in: target.island)
        return true
    }

    // MARK: - Drops from outside

    /// The island under `point`, within `reach` of its glass, and the row a drop there goes
    /// before: the rows as scrolled, the row under the pointer.
    func dropTarget(at point: CGPoint, reach: CGFloat = IslandGeometry.padding) -> IslandDrop? {
        guard let island = visibleIslands.first(where: { frame(of: $0).insetBy(dx: -reach, dy: -reach).contains(point) }) else { return nil }
        let frame = frame(of: island)
        let local = rowPoint(CGPoint(x: point.x - frame.minX, y: point.y - frame.minY), in: island)
        return IslandDrop(island: island.id, row: geometry(for: island).insertion(at: local, count: island.rows.count))
    }

    /// Something from outside is held at `point`: the island under it shows where it would
    /// go. Returns whether an island takes it.
    @discardableResult
    func updateExternalDrop(at point: CGPoint) -> Bool {
        let target = dropTarget(at: point)
        update(\.drop, to: target)
        return target != nil
    }

    /// The drop from outside left the islands, or was let go.
    func endExternalDrop() {
        guard draggedTabID == nil else { return }
        update(\.drop, to: nil)
    }

    /// Takes in `payload` let go at `point`: tabs dragged from an island move to the row under
    /// the pointer; pages open there as new tabs, the first one shown. Returns whether an
    /// island took it.
    @discardableResult
    func performDrop(_ payload: IslandDropPayload, at point: CGPoint) -> Bool {
        defer { endExternalDrop() }
        guard !payload.isEmpty, let target = dropTarget(at: point), let island = island(target.island),
              let space = windowState.activeSpace else { return false }
        if !payload.tabIDs.isEmpty {
            let moving = payload.tabIDs.compactMap(tab(for:)).filter { $0.space?.id == space.id }
            guard !moving.isEmpty else { return false }
            var row = target.row
            for tab in moving {
                moveTab(tab.id, to: row, in: target.island)
                if let placed = self.island(target.island)?.layout.row(of: tab.id) {
                    row = placed + 1
                }
            }
            return true
        }
        let slot = island.layout.insertion(at: target.row)
        let groupID = slot.section ?? (island.isDefault ? nil : island.id)
        var after = slot.after.flatMap(tab(for:))
        let before = slot.before.flatMap(tab(for:))
        var opened: [Tab] = []
        for url in payload.urls {
            let tab = tabManager.createTab(url: url, in: space, groupID: groupID, makeActive: false, loadImmediately: false)
            tabManager.placeTab(tab, after: after, before: before)
            after = tab
            opened.append(tab)
        }
        rebuild()
        if let first = opened.first {
            first.isUnread = false
            open(first)
        }
        return !opened.isEmpty
    }

    func moveIsland(_ islandID: UUID, to origin: CGPoint) {
        if state.automaticallyArranged {
            useFreePlacement(keepingArrangement: true)
        }
        guard let index = islands.firstIndex(where: { $0.id == islandID }) else { return }
        if islands[index].placement.iconsOnly {
            let geometry = geometry(for: islands[index])
            let height = geometry.size(rows: islands[index].rows.count, in: bounds.size).height + IslandGeometry.headerReserve
            var placement = islands[index].placement.railPlacement ?? defaultRailPlacement(height: height)
            placement.move(to: CGPoint(x: origin.x, y: origin.y - IslandGeometry.headerReserve), in: bounds, height: height)
            islands[index].placement.railPlacement = placement
            state.islands[islandID] = islands[index].placement
            return
        }
        let size = frame(of: islands[index]).size
        let x = min(max(area.minX, origin.x), max(area.minX, area.maxX - size.width))
        let y = min(max(area.minY, origin.y), max(area.minY, area.maxY - size.height))
        var placement = islands[index].placement
        placement.x = (x - area.minX) / max(1, area.width)
        placement.y = (y - area.minY) / max(1, area.height)
        // One write to the islands and one to the state per frame, and none when the pointer
        // has not moved the island: each write re-evaluates every island on the layer.
        guard placement != islands[index].placement else { return }
        islands[index].placement = placement
        state.islands[islandID] = placement
    }

    /// The move is over: the island's place is kept, and the others keep clear of it.
    func endIslandMove(keeping islandID: UUID? = nil) {
        if let islandID, let index = islands.firstIndex(where: { $0.id == islandID }),
           var placement = islands[index].placement.railPlacement, islands[index].placement.iconsOnly {
            let geometry = geometry(for: islands[index])
            let height = geometry.size(rows: islands[index].rows.count, in: bounds.size).height + IslandGeometry.headerReserve
            placement = placement.snapped(in: bounds, height: height)
            islands[index].placement.railPlacement = placement
            state.islands[islandID] = islands[index].placement
        }
        resolveOverlaps(keeping: islandID)
        persist()
    }

    /// A secondary click at `point`, which a click with the reveal key down is: on a direction
    /// label it steps that way. Returns whether a label took it.
    func clickDirectionLabel(at point: CGPoint) -> Bool {
        guard canvas.isMomentaryNavigation, let direction = directionLabelFrames.first(where: { $0.value.contains(point) })?.key else { return false }
        step(direction, atOnce: true)
        return true
    }

    /// Where a first island goes: right of the rail when the rail is on the left, else the
    /// area's top-left corner.
    private var firstIslandOrigin: CGPoint {
        let rail = windowState.controlIsland.railFrame
        guard !rail.isEmpty, !area.isEmpty, rail.midX < area.midX else { return Layout.firstIslandOrigin }
        return CGPoint(x: min(0.9, (rail.maxX + Layout.islandGap - area.minX) / max(1, area.width)), y: Layout.firstIslandOrigin.y)
    }

    /// What islands keep clear of besides one another: the rail and the page card, when shown.
    private var obstacles: [CGRect] {
        let rail = windowState.controlIsland.hiddenEdge == nil ? windowState.controlIsland.railFrame : .zero
        return [rail, windowState.controlIsland.pageCardFrame].filter { !$0.isEmpty }
    }

    /// Islands keep clear of one another, shown or not, so none comes up under another, and
    /// of the rail and the page card: an island over another moves below it, or beside it when
    /// there is no room below. The island being moved, or the current tab's, stays put.
    func resolveOverlaps(keeping keptID: UUID? = nil) {
        guard draggedIslandID == nil, !area.isEmpty else { return }
        let kept = keptID ?? placingIslandID ?? currentTab.flatMap { island(holding: $0.id)?.id }
        let visible = islands.sorted { ($0.id == kept ? 0 : 1, $0.placement.y) < ($1.id == kept ? 0 : 1, $1.placement.y) }
        var frames = Dictionary(uniqueKeysWithValues: visible.map { ($0.id, fullFrame(of: $0)) })
        let gap = Layout.islandGap
        let fixed = obstacles
        // Moves `b` out from under `a`: below it, else beside it. Returns nil when nothing fits.
        func cleared(_ b: CGRect, of a: CGRect) -> CGRect? {
            var b = b
            if a.maxY + gap + b.height <= area.maxY {
                b.origin.y = a.maxY + gap
            } else if a.maxX + gap + b.width <= area.maxX {
                b.origin.x = a.maxX + gap
            } else if a.minX - gap - b.width >= area.minX {
                b.origin.x = a.minX - gap - b.width
            } else {
                return nil
            }
            return b
        }
        for _ in 0 ..< 4 {
            var moved = false
            for (i, upper) in visible.enumerated() {
                for obstacle in fixed {
                    guard let b = frames[upper.id], b.intersects(obstacle) else { continue }
                    // Beside the rail first: an island under the rail is wanted to its right.
                    var next = b
                    if obstacle.maxX + gap + b.width <= area.maxX {
                        next.origin.x = obstacle.maxX + gap
                    } else if let below = cleared(b, of: obstacle) {
                        next = below
                    } else {
                        continue
                    }
                    frames[upper.id] = next
                    moved = true
                }
                for lower in visible[(i + 1)...] {
                    guard let a = frames[upper.id], let b = frames[lower.id], a.intersects(b), let next = cleared(b, of: a) else { continue }
                    frames[lower.id] = next
                    moved = true
                }
            }
            if !moved {
                break
            }
        }
        for island in visible {
            guard !island.placement.iconsOnly, let frame = frames[island.id], frame != fullFrame(of: island),
                  let index = islands.firstIndex(where: { $0.id == island.id }) else { continue }
            islands[index].placement.x = (frame.minX - area.minX) / max(1, area.width)
            islands[index].placement.y = (frame.minY + IslandGeometry.headerReserve - area.minY) / max(1, area.height)
            state.islands[island.id] = islands[index].placement
        }
    }

    /// Renames a group's island; the space's own island carries the space's name.
    func rename(_ islandID: UUID, to name: String) {
        guard var appearance = appearance(of: islandID) else { return }
        appearance.name = name
        setAppearance(appearance, of: islandID)
    }

    func togglePin(_ islandID: UUID) {
        guard let index = islands.firstIndex(where: { $0.id == islandID }) else { return }
        islands[index].placement.isPinned.toggle()
        state.islands[islandID] = islands[index].placement
        persist()
    }

    func toggleIconsOnly(_ islandID: UUID) {
        guard let index = islands.firstIndex(where: { $0.id == islandID }) else { return }
        setIconsOnly(!islands[index].placement.iconsOnly, for: islandID)
    }

    func setIconsOnly(_ compact: Bool, for islandID: UUID) {
        guard let index = islands.firstIndex(where: { $0.id == islandID }) else { return }
        islands[index].placement.iconsOnly = compact
        if compact, islands[index].placement.railPlacement == nil {
            let geometry = geometry(for: islands[index])
            let height = geometry.size(rows: islands[index].rows.count, in: bounds.size).height + IslandGeometry.headerReserve
            islands[index].placement.railPlacement = defaultRailPlacement(height: height)
        }
        state.islands[islandID] = islands[index].placement
        persist()
    }

    /// The first place beside `source` where an island of `rows` rows would cover no other
    /// island: to its right, then below, then left, stepping outward.
    private func freePlacement(near source: Island, rows: Int, iconsOnly: Bool) -> IslandPlacement {
        let size = IslandGeometry(iconsOnly: iconsOnly).size(rows: rows, in: area.size)
        let sourceFrame = frame(of: source)
        let others = islands.filter { $0.id != source.id }.map(frame(of:)) + [sourceFrame]
        let gap = IslandGeometry.rowHeight
        var candidates: [CGPoint] = []
        for step in 0 ..< 6 {
            let shift = CGFloat(step) * (size.height + gap)
            candidates.append(CGPoint(x: sourceFrame.maxX + gap, y: sourceFrame.minY + shift))
            candidates.append(CGPoint(x: sourceFrame.minX, y: sourceFrame.maxY + gap + shift))
            candidates.append(CGPoint(x: sourceFrame.minX - gap - size.width, y: sourceFrame.minY + shift))
        }
        let chosen = candidates.first { origin in
            let frame = CGRect(origin: origin, size: size)
            return area.contains(frame) && !others.contains { $0.intersects(frame) }
        } ?? CGPoint(x: sourceFrame.maxX + gap, y: sourceFrame.minY)
        return IslandPlacement(
            x: min(1, max(0, (chosen.x - area.minX) / max(1, area.width))),
            y: min(1, max(0, (chosen.y - area.minY) / max(1, area.height))),
            isPinned: false,
            iconsOnly: iconsOnly,
        )
    }

    /// Makes a new island from `tabID`: a new group beside the source island, unfolding.
    func makeIsland(from tabID: UUID) {
        makeIsland(from: actionTabs(for: tabID).map(\.id))
    }

    /// Makes a new island from `tabID`'s row, or its selection, where a drag let it go: it
    /// lands where its ghost stood at `point`.
    func makeIsland(from tabID: UUID, at point: CGPoint) {
        guard let ghost = ghost(for: tabID, at: point) else { return }
        makeIsland(from: actionTabs(for: tabID).map(\.id), frame: ghost.frame)
    }

    /// The name a new island takes from its first tab: the page's domain, else its title.
    func islandName(for tab: Tab) -> String {
        tab.activePage.url.safeDisplayDomain.isEmpty ? tab.displayTitle : tab.activePage.url.safeDisplayDomain
    }

    /// Makes a new island from `tabIDs`, in their order: at `frame` (header included) when a
    /// drop chose one, else beside the island the first came from.
    func makeIsland(from tabIDs: [UUID], frame: CGRect? = nil) {
        let members = tabIDs.compactMap(tab(for:))
        guard let first = members.first, let space = first.space, let source = island(holding: first.id) else { return }
        guard let group = try? groupManager.createGroup(in: space, name: islandName(for: first)) else { return }
        // The id is read once: the group may be gone again (ungrouped, undone) before the unfold ends,
        // and a deleted model's fields are not to be read.
        let islandID = group.id
        let iconsOnly = source.placement.iconsOnly
        if let frame {
            var placement = IslandDropPlacement.placement(for: frame, in: area)
            placement.iconsOnly = iconsOnly
            if iconsOnly {
                var rail = ControlIslandPlacement()
                rail.move(to: frame.origin, in: bounds, height: frame.height)
                placement.railPlacement = rail
            }
            state.islands[islandID] = placement
        } else {
            state.islands[islandID] = freePlacement(near: source, rows: members.count, iconsOnly: iconsOnly)
        }
        for member in members {
            groupManager.moveTabToGroup(member, group: group, in: space, skipReordering: true)
        }
        clearSelection()
        emergingIslandID = islandID
        placingIslandID = frame == nil ? nil : islandID
        rebuild()
        placingIslandID = nil
        holdControls(islandID, true)
        renameRequest = islandID
        Task(name: "Finish an island's unfold") { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            if self?.emergingIslandID == islandID {
                self?.emergingIslandID = nil
            }
        }
    }

    // MARK: - Snapshots

    func snapshot(for tabID: UUID) -> NSImage? {
        _ = captureVersion
        return captures[tabID]
    }

    /// Renders the tab through WebKit, which draws each page alone and nothing over it, and
    /// keeps the image in memory and on disk. The tab stays on screen while it renders. A tab
    /// of several panes is one image: each pane's render at the pane's place in the window.
    @discardableResult
    func refreshSnapshot(of tab: Tab, force: Bool = true) async -> NSImage? {
        if !force, let at = capturedAt[tab.id], Date.now.timeIntervalSince(at) < Layout.captureCoalescing {
            return captures[tab.id]
        }
        let pages = tab.pages.compactMap { pagePool.existingPage(for: $0) }.filter { $0.contentView.bounds.width > 0 }
        guard !pages.isEmpty else { return nil }
        let image: NSImage? = if pages.count == 1 {
            try? await pages[0].snapshot()
        } else {
            await Self.composite(pages)
        }
        guard let image, !Task.isCancelled, tab.id == windowState.activeTabID else { return nil }
        store(image, for: tab.id)
        if tab.space?.dataStoreMode != .private, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let id = tab.id
            Task(name: "Keep a page's image", priority: .utility) { await CanvasSnapshotStore.save(image: cgImage, for: id) }
        }
        return image
    }

    /// The panes' renders drawn into one image of the window's content, each where its view
    /// is, at the window's scale.
    private static func composite(_ pages: [WebPage]) async -> NSImage? {
        guard let window = pages.first?.contentView.window, let content = window.contentView else { return nil }
        var renders: [(CGRect, NSImage)] = []
        for page in pages {
            if let render = try? await page.snapshot() {
                renders.append((page.contentView.convert(page.contentView.bounds, to: content), render))
            }
        }
        guard !renders.isEmpty else { return nil }
        let size = content.bounds.size
        let scale = window.backingScaleFactor
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0,
        ) else { return nil }
        bitmap.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        NSColor.windowBackgroundColor.setFill()
        CGRect(origin: .zero, size: size).fill()
        for (frame, render) in renders {
            // The view's rect in the content view is bottom-up, as the bitmap is.
            render.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1)
        }
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: size)
        image.addRepresentation(bitmap)
        return image
    }

    func requestStoredSnapshot(for tab: Tab) {
        guard snapshot(for: tab.id) == nil, !capturing.contains(tab.id), tab.space?.dataStoreMode != .private else { return }
        let id = tab.id
        capturing.insert(id)
        Task(name: "Load island snapshot") { [weak self] in
            let decoded = await CanvasSnapshotStore.loadImage(for: id)
            guard let self, !Task.isCancelled else { return }
            if let decoded, captures[id] == nil {
                store(NSImage(cgImage: decoded, size: .zero), for: id)
            }
            capturing.remove(id)
        }
    }

    /// Loads the stored images of the pages one step away in each direction, so a step shows
    /// the page's picture from its first frame rather than a placeholder that fills in later.
    func prefetchNeighbourSnapshots() {
        for direction in TableDirection.allCases {
            if let tab = destination(toward: direction) {
                requestStoredSnapshot(for: tab)
            } else if let island = island(toward: direction), let tabID = lastTab[island.id] ?? island.tabIDs.first, let tab = tab(for: tabID) {
                requestStoredSnapshot(for: tab)
            }
        }
    }

    private func store(_ image: NSImage, for tabID: UUID) {
        captures[tabID] = image
        capturedAt[tabID] = .now
        captureVersion += 1
        captureOrder.removeAll { $0 == tabID }
        captureOrder.append(tabID)
        while captureOrder.count > Layout.snapshotLimit {
            captures.removeValue(forKey: captureOrder.removeFirst())
        }
    }
}
