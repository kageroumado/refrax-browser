import Algorithms
import Foundation
import SwiftUI

extension Sidebar.DragCoordinator {
    // MARK: - Private Helpers - Target Index Calculation

    /// Calculate target position based on drag offset relative to slot height.
    ///
    /// Uses index-based calculation rather than frame Y positions to avoid issues
    /// with stale frames in LazyVStack (items that scroll out of view keep old frames).
    ///
    /// Returns global index for internal use. Use `calculateTargetPosition()` for ItemPosition.
    func calculateTargetIndex() -> Int {
        guard let calc = calculateDragTarget() else { return globalIndexOffset }

        // Clear previous tracking
        _partialAnimationItems.removeAll()
        _crossedThresholdItems.removeAll()

        // Track which items are in the crossed range for animation
        let allItems = getAllItems()

        for (localIdx, item) in allItems.enumerated() {
            // Skip the dragged item and its descendants
            if item.id == primaryDraggedItem?.id || _draggedItemExclusionSet.contains(item.id) {
                continue
            }

            // Check if this item is in the affected range using the shared calculation
            let isInCrossedRange: Bool = if calc.isDraggingUp {
                localIdx >= calc.effectiveTarget && localIdx < calc.effectiveOrigin
            } else {
                localIdx > calc.effectiveOrigin && localIdx <= calc.effectiveTarget
            }

            if isInCrossedRange {
                _crossedThresholdItems.insert(item.id)
                _partialAnimationItems.insert(item.id)
                addGroupMembersToSet(&_crossedThresholdItems, for: item)
                addGroupMembersToSet(&_partialAnimationItems, for: item)
            }
        }

        return calc.headerTargetIndex
    }

    /// Convenience to convert `calculateTargetIndex()` result to `ItemPosition`.
    func calculateTargetPosition() -> ItemPosition? {
        let globalIndex = calculateTargetIndex()
        return ItemPosition.from(globalIndex: globalIndex, bounds: layoutManager.collectionBounds)
    }

    /// Iterate through items affected by drag and calculate their intersection progress
    func forEachAffectedItem(
        isDraggingUp: Bool,
        overlayFrame: CGRect,
        handler: (TabListItem, CGFloat) -> Void,
    ) {
        // Use cached exclusion set (calculated once at drag start)
        let excludedIDs = _draggedItemExclusionSet

        // Use group bounds if dragging a group, otherwise use item frame
        guard let originalFrame = _draggedItemOriginalFrame else { return }
        let draggedOriginalBounds = _draggedGroupBounds ?? originalFrame

        // Get sorted visible items for efficient searching
        let visibleItems = getVisibleItems()

        // Calculate search start position based on drag direction
        let searchStartY: CGFloat = isDraggingUp ? overlayFrame.minY : draggedOriginalBounds.maxY

        // Binary search to find first potentially affected item
        let startIdx = findFirstAffectedItemIndex(
            in: visibleItems,
            searchStartY: searchStartY,
            isDraggingUp: isDraggingUp,
        )

        // Iterate only through potentially affected items
        for validatedItem in visibleItems[startIdx...] {
            let item = validatedItem.item
            let itemFrame = validatedItem.frame

            // Early exit: items too far away can't be affected
            if shouldExitEarly(itemFrame: itemFrame, overlayFrame: overlayFrame, isDraggingUp: isDraggingUp) {
                break
            }

            // Skip excluded items (dragged item and its descendants)
            if excludedIDs.contains(item.id) {
                continue
            }

            // Check if this item should be considered based on drag direction
            if !shouldConsiderItem(itemFrame: itemFrame, draggedBounds: draggedOriginalBounds, isDraggingUp: isDraggingUp) {
                continue
            }

            // Calculate intersection progress
            let progress = calculateIntersectionProgress(
                itemFrame: itemFrame,
                overlayFrame: overlayFrame,
                isDraggingUp: isDraggingUp,
            )

            if progress > 0 {
                handler(item, progress)
            }
        }
    }

    func findFirstAffectedItemIndex(
        in visibleItems: [ValidatedItem],
        searchStartY: CGFloat,
        isDraggingUp: Bool,
    ) -> Int {
        // Find first item that might be affected by the drag
        // When dragging up: find items whose maxY reaches the overlay (maxY >= searchStartY)
        // When dragging down: find items whose minY is at or past the original position
        visibleItems.partitioningIndex { item in
            isDraggingUp ? item.frame.maxY >= searchStartY : item.frame.minY >= searchStartY
        }
    }

    func shouldExitEarly(itemFrame: CGRect, overlayFrame: CGRect, isDraggingUp: Bool) -> Bool {
        if isDraggingUp {
            // When dragging up, items are sorted top-to-bottom
            // Break when we reach items that start below the bottom of the overlay
            // (all remaining items in the sorted list will be even further below)
            itemFrame.minY > overlayFrame.maxY
        } else {
            // When dragging down, break when items are too far below
            itemFrame.maxY > overlayFrame.maxY + itemFrame.height
        }
    }

    func shouldConsiderItem(itemFrame: CGRect, draggedBounds: CGRect, isDraggingUp: Bool) -> Bool {
        if isDraggingUp {
            // When dragging up, only consider items above the TOP of the group
            itemFrame.midY < draggedBounds.minY
        } else {
            // When dragging down, only consider items below the BOTTOM of the group
            itemFrame.midY > draggedBounds.maxY
        }
    }

