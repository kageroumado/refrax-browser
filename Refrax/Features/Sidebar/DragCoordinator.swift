import Algorithms
import Foundation
import SwiftUI

extension Sidebar {
    /// Coordinates drag operations across all sidebar collections.
    ///
    /// Handles drag-to-reorder within collections and cross-collection moves:
    /// - Tab ↔ Favorites (convert to live tab/shortcut)
    /// - Tab → Group (add to group)
    /// - Group → Group (nest groups)
    /// - Reorder within pinned/normal sections
    ///
    /// ## Drag Physics
    ///
    /// Uses hysteresis-based swapping with smooth animations. Items being pushed
    /// aside animate using smoothstep easing for natural feel.
    ///
    /// ## Multi-Item Drag
    ///
    /// When dragging a group, all its contents (tabs + nested groups) move together.
    ///
    /// ## Performance
    ///
    /// - Caches combined item lists to avoid repeated array concatenation
    /// - Pre-calculates group descendants at drag start
    /// - Uses binary search on sorted visible items
    /// - Incrementally updates item offsets instead of rebuilding
    ///
    /// ## File layout
    /// - `DragCoordinator.swift`: stored state + public entry points + frame updates.
    /// - `DragCoordinator+VisualFeedback.swift`: push offsets + drop zone visibility + overlay helpers.
    /// - `DragCoordinator+Caches.swift`: item caches and invalidation.
    /// - `DragCoordinator+Targets.swift`: drop target detection and index math.
    /// - `DragCoordinator+Nesting.swift`: nesting level decisions.
    /// - `DragCoordinator+AffectedItems.swift`: affected items + offset calculations.
    /// - `DragCoordinator+DropZones.swift`: drop zone progress and thresholds.
    /// - `DragCoordinator+Overlay.swift`: overlay frames and easing.
    /// - `DragCoordinator+Animation.swift`: commit animation + cleanup.
    /// - `DragCoordinator+Reset.swift`: state resets.
    /// - `DragCoordinator+Types.swift`: helper types/debug accessors.
    /// - `DragCoordinator+Constants.swift`: constants used across extensions.
    @Observable
    final class DragCoordinator {
        unowned var tabManager: TabManager!
        unowned var layoutManager: LayoutManager!
        unowned var windowState: WindowState!
        unowned var frameRegistry: FrameRegistry!
        unowned var state: Sidebar.GeometryState!
        
        // MARK: - Drag State

        /// Warning: Not meant to be set externally.
        /// Current drag offset in points (negative = up, positive = down)
        var currentOffset: CGFloat = 0

        /// Warning: Not meant to be set externally.
        /// The main dragged item (the one under the cursor at drag start).
        ///
        /// For single-item drags, this contains one element.
        /// For multi-selection drags, this contains only the grabbed tab.
        /// Groups cannot be part of multi-selection drags.
        ///
        /// Marked `@ObservationIgnored` to prevent views from creating observations.
        /// Views should use `isDragging` or `isItemBeingDragged(_:)` instead.
        @ObservationIgnored var draggedItems: [DraggedItem] = []

        /// Follower items that will be repositioned after the main item during commit.
        ///
        /// Empty for single-item drags. For multi-selection, contains all selected
        /// items except the main (grabbed) one. Followers are hidden during drag
        /// and inserted after the main item on commit.
        @ObservationIgnored var followerItems: [DraggedItem] = []

        /// IDs of follower items to hide during drag.
        ///
        /// Used by views to hide followers while the main item is being dragged,
        /// creating a "collapse" animation. Cleared on commit/cancel.
        ///
        /// Marked `@ObservationIgnored` - views should use `shouldHideItem(_:)` instead.
        @ObservationIgnored var hiddenFollowerIDs: Set<UUID> = []

        /// Convenience accessor for the main dragged item.
        ///
        /// Returns the first item in `draggedItems`, or nil if not dragging.
        /// This is the tab that was physically grabbed by the user.
        var primaryDraggedItem: DraggedItem? {
            draggedItems.first
        }

        /// Whether a drag operation is currently active.
        ///
        /// This is a stored property (not computed) because `draggedItems` is `@ObservationIgnored`.
        /// Making this stored ensures views observing `isDragging` get notified when drag state changes.
        var isDragging: Bool = false

        // MARK: - View Helper Methods

        /// Check if a specific item is currently being dragged.
        ///
        /// Use this instead of directly accessing `draggedItems` to avoid creating
        /// observation dependencies that would cause view updates on every drag change.
        func isItemBeingDragged(_ itemID: UUID) -> Bool {
            draggedItems.contains { $0.id == itemID }
        }

        /// Check if a specific tab is currently being dragged.
        ///
        /// Use this instead of directly accessing `draggedItems` to avoid creating
        /// observation dependencies that would cause view updates on every drag change.
        func isTabBeingDragged(_ tabID: UUID) -> Bool {
            draggedItems.contains { $0.tab?.id == tabID }
        }

