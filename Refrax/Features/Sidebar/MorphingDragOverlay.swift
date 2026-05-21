import SwiftUI

/// Drag overlay that morphs between tab row and tile appearances.
///
/// The overlay transforms when crossing zone boundaries:
/// - **Tab List → Favorites Grid**: Tab row scales down and morphs into tile
/// - **Favorites Grid → Tab List**: Tile scales up and morphs into tab row
///
/// ## Animation
///
/// Morphing uses 150ms easeInOut transition with:
/// - Size interpolation between source and target dimensions
/// - Content crossfade between tab and tile views
/// - Center-anchored positioning during morph
///
/// ## Groups
///
/// Tab groups cannot become favorites, so they always render as tab rows
/// regardless of drop zone.
///
/// ## Multi-Selection
///
/// When multiple items are selected (totalCount > 1), the overlay shows:
/// - Stacked cards with 4px offset per card (max 3 visible)
/// - Count badge in bottom-right corner
/// - Only tab items can be multi-selected (groups filtered out)
struct MorphingDragOverlay: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(WindowState.self) private var windowState
    @Environment(Sidebar.LayoutManager.self) private var layoutManager
    @Environment(Sidebar.TabSelectionManager.self) private var selectionManager
    @Environment(Sidebar.DragCoordinator.self) private var dragCoordinator

    /// The primary item being dragged (first in selection)
    let primaryItem: Sidebar.DragCoordinator.DraggedItem

    /// Total number of items being dragged (1 for single item, > 1 for multi-selection)
    let totalCount: Int

    // MARK: - Computed Sizes

    /// Actual tile size from grid layout.
    /// Falls back to tab row dimensions if no favorites exist (first favorite will match tab width).
    private var actualTileSize: CGSize {
        if let gridLayout = dragCoordinator._favoritesGridLayout {
            return gridLayout.tileSize
        }
        // No favorites grid available - use tab width with fixed tile height (1.5x tab height)
        let tileHeight = Constants.Layout.tabItemHeight * 1.5
        return CGSize(width: dragCoordinator.tabRowWidth, height: tileHeight)
    }

    /// Current overlay mode with actual sizes injected.
    private var effectiveOverlayMode: Sidebar.DragCoordinator.OverlayMode {
        switch dragCoordinator.currentOverlayMode {
        case .tabRow:
            .tabRow
        case .tile:
            // Use actual grid tile size instead of the cached one
            .tile(actualTileSize)
        }
    }

    /// Tab row width accounting for current nesting level.
    ///
    /// Nesting level is dynamically updated by `DragCoordinator.updateDraggedItemNestingLevel`
    /// based on overlay position during drag. Each nesting level adds 20px leading padding,
    /// which reduces the available tab row width.
    private var effectiveTabRowWidth: CGFloat {
        let baseWidth = dragCoordinator.tabRowWidth
        let nestingLevel = layoutManager.metadata[primaryItem.id]?.nestingLevel ?? 0
        return baseWidth - CGFloat(nestingLevel) * Constants.Layout.nestingLevelPadding
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 4) {
            overlayContent
                .geometryGroup() // Isolate from parent position updates

            if dragCoordinator.showDataStorageWarning {
                dataStorageWarningBadge
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
            }
        }
        .animation(.easeInOut(duration: 0.15), value: dragCoordinator.showDataStorageWarning)
        .position(dragCoordinator.overlayPositionInSidebar)
        .allowsHitTesting(false)
    }

    // MARK: - Content

    @ViewBuilder
    private var overlayContent: some View {
        if totalCount > 1 {
            // Multi-selection: show stacked cards
            multiSelectionOverlay
        } else {
            // Single item: show morphing overlay
            singleItemOverlay
        }
    }

    @ViewBuilder
    private var singleItemOverlay: some View {
        switch primaryItem {
        case let .favorite(favorite):
            favoriteOverlay(favorite)

        case let .tab(tab):
            tabOverlay(tab)

        case let .group(group):
            // Groups can't become favorites, always show as tab row
            groupOverlay(group)
        }
    }

    // MARK: - Multi-Selection Overlay

    /// Stacked morphable cards for multi-selection drag.
    ///
    /// Each card uses `MorphableOverlayContent` to smoothly animate between
    /// tab row and tile appearances, matching the single-item behavior.
    private var multiSelectionOverlay: some View {
        // Get all tabs: main item + followers (groups are filtered out for multi-selection)
        let mainTabs = dragCoordinator.draggedItems.compactMap(\.tab)
        let followerTabs = dragCoordinator.followerItems.compactMap(\.tab)
        let tabs = mainTabs + followerTabs
        let visibleCount = min(tabs.count, Metrics.maxStackedCards)

        return ZStack {
            // Render cards from back to front (reversed so first is on top)
            ForEach(Array(tabs.prefix(visibleCount).enumerated().reversed()), id: \.element.id) { index, tab in
                let page = tab.activePage
                let isActive = tab.id == windowState.activeTabID
                let isMultiSelected = selectionManager.isSelected(tab)
                MorphableOverlayContent(
                    mode: effectiveOverlayMode,
                    faviconData: page.faviconData,
                    largeFaviconData: page.largeFaviconData,
                    url: page.url,
                    title: tab.displayTitle,
                    tabRowWidth: effectiveTabRowWidth,
                    faviconCache: tabManager.state.faviconCache,
                    isActive: isActive,
                    isMultiSelected: isMultiSelected,
                )
                .offset(
                    x: CGFloat(index) * Metrics.stackOffsetX,
                    y: -CGFloat(index) * Metrics.stackOffsetY,
                )
            }

            // Count badge
            if tabs.count > 1 {
                countBadge(count: tabs.count)
            }
        }
    }

    /// Count badge showing total number of dragged items.
    private func countBadge(count: Int) -> some View {
        Text("\(count)")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.blue, in: Capsule())
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .offset(x: 4, y: 4)
    }

    // MARK: - Favorite Overlay

    /// Overlay for dragged favorite items.
    ///
    /// Uses `MorphableOverlayContent` to smoothly animate between tile (native)
    /// and tab row appearances when crossing zone boundaries.
    private func favoriteOverlay(_ favorite: FavoriteItem) -> some View {
        let isLiveFavorite = if case .liveFavorite = favorite.type { true } else { false }

        return MorphableOverlayContent(
            mode: effectiveOverlayMode,
            faviconData: favorite.faviconData,
            largeFaviconData: favorite.largeFaviconData,
            url: favorite.url,
            title: favorite.displayName,
            tabRowWidth: effectiveTabRowWidth,
            faviconCache: tabManager.state.faviconCache,
            // Use captured active state to preserve title font weight during return animation
            isActive: dragCoordinator._draggedItemWasActive,
            isLiveFavorite: isLiveFavorite,
            // SF Symbol for app shortcuts and folders
            sfSymbol: favorite.sfSymbol,
            symbolColor: favorite.color,
        )
    }

    // MARK: - Tab Overlay

    /// Overlay for dragged tab items.
    ///
    /// Uses `MorphableOverlayContent` to smoothly animate between tab row (native)
    /// and tile appearances when crossing zone boundaries.
    private func tabOverlay(_ tab: Tab) -> some View {
        let page = tab.activePage
        let isMultiSelected = selectionManager.isSelected(tab)

        return MorphableOverlayContent(
            mode: effectiveOverlayMode,
            faviconData: page.faviconData,
            largeFaviconData: page.largeFaviconData,
            url: page.url,
            title: tab.displayTitle,
            tabRowWidth: effectiveTabRowWidth,
            faviconCache: tabManager.state.faviconCache,
            // Use captured active state to preserve title font weight during return animation
            isActive: dragCoordinator._draggedItemWasActive,
            isMultiSelected: isMultiSelected,
        )
    }

    // MARK: - Group Overlay

    /// Overlay for dragged group items.
    ///
    /// Groups always render as tab rows since they can't become favorites.
    private func groupOverlay(_ group: TabGroup) -> some View {
        TabGroupHeaderView(
            group: group,
            isActive: false,
            isDragging: true,
        )
        .frame(height: Constants.Layout.tabItemHeight)
        .padding(.horizontal, Constants.Layout.tabHorizontalPadding)
        .padding(.leading, CGFloat(layoutManager.nestingLevel(for: group.id)) * Constants.Layout.nestingLevelPadding)
    }

    // MARK: - Warning Badge

    private var dataStorageWarningBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text("Tab will reload (different data storage)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.regularMaterial, in: Capsule())
    }
}

