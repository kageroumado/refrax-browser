import Foundation
import SwiftData

// MARK: - Cross-Collection Operations (Favorites ↔ Tabs)

extension TabManager {
    /// Converts a tab to a favorite bookmark.
    ///
    /// A `.liveFavorite` conversion makes the tab itself a favorite in place
    /// (``makeFavorite(_:home:in:)``). A `.shortcut` conversion closes the tab and keeps a
    /// shortcut bookmark at its address.
    ///
    /// - Parameters:
    ///   - tab: The tab to convert.
    ///   - mode: Whether the tab becomes a favorite or a shortcut.
    ///   - targetWindow: The window whose selection is preserved. Defaults to the active window.
    /// - Returns: The bookmark ID on success, nil on failure.
    @discardableResult
    func convertTabToFavorite(_ tab: Tab, mode: FavoriteMode, in targetWindow: WindowState? = nil) -> UUID? {
        guard tab.space != nil else { return nil }
        if mode == .liveFavorite {
            return makeFavorite(tab, in: targetWindow)?.id
        }

        let url = tab.activePage.url
        let title = tab.activePage.title
        let faviconData = tab.activePage.faviconData
        let largeFaviconData = tab.activePage.largeFaviconData

        // Bypass archive and undo: the content is preserved as a shortcut.
        closeTab(tab, registerUndo: false, bypassArchive: true)

        let bookmark = bookmarksManager.createBookmark(
            url: url,
            title: title,
            isFavorite: true,
            favoriteMode: mode,
            faviconData: faviconData,
            largeFaviconData: largeFaviconData,
        )
        state.incrementContentVersion()
        return bookmark.id
    }

    /// Converts a favorite to a regular tab in the active space.
    ///
    /// Used when removing a favorite from Favorites: instead of closing the tab, it becomes
    /// a regular tab at the top of the tab list. The bookmark/tab link is broken.
    ///
    /// - Parameters:
    ///   - tab: The live favorite tab to convert.
    ///   - bookmark: The associated bookmark (will have its link cleared).
    ///   - targetWindow: The window that receives the tab. Defaults to the active window.
    /// - Returns: `true` if successful, `false` if no active window/space.
    @discardableResult
    func convertLiveFavoriteToTab(_ tab: Tab, bookmark: Bookmark, in targetWindow: WindowState? = nil) -> Bool {
        guard let windowState = targetWindow ?? activeWindowState,
              let activeSpace = windowState.activeSpace else {
            return false
        }

        // Check if this was the active tab BEFORE we modify state
        let wasActiveLiveFavorite = windowState.activeTab == tab

        // Prepend to the tabs outside pinned groups
        let firstPosition = activeSpace.unpinnedTabs.first?.position ?? 1_000_000
        tab.position = firstPosition - 1

        state.convertFavoriteToSpaceTab(tab, in: activeSpace)

        // Break the live favorite link
        bookmark.linkedTab = nil
        tab.linkedBookmark = nil

        // If this was the active live favorite, keep it active (now as a space tab)
        if wasActiveLiveFavorite {
            setActiveTab(tab, in: windowState)
        }

        scheduleSave()
        return true
    }