        /// Check if an item should be hidden (main dragged item or follower).
        ///
        /// Use this instead of directly accessing `hiddenFollowerIDs` to avoid creating
        /// observation dependencies that would cause view updates on every drag change.
        func shouldHideFollower(_ itemID: UUID) -> Bool {
            hiddenFollowerIDs.contains(itemID)
        }

        /// Whether an item should be invisible during drag — it's being dragged,
        /// is a follower of the dragged item, or is the converted item during return animation.
        func shouldHideItemDuringDrag(_ itemID: UUID) -> Bool {
            isItemBeingDragged(itemID)
                || shouldHideFollower(itemID)
                || (isAnimatingReturn && itemID == _convertedItemID)
        }

        /// Warning: Not meant to be set externally.
        /// Whether the drag gesture ended and overlay is animating return. No new drag gestures should be allowed during this time.
        ///
        /// Observable so views can react to return animation state changes (e.g., to suppress
        /// animations for cross-collection moves until the return animation completes).
        var isAnimatingReturn = false
        
        /// Internal only. Do not use externally.
        /// The origin position of the dragged item when drag started.
        @ObservationIgnored var _originPosition: ItemPosition?
        /// Whether the dragged item was active when drag started.
        /// Captured at drag start to preserve appearance during return animation.
        @ObservationIgnored var _draggedItemWasActive: Bool = false

        // MARK: - Drop Target Detection

        /// Internal only. Do not use externally.
        @ObservationIgnored var _dropTarget: DropTarget = .none
        /// Warning: Not meant to be set externally.
        var activeDropZone: DropZone?
        /// Pre-calculated target position for return animation (calculated before commit).
        @ObservationIgnored var _preCalculatedTargetPosition: CGPoint?
        /// Compensation offset applied at commit time when FAV→TAB causes grid row reduction.
        ///
        /// When the favorites grid loses a row, this holds the row height. Applied instantly
        /// after commit to prevent visual jump, then animated to zero for smooth pull-up.
        var _gridShrinkCompensation: CGFloat = 0

        /// Compensation offset for drop zone push during return animation.
        ///
        /// When committing from drop zones, the tab list was pushed down. This captures
        /// that offset at commit time so it can be animated to zero smoothly, rather than
        /// having the tabs jump up instantly.
        var _dropZonePushCompensation: CGFloat = 0

        /// ID of the newly created/converted item during FAV→TAB conversion.
        ///
        /// Used to hide the new tab during return animation to prevent duplication
        /// (overlay + real item both visible). Cleared on reset.
        @ObservationIgnored var _convertedItemID: UUID?

        // MARK: - Visual Feedback

        /// Per-item 2D offsets during drag (for smooth push-aside animation).
        ///
        /// - For tabs: y component used, x always 0
        /// - For favorites: both x and y used for grid flow
        ///
        /// Observable so views automatically update when offsets change.
        var itemPushOffsets: [UUID: CGPoint] = [:]
        
        /// Warning: Not meant to be set externally.
        /// Overlay position in global coordinate space
        var overlayPosition: CGPoint = .zero

        /// Overlay position converted to sidebar-local coordinates for rendering.
        ///
        /// Since drag gestures report in global coordinates but the overlay is positioned
        /// within the sidebar's coordinate space, this converts by subtracting sidebar origin.
        var overlayPositionInSidebar: CGPoint {
            CGPoint(
                x: overlayPosition.x - sidebarBounds.minX,
                y: overlayPosition.y - sidebarBounds.minY,
            )
        }

        /// Favorites grid frame (delegated to Sidebar.GeometryState).
        var favoritesGridFrame: CGRect {
            state.favoritesGridFrame
        }

        /// Complete sidebar bounds (delegated to Sidebar.GeometryState).
        var sidebarBounds: CGRect {
            state.sidebarBounds
        }

        /// Grid layout info for favorites (delegated to Sidebar.GeometryState).
        var _favoritesGridLayout: Sidebar.GeometryState.GridLayoutInfo? {
            state.favoritesGridLayout
        }

        /// Whether to show a data storage warning on the drag overlay.
        ///
        /// Set to true when dragging between zones with different data storage configurations:
        /// - Favorite → Space with separate/private data store
        /// - Tab from separate/private space → Favorites grid
        ///
        /// The warning indicates that the tab will need to reload with different cookies/storage.
        @ObservationIgnored var showDataStorageWarning = false

        // MARK: - Overlay Morphing

        /// Current overlay appearance mode. Changes when crossing zone boundaries.
        ///
        /// - `.tabRow`: When dragging within or toward tab list (pinned/normal sections)
        /// - `.tile`: When dragging within or toward favorites grid
        @ObservationIgnored var currentOverlayMode: OverlayMode = .tabRow

        /// Animation progress for overlay morph transition (0.0 → 1.0).
        ///
        /// Animated over 150ms with easeInOut when `currentOverlayMode` changes.
        /// Used by `MorphingDragOverlay` to crossfade and scale between appearances.
        @ObservationIgnored var overlayMorphProgress: CGFloat = 1.0