// MARK: - Metrics

private enum Metrics {
    /// Duration of the morph transition in seconds
    static let morphDuration: Double = 0.25

    /// Maximum number of stacked cards to show for multi-selection
    static let maxStackedCards: Int = 3

    /// Horizontal offset per stacked card (in pixels)
    static let stackOffsetX: CGFloat = 4

    /// Vertical offset per stacked card (in pixels, negative = up)
    static let stackOffsetY: CGFloat = 4

    /// Icon size for tile appearance (matches FavoriteTileView)
    static let tileIconSize: CGFloat = 32

    /// Icon size for tab row appearance
    static let tabIconSize: CGFloat = Constants.Layout.tabFaviconSize

    /// Corner radius for tile appearance
    static let tileCornerRadius: CGFloat = 16

    /// Corner radius for tab row appearance
    static let tabCornerRadius: CGFloat = Constants.Layout.tabCornerRadius
}

// MARK: - Morphable Overlay Content

/// Unified overlay that morphs between tab row and tile appearances.
///
/// Uses explicit @State for animated values with withAnimation to ensure smooth transitions.
/// All animatable properties are stored as state and updated via onChange.
private struct MorphableOverlayContent: View {
    let mode: Sidebar.DragCoordinator.OverlayMode
    let faviconData: Data?
    let largeFaviconData: Data?
    let url: URL?
    let title: String
    let tabRowWidth: CGFloat
    let faviconCache: FaviconCache?
    let isActive: Bool
    var isMultiSelected: Bool = false
    var isLiveFavorite: Bool = false