    func calculateIntersectionProgress(
        itemFrame: CGRect,
        overlayFrame: CGRect,
        isDraggingUp: Bool,
    ) -> CGFloat {
        if isDraggingUp {
            let overlapAmount = max(0, itemFrame.maxY - overlayFrame.minY)
            return min(1.0, overlapAmount / itemFrame.height)
        } else {
            let overlapAmount = max(0, overlayFrame.maxY - itemFrame.minY)
            return min(1.0, overlapAmount / itemFrame.height)
        }
    }

    /// Add all group members (tabs and descendants) to a set
    func addGroupMembersToSet(_ set: inout Set<UUID>, for item: TabListItem) {
        if let tab = item.tab, let groupID = tab.groupID {
            set.formUnion(getDescendants(of: groupID))
        } else if let group = item.group {
            set.formUnion(getDescendants(of: group.id))
        }
    }

    // MARK: - Private Helpers - Drop Target Detection

    /// Detect what would happen if user dropped at current location
    func detectDropTarget(at location: CGPoint) {
        guard let item = primaryDraggedItem,
              let origin = _originPosition,
              _draggedItemOriginalFrame != .zero
        else {
            clearDropTarget()
            return
        }

        let source = origin.collection

        // Check priorities in order (most specific to least specific).
        //
        // IMPORTANT: Favorites are in the scroll view's SAFE AREA (fixed at top),
        // while pinned/normal items are in the scroll CONTENT (scrollable).
        // When tabs scroll up, they can visually overlap with the favorites area.
        // The priority order ensures favorites always wins when there's overlap,
        // since favorites is visually "on top" and non-scrolling.

        // Priority 0: Drop zone area (above tab list)
        if let target = checkDropZoneTarget(at: location, item: item) {
            applyDropTargetResult(target)
            return
        }

        // Priority 1: Favorites Grid (when it exists)
        if let target = checkFavoritesGridTarget(at: location, item: item) {
            applyDropTargetResult(target)
            return
        }

        // Priority 2: Pin Section (when it exists)
        if let target = checkPinnedSectionTarget(at: location, item: item) {
            applyDropTargetResult(target)
            return
        }

        // Priority 3: Normal Section (for favorites being dropped into tab list)
        if let target = checkNormalSectionTarget(at: location, item: item) {
            applyDropTargetResult(target)
            return
        }

        // Priority 4: Group Header (add to group or nest group)
        if let target = checkGroupHeaderTarget(at: location, item: item) {
            applyDropTargetResult(target)
            return
        }

        // Priority 5: Tab List Reordering (within same collection)
        if let target = checkTabListReorderTarget(at: location, source: source, item: item) {
            applyDropTargetResult(target)
            return
        }

        clearDropTarget()
    }

    struct DropTargetResult {
        let target: DropTarget
        let zone: DropZone?
    }

    func clearDropTarget() {
        _dropTarget = .none
        activeDropZone = nil
        showDataStorageWarning = false
        updateOverlayMode(for: nil)
    }

    /// Apply a drop target result, updating all related state.
    private func applyDropTargetResult(_ result: DropTargetResult) {
        _dropTarget = result.target
        activeDropZone = result.zone
        updateDataStorageWarning()
        updateOverlayMode(for: result.zone)
    }

    /// Update overlay mode based on drop zone.
    ///
    /// - `.favoritesGrid` → tile mode (sized from grid layout)
    /// - Tab list zones → tab row mode (unless favorite is non-convertible)
    /// - `nil` → preserve current mode (dragged item's native form)
    private func updateOverlayMode(for zone: DropZone?) {
        // Check if dragged favorite can convert to tab (folders and appShortcuts cannot)
        let canConvertToTab: Bool = if let favorite = primaryDraggedItem?.favorite {
            favorite.isDraggableToTabs
        } else {
            true // Tabs and groups can always become tab rows
        }

        let newMode: OverlayMode
        switch zone {
        case .favoritesGrid:
            // Use actual tile size from grid layout if available, otherwise fall back to tab width
            let tileHeight = Constants.Layout.tabItemHeight * 1.5
            let tileSize = _favoritesGridLayout?.tileSize ?? CGSize(width: tabRowWidth, height: tileHeight)
            newMode = .tile(tileSize)

        case .pinnedSection, .normalSection, .groupHeader:
            // Only morph to tab row if the item can become a tab
            if canConvertToTab {
                newMode = .tabRow
            } else {
                // Non-convertible favorites stay as tiles even over tab zones
                return
            }

        case nil:
            // When no zone is active (in gaps between sections), infer mode from position.
            // If we're below the favorites grid, use tabRow mode since we're heading toward tabs.
            // If we're in/above favorites area, preserve current mode.
            if !favoritesGridFrame.isEmpty, overlayPosition.y > favoritesGridFrame.maxY, canConvertToTab {
                newMode = .tabRow
            } else {
                // Above or within favorites area with no specific zone - preserve current mode
                return
            }
        }

        // Only animate if mode actually changed
        if currentOverlayMode != newMode {
            // Reset click offset when transitioning between tab/tile modes.
            // Tab rows are much wider than tiles, so an offset that works for tabs
            // can place the tile completely outside the cursor. Centering on transition
            // ensures the overlay stays under the cursor in both modes.
            if _clickOffset != .zero {
                // Adjust overlay position to center under cursor by adding back the offset
                // we previously subtracted (overlayPosition = location - _clickOffset)
                overlayPosition = CGPoint(
                    x: overlayPosition.x + _clickOffset.x,
                    y: overlayPosition.y + _clickOffset.y,
                )
                _clickOffset = .zero
            }

            withAnimation(.easeInOut(duration: 0.15)) {
                currentOverlayMode = newMode
            }
        }
    }