        /// Cached tab row width computed from sidebar bounds.
        ///
        /// TabList fills the sidebar width. Each tab has `.padding(.horizontal, tabHorizontalPadding)`
        /// applied, so the background width is: sidebarWidth - 2 * tabHorizontalPadding.
        /// Falls back to 300 if sidebar bounds are not yet captured.
        var tabRowWidth: CGFloat {
            let sidebarWidth = sidebarBounds.width
            guard sidebarWidth > 0 else { return 300 }
            // TabList has no padding; individual tabs have tabHorizontalPadding on each side
            let totalPadding = 2 * Constants.Layout.tabHorizontalPadding
            return max(200, sidebarWidth - totalPadding)
        }

        /// Returns the target size for the current overlay mode.
        ///
        /// Uses the dynamically computed `tabRowWidth` for tab row mode,
        /// rather than the hardcoded value in `OverlayMode.targetSize`.
        /// For groups, returns the full group bounds size (header + all children).
        var overlayTargetSize: CGSize {
            // For groups, use the pre-calculated group bounds
            if let groupBounds = _draggedGroupBounds {
                return groupBounds.size
            }

            switch currentOverlayMode {
            case .tabRow:
                return CGSize(width: tabRowWidth, height: Constants.Layout.tabItemHeight)
            case let .tile(size):
                return size
            }
        }

        // MARK: - AppKit Handoff

        /// Current phase of the drag with respect to SwiftUI/AppKit ownership.
        ///
        /// - `.internal`: SwiftUI overlay is active (default state)
        /// - `.transitioning`: AppKit session being created
        /// - `.external`: AppKit owns the drag session
        ///
        /// Observable (not ignored) because views need to show/hide the SwiftUI overlay
        /// based on whether we're in internal vs external phase.
        var handoffPhase: HandoffPhase = .internal

        /// Frozen state preserved during AppKit phase for re-entry.
        ///
        /// Captured when transitioning to external phase, restored if user
        /// drags back into sidebar. Cleared when drag ends.
        @ObservationIgnored var ghostState: GhostState?

        /// Timestamp when external phase began (for debouncing re-entry).
        ///
        /// Set when `handoffPhase` transitions to `.external`. Used to prevent
        /// flickering at the sidebar edge by requiring at least one frame
        /// (~16ms) in external phase before allowing re-entry.
        @ObservationIgnored var externalPhaseStartTime: CFTimeInterval?

        // MARK: - Inbound Drop Tracking

        /// Active drop zone during inbound external drop.
        ///
        /// Set when an external URL is being dragged over the sidebar.
        /// Used by views to highlight the active drop zone.
        ///
        /// Note: Not marked `@ObservationIgnored` because views need to
        /// re-render when this changes (both on set and clear).
        var inboundDropZone: DropZone?

        /// Whether an external drop is currently in progress.
        var isReceivingExternalDrop: Bool {
            inboundDropZone != nil
        }

        /// Reference to the NSView used for AppKit drag sessions.
        ///
        /// Set by `SidebarDragSourceView` when it creates its NSView.
        /// Used to initiate AppKit drag sessions during handoff.
        @ObservationIgnored weak var dragSourceView: DragSourceNSView?

        /// Internal only. Do not use externally.
        /// Y position of the first item in the tab list at drag start (baseline for "above" detection)
        @ObservationIgnored var _firstItemStartY: CGFloat?

        /// Hysteresis state for drop zone activation.
        ///
        /// Once drop zones activate (drag crosses above first item), they stay active
        /// until the drag crosses below the exit threshold (bottom of drop zone area).
        /// This prevents flickering when the drag hovers near the boundary.
        @ObservationIgnored var _dropZonesActive: Bool = false

        /// Internal only. Do not use externally.
        /// Original frame of dragged item (before drag started) - nil until captured
        @ObservationIgnored var _draggedItemOriginalFrame: CGRect?

        /// Internal only. Do not use externally.
        /// Offset from the cursor to the overlay center at drag start.
        /// When user grabs the tab off-center, this preserves that offset throughout the drag.
        @ObservationIgnored var _clickOffset: CGPoint = .zero

        /// Internal only. Do not use externally.
        /// Full bounds of dragged group (header + all descendants) - nil until captured
        @ObservationIgnored var _draggedGroupBounds: CGRect?

        /// Internal only. Do not use externally.
        /// Items that crossed the swap threshold (progress > 0.5) - will be reordered
        @ObservationIgnored var _crossedThresholdItems: Set<UUID> = []

        /// Internal only. Do not use externally.
        /// Items with partial animation progress (0 < progress < 1)
        @ObservationIgnored var _partialAnimationItems: Set<UUID> = []

        // MARK: - Performance Caches

        /// Internal only. Do not use externally.
        /// Cached combined items list (invalidated on frameGeneration change)
        @ObservationIgnored var _allItemsCache: [TabListItem] = []
        /// Internal only. Do not use externally.
        @ObservationIgnored var _cachedAllItemsGeneration: Int = -1
        /// Internal only. Do not use externally.
        @ObservationIgnored var _cachedVisibleItemsGeneration: Int = -1

