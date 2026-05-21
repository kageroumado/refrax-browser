import Foundation
import SwiftUI

extension Sidebar.DragCoordinator {
    // MARK: - Visual Feedback

    /// Offset to apply to the divider during drag and commit animation.
    ///
    /// Divider moves when inserting into pinned section (everything below pinned moves),
    /// or when removing a pinned tab (everything pulls up).
    ///
    /// Note: Grid shrink compensation is handled via padding on FavoritesGrid,
    /// not through offset adjustments here.
    var dividerPushOffset: CGFloat {
        // Only apply offset during active drag, not during return animation.
        // After commit, the data model has changed and SwiftUI positions
        // elements at their new locations. Continuing to apply the offset
        // during return animation would cause double movement:
        // 1. SwiftUI layout shift (from data change)
        // 2. dividerPushOffset still applied → double the expected movement
        guard isDragging, !isAnimatingReturn else { return 0 }

        let tabSlotHeight = Constants.Layout.tabItemHeight + Constants.Layout.tabSpacing
        // For groups, use full group height (header + visible descendants)
        let draggedItemHeight = calculateSlotHeight()
        var baseOffset: CGFloat = 0
        let sourceCollection = _originPosition?.collection

        // When dragging a PINNED tab to favorites - pull everything up
        if case .convertToFavorite = _dropTarget,
           sourceCollection == .pinned {
            baseOffset = -draggedItemHeight
        }
        // When dragging a favorite into PINNED section
        else if case let .convertToTab(_, targetPosition) = _dropTarget,
                sourceCollection == .favorites,
                targetPosition.collection == .pinned {
            // Favorites are single items, use tab slot height
            baseOffset = tabSlotHeight
        }
        // When moving an unpinned item INTO pinned section (cross-section move)
        // Push down to make room for the new pinned item (or group).
        // Only applies when pinned section has existing items - when empty,
        // the drop zone placeholder handles visual feedback via tabListPushOffset.
        else if activeDropZone == .pinnedSection,
                sourceCollection != .pinned,
                !layoutManager.pinnedItems.isEmpty {
            baseOffset = draggedItemHeight
        }
        // When moving a pinned item OUT to normal section (cross-section move)
        // Pull up to fill the gap left by the departing pinned item (or group)
        else if activeDropZone == .normalSection, sourceCollection == .pinned {
            baseOffset = -draggedItemHeight
        }

        return baseOffset
    }

    /// Offset to apply to the "Add Tab" button during drag and commit animation.
    ///
    /// Moves together with the divider.
    var newTabButtonPushOffset: CGFloat {
        dividerPushOffset
    }

    /// Calculates the grid shrink amount for FAV→TAB conversion.
    ///
    /// When a favorite is removed and the grid loses a row (or becomes empty),
    /// this returns the height that needs to be compensated during commit animation.
    /// Called at commit time to set up `_gridShrinkCompensation`.
    func calculateGridShrinkCompensation() -> CGFloat {
        guard _originPosition?.collection == .favorites,
              case .convertToTab = _dropTarget,
              let layout = _favoritesGridLayout else { return 0 }

        let currentCount = layoutManager.favoritesLayout.count
        guard currentCount >= 1 else { return 0 }

        // When removing the last favorite, compensate for entire grid height
        if currentCount == 1 {
            return favoritesGridFrame.height
        }

        let columns = layout.columns
        let currentRows = (currentCount + columns - 1) / columns
        let newRows = (currentCount - 1 + columns - 1) / columns

        // If row count will decrease, return the row height as compensation
        if newRows < currentRows {
            return layout.verticalStride
        }
        return 0
    }