    /// Converts a favorite to a tab in the active space.
    ///
    /// For favorites with a tab, moves the existing tab into the space at the position.
    /// For shortcuts, creates a new tab at the specified position.
    ///
    /// - Parameters:
    ///   - favorite: The favorite item to convert.
    ///   - atIndex: Target position among the sidebar's tabs outside pinned groups.
    ///   - layoutManager: Layout manager for position calculation.
    /// - Returns: The ID of the resulting tab on success, `nil` on failure.
    @discardableResult
    func convertFavoriteToTab(
        _ favorite: FavoriteItem,
        atIndex targetIndex: Int,
        using layoutManager: Sidebar.LayoutManager,
    ) -> UUID? {
        switch favorite.type {
        case let .liveFavorite(bookmark, tab):
            guard let windowState = activeWindowState,
                  let activeSpace = windowState.activeSpace else { return nil }

            // Calculate position that sorts BEFORE the target item
            let items = layoutManager.normalItems
            if items.isEmpty {
                tab.position = 1_000_000
            } else {
                let clampedIndex = min(targetIndex, items.count)
                if clampedIndex == 0 {
                    // Insert before first item
                    tab.position = items[0].position - 1
                } else if clampedIndex < items.count {
                    // Insert between items: use position just before target
                    tab.position = items[clampedIndex].position - 1
                } else {
                    // Insert after last item
                    tab.position = items[items.count - 1].position + 1
                }
            }

            // Check if this was the active tab BEFORE we modify state
            let wasActiveLiveFavorite = windowState.activeTab == tab

            state.convertFavoriteToSpaceTab(tab, in: activeSpace)

            // Break the live favorite link and remove from favorites
            // (without calling removeLiveFavoriteTab which would try to close the tab)
            bookmark.isFavorite = false
            bookmark.linkedTab = nil
            tab.linkedBookmark = nil

            // If this was the active live favorite, keep it active (now as a space tab)
            if wasActiveLiveFavorite {
                setActiveTab(tab, in: windowState)
            }
            bookmarksManager.recordVisit(for: bookmark)
            bookmarksManager.scheduleRefreshFavoritesCache()

            normalizePositions()
            scheduleSave()

            return tab.id

        case let .shortcut(bookmark):
            guard let windowState = activeWindowState,
                  let space = windowState.activeSpace else { return nil }

            // Get items sorted by position (same as layoutManager view)
            let items = layoutManager.normalItems

            // Calculate position that sorts BEFORE the target item
            let targetPosition: Int
            if items.isEmpty {
                targetPosition = 1_000_000 // After pinned section
            } else {
                let clampedIndex = min(targetIndex, items.count)
                if clampedIndex == 0 {
                    // Insert before first item: use position less than first
                    targetPosition = items[0].position - 1
                } else if clampedIndex < items.count {
                    // Insert between items: use midpoint
                    let prevPosition = items[clampedIndex - 1].position
                    let nextPosition = items[clampedIndex].position
                    targetPosition = (prevPosition + nextPosition) / 2
                } else {
                    // Insert after last item
                    targetPosition = items[items.count - 1].position + 1
                }
            }

            let tab = Tab(space: space, url: bookmark.url, title: bookmark.title, position: targetPosition)
            tab.activePage.faviconData = bookmark.faviconData
            tab.activePage.largeFaviconData = bookmark.largeFaviconData

            // Find correct array index based on position (position determines sort order)
            let insertIndex = space.tabs.firstIndex { $0.position >= targetPosition } ?? space.tabs.count

            space.tabs.insert(tab, at: insertIndex)
            state.indexTab(tab)
            state.modelContext.insert(tab)

            normalizePositions()
            state.incrementListVersion()
            scheduleSave()

            // Don't activate the new tab - shortcuts are just bookmarks being converted,
            // the user is organizing, not intending to switch focus
            bookmarksManager.deleteBookmark(bookmark)

            return tab.id

        case .folder:
            return nil

        case .appShortcut:
            // App shortcuts cannot be converted to tabs (no URL)
            return nil
        }
    }

    /// Favorites all tabs in a group.
    ///
    /// Archive groups cannot be converted to favorites.
    func favoriteGroup(_ group: TabGroup) {
        // Archive groups cannot be favorited
        guard !group.isArchive else {
            Logger.debug("Cannot convert archive group to favorites", category: Logger.tabs)
            return
        }
        guard let space = group.space else { return }

        var allTabs: [Tab] = []
        collectTabsRecursively(from: group.id, in: space, into: &allTabs)

        for tab in allTabs {
            convertTabToFavorite(tab, mode: .liveFavorite)
        }

        state.incrementContentVersion()
    }

    // MARK: - Reordering Operations

    func reorderFavorite(_ favorite: FavoriteItem, to targetIndex: Int) -> Bool {
        // Calculate grid position from linear index
        let layout = bookmarksManager.calculateFavoritesLayout()
        let row = targetIndex / layout.columns
        let col = targetIndex % layout.columns

        bookmarksManager.reorderFavorite(
            favorite,
            from: (favorite.position.row, favorite.position.column),
            to: (row, col),
        )

        return true
    }