        /// Internal only. Do not use externally.
        /// Pre-validated visible items sorted by Y position
        @ObservationIgnored var _visibleItemsCache: [ValidatedItem] = []

        /// Internal only. Do not use externally.
        /// Pre-calculated descendants for all groups (built at drag start)
        @ObservationIgnored var _descendantsCache: [UUID: Set<UUID>] = [:]

        /// Internal only. Do not use externally.
        /// Exclusion set for dragged item + its descendants (built at drag start)
        @ObservationIgnored var _draggedItemExclusionSet: Set<UUID> = []

        // MARK: - Lifecycle

        /// Start a drag operation with a single item.
        ///
        /// Convenience wrapper for single-item drags. For multi-selection drags,
        /// use ``startDrag(items:originPosition:startLocation:)``.
        ///
        /// - Parameters:
        ///   - item: Item to drag
        ///   - originPosition: Position of the item in the sidebar
        ///   - startLocation: Cursor position in global coordinates at drag start.
        ///     Used to calculate the grab offset so the overlay stays correctly
        ///     positioned under the cursor throughout the drag.
        func startDrag(
            item: DraggedItem,
            originPosition: ItemPosition,
            startLocation: CGPoint,
        ) {
            startDrag(
                items: [item],
                originPosition: originPosition,
                startLocation: startLocation,
            )
        }

        /// Start a drag operation with multiple items.
        ///
        /// For multi-selection drags:
        /// - Groups are automatically filtered out (only tabs supported)
        /// - The first item determines the overlay appearance and origin
        /// - All items move together and commit to the same destination
        ///
        /// - Parameters:
        ///   - items: Items to drag (groups filtered for multi-selection)
        ///   - originPosition: Position of the primary (first) item
        ///   - startLocation: Cursor position in global coordinates at drag start.
        ///     Used to calculate the grab offset so the overlay stays correctly
        ///     positioned under the cursor throughout the drag.
        func startDrag(
            items: [DraggedItem],
            originPosition: ItemPosition,
            startLocation: CGPoint,
        ) {
            // Filter out undraggable items:
            // - Archive groups cannot be dragged at all
            // - Regular groups can only be dragged alone (not in multi-selection)
            let isMultiSelect = items.count > 1
            let filteredItems = items.filter { item in
                guard let group = item.group else { return true }
                if group.isArchive { return false }
                if isMultiSelect { return false }
                return true
            }

            guard let mainItem = filteredItems.first else { return }

            // Separate main item (grabbed by cursor) from followers (other selected)
            // Only the main item participates in drag logic; followers are hidden
            // during drag and repositioned after the main item on commit.
            if filteredItems.count == 1 {
                // Single-item drag: standard path
                draggedItems = [mainItem]
                followerItems = []
                hiddenFollowerIDs = []
            } else {
                // Multi-item: main + followers
                draggedItems = [mainItem]
                followerItems = Array(filteredItems.dropFirst())
                hiddenFollowerIDs = Set(followerItems.map(\.id))
            }

            // Set isDragging AFTER populating draggedItems (isDragging is stored, not computed,
            // because draggedItems is @ObservationIgnored - this triggers view updates).
            isDragging = true

            _originPosition = originPosition
            currentOffset = 0

            // Capture whether the item was active at drag start
            // (preserves title font weight during return animation when active state changes)
            _draggedItemWasActive = isItemActive(mainItem)

            // Set initial overlay mode based on source item type
            if case .favorite = mainItem {
                // Use grid layout if available, otherwise fall back to tab width with fixed tile height
                let tileHeight = Constants.Layout.tabItemHeight * 1.5
                let tileSize = _favoritesGridLayout?.tileSize ?? CGSize(width: tabRowWidth, height: tileHeight)
                currentOverlayMode = .tile(tileSize)
            } else {
                currentOverlayMode = .tabRow
            }
            overlayMorphProgress = 1.0

            // Use computed frame (from section geometry) instead of NSView frame.
            // NSView frames in LazyVStack don't update during scroll - they keep
            // their initial creation position even after scrolling offscreen.
            if let frame = computedItemFrame(for: mainItem.id) {
                _draggedItemOriginalFrame = frame

                // Also pre-calculate group bounds if applicable
                if let group = mainItem.group {
                    _draggedGroupBounds = layoutManager.calculateGroupBounds(groupID: group.id)
                } else {
                    _draggedGroupBounds = nil
                }

                // Calculate click offset: how far the grab point is from item center.
                // This preserves the user's grab position throughout the drag so the
                // overlay doesn't jump to be centered under the cursor.
                let frameCenter = CGPoint(x: frame.midX, y: frame.midY)
                _clickOffset = CGPoint(
                    x: startLocation.x - frameCenter.x,
                    y: startLocation.y - frameCenter.y,
                )

                // Set initial overlay position at the computed frame center.
                // The click offset will be applied when updating position during drag.
                overlayPosition = frameCenter
            } else {
                // No computed frame - set click offset to zero and use startLocation
                _clickOffset = .zero
                overlayPosition = startLocation
            }

            // PRE-CALCULATE: Build caches for performance
            buildDescendantsCache()
            // Build exclusion set for main item (includes descendants if group)
            buildExclusionSetForMainItem()

            // Capture the Y position of the first visible tab as baseline
            // (this also forces cache building via getAllItems())
            captureFirstItemBaseline()
        }
        
