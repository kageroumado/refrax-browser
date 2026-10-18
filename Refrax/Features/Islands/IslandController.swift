import AppKit
import Observation
import SwiftUI

/// One island on the window: a tab group, or the space's loose tabs, with its chips on a grid
/// and its place on the window.
struct Island: Identifiable, Equatable {
    let id: UUID
    var title: String
    var colorString: String?
    var layout: IslandLayout
    var placement: IslandPlacement
    /// The loose tabs' island, named after the space.
    var isDefault: Bool
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

/// A beam from the page card to a chip, in the islands layer's coordinates.
struct IslandBeam: Identifiable, Equatable {
    let id = UUID()
    let from: CGRect
    let to: CGRect
    let color: Color.Components
}

/// One window's islands: the layout of every island built from the space's groups, the
/// placements kept for them, the moves between pages, and the islands' own edits.
///
/// Rebuilt from the space whenever it changes. A tab new to an island goes below the
/// window's current chip when that chip is on the same island; a tab gone lets the chips
/// below it move up. Only chips and island placements are stored (``IslandState``, on the
/// space); membership and titles are the group relation.
@MainActor
@Observable
final class IslandController {
    enum Layout {
        static let snapshotLimit = 16
        /// Where the first island of a space goes, normalized to the window.
        static let firstIslandOrigin = CGPoint(x: 0.1, y: 0.1)
        /// How far a new island lands from the one it came from, in window widths.
        static let newIslandOffset: Double = 0.26
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
    /// The beams running now, for the layer to draw.
    private(set) var beams: [IslandBeam] = []
    /// A chip being dragged: where it would land, if it may.
    var dropCandidate: (island: UUID, cell: IslandCell)?
    /// The island being moved, drawn over the others.
    var draggedIslandID: UUID?
    /// The island that just appeared, for its unfold.
    private(set) var emergingIslandID: UUID?
    /// The area the islands are placed in, in the layer's coordinates.
    private(set) var area: CGRect = .zero
    /// The page's area, for the moves that need it.
    @ObservationIgnored private(set) var viewportFrame: CGRect = .zero
    /// The last current tab of each island, where a crossing lands.
    @ObservationIgnored private var lastTab: [UUID: UUID] = [:]
    @ObservationIgnored private var previousMembers: [UUID: Set<UUID>] = [:]
    @ObservationIgnored private var captures: [UUID: NSImage] = [:]
    @ObservationIgnored private var captureOrder: [UUID] = []
    @ObservationIgnored private var capturing: Set<UUID> = []
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []
    @ObservationIgnored private var spaceID: UUID?
    @ObservationIgnored private var activatedHere: UUID?
    /// The page view shows the page itself, so a capture of its region is the page: set by
    /// the page view, false while a slab or a move's images stand in for it.
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
    }

    private func sync(_ key: SyncKey) {
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
        islands.first { $0.layout[tabID] != nil }
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
        let size = geometry(for: island).islandSize(of: island.layout, in: area.size)
        let origin = CGPoint(
            x: area.minX + island.placement.x * max(0, area.width - size.width),
            y: area.minY + island.placement.y * max(0, area.height - size.height),
        )
        return CGRect(origin: origin, size: size)
    }

    /// A chip's frame in the layer.
    func frame(ofChip tabID: UUID) -> CGRect? {
        guard let island = island(holding: tabID), let chip = island.layout[tabID] else { return nil }
        let islandFrame = frame(of: island)
        return geometry(for: island).frame(of: chip, in: island.layout).offsetBy(dx: islandFrame.minX, dy: islandFrame.minY)
    }

    /// Where the islands take the pointer: every visible island.
    func hitRegions(in bounds: CGRect) -> [CGRect] {
        visibleIslands.map(frame(of:))
    }

    func color(of island: Island) -> Color {
        island.colorString.map(Color.resolveStoredColor) ?? .appAccentColor
    }

