import AppKit
import Observation
import SwiftUI
import WebKit

/// A group drawn on the tab canvas: a zone that holds its member tiles.
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

/// Manages the tab canvas: a board on which every tab of the active space is a
/// tile placed at a position of its own, zoomed out from and back into the live page.
///
/// The board is a table, not a list. Tiles keep the position they were given
/// (persisted on ``Tab/boardFrame``), a click zooms into a tile until it fills the
/// window and the live page takes over, and dismissing zooms back out. Tab groups
/// are zones on the board: a zone is at least the rectangle stored on
/// ``TabGroup/boardFrame`` and always grows to hold its members; dragging a zone
/// carries its members, and dropping a tile inside a zone joins the group.
///
/// Tile content is a software snapshot of the page, taken whenever the tab is
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

    /// Tabs on the board, in sidebar order.
    private(set) var tabs: [Tab] = []

    /// Where each tab's tile sits, mirrored from ``Tab/boardFrame`` for observation.
    private(set) var tileFrames: [Tab.ID: CGRect] = [:]

    /// Zones derived from the space's groups and the current tile positions.
    private(set) var zones: [CanvasZone] = []

    /// Snapshot of each tab's page.
    private(set) var snapshots: [Tab.ID: NSImage] = [:]

    /// The tab the board zooms out from on show and back into on dismiss.
    private(set) var focusedTabID: Tab.ID?

    /// Tile size, matching the content area's aspect ratio so a zoomed tile lands
    /// exactly on the live page.
    private(set) var tileSize = Layout.defaultTileSize

    @ObservationIgnored
    private var snapshotTask: Task<Void, Never>?

    @ObservationIgnored
    private var activationTask: Task<Void, Never>?

    @ObservationIgnored
    private var previousActiveTabID: Tab.ID?

    // MARK: - Constants

    enum Layout {
        static let defaultTileSize = CGSize(width: 320, height: 200)
        static let tileWidth: CGFloat = 320
        static let gap: CGFloat = 48
        static let columns = 4
        /// Empty board around the outermost tiles, so there is always room to drag.
        static let boardMargin: CGFloat = 600
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

    // MARK: - Public API

    func toggle() {
        if isActive {
            dismiss(activating: nil)
        } else {
            show()
        }
    }

    /// Opens the canvas for the active space.
    func show() {
        guard !isActive else { return }

        tabs = windowState.activeSpaceTabs.filter { !$0.isArchived }
        focusedTabID = windowState.activeTab?.id
        tileSize = contentAspectTileSize()
        loadTileFrames()
        placeUnplacedTabs()
        rebuildZones()
        isActive = true

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
        isActive = false
    }

    /// Records a tile's new position while it is being dragged.
    func moveTile(_ tabID: Tab.ID, to frame: CGRect) {
        tileFrames[tabID] = frame
        tab(for: tabID)?.boardFrame = frame
        tabManager.state.scheduleSave()
    }

    /// Settles a dropped tile: it joins the zone it landed in, or leaves the one it left.
    func finishTileDrag(_ tabID: Tab.ID) {
        defer { rebuildZones() }
        guard let tab = tab(for: tabID), let frame = tileFrames[tabID] else { return }

        let target = zone(containing: CGPoint(x: frame.midX, y: frame.midY))
        let targetGroup = target.flatMap { group(for: $0.id) }
        guard tab.group?.id != targetGroup?.id else { return }

        groupManager.moveTabToGroup(tab, group: targetGroup, in: windowState.activeSpace)
    }

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
        rebuildZones()
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
        tileFrames = [:]
        for tab in tabs {
            if let frame = tab.boardFrame {
                tileFrames[tab.id] = frame
            }
        }
    }

    /// Places tabs that have no tile yet in reading order after the last placed one.
    private func placeUnplacedTabs() {
        let unplaced = tabs.filter { tileFrames[$0.id] == nil }
        guard !unplaced.isEmpty else { return }

        let step = CGSize(width: tileSize.width + Layout.gap, height: tileSize.height + Layout.gap * 1.5)
        var index = tabs.count - unplaced.count
        for tab in unplaced {
            let column = index % Layout.columns
            let row = index / Layout.columns
            let frame = CGRect(
                x: CGFloat(column) * step.width,
                y: CGFloat(row) * step.height,
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
        let bounds = page.backingWebView.bounds
        guard bounds.width > 0, bounds.height > 0 else { return Layout.defaultTileSize }
        let height = (Layout.tileWidth * bounds.height / bounds.width).rounded()
        return CGSize(width: Layout.tileWidth, height: height)
    }

    // MARK: - Zones

    /// Recomputes every zone from the groups and the current tile positions.
    ///
    /// A zone is the union of the group's claimed rectangle, its own tiles (padded,
    /// with room for their titles), and its child zones. Groups with neither a claim
    /// nor members have no zone.
    private func rebuildZones() {
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
            for child in all where child.parentGroupID == group.id {
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

        zones = all.compactMap { group in
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
        let webView = page.backingWebView
        guard webView.bounds.width > 0, webView.bounds.height > 0 else { return }

        let configuration = WKSnapshotConfiguration()
        configuration.snapshotWidth = NSNumber(value: Layout.snapshotWidth)
        configuration.afterScreenUpdates = false

        guard let image = try? await webView.takeSnapshot(configuration: configuration) else { return }
        snapshots[tab.id] = image
        if let tiff = image.tiffRepresentation {
            await CanvasSnapshotStore.save(tiff: tiff, for: tab.id)
        }
    }
}