    /// Reorders a tab within the sidebar.
    ///
    /// Handles group membership changes and position updates. A tab moved into the pinned
    /// section from outside it becomes a favorite.
    ///
    /// - Parameters:
    ///   - tab: The tab to reorder.
    ///   - originIndex: Original index in the combined pinned+normal list.
    ///   - targetIndex: Target index in the combined list.
    ///   - targetCollection: The collection being dropped into.
    ///   - layoutManager: Layout manager for metadata access.
    /// - Returns: `true` if reorder succeeded.
    @discardableResult
    func reorderTab(
        _ tab: Tab,
        from originIndex: Int,
        to targetIndex: Int,
        in targetCollection: SidebarCollection,
        using layoutManager: Sidebar.LayoutManager,
    ) -> Bool {
        let items = layoutManager.pinnedItems + layoutManager.normalItems

        // Detect cross-collection move
        let sourceIsPinned = tab.isInPinnedGroup
        let targetIsPinned = targetCollection == .pinned
        let isCrossCollectionMove = sourceIsPinned != targetIsPinned

        // The pinned section holds pinned groups; a tab dropped there becomes a favorite.
        if targetIsPinned, !sourceIsPinned {
            return makeFavorite(tab) != nil
        }

        // For cross-collection moves, we need to handle the case where indices might be equal
        // because the target position in the new collection maps to the same global index.
        if !isCrossCollectionMove {
            guard originIndex != targetIndex else { return false }
        }

        guard originIndex >= 0, originIndex < items.count,
              targetIndex >= 0, targetIndex <= items.count else {
            return false
        }

        let effectiveTargetIndex = min(targetIndex, items.count - 1)
        let targetItem = items[effectiveTargetIndex]
        guard let targetMetadata = layoutManager.metadata[targetItem.id] else {
            return false
        }

        // For cross-collection moves, always insert BEFORE the target (movingDown = false).
        // The direction relative to origin doesn't make sense across collections - we want
        // to INSERT at a specific position, not move past the target item.
        // For same-collection moves, use the natural direction based on index comparison.
        let newPosition = calculateNewPosition(
            for: tab.id,
            targetItem: targetItem,
            targetMetadata: targetMetadata,
            items: items,
            layoutManager: layoutManager,
            movingDown: isCrossCollectionMove ? false : (targetIndex > originIndex),
        )

        tab.position = newPosition

        // For cross-collection moves, clear group membership (can't belong to group in other section)
        if isCrossCollectionMove {
            updateGroupMembership(for: tab, newGroupID: nil)
        } else {
            updateGroupMembership(for: tab, newGroupID: targetMetadata.parentGroupID)
        }

        normalizePositions()
        state.incrementListVersion()
        scheduleSave()

        // Notify extensions of tab move
        state.extensionManager?.dispatchTabMoved(tab, fromIndex: originIndex, oldWindow: nil)

        return true
    }

