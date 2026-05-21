import Foundation
import SwiftUI

extension Sidebar {
    /// Manages visual layout and hierarchy for all sidebar collections.
    ///
    /// This manager maintains three distinct collections:
    /// - **Favorites**: Space-independent live tabs and shortcuts (grid layout)
    /// - **Pinned**: Pinned tabs/groups in the current space
    /// - **Normal**: Unpinned tabs/groups in the current space (filtered)
    ///
    /// ## Selective Rebuilds
    ///
    /// The manager selectively rebuilds only affected collections based on what changed:
    /// - `favoritesVersion` changes → rebuild favorites only
    /// - `tabListVersion` or `filterSignature` changes → rebuild tabs only
    ///
    /// This prevents cascading SwiftUI invalidation where a favorites change would
    /// unnecessarily re-render all tab views.
    ///
    /// ## Performance
    ///
    /// Rebuilds are triggered explicitly via `onChange` modifiers, not on every
    /// body evaluation. The `frameGeneration` counter only increments when tabs
    /// change, preventing metadata-dependent views from invalidating on unrelated changes.
    @Observable
    final class LayoutManager {
        // MARK: - Dependencies
        
        unowned var windowState: WindowState!
        unowned var tabManager: TabManager!
        unowned var bookmarksManager: BookmarksManager!
        unowned var filterManager: FilterManager!
        unowned var dragCoordinator: DragCoordinator!
        
        // MARK: - Output Collections
        
        /// Favorites grid items (space-independent)
        private(set) var favoritesLayout: [FavoriteItem] = []
        
        /// Pinned tabs/groups in current space
        private(set) var pinnedItems: [TabListItem] = []
        
        /// Normal (unpinned) tabs/groups in current space, filtered
        private(set) var normalItems: [TabListItem] = []
        
        // MARK: - Collection Boundaries
        
        /// Index ranges for each collection in the unified item list.
        ///
        /// Used by drag coordinator to determine drop targets and by
        /// views to apply collection-specific styling.
        struct CollectionBounds {
            let favorites: Range<Int>
            let pinned: Range<Int>
            let normal: Range<Int>
            
            func collection(for index: Int) -> SidebarCollection? {
                if favorites.contains(index) { return .favorites }
                if pinned.contains(index) { return .pinned }
                if normal.contains(index) { return .normal }
                return nil
            }
        }
        
        private(set) var collectionBounds = CollectionBounds(
            favorites: 0 ..< 0,
            pinned: 0 ..< 0,
            normal: 0 ..< 0,
        )
        
        // MARK: - Visual Metadata
        
        /// Metadata for a single item in the sidebar.
        ///
        /// Provides positioning, nesting, and layout information used by
        /// views and drag operations.
        struct ItemMetadata: Equatable {
            let collection: SidebarCollection
            let indexInCollection: Int
            let globalIndex: Int
            var nestingLevel: Int
            let parentGroupID: UUID?
            let topPadding: CGFloat
        }
        
        /// Metadata keyed by item ID.
        ///
        /// Not observed to avoid triggering SwiftUI updates on frame changes.
        @ObservationIgnored
        var metadata: [UUID: ItemMetadata] = [:]

        /// Cached group descendants to avoid repeated traversal.
        ///
        /// Built during `buildMetadata()` and invalidated on layout rebuild.
        /// Key is group ID, value is set of all descendant IDs (tabs and nested groups).
        @ObservationIgnored
        private var descendantsIndex: [UUID: Set<UUID>] = [:]

        /// Cached set of all group IDs for O(1) lookup in buildDescendantsIndex.
        ///
        /// Populated during `buildMetadata()` to avoid O(n) linear search when
        /// checking if a child ID is a group.
        @ObservationIgnored
        private var allGroupIDs: Set<UUID> = []

        /// Items hidden due to their parent group being collapsed.
        ///
        /// Used by `setItemsHidden` for O(n) collapse/expand operations instead
        /// of full hierarchy rebuilds. Items in this set are excluded from
        /// display arrays but retained in the underlying data structures.
        ///
        /// - Note: This set is cleared on full layout rebuilds since the collapse
        ///   state is re-evaluated during `buildTabHierarchy`.
        @ObservationIgnored
        private var hiddenItems: Set<UUID> = []

        /// Backing storage for pinned items including hidden ones.
        ///
        /// Used by `setItemsHidden` to restore items when expanding without
        /// needing a full rebuild. Maps item ID to (item, originalIndex) where
        /// originalIndex preserves sort order for restoration.
        @ObservationIgnored
        private var hiddenPinnedItems: [(item: TabListItem, originalIndex: Int)] = []

        /// Backing storage for normal items including hidden ones.
        ///
        /// Used by `setItemsHidden` to restore items when expanding without
        /// needing a full rebuild. Maps item ID to (item, originalIndex) where
        /// originalIndex preserves sort order for restoration.
        @ObservationIgnored
        private var hiddenNormalItems: [(item: TabListItem, originalIndex: Int)] = []

        // MARK: - Layout Cache (Space Switching Optimization)

        /// Cached layout data for a space.
        ///
        /// Enables instant (~0.1-0.2ms) space switching for previously visited spaces
        /// instead of full rebuilds (5-20ms). The cache stores unfiltered normal items
        /// so the current filter can be applied on retrieval.
        ///
        /// **Invalidation Rules:**
        /// - Tab add/remove/reorder in Space X → Invalidate Space X only
        /// - Group create/delete/collapse in Space X → Invalidate Space X only
        /// - Tab pin toggle in Space X → Invalidate Space X only
        /// - Favorite change → Invalidate ALL spaces (favorites are global)
        /// - Filter change → No invalidation (filter applies on cached items)
        /// - Tab title/favicon change → No invalidation (metadata observed per-tab)
        struct CachedLayout {
            let pinnedItems: [TabListItem]
            let normalItemsUnfiltered: [TabListItem]
            let metadata: [UUID: ItemMetadata]
            let descendantsIndex: [UUID: Set<UUID>]
            let allGroupIDs: Set<UUID>
            let tabListVersion: UInt64
            let cachedAt: Date
        }

        /// Per-space layout cache.
        ///
        /// Key is `Space.id`. Cache is checked on space switch and populated after
        /// layout builds. Use `invalidateCacheForSpace(_:)` for space-local changes
        /// and `invalidateAllCaches()` for global changes like favorites.
        @ObservationIgnored
        private var layoutCache: [UUID: CachedLayout] = [:]

        /// Task for pre-building layouts of inactive spaces.
        ///
        /// Cancelled and recreated on each cache invalidation to debounce rapid mutations.
        /// Uses low priority to avoid blocking UI during active use.
        @ObservationIgnored
        private var prebuildLayoutTask: Task<Void, Never>?

        // MARK: - Version Tracking

        /// Incremented on each layout rebuild for frame tracking.
        private(set) var frameGeneration = 0

        /// Last seen tab list version to avoid redundant rebuilds.
        private var lastSeenVersion: UInt64 = 0

