import Foundation
import SwiftUI

extension Sidebar {
    /// Shared geometry state for sidebar layout calculations.
    ///
    /// `Sidebar.GeometryState` is the single source of truth for sidebar geometry, holding
    /// scroll position and layout data needed for frame calculations. This centralizes
    /// state that was previously scattered across DragCoordinator and other components.
    ///
    /// ## Purpose
    ///
    /// - Single source of truth for sidebar geometry
    /// - Enables computed item frames without storing per-item frame data
    /// - Decouples frame calculation from drag coordination
    /// - Shared by DragCoordinator, MiddleClickCoordinator, and other consumers
    ///
    /// ## Geometry Sources
    ///
    /// The state is updated from multiple SwiftUI geometry observers:
    /// - `currentScrollTopInset` / `documentToSidebarOffset`: From NSScrollView
    /// - `sidebarBounds`: From the sidebar container
    /// - `favoritesGridFrame`: From the favorites grid section
    ///
    /// ## Usage
    ///
    /// Inject via environment and access frame calculations:
    /// ```swift
    /// @Environment(Sidebar.GeometryState.self) private var geometryState
    ///
    /// let frame = geometryState.itemFrame(for: itemID)
    /// ```
    @Observable
    final class GeometryState {
        // MARK: - Dependencies

        unowned var layoutManager: LayoutManager!

        // MARK: - Scroll Position

        /// Current scroll view top content inset (header height).
        ///
        /// Used by ActiveTabIndicator to determine the visible content area.
        /// Observable — triggers indicator updates when header height changes.
        var currentScrollTopInset: CGFloat = 0

        /// Offset from document coordinates to sidebar-local coordinates.
        ///
        /// `sidebarLocalY = documentY + documentToSidebarOffset`
        ///
        /// `@ObservationIgnored` because this changes on every scroll frame and is
        /// only consumed by DragCoordinator's frame calculations (not by views).
        /// Making this observable would create a feedback loop:
        /// scroll → write offset → Sidebar re-renders → updateNSView → write offset → ...
        @ObservationIgnored
        var documentToSidebarOffset: CGFloat = 0

        // MARK: - Active Tab Scroll Position

        /// Whether the active tab is scrolled above, below, or within the visible area.
        ///
        /// Computed from the scroll handler and only triggers observation when the
        /// state actually changes (visible ↔ above ↔ below), not on every scroll frame.
        /// Used by `ActiveTabIndicator` instead of computing from `itemFrame(for:)`,
        /// which depends on the non-observable `documentToSidebarOffset`.
        var activeTabScrollPosition: ActiveTabScrollPosition = .visible

        enum ActiveTabScrollPosition: Equatable {
            case visible
            case above
            case below
        }

        /// Recompute `activeTabScrollPosition` from current scroll and layout state.
        ///
        /// Called from the scroll handler (every frame) and from `updateNSView`
        /// (when the active tab changes). Only writes when the state actually
        /// changed to avoid unnecessary observation triggers.
        func updateActiveTabScrollPosition(activeTabID: UUID?) {
            guard let activeTabID,
                  let frame = itemFrame(for: activeTabID)
            else {
                if activeTabScrollPosition != .visible {
                    activeTabScrollPosition = .visible
                }
                return
            }

            let visibleTop = sidebarBounds.minY + currentScrollTopInset
            let visibleBottom = sidebarBounds.maxY - bottomControlsHeight

            guard visibleBottom > visibleTop else {
                if activeTabScrollPosition != .visible {
                    activeTabScrollPosition = .visible
                }
                return
            }

            let newPosition: ActiveTabScrollPosition =
                if frame.maxY <= visibleTop { .above }
                else if frame.minY >= visibleBottom { .below }
                else { .visible }

            if activeTabScrollPosition != newPosition {
                activeTabScrollPosition = newPosition
            }
        }

