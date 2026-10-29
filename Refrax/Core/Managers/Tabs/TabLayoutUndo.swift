import Foundation
import SwiftData

/// The source tab's value state and the destination's layout before combining pages.
struct TabLayoutUndo {
    let sourceID: UUID
    let spaceID: UUID?
    let groupID: UUID?
    let position: Int
    let customName: String?
    let createdAt: Date
    let lastAccessed: Date?
    let isUnread: Bool
    let unreadFromBadge: Bool
    let lastBadgeCount: Int?
    let boardFrameData: Data?
    let floatingPlacement: FloatingTabPlacement?
    let wasDetached: Bool
    let destinationID: UUID
    let originalLayout: LayoutConfiguration?
    let destinationLayout: LayoutConfiguration?
    let selections: [Selection]

    struct Selection {
        weak var window: WindowState?
        let activeTabID: UUID?
        let floatingPlacement: FloatingTabPlacement?
    }

    init(source: Tab, destination: Tab, windows: [WindowState]) {
        self.sourceID = source.id
        self.spaceID = source.space?.id
        self.groupID = source.groupID
        self.position = source.position
        self.customName = source.customName
        self.createdAt = source.createdAt
        self.lastAccessed = source.lastAccessed
        self.isUnread = source.isUnread
        self.unreadFromBadge = source.unreadFromBadge
        self.lastBadgeCount = source.lastBadgeCount
        self.boardFrameData = source.boardFrameData
        self.floatingPlacement = source.floatingPlacement
        self.wasDetached = IslandState.decode(source.space?.tableLayoutData).detached.contains(source.id)
        self.destinationID = destination.id
        self.originalLayout = destination.pages.count == 1 ? nil : destination.layoutConfiguration
        self.destinationLayout = destination.layoutConfiguration
        self.selections = windows.map { Selection(window: $0, activeTabID: $0.activeTabID, floatingPlacement: $0.floatingPlacements[source.id]) }
    }
}

extension TabManager {
    func layoutWindows(in space: Space?) -> [WindowState] {
        guard let space else { return [] }
        var windows = windowSync.allWindowStates(for: space)
        if let active = windowSync.findWindowState(for: space), !windows.contains(where: { $0 === active }) {
            windows.append(active)
        }
        return windows
    }

    func registerLayoutUndo(_ snapshot: TabLayoutUndo, joinedPageID: UUID, position: PanePosition) {
        let undoManager = undoRedoManager.undoManager
        undoManager.registerUndo(withTarget: self) { target in
            target.undoLayoutJoin(snapshot, joinedPageID: joinedPageID, position: position)
        }
        undoManager.setActionName("Combine Tabs")
    }

    private func undoLayoutJoin(_ snapshot: TabLayoutUndo, joinedPageID: UUID, position: PanePosition) {
        guard let spaceID = snapshot.spaceID, let space = state.space(for: spaceID),
              let target = state.tab(for: snapshot.destinationID),
              let page = target.pages.first(where: { $0.id == joinedPageID }), target.pages.count > 1 else { return }

        let restored = Tab(space: space, url: page.url, title: page.title, groupID: snapshot.groupID, position: snapshot.position)
        restored.id = snapshot.sourceID
        restored.customName = snapshot.customName
        restored.createdAt = snapshot.createdAt
        restored.lastAccessed = snapshot.lastAccessed
        restored.isUnread = snapshot.isUnread
        restored.unreadFromBadge = snapshot.unreadFromBadge
        restored.lastBadgeCount = snapshot.lastBadgeCount
        restored.boardFrameData = snapshot.boardFrameData
        restored.floatingPlacement = snapshot.floatingPlacement
        restored.activePage.copyContent(from: page)
        state.modelContext.insert(restored)
        space.tabs.append(restored)
        if let group = space.groups.first(where: { $0.id == snapshot.groupID }) {
            group._addTab(restored)
        }
        state.extensionManager?.dispatchPageClosed(page)
        for window in layoutWindows(in: space) {
            window.clearFocusIfNeeded(for: page.id)
        }
        pagePool.transferPage(from: page, to: restored.activePage, preserveHistory: true)
        target._removePage(page)
        target.layoutConfiguration = snapshot.originalLayout
        for remaining in target.pages {
            remaining.position = snapshot.originalLayout?.panePositions[remaining.id] ?? .single
        }
        state.modelContext.delete(page)
        mutationPipeline.withMutation { effects in
            effects.tabAdded(restored, in: space)
        }

        var islands = IslandState.decode(space.tableLayoutData)
        if snapshot.wasDetached {
            islands.detached.insert(restored.id)
        }
        space.tableLayoutData = islands.encoded()
        for window in layoutWindows(in: space) {
            window.islandController?.reloadState()
        }
        for selection in snapshot.selections {
            guard let window = selection.window else { continue }
            window.floatingPlacements[restored.id] = selection.floatingPlacement
            if window.activeSpaceID != space.id {
                spaceManager.switchToSpaceSync(space, for: window)
                window.islandController?.reloadState()
            }
            window.setActiveTabID(selection.activeTabID, for: space.id, trackPrevious: false)
        }
        state.extensionManager?.dispatchTabOpened(restored)
        let undoManager = undoRedoManager.undoManager
        undoManager.registerUndo(withTarget: self) { target in
            target.redoLayoutJoin(snapshot, position: position)
        }
        undoManager.setActionName("Combine Tabs")
    }

    private func redoLayoutJoin(_ snapshot: TabLayoutUndo, position: PanePosition) {
        guard let source = state.tab(for: snapshot.sourceID), let destination = state.tab(for: snapshot.destinationID) else { return }
        destination.layoutConfiguration = snapshot.destinationLayout
        for page in destination.pages {
            page.position = snapshot.destinationLayout?.panePositions[page.id] ?? .single
        }
        _ = moveTabToLayout(source, into: destination, at: position)
        if let space = destination.space {
            var islands = IslandState.decode(space.tableLayoutData)
            islands.detached.remove(snapshot.sourceID)
            space.tableLayoutData = islands.encoded()
            for window in layoutWindows(in: space) {
                window.islandController?.reloadState()
            }
        }
    }
}