        /// Update drag with new offset and location
        func updateDrag(
            offset: CGFloat,
            location: CGPoint,
        ) {
            // If we're in transitioning or external phase, ignore SwiftUI gesture updates
            // The AppKit drag session owns the drag now
            guard handoffPhase == .internal else { return }

            currentOffset = offset

            // Update overlay position BEFORE other calculations that depend on it.
            // This ensures grid offset calculations use the current position, not
            // the position from the previous frame.
            // Apply click offset so the grab point stays under the cursor.
            overlayPosition = CGPoint(
                x: location.x - _clickOffset.x,
                y: location.y - _clickOffset.y,
            )

            // Check if cursor has left the sidebar - trigger AppKit handoff
            if cursorIsOutsideSidebar(at: location) {
                beginAppKitHandoff()
                return
            }

            detectDropTarget(at: location)
            updateAffectedItems()
        }
        
        /// Commit the drag operation
        @discardableResult
        func commitDrag() -> Bool {
            guard let primaryItem = primaryDraggedItem else { return false }

            // Capture drop zone push compensation for staged animation.
            // After commit: drop zones disappear BUT new content appears.
            // The compensation keeps the tab list visually in place:
            //   compensation = dropZonePush - newContentSpace
            //
            // We need to account for:
            // - New pinned item: 36pt height + 4pt spacing = 40pt
            // - Divider appearing: 9pt (NewTabView top padding)
            var dropZonePush: CGFloat = 0
            if shouldShowFavoritesDropZone {
                dropZonePush += DropZoneConstants.favoritesDropZoneTotalHeight
            }
            if shouldShowPinDropZone {
                dropZonePush += DropZoneConstants.pinnedDropZoneTotalHeight
            }

            // Calculate space that new content will take after commit
            var newContentSpace: CGFloat = 0
            if case let .reorder(target) = _dropTarget {
                if target.collection == .pinned, layoutManager.pinnedItems.isEmpty {
                    // New pinned item will appear
                    newContentSpace += Constants.Layout.tabItemHeight + Constants.Layout.tabSpacing
                    // Divider will appear (if no favorites either)
                    if layoutManager.favoritesLayout.isEmpty {
                        newContentSpace += 9 // Divider padding on NewTabView
                    }
                    _dropZonePushCompensation = max(0, dropZonePush - newContentSpace)
                }
            }

            // Set animating return BEFORE commit operations so that any rebuildLayout
            // calls during multi-item moves don't get blocked by the "isDragging" guard.
            isAnimatingReturn = true

            // Pre-calculate target position BEFORE commit changes the data model.
            // After commit, frame metadata may be stale or not yet captured for new items.
            _preCalculatedTargetPosition = calculateTargetOverlayPosition()

            // Pre-calculate grid shrink compensation BEFORE commit changes the data model.
            // This captures the row height if removing the favorite will reduce grid row count.
            let gridShrinkAmount = calculateGridShrinkCompensation()

            // Adjust target position for grid shrink: when grid loses a row, the tab list
            // moves UP by gridShrinkAmount at the end of animation. The overlay should
            // animate to where the new tab will be AFTER the grid shrinks.
            if gridShrinkAmount > 0, case .convertToTab = _dropTarget {
                _preCalculatedTargetPosition?.y -= gridShrinkAmount
            }

            // Adjust target position for divider appearance/disappearance.
            // When the divider shows/hides, the normal section shifts by 9pt.
            // Only apply to normal section targets (divider is above normal).
            let dividerAdjustment = calculateDividerHeightAdjustment()
            if dividerAdjustment != 0 {
                let isNormalTarget: Bool = switch _dropTarget {
                case let .reorder(target): target.collection == .normal
                case let .convertToTab(_, target): target.collection == .normal
                default: false
                }
                if isNormalTarget {
                    _preCalculatedTargetPosition?.y += dividerAdjustment
                }
            }

            let didReorder: Bool
            switch _dropTarget {
            case .none:
                didReorder = false

            case let .reorder(target):
                didReorder = commitReorder(to: target)

            case let .convertToFavorite(mode):
                didReorder = commitConvertToFavorites(mode: mode)

            case let .convertToTab(_, targetPosition):
                guard case let .favorite(favorite) = primaryItem else {
                    didReorder = false
                    break
                }
                let isPinned = targetPosition.collection == .pinned
                let convertedTabID = tabManager.convertFavoriteToTab(
                    favorite,
                    atIndex: targetPosition.localIndex,
                    isPinned: isPinned,
                    using: layoutManager,
                )
                didReorder = convertedTabID != nil
                _convertedItemID = convertedTabID

            case let .addToGroup(groupID):
                didReorder = commitAddToGroup(groupID: groupID)

            case let .nestGroup(parentGroupID):
                guard case let .group(group) = primaryItem else {
                    didReorder = false
                    break
                }
                didReorder = tabManager.nestGroup(group, in: parentGroupID, using: layoutManager)
            }

            // Calculate animation parameters before rebuild
            let animationParams = calculateCommitAnimationParameters()
            
            // Capture items that need special animation handling
            let itemsWithPartialAnimation = _partialAnimationItems
            let itemsThatCrossed = _crossedThresholdItems
    
            // Set grid shrink compensation BEFORE rebuild so the FavoritesGrid padding
            // keeps the total height stable. When the grid loses a row, the padding
            // maintains the same total height, preventing the tab list from jumping.
            if gridShrinkAmount > 0 {
                _gridShrinkCompensation = gridShrinkAmount
            }

            if didReorder {
                layoutManager.rebuildLayout()
            } else {
                // Reset nesting level modified during drag without expensive rebuild
                resetDraggedItemNestingLevel()
            }

            // Apply animation adjustments (clears most offsets)
            applyCommitAnimationAdjustments(
                params: animationParams,
                itemsWithPartialAnimation: itemsWithPartialAnimation,
                itemsThatCrossed: itemsThatCrossed,
            )

            // Animate everything to final positions (including _gridShrinkCompensation → 0)
            animateToFinalPositions()
            
            // Schedule cleanup after animation
            scheduleCleanup()
            
            return didReorder
        }
        