    func checkDropZoneTarget(
        at location: CGPoint,
        item: DraggedItem,
    ) -> DropTargetResult? {
        guard _isDragAboveTabList else { return nil }

        let hasFavorites = !layoutManager.favoritesLayout.isEmpty
        let hasPinnedTabs = !layoutManager.pinnedItems.isEmpty

        // Priority 1: Existing favorites grid - use gap rounding for boundary detection
        // Note: favoritesGridFrame doesn't get pushed by tabListPushOffset since it's above the tab list
        if hasFavorites, !favoritesGridFrame.isEmpty {
            // Determine next section for gap calculation.
            // When pinned drop zone is showing, it's the "next section" below favorites.
            let nextSectionMinY: CGFloat
            if hasPinnedTabs {
                nextSectionMinY = _adjustedPinnedSectionFrame.minY
            } else if shouldShowPinDropZone {
                // Pinned drop zone position (below favorites grid)
                let dropZoneBaseOffset = DropZoneConstants.addressBarOffset + favoritesGridFrame.height + 12
                nextSectionMinY = sidebarBounds.minY + dropZoneBaseOffset
            } else {
                nextSectionMinY = _adjustedNormalSectionFrame.minY
            }

            // Check if in favorites grid OR upper half of gap below it
            let isInFavoritesGrid = favoritesGridFrame.contains(location)
            let isInUpperHalfOfGap: Bool
            if nextSectionMinY > favoritesGridFrame.maxY {
                let gapMidY = (favoritesGridFrame.maxY + nextSectionMinY) / 2
                isInUpperHalfOfGap = location.y >= favoritesGridFrame.maxY && location.y < gapMidY
            } else {
                isInUpperHalfOfGap = false
            }

            if isInFavoritesGrid || isInUpperHalfOfGap, case .tab = item {
                return DropTargetResult(
                    target: .convertToFavorite(mode: .liveFavorite),
                    zone: .favoritesGrid,
                )
            }
        }

        // Priority 2: Existing pinned section takes precedence over drop zone placeholders.
        // Use ADJUSTED frame that accounts for tabListPushOffset since the location
        // is in visual coordinates.
        if hasPinnedTabs, _adjustedPinnedSectionFrame.contains(location) {
            return checkPinnedSectionDrop(at: location, item: item, layoutManager: layoutManager)
        }

        // Priority 3 & 4: Drop zone placeholders
        // Drop zones are positioned at fixed offsets from the sidebar top (same as Sidebar.swift).
        // They appear below the address bar and any existing favorites grid.

        // Base offset from sidebar top: addressBarOffset (32) + favorites grid height if exists
        var dropZoneBaseOffset = DropZoneConstants.addressBarOffset
        if !layoutManager.favoritesLayout.isEmpty {
            dropZoneBaseOffset += favoritesGridFrame.height + 12
        }

        // Drop zones are positioned in global coordinates starting from sidebar bounds
        let dropZoneAreaTop = sidebarBounds.minY + dropZoneBaseOffset

        // Priority 3: Favorites drop zone placeholder
        if shouldShowFavoritesDropZone, case .tab = item {
            let favoritesZoneTop = dropZoneAreaTop
            let favoritesZoneBottom = favoritesZoneTop + DropZoneConstants.favoritesDropZoneTotalHeight

            if location.y >= favoritesZoneTop, location.y < favoritesZoneBottom {
                return DropTargetResult(
                    target: .convertToFavorite(mode: .liveFavorite),
                    zone: .favoritesGrid,
                )
            }
        }

        // Priority 4: Pin drop zone placeholder (with gap handling)
        if shouldShowPinDropZone {
            // Pinned zone is after favorites zone (if showing) or at the base otherwise
            let pinnedZoneTop: CGFloat = if shouldShowFavoritesDropZone {
                dropZoneAreaTop + DropZoneConstants.favoritesDropZoneTotalHeight
            } else {
                dropZoneAreaTop
            }
            let pinnedZoneBottom = pinnedZoneTop + DropZoneConstants.pinnedDropZoneTotalHeight

            // Check if in pinned drop zone
            let isInPinnedZone = location.y >= pinnedZoneTop && location.y < pinnedZoneBottom

            // Check if in lower half of gap FROM favorites (above pinned zone)
            // Favorites claims upper half, pinned claims lower half
            let isInLowerHalfOfGapFromFavorites: Bool
            if hasFavorites, !favoritesGridFrame.isEmpty, pinnedZoneTop > favoritesGridFrame.maxY {
                let gapMidY = (favoritesGridFrame.maxY + pinnedZoneTop) / 2
                isInLowerHalfOfGapFromFavorites = location.y >= gapMidY && location.y < pinnedZoneTop
            } else {
                isInLowerHalfOfGapFromFavorites = false
            }

            // Check if in upper half of gap TO normal section (below pinned zone)
            // Pinned claims upper half, normal claims lower half
            let isInUpperHalfOfGapToNormal: Bool
            let normalMinY = _adjustedNormalSectionFrame.minY
            if normalMinY > pinnedZoneBottom {
                let gapMidY = (pinnedZoneBottom + normalMinY) / 2
                isInUpperHalfOfGapToNormal = location.y >= pinnedZoneBottom && location.y < gapMidY
            } else {
                isInUpperHalfOfGapToNormal = false
            }

            if isInPinnedZone || isInLowerHalfOfGapFromFavorites || isInUpperHalfOfGapToNormal {
                return DropTargetResult(
                    target: .reorder(target: .pinned(localIndex: 0)),
                    zone: .pinnedSection,
                )
            }
        }

        return nil
    }

