import Algorithms
import Foundation
import SwiftUI

extension Sidebar.DragCoordinator {
    // MARK: - Private Helpers - Initialization

    func captureFirstItemBaseline() {
        // Use computed section frames derived from item positions and scroll offset.
        // The first item starts at the top of whichever section exists first.
        let pinnedFrame = computedPinnedSectionFrame
        let normalFrame = computedNormalSectionFrame

        if !layoutManager.pinnedItems.isEmpty, !pinnedFrame.isEmpty {
            _firstItemStartY = pinnedFrame.minY
        } else if !layoutManager.normalItems.isEmpty, !normalFrame.isEmpty {
            _firstItemStartY = normalFrame.minY
        }
        // No sections have frames yet - leave _firstItemStartY as nil
    }

    func buildDescendantsCache() {
        _descendantsCache.removeAll()

        let allGroups = getAllItems().compactMap(\.group)
        for group in allGroups {
            _descendantsCache[group.id] = layoutManager.getAllDescendantIDs(of: group.id)
        }
    }

    /// Build exclusion set for the main dragged item and followers.
    ///
    /// The main item, its descendants (if a group), and all follower items
    /// are excluded from drop target calculations and offset animations.
    func buildExclusionSetForMainItem() {
        _draggedItemExclusionSet.removeAll()
        guard let mainItem = primaryDraggedItem else { return }

        _draggedItemExclusionSet.insert(mainItem.id)
        if let group = mainItem.group {
            _draggedItemExclusionSet.formUnion(getDescendants(of: group.id))
        }

        // Also exclude follower items (multi-selection drag)
        for follower in followerItems {
            _draggedItemExclusionSet.insert(follower.id)
        }
    }

    /// Legacy function for restoring from AppKit ghost state.
    /// Builds exclusion set from arbitrary items array.
    func buildExclusionSetForMultiDrag(_ items: [DraggedItem]) {
        _draggedItemExclusionSet.removeAll()
        for item in items {
            _draggedItemExclusionSet.insert(item.id)
            if let group = item.group {
                _draggedItemExclusionSet.formUnion(getDescendants(of: group.id))
            }
        }
    }

    // MARK: - Private Helpers - Cache Access

    /// Get combined items list with caching
    func getAllItems() -> [TabListItem] {
        // Build cache if empty (first call) OR if generation changed
        if _allItemsCache.isEmpty || _cachedAllItemsGeneration != layoutManager.frameGeneration {
            // Note: This returns pinned + normal items only, NOT favorites.
            // Indices in this array don't match globalIndex from metadata.
            // Use globalIndexOffset to convert between them.
            _allItemsCache = layoutManager.pinnedItems + layoutManager.normalItems
            _cachedAllItemsGeneration = layoutManager.frameGeneration
        }

        return _allItemsCache
    }

    /// Offset to convert from getAllItems() local index to globalIndex.
    ///
    /// Since getAllItems() excludes favorites, add this offset to get globalIndex.
    /// Example: if there are 7 favorites, getAllItems()[0] has globalIndex 7.
    var globalIndexOffset: Int {
        layoutManager.favoritesLayout.count
    }

    /// Convert global index to local index for getAllItems()
    func localIndex(from globalIndex: Int) -> Int {
        globalIndex - globalIndexOffset
    }

    /// Convert local index (from getAllItems) to global index
    func globalIndex(from localIndex: Int) -> Int {
        localIndex + globalIndexOffset
    }

    /// Get only visible items (valid frames, current generation), sorted by Y
    func getVisibleItems() -> [ValidatedItem] {
        // Rebuild if cache empty (first call) OR generation changed
        if _visibleItemsCache.isEmpty || _cachedVisibleItemsGeneration != layoutManager.frameGeneration {
            _visibleItemsCache = getAllItems().compactMap { item in
                guard let metadata = layoutManager.metadata[item.id],
                      let frame = computedItemFrame(for: item.id)
                else { return nil }

                return ValidatedItem(item: item, frame: frame, metadata: metadata)
            }
            .sorted { $0.frame.minY < $1.frame.minY }
            _cachedVisibleItemsGeneration = layoutManager.frameGeneration
        }

        return _visibleItemsCache
    }

    /// Get cached descendants for a group
    func getDescendants(of groupID: UUID) -> Set<UUID> {
        _descendantsCache[groupID] ?? []
    }

    func clearCaches() {
        _allItemsCache.removeAll()
        _visibleItemsCache.removeAll()
        _descendantsCache.removeAll()
        _draggedItemExclusionSet.removeAll()
        _cachedAllItemsGeneration = -1
        _cachedVisibleItemsGeneration = -1
    }
}