    /// SF Symbol name for app shortcuts (renders instead of favicon when set).
    var sfSymbol: String?

    /// Background color for SF Symbol icon (hex string).
    var symbolColor: String?

    /// Large favicon loaded from cache when model doesn't have it.
    @State private var cachedLargeFavicon: Data?

    // Animated state values - updated via onChange with withAnimation.
    // Initialized to tab row defaults since most drags start as tabs.
    // onAppear sets correct values before view becomes visible.
    @State private var animatedWidth: CGFloat = 300
    @State private var animatedHeight: CGFloat = Constants.Layout.tabItemHeight
    @State private var animatedCornerRadius: CGFloat = Metrics.tabCornerRadius
    @State private var animatedFaviconSize: CGFloat = Metrics.tabIconSize
    @State private var animatedFaviconOffsetX: CGFloat = 0
    @State private var animatedTitleOpacity: CGFloat = 1
    @State private var animatedTitleOffsetX: CGFloat = 0
    @State private var animatedBackgroundStyle: AdaptiveBackgroundStyle = .subtle
    @State private var animatedIsTile: Bool = false
    @State private var isInitialized: Bool = false

    // MARK: - Computed Properties

    private var isTile: Bool {
        if case .tile = mode { true } else { false }
    }

    /// Best available favicon data for current mode.
    private var effectiveFaviconData: Data? {
        if animatedIsTile {
            return largeFaviconData ?? cachedLargeFavicon ?? faviconData
        }
        return faviconData
    }

    // MARK: - Target Layout Values

    private var targetSize: CGSize {
        switch mode {
        case .tabRow:
            CGSize(width: tabRowWidth, height: Constants.Layout.tabItemHeight)
        case let .tile(size):
            size
        }
    }

    private var targetFaviconSize: CGFloat {
        isTile ? Metrics.tileIconSize : Metrics.tabIconSize
    }

    private var targetCornerRadius: CGFloat {
        isTile ? Metrics.tileCornerRadius : Metrics.tabCornerRadius
    }

    /// Favicon offset from center in tab row mode.
    /// TabView layout: HStack content has .padding(.horizontal, small2) inside background.
    private var targetFaviconOffsetX: CGFloat {
        if isTile { return 0 }
        // Favicon is at left edge of content area (which has small2 padding from background)
        // Favicon center: small2 + faviconSize/2 from left of background
        let faviconCenterFromLeft = Constants.Spacing.small2 + Metrics.tabIconSize / 2
        return faviconCenterFromLeft - tabRowWidth / 2
    }

    private var targetTitleOpacity: CGFloat {
        isTile ? 0 : 1
    }

    /// Title left position from background left edge.
    /// Layout: small2 (content padding) + faviconSize + small (spacing to title)
    private var titleLeftFromBackgroundLeft: CGFloat {
        Constants.Spacing.small2 + Constants.Layout.tabFaviconSize + Constants.Spacing.small
    }

    /// Title width in tab row mode.
    private var titleWidth: CGFloat {
        // Title extends from after favicon+spacing to right content padding
        tabRowWidth - titleLeftFromBackgroundLeft - Constants.Spacing.small2
    }

    /// Title offset from center to position it after the favicon
    private var targetTitleOffsetX: CGFloat {
        // In tile mode, title starts near favicon (will slide out when transitioning to tab)
        if isTile { return targetFaviconOffsetX + Metrics.tabIconSize / 2 }
        // Tab mode: title center position relative to background center
        let titleCenterFromLeft = titleLeftFromBackgroundLeft + titleWidth / 2
        return titleCenterFromLeft - tabRowWidth / 2
    }

    /// Background style matching TabView/FavoriteTileView conventions.
    ///
    /// TabView uses hover-style (.subtle) during drag since isDragging triggers effectiveHoverState.
    /// FavoriteTileView hover state uses .muted.
    private var backgroundStyle: AdaptiveBackgroundStyle {
        if isTile {
            // Tile mode: match FavoriteTileView hover state
            // Previously active tabs keep emphasized appearance during conversion.
            if isActive { return .emphasized }
            // Non-active: use .muted to match FavoriteTileView's hover state
            return .muted
        } else {
            // Tab mode: match TabView with isDragging=true (hover state)
            if isActive, isMultiSelected { return .emphasizedSecondary }
            if isActive { return .emphasized }
            if isMultiSelected { return .secondary }
            return .subtle // Hover state during drag
        }
    }