    func checkPinnedSectionDrop(
        at location: CGPoint,
        item: DraggedItem,
        layoutManager: Sidebar.LayoutManager,
    ) -> DropTargetResult? {
        switch item {
        case let .tab(tab):
            if !tab.isPinned {
                let localIndex = calculatePinnedTargetIndex(at: location, pinnedCount: layoutManager.pinnedItems.count)
                return DropTargetResult(
                    target: .reorder(target: .pinned(localIndex: localIndex)),
                    zone: .pinnedSection,
                )
            }
        case let .group(group):
            if group.isPinned != true {
                let localIndex = calculatePinnedTargetIndex(at: location, pinnedCount: layoutManager.pinnedItems.count)
                return DropTargetResult(
                    target: .reorder(target: .pinned(localIndex: localIndex)),
                    zone: .pinnedSection,
                )
            }
        case let .favorite(favorite):
            // Only allow draggable favorites (live favorites and shortcuts) to be dropped on tab list
            guard favorite.isDraggableToTabs else { return nil }
            if let windowState, let activeSpace = windowState.activeSpace {
                let localIndex = calculatePinnedTargetIndex(at: location, pinnedCount: layoutManager.pinnedItems.count)
                return DropTargetResult(
                    target: .convertToTab(targetSpace: activeSpace, targetPosition: .pinned(localIndex: localIndex)),
                    zone: .pinnedSection,
                )
            }
        }

        return nil
    }

    func checkFavoritesGridTarget(at location: CGPoint, item: DraggedItem) -> DropTargetResult? {
        guard !favoritesGridFrame.isEmpty else { return nil }

        // Determine the next section below favorites for gap calculation
        let hasPinned = !layoutManager.pinnedItems.isEmpty
        let nextSectionMinY: CGFloat = if hasPinned {
            _adjustedPinnedSectionFrame.minY
        } else {
            _adjustedNormalSectionFrame.minY
        }

        // Check if location is in favorites grid OR in the upper half of the gap
        // between favorites and the next section. This rounding prevents dead zones.
        let isInFavoritesGrid = favoritesGridFrame.contains(location)
        let isInUpperHalfOfGap: Bool
        if nextSectionMinY > favoritesGridFrame.maxY {
            let gapMidY = (favoritesGridFrame.maxY + nextSectionMinY) / 2
            isInUpperHalfOfGap = location.y >= favoritesGridFrame.maxY && location.y < gapMidY
        } else {
            isInUpperHalfOfGap = false
        }

        guard isInFavoritesGrid || isInUpperHalfOfGap else { return nil }

        switch item {
        case .tab:
            return DropTargetResult(
                target: .convertToFavorite(mode: .liveFavorite),
                zone: .favoritesGrid,
            )
        case .favorite:
            let targetIndex = calculateFavoriteTargetIndex(at: location)
            return DropTargetResult(
                target: .reorder(target: .favorites(localIndex: targetIndex)),
                zone: .favoritesGrid,
            )
        case .group:
            return nil
        }
    }

    /// Calculate target index for favorites grid based on location.
    func calculateFavoriteTargetIndex(at location: CGPoint) -> Int {
        let favorites = layoutManager.favoritesLayout
        guard !favorites.isEmpty else { return 0 }

        // Use actual layout info if available
        if let layout = _favoritesGridLayout {
            // Convert location to grid-local coordinates
            let localX = location.x - favoritesGridFrame.minX
            let localY = location.y - favoritesGridFrame.minY

            // Calculate which cell the cursor is in
            let col = max(0, min(layout.columns - 1, Int(localX / layout.horizontalStride)))
            let row = max(0, Int(localY / layout.verticalStride))

            let index = row * layout.columns + col
            return min(index, favorites.count)
        }

        // Fallback: estimate layout when actual info isn't available
        let gridWidth = favoritesGridFrame.width
        let gridHeight = favoritesGridFrame.height

        guard gridWidth > 0, gridHeight > 0 else { return 0 }

        // Tiles have fixed height (1.5x tab height = 54pt) and min width (same as height).
        // With a single tile, it spans full width like tabs.
        let tileHeight = Constants.Layout.tabItemHeight * 1.5
        let minTileWidth = tileHeight
        let spacing: CGFloat = 8

        // Estimate columns based on min tile width
        let estimatedColumns = max(1, Int((gridWidth + spacing) / (minTileWidth + spacing)))
        let rowHeight = tileHeight + spacing

        let localY = location.y - favoritesGridFrame.minY
        let localX = location.x - favoritesGridFrame.minX

        let row = max(0, Int(localY / rowHeight))
        let col = max(0, Int(localX / (gridWidth / CGFloat(estimatedColumns))))

        let index = row * estimatedColumns + col
        return min(index, favorites.count)
    }