        /// Height of the bottom controls area (space picker, filter, media panel, etc).
        ///
        /// Tracked separately via `onGeometryChange` because the bottom controls are
        /// applied as a `safeAreaInset` AFTER the scroll geometry handler, so
        /// `ScrollGeometry.contentInsets.bottom` doesn't include their height.
        var bottomControlsHeight: CGFloat = 0

        // MARK: - Sidebar Geometry

        /// Complete sidebar bounds in window coordinate space.
        ///
        /// Updated via geometry preference from the Sidebar container.
        @ObservationIgnored
        private(set) var sidebarBounds: CGRect = .zero

        /// Favorites grid frame in window coordinate space.
        private(set) var favoritesGridFrame: CGRect = .zero

        /// Grid layout info for favorites (captured from FavoritesGrid).
        @ObservationIgnored
        var favoritesGridLayout: GridLayoutInfo?

        /// Grid layout information for favorites.
        struct GridLayoutInfo {
            let columns: Int
            let tileSize: CGSize
            let spacing: CGFloat

            /// Stride between tile centers horizontally.
            var horizontalStride: CGFloat {
                tileSize.width + spacing
            }

            /// Stride between tile centers vertically.
            var verticalStride: CGFloat {
                tileSize.height + spacing
            }
        }

        // MARK: - Layout Constants

        /// Tab row X origin in global coordinates.
        ///
        /// This is the outer frame origin, not the content origin. The cell applies
        /// `.padding(.horizontal, tabHorizontalPadding)` internally, which is accounted
        /// for in the width calculation but not the X origin.
        var tabsOriginX: CGFloat {
            sidebarBounds.minX
        }

        /// Extra padding between the header and the first tab row.
        ///
        /// With NSTableView, this padding is baked into the scroll view's content
        /// inset (via `topPadding` in `RecyclingTabListView.Coordinator`), so
        /// `documentToSidebarOffset` already accounts for it. Set to 0 to avoid
        /// double-counting.
        let scrollViewInsetPadding: CGFloat = 0

        /// All tabs have the same slot height (item + spacing).
        var slotHeight: CGFloat {
            Constants.Layout.tabItemHeight + Constants.Layout.tabSpacing
        }

        /// Divider height including vertical padding.
        let dividerHeight: CGFloat = 2 + 1 + 2

        /// Width of tab cell frames (full sidebar width).
        ///
        /// Padding is internal to the cell (`.padding(.horizontal, tabHorizontalPadding)`),
        /// not a reduction of the frame width.
        var tabsWidth: CGFloat {
            sidebarBounds.width
        }

        // MARK: - Section Geometry

        /// Pinned section minY in global (screen) coordinates.
        ///
        /// First cell is at document Y = `scrollViewInsetPadding` (8pt).
        /// Converted to global via `documentToSidebarOffset` + `sidebarBounds.minY`.
        var pinnedSectionMinY: CGFloat {
            sidebarBounds.minY + scrollViewInsetPadding + documentToSidebarOffset
        }

        /// Normal section minY in window coordinates.
        var normalSectionMinY: CGFloat {
            let spacing = Constants.Layout.tabSpacing
            guard !layoutManager.pinnedItems.isEmpty else {
                let tabListMinY = pinnedSectionMinY
                let addTabHeight = slotHeight
                return tabListMinY + addTabHeight
            }
            let pinnedSectionMaxY = computedPinnedSectionFrame.maxY
            let addTabHeight = spacing + slotHeight

            return pinnedSectionMaxY + dividerHeight + addTabHeight + spacing
        }

        /// Computed pinned section frame from item count and geometry.
        var computedPinnedSectionFrame: CGRect {
            let items = layoutManager.pinnedItems
            guard !items.isEmpty else { return .zero }

            let itemsCount = CGFloat(items.count)
            let pinnedSectionHeight = itemsCount * slotHeight - Constants.Layout.tabSpacing

            return CGRect(
                x: tabsOriginX,
                y: pinnedSectionMinY,
                width: tabsWidth,
                height: pinnedSectionHeight,
            )
        }