        /// Last seen favorites version for change detection (covers add/remove/reorder).
        private var lastFavoritesVersion: Int = 0

        /// Last seen filter signature for change detection.
        private var lastFilterSignature: Int = 0

        /// Previous item IDs for structural change detection.
        ///
        /// Used to determine if `frameGeneration` should increment. Only structural
        /// changes (add/remove/reorder) require frame recapture - property changes
        /// like tab title don't affect positions.
        @ObservationIgnored
        private var previousPinnedIDs: [UUID] = []
        @ObservationIgnored
        private var previousNormalIDs: [UUID] = []
        
        // MARK: - Public API

        /// Rebuilds collections and metadata based on what actually changed.
        ///
        /// Call this when `tabListVersion`, `favoritesVersion`, or `filterSignature` changes.
        /// The method selectively rebuilds only affected collections to minimize SwiftUI invalidation.
        ///
        /// **Cache Behavior:**
        /// - On space switch, checks for a valid cache entry (matching `tabListVersion`)
        /// - Cache HIT (~0.1-0.2ms): Uses cached layout, applies current filter
        /// - Cache MISS (5-20ms): Builds layout from scratch, populates cache
        func rebuildLayout() {
            // Skip if this version was already handled incrementally
            if tabManager.state.lastIncrementallyHandledVersion == tabManager.state.tabListVersion,
               tabManager.state.tabListVersion != 0 {
                // Update version tracking to stay in sync
                lastSeenVersion = tabManager.state.tabListVersion
                return
            }

            if dragCoordinator.isDragging,
               !dragCoordinator.isAnimatingReturn {
                dragCoordinator.cancelDrag()
                return
            }

            let tabsChanged = tabManager.state.tabListVersion != lastSeenVersion
            let favoritesChanged = bookmarksManager.favoritesVersion != lastFavoritesVersion
            let filterChanged = filterManager.signature != lastFilterSignature

            guard tabsChanged || favoritesChanged || filterChanged else { return }

            // Update version tracking
            lastSeenVersion = tabManager.state.tabListVersion
            lastFavoritesVersion = bookmarksManager.favoritesVersion
            lastFilterSignature = filterManager.signature

            // Only rebuild favorites if favorites changed
            if favoritesChanged {
                favoritesLayout = bookmarksManager.favorites
            }

            // Only rebuild tabs if tabs or filter changed
            if tabsChanged || filterChanged {
                // Clear hidden items state - collapse is re-evaluated during buildTabHierarchy
                clearHiddenItemsState()

                guard let space = windowState.activeSpace else {
                    let structureChanged = !pinnedItems.isEmpty || !normalItems.isEmpty
                    pinnedItems = []
                    normalItems = []
                    previousPinnedIDs = []
                    previousNormalIDs = []
                    if structureChanged {
                        frameGeneration += 1
                    }
                    updateCollectionBounds()
                    buildMetadata()
                    return
                }

                // Check cache for this space - cache hit path (~0.1-0.2ms)
                if let cached = layoutCache[space.id],
                   cached.tabListVersion == tabManager.state.tabListVersion {
                    // Cache HIT - restore cached data and apply current filter
                    restoreFromCache(cached, applyingFilterTo: cached.normalItemsUnfiltered)
                    return
                }

                // Cache MISS - build from scratch (5-20ms)
                let allItems = buildTabHierarchy(from: space)

                // Use filter instead of partition to preserve order (partition is unstable)
                let newPinnedItems = allItems.filter(\.isPinned)
                let unfilteredNormal = allItems.filter { !$0.isPinned }
                let newNormalItems = filterManager.filterItems(unfilteredNormal)

                // Check for structural changes (add/remove/reorder) before updating arrays.
                // Property changes (title, favicon, etc.) are observed directly on Tab objects,
                // so views don't need array replacement to see them.
                let newPinnedIDs = newPinnedItems.map(\.id)
                let newNormalIDs = newNormalItems.map(\.id)
                let structureChanged = newPinnedIDs != previousPinnedIDs || newNormalIDs != previousNormalIDs

                if structureChanged {
                    pinnedItems = newPinnedItems
                    normalItems = newNormalItems
                    previousPinnedIDs = newPinnedIDs
                    previousNormalIDs = newNormalIDs
                }

                updateCollectionBounds()

                // Capture old nesting levels before rebuild
                let oldNestingLevels = metadata.mapValues(\.nestingLevel)

                buildMetadata()

                // Increment frameGeneration if structure OR nesting levels changed.
                // nestingLevel(for:) reads frameGeneration to create observation dependency,
                // so views re-evaluate when this increments.
                let nestingChanged = metadata.contains { id, meta in
                    oldNestingLevels[id] != meta.nestingLevel
                }
                if structureChanged || nestingChanged {
                    frameGeneration += 1
                }

                // Populate cache for this space (after metadata is built)
                populateCache(for: space.id, pinnedItems: newPinnedItems, unfilteredNormal: unfilteredNormal)
            } else if favoritesChanged {
                // When favorites change, globalIndex values for ALL items must be updated
                // since globalIndex is: favorites(0..<n) + pinned(n..<n+p) + normal(n+p..<...)
                // Even though tab structure didn't change, all indices shift when favorites count changes.
                reindexMetadata()
                updateCollectionBounds()
            }
        }

        /// Restores layout state from a cached entry.
        ///
        /// - Parameters:
        ///   - cached: The cached layout data to restore.
        ///   - unfilteredNormal: The unfiltered normal items to apply the current filter to.
        private func restoreFromCache(_ cached: CachedLayout, applyingFilterTo unfilteredNormal: [TabListItem]) {
            let filteredNormal = filterManager.filterItems(unfilteredNormal)

            // Check for structural changes
            let newPinnedIDs = cached.pinnedItems.map(\.id)
            let newNormalIDs = filteredNormal.map(\.id)
            let structureChanged = newPinnedIDs != previousPinnedIDs || newNormalIDs != previousNormalIDs

            if structureChanged {
                pinnedItems = cached.pinnedItems
                normalItems = filteredNormal
                previousPinnedIDs = newPinnedIDs
                previousNormalIDs = newNormalIDs
                frameGeneration += 1
            }

            // Restore cached auxiliary data
            metadata = cached.metadata
            descendantsIndex = cached.descendantsIndex
            allGroupIDs = cached.allGroupIDs

            // Reindex metadata for the filtered normal items (filter may have changed)
            // Note: Cached metadata has correct indices for unfiltered items, but we need
            // to update globalIndex and indexInCollection for filtered normal items
            reindexMetadataAfterCacheRestore()

            updateCollectionBounds()
        }

        /// Populates the cache for a space after a layout build.
        ///
        /// - Parameters:
        ///   - spaceID: The ID of the space to cache.
        ///   - pinnedItems: The pinned items for this space.
        ///   - unfilteredNormal: The unfiltered normal items (filter will be applied on cache retrieval).
        private func populateCache(for spaceID: UUID, pinnedItems: [TabListItem], unfilteredNormal: [TabListItem]) {
            layoutCache[spaceID] = CachedLayout(
                pinnedItems: pinnedItems,
                normalItemsUnfiltered: unfilteredNormal,
                metadata: metadata,
                descendantsIndex: descendantsIndex,
                allGroupIDs: allGroupIDs,
                tabListVersion: tabManager.state.tabListVersion,
                cachedAt: Date(),
            )
        }