    /// The tab a step in `direction` reaches from the current chip, within its island.
    func destination(toward direction: TableDirection) -> Tab? {
        guard let current = currentTab, let island = island(holding: current.id),
              let next = island.layout.neighbor(of: current.id, toward: direction) else { return nil }
        return tab(for: next)
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
            previousMembers = [:]
            lastTab = [:]
        }
        let onIslands = space.mainTabs.filter { !$0.isFavorite && canvas.storedFloatingPlacement(for: $0)?.isDocked != true }
        var sources: [(id: UUID, title: String, color: String?, members: [UUID], isDefault: Bool)] = [
            (space.id, space.name, nil, onIslands.filter { $0.group == nil }.map(\.id), true),
        ]
        for group in space.groups.filter({ !$0.isArchive }).sorted(by: { $0.position < $1.position }) {
            sources.append((group.id, group.name, group.colorString, group.sortedTabs.filter { tab in onIslands.contains { $0.id == tab.id } }.map(\.id), false))
        }
        let current = windowState.activeTabID
        var changed = false
        var built: [Island] = []
        var nextOrigin = Layout.firstIslandOrigin
        for source in sources where !source.members.isEmpty || source.isDefault {
            var layout = IslandLayout(chips: state.chips.filter { source.members.contains($0.key) })
            let previous = previousMembers[source.id] ?? Set(layout.tabIDs)
            for gone in previous.subtracting(source.members) where layout[gone] != nil {
                layout = layout.removing(gone)
            }
            for tabID in source.members where layout[tabID] == nil {
                let below = current.flatMap { layout[$0] != nil ? $0 : nil } ?? lastTab[source.id].flatMap { layout[$0] != nil ? $0 : nil }
                layout = layout.placing(tabID, below: below)
            }
            if !layout.isConnected {
                layout = layout.reconnected()
            }
            for (tabID, chip) in layout.chips where state.chips[tabID] != chip {
                state.chips[tabID] = chip
                changed = true
            }
            previousMembers[source.id] = Set(source.members)
            var placement = state.islands[source.id] ?? IslandPlacement(x: nextOrigin.x, y: nextOrigin.y)
            if state.islands[source.id] == nil {
                state.islands[source.id] = placement
                changed = true
            }
            placement = state.islands[source.id]!
            nextOrigin.x = min(0.9, placement.x + Layout.newIslandOffset)
            built.append(Island(id: source.id, title: source.title, colorString: source.color, layout: layout, placement: placement, isDefault: source.isDefault))
        }
        let present = built.flatMap(\.layout.tabIDs)
        let before = state
        state.prune(tabs: present, islands: built.map(\.id))
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

    func updateArea(_ area: CGRect) {
        if self.area != area {
            self.area = area
        }
    }

    func updateViewport(_ frame: CGRect) {
        viewportFrame = frame
    }

    // MARK: - Moving between pages

    /// Steps to the neighbor in `direction`; at the island's edge, crosses to the island that
    /// way, or pushes against nothing.
    func step(_ direction: TableDirection) {
        if let tab = destination(toward: direction) {
            travel(to: tab, style: .slide(direction))
        } else if let island = island(toward: direction), let tabID = lastTab[island.id] ?? island.layout.tabIDs.first, let tab = tab(for: tabID) {
            travel(to: tab, style: .cross(direction))
        } else {
            windowState.showToast(direction == .up || direction == .down ? "No tab \(direction.rawValue) from here." : "No tab to the \(direction.rawValue) from here.")
        }
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
        } else if let here, let from = here.layout[current.id], let to = here.layout[tab.id] {
            let dx = to.cell.x - from.cell.x
            let dy = to.cell.y - from.cell.y
            let direction: TableDirection = abs(dx) >= abs(dy) ? (dx >= 0 ? .right : .left) : (dy >= 0 ? .down : .up)
            travel(to: tab, style: .slide(direction))
        } else {
            travel(to: tab, style: .jump)
        }
    }

    /// Makes `tab` current with `style`: the outgoing page leaves as its snapshot and a beam
    /// runs from the page card to the new chip. A page still live is captured first, once the
    /// window's controls have stepped away from it.
    private func travel(to tab: Tab, style: TravelStyle) {
        guard liveIsVisible, let current = windowState.activeTab else {
            start(PageTravel(outgoing: windowState.activeTab.flatMap { snapshot(for: $0.id) }, style: style), to: tab)
            return
        }
        canvas.isCapturingPage = true
        Task(name: "Capture the page before a move") { [weak self] in
            try? await Task.sleep(for: PageCapture.compositingDelay)
            guard let self else { return }
            canvas.isCapturingPage = false
            guard !Task.isCancelled, windowState.activeTabID == current.id else { return }
            let snapshot = captureSnapshot(of: current)
            canvas.showsPageSlab = true
            start(PageTravel(outgoing: snapshot, style: style), to: tab)
        }
    }

    private func start(_ move: PageTravel, to tab: Tab) {
        travel = move
        activatedHere = tab.id
        tabManager.setActiveTab(tab, in: windowState, displacingPrevious: false)
        if let island = island(holding: tab.id) {
            lastTab[island.id] = tab.id
            beam(to: tab.id, color: color(of: island))
        }
    }

    /// The page view finished the move.
    func finishTravel(_ id: UUID) {
        if travel?.id == id {
            travel = nil
        }
    }

    private func beam(to tabID: UUID, color: Color) {
        guard let to = frame(ofChip: tabID), visibleIslands.contains(where: { $0.layout[tabID] != nil }) else { return }
        let from = windowState.pageCardFrame
        guard !from.isEmpty else { return }
        beams.append(IslandBeam(from: from, to: to, color: Color.Components(color: color)))
    }

    func finishBeam(_ id: UUID) {
        beams.removeAll { $0.id == id }
    }

    // MARK: - Editing islands

    /// Moves a chip to `cell` on its island, when it may land there.
    func moveChip(_ tabID: UUID, to cell: IslandCell) {
        guard let index = islands.firstIndex(where: { $0.layout[tabID] != nil }) else { return }
        let moved = islands[index].layout.moving(tabID, to: cell)
        guard moved != islands[index].layout else { return }
        islands[index].layout = moved
        state.chips[tabID] = moved[tabID]
        persist()
    }