    /// Computes the effective location for cross-section boundary checks.
    ///
    /// For groups, the boundary check uses:
    /// - Moving UP: header position (top of group)
    /// - Moving DOWN: bottom of group
    ///
    /// This matches how affected items are calculated.
    private func effectiveLocation(for location: CGPoint, item: DraggedItem) -> CGPoint {
        guard case .group = item else { return location }

        let isMovingUp = currentOffset < 0
        let groupHeight = calculateSlotHeight()

        let result: CGPoint
        if isMovingUp {
            // Moving UP: use header position (top of group)
            let headerY = location.y - _clickOffset.y
            result = CGPoint(x: location.x, y: headerY)
        } else {
            // Moving DOWN: use bottom of group
            let bottomY = location.y + (groupHeight - _clickOffset.y)
            result = CGPoint(x: location.x, y: bottomY)
        }

        return result
    }

    func checkPinnedSectionTarget(
        at location: CGPoint,
        item: DraggedItem,
    ) -> DropTargetResult? {
        guard !layoutManager.pinnedItems.isEmpty else { return nil }

        // For groups moving down, use bottom of group for boundary checks
        let effectiveLoc = effectiveLocation(for: location, item: item)

        let adjustedPinned = _adjustedPinnedSectionFrame
        let adjustedNormal = _adjustedNormalSectionFrame

        // Check if location is in pinned section OR in the adjacent gap halves.
        // For tabs and groups (not favorites), also check:
        // - Lower half of gap ABOVE pinned (between favorites and pinned)
        // - Upper half of gap BELOW pinned (between pinned and normal)
        // Favorites have their own gap handling in checkNormalSectionTarget.
        let isInPinnedSection = adjustedPinned.contains(effectiveLoc)

        // Gap below pinned (between pinned and normal)
        let isInUpperHalfOfGapBelow: Bool
        if case .favorite = item {
            isInUpperHalfOfGapBelow = false
        } else if !adjustedPinned.isEmpty, !adjustedNormal.isEmpty {
            let gapMidY = (adjustedPinned.maxY + adjustedNormal.minY) / 2
            isInUpperHalfOfGapBelow = effectiveLoc.y >= adjustedPinned.maxY && effectiveLoc.y < gapMidY
        } else {
            isInUpperHalfOfGapBelow = false
        }

        // Gap above pinned (between favorites and pinned)
        let isInLowerHalfOfGapAbove: Bool
        if case .favorite = item {
            isInLowerHalfOfGapAbove = false
        } else if !favoritesGridFrame.isEmpty, !adjustedPinned.isEmpty, adjustedPinned.minY > favoritesGridFrame.maxY {
            let gapMidY = (favoritesGridFrame.maxY + adjustedPinned.minY) / 2
            isInLowerHalfOfGapAbove = effectiveLoc.y >= gapMidY && effectiveLoc.y < adjustedPinned.minY
        } else {
            isInLowerHalfOfGapAbove = false
        }

        guard isInPinnedSection || isInUpperHalfOfGapBelow || isInLowerHalfOfGapAbove else { return nil }

        switch item {
        case let .tab(tab):
            if !tab.isPinned {
                let localIndex = calculatePinnedTargetIndex(at: location, pinnedCount: layoutManager.pinnedItems.count)
                return DropTargetResult(
                    target: .reorder(target: .pinned(localIndex: localIndex)),
                    zone: .pinnedSection,
                )
            }
        case let .favorite(favorite):
            // Only allow draggable favorites (live favorites and shortcuts) to be dropped on tab list
            guard favorite.isDraggableToTabs else {
                return nil
            }
            if let windowState, let activeSpace = windowState.activeSpace {
                let localIndex = calculatePinnedTargetIndex(at: location, pinnedCount: layoutManager.pinnedItems.count)
                return DropTargetResult(
                    target: .convertToTab(targetSpace: activeSpace, targetPosition: .pinned(localIndex: localIndex)),
                    zone: .pinnedSection,
                )
            }
        case let .group(group):
            if group.isPinned != true {
                let localIndex = calculatePinnedTargetIndex(at: location, pinnedCount: layoutManager.pinnedItems.count)
                return DropTargetResult(
                    target: .reorder(target: .pinned(localIndex: localIndex)),
                    zone: .pinnedSection,
                )
            }
        }

        return nil
    }