    /// Reorders a group within the sidebar.
    ///
    /// - Parameters:
    ///   - group: The group to reorder.
    ///   - originIndex: Original index in the combined list.
    ///   - targetIndex: Target index in the combined list.
    ///   - targetCollection: The collection being dropped into.
    ///   - layoutManager: Layout manager for metadata access.
    /// - Returns: `true` if reorder succeeded.
    @discardableResult
    func reorderGroup(
        _ group: TabGroup,
        from originIndex: Int,
        to targetIndex: Int,
        in targetCollection: SidebarCollection,
        using layoutManager: Sidebar.LayoutManager,
    ) -> Bool {
        // Use combined pinned + normal array, same as reorderTab
        let items = layoutManager.pinnedItems + layoutManager.normalItems
        let descendantCount = layoutManager.getAllDescendantIDs(of: group.id).count

        // Detect cross-collection move
        let sourceIsPinned = group.isPinned == true
        let targetIsPinned = targetCollection == .pinned
        let isCrossCollectionMove = sourceIsPinned != targetIsPinned

        // When moving DOWN within SAME collection, the target needs adjustment:
        // The drag coordinator's targetIndex counts visual slots from origin, but
        // the first `descendantCount` slots are the group's own descendants.
        // For CROSS-COLLECTION moves, descendants are in source collection, not blocking target.
        let isMovingDown = targetIndex > originIndex
        let adjustedTarget: Int = if isCrossCollectionMove {
            // Cross-collection: no adjustment, descendants aren't in the target collection
            targetIndex
        } else if isMovingDown {
            // Same-collection moving down: account for descendants
            targetIndex + descendantCount
        } else {
            targetIndex
        }

        // For cross-collection moves, indices can be equal but represent different positions
        // (e.g., normal[0] with pinnedCount=2 has global index 2, same as pinned[2])
        guard isCrossCollectionMove || originIndex != targetIndex else { return false }
        guard adjustedTarget >= 0, adjustedTarget < items.count else { return false }

        updateGroupPinState(group, for: targetCollection)

        var effectiveTargetIndex = findEffectiveTargetIndex(
            for: group,
            localTarget: adjustedTarget,
            items: items,
            layoutManager: layoutManager,
        )

        // For cross-collection moves, if the target points to the group itself (or its descendants),
        // we need to use the item BEFORE as reference and insert AFTER it.
        // This happens when moving from start of source collection to end of target collection,
        // e.g., normal[0] → pinned[end] where both have the same global index.
        var movingDownOverride: Bool?
        if isCrossCollectionMove {
            let descendants = layoutManager.getAllDescendantIDs(of: group.id)
            if effectiveTargetIndex == originIndex || descendants.contains(items[effectiveTargetIndex].id) {
                // Target points to the group or its descendants - use previous item instead
                if adjustedTarget > 0 {
                    effectiveTargetIndex = adjustedTarget - 1
                    movingDownOverride = true // Insert AFTER the previous item
                }
            }
        }

        guard effectiveTargetIndex < items.count else { return false }

        let targetItem = items[effectiveTargetIndex]
        guard let targetMetadata = layoutManager.metadata[targetItem.id] else { return false }

        // Groups can only be at root level
        if targetMetadata.nestingLevel >= 1 {
            return false
        }

        // For same-collection moves, movingDown is based on whether adjustedTarget > group's end.
        // For cross-collection moves, usually insert BEFORE target (movingDown = false),
        // unless we had to adjust the target (then use the override).
        let groupEndIndex = originIndex + descendantCount
        let movingDown: Bool = if let override = movingDownOverride {
            override
        } else if isCrossCollectionMove {
            false
        } else {
            adjustedTarget > groupEndIndex
        }

        let newPosition = calculateNewPosition(
            for: group.id,
            targetItem: targetItem,
            targetMetadata: targetMetadata,
            items: items,
            layoutManager: layoutManager,
            movingDown: movingDown,
        )

        group.position = newPosition

        if targetMetadata.parentGroupID != group.parentGroupID {
            group.parentGroupID = targetMetadata.parentGroupID
        }

        normalizePositions()
        state.incrementListVersion()
        scheduleSave()

        return true
    }

    /// Adds a tab to a group.
    @discardableResult
    func addTabToGroup(_ tab: Tab, groupID: UUID) -> Bool {
        guard let space = tab.space,
              let group = space.groups.first(where: { $0.id == groupID }) else {
            return false
        }

        groupManager.moveTabToGroup(tab, group: group)
        state.incrementListVersion()
        return true
    }

    /// Nests a group within another group.
    @discardableResult
    func nestGroup(_ group: TabGroup, in parentGroupID: UUID, using layoutManager: Sidebar.LayoutManager) -> Bool {
        guard group.id != parentGroupID else { return false }

        // Prevent cycle
        if layoutManager.getAllDescendantIDs(of: group.id).contains(parentGroupID) {
            return false
        }

        guard let space = group.space,
              let parentGroup = space.groups.first(where: { $0.id == parentGroupID }),
              group.parentGroupID == nil,
              parentGroup.parentGroupID == nil else {
            return false
        }

        do {
            try groupManager.nestGroup(group, in: parentGroup)
            state.incrementListVersion()
            return true
        } catch {
            return false
        }
    }

    /// Pins a group and all its contents recursively.
    func pinGroup(_ group: TabGroup) {
        setGroupPinStateRecursively(group, isPinned: true)
        normalizePositions()
        state.incrementListVersion()
        scheduleSave()
    }
}
