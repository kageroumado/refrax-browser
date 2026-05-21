import SwiftUI

/// Responsive grid of favorite bookmarks displayed at the top of the sidebar.
///
/// Favorites are space-independent and always visible. They can be:
/// - **Live tabs**: Persistent tabs that activate when clicked
/// - **Shortcuts**: Navigate current tab to URL
/// - **Folders**: Collections of bookmarks
///
/// ## Layout
///
/// Uses `AdaptiveFavoritesGridLayout`, a custom `Layout` implementation that properly participates
/// in SwiftUI's layout negotiation. This ensures the grid responds to actual available
/// space rather than computing size from external state, fixing sibling view sizing issues.
///
/// ## Drag & Drop
///
/// - Drag tiles to reorder within grid
/// - Drag tabs from tab list into grid to create favorites (shows mode selection sheet)
/// - Drag favorites into tab list to activate/create tabs
struct FavoritesGrid: View {
    @Environment(BookmarksManager.self) private var bookmarksManager
    @Environment(Sidebar.LayoutManager.self) private var layoutManager
    @Environment(Sidebar.DragCoordinator.self) private var dragCoordinator

    /// Stores the measured width from geometry change to compute layout params for drag coordinator.
    @State private var measuredWidth: CGFloat = 0

    var body: some View {
        Group {
            if !layoutManager.favoritesLayout.isEmpty {
                AdaptiveFavoritesGridLayout(configuration: gridConfiguration) {
                    ForEach(layoutManager.favoritesLayout) { item in
                        gridItem(for: item)
                    }
                }
                .accessibilityIdentifier("FavoritesGrid")
                .onGeometryChange(for: CGRect.self) { geo in
                    geo.frame(in: .global)
                } action: { frame in
                    handleGeometryChange(frame)
                }
                // Placeholder padding that maintains grid height when a row is removed.
                // This prevents the tab list from jumping up during FAV→TAB conversion.
                // The compensation is set at commit time and animated to zero.
                .padding(.bottom, dragCoordinator._gridShrinkCompensation)
                .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragCoordinator._gridShrinkCompensation)
            } else if dragCoordinator._gridShrinkCompensation > 0 {
                // When all favorites removed during animation, maintain height with spacer.
                // This prevents the header from abruptly shrinking before the return animation completes.
                Color.clear
                    .frame(height: dragCoordinator._gridShrinkCompensation)
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: dragCoordinator._gridShrinkCompensation)
            }
        }
        // Reset frame and layout info when favorites become empty.
        // The onGeometryChange inside the conditional view never fires when
        // favorites become empty (the view disappears), leaving stale values.
        .onChange(of: layoutManager.favoritesLayout.isEmpty) { _, isEmpty in
            if isEmpty {
                dragCoordinator.updateFavoritesGridFrame(.zero)
                dragCoordinator.clearFavoritesGridLayout()
            }
        }
        // Update layout when favorites count changes (affects column count and tile width).
        // The onGeometryChange only fires when the frame changes, but adding/removing
        // items can change the column layout without changing the frame dimensions.
        .onChange(of: layoutManager.favoritesLayout.count) { _, count in
            guard count > 0, measuredWidth > 0 else { return }
            let params = computeLayoutParams(for: measuredWidth)
            dragCoordinator.updateFavoritesGridLayout(
                columns: params.columns,
                tileSize: CGSize(width: params.tileWidth, height: Metrics.tileHeight),
                spacing: Metrics.spacing,
            )
        }
    }

    // MARK: - Grid Configuration

    private var gridConfiguration: AdaptiveFavoritesGridLayout.Configuration {
        AdaptiveFavoritesGridLayout.Configuration(
            minTileWidth: Metrics.minTileWidth,
            tileHeight: Metrics.tileHeight,
            maxColumns: Metrics.maxColumns,
            spacing: Metrics.spacing,
        )
    }

    // MARK: - Grid Item

    @ViewBuilder
    private func gridItem(for item: FavoriteItem) -> some View {
        let offset = dragCoordinator.itemPushOffsets[item.id] ?? .zero
        let isHidden = shouldHideItem(item.id)

        FavoriteTileView(
            item: item,
            isDragging: dragCoordinator.isItemBeingDragged(item.id),
            shouldShowTitle: false,
        )
        .offset(x: offset.x, y: offset.y)
        // Smooth animation for grid reordering - uses single CGPoint to avoid 2N animation watchers
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: offset)
        .opacity(isHidden ? 0 : 1)
        .gesture(favoriteDragGesture(for: item))
    }

    // MARK: - Layout Calculation for Drag Coordinator

    /// Computes layout parameters from measured width for drag coordinator.
    ///
    /// Uses the same algorithm as `AdaptiveFavoritesGridLayout` to ensure consistency.
    /// This is computed from actual rendered width, not external state.
    private func computeLayoutParams(for width: CGFloat) -> (columns: Int, tileWidth: CGFloat) {
        let itemCount = layoutManager.favoritesLayout.count
        guard itemCount > 0, width > 0 else { return (1, Metrics.minTileWidth) }

        // Calculate columns (same algorithm as AdaptiveFavoritesGridLayout)
        let maxFitting = Int((width + Metrics.spacing) / (Metrics.minTileWidth + Metrics.spacing))
        let columns = max(1, min(min(itemCount, Metrics.maxColumns), maxFitting))

        // Calculate tile width
        let totalSpacing = Metrics.spacing * CGFloat(columns - 1)
        let availableForTiles = width - totalSpacing
        let tileWidth = max(Metrics.minTileWidth, availableForTiles / CGFloat(columns))

        return (columns, tileWidth)
    }

    private func handleGeometryChange(_ frame: CGRect) {
        dragCoordinator.updateFavoritesGridFrame(frame)

        // Compute layout params from actual rendered width
        let width = frame.width
        if width != measuredWidth {
            measuredWidth = width
        }

        let params = computeLayoutParams(for: width)
        dragCoordinator.updateFavoritesGridLayout(
            columns: params.columns,
            tileSize: CGSize(width: params.tileWidth, height: Metrics.tileHeight),
            spacing: Metrics.spacing,
        )
    }

    // MARK: - Drag Gesture

    private func favoriteDragGesture(for item: FavoriteItem) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .global)
            .onChanged { value in
                guard !dragCoordinator.isAnimatingReturn else { return }

                if !dragCoordinator.isDragging,
                   let metadata = layoutManager.metadata[item.id] {
                    dragCoordinator.startDrag(
                        item: .favorite(item),
                        originPosition: ItemPosition.from(metadata: metadata),
                        startLocation: value.startLocation,
                    )
                }

                // updateDrag handles overlayPosition internally, ensuring grid offset
                // calculations use the current position (not the previous frame's)
                dragCoordinator.updateDrag(
                    offset: value.translation.height,
                    location: value.location,
                )
            }
            .onEnded { _ in
                dragCoordinator.commitDrag()
            }
    }

    private func shouldHideItem(_ itemID: UUID) -> Bool {
        // Hide dragged item immediately (shown in overlay instead).
        // Uses isDragging (observed) to ensure re-render when drag ends,
        // since isItemBeingDragged reads from @ObservationIgnored draggedItems.
        if dragCoordinator.isDragging, dragCoordinator.isItemBeingDragged(itemID) {
            return true
        }

        // Hide newly converted favorite during return animation (TAB→FAV).
        // The overlay animates to this position, then reveals the real item.
        if dragCoordinator.isAnimatingReturn, itemID == dragCoordinator._convertedItemID {
            return true
        }

        return false
    }
}

// MARK: - Batch Frame Capture

/// Preference key aggregating anchors from all visible favorite items.
///
// MARK: - Metrics

private enum Metrics {
    static let spacing: CGFloat = 8
    static let minTileWidth: CGFloat = Constants.Layout.tabItemHeight * 1.5
    static let tileHeight: CGFloat = Constants.Layout.tabItemHeight * 1.5
    static let maxColumns: Int = 4
}