        /// Reindexes metadata after restoring from cache.
        ///
        /// Similar to `reindexMetadata()` but optimized for cache restoration where
        /// we know the structure is correct but indices need updating for the
        /// filtered normal items.
        private func reindexMetadataAfterCacheRestore() {
            var globalIndex = favoritesLayout.count

            // Reindex pinned items
            for (localIndex, item) in pinnedItems.enumerated() {
                if var meta = metadata[item.id] {
                    meta = ItemMetadata(
                        collection: .pinned,
                        indexInCollection: localIndex,
                        globalIndex: globalIndex,
                        nestingLevel: meta.nestingLevel,
                        parentGroupID: meta.parentGroupID,
                        topPadding: meta.topPadding,
                    )
                    metadata[item.id] = meta
                }
                globalIndex += 1
            }

            // Reindex normal items (these may differ from cache due to filter)
            for (localIndex, item) in normalItems.enumerated() {
                let padding: CGFloat = (localIndex == 0 && !pinnedItems.isEmpty)
                    ? Constants.Layout.pinnedUnpinnedSpacing
                    : 0

                if var meta = metadata[item.id] {
                    meta = ItemMetadata(
                        collection: .normal,
                        indexInCollection: localIndex,
                        globalIndex: globalIndex,
                        nestingLevel: meta.nestingLevel,
                        parentGroupID: meta.parentGroupID,
                        topPadding: padding,
                    )
                    metadata[item.id] = meta
                }
                globalIndex += 1
            }
        }
        
        /// Forces a layout rebuild regardless of cache state.
        ///
        /// Use when external state has changed in ways not tracked by version counters.
        func forceRebuild() {
            lastSeenVersion = 0
            lastFavoritesVersion = 0
            rebuildLayout()
        }

        // MARK: - Space Swipe Cache Access

        /// Returns cached layout items for a space without switching to it.
        ///
        /// Used by the space swipe gesture to render adjacent space previews
        /// during the drag. Returns nil if no cache exists for the space.
        ///
        /// - Parameter spaceID: The ID of the space to retrieve cached items for.
        /// - Returns: Pinned and normal items if cached, nil otherwise.
        func cachedItemsForSpace(_ spaceID: UUID) -> (pinned: [TabListItem], normal: [TabListItem])? {
            guard let cached = layoutCache[spaceID] else { return nil }
            let filteredNormal = filterManager.filterItems(cached.normalItemsUnfiltered)
            return (pinned: cached.pinnedItems, normal: filteredNormal)
        }

        /// Builds and caches the layout for a space on demand.
        ///
        /// Called by the space swipe gesture handler when no cache exists for
        /// the adjacent space. This is a synchronous operation (~5-20ms).
        ///
        /// - Parameter space: The space to build layout for.
        func buildLayoutForSpace(_ space: Space) {
            let version = tabManager.state.tabListVersion
            prebuildLayoutForSpace(space, version: version)
        }

        // MARK: - Cache Invalidation

        /// Invalidates the cached layout for a specific space.
        ///
        /// Call this when structural changes occur in a space:
        /// - Tab add/remove/reorder
        /// - Group create/delete/collapse
        /// - Tab pin toggle
        ///
        /// Also schedules a debounced pre-build of inactive space layouts so they're
        /// ready when the user switches spaces.
        ///
        /// - Parameter spaceID: The ID of the space whose cache should be invalidated.
        func invalidateCacheForSpace(_ spaceID: UUID) {
            layoutCache.removeValue(forKey: spaceID)
            schedulePrebuildInactiveSpaces()
        }

        /// Invalidates all cached layouts across all spaces.
        ///
        /// Call this when global changes occur that affect all spaces:
        /// - Favorites changes (favorites are displayed in all spaces)
        ///
        /// Also schedules a debounced pre-build of all space layouts.
        ///
        /// - Note: Filter changes do NOT require invalidation since filters
        ///   are applied on cache retrieval, not stored in the cache.
        func invalidateAllCaches() {
            layoutCache.removeAll()
            schedulePrebuildInactiveSpaces()
        }

        // MARK: - Pre-build Debouncer

        /// Schedules a debounced pre-build of inactive space layouts.
        ///
        /// Cancels any pending prebuild task and schedules a new one after 500ms.
        /// This debouncing prevents thrashing during rapid mutations (e.g., closing
        /// multiple tabs quickly).
        ///
        /// The prebuild uses low priority to avoid blocking UI operations.
        private func schedulePrebuildInactiveSpaces() {
            prebuildLayoutTask?.cancel()
            prebuildLayoutTask = Task(priority: .low) { [weak self] in
                // 500ms debounce
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                await self?.prebuildInactiveSpaces()
            }
        }

        /// Pre-builds layouts for all inactive spaces.
        ///
        /// Iterates through all spaces except the active one and builds their layouts
        /// so they're cached and ready for instant switching. Uses cooperative
        /// cancellation between spaces to allow early exit if another mutation occurs.
        ///
        /// - Note: Building layout for an inactive space requires temporarily accessing
        ///   that space's tabs/groups, but the result is keyed by space ID in the cache.
        private func prebuildInactiveSpaces() async {
            guard let activeSpaceID = windowState.activeSpace?.id else { return }
            let currentVersion = tabManager.state.tabListVersion

            for space in tabManager.state.spaces {
                // Skip the active space - it already has current layout
                guard space.id != activeSpaceID else { continue }

                // Cooperative cancellation - check between spaces
                guard !Task.isCancelled else { return }

                // Skip if cache is already valid for this space
                if let cached = layoutCache[space.id],
                   cached.tabListVersion == currentVersion {
                    continue
                }

                // Build layout for this inactive space
                prebuildLayoutForSpace(space, version: currentVersion)
            }
        }

