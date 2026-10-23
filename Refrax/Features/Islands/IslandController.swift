import AppKit
import Observation
import SwiftUI

/// One island on the window: a tab group, or the space's loose tabs, as a column of rows in
/// the tab list's order, with its place on the window.
struct Island: Identifiable, Equatable {
    let id: UUID
    var title: String
    var colorString: String?
    var tabIDs: [UUID]
    var placement: IslandPlacement
    /// The loose tabs' island, named after the space.
    var isDefault: Bool
}

/// Where a dragged row would land: an island and the row it goes before, or the tab on that
/// island it joins as a second pane.
struct IslandDrop: Equatable {
    let island: UUID
    let row: Int
    var joins: UUID?
}

/// How a page replaces the current one.
nonisolated enum TravelStyle: Sendable {
    /// A neighbor in the same island: the pages slide in the direction of travel.
    case slide(TableDirection)
    /// Another island: the page shrinks toward its island and the next grows out of the other.
    case cross(TableDirection)
    /// A chip chosen directly: a short fade.
    case jump
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
        static let snapshotLimit = 16
        /// How long after a push against an edge a second push crosses it.
        static let crossingWindow: TimeInterval = 1.5
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
    /// The row being dragged, and where it would land; nowhere means it leaves as a card.
    var draggedTabID: UUID?
    var drop: IslandDrop?
    /// The side of the page a dragged row would join the current tab on, as a pane.
    var sideDrop: PanePosition?
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

    init(windowState: WindowState, tabManager: TabManager, groupManager: TabGroupManager, canvas: TabCanvasManager, pagePool: WebPagePool) {
        self.windowState = windowState
        self.tabManager = tabManager
        self.groupManager = groupManager
        self.canvas = canvas
        self.pagePool = pagePool
    }

    // MARK: - Lifecycle

    func start() {
        rebuild()
        canvas.islandDrop = { [weak self] tab, point in self?.attach(tab, at: point) ?? false }
        let windowState = windowState
        let tabManager = tabManager
        let changes = Observations {
            SyncKey(spaceID: windowState.activeSpaceID, tabListVersion: tabManager.state.tabListVersion, activeTabID: windowState.activeTabID)
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

    func stop() {
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
        islands.first { $0.tabIDs.contains(tabID) }
    }

    /// The tabs taken out of their islands, floating as live cards.
    var detachedTabs: [Tab] {
        guard !windowState.isSpaceLocked, !windowState.showsCommandLens else { return [] }
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
        guard !windowState.isSpaceLocked, !windowState.showsCommandLens else { return [] }
        return islands.filter { isRevealed || $0.placement.isPinned || $0.id == emergingIslandID }
    }

    func geometry(for island: Island) -> IslandGeometry {
        IslandGeometry(iconsOnly: island.placement.iconsOnly)
    }

    /// An island's frame in the layer: its corner where it was put, as a share of the area, held
    /// inside the area. The corner stays put as the island grows or shrinks.
    func frame(of island: Island) -> CGRect {
        let size = geometry(for: island).size(rows: island.tabIDs.count, in: area.size)
        let origin = CGPoint(
            x: min(max(area.minX, area.minX + island.placement.x * area.width), max(area.minX, area.maxX - size.width)),
            y: min(max(area.minY, area.minY + island.placement.y * area.height), max(area.minY, area.maxY - size.height)),
        )
        return CGRect(origin: origin, size: size)
    }

    /// Where the islands take the pointer: every visible island and every card on screen.
    func hitRegions(in bounds: CGRect) -> [CGRect] {
        visibleIslands.map(frame(of:))
            + detachedTabs.filter { $0.id != windowState.activeTabID }.map { canvas.floatingHitFrame(for: $0, in: bounds) }
    }

    /// The side of the page a row dragged to `point` would join the current tab on: the
    /// band at either side, when the row's tab can be its second pane.
    func sideZone(at point: CGPoint, dragging tabID: UUID) -> PanePosition? {
        guard let current = currentTab, canJoin(tabID, with: current.id) else { return nil }
        let width = bounds.width * Layout.sideZoneShare
        if point.x < bounds.minX + width {
            return .topLeft
        }
        if point.x > bounds.maxX - width {
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

    /// Opens the lens for a new tab that will go to the end of `islandID`.
    func addTab(to islandID: UUID) {
        guard let island = island(islandID) else { return }
        windowState.newTabIsland = WindowState.NewTabIsland(groupID: island.isDefault ? nil : island.id)
        windowState.openCommandLens(prefill: "", anchor: frame(of: island))
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
        }
        repairPanes(in: space)
        // Favorites, docked pages, and tabs floating as cards are not rows.
        let onIslands = space.mainTabs.filter {
            !$0.isFavorite && !state.detached.contains($0.id) && canvas.storedFloatingPlacement(for: $0)?.isDocked != true
        }
        var sources: [(id: UUID, title: String, color: String?, members: [UUID], isDefault: Bool)] = [
            (space.id, "Tabs", nil, onIslands.filter { $0.group == nil }.map(\.id), true),
        ]
        for group in space.groups.filter({ !$0.isArchive }).sorted(by: { $0.position < $1.position }) {
            let members = onIslands.filter { $0.group?.id == group.id }.map(\.id)
            sources.append((group.id, group.name, group.colorString, members, false))
        }
        var changed = false
        var built: [Island] = []
        var nextOrigin = Layout.firstIslandOrigin
        // The loose tabs' island folds away while every tab is in a group.
        for source in sources where !source.members.isEmpty {
            if state.islands[source.id] == nil {
                state.islands[source.id] = IslandPlacement(x: nextOrigin.x, y: nextOrigin.y)
                changed = true
            }
            let placement = state.islands[source.id]!
            nextOrigin.x = min(0.9, placement.x + Layout.newIslandOffset)
            built.append(Island(id: source.id, title: source.title, colorString: source.color, tabIDs: source.members, placement: placement, isDefault: source.isDefault))
        }
        let before = state
        // An island that is empty for a while keeps its place; only a group that is gone loses it.
        state.prune(tabs: space.mainTabs.map(\.id), islands: space.groups.map(\.id) + [space.id])
        if changed || state != before {
            persist()
        }
        if built != islands {
            islands = built
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
    func step(_ direction: TableDirection) {
        guard travel == nil else {
            pendingStep = direction
            return
        }
        if let tab = destination(toward: direction) {
            armedCrossing = nil
            travel(to: tab, style: .slide(direction))
        } else if let island = island(toward: direction), let tabID = lastTab[island.id] ?? island.tabIDs.first, let tab = tab(for: tabID) {
            // The island's edge resists: the first push leans on it, the second crosses.
            if let armed = armedCrossing, armed.direction == direction, Date.now.timeIntervalSince(armed.at) < Layout.crossingWindow {
                armedCrossing = nil
                travel(to: tab, style: .cross(direction))
            } else {
                armedCrossing = ArmedCrossing(direction: direction, at: .now)
                pushEdge(direction, toast: "Once more to go to \(island.title).")
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
        tabManager.requestCloseTabs(island.tabIDs.filter { $0 != tabID }.compactMap(tab(for:)))
    }

    /// Closes the rows above (`below == false`) or below `tabID` on its island.
    func close(below: Bool, of tabID: UUID) {
        guard let island = island(holding: tabID), let index = island.tabIDs.firstIndex(of: tabID) else { return }
        let ids = below ? Array(island.tabIDs[(index + 1)...]) : Array(island.tabIDs[..<index])
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
        groupManager.moveTabToGroup(tab, group: nil, in: space, skipReordering: true)
        rebuild()
    }

    // MARK: - Acting on islands

    func setColor(_ color: GroupColor, of islandID: UUID) {
        guard let group = windowState.activeSpace?.groups.first(where: { $0.id == islandID }) else { return }
        groupManager.updateGroupColor(group, to: color.rawValue)
        rebuild()
    }

    func closeAll(in islandID: UUID) {
        guard let island = island(islandID) else { return }
        tabManager.requestCloseTabs(island.tabIDs.compactMap(tab(for:)))
    }

    /// Removes the group; its tabs go to the loose tabs' island.
    func dissolve(_ islandID: UUID) {
        guard let space = windowState.activeSpace, let group = space.groups.first(where: { $0.id == islandID }) else { return }
        state.islands.removeValue(forKey: islandID)
        groupManager.deleteGroup(group, in: space, deleteContainedTabs: false)
        rebuild()
    }

    /// Opens `tab` from its chip: a slide when it is a neighbor, a crossing from another
    /// island, a fade otherwise.
    func open(_ tab: Tab) {
        guard let current = currentTab else {
            tabManager.setActiveTab(tab, in: windowState)
            return
        }
        guard current.id != tab.id else { return }
        let here = island(holding: current.id)
        let there = island(holding: tab.id)
        if let here, let there, here.id != there.id {
            let direction: TableDirection = frame(of: there).midX >= frame(of: here).midX ? .right : .left
            travel(to: tab, style: .cross(direction))
        } else if let here, let from = here.tabIDs.firstIndex(of: current.id), let to = here.tabIDs.firstIndex(of: tab.id) {
            travel(to: tab, style: .slide(to > from ? .down : .up))
        } else {
            travel(to: tab, style: .jump)
        }
    }

    /// Makes `tab` current with `style`: the outgoing page leaves as its snapshot. A page
    /// still live is rendered first, through WebKit, while it stays on screen.
    private func travel(to tab: Tab, style: TravelStyle) {
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

    /// Puts `tabID` before row `row` of island `islandID`, or after its last row, moving it
    /// between groups when the island is another one. A card dropped here becomes a row again.
    func moveTab(_ tabID: UUID, to row: Int, in islandID: UUID) {
        guard let tab = tab(for: tabID), let space = tab.space, let target = island(islandID) else { return }
        let group = target.isDefault ? nil : space.groups.first { $0.id == islandID }
        if tab.group?.id != group?.id {
            groupManager.moveTabToGroup(tab, group: group, in: space, skipReordering: true)
        }
        state.detached.remove(tabID)
        let rows = target.tabIDs.filter { $0 != tabID }.compactMap(self.tab(for:))
        let at = min(row, rows.count)
        tabManager.placeTab(tab, after: at > 0 ? rows[at - 1] : nil, before: at < rows.count ? rows[at] : nil)
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
        state.detached.remove(tabID)
        persist()
        rebuild()
    }

    /// Takes `tabID` out of its island: it floats as a live card at `point`, pinned so it
    /// stays when the reveal key is up.
    func detach(_ tabID: UUID, at point: CGPoint) {
        guard let tab = tab(for: tabID) else { return }
        var placement = canvas.storedFloatingPlacement(for: tab) ?? FloatingTabPlacement.initial(index: 0, count: 1, shape: .live)
        placement.shape = .live
        placement.isPinned = true
        placement.dock = nil
        let size = placement.frame(in: bounds).size
        placement.move(to: CGPoint(x: point.x - size.width / 2, y: point.y - Layout.cardGrab), in: bounds)
        canvas.updateFloatingPlacement(placement, for: tab)
        state.detached.insert(tabID)
        persist()
        rebuild()
    }

    /// A card released at `point` over an island goes in as a row there.
    private func attach(_ tab: Tab, at point: CGPoint) -> Bool {
        guard state.detached.contains(tab.id), let island = visibleIslands.first(where: { frame(of: $0).contains(point) }) else { return false }
        let local = rowPoint(CGPoint(x: point.x - frame(of: island).minX, y: point.y - frame(of: island).minY), in: island)
        let geometry = geometry(for: island)
        if let hit = geometry.joinedRow(at: local, count: island.tabIDs.count), canJoin(tab.id, with: island.tabIDs[hit]) {
            join(tab.id, with: island.tabIDs[hit])
        } else {
            moveTab(tab.id, to: geometry.insertion(at: local, count: island.tabIDs.count), in: island.id)
        }
        return true
    }

    func moveIsland(_ islandID: UUID, to origin: CGPoint) {
        guard let index = islands.firstIndex(where: { $0.id == islandID }) else { return }
        let size = frame(of: islands[index]).size
        let x = min(max(area.minX, origin.x), max(area.minX, area.maxX - size.width))
        let y = min(max(area.minY, origin.y), max(area.minY, area.maxY - size.height))
        islands[index].placement.x = (x - area.minX) / max(1, area.width)
        islands[index].placement.y = (y - area.minY) / max(1, area.height)
        state.islands[islandID] = islands[index].placement
        persist()
    }

    /// Renames a group's island; the space's own island carries the space's name.
    func rename(_ islandID: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let group = windowState.activeSpace?.groups.first(where: { $0.id == islandID }) else { return }
        groupManager.renameGroup(group, to: trimmed)
        rebuild()
    }

    func togglePin(_ islandID: UUID) {
        guard let index = islands.firstIndex(where: { $0.id == islandID }) else { return }
        islands[index].placement.isPinned.toggle()
        state.islands[islandID] = islands[index].placement
        persist()
    }

    func toggleIconsOnly(_ islandID: UUID) {
        guard let index = islands.firstIndex(where: { $0.id == islandID }) else { return }
        islands[index].placement.iconsOnly.toggle()
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

    /// Makes a new island from `tabIDs`, in their order, beside the island the first came from.
    func makeIsland(from tabIDs: [UUID]) {
        let members = tabIDs.compactMap(tab(for:))
        guard let first = members.first, let space = first.space, let source = island(holding: first.id) else { return }
        let name = "Island \(space.groups.filter { !$0.isArchive }.count + 1)"
        guard let group = try? groupManager.createGroup(in: space, name: name) else { return }
        state.islands[group.id] = freePlacement(near: source, rows: members.count, iconsOnly: source.placement.iconsOnly)
        for member in members {
            groupManager.moveTabToGroup(member, group: group, in: space, skipReordering: true)
        }
        clearSelection()
        emergingIslandID = group.id
        rebuild()
        Task(name: "Finish an island's unfold") { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            if self?.emergingIslandID == group.id {
                self?.emergingIslandID = nil
            }
        }
    }

    // MARK: - Snapshots

    func snapshot(for tabID: UUID) -> NSImage? {
        _ = captureVersion
        return captures[tabID] ?? canvas.snapshots[tabID]
    }

    /// Renders the tab through WebKit, which draws each page alone and nothing over it, and
    /// keeps the image in memory and on disk. The tab stays on screen while it renders. A tab
    /// of several panes is one image: each pane's render at the pane's place in the window.
    @discardableResult
    func refreshSnapshot(of tab: Tab) async -> NSImage? {
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
        captureVersion += 1
        captureOrder.removeAll { $0 == tabID }
        captureOrder.append(tabID)
        while captureOrder.count > Layout.snapshotLimit {
            captures.removeValue(forKey: captureOrder.removeFirst())
        }
    }
}