    /// Calculates the divider height adjustment for normal section targets.
    ///
    /// When the divider appears or disappears after commit, the normal section shifts.
    /// This returns the Y adjustment needed to account for this shift:
    /// - Negative: divider will disappear (normal moves UP)
    /// - Positive: divider will appear (normal moves DOWN)
    /// - Zero: no divider state change
    ///
    /// The divider height (9pt) includes the NewTabView top padding.
    func calculateDividerHeightAdjustment() -> CGFloat {
        let dividerHeight: CGFloat = 9

        // Current divider state
        let currentlyShowing = !layoutManager.pinnedItems.isEmpty || !layoutManager.favoritesLayout.isEmpty

        // Calculate expected divider state AFTER commit
        let willShow: Bool = switch _dropTarget {
        case let .reorder(target):
            // Moving item between collections
            if let origin = _originPosition {
                // Moving LAST pinned to normal (pinned becomes empty)
                if origin.collection == .pinned,
                   target.collection == .normal,
                   layoutManager.pinnedItems.count == 1,
                   layoutManager.favoritesLayout.isEmpty {
                    false
                }
                // Moving to pinned (first pinned item)
                else if target.collection == .pinned,
                        layoutManager.pinnedItems.isEmpty,
                        layoutManager.favoritesLayout.isEmpty {
                    true
                } else {
                    currentlyShowing
                }
            } else {
                currentlyShowing
            }

        case .convertToFavorite:
            // Converting tab to favorite - divider will show if it wasn't already
            true

        case .convertToTab:
            // Converting favorite to tab
            if layoutManager.favoritesLayout.count == 1, layoutManager.pinnedItems.isEmpty {
                // Last favorite being removed, no pinned - divider will hide
                false
            } else {
                currentlyShowing
            }

        case .addToGroup, .nestGroup, .none:
            currentlyShowing
        }

        // Calculate adjustment (only affects normal section targets)
        if currentlyShowing, !willShow {
            // Divider disappearing - normal section moves UP
            return -dividerHeight
        } else if !currentlyShowing, willShow {
            // Divider appearing - normal section moves DOWN
            return dividerHeight
        }
        return 0
    }

    var headerPushOffset: CGFloat {
        shouldShowFavoritesDropZone ? DropZoneConstants.addressBarOffset : 0
    }

    /// Offset to apply to the entire tab list during drag.
    ///
    /// Combines drop zone push offset and divider visibility offset into a single value.
    /// During return animation:
    /// - Drop zone push uses staged animation via `_dropZonePushCompensation`
    /// - Divider visibility offset goes to 0 synchronously (handled by SwiftUI layout)
    var tabListPushOffset: CGFloat {
        // During return animation, only return the drop zone compensation (staged animation).
        // Divider visibility offset is NOT included - it changes synchronously.
        if case .reorder = _dropTarget, isAnimatingReturn {
            return _dropZonePushCompensation
        }

        var pushHeight: CGFloat = 0
        if shouldShowFavoritesDropZone {
            pushHeight += DropZoneConstants.favoritesDropZoneTotalHeight
        }
        if shouldShowPinDropZone {
            pushHeight += DropZoneConstants.pinnedDropZoneTotalHeight
        }
        // Add divider visibility offset when divider would appear/disappear
        pushHeight += dividerVisibilityOffset
        return pushHeight
    }

    /// Whether the divider should be visually shown during drag.
    ///
    /// This predicts the visual divider state based on current drag target,
    /// even before the data model is committed. Used by TabList to animate
    /// divider opacity during drag.
    var shouldShowDividerDuringDrag: Bool {
        let currentlyShowing = !layoutManager.pinnedItems.isEmpty || !layoutManager.favoritesLayout.isEmpty

        // When not dragging or during return animation, use actual model state
        guard isDragging, !isAnimatingReturn else { return currentlyShowing }

        let sourceCollection = _originPosition?.collection

        // When drop zones are showing, divider state depends on what would happen
        // if dropped there - but visually it should stay as-is until commit
        if _isDragAboveTabList { return currentlyShowing }

        // Case 1: Dragging LAST pinned item to normal section - divider will disappear
        if activeDropZone == .normalSection,
           sourceCollection == .pinned,
           layoutManager.pinnedItems.count == 1,
           layoutManager.favoritesLayout.isEmpty {
            return false
        }

        // Case 2: Dragging LAST favorite to become a tab - divider will disappear
        if case .convertToTab = _dropTarget,
           sourceCollection == .favorites,
           layoutManager.favoritesLayout.count == 1,
           layoutManager.pinnedItems.isEmpty {
            return false
        }

        // Case 3: Converting tab to favorite when no favorites/pinned exist - divider will appear
        if case .convertToFavorite = _dropTarget,
           !currentlyShowing {
            return true
        }

        return currentlyShowing
    }

