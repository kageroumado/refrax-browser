import Foundation
import SwiftUI

extension Sidebar.DragCoordinator {
    // MARK: - Private Helpers - Commit Animation

    struct CommitAnimationParameters {
        let slotHeight: CGFloat
        let targetOffset: CGFloat
    }

    func calculateCommitAnimationParameters() -> CommitAnimationParameters {
        let slotHeight = calculateSlotHeight()
        let isDraggingUp = currentOffset < 0
        let targetOffset = isDraggingUp ? slotHeight : -slotHeight

        return CommitAnimationParameters(
            slotHeight: slotHeight,
            targetOffset: targetOffset,
        )
    }

    func applyCommitAnimationAdjustments(
        params: CommitAnimationParameters,
        itemsWithPartialAnimation: Set<UUID>,
        itemsThatCrossed: Set<UUID>,
    ) {
        // Immediately clear offsets for items not involved in animation
        for itemID in itemPushOffsets.keys {
            if !itemsWithPartialAnimation.contains(itemID), !itemsThatCrossed.contains(itemID) {
                itemPushOffsets[itemID] = .zero
            }
        }

        // Items that crossed threshold had their data position move by targetOffset
        // Adjust their offset to maintain visual continuity
        // Note: targetOffset is a Y offset for tab list vertical reordering
        for itemID in itemsThatCrossed {
            if let currentOffset = itemPushOffsets[itemID] {
                // Formula: adjustedOffset = currentOffset - targetOffset (Y axis only for tabs)
                itemPushOffsets[itemID] = CGPoint(
                    x: currentOffset.x,
                    y: currentOffset.y - params.targetOffset,
                )
            }
        }
    }

    func animateToFinalPositions() {
        // Use pre-calculated position if available (calculated before commit),
        // otherwise calculate now (for cases like cancel where no commit happened)
        let targetOverlayPosition: CGPoint = _preCalculatedTargetPosition ?? calculateTargetOverlayPosition()

        // Note: For staged animation (when _dropZonePushCompensation > 0), the target position
        // from effectivePinnedFrame is already in visual coordinates (where the drop zone is).
        // We do NOT add compensation here - the overlay should stay approximately where it is.
        // Phase 2 will animate everything up together.

        // IMPORTANT: Clear offsets IMMEDIATELY (outside animation block).
        // During drag, offsets are a PREVIEW of the final position.
        // After commit, SwiftUI's natural layout puts elements in the correct place.
        // If we animate offsets to 0, we get double movement:
        //   1. SwiftUI layout moves element to new position (with offset still applied = wrong)
        //   2. Offset animates to 0 (element moves again to correct position)
        // By clearing immediately, the element goes directly to the correct position.
        activeDropZone = nil
        itemPushOffsets.removeAll()

        // Drop zones stay visible during overlay animation via _dropZonePushCompensation.
        // For staged animations (compensation > 0), tabListPushOffset reads from compensation.
        // Clear _dropZonesActive so shouldShow* return false, but tab list stays pushed via compensation.
        _dropZonesActive = false
        let hasStaged: Bool = switch _dropTarget {
        case .reorder: _dropZonePushCompensation > 0
        default: false
        }

        // Phase 1: Animate overlay to target position (tab list stays pushed)
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            currentOffset = 0

            // Animate grid shrink compensation to zero (smooth pull-up for favorites)
            _gridShrinkCompensation = 0
            if !hasStaged {
                _dropZonePushCompensation = 0
            }

            // Animate overlay to target position
            overlayPosition = targetOverlayPosition
        }

