import SwiftUI

/// Custom layout for the favorites grid that properly participates in SwiftUI's layout negotiation.
///
/// ## Why a Custom Layout?
///
/// The previous implementation computed grid dimensions from external state (`windowState.sidebarThickness`)
/// rather than responding to SwiftUI's size proposals. This created layout issues:
/// - The grid declared fixed sizes without knowing actual available space
/// - Sibling views could be forced larger than necessary
/// - Padding calculations were fragile and duplicated
///
/// This layout receives size proposals, responds with what it needs, and places children correctly.
///
/// ## Algorithm
///
/// 1. **sizeThatFits**: Given a proposed width, calculate how many columns fit and the resulting height
/// 2. **placeSubviews**: Position each child in row-major order with calculated tile sizes
///
/// ## Integration with Drag Coordinator
///
/// The layout reports its computed parameters (columns, tile size, spacing) via the cache,
/// which `FavoritesGrid` can read after layout to update the drag coordinator.
struct AdaptiveFavoritesGridLayout: Layout {
    /// Configuration for the grid layout.
    ///
    /// Marked `Sendable` because `Layout` protocol methods are nonisolated and
    /// configuration values need to cross isolation boundaries.
    nonisolated struct Configuration: Sendable {
        let minTileWidth: CGFloat
        let tileHeight: CGFloat
        let maxColumns: Int
        let spacing: CGFloat
    }

    /// Cache storing computed layout parameters for external consumption.
    struct LayoutCache {
        var columns: Int = 1
        var tileWidth: CGFloat = 0
        var tileHeight: CGFloat = 0
        var spacing: CGFloat = 0
        var totalSize: CGSize = .zero
    }

    let configuration: Configuration

    init(configuration: Configuration) {
        self.configuration = configuration
    }

    // MARK: - Layout Protocol

    func makeCache(subviews _: Subviews) -> LayoutCache {
        LayoutCache(tileHeight: configuration.tileHeight, spacing: configuration.spacing)
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout LayoutCache) -> CGSize {
        let itemCount = subviews.count
        guard itemCount > 0 else {
            cache.totalSize = .zero
            return .zero
        }

        // Use proposed width, falling back to minimum sensible width.
        // Guard against infinite proposals (which SwiftUI can send during layout negotiation).
        let proposedWidth = proposal.width ?? 0
        let availableWidth: CGFloat
        if proposedWidth.isFinite, proposedWidth > 0 {
            availableWidth = proposedWidth
        } else {
            // Fallback: use max columns at minimum tile width
            let fallbackWidth = CGFloat(configuration.maxColumns) * configuration.minTileWidth
                + CGFloat(configuration.maxColumns - 1) * configuration.spacing
            availableWidth = fallbackWidth
        }

        // Calculate columns that fit
        let columns = columnsForWidth(availableWidth, itemCount: itemCount)
        let tileWidth = tileWidthForColumns(columns, in: availableWidth)

        // Calculate rows needed
        let rows = (itemCount + columns - 1) / columns

        // Calculate total height
        let totalHeight = CGFloat(rows) * configuration.tileHeight + CGFloat(max(0, rows - 1)) * configuration.spacing

        // Update cache for external consumption
        cache.columns = columns
        cache.tileWidth = tileWidth
        cache.tileHeight = configuration.tileHeight
        cache.spacing = configuration.spacing
        cache.totalSize = CGSize(width: availableWidth, height: totalHeight)

        return CGSize(width: availableWidth, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout LayoutCache) {
        guard !subviews.isEmpty else { return }

        let columns = cache.columns
        let tileWidth = cache.tileWidth
        let tileHeight = cache.tileHeight
        let spacing = cache.spacing

        // Size proposal for each tile
        let tileProposal = ProposedViewSize(width: tileWidth, height: tileHeight)

        for (index, subview) in subviews.enumerated() {
            let row = index / columns
            let col = index % columns

            let x = bounds.minX + CGFloat(col) * (tileWidth + spacing)
            let y = bounds.minY + CGFloat(row) * (tileHeight + spacing)

            subview.place(
                at: CGPoint(x: x, y: y),
                anchor: .topLeading,
                proposal: tileProposal,
            )
        }
    }

    // MARK: - Layout Calculations

    /// Calculate number of columns that fit in available width.
    private func columnsForWidth(_ width: CGFloat, itemCount: Int) -> Int {
        guard itemCount > 0, width > 0, width.isFinite else { return 1 }

        // Calculate max columns that fit: (width + spacing) / (minTileWidth + spacing)
        // This accounts for n-1 spacings between n columns
        let ratio = (width + configuration.spacing) / (configuration.minTileWidth + configuration.spacing)
        guard ratio.isFinite else { return configuration.maxColumns }
        let maxFitting = Int(ratio)

        // Clamp between 1 and min(itemCount, maxColumns)
        return max(1, min(min(itemCount, configuration.maxColumns), maxFitting))
    }

    /// Calculate tile width to fill available space evenly.
    private func tileWidthForColumns(_ columns: Int, in width: CGFloat) -> CGFloat {
        guard columns > 0 else { return configuration.minTileWidth }

        let totalSpacing = configuration.spacing * CGFloat(columns - 1)
        let availableForTiles = width - totalSpacing
        return max(configuration.minTileWidth, availableForTiles / CGFloat(columns))
    }
}

// MARK: - Layout Result Accessor

extension AdaptiveFavoritesGridLayout {
    /// Extracts the computed layout parameters after layout has occurred.
    ///
    /// This is used by `FavoritesGrid` to report layout info to the drag coordinator
    /// without recomputing it.
    struct LayoutResult {
        let columns: Int
        let tileSize: CGSize
        let spacing: CGFloat

        init(from cache: LayoutCache) {
            self.columns = cache.columns
            self.tileSize = CGSize(width: cache.tileWidth, height: cache.tileHeight)
            self.spacing = cache.spacing
        }
    }
}

// MARK: - Preference Key for Layout Info

/// Preference key to propagate computed layout info from the layout to the view.
struct AdaptiveFavoritesGridLayoutInfoKey: PreferenceKey {
    static let defaultValue: AdaptiveFavoritesGridLayout.LayoutResult? = nil

    static func reduce(value: inout AdaptiveFavoritesGridLayout.LayoutResult?, nextValue: () -> AdaptiveFavoritesGridLayout.LayoutResult?) {
        value = nextValue() ?? value
    }
}