    /// Offset for tab list when divider visibility would change during drag.
    ///
    /// When dragging an item that would make the divider appear or disappear,
    /// this returns the offset needed to compensate for that layout change.
    /// - Negative: divider will disappear (normal section moves UP)
    /// - Positive: divider will appear (normal section moves DOWN)
    /// - Zero: no divider visibility change
    ///
    /// Note: When drop zones are showing, they handle their own push offset
    /// via `tabListPushOffset`, so this returns 0 in those cases.
    var dividerVisibilityOffset: CGFloat {
        guard isDragging, !isAnimatingReturn else { return 0 }

        let dividerHeight: CGFloat = 9
        let sourceCollection = _originPosition?.collection

        // Current divider state
        let currentlyShowing = !layoutManager.pinnedItems.isEmpty || !layoutManager.favoritesLayout.isEmpty

        // When drop zones are showing, they handle layout shifts
        if _isDragAboveTabList { return 0 }

        // Check if divider will disappear
        // Case 1: Dragging LAST pinned item to normal section
        if activeDropZone == .normalSection,
           sourceCollection == .pinned,
           layoutManager.pinnedItems.count == 1,
           layoutManager.favoritesLayout.isEmpty {
            // Divider will disappear - pull normal section up
            return -dividerHeight
        }

        // Case 2: Dragging LAST favorite to become a tab
        if case .convertToTab = _dropTarget,
           sourceCollection == .favorites,
           layoutManager.favoritesLayout.count == 1,
           layoutManager.pinnedItems.isEmpty {
            // Divider will disappear - pull normal section up
            return -dividerHeight
        }

        // Check if divider will appear (when not in drop zone area)
        // Case 3: Dragging into existing pinned section as first pinned item
        // (This is handled by dividerPushOffset when pinned section exists,
        // and by drop zone when pinned section is empty)

        // Case 4: Converting tab to favorite when no favorites/pinned exist
        if case .convertToFavorite = _dropTarget,
           !currentlyShowing {
            // Divider will appear - push normal section down
            return dividerHeight
        }

        return 0
    }

    /// Whether to show the favorites drop zone placeholder
    var shouldShowFavoritesDropZone: Bool {
        _isDragAboveTabList && layoutManager.favoritesLayout.isEmpty
    }

    /// Whether to show the pin drop zone placeholder
    var shouldShowPinDropZone: Bool {
        // Show pin zone if:
        // 1. Dragging above tab list
        // 2. No pinned items exist
        // 3. Item being dragged is not already pinned
        guard _isDragAboveTabList, layoutManager.pinnedItems.isEmpty else { return false }

        if let tab = primaryDraggedItem?.tab {
            return !tab.isPinned
        } else if let group = primaryDraggedItem?.group {
            return group.isPinned != true
        }
        return false
    }

    /// Adjusted pinned section frame accounting for current drag offset.
    ///
    /// During drag, the tab list may be pushed down by drop zone placeholders.
    /// This property returns the visually correct frame for hit testing.
    ///
    /// Uses computed section frames derived from item positions and scroll offset,
    /// rather than stored frames which can become stale.
    /// Internal only. Do not use externally.
    var _adjustedPinnedSectionFrame: CGRect {
        let frame = computedPinnedSectionFrame
        guard !frame.isEmpty else { return .zero }
        return frame.offsetBy(dx: 0, dy: tabListPushOffset)
    }

    /// Internal only. Do not use externally.
    /// Adjusted normal section frame accounting for current drag offset.
    ///
    /// Uses computed section frames derived from item positions and scroll offset,
    /// rather than stored frames which can become stale.
    var _adjustedNormalSectionFrame: CGRect {
        let frame = computedNormalSectionFrame
        guard !frame.isEmpty else { return .zero }
        return frame.offsetBy(dx: 0, dy: tabListPushOffset)
    }

    /// Converts a visual location to static coordinate space.
    ///
    /// During drag, the tab list is pushed down by `tabListPushOffset`. Item frames
    /// in metadata are captured at rest (static). To compare a visual location against
    /// static frames, we need to subtract the current push offset.
    ///
    /// - Parameter location: Location in visual (current) coordinate space.
    /// - Returns: Location in static coordinate space (matching item frames).
    func locationInStaticSpace(_ location: CGPoint) -> CGPoint {
        CGPoint(x: location.x, y: location.y - tabListPushOffset)
    }

    // MARK: - Virtual Frames for Drop Zone Hit Testing

    /// Effective favorites frame - real grid frame OR virtual drop zone frame.
    ///
    /// When the favorites grid has items, returns the actual grid frame.
    /// When the grid is empty but a drop zone placeholder is showing,
    /// returns a virtual frame representing where drops should target.
    var effectiveFavoritesFrame: CGRect {
        // If real favorites exist, use their frame
        if !favoritesGridFrame.isEmpty {
            return favoritesGridFrame
        }
        // If drop zone is showing, return virtual frame
        guard shouldShowFavoritesDropZone else {
            return .zero
        }
        // Virtual frame positioned where drop zone appears.
        // Uses same logic as Sidebar.swift's drop zone positioning:
        // - Base offset from sidebar top: addressBarOffset (32) + favorites height if exists
        // - Zone content is inset by verticalPadding/2 (8) from zone boundaries
        var dropZoneBaseOffset = DropZoneConstants.addressBarOffset
        if !layoutManager.favoritesLayout.isEmpty {
            dropZoneBaseOffset += favoritesGridFrame.height + 12
        }
        let zoneTop = sidebarBounds.minY + dropZoneBaseOffset + DropZoneConstants.verticalPadding / 2
        return CGRect(
            x: sidebarBounds.minX + Constants.Layout.sidebarPadding,
            y: zoneTop,
            width: sidebarBounds.width - Constants.Layout.sidebarPadding * 2,
            height: DropZoneConstants.favoritesTileHeight,
        )
    }