        /// Reorder item within a collection
        private func reorderItem(
            _ item: DragCoordinator.DraggedItem,
            from origin: ItemPosition,
            to target: ItemPosition,
        ) -> Bool {
            switch target.collection {
            case .favorites:
                guard case let .favorite(favorite) = item else { return false }
                return tabManager.reorderFavorite(favorite, to: target.localIndex)

            case .pinned, .normal:
                // Use local indices for the tab list (excludes favorites)
                // TabManager expects indices relative to pinnedItems+normalItems array
                let bounds = layoutManager.collectionBounds
                let localOrigin = origin.globalIndex(bounds: bounds) - globalIndexOffset
                let localTarget = target.globalIndex(bounds: bounds) - globalIndexOffset

                if case let .tab(tab) = item {
                    return tabManager.reorderTab(tab, from: localOrigin, to: localTarget, in: target.collection, using: layoutManager)
                } else if case let .group(group) = item {
                    return tabManager.reorderGroup(group, from: localOrigin, to: localTarget, in: target.collection, using: layoutManager)
                }
                return false
            }
        }

        /// Check if a dragged item is currently active.
        ///
        /// Used to capture active state at drag start so it can be preserved during
        /// return animation when the underlying state changes.
        private func isItemActive(_ item: DraggedItem) -> Bool {
            switch item {
            case let .favorite(favorite):
                if case let .liveFavorite(_, tab) = favorite.type {
                    return windowState.activeTabID == tab.id
                }
                return false
            case let .tab(tab):
                return tab.id == windowState.activeTabID
            case .group:
                return false
            }
        }

        // MARK: - Multi-Item Commit Helpers

        /// Commit reorder operation for single or multiple tabs.
        ///
        /// For multi-selection drags, only the main item (grabbed by cursor) participates
        /// in drag logic. Follower items are then repositioned after the main item.
        ///
        /// If tabs are being dragged out of the archive group, they are restored first.
        private func commitReorder(to target: ItemPosition) -> Bool {
            guard let mainItem = primaryDraggedItem,
                  let origin = _originPosition else { return false }

            // Handle drag-out-of-archive: restore archived tabs being moved
            if let mainTab = mainItem.tab, mainTab.isArchived {
                let archivedFollowers = followerItems.compactMap(\.tab).filter(\.isArchived)
                tabManager.archiveManager.restoreTabs([mainTab] + archivedFollowers)
            }

            // Step 1: Move main item using standard single-item logic
            let mainMoved = reorderItem(
                mainItem,
                from: origin,
                to: target,
            )

            if !mainMoved { return false }

            // Step 2: Insert followers after main item (preserving relative order)
            if !followerItems.isEmpty, let mainTab = mainItem.tab {
                layoutManager.rebuildLayout()

                // Find where main item ended up
                let mainNewIndex = findCurrentIndex(for: mainTab)

                // Insert each follower after the previous one
                var insertIndex = mainNewIndex + 1
                for follower in followerItems {
                    guard let tab = follower.tab else { continue }

                    // Follower adopts main item's pin state (cross-collection move)
                    if tab.isPinned != mainTab.isPinned {
                        tab.isPinned = mainTab.isPinned
                    }

                    // Remove from any group (followers follow main's context)
                    if tab.groupID != nil {
                        tabManager.groupManager.removeTabFromGroup(tab, skipReordering: true)
                    }

                    // Find current position and move to target
                    let currentIndex = findCurrentIndex(for: tab)
                    if tabManager.reorderTab(
                        tab,
                        from: currentIndex,
                        to: insertIndex,
                        in: target.collection,
                        using: layoutManager,
                    ) {
                        layoutManager.rebuildLayout()
                        // Update insert index for next follower
                        insertIndex = findCurrentIndex(for: tab) + 1
                    }
                }
            }

            // Clear follower state
            hiddenFollowerIDs = []

            return true
        }