        // Phase 2: Animate tab list back up (staged animation for drop zones)
        // Only needed when drop zones were showing (compensation > 0)
        if hasStaged {
            // Phase 2a: Wait for phase 1 (overlay animation) to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [self] in
                // Hide overlay and reveal real items (without animation due to isAnimatingReturn)
                isDragging = false
                draggedItems.removeAll()
                followerItems.removeAll()
                hiddenFollowerIDs.removeAll()

                // Phase 2b: Let item settle into position before moving list
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [self] in
                    // Phase 2c: Animate tab list up
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        _dropZonePushCompensation = 0
                    }
                }
            }
        }
    }

    /// Calculate where the overlay should animate to based on drop target.
    ///
    /// - `.reorder`: Animate to the new slot position (1D for tabs, 2D for favorites)
    /// - `.none`: Animate back to original position (cancel)
    /// - Conversions: Animate to the NEW position in target collection
    func calculateTargetOverlayPosition() -> CGPoint {
        let originalFrame = _draggedItemOriginalFrame ?? .zero
        let originalCenter = CGPoint(x: originalFrame.midX, y: originalFrame.midY)

        switch _dropTarget {
        case let .reorder(target):
            // Handle favorites grid (2D) vs tab list (1D)
            if target.collection == .favorites, let layout = _favoritesGridLayout {
                return calculateFavoritesTargetPosition(
                    targetPosition: target,
                    layout: layout,
                    originalCenter: originalCenter,
                )
            }

            // Check if this is a cross-collection move (pinned ↔ normal)
            let sourceCollection = _originPosition?.collection
            let isCrossCollectionMove = (target.collection == .pinned && sourceCollection == .normal) ||
                (target.collection == .normal && sourceCollection == .pinned)

            if isCrossCollectionMove {
                // For cross-collection moves, use frame-based calculation
                // because the divider gap makes index math incorrect
                return calculateCrossCollectionTargetPosition(
                    targetPosition: target,
                    originalCenter: originalCenter,
                )
            }

            // Same-collection reorder: simple index delta calculation
            // Use tab slot height (not group height) because indices correspond to
            // individual items (tabs/group headers), not the dragged item's visual size
            guard let origin = _originPosition else { return originalCenter }
            let slotHeight = Constants.Layout.tabItemHeight + Constants.Layout.tabSpacing
            let indexDelta = target.localIndex - origin.localIndex

            // If no movement, return to original position
            guard indexDelta != 0 else { return originalCenter }

            // Calculate target Y from original position + index delta
            // Use original frame's X (not current overlay X which may drift during drag)
            let targetY = originalFrame.midY + CGFloat(indexDelta) * slotHeight

            return CGPoint(x: originalFrame.midX, y: targetY)

        case .none:
            // No valid drop target - animate back to original position
            return originalCenter

        case let .convertToFavorite(mode):
            // Animate to where the new favorite will appear in the grid
            if let layout = _favoritesGridLayout {
                let targetIndex = calculateFavoriteInsertIndex(mode: mode)
                return calculateFavoritesTargetPosition(
                    targetPosition: .favorites(localIndex: targetIndex),
                    layout: layout,
                    originalCenter: originalCenter,
                )
            }
            // Empty favorites - calculate target using static position (no push offset)
            // The grid will appear at: addressBar height (32) + VStack spacing (12) = 44pt from sidebar top
            let gridTop = sidebarBounds.minY + Constants.AddressBar.height + 12
            let tileHeight = DropZoneConstants.favoritesTileHeight
            return CGPoint(
                x: sidebarBounds.midX,
                y: gridTop + tileHeight / 2,
            )

        case let .convertToTab(_, targetPosition):
            // Animate to where the new tab will appear in the tab list
            let isPinned = targetPosition.collection == .pinned
            let items = isPinned ? layoutManager.pinnedItems : layoutManager.normalItems
            if targetPosition.localIndex < items.count,
               let frame = computedItemFrame(for: items[targetPosition.localIndex].id) {
                return CGPoint(x: frame.midX, y: frame.midY)
            } else if let lastItem = items.last,
                      let frame = computedItemFrame(for: lastItem.id) {
                // Insert after last item
                let slotHeight = Constants.Layout.tabItemHeight + Constants.Layout.tabSpacing
                return CGPoint(x: frame.midX, y: frame.midY + slotHeight)
            }
            return originalCenter

        case .addToGroup, .nestGroup:
            // These keep the item in the tab list, animate to current overlay position
            return overlayPosition
        }
    }

    /// Calculate the index where a favorite will be inserted based on conversion mode.
    private func calculateFavoriteInsertIndex(mode _: FavoriteMode) -> Int {
        // For now, new favorites are appended at the end
        // Could be enhanced to use a specific insertion point
        layoutManager.favoritesLayout.count
    }

    /// Calculate target position for cross-collection moves (pinned ↔ normal).
    ///
    /// Uses frame-based calculation because the divider gap between pinned and normal
    /// makes simple index math incorrect. We look at actual item positions in the
    /// target collection to determine where the dragged item will end up.
    ///
    /// Important: Frame positions are STATIC (at-rest), but after commit the layout
    /// shifts because the source collection loses an item:
    /// - PINNED→NORMAL: Pinned shrinks, so normal section moves UP by dragged item height
    /// - NORMAL→PINNED: Pinned grows, but normal section position doesn't shift
    private func calculateCrossCollectionTargetPosition(
        targetPosition: ItemPosition,
        originalCenter: CGPoint,
    ) -> CGPoint {
        let slotHeight = Constants.Layout.tabItemHeight + Constants.Layout.tabSpacing
        let draggedItemHeight = calculateSlotHeight() // Full group height for groups
        let items = targetPosition.collection == .pinned ? layoutManager.pinnedItems : layoutManager.normalItems
        let sourceCollection = _originPosition?.collection

        // Calculate adjustment for layout shift after commit.
        // PINNED→NORMAL: pinned section shrinks by dragged item height, normal moves up
        // NORMAL→PINNED: pinned section grows, but normal items' final positions don't shift
        let layoutShiftAdjustment: CGFloat = if sourceCollection == .pinned, targetPosition.collection == .normal {
            -draggedItemHeight // Normal section moves up after pinned shrinks
        } else {
            0 // NORMAL→PINNED doesn't shift normal items' final positions
        }

        // Get reference frame from target collection (use computed frames for accuracy)
        if targetPosition.localIndex > 0, targetPosition.localIndex <= items.count {
            // Inserting after an existing item - use that item's frame + slotHeight
            let referenceItem = items[targetPosition.localIndex - 1]
            if let frame = computedItemFrame(for: referenceItem.id) {
                return CGPoint(x: frame.midX, y: frame.midY + slotHeight + layoutShiftAdjustment)
            }
        } else if targetPosition.localIndex == 0, !items.isEmpty {
            // Inserting at start - use first item's position
            let firstItem = items[0]
            if let frame = computedItemFrame(for: firstItem.id) {
                return CGPoint(x: frame.midX, y: frame.midY + layoutShiftAdjustment)
            }
        } else if items.isEmpty {
            // Empty target collection - use effective frame (includes virtual drop zone)
            // effectivePinnedFrame already has height = tabItemHeight, so midY is correct
            let sectionFrame = targetPosition.collection == .pinned
                ? effectivePinnedFrame
                : _adjustedNormalSectionFrame
            if !sectionFrame.isEmpty {
                return CGPoint(x: sectionFrame.midX, y: sectionFrame.midY + layoutShiftAdjustment)
            }
        }

        // Fallback to original center if no frame data available
        return originalCenter
    }

    /// Calculate target position for favorites grid.
    ///
    /// Favorites use a 2D grid layout, so we need to calculate both X and Y
    /// based on the target index's grid position.
    ///
    /// Handles both reordering within favorites and conversion from tabs.
    private func calculateFavoritesTargetPosition(
        targetPosition: ItemPosition,
        layout: GridLayoutInfo,
        originalCenter: CGPoint,
    ) -> CGPoint {
        // For reordering within favorites, check if we're actually moving
        if case let .favorites(localOriginIndex) = _originPosition,
           targetPosition.localIndex == localOriginIndex {
            return originalCenter
        }

        // Calculate grid position for target index
        let targetPos = GridPosition.fromLinearIndex(targetPosition.localIndex, columns: layout.columns)

        // Calculate pixel position relative to grid origin
        let targetLocalX = CGFloat(targetPos.column) * layout.horizontalStride + layout.tileSize.width / 2
        let targetLocalY = CGFloat(targetPos.row) * layout.verticalStride + layout.tileSize.height / 2

        // Convert to global coordinates using grid frame.
        // Use effectiveFavoritesFrame which returns the virtual drop zone frame
        // when there are no favorites yet (favoritesGridFrame would be zero).
        let gridFrame = effectiveFavoritesFrame
        let targetX = gridFrame.minX + targetLocalX
        let targetY = gridFrame.minY + targetLocalY

        return CGPoint(x: targetX, y: targetY)
    }

    func scheduleCleanup() {
        // For staged animation (drop zones):
        //   Phase 1 (~0.35s) + settle (~0.1s) + Phase 2 animation (~0.3s) = ~0.75s
        // Schedule full reset after phase 2 animation completes.
        // For non-staged: Reset after overlay animation (~0.35s).
        let isStaged = _dropZonePushCompensation > 0
        let delay: Double = isStaged ? 0.8 : 0.35
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.reset()
        }
    }
}