    /// Effective pinned frame - real section frame OR virtual drop zone frame.
    ///
    /// When pinned items exist, returns the adjusted section frame.
    /// When no pinned items exist but a drop zone placeholder is showing,
    /// returns a virtual frame representing where drops should target.
    var effectivePinnedFrame: CGRect {
        // If real pinned items exist, use adjusted frame
        if !_adjustedPinnedSectionFrame.isEmpty {
            return _adjustedPinnedSectionFrame
        }
        // If drop zone is showing, return virtual frame
        guard shouldShowPinDropZone else {
            return .zero
        }
        // Base offset from sidebar top (same as Sidebar.swift)
        var dropZoneBaseOffset = DropZoneConstants.addressBarOffset
        if !layoutManager.favoritesLayout.isEmpty {
            dropZoneBaseOffset += favoritesGridFrame.height + 12
        }
        // Position depends on whether favorites drop zone is also showing
        let zoneTop: CGFloat = if shouldShowFavoritesDropZone {
            // Pinned zone is below favorites zone
            sidebarBounds.minY + dropZoneBaseOffset + DropZoneConstants.favoritesDropZoneTotalHeight + DropZoneConstants.verticalPadding / 2
        } else {
            // Pinned zone at top of zone area
            sidebarBounds.minY + dropZoneBaseOffset + DropZoneConstants.verticalPadding / 2
        }
        let tabsOriginX = sidebarBounds.minX + Constants.Layout.tabHorizontalPadding
        let tabsWidth = sidebarBounds.width - Constants.Layout.tabHorizontalPadding * 2
        return CGRect(
            x: tabsOriginX,
            y: zoneTop,
            width: tabsWidth,
            height: DropZoneConstants.pinnedPlaceholderHeight,
        )
    }

    /// Internal only. Do not use externally.
    /// Whether the dragged tab is currently in the drop zone area (above the tab list).
    ///
    /// Uses hysteresis to prevent flickering at boundaries:
    /// - Activates when drag crosses above the first item baseline
    /// - Deactivates when drag crosses below the exit threshold (bottom of drop zone area)
    var _isDragAboveTabList: Bool {
        guard let originalFrame = _draggedItemOriginalFrame else { return false }
        guard primaryDraggedItem?.tab != nil || primaryDraggedItem?.group != nil else { return false }
        let sourceCollection = _originPosition?.collection
        guard sourceCollection == .pinned || sourceCollection == .normal else { return false }
        guard let firstY = _firstItemStartY else { return false }

        let dragY = originalFrame.minY + currentOffset

        // Enter threshold: above first item baseline
        let enterThreshold = firstY

        // Exit threshold: below the maxY of where drop zones would end
        // Calculate total drop zone height based on what would be shown
        let wouldShowFavorites = layoutManager.favoritesLayout.isEmpty
        let wouldShowPinned: Bool = if layoutManager.pinnedItems.isEmpty {
            if let tab = primaryDraggedItem?.tab {
                !tab.isPinned
            } else if let group = primaryDraggedItem?.group {
                group.isPinned != true
            } else {
                false
            }
        } else {
            false
        }

        var totalDropZoneHeight: CGFloat = 0
        if wouldShowFavorites {
            totalDropZoneHeight += DropZoneConstants.favoritesDropZoneTotalHeight
        }
        if wouldShowPinned {
            totalDropZoneHeight += DropZoneConstants.pinnedDropZoneTotalHeight
        }

        // Exit threshold includes some margin below the drop zone area
        let exitThreshold = firstY + totalDropZoneHeight * 0.5

        if _dropZonesActive {
            // Only deactivate when crossing exit threshold going DOWN
            if dragY > exitThreshold {
                _dropZonesActive = false
            }
        } else {
            // Activate when crossing enter threshold going UP
            if dragY < enterThreshold {
                _dropZonesActive = true
            }
        }

        return _dropZonesActive
    }
}