        /// Find the current global index of a tab in the layout.
        private func findCurrentIndex(for tab: Tab) -> Int {
            if tab.isPinned {
                return layoutManager.pinnedItems.firstIndex { $0.tab?.id == tab.id } ?? 0
            } else {
                let normalIndex = layoutManager.normalItems.firstIndex { $0.tab?.id == tab.id } ?? 0
                return layoutManager.pinnedItems.count + normalIndex
            }
        }

        /// Commit convert-to-favorites operation for main item and followers.
        private func commitConvertToFavorites(mode: FavoriteMode) -> Bool {
            // Get all tabs: main item + followers
            let mainTabs = draggedItems.compactMap(\.tab)
            let followerTabs = followerItems.compactMap(\.tab)
            let allTabs = mainTabs + followerTabs
            guard !allTabs.isEmpty else { return false }

            var anyConverted = false
            for (index, tab) in allTabs.enumerated() {
                if let bookmarkID = tabManager.convertTabToFavorite(tab, mode: mode) {
                    anyConverted = true
                    // Store first converted item's ID to hide during return animation
                    if index == 0 {
                        _convertedItemID = bookmarkID
                    }
                }
            }

            hiddenFollowerIDs = []
            return anyConverted
        }

        /// Commit add-to-group operation for main item and followers.
        ///
        /// If the target group is an archive group, tabs are archived instead of
        /// simply being added to the group.
        private func commitAddToGroup(groupID: UUID) -> Bool {
            // Get all tabs: main item + followers
            let mainTabs = draggedItems.compactMap(\.tab)
            let followerTabs = followerItems.compactMap(\.tab)
            let allTabs = mainTabs + followerTabs
            guard !allTabs.isEmpty else { return false }

            // Check if target group is the archive
            if let firstTab = allTabs.first,
               let space = firstTab.space,
               let targetGroup = space.groups.first(where: { $0.id == groupID }),
               targetGroup.isArchive {
                // Dragging into archive = archive the tabs
                let archived = tabManager.archiveManager.archiveBatch(allTabs)
                hiddenFollowerIDs = []
                return archived > 0
            }

            // Normal add to group
            var anyAdded = false
            for tab in allTabs {
                if tabManager.addTabToGroup(tab, groupID: groupID) {
                    anyAdded = true
                }
            }

            hiddenFollowerIDs = []
            return anyAdded
        }
        
        /// Cancel the drag without committing
        func cancelDrag() {
            // Capture items that need to animate back
            let itemsToAnimate = Set(itemPushOffsets.keys)

            // Calculate overlay target position (back to original)
            let originalFrame = _draggedItemOriginalFrame ?? .zero
            let originalCenter = CGPoint(
                x: originalFrame.midX,
                y: originalFrame.midY,
            )

            isAnimatingReturn = true

            // Reset nesting level modified during drag without expensive rebuild
            resetDraggedItemNestingLevel()

            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                currentOffset = 0

                // Animate all items back to their original positions
                for itemID in itemsToAnimate {
                    itemPushOffsets[itemID] = .zero
                }

                // Animate overlay back to original position
                overlayPosition = originalCenter
            }

            scheduleCleanup()
        }
        
