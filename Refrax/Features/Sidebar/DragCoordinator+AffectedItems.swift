import Foundation
import SwiftUI

extension Sidebar.DragCoordinator {
    // MARK: - Private Helpers - Affected Items

    /// Update which items are affected by the drag (for push-aside animation)
    func updateAffectedItems() {
        // When a favorite is being dropped into the tab list, show insertion feedback
        // in the tab list even though source is favorites
        if _originPosition?.collection == .favorites {
            if case let .convertToTab(_, targetPosition) = _dropTarget {
                // Favorite is targeting tab list - update tab list item offsets
                // Clear any favorites grid offsets since we're not in the grid anymore
                updateAffectedItemsForFavoriteToTab(targetPosition: targetPosition)
            } else {
                // Favorite staying in grid or no target - update grid offsets
                updateAffectedItemsForFavorites()
            }
        } else if case .convertToFavorite = _dropTarget {
            // Tab is being converted to a favorite - pull up tabs below the dragged item
            updateAffectedItemsForTabToFavorite()
        } else {
            updateAffectedItemsForTabList()
        }
    }

    /// Update affected items when a favorite is being inserted into the tab list.
    ///
    /// When a favorite is dropped into the tab list, we need to push ALL items
    /// at or after the insertion point, regardless of which section they're in.
    /// For example, inserting at pinned index 0 should push all pinned items
    /// AND all normal items down.
    ///
    /// Note: Grid shrink compensation is NOT applied during drag. Instead, it's
    /// handled at commit time via `_gridShrinkCompensation` to keep the empty
    /// row visible until the new tab is in place, then animate the pull-up.
    private func updateAffectedItemsForFavoriteToTab(targetPosition: ItemPosition) {
        let slotHeight = Constants.Layout.tabItemHeight + Constants.Layout.tabSpacing
        var newItemPushOffsets: [UUID: CGPoint] = [:]

        let pinnedItems = layoutManager.pinnedItems
        let normalItems = layoutManager.normalItems
        let isPinned = targetPosition.collection == .pinned
        let targetIndex = targetPosition.localIndex

        if isPinned {
            // Inserting into pinned section at local index `targetIndex`
            // Push pinned items from targetIndex onwards
            for (localIdx, item) in pinnedItems.enumerated() {
                if localIdx >= targetIndex {
                    newItemPushOffsets[item.id] = CGPoint(x: 0, y: slotHeight)
                }
            }
            // Also push ALL normal items (they're all after pinned)
            for item in normalItems {
                newItemPushOffsets[item.id] = CGPoint(x: 0, y: slotHeight)
            }
        } else {
            // Inserting into normal section at local index `targetIndex`
            // Push normal items from targetIndex onwards
            for (localIdx, item) in normalItems.enumerated() {
                if localIdx >= targetIndex {
                    newItemPushOffsets[item.id] = CGPoint(x: 0, y: slotHeight)
                }
            }
        }

        // Also update remaining favorites to fill the gap left by the dragged item
        if let layout = _favoritesGridLayout,
           case let .favorites(draggedLocalIndex) = _originPosition {
            let favorites = layoutManager.favoritesLayout

            if draggedLocalIndex >= 0, draggedLocalIndex < favorites.count {
                // Items after the dragged favorite shift backward by one in linear flow
                for (index, fav) in favorites.enumerated() {
                    guard index > draggedLocalIndex else { continue }

                    let currentPos = GridPosition.fromLinearIndex(index, columns: layout.columns)
                    let shiftedPos = GridPosition.fromLinearIndex(index - 1, columns: layout.columns)

                    let dx = CGFloat(shiftedPos.column - currentPos.column) * layout.horizontalStride
                    let dy = CGFloat(shiftedPos.row - currentPos.row) * layout.verticalStride

                    newItemPushOffsets[fav.id] = CGPoint(x: dx, y: dy)
                }
            }
        }

        itemPushOffsets = newItemPushOffsets
    }

    /// Update affected items when a tab is being converted to a favorite.
    ///
    /// When a tab is dropped into the favorites grid, items BELOW the dragged tab
    /// should pull UP to fill the gap (negative offset).
    private func updateAffectedItemsForTabToFavorite() {
        guard let origin = _originPosition else {
            itemPushOffsets = [:]
            return
        }

        let slotHeight = Constants.Layout.tabItemHeight + Constants.Layout.tabSpacing
        var newItemPushOffsets: [UUID: CGPoint] = [:]

        let allItems = getAllItems()
        let bounds = layoutManager.collectionBounds
        let originLocalIndex = localIndex(from: origin.globalIndex(bounds: bounds))

        // All items AFTER the dragged item should pull up to fill the gap
        for (localIdx, item) in allItems.enumerated() {
            // Skip the dragged item itself and its descendants
            if shouldSkipItem(item) {
                continue
            }

            // Items below the origin should pull UP (negative offset)
            if localIdx > originLocalIndex {
                newItemPushOffsets[item.id] = CGPoint(x: 0, y: -slotHeight)
            }
        }

        itemPushOffsets = newItemPushOffsets
    }

