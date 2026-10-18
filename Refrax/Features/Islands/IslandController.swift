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
        guard !windowState.isSpaceLocked, !windowState.showsCommandLens, !canvas.isActive else { return [] }
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
        guard !windowState.isSpaceLocked, !windowState.showsCommandLens, !canvas.isActive else { return [] }
        return islands.filter { isRevealed || $0.placement.isPinned || $0.id == emergingIslandID }
    }

    func geometry(for island: Island) -> IslandGeometry {
        IslandGeometry(iconsOnly: island.placement.iconsOnly)
    }

    /// An island's frame in the layer, held inside the area.
    func frame(of island: Island) -> CGRect {
        let size = geometry(for: island).size(rows: island.tabIDs.count, in: area.size)
        let origin = CGPoint(
            x: area.minX + island.placement.x * max(0, area.width - size.width),
            y: area.minY + island.placement.y * max(0, area.height - size.height),
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
        if point.x < bounds.minX + width { return .topLeft }
        if point.x > bounds.maxX - width { return .topRight }
        return nil
    }

    /// A single page can join a tab that has room for a second.
    func canJoin(_ tabID: UUID, with otherID: UUID) -> Bool {
        guard tabID != otherID, let source = tab(for: tabID), let target = tab(for: otherID) else { return false }
        return source.pages.count == 1 && !source.isMultiPage && target.pages.count < 2
    }

    func color(of island: Island) -> Color {
        island.colorString.map(Color.resolveStoredColor) ?? .appAccentColor
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
        // Favorites, docked pages, and tabs floating as cards are not rows.
        let onIslands = space.mainTabs.filter {
            !$0.isFavorite && !state.detached.contains($0.id) && canvas.storedFloatingPlacement(for: $0)?.isDocked != true
        }
        var sources: [(id: UUID, title: String, color: String?, members: [UUID], isDefault: Bool)] = [
            (space.id, space.name, nil, onIslands.filter { $0.group == nil }.map(\.id), true),
        ]
        for group in space.groups.filter({ !$0.isArchive }).sorted(by: { $0.position < $1.position }) {
            let members = onIslands.filter { $0.group?.id == group.id }.map(\.id)
            sources.append((group.id, group.name, group.colorString, members, false))
        }
        var changed = false
        var built: [Island] = []
        var nextOrigin = Layout.firstIslandOrigin
        for source in sources where !source.members.isEmpty || source.isDefault {
            if state.islands[source.id] == nil {
                state.islands[source.id] = IslandPlacement(x: nextOrigin.x, y: nextOrigin.y)
                changed = true
            }
            let placement = state.islands[source.id]!
            nextOrigin.x = min(0.9, placement.x + Layout.newIslandOffset)
            built.append(Island(id: source.id, title: source.title, colorString: source.color, tabIDs: source.members, placement: placement, isDefault: source.isDefault))
        }
        let before = state
        state.prune(tabs: space.mainTabs.map(\.id), islands: built.map(\.id))
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

    /// Opens `tab` from its chip: a slide when it is a neighbor, a crossing from another
    /// island, a fade otherwise.
    func open(_ tab: Tab) {
        guard let current = currentTab else {
            tabManager.setActiveTab(tab, in: windowState, displacingPrevious: false)
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
        travel = move
        activatedHere = tab.id
        tabManager.setActiveTab(tab, in: windowState, displacingPrevious: false)
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
        tabManager.moveTabToLayout(source, into: target, at: .topRight)
        persist()
        rebuild()
    }

    /// Joins `tabID` to the current tab as a pane on `side` of the page.
    func joinPage(_ tabID: UUID, at side: PanePosition) {
        guard let current = currentTab, canJoin(tabID, with: current.id), let source = tab(for: tabID) else { return }
        let existing = current.pages
        state.detached.remove(tabID)
        guard tabManager.moveTabToLayout(source, into: current, at: side == .topLeft ? .topLeft : .topRight) != nil else { return }
        if side == .topLeft, let page = existing.first {
            page.position = .topRight
            current.layoutConfiguration?.panePositions[page.id] = .topRight
            tabManager.scheduleSave()
        }
        persist()
        rebuild()
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
        let local = CGPoint(x: point.x - frame(of: island).minX, y: point.y - frame(of: island).minY)
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
        let x = (origin.x - area.minX) / max(1, area.width - size.width)
        let y = (origin.y - area.minY) / max(1, area.height - size.height)
        islands[index].placement.x = min(1, max(0, x))
        islands[index].placement.y = min(1, max(0, y))
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
            x: min(1, max(0, (chosen.x - area.minX) / max(1, area.width - size.width))),
            y: min(1, max(0, (chosen.y - area.minY) / max(1, area.height - size.height))),
            isPinned: false,
            iconsOnly: iconsOnly,
        )
    }

    /// Makes a new island from `tabID`: a new group beside the source island, unfolding.
    func makeIsland(from tabID: UUID) {
        guard let tab = tab(for: tabID), let space = tab.space, let source = island(holding: tabID) else { return }
        let name = "Island \(space.groups.filter { !$0.isArchive }.count + 1)"
        guard let group = try? groupManager.createGroup(in: space, name: name) else { return }
        state.islands[group.id] = freePlacement(near: source, rows: 1, iconsOnly: source.placement.iconsOnly)
        groupManager.moveTabToGroup(tab, group: group, in: space, skipReordering: true)
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
        captures[tabID] ?? canvas.snapshots[tabID]
    }

    /// Renders the page through WebKit, which draws the page alone and nothing over it, and
    /// keeps the image in memory and on disk. The page stays on screen while it renders.
    @discardableResult
    func refreshSnapshot(of tab: Tab) async -> NSImage? {
        guard let page = pagePool.existingPage(for: tab.activePage), page.contentView.bounds.width > 0,
              let image = try? await page.snapshot(), !Task.isCancelled, tab.id == windowState.activeTabID else { return nil }
        store(image, for: tab.id)
        if tab.space?.dataStoreMode != .private, let data = image.tiffRepresentation {
            let id = tab.id
            Task(name: "Keep a page's image", priority: .utility) { await CanvasSnapshotStore.save(tiff: data, for: id) }
        }
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
        captureOrder.removeAll { $0 == tabID }
        captureOrder.append(tabID)
        while captureOrder.count > Layout.snapshotLimit {
            captures.removeValue(forKey: captureOrder.removeFirst())
        }
    }
}