    /// Checks if an item is being dropped into the normal section.
    ///
    /// Handles:
    /// - Favorites being converted to tabs
    /// - Pinned tabs/groups being unpinned
    ///
    /// Uses frame-based detection to calculate the target position within normal items.
    func checkNormalSectionTarget(
        at location: CGPoint,
        item: DraggedItem,
    ) -> DropTargetResult? {
        // For groups moving down, use bottom of group for boundary checks
        let effectiveLoc = effectiveLocation(for: location, item: item)

        // Use adjusted frame that accounts for tabListPushOffset
        let adjustedPinned = _adjustedPinnedSectionFrame
        let adjustedNormal = _adjustedNormalSectionFrame

        // Check if location is in the normal section area using gap midpoint rounding.
        // Normal section claims the lower half of the gap above it.
        let isInNormalArea: Bool
        if !adjustedPinned.isEmpty, !adjustedNormal.isEmpty {
            // Gap between pinned and normal - use midpoint
            let gapMidY = (adjustedPinned.maxY + adjustedNormal.minY) / 2
            isInNormalArea = effectiveLoc.y >= gapMidY
        } else if !adjustedPinned.isEmpty {
            // Pinned exists but normal frame unavailable - below pinned
            isInNormalArea = effectiveLoc.y > adjustedPinned.maxY
        } else if shouldShowPinDropZone, !adjustedNormal.isEmpty {
            // No pinned items but pinned DROP ZONE is showing - use drop zone bottom for gap.
            // Calculate pinned drop zone bottom position.
            var dropZoneBaseOffset = DropZoneConstants.addressBarOffset
            if !favoritesGridFrame.isEmpty {
                dropZoneBaseOffset += favoritesGridFrame.height + 12
            }
            let pinnedZoneTop: CGFloat = if shouldShowFavoritesDropZone {
                sidebarBounds.minY + dropZoneBaseOffset + DropZoneConstants.favoritesDropZoneTotalHeight
            } else {
                sidebarBounds.minY + dropZoneBaseOffset
            }
            let pinnedZoneBottom = pinnedZoneTop + DropZoneConstants.pinnedDropZoneTotalHeight
            let gapMidY = (pinnedZoneBottom + adjustedNormal.minY) / 2
            isInNormalArea = effectiveLoc.y >= gapMidY
        } else if !favoritesGridFrame.isEmpty, !adjustedNormal.isEmpty {
            // No pinned, gap between favorites and normal - use midpoint
            let gapMidY = (favoritesGridFrame.maxY + adjustedNormal.minY) / 2
            isInNormalArea = effectiveLoc.y >= gapMidY
        } else if !favoritesGridFrame.isEmpty {
            // Favorites exist but normal frame unavailable - below favorites
            isInNormalArea = effectiveLoc.y > favoritesGridFrame.maxY
        } else {
            // No pinned or favorites sections - anywhere is valid
            isInNormalArea = true
        }

        guard isInNormalArea else { return nil }

        switch item {
        case let .favorite(favorite):
            // Favorite being dropped into normal section - convert to tab
            // Only allow draggable favorites (live favorites and shortcuts)
            guard favorite.isDraggableToTabs else {
                return nil
            }
            guard let windowState, let activeSpace = windowState.activeSpace else {
                return nil
            }
            let targetIndex = calculateNormalTargetIndex(at: location)
            return DropTargetResult(
                target: .convertToTab(targetSpace: activeSpace, targetPosition: .normal(localIndex: targetIndex)),
                zone: .normalSection,
            )

        case let .tab(tab):
            // Pinned tab being dropped into normal section - unpin it
            if tab.isPinned {
                let localIndex = calculateNormalTargetIndex(at: location)
                return DropTargetResult(
                    target: .reorder(target: .normal(localIndex: localIndex)),
                    zone: .normalSection,
                )
            }
            return nil

        case let .group(group):
            // Pinned group being dropped into normal section - unpin it
            if group.isPinned == true {
                let localIndex = calculateNormalTargetIndex(at: location)
                return DropTargetResult(
                    target: .reorder(target: .normal(localIndex: localIndex)),
                    zone: .normalSection,
                )
            }
            return nil
        }
    }

    /// Calculate target index for normal section based on Y location.
    ///
    /// Uses computed frames from section geometry instead of NSView frames.
    /// NSView frames become unreliable during cross-section drags when layout shifts
    /// cause most items to be excluded from `getVisibleItems()`.
    func calculateNormalTargetIndex(at location: CGPoint) -> Int {
        let normalItems = layoutManager.normalItems
        guard !normalItems.isEmpty else { return 0 }

        // Convert visual location to static space for comparison with computed frames.
        // For PINNED→NORMAL cross-collection moves, we also need to account for
        // dividerPushOffset since the divider pulls up, creating visual space at
        // the top of normal section that doesn't exist in static coordinates.
        var staticLocation = locationInStaticSpace(location)
        if _originPosition?.collection == .pinned {
            // dividerPushOffset is negative (pull up), so subtracting it adds to Y,
            // which correctly maps the visual position to static item positions.
            staticLocation.y -= dividerPushOffset
        }

        // Use single-item stride (not group height) for slot calculation.
        // We're calculating which item slot the cursor is in, not the dragged item's size.
        let itemHeight = Constants.Layout.tabItemHeight
        let spacing = Constants.Layout.tabSpacing
        let slotStride = itemHeight + spacing
        let sectionTop = computedNormalSectionFrame.minY

        // Calculate which slot the cursor is in relative to section top.
        let relativeY = staticLocation.y - sectionTop

        // Insert at index N where cursor is past item[N-1]'s midpoint.
        // Adding spacing/2 provides rounding to nearest slot boundary.
        let insertIndex = max(0, Int((relativeY + spacing / 2) / slotStride))

        // Clamp to valid range (0 to count)
        let result = min(insertIndex, normalItems.count)

        return result
    }