    /// Update affected items for favorites grid drag (2D offsets).
    private func updateAffectedItemsForFavorites() {
        guard let layout = _favoritesGridLayout,
              case let .favorites(localDraggedIndex) = _originPosition else {
            itemPushOffsets = [:]
            return
        }

        let favorites = layoutManager.favoritesLayout
        guard !favorites.isEmpty,
              localDraggedIndex >= 0,
              localDraggedIndex < favorites.count else {
            itemPushOffsets = [:]
            return
        }

        // Calculate target index using grid-aware logic (returns local index)
        let targetIndex = calculateFavoriteTargetIndexForOffsets(localDraggedIndex: localDraggedIndex)

        // Use the grid offset computation
        let offsets = computeGridOffsets(
            items: favorites,
            draggedIndex: localDraggedIndex,
            targetIndex: targetIndex,
            layout: layout,
        )

        itemPushOffsets = offsets
    }

    /// Calculate target index for favorites grid offset calculation.
    ///
    /// This is different from `calculateFavoriteTargetIndex()` in Targets.swift
    /// because it accounts for the dragged item's position in the array.
    ///
    /// - Parameter localDraggedIndex: Index of the dragged item within favorites array.
    /// - Returns: Target insertion index (local to favorites array).
    private func calculateFavoriteTargetIndexForOffsets(localDraggedIndex: Int) -> Int {
        guard let layout = _favoritesGridLayout else { return localDraggedIndex }

        let favorites = layoutManager.favoritesLayout
        guard !favorites.isEmpty else { return 0 }

        // Use the grid-aware calculation
        return calculateGridTargetIndex(
            at: overlayPosition,
            items: favorites,
            draggedIndex: localDraggedIndex,
            gridFrame: favoritesGridFrame,
            layout: layout,
        )
    }

    /// Update affected items for tab list drag (1D vertical offsets).
    ///
    /// Uses the shared `calculateDragTarget()` for consistent index calculations
    /// between visual feedback and drop targeting.
    ///
    /// ## Group Drag Behavior
    ///
    /// When dragging a group (header + visible descendants):
    /// - **UP**: Items above the header get pushed DOWN by the full group height.
    /// - **DOWN**: Items below the group's bottom get pushed UP by the full group height.
    ///   Threshold is based on single-item slots, not group slots.
    private func updateAffectedItemsForTabList() {
        // Check if this is a cross-collection move (pinned ↔ normal).
        // This includes drop zone cases where target section is empty.
        if let crossCollectionResult = updateAffectedItemsForCrossCollectionMove() {
            itemPushOffsets = crossCollectionResult
            return
        }

        // When in drop zone area (above tab list) without a cross-collection target,
        // the placeholders provide visual feedback. Don't apply push offsets.
        if _isDragAboveTabList {
            itemPushOffsets = [:]
            return
        }

        guard let calc = calculateDragTarget() else {
            itemPushOffsets = [:]
            return
        }

        // Offset amount is always the full group height (or single item height)
        let groupSlotHeight = calculateSlotHeight()
        let targetOffsetY = calc.isDraggingUp ? groupSlotHeight : -groupSlotHeight

        var newItemPushOffsets: [UUID: CGPoint] = [:]
        var processedGroups: Set<UUID> = []

        let allItems = getAllItems()

        for (localIdx, item) in allItems.enumerated() {
            if shouldSkipItem(item) {
                continue
            }

            // Use the shared calculation's effective indices for range checking
            let isInRange: Bool = if calc.isDraggingUp {
                localIdx >= calc.effectiveTarget && localIdx < calc.effectiveOrigin
            } else {
                localIdx > calc.effectiveOrigin && localIdx <= calc.effectiveTarget
            }

            guard isInRange else { continue }

            let offset = CGPoint(x: 0, y: targetOffsetY)
            newItemPushOffsets[item.id] = offset

            propagateOffsetToGroup(
                item: item,
                offset: offset,
                processedGroups: &processedGroups,
                newItemPushOffsets: &newItemPushOffsets,
            )
        }

        itemPushOffsets = newItemPushOffsets
    }