    /// Title font weight - bold for active tabs (matching TabView behavior).
    private var titleFontWeight: Font.Weight {
        isActive ? .semibold : .regular
    }

    // MARK: - Body

    var body: some View {
        // Fixed-size container at max dimensions - only inner content animates
        ZStack {
            // Icon: SF Symbol for app shortcuts, or favicon for web content
            iconView
                .frame(width: animatedFaviconSize, height: animatedFaviconSize)
                .offset(x: animatedFaviconOffsetX)

            // Title slides out from favicon area
            Text(title)
                .font(.system(size: Constants.Typography.bodySize, weight: titleFontWeight))
                .foregroundColor(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: titleWidth, alignment: .leading)
                .offset(x: animatedTitleOffsetX)
                .opacity(animatedTitleOpacity)
        }
        .frame(width: animatedWidth, height: animatedHeight)
        // Background with proper styling (enable blur to match FavoriteTileView appearance)
        .adaptiveBackground(animatedBackgroundStyle, in: RoundedRectangle(cornerRadius: animatedCornerRadius))
        .adaptiveBackgroundBlur(isTile)
        // FIXED container size - use max of both states so layout doesn't shift
        .frame(width: containerSize.width, height: containerSize.height)
        // Don't render until initialized to prevent flash of wrong values
        .opacity(isInitialized ? 1 : 0)
        .task { await preloadLargeFaviconIfNeeded() }
        // Use onChange with initial:true to handle both first appearance and changes.
        // This avoids race conditions between onAppear and onChange handlers.
        .onChange(of: mode, initial: true) { _, _ in
            // Only animate after first initialization
            updateAnimatedValues(animated: isInitialized)
        }
        .onChange(of: tabRowWidth) { _, _ in
            if isInitialized {
                updateAnimatedValues(animated: true)
            }
        }
    }

    // MARK: - Icon View

    /// Renders either an SF Symbol (for app shortcuts) or a favicon (for web content).
    @ViewBuilder
    private var iconView: some View {
        if let symbol = sfSymbol {
            // App shortcut or folder: render SF Symbol with colored background
            SymbolIconView(
                symbolName: symbol,
                size: animatedFaviconSize,
                fontSize: animatedFaviconSize * 0.5,
                backgroundColor: Color.resolveStoredColor(symbolColor ?? "#808080"),
            )
        } else {
            // Web content: render favicon
            FaviconView(data: effectiveFaviconData, url: url, size: animatedFaviconSize)
        }
    }

    /// Fixed container size that fits both tile and tab row states
    private var containerSize: CGSize {
        let tileSize: CGSize = {
            if case let .tile(size) = mode { return size }
            // Default tile size if we're in tab mode
            return CGSize(width: 80, height: Constants.Layout.tabItemHeight * 1.5)
        }()
        let tabSize = CGSize(width: tabRowWidth, height: Constants.Layout.tabItemHeight)
        return CGSize(
            width: max(tileSize.width, tabSize.width),
            height: max(tileSize.height, tabSize.height),
        )
    }

    // MARK: - Animation

    private func updateAnimatedValues(animated: Bool) {
        let update = {
            animatedWidth = targetSize.width
            animatedHeight = targetSize.height
            animatedCornerRadius = targetCornerRadius
            animatedFaviconSize = targetFaviconSize
            animatedFaviconOffsetX = targetFaviconOffsetX
            animatedTitleOpacity = targetTitleOpacity
            animatedTitleOffsetX = targetTitleOffsetX
            animatedBackgroundStyle = backgroundStyle
            animatedIsTile = isTile
            isInitialized = true
        }

        if animated {
            withAnimation(.easeOut(duration: Metrics.morphDuration)) {
                update()
            }
        } else {
            update()
        }
    }

    // MARK: - Cache Loading

    private func preloadLargeFaviconIfNeeded() async {
        guard largeFaviconData == nil, cachedLargeFavicon == nil else { return }
        guard let host = url?.host, let cache = faviconCache else { return }
        cachedLargeFavicon = await cache.cachedFaviconData(forHost: host, size: .large)
    }
}

// MARK: - Symbol Icon View

/// Renders an SF Symbol with a colored squircle background.
/// Used for app shortcuts and folders in the drag overlay.
private struct SymbolIconView: View {
    let symbolName: String
    let size: CGFloat
    let fontSize: CGFloat
    let backgroundColor: Color

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: fontSize, weight: .semibold))
            .foregroundStyle(.white)
            .offset(x: 0.5)
            .frame(width: size, height: size)
            .background {
                SquircleShape()
                    .fill(backgroundColor)
            }
    }
}