        /// Pre-builds and caches the layout for a single space.
        ///
        /// - Parameters:
        ///   - space: The space to build layout for.
        ///   - version: The current tab list version to associate with the cache.
        private func prebuildLayoutForSpace(_ space: Space, version: UInt64) {
            let ignoreCollapsed = filterManager.hasActiveFilter
            var items: [TabListItem] = []

            // Build tab hierarchy (same logic as buildTabHierarchy but for arbitrary space)
            var tabsByGroup: [UUID: [Tab]] = [:]
            var ungroupedTabs: [Tab] = []

            for tab in space.mainTabs where tab.linkedBookmark == nil {
                if let groupID = tab.groupID {
                    tabsByGroup[groupID, default: []].append(tab)
                } else {
                    ungroupedTabs.append(tab)
                }
            }

            // Include archived tabs in their archive group
            if let archiveGroup = space.groups.first(where: \.isArchive) {
                let archivedTabs = space.tabs.filter(\.isArchived)
                if !archivedTabs.isEmpty {
                    tabsByGroup[archiveGroup.id, default: []].append(contentsOf: archivedTabs)
                }
            }

            for (groupID, tabs) in tabsByGroup {
                tabsByGroup[groupID] = tabs.sorted { $0.position < $1.position }
            }
            ungroupedTabs.sort { $0.position < $1.position }

            var rootGroups: [TabGroup] = []
            var nestedGroupsByParent: [UUID: [TabGroup]] = [:]

            for group in space.groups {
                if let parentID = group.parentGroupID {
                    nestedGroupsByParent[parentID, default: []].append(group)
                } else {
                    rootGroups.append(group)
                }
            }

            rootGroups.sort { $0.position < $1.position }
            for (parentID, nested) in nestedGroupsByParent {
                nestedGroupsByParent[parentID] = nested.sorted { $0.position < $1.position }
            }

            var allRootItems: [(item: Any, position: Int, isPinned: Bool)] = []

            for tab in ungroupedTabs {
                allRootItems.append((tab, tab.position, tab.isPinned))
            }
            for group in rootGroups {
                allRootItems.append((group, group.position, group.isPinned))
            }

            allRootItems.sort { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned
                }
                return lhs.position < rhs.position
            }

            for (item, _, _) in allRootItems {
                if let tab = item as? Tab {
                    items.append(.tab(tab))
                } else if let group = item as? TabGroup {
                    // DFS traversal (replaces recursive local function to avoid
                    // Release-only false positive about local function parameter isolation)
                    var stack: [TabGroup] = [group]
                    while let current = stack.popLast() {
                        items.append(.group(current))
                        guard ignoreCollapsed || !current.isCollapsed else { continue }

                        if let groupedTabs = tabsByGroup[current.id] {
                            for tab in groupedTabs {
                                items.append(.tab(tab))
                            }
                        }

                        if let nestedGroups = nestedGroupsByParent[current.id] {
                            for nestedGroup in nestedGroups.reversed() {
                                stack.append(nestedGroup)
                            }
                        }
                    }
                }
            }

            // Separate into pinned and normal
            let pinnedItems = items.filter(\.isPinned)
            let unfilteredNormal = items.filter { !$0.isPinned }

            // Build metadata for caching (simplified - no frames since not displayed)
            var prebuiltMetadata: [UUID: ItemMetadata] = [:]
            var prebuiltDescendantsIndex: [UUID: Set<UUID>] = [:]
            var prebuiltGroupIDs: Set<UUID> = []

            // Build group ID set
            for item in pinnedItems {
                if case let .group(group) = item {
                    prebuiltGroupIDs.insert(group.id)
                }
            }
            for item in unfilteredNormal {
                if case let .group(group) = item {
                    prebuiltGroupIDs.insert(group.id)
                }
            }

            var globalIndex = favoritesLayout.count

            for (localIndex, item) in pinnedItems.enumerated() {
                prebuiltMetadata[item.id] = ItemMetadata(
                    collection: .pinned,
                    indexInCollection: localIndex,
                    globalIndex: globalIndex,
                    nestingLevel: calculateNestingLevelForItem(item, in: space),
                    parentGroupID: getParentGroupIDForItem(item),
                    topPadding: 0,
                )
                globalIndex += 1
            }

            for (localIndex, item) in unfilteredNormal.enumerated() {
                let padding: CGFloat = (localIndex == 0 && !pinnedItems.isEmpty)
                    ? Constants.Layout.pinnedUnpinnedSpacing
                    : 0

                prebuiltMetadata[item.id] = ItemMetadata(
                    collection: .normal,
                    indexInCollection: localIndex,
                    globalIndex: globalIndex,
                    nestingLevel: calculateNestingLevelForItem(item, in: space),
                    parentGroupID: getParentGroupIDForItem(item),
                    topPadding: padding,
                )
                globalIndex += 1
            }

            // Build descendants index
            var directChildren: [UUID: Set<UUID>] = [:]
            for item in pinnedItems {
                if let parentID = getParentGroupIDForItem(item) {
                    directChildren[parentID, default: []].insert(item.id)
                }
            }
            for item in unfilteredNormal {
                if let parentID = getParentGroupIDForItem(item) {
                    directChildren[parentID, default: []].insert(item.id)
                }
            }

            func computeDescendants(for groupID: UUID) -> Set<UUID> {
                if let cached = prebuiltDescendantsIndex[groupID] {
                    return cached
                }
                var descendants = directChildren[groupID] ?? []
                for childID in descendants {
                    if prebuiltGroupIDs.contains(childID) {
                        descendants.formUnion(computeDescendants(for: childID))
                    }
                }
                prebuiltDescendantsIndex[groupID] = descendants
                return descendants
            }

            for item in pinnedItems {
                if case let .group(group) = item {
                    _ = computeDescendants(for: group.id)
                }
            }
            for item in unfilteredNormal {
                if case let .group(group) = item {
                    _ = computeDescendants(for: group.id)
                }
            }

            // Store in cache
            layoutCache[space.id] = CachedLayout(
                pinnedItems: pinnedItems,
                normalItemsUnfiltered: unfilteredNormal,
                metadata: prebuiltMetadata,
                descendantsIndex: prebuiltDescendantsIndex,
                allGroupIDs: prebuiltGroupIDs,
                tabListVersion: version,
                cachedAt: Date(),
            )
        }

        /// Calculates nesting level for an item in a specific space.
        ///
        /// Used during prebuild when the active space may differ from the target space.
        private func calculateNestingLevelForItem(_ item: TabListItem, in space: Space) -> Int {
            switch item {
            case let .tab(tab):
                guard let groupID = tab.groupID,
                      let group = space.groups.first(where: { $0.id == groupID }) else {
                    return 0
                }
                return group.parentGroupID == nil ? 1 : 2

            case let .group(group):
                return group.parentGroupID == nil ? 0 : 1
            }
        }

        /// Gets the parent group ID for an item.
        ///
        /// Used during prebuild for metadata construction.
        private func getParentGroupIDForItem(_ item: TabListItem) -> UUID? {
            switch item {
            case let .tab(tab):
                tab.groupID
            case let .group(group):
                group.parentGroupID
            }
        }

        // MARK: - Incremental Updates

        /// Removes a single item incrementally without full layout rebuild.
        ///
        /// This is significantly faster than `rebuildLayout()` for single-item removals
        /// like `closeTab`, since it directly removes the item from the appropriate
        /// collection instead of rebuilding the entire hierarchy.
        ///
        /// - Parameters:
        ///   - itemID: The ID of the item to remove.
        ///   - context: Information about where the item was located before removal.
        func removeItemIncremental(_ itemID: UUID, context: TabMutationPipeline.RemovalContext) {
            // Only apply to the active space
            guard let activeSpace = windowState.activeSpace,
                  activeSpace.id == context.spaceID else {
                return
            }

            // Cancel drag if in progress
            if dragCoordinator.isDragging, !dragCoordinator.isAnimatingReturn {
                dragCoordinator.cancelDrag()
                return
            }

            // Remove from the appropriate collection with animation
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                if context.wasPinned {
                    if let index = pinnedItems.firstIndex(where: { $0.id == itemID }) {
                        pinnedItems.remove(at: index)
                        previousPinnedIDs.removeAll { $0 == itemID }
                    }
                } else {
                    if let index = normalItems.firstIndex(where: { $0.id == itemID }) {
                        normalItems.remove(at: index)
                        previousNormalIDs.removeAll { $0 == itemID }
                    }
                }
            }