    /// Handle cross-collection moves (pinned ↔ normal).
    ///
    /// When dragging between pinned and normal sections, we need to:
    /// 1. Pull up items in the source collection (to fill the gap left by dragged item)
    /// 2. Push down items in the target collection (to make room for insertion)
    ///
    /// - Returns: Computed offsets if this is a cross-collection move, nil otherwise.
    private func updateAffectedItemsForCrossCollectionMove() -> [UUID: CGPoint]? {
        // Check if drop target indicates a cross-collection reorder
        guard case let .reorder(target) = _dropTarget else {
            return nil
        }

        guard let origin = _originPosition else {
            return nil
        }

        let sourceCollection = origin.collection
        let targetCollection = target.collection

        // Same-collection moves are handled by the regular tab list logic
        guard sourceCollection != targetCollection else {
            return nil
        }

        // Favorites are handled separately
        guard sourceCollection != .favorites, targetCollection != .favorites else {
            return nil
        }

        let pinnedItems = layoutManager.pinnedItems
        let normalItems = layoutManager.normalItems
        let slotHeight = calculateSlotHeight()
        var newItemPushOffsets: [UUID: CGPoint] = [:]

        // When targeting an EMPTY section (drop zone placeholder), we only need to
        // pull up items in the SOURCE section below the origin (to fill the gap).
        // The drop zone placeholder handles visual feedback for the target position.
        if targetCollection == .pinned, pinnedItems.isEmpty {
            // Normal → empty Pinned: pull up normal items below origin
            let originLocalIndex = origin.localIndex
            for (localIdx, item) in normalItems.enumerated() {
                if shouldSkipItem(item) { continue }
                if localIdx > originLocalIndex {
                    newItemPushOffsets[item.id] = CGPoint(x: 0, y: -slotHeight)
                }
            }
            return newItemPushOffsets
        }
        if targetCollection == .normal, normalItems.isEmpty {
            // Pinned → empty Normal: pull up pinned items below origin
            let originLocalIndex = origin.localIndex
            for (localIdx, item) in pinnedItems.enumerated() {
                if shouldSkipItem(item) { continue }
                if localIdx > originLocalIndex {
                    newItemPushOffsets[item.id] = CGPoint(x: 0, y: -slotHeight)
                }
            }
            return newItemPushOffsets
        }

        // When target section has items, handle full cross-collection logic.

        if sourceCollection == .pinned, targetCollection == .normal {
            // Pinned → Normal: The divider pulls up (dividerPushOffset = -slotHeight)
            // because the pinned section loses an item.
            //
            // For insertion at index 0: normal items stay in place, the gap between
            // pulled-up divider and first normal item IS the insertion space.
            //
            // For insertion at index N > 0: normal items BEFORE N must also pull up
            // to follow the divider (close the gap). Items at/after N stay in place,
            // creating the insertion gap between item N-1 and item N.
            let originLocalIndex = origin.localIndex
            let targetLocalIndex = target.localIndex

            // Pull up pinned items BELOW the origin (to fill the gap left by dragged item)
            for (localIdx, item) in pinnedItems.enumerated() {
                if shouldSkipItem(item) { continue }
                if localIdx > originLocalIndex {
                    newItemPushOffsets[item.id] = CGPoint(x: 0, y: -slotHeight)
                }
            }

            // Pull up normal items BEFORE the target index (to follow the divider).
            // Items at/after target stay in place - the gap IS the insertion space.
            for (localIdx, item) in normalItems.enumerated() {
                if shouldSkipItem(item) { continue }
                if localIdx < targetLocalIndex {
                    newItemPushOffsets[item.id] = CGPoint(x: 0, y: -slotHeight)
                }
            }

        } else if sourceCollection == .normal, targetCollection == .pinned {
            // Normal → Pinned: show insertion preview in pinned section
            // Also maintain push on normal items that the overlay passed through
            let originLocalIndex = origin.localIndex
            let targetLocalIndex = target.localIndex

            // Push down pinned items at/after target index (to make room for insertion)
            for (localIdx, item) in pinnedItems.enumerated() {
                if shouldSkipItem(item) { continue }
                if localIdx >= targetLocalIndex {
                    newItemPushOffsets[item.id] = CGPoint(x: 0, y: slotHeight)
                }
            }

            // Push down normal items ABOVE the origin (the ones the overlay passed through)
            // These were already pushed during same-collection drag, keep them pushed
            for (localIdx, item) in normalItems.enumerated() {
                if shouldSkipItem(item) { continue }
                if localIdx < originLocalIndex {
                    newItemPushOffsets[item.id] = CGPoint(x: 0, y: slotHeight)
                }
            }
        }

        return newItemPushOffsets
    }