    func checkGroupHeaderTarget(
        at location: CGPoint,
        item: DraggedItem,
    ) -> DropTargetResult? {
        guard let groupID = detectGroupHover(at: location) else {
            return nil
        }

        if case .group = item {
            return DropTargetResult(
                target: .nestGroup(parentGroupID: groupID),
                zone: .groupHeader(groupID),
            )
        } else if case .tab = item {
            return DropTargetResult(
                target: .addToGroup(groupID: groupID),
                zone: .groupHeader(groupID),
            )
        }

        return nil
    }

    func checkTabListReorderTarget(
        at location: CGPoint,
        source: SidebarCollection,
        item: DraggedItem,
    ) -> DropTargetResult? {
        // Check which section the overlay is in
        let adjustedPinned = _adjustedPinnedSectionFrame
        let adjustedNormal = _adjustedNormalSectionFrame

        let isInPinnedSection = !adjustedPinned.isEmpty && location.y >= adjustedPinned.minY && location.y < adjustedPinned.maxY
        let isInNormalSection = !adjustedNormal.isEmpty && location.y >= adjustedNormal.minY

        // Handle gaps gracefully by rounding to nearest section.
        // Sections from top to bottom: favorites → pinned → newtab → normal

        // Gap between favorites and pinned: treat as "insert at top of pinned"
        let isInGapAbovePinned = !adjustedPinned.isEmpty
            && location.y < adjustedPinned.minY
            && location.y > favoritesGridFrame.maxY

        // Gap between pinned and normal (where new tab button lives): round to nearest
        let isInGapBetweenPinnedAndNormal = !adjustedPinned.isEmpty
            && !adjustedNormal.isEmpty
            && location.y >= adjustedPinned.maxY
            && location.y < adjustedNormal.minY

        // Gap between favorites and normal when no pinned section exists
        let isInGapBetweenFavoritesAndNormal = adjustedPinned.isEmpty
            && !adjustedNormal.isEmpty
            && !favoritesGridFrame.isEmpty
            && location.y > favoritesGridFrame.maxY
            && location.y < adjustedNormal.minY

        guard isInPinnedSection || isInNormalSection || isInGapAbovePinned || isInGapBetweenPinnedAndNormal || isInGapBetweenFavoritesAndNormal else {
            // Location is outside all known sections (above favorites or below normal)
            return nil
        }

        // Handle gap above pinned: insert at top of pinned
        if isInGapAbovePinned {
            return handleTabListReorder(
                source: source,
                targetCollection: .pinned,
                hoveredIndex: layoutManager.collectionBounds.pinned.lowerBound,
                item: item,
            )
        }

        // Handle gap between pinned and normal (where new tab button lives):
        // Round to the nearest section based on position within the gap.
        // This allows targeting the END of pinned (by being in upper half of gap)
        // or START of normal (by being in lower half of gap).
        if isInGapBetweenPinnedAndNormal {
            let gapMidY = (adjustedPinned.maxY + adjustedNormal.minY) / 2
            if location.y < gapMidY {
                // Upper half of gap: insert at END of pinned section
                return handleTabListReorder(
                    source: source,
                    targetCollection: .pinned,
                    hoveredIndex: layoutManager.collectionBounds.pinned.upperBound,
                    item: item,
                )
            } else {
                // Lower half of gap: insert at START of normal section
                return handleTabListReorder(
                    source: source,
                    targetCollection: .normal,
                    hoveredIndex: layoutManager.collectionBounds.normal.lowerBound,
                    item: item,
                )
            }
        }

        // Handle gap between favorites and normal (when no pinned section exists)
        if isInGapBetweenFavoritesAndNormal {
            // Always insert at start of normal since there's no pinned section
            return handleTabListReorder(
                source: source,
                targetCollection: .normal,
                hoveredIndex: layoutManager.collectionBounds.normal.lowerBound,
                item: item,
            )
        }

        // Calculate which item we're hovering over based on offset
        let hoveredIndex = calculateTargetIndex()

        // Ensure we have a valid collection for the hover location
        let bounds = layoutManager.collectionBounds
        guard let targetCollection = bounds.collection(for: hoveredIndex) else {
            return nil
        }

        // Update nesting level for visual feedback
        updateDraggedItemNestingLevel(hoveredIndex: hoveredIndex)

        // Reorder within collection (or cross-collection move)
        let result = handleTabListReorder(
            source: source,
            targetCollection: targetCollection,
            hoveredIndex: hoveredIndex,
            item: item,
        )

        return result
    }