        /// Update overlay position in sidebar coordinate space
        func updateOverlayPosition(_ position: CGPoint) {
            if isAnimatingReturn {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    overlayPosition = position
                }
            } else {
                overlayPosition = position
            }
        }

        func updateFavoritesGridFrame(_ frame: CGRect) {
            state.updateFavoritesGridFrame(frame)
        }

        /// Update the complete sidebar bounds from geometry preference.
        ///
        /// Called by Sidebar.swift when the sidebar frame changes. This provides
        /// an authoritative bounds for handoff detection that stays current
        /// regardless of scroll, filter, or layout animation state.
        func updateSidebarBounds(_ bounds: CGRect) {
            state.updateSidebarBounds(bounds)
        }

        /// Update the favorites grid layout info for offset calculations.
        ///
        /// Called by FavoritesGrid when layout changes (column count, tile size).
        func updateFavoritesGridLayout(columns: Int, tileSize: CGSize, spacing: CGFloat) {
            state.updateFavoritesGridLayout(columns: columns, tileSize: tileSize, spacing: spacing)
        }

        /// Clear the favorites grid layout info when favorites become empty.
        ///
        /// Called by FavoritesGrid when all favorites are removed to prevent stale values.
        func clearFavoritesGridLayout() {
            state.clearFavoritesGridLayout()
        }

        // MARK: - Frame Access (delegated to Sidebar.GeometryState)

        /// Returns the item's frame from Sidebar.GeometryState.
        func computedItemFrame(for itemID: UUID) -> CGRect? {
            state.itemFrame(for: itemID)
        }

        /// Computed pinned section frame (delegated to Sidebar.GeometryState).
        var computedPinnedSectionFrame: CGRect {
            state.computedPinnedSectionFrame
        }

        /// Computed normal section frame (delegated to Sidebar.GeometryState).
        var computedNormalSectionFrame: CGRect {
            state.computedNormalSectionFrame
        }

        // MARK: - Target Calculation

        /// Result of calculating drag target indices for both visual feedback and drop targeting.
        ///
        /// This provides consistent calculations for:
        /// - Drop target determination (where to insert the item)
        /// - Affected items calculation (which items to push aside)
        struct DragTargetCalculation {
            /// Number of external items the drag has crossed.
            let itemsCrossed: Int

            /// The header's target index (where the dragged item/group header will be placed).
            let headerTargetIndex: Int

            /// For range checking: the effective origin index.
            /// - Single items: same as header origin
            /// - Groups dragging UP: header origin
            /// - Groups dragging DOWN: last item in group (bottom of group)
            let effectiveOrigin: Int

            /// For range checking: the effective target index.
            /// - Single items: same as headerTargetIndex
            /// - Groups: adjusted based on direction and group size
            let effectiveTarget: Int

            /// Whether we're dragging upward (negative offset).
            let isDraggingUp: Bool

            /// The visible group size (1 for single items, header + descendants for groups).
            let visibleGroupSize: Int
        }

        /// Calculates target indices for the current drag state.
        ///
        /// For groups, the key insight is:
        /// - **UP**: Items above the header should react. The header's target is the insertion point.
        /// - **DOWN**: Items below the group's BOTTOM should react. We use tabSlotHeight
        ///   (not groupSlotHeight) to determine when external items are crossed.
        ///
        /// This ensures both visual feedback (push-asides) and drop targeting use identical logic.
        func calculateDragTarget() -> DragTargetCalculation? {
            guard let origin = _originPosition else { return nil }

            let isDraggingUp = currentOffset < 0
            let tabSlotHeight = state.slotHeight
            let bounds = layoutManager.collectionBounds
            let originGlobalIndex = origin.globalIndex(bounds: bounds)
            let originLocalIndex = localIndex(from: originGlobalIndex)

            let draggedGroup = primaryDraggedItem?.group
            let isDraggingGroup = draggedGroup != nil

            // For collapsed groups, only the header is visible - treat as size 1
            let visibleGroupSize: Int = if let group = draggedGroup, group.isCollapsed {
                1
            } else if isDraggingGroup {
                _draggedItemExclusionSet.count
            } else {
                1
            }

            // Calculate how many EXTERNAL items the drag has crossed.
            // Always use tabSlotHeight - we're counting individual item crossings.
            let threshold = tabSlotHeight * 0.5
            let itemsCrossed = Int((currentOffset + (isDraggingUp ? -threshold : threshold)) / tabSlotHeight)

            // Header target: where the header will be placed
            let rawHeaderTarget = originGlobalIndex + itemsCrossed

            // Clamp to valid range
            let minTarget = globalIndexOffset
            let maxTarget = getAllItems().count + globalIndexOffset - 1
            var headerTargetIndex = max(minTarget, min(maxTarget, rawHeaderTarget))

            // Clamp to source collection range
            switch origin.collection {
            case .pinned:
                let pinnedRange = bounds.pinned
                if !pinnedRange.isEmpty, pinnedRange.contains(originGlobalIndex) {
                    headerTargetIndex = max(pinnedRange.lowerBound, min(pinnedRange.upperBound - 1, headerTargetIndex))
                }
            case .normal:
                let normalRange = bounds.normal
                if !normalRange.isEmpty, normalRange.contains(originGlobalIndex) {
                    headerTargetIndex = max(normalRange.lowerBound, min(normalRange.upperBound - 1, headerTargetIndex))
                }
            case .favorites:
                break
            }

            let headerTargetLocalIndex = localIndex(from: headerTargetIndex)

            // Effective indices for range checking (affected items)
            let effectiveOrigin: Int
            let effectiveTarget: Int

            if isDraggingUp {
                // UP: check from header, target is where header moves to
                effectiveOrigin = originLocalIndex
                effectiveTarget = headerTargetLocalIndex
            } else {
                // DOWN: check from bottom of group, target adjusted for group size
                effectiveOrigin = originLocalIndex + visibleGroupSize - 1
                effectiveTarget = headerTargetLocalIndex + visibleGroupSize - 1
            }

            return DragTargetCalculation(
                itemsCrossed: itemsCrossed,
                headerTargetIndex: headerTargetIndex,
                effectiveOrigin: effectiveOrigin,
                effectiveTarget: effectiveTarget,
                isDraggingUp: isDraggingUp,
                visibleGroupSize: visibleGroupSize,
            )
        }
    }
}

// MARK: - CGRect Approximate Equality

private extension CGRect {
    /// Checks if this rect is approximately equal to another within a tolerance.
    ///
    /// Used to skip frame updates during scroll when changes are negligible.
    func isAlmostEqual(to other: CGRect, tolerance: CGFloat) -> Bool {
        abs(origin.x - other.origin.x) <= tolerance
            && abs(origin.y - other.origin.y) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}