        /// Computed normal section frame.
        ///
        /// Height extends to sidebar bounds since normal section scrolls.
        var computedNormalSectionFrame: CGRect {
            CGRect(
                x: tabsOriginX,
                y: normalSectionMinY,
                width: tabsWidth,
                height: sidebarBounds.height,
            )
        }

        // MARK: - Frame Updates

        func updateSidebarBounds(_ bounds: CGRect) {
            sidebarBounds = bounds
        }

        func updateFavoritesGridFrame(_ frame: CGRect) {
            favoritesGridFrame = frame
        }

        func updateFavoritesGridLayout(columns: Int, tileSize: CGSize, spacing: CGFloat) {
            favoritesGridLayout = GridLayoutInfo(
                columns: columns,
                tileSize: tileSize,
                spacing: spacing,
            )
        }

        func clearFavoritesGridLayout() {
            favoritesGridLayout = nil
        }

        // MARK: - Item Frame Calculation

        /// Computes the frame for an item based on current scroll position and layout.
        ///
        /// - Parameter itemID: The item's unique identifier.
        /// - Returns: The computed frame in window coordinates, or nil if not found.
        func itemFrame(for itemID: UUID) -> CGRect? {
            // Read frameGeneration to establish observation dependency.
            // Without this, if metadata[itemID] is nil (tab just created, layout
            // not yet rebuilt), we return nil without observing any @Observable
            // property. When layout rebuilds and increments frameGeneration,
            // callers re-evaluate and find the metadata.
            _ = layoutManager.frameGeneration

            guard let metadata = layoutManager.metadata[itemID] else {
                return nil
            }

            return computeFrame(for: itemID, metadata: metadata)
        }

        /// Internal frame computation.
        func computeFrame(for itemID: UUID, metadata: LayoutManager.ItemMetadata) -> CGRect? {
            let itemHeight = Constants.Layout.tabItemHeight

            switch metadata.collection {
            case .pinned:
                guard let localIndex = layoutManager.pinnedItems.firstIndex(where: { $0.id == itemID }) else {
                    return nil
                }

                let y = pinnedSectionMinY + CGFloat(localIndex) * slotHeight
                let nestingLevelShrink = CGFloat(metadata.nestingLevel) * Constants.Layout.nestingLevelPadding
                return CGRect(
                    x: tabsOriginX + nestingLevelShrink,
                    y: y,
                    width: tabsWidth - nestingLevelShrink,
                    height: itemHeight,
                )

            case .normal:
                guard let localIndex = layoutManager.normalItems.firstIndex(where: { $0.id == itemID }) else {
                    return nil
                }

                let y = normalSectionMinY + CGFloat(localIndex) * slotHeight
                let nestingLevelShrink = CGFloat(metadata.nestingLevel) * Constants.Layout.nestingLevelPadding
                return CGRect(
                    x: tabsOriginX + nestingLevelShrink,
                    y: y,
                    width: tabsWidth - nestingLevelShrink,
                    height: itemHeight,
                )

            case .favorites:
                guard let gridLayout = favoritesGridLayout,
                      let localIndex = layoutManager.favoritesLayout.firstIndex(where: { $0.id == itemID }) else {
                    return nil
                }

                let row = localIndex / gridLayout.columns
                let col = localIndex % gridLayout.columns

                let x = favoritesGridFrame.minX + CGFloat(col) * (gridLayout.tileSize.width + gridLayout.spacing)
                let y = favoritesGridFrame.minY + CGFloat(row) * (gridLayout.tileSize.height + gridLayout.spacing)

                return CGRect(
                    x: x,
                    y: y,
                    width: gridLayout.tileSize.width,
                    height: gridLayout.tileSize.height,
                )
            }
        }
    }
}
