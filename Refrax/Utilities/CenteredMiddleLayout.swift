import SwiftUI

/// A layout that places leading/trailing views at edges and centers the middle view.
/// The middle view only shifts from center when it would otherwise overlap the edges.
struct CenteredMiddleLayout: Layout {
    /// Minimum spacing between the center view and the leading/trailing views.
    var spacing: CGFloat = 8

    struct CacheData {
        var leadingSize: CGSize = .zero
        var centerSize: CGSize = .zero
        var trailingSize: CGSize = .zero
        var totalHeight: CGFloat = 0
    }

    static var layoutProperties: LayoutProperties {
        var properties = LayoutProperties()
        properties.stackOrientation = .horizontal
        return properties
    }
    
    func makeCache(subviews: Subviews) -> CacheData {
        var cache = CacheData()
        updateCache(&cache, subviews: subviews)
        return cache
    }
    
    func updateCache(_ cache: inout CacheData, subviews: Subviews) {
        guard subviews.count == 3 else { return }

        cache.leadingSize = subviews[0].sizeThatFits(.unspecified)
        // Center size is computed at placement time based on available width
        cache.centerSize = subviews[1].sizeThatFits(.unspecified)
        cache.trailingSize = subviews[2].sizeThatFits(.unspecified)
        cache.totalHeight = max(cache.leadingSize.height, cache.centerSize.height, cache.trailingSize.height)
    }
    
    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache: inout CacheData) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: cache.totalHeight)
    }
    
    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout CacheData) {
        guard subviews.count == 3 else { return }

        let leading = subviews[0]
        let center = subviews[1]
        let trailing = subviews[2]

        // Place leading at start
        leading.place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: .unspecified,
        )

        // Place trailing at end
        trailing.place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: .unspecified,
        )

        // Calculate available width for center view
        let availableWidth = bounds.width - cache.leadingSize.width - cache.trailingSize.width - spacing * 2

        // Ask center view for its size given the available width.
        // This respects minWidth/maxWidth frame modifiers properly.
        let centerSize = center.sizeThatFits(ProposedViewSize(width: availableWidth, height: bounds.height))

        // Ideal: true center of bounds
        let idealX = bounds.midX - centerSize.width / 2

        // Constraints: must not overlap leading/trailing (with spacing)
        let minX = bounds.minX + cache.leadingSize.width + spacing
        let maxX = bounds.maxX - cache.trailingSize.width - centerSize.width - spacing

        // Use ideal center if it fits, otherwise clamp
        let actualX = max(minX, min(idealX, maxX))

        center.place(
            at: CGPoint(x: actualX, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: centerSize.width, height: bounds.height),
        )
    }
}