    func handleTabListReorder(
        source: SidebarCollection,
        targetCollection: SidebarCollection,
        hoveredIndex: Int,
        item: DraggedItem,
    ) -> DropTargetResult? {
        // Determine the zone for overlay mode changes
        let zone: DropZone? = switch targetCollection {
        case .pinned: .pinnedSection
        case .normal: .normalSection
        case .favorites: nil
        }

        // Convert hoveredIndex (global) to ItemPosition
        let bounds = layoutManager.collectionBounds
        guard let targetPosition = ItemPosition.from(globalIndex: hoveredIndex, bounds: bounds) else {
            return nil
        }

        switch (source, targetCollection) {
        case (.pinned, .pinned), (.normal, .normal):
            // Same collection reorder
            return DropTargetResult(
                target: .reorder(target: targetPosition),
                zone: zone,
            )

        case (.pinned, .normal), (.normal, .pinned):
            // Cross-section move (handles pin state internally)
            return DropTargetResult(
                target: .reorder(target: targetPosition),
                zone: zone,
            )

        case (.pinned, .favorites), (.normal, .favorites):
            // Tab being dragged to favorites - should be caught by checkFavoritesGridTarget
            if case .tab = item {
                return DropTargetResult(
                    target: .convertToFavorite(mode: .liveFavorite),
                    zone: .favoritesGrid,
                )
            }

        case (.favorites, _):
            // Favorites are handled by checkPinnedSectionTarget and checkNormalSectionTarget
            return nil
        }

        return nil
    }

    // MARK: - Private Helpers - Pinned Target Calculation

    /// Calculate target index for pinning based on Y location within pinned section.
    ///
    /// Uses computed frames derived from scroll position and layout geometry.
    /// This is reliable even during cross-section drags when layout shifts
    /// cause items to lose their valid NSView frames.
    ///
    /// Note: Uses single-item slot height (not group height) because we're calculating
    /// insertion position based on which item slot the cursor is in, not the dragged
    /// item's size. This ensures consistent behavior for both tabs and groups.
    ///
    /// - Returns: **Local** index within pinned items (0 to pinnedCount).
    ///   For `.reorder` targets, callers must convert to global by adding `globalIndexOffset`.
    ///   For `.convertToTab` targets, use as-is since `convertFavoriteToTab` expects local index.
    func calculatePinnedTargetIndex(at location: CGPoint, pinnedCount: Int) -> Int {
        guard pinnedCount > 0 else { return 0 }

        // Convert visual location to static space for comparison with computed frames
        let staticLocation = locationInStaticSpace(location)

        // Use single-item stride (not group height) for slot calculation
        let itemHeight = Constants.Layout.tabItemHeight
        let spacing = Constants.Layout.tabSpacing
        let slotStride = itemHeight + spacing
        let sectionTop = computedPinnedSectionFrame.minY

        // Calculate which slot the cursor is in relative to section top.
        let relativeY = staticLocation.y - sectionTop

        // Insert at index N where cursor is past item[N-1]'s midpoint.
        // Adding spacing/2 provides rounding to nearest slot boundary.
        let insertIndex = max(0, Int((relativeY + spacing / 2) / slotStride))

        // Clamp to valid range (0 to count)
        return min(insertIndex, pinnedCount)
    }

    // MARK: - Private Helpers - Group Detection

    /// Detect if hovering over a group header
    func detectGroupHover(at location: CGPoint) -> UUID? {
        guard primaryDraggedItem != nil else { return nil }

        // Convert to static space for comparison with item frames
        let staticLocation = locationInStaticSpace(location)
        let targetY = staticLocation.y
        let tolerance = DragConstants.groupHoverTolerance

        // Binary search for groups near location
        let visibleItems = getVisibleItems()
        // Find first item that might contain target (maxY extends to or past search area)
        let searchStart = visibleItems.partitioningIndex { $0.frame.maxY >= targetY - tolerance }

        for validatedItem in visibleItems[searchStart...] {
            // Early exit if we've gone past the location
            if validatedItem.frame.minY > targetY + tolerance {
                break
            }

            guard case let .group(group) = validatedItem.item,
                  !_draggedItemExclusionSet.contains(group.id) else {
                continue
            }

            let expandedFrame = validatedItem.frame.insetBy(dx: 0, dy: -tolerance)

            if expandedFrame.contains(staticLocation) {
                // Additional validation: prevent creating cycles
                if case let .group(draggedGroup) = primaryDraggedItem {
                    // Check if target group is a descendant of dragged group
                    if getDescendants(of: draggedGroup.id).contains(group.id) {
                        continue // would create cycle
                    }
                }

                return group.id
            }
        }

        return nil
    }

    // MARK: - Data Storage Warning

    /// Updates the data storage warning based on current drag state.
    ///
    /// Shows a warning when dragging between zones with different data storage:
    /// - Favorite → Space with non-global data store mode
    /// - Tab from space with non-global data store mode → Favorites grid
    ///
    /// Favorites always use the default (shared) data store, so any transfer
    /// to/from a separate or private data store requires a reload.
    func updateDataStorageWarning() {
        guard let item = primaryDraggedItem else {
            showDataStorageWarning = false
            return
        }

        switch item {
        case .favorite:
            // Favorite being dragged to tab list
            // Check if target space has different data storage
            if case .convertToTab = _dropTarget,
               let activeSpace = windowState?.activeSpace {
                showDataStorageWarning = !activeSpace.dataStoreMode.isGlobal
            } else {
                showDataStorageWarning = false
            }

        case let .tab(tab):
            // Tab being dragged to favorites grid
            // Check if source space has different data storage
            if activeDropZone == .favoritesGrid,
               let sourceSpace = tab.space {
                showDataStorageWarning = !sourceSpace.dataStoreMode.isGlobal
            } else {
                showDataStorageWarning = false
            }

        case .group:
            // Groups cannot be converted to favorites
            showDataStorageWarning = false
        }
    }
}