    /// Moves a chip onto another island, below that island's last current chip.
    func moveChip(_ tabID: UUID, toIsland islandID: UUID) {
        guard let tab = tab(for: tabID), let space = tab.space, let target = island(islandID), target.layout[tabID] == nil else { return }
        let group = target.isDefault ? nil : space.groups.first { $0.id == islandID }
        if let source = islands.first(where: { $0.layout[tabID] != nil }) {
            previousMembers[source.id]?.remove(tabID)
            state.chips.removeValue(forKey: tabID)
        }
        groupManager.moveTabToGroup(tab, group: group, in: space, skipReordering: true)
        rebuild()
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

    /// Shows a chip as a preview of its page at a preset size, or as its title again.
    func setShape(_ shape: ChipShape, span: IslandSpan = .one, region: FloatingPageRegion? = nil, of tabID: UUID) {
        guard let index = islands.firstIndex(where: { $0.layout[tabID] != nil }) else { return }
        let reshaped = islands[index].layout.reshaping(tabID, shape: shape, span: shape == .preview ? span : .one, region: region)
        islands[index].layout = reshaped
        state.chips[tabID] = reshaped[tabID]
        persist()
    }

    /// Resizes a preview chip to `span` cells, where it fits.
    func resizePreview(_ tabID: UUID, to span: IslandSpan) {
        guard let island = island(holding: tabID), let chip = island.layout[tabID], chip.shape == .preview else { return }
        setShape(.preview, span: IslandSpan(width: max(1, span.width), height: max(1, span.height)), region: chip.region, of: tabID)
    }

    /// The first place beside `source` where an island of `layout` would cover no other island:
    /// to its right, then below, then left, stepping outward.
    private func freePlacement(near source: Island, for layout: IslandLayout, iconsOnly: Bool) -> IslandPlacement {
        let size = IslandGeometry(iconsOnly: iconsOnly).islandSize(of: layout, in: area.size)
        let sourceFrame = frame(of: source)
        let others = islands.filter { $0.id != source.id }.map(frame(of:)) + [sourceFrame]
        // A full cell of room, so either island can grow toward the other before they touch.
        let gap = IslandGeometry.titleCell.width + IslandGeometry.gap
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

    /// Makes a new island from `tabID` and the chips below it: a new group beside the source
    /// island, unfolding, with the chips traveling into it.
    func makeIsland(from tabID: UUID) {
        guard let tab = tab(for: tabID), let space = tab.space, let source = island(holding: tabID) else { return }
        let memberIDs = source.layout.subtree(below: tabID)
        let members = memberIDs.compactMap(self.tab(for:))
        let name = "Island \(space.groups.filter { !$0.isArchive }.count + 1)"
        guard let group = try? groupManager.createGroup(in: space, name: name) else { return }
        // The chips keep their shape, carried so the top one sits at the new island's origin.
        var carried = IslandLayout()
        if let top = source.layout[tabID] {
            for member in memberIDs {
                if var chip = source.layout[member] {
                    chip.cell = IslandCell(x: chip.cell.x - top.cell.x, y: chip.cell.y - top.cell.y)
                    state.chips[member] = chip
                    carried = IslandLayout(chips: carried.chips.merging([member: chip]) { $1 })
                }
            }
        }
        var placement = source.placement
        placement.isPinned = false
        state.islands[group.id] = freePlacement(near: source, for: carried, iconsOnly: placement.iconsOnly)
        for member in members {
            previousMembers[source.id]?.remove(member.id)
            groupManager.moveTabToGroup(member, group: group, in: space, skipReordering: true)
        }
        emergingIslandID = group.id
        rebuild()
        if let chip = frame(ofChip: tabID), let made = island(group.id) {
            beams.append(IslandBeam(from: frame(of: source), to: chip, color: Color.Components(color: color(of: made))))
        }
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

    /// Captures the page from the window server now, while the page view shows it, and keeps
    /// the image in memory and on disk; otherwise the newest image kept for it.
    @discardableResult
    func captureSnapshot(of tab: Tab) -> NSImage? {
        if liveIsVisible, tab.id == windowState.activeTabID, let page = pagePool.existingPage(for: tab.activePage),
           let image = PageCapture.image(of: page.contentView) {
            store(image, for: tab.id)
            if tab.space?.dataStoreMode != .private, let data = image.tiffRepresentation {
                let id = tab.id
                Task(name: "Keep a page's image", priority: .utility) { await CanvasSnapshotStore.save(tiff: data, for: id) }
            }
            return image
        }
        return snapshot(for: tab.id)
    }

    /// Renders the page through WebKit, which draws the page alone, and keeps the image in
    /// memory and on disk: for the captures that can wait while the page stays on screen.
    func refreshSnapshot(of tab: Tab) async {
        guard let page = pagePool.existingPage(for: tab.activePage), page.contentView.bounds.width > 0,
              let image = try? await page.snapshot(), !Task.isCancelled, tab.id == windowState.activeTabID else { return }
        store(image, for: tab.id)
        if tab.space?.dataStoreMode != .private, let data = image.tiffRepresentation {
            await CanvasSnapshotStore.save(tiff: data, for: tab.id)
        }
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