            // Remove from metadata
            metadata.removeValue(forKey: itemID)

            // Update descendants index if item was in a group
            if let parentGroupID = context.wasInGroupID {
                descendantsIndex[parentGroupID]?.remove(itemID)
            }

            // Update version tracking to stay in sync
            lastSeenVersion = tabManager.state.tabListVersion

            // Increment frame generation to signal structural change
            frameGeneration += 1

            // Rebuild collection bounds and reindex metadata
            updateCollectionBounds()
            reindexMetadata()
        }

        /// Removes multiple items at once without full layout rebuild.
        ///
        /// This is more efficient than calling `removeItemIncremental` for each item
        /// in batch operations like `closeTabsInBatch`, since it iterates through
        /// collections once instead of once per item.
        ///
        /// - Parameters:
        ///   - itemIDs: The set of item IDs to remove.
        ///   - spaceID: The space these items belong to (must match active space).
        func batchRemoveItems(_ itemIDs: Set<UUID>, from spaceID: Space.ID) {
            // Only apply to the active space
            guard let activeSpace = windowState.activeSpace,
                  activeSpace.id == spaceID else {
                return
            }

            // Early exit if nothing to remove
            guard !itemIDs.isEmpty else { return }

            // Cancel drag if in progress
            if dragCoordinator.isDragging, !dragCoordinator.isAnimatingReturn {
                dragCoordinator.cancelDrag()
                return
            }

            // Track if we actually removed anything
            var removedAny = false

            // Collect parent group IDs for descendants index updates
            var affectedGroupIDs: Set<UUID> = []
            for itemID in itemIDs {
                if let meta = metadata[itemID], let parentGroupID = meta.parentGroupID {
                    affectedGroupIDs.insert(parentGroupID)
                }
            }

            // Remove from collections with animation - single pass each
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                let pinnedCountBefore = pinnedItems.count
                pinnedItems.removeAll { itemIDs.contains($0.id) }
                if pinnedItems.count != pinnedCountBefore {
                    removedAny = true
                    previousPinnedIDs.removeAll { itemIDs.contains($0) }
                }

                let normalCountBefore = normalItems.count
                normalItems.removeAll { itemIDs.contains($0.id) }
                if normalItems.count != normalCountBefore {
                    removedAny = true
                    previousNormalIDs.removeAll { itemIDs.contains($0) }
                }
            }

            guard removedAny else { return }

            // Remove from metadata - single pass
            for itemID in itemIDs {
                metadata.removeValue(forKey: itemID)
            }

            // Update descendants index for affected groups
            for groupID in affectedGroupIDs {
                descendantsIndex[groupID]?.subtract(itemIDs)
            }

            // Update version tracking to stay in sync
            lastSeenVersion = tabManager.state.tabListVersion

            // Increment frame generation to signal structural change
            frameGeneration += 1

            // Rebuild collection bounds and reindex metadata
            updateCollectionBounds()
            reindexMetadata()
        }

        /// Removes a group and optionally its descendants incrementally.
        ///
        /// This method handles group deletion without requiring a full layout rebuild.
        /// It's more efficient than `rebuildLayout()` for `deleteGroup` operations since
        /// it directly manipulates the affected items.
        ///
        /// **Behavior based on `deleteContents`:**
        /// - `true`: Removes the group AND all descendants (tabs and nested groups)
        /// - `false`: Removes only the group header; tabs become ungrouped and remain in place
        ///
        /// - Parameters:
        ///   - groupID: The ID of the group being deleted.
        ///   - descendantIDs: Pre-computed set of all descendant IDs (from `getAllDescendantIDs`).
        ///   - deleteContents: Whether to delete contained tabs/groups or just ungroup them.
        func removeGroupIncremental(
            groupID: UUID,
            descendantIDs: Set<UUID>,
            deleteContents: Bool,
        ) {
            // Only apply to the active space
            guard windowState.activeSpace != nil else { return }

            // Cancel drag if in progress
            if dragCoordinator.isDragging, !dragCoordinator.isAnimatingReturn {
                dragCoordinator.cancelDrag()
                return
            }

            if deleteContents {
                removeGroupWithContents(groupID: groupID, descendantIDs: descendantIDs)
            } else {
                removeGroupKeepContents(groupID: groupID, descendantIDs: descendantIDs)
            }

            // Remove the group's entry from descendants index
            descendantsIndex.removeValue(forKey: groupID)
            allGroupIDs.remove(groupID)

            // Update version tracking to stay in sync
            lastSeenVersion = tabManager.state.tabListVersion

            // Increment frame generation to signal structural change
            frameGeneration += 1

            // Rebuild collection bounds and reindex metadata
            updateCollectionBounds()
            reindexMetadata()
        }

        /// Removes a group and all its descendants from collections.
        private func removeGroupWithContents(groupID: UUID, descendantIDs: Set<UUID>) {
            // Build the full set of IDs to remove: group + all descendants
            var idsToRemove = descendantIDs
            idsToRemove.insert(groupID)

            // Track affected parent groups for descendants index updates
            var affectedParentGroupIDs: Set<UUID> = []
            for itemID in idsToRemove {
                if let meta = metadata[itemID], let parentGroupID = meta.parentGroupID {
                    // Only track parents that aren't being removed themselves
                    if !idsToRemove.contains(parentGroupID) {
                        affectedParentGroupIDs.insert(parentGroupID)
                    }
                }
            }

            // Remove from pinned collection - single pass
            pinnedItems.removeAll { idsToRemove.contains($0.id) }
            previousPinnedIDs.removeAll { idsToRemove.contains($0) }

            // Remove from normal collection - single pass
            normalItems.removeAll { idsToRemove.contains($0.id) }
            previousNormalIDs.removeAll { idsToRemove.contains($0) }

            // Remove from hidden items storage if any were hidden
            hiddenItems.subtract(idsToRemove)
            hiddenPinnedItems.removeAll { idsToRemove.contains($0.item.id) }
            hiddenNormalItems.removeAll { idsToRemove.contains($0.item.id) }

            // Remove from metadata
            for itemID in idsToRemove {
                metadata.removeValue(forKey: itemID)
            }

            // Update descendants index for any parent groups that weren't removed
            for parentID in affectedParentGroupIDs {
                descendantsIndex[parentID]?.subtract(idsToRemove)
            }

            // Also remove descendants index entries for any nested groups being deleted
            for itemID in descendantIDs {
                if allGroupIDs.contains(itemID) {
                    descendantsIndex.removeValue(forKey: itemID)
                    allGroupIDs.remove(itemID)
                }
            }
        }

        /// Removes only the group header, keeping tabs in place as ungrouped.
        private func removeGroupKeepContents(groupID: UUID, descendantIDs: Set<UUID>) {
            // Capture the group's parent before removing metadata
            let parentOfDeletedGroup = metadata[groupID]?.parentGroupID

            // Remove the group header from collections
            pinnedItems.removeAll { $0.id == groupID }
            previousPinnedIDs.removeAll { $0 == groupID }
            normalItems.removeAll { $0.id == groupID }
            previousNormalIDs.removeAll { $0 == groupID }

            // Remove group from hidden storage if it was hidden
            hiddenItems.remove(groupID)
            hiddenPinnedItems.removeAll { $0.item.id == groupID }
            hiddenNormalItems.removeAll { $0.item.id == groupID }

            // Remove group's metadata
            metadata.removeValue(forKey: groupID)

            // Update metadata for direct children: remove parent reference, adjust nesting level
            // Only direct children need parent cleared; nested items under nested groups
            // still have their own parent groups
            for itemID in descendantIDs {
                guard let meta = metadata[itemID] else { continue }

                // Check if this item's direct parent was the deleted group
                if meta.parentGroupID == groupID {
                    // Clear parent reference and reduce nesting level
                    let newMeta = ItemMetadata(
                        collection: meta.collection,
                        indexInCollection: meta.indexInCollection,
                        globalIndex: meta.globalIndex,
                        nestingLevel: max(0, meta.nestingLevel - 1),
                        parentGroupID: nil,
                        topPadding: meta.topPadding,
                    )
                    metadata[itemID] = newMeta
                }
            }

            // Update descendants index: if deleted group was nested, remove it and its
            // descendants from the parent group's index
            if let parentID = parentOfDeletedGroup {
                var idsToRemoveFromParent = descendantIDs
                idsToRemoveFromParent.insert(groupID)
                descendantsIndex[parentID]?.subtract(idsToRemoveFromParent)
            }
        }

        /// Toggles visibility of items without a full layout rebuild.
        ///
        /// This method is optimized for group collapse/expand operations. When a group
        /// is collapsed, its descendants can be hidden in O(n) time instead of triggering
        /// an O(n log n) full hierarchy rebuild with sorting.
        ///
        /// **Usage from TabGroupManager:**
        /// ```swift
        /// // When collapsing:
        /// let descendantIDs = layoutManager.getAllDescendantIDs(of: group.id)
        /// layoutManager.setItemsHidden(descendantIDs, hidden: true)
        ///
        /// // When expanding:
        /// layoutManager.setItemsHidden(descendantIDs, hidden: false)
        /// ```
        ///
        /// - Parameters:
        ///   - itemIDs: The set of item IDs to show or hide.
        ///   - hidden: If `true`, removes items from display arrays and stores them
        ///     for later restoration. If `false`, restores previously hidden items.
        ///
        /// - Note: Hidden items retain their metadata and can be restored in their
        ///   original positions. This method does NOT call `rebuildLayout()`.
        func setItemsHidden(_ itemIDs: Set<UUID>, hidden: Bool) {
            guard !itemIDs.isEmpty else { return }

            // Cancel drag if in progress - visibility changes affect drag targets
            if dragCoordinator.isDragging, !dragCoordinator.isAnimatingReturn {
                dragCoordinator.cancelDrag()
                return
            }

            if hidden {
                hideItems(itemIDs)
            } else {
                showItems(itemIDs)
            }

            // Update version tracking to stay in sync
            lastSeenVersion = tabManager.state.tabListVersion

            // Increment frame generation to signal structural change
            frameGeneration += 1

            // Rebuild collection bounds and reindex metadata
            updateCollectionBounds()
            reindexMetadata()
        }

        /// Hides items by removing them from display arrays and storing for restoration.
        private func hideItems(_ itemIDs: Set<UUID>) {
            // Track which items are being hidden
            hiddenItems.formUnion(itemIDs)

            // Remove from pinned items, storing for later restoration
            var pinnedIndicesToRemove: [Int] = []
            for (index, item) in pinnedItems.enumerated() where itemIDs.contains(item.id) {
                // Store with a logical index that preserves order relative to remaining items
                hiddenPinnedItems.append((item: item, originalIndex: index))
                pinnedIndicesToRemove.append(index)
            }

            // Remove in reverse order to preserve indices
            for index in pinnedIndicesToRemove.reversed() {
                pinnedItems.remove(at: index)
                previousPinnedIDs.remove(at: index)
            }

            // Remove from normal items, storing for later restoration
            var normalIndicesToRemove: [Int] = []
            for (index, item) in normalItems.enumerated() where itemIDs.contains(item.id) {
                hiddenNormalItems.append((item: item, originalIndex: index))
                normalIndicesToRemove.append(index)
            }

            // Remove in reverse order to preserve indices
            for index in normalIndicesToRemove.reversed() {
                normalItems.remove(at: index)
                previousNormalIDs.remove(at: index)
            }
        }

        /// Shows previously hidden items by restoring them to display arrays.
        private func showItems(_ itemIDs: Set<UUID>) {
            // Remove from hidden tracking
            hiddenItems.subtract(itemIDs)

            // Restore pinned items in their original positions
            let pinnedToRestore = hiddenPinnedItems.filter { itemIDs.contains($0.item.id) }
            hiddenPinnedItems.removeAll { itemIDs.contains($0.item.id) }

            // Sort by original index to maintain order
            for (item, originalIndex) in pinnedToRestore.sorted(by: { $0.originalIndex < $1.originalIndex }) {
                // Calculate adjusted insertion index accounting for already-restored items
                // and items that were originally before this one but are still hidden
                let insertIndex = min(originalIndex, pinnedItems.count)
                pinnedItems.insert(item, at: insertIndex)
                previousPinnedIDs.insert(item.id, at: insertIndex)
            }

            // Restore normal items in their original positions
            let normalToRestore = hiddenNormalItems.filter { itemIDs.contains($0.item.id) }
            hiddenNormalItems.removeAll { itemIDs.contains($0.item.id) }

            for (item, originalIndex) in normalToRestore.sorted(by: { $0.originalIndex < $1.originalIndex }) {
                let insertIndex = min(originalIndex, normalItems.count)
                normalItems.insert(item, at: insertIndex)
                previousNormalIDs.insert(item.id, at: insertIndex)
            }
        }

        /// Clears all hidden items state.
        ///
        /// Called during full layout rebuilds since collapse state is re-evaluated
        /// from scratch during `buildTabHierarchy`.
        private func clearHiddenItemsState() {
            hiddenItems.removeAll()
            hiddenPinnedItems.removeAll()
            hiddenNormalItems.removeAll()
        }

        /// Reindexes metadata after incremental removal.
        ///
        /// Updates `indexInCollection` and `globalIndex` for all items without
        /// rebuilding the entire metadata dictionary. Preserves existing frames
        /// and nesting levels.
        private func reindexMetadata() {
            var globalIndex = 0

            // Reindex favorites - create new entries for new favorites, update existing
            for (localIndex, item) in favoritesLayout.enumerated() {
                // Favorites always have nesting=0, no parent, no padding
                metadata[item.id] = ItemMetadata(
                    collection: .favorites,
                    indexInCollection: localIndex,
                    globalIndex: globalIndex,
                    nestingLevel: 0,
                    parentGroupID: nil,
                    topPadding: 0,
                )
                globalIndex += 1
            }

            // Reindex pinned items
            for (localIndex, item) in pinnedItems.enumerated() {
                if let existingMeta = metadata[item.id] {
                    let newMeta = ItemMetadata(
                        collection: .pinned,
                        indexInCollection: localIndex,
                        globalIndex: globalIndex,
                        nestingLevel: existingMeta.nestingLevel,
                        parentGroupID: existingMeta.parentGroupID,
                        topPadding: existingMeta.topPadding,
                    )
                    metadata[item.id] = newMeta
                }
                globalIndex += 1
            }

            // Reindex normal items
            for (localIndex, item) in normalItems.enumerated() {
                // Recalculate top padding for first item
                let padding: CGFloat = (localIndex == 0 && !pinnedItems.isEmpty)
                    ? Constants.Layout.pinnedUnpinnedSpacing
                    : 0

                if let existingMeta = metadata[item.id] {
                    let newMeta = ItemMetadata(
                        collection: .normal,
                        indexInCollection: localIndex,
                        globalIndex: globalIndex,
                        nestingLevel: existingMeta.nestingLevel,
                        parentGroupID: existingMeta.parentGroupID,
                        topPadding: padding,
                    )
                    metadata[item.id] = newMeta
                }
                globalIndex += 1
            }
        }
        
        /// Gets the collection that contains the given item.
        func collection(for itemID: UUID) -> SidebarCollection? {
            metadata[itemID]?.collection
        }
        
        /// Gets nesting level for an item (0 = root, 1 = in group, 2 = nested group).
        ///
        /// Accesses `frameGeneration` to create observation dependency for SwiftUI.
        func nestingLevel(for itemID: UUID) -> Int {
            _ = frameGeneration
            return metadata[itemID]?.nestingLevel ?? 0
        }
        
        /// Calculates 2D offset for an item during drag operations.
        ///
        /// Returns the appropriate offset based on whether the item is being
        /// dragged, is a child of a dragged group, or is being pushed by a drag.
        ///
        /// - For tabs: Only the y component is used (vertical reordering)
        /// - For favorites: Both x and y are used (2D grid flow)
        func calculateItemOffset(for itemID: UUID) -> CGPoint {
            guard let primaryItem = dragCoordinator.primaryDraggedItem else {
                return .zero
            }

            // Check if this item is any of the dragged items
            if dragCoordinator.isItemBeingDragged(itemID) {
                // Dragged item uses currentOffset for y, x stays 0 (tabs only drag vertically)
                return CGPoint(x: 0, y: dragCoordinator.currentOffset)
            }

            if let draggedGroup = primaryItem.group,
               containsItem(itemID, inGroupHierarchy: draggedGroup.id) {
                return dragCoordinator.isAnimatingReturn ? .zero : CGPoint(x: 0, y: dragCoordinator.currentOffset)
            }

            return dragCoordinator.itemPushOffsets[itemID] ?? .zero
        }

        /// Gets all descendant IDs of a group.
        ///
        /// Includes both tabs and nested groups. Used for drag validation
        /// (preventing drops into own descendants) and group operations.
        ///
        /// - Note: Results are cached during layout rebuild for O(1) lookup.
        func getAllDescendantIDs(of groupID: UUID) -> Set<UUID> {
            if let cached = descendantsIndex[groupID] {
                return cached
            }
            // Fallback to computation if not cached (shouldn't happen in normal flow)
            return computeDescendants(of: groupID)
        }

        /// Computes descendants without using cache.
        private func computeDescendants(of groupID: UUID) -> Set<UUID> {
            var descendants: Set<UUID> = []

            for item in pinnedItems {
                switch item {
                case let .tab(tab) where tab.groupID == groupID:
                    descendants.insert(tab.id)
                case let .group(group) where group.parentGroupID == groupID:
                    descendants.insert(group.id)
                    descendants.formUnion(computeDescendants(of: group.id))
                default:
                    break
                }
            }

            for item in normalItems {
                switch item {
                case let .tab(tab) where tab.groupID == groupID:
                    descendants.insert(tab.id)
                case let .group(group) where group.parentGroupID == groupID:
                    descendants.insert(group.id)
                    descendants.formUnion(computeDescendants(of: group.id))
                default:
                    break
                }
            }

            return descendants
        }
        
        /// Calculates the bounding rect for a group including all visible contents.
        ///
        /// Uses the header's minY and computes maxY by adding slotHeight for each
        /// visible descendant. This is more reliable than iterating frame lookups
        /// since we know group contents are contiguous in the layout.
        func calculateGroupBounds(groupID: UUID) -> CGRect {
            guard let headerFrame = dragCoordinator.computedItemFrame(for: groupID) else {
                return .zero
            }

            // Count visible descendants (tabs + nested group headers)
            let visibleDescendantCount = countVisibleDescendants(of: groupID)
            let slotHeight = dragCoordinator.state.slotHeight

            // Group bounds: header minY to (header maxY + descendant slots)
            let totalHeight = headerFrame.height + CGFloat(visibleDescendantCount) * slotHeight

            return CGRect(
                x: headerFrame.minX,
                y: headerFrame.minY,
                width: headerFrame.width,
                height: totalHeight,
            )
        }

        /// Counts visible descendants of a group (not hidden by collapse).
        private func countVisibleDescendants(of groupID: UUID) -> Int {
            let allDescendants = getAllDescendantIDs(of: groupID)
            return allDescendants.count(where: { !hiddenItems.contains($0) })
        }

        // MARK: - Private Hierarchy Building
        
        /// Builds ordered hierarchy of tabs and groups.
        ///
        /// When filtering is active, collapse state is ignored so all items
        /// are available for filter evaluation.
        private func buildTabHierarchy(from space: Space) -> [TabListItem] {
            let ignoreCollapsed = filterManager.hasActiveFilter
            var items: [TabListItem] = []

            var tabsByGroup: [UUID: [Tab]] = [:]
            var ungroupedTabs: [Tab] = []

            for tab in space.mainTabs where tab.linkedBookmark == nil {
                if let groupID = tab.groupID {
                    tabsByGroup[groupID, default: []].append(tab)
                } else {
                    ungroupedTabs.append(tab)
                }
            }

            // Include archived tabs in their archive group (mainTabs excludes archived)
            if let archiveGroup = space.groups.first(where: \.isArchive) {
                let archivedTabs = space.tabs.filter(\.isArchived)
                if !archivedTabs.isEmpty {
                    tabsByGroup[archiveGroup.id, default: []].append(contentsOf: archivedTabs)
                }
            }
            
            for (groupID, tabs) in tabsByGroup {
                tabsByGroup[groupID] = tabs.sorted { $0.position < $1.position }
            }
            ungroupedTabs.sort { $0.position < $1.position }
            
            var rootGroups: [TabGroup] = []
            var nestedGroupsByParent: [UUID: [TabGroup]] = [:]
            
            for group in space.groups {
                if let parentID = group.parentGroupID {
                    nestedGroupsByParent[parentID, default: []].append(group)
                } else {
                    rootGroups.append(group)
                }
            }
            
            rootGroups.sort { $0.position < $1.position }
            for (parentID, nested) in nestedGroupsByParent {
                nestedGroupsByParent[parentID] = nested.sorted { $0.position < $1.position }
            }
            
            var allRootItems: [(item: Any, position: Int, isPinned: Bool)] = []

            for tab in ungroupedTabs {
                allRootItems.append((tab, tab.position, tab.isPinned))
            }
            for group in rootGroups {
                allRootItems.append((group, group.position, group.isPinned))
            }

            allRootItems.sort { lhs, rhs in
                if lhs.isPinned != rhs.isPinned {
                    return lhs.isPinned
                }
                return lhs.position < rhs.position
            }

            for (item, _, _) in allRootItems {
                if let tab = item as? Tab {
                    items.append(.tab(tab))
                } else if let group = item as? TabGroup {
                    var stack: [TabGroup] = [group]
                    while let current = stack.popLast() {
                        items.append(.group(current))
                        guard ignoreCollapsed || !current.isCollapsed else { continue }

                        if let groupedTabs = tabsByGroup[current.id] {
                            for tab in groupedTabs {
                                items.append(.tab(tab))
                            }
                        }

                        if let nestedGroups = nestedGroupsByParent[current.id] {
                            for nestedGroup in nestedGroups.reversed() {
                                stack.append(nestedGroup)
                            }
                        }
                    }
                }
            }

            return items
        }
        
        private func updateCollectionBounds() {
            let favCount = favoritesLayout.count
            let pinnedCount = pinnedItems.count
            let normalCount = normalItems.count

            collectionBounds = CollectionBounds(
                favorites: 0 ..< favCount,
                pinned: favCount ..< (favCount + pinnedCount),
                normal: (favCount + pinnedCount) ..< (favCount + pinnedCount + normalCount),
            )
        }

        private func buildMetadata() {
            metadata.removeAll()
            descendantsIndex.removeAll()
            allGroupIDs.removeAll()

            // Build group ID set for O(1) lookup in buildDescendantsIndex
            for item in pinnedItems {
                if case let .group(group) = item {
                    allGroupIDs.insert(group.id)
                }
            }
            for item in normalItems {
                if case let .group(group) = item {
                    allGroupIDs.insert(group.id)
                }
            }

            var globalIndex = 0

            for (localIndex, item) in favoritesLayout.enumerated() {
                metadata[item.id] = ItemMetadata(
                    collection: .favorites,
                    indexInCollection: localIndex,
                    globalIndex: globalIndex,
                    nestingLevel: 0,
                    parentGroupID: nil,
                    topPadding: 0,
                )
                globalIndex += 1
            }

            for (localIndex, item) in pinnedItems.enumerated() {
                metadata[item.id] = ItemMetadata(
                    collection: .pinned,
                    indexInCollection: localIndex,
                    globalIndex: globalIndex,
                    nestingLevel: calculateNestingLevel(for: item),
                    parentGroupID: getParentGroupID(for: item),
                    topPadding: 0,
                )
                globalIndex += 1
            }

            for (localIndex, item) in normalItems.enumerated() {
                // Add spacing before first normal item if there are pinned items
                let padding: CGFloat = (localIndex == 0 && !pinnedItems.isEmpty)
                    ? Constants.Layout.pinnedUnpinnedSpacing
                    : 0

                metadata[item.id] = ItemMetadata(
                    collection: .normal,
                    indexInCollection: localIndex,
                    globalIndex: globalIndex,
                    nestingLevel: calculateNestingLevel(for: item),
                    parentGroupID: getParentGroupID(for: item),
                    topPadding: padding,
                )
                globalIndex += 1
            }

            buildDescendantsIndex()
        }

        /// Builds the descendants index for all groups.
        ///
        /// Uses a bottom-up approach: processes items in reverse order so nested groups
        /// are computed before their parents, enabling O(1) union operations.
        private func buildDescendantsIndex() {
            // First pass: collect direct children for each group
            var directChildren: [UUID: Set<UUID>] = [:]

            for item in pinnedItems {
                if let parentID = getParentGroupID(for: item) {
                    directChildren[parentID, default: []].insert(item.id)
                }
            }

            for item in normalItems {
                if let parentID = getParentGroupID(for: item) {
                    directChildren[parentID, default: []].insert(item.id)
                }
            }

            /// Second pass: compute full descendants for each group
            /// Process groups in reverse hierarchy order (nested first, then parents)
            func computeFullDescendants(for groupID: UUID) -> Set<UUID> {
                if let cached = descendantsIndex[groupID] {
                    return cached
                }

                var descendants = directChildren[groupID] ?? []

                // For each direct child that is a group, add its descendants
                for childID in descendants {
                    // O(1) lookup using pre-built group ID set
                    if allGroupIDs.contains(childID) {
                        descendants.formUnion(computeFullDescendants(for: childID))
                    }
                }

                descendantsIndex[groupID] = descendants
                return descendants
            }

            // Process all groups
            for item in pinnedItems {
                if case let .group(group) = item {
                    _ = computeFullDescendants(for: group.id)
                }
            }

            for item in normalItems {
                if case let .group(group) = item {
                    _ = computeFullDescendants(for: group.id)
                }
            }
        }
        
        /// Calculates nesting level for tab/group.
        func calculateNestingLevel(for item: TabListItem) -> Int {
            guard let space = windowState.activeSpace else { return 0 }
            
            switch item {
            case let .tab(tab):
                guard let groupID = tab.groupID,
                      let group = space.groups.first(where: { $0.id == groupID }) else {
                    return 0
                }
                return group.parentGroupID == nil ? 1 : 2
                
            case let .group(group):
                return group.parentGroupID == nil ? 0 : 1
            }
        }
        
        private func getParentGroupID(for item: TabListItem) -> UUID? {
            switch item {
            case let .tab(tab):
                tab.groupID
            case let .group(group):
                group.parentGroupID
            }
        }
        
        private func containsItem(_ itemID: UUID, inGroupHierarchy groupID: UUID) -> Bool {
            getAllDescendantIDs(of: groupID).contains(itemID)
        }
    }
}

// MARK: - GroupCollapseHandler Conformance

extension Sidebar.LayoutManager: GroupCollapseHandler {
    // getAllDescendantIDs(of:) and setItemsHidden(_:hidden:) are already implemented above.
    // This extension just declares conformance to the protocol.
}
