import SwiftUI

/// Custom layout for the address bar with stable URL positioning.
///
/// The layout takes 4 subviews in order:
/// 1. Navigation controls (leading edge)
/// 2. URL display (always centered between nav and reload)
/// 3. Hover buttons (trailing edge, before reload)
/// 4. Reload button (trailing edge)
///
/// **Critical**: The URL position is FIXED at center regardless of hover buttons.
/// This ensures stable layout that doesn't shift when buttons appear/disappear.
///
/// The layout reports whether buttons would overlap with the URL via preference key.
/// The parent view uses this to determine if URL should dim when hovering.
struct AddressBarLayout: Layout {
    struct CacheData {
        var navSize: CGSize = .zero
        var urlSize: CGSize = .zero
        var hoverButtonsSize: CGSize = .zero
        var reloadSize: CGSize = .zero
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
        guard subviews.count == 4 else { return }

        cache.navSize = subviews[0].sizeThatFits(.unspecified)
        cache.urlSize = subviews[1].sizeThatFits(.unspecified)
        cache.hoverButtonsSize = subviews[2].sizeThatFits(.unspecified)
        cache.reloadSize = subviews[3].sizeThatFits(.unspecified)
        cache.totalHeight = max(
            cache.navSize.height,
            cache.urlSize.height,
            cache.hoverButtonsSize.height,
            cache.reloadSize.height,
        )
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews _: Subviews, cache: inout CacheData) -> CGSize {
        CGSize(width: proposal.width ?? 0, height: cache.totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache: inout CacheData) {
        guard subviews.count == 4 else { return }

        let nav = subviews[0]
        let url = subviews[1]
        let hoverButtons = subviews[2]
        let reload = subviews[3]

        // Fixed positions for nav and reload at edges
        nav.place(
            at: CGPoint(x: bounds.minX, y: bounds.midY),
            anchor: .leading,
            proposal: .unspecified,
        )

        reload.place(
            at: CGPoint(x: bounds.maxX, y: bounds.midY),
            anchor: .trailing,
            proposal: .unspecified,
        )

        // Content area is between nav and reload (for width constraints)
        let contentAreaEnd = bounds.maxX - cache.reloadSize.width
        let maxUrlWidth = contentAreaEnd - bounds.minX - cache.navSize.width

        // URL is centered at the TRUE CENTER of bounds - not affected by nav width changes.
        // This ensures the URL doesn't shift when the forward button appears/disappears.
        url.place(
            at: CGPoint(x: bounds.midX, y: bounds.midY),
            anchor: .center,
            proposal: ProposedViewSize(width: min(cache.urlSize.width, maxUrlWidth), height: bounds.height),
        )

        // Hover buttons are ALWAYS at trailing edge of content area (before reload)
        hoverButtons.place(
            at: CGPoint(x: contentAreaEnd, y: bounds.midY),
            anchor: .trailing,
            proposal: .unspecified,
        )
    }
}

// MARK: - Compact Mode Detection

/// Computes whether the address bar is in compact mode (URL and buttons would overlap).
///
/// When in compact mode, the URL should dim when hovering to make room for buttons.
func addressBarIsCompactMode(
    availableWidth: CGFloat,
    navWidth _: CGFloat,
    urlWidth: CGFloat,
    hoverButtonsWidth: CGFloat,
    reloadWidth _: CGFloat,
) -> Bool {
    // URL is centered at availableWidth / 2 (true center of bounds)
    let urlCenterX = availableWidth / 2
    let urlHalfWidth = urlWidth / 2

    // Buttons are positioned at trailing edge
    let buttonsTrailingX = availableWidth
    let buttonsLeadingX = buttonsTrailingX - hoverButtonsWidth

    // URL trailing edge vs buttons leading edge
    let urlTrailingEdge = urlCenterX + urlHalfWidth

    // Compact only if frames actually intersect
    return urlTrailingEdge > buttonsLeadingX
}