    /// Check if an item should be skipped (dragged item or its descendants)
    func shouldSkipItem(_ item: TabListItem) -> Bool {
        guard let primaryDraggedItem else { return false }
        return item.id == primaryDraggedItem.id || _draggedItemExclusionSet.contains(item.id)
    }

    /// Determine if an item is in the affected range (between origin and target)
    func isItemInAffectedRange(
        index: Int,
        originIndex: Int,
        targetIndex: Int,
        isDraggingUp: Bool,
    ) -> Bool {
        if isDraggingUp {
            // Look at (targetIndex - 1) to allow smoothstep animation to start BEFORE centers cross
            index >= (targetIndex - 1) && index < originIndex
        } else {
            // Look at (targetIndex + 1) to allow smoothstep animation to start BEFORE centers cross
            index > originIndex && index <= (targetIndex + 1)
        }
    }

    /// Calculate the Y offset for an item with smooth approach transitions.
    ///
    /// Used for vertical tab list reordering. For 2D grid offsets, see `computeGridOffsets()`.
    func calculateItemOffsetY(
        index: Int,
        targetIndex: Int,
        itemFrame: CGRect,
        targetOffsetY: CGFloat,
        isDraggingUp: Bool,
    ) -> CGFloat {
        guard let origin = _originPosition else { return 0 }
        let bounds = layoutManager.collectionBounds
        let originIndex = origin.globalIndex(bounds: bounds)

        let overlayFrame = calculateCurrentOverlayFrame()

        // Check if item is already fully displaced (already passed, should stay displaced)
        let isAlreadyPassed: Bool = if isDraggingUp {
            index > targetIndex && index < originIndex
        } else {
            index < targetIndex && index > originIndex
        }

        if isAlreadyPassed {
            return targetOffsetY
        }

        let isCurrentOrNextTarget: Bool = if isDraggingUp {
            (index == targetIndex) || (index == targetIndex - 1)
        } else {
            (index == targetIndex) || (index == targetIndex + 1)
        }

        guard isCurrentOrNextTarget else {
            return 0
        }

        // Start moving items a bit after they overlap (negative lookahead)
        let lookAheadDistance: CGFloat = -itemFrame.height * 0.2

        let approachDistance: CGFloat = if isDraggingUp {
            overlayFrame.minY - itemFrame.maxY
        } else {
            itemFrame.minY - overlayFrame.maxY
        }

        if approachDistance >= lookAheadDistance {
            return 0
        } else if approachDistance <= -itemFrame.height {
            return targetOffsetY
        } else {
            let totalTransitionDistance = lookAheadDistance + itemFrame.height
            let distanceIntoTransition = lookAheadDistance - approachDistance

            let progress = min(1.0, max(0.0, distanceIntoTransition / totalTransitionDistance))
            return targetOffsetY * smoothstep(progress)
        }
    }

    /// Propagate offset to group members based on context
    func propagateOffsetToGroup(
        item: TabListItem,
        offset: CGPoint,
        processedGroups: inout Set<UUID>,
        newItemPushOffsets: inout [UUID: CGPoint],
    ) {
        guard let primaryDraggedItem else { return }

        let draggedTabGroupID: UUID? = primaryDraggedItem.tab?.groupID
        let isDraggingGroup = primaryDraggedItem.group != nil

        if let tab = item.tab,
           let groupID = tab.groupID,
           !processedGroups.contains(groupID) {
            // Case 1: Dragging a group - all members move together
            if isDraggingGroup {
                processedGroups.insert(groupID)
                for memberID in getDescendants(of: groupID) {
                    newItemPushOffsets[memberID] = offset
                }
            }
            // Case 2: Dragging within same group - let each item calculate independently
            // Case 3: Dragging from outside - let each tab calculate its own offset
            //         (allows threading tabs into groups)
        } else if let group = item.group, !processedGroups.contains(group.id) {
            processedGroups.insert(group.id)

            // Only propagate if dragging a group OR if dragging from within this group
            let isDraggingFromWithinThisGroup = draggedTabGroupID == group.id

            if isDraggingGroup {
                // Dragging a group - move all descendants together
                for descendantID in getDescendants(of: group.id) {
                    newItemPushOffsets[descendantID] = offset
                }
            } else if isDraggingFromWithinThisGroup {
                // Dragging from within - header moves independently
                // (allows ungrouping by moving above header)
            } else {
                // Dragging from outside - header moves independently
                // Descendants calculate their own offsets (allows insertion into group)
            }
        }
    }

    func calculateSlotHeight() -> CGFloat {
        if let groupBounds = _draggedGroupBounds {
            groupBounds.height + Constants.Layout.tabSpacing
        } else {
            Constants.Layout.tabItemHeight + Constants.Layout.tabSpacing
        }
    }
}
