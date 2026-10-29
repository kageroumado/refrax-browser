import SwiftUI

/// Responsive grid of shared favorites in the library drawer.
///
/// Favorites are space-independent and always available. They can be:
/// - **Live tabs**: Persistent tabs that activate when clicked
/// - **Shortcuts**: Navigate current tab to URL
/// - **Folders**: Collections of bookmarks
///
/// Uses `AdaptiveFavoritesGridLayout`, a custom `Layout` that sizes its columns from
/// the width it is offered.
struct FavoritesGrid: View {
    var showsTitles = false
    @Environment(BookmarksManager.self) private var bookmarksManager

    var body: some View {
        AdaptiveFavoritesGridLayout(configuration: gridConfiguration) {
            ForEach(bookmarksManager.favorites) { item in
                FavoriteTileView(item: item, shouldShowTitle: showsTitles)
            }
        }
        .accessibilityIdentifier("FavoritesGrid")
    }

    private var gridConfiguration: AdaptiveFavoritesGridLayout.Configuration {
        AdaptiveFavoritesGridLayout.Configuration(
            minTileWidth: Metrics.minTileWidth,
            tileHeight: Metrics.tileHeight + (showsTitles ? 24 : 0),
            maxColumns: Metrics.maxColumns,
            spacing: Metrics.spacing,
        )
    }
}

// MARK: - Metrics

private enum Metrics {
    static let spacing: CGFloat = 8
    static let minTileWidth: CGFloat = Constants.Layout.tabItemHeight * 1.5
    static let tileHeight: CGFloat = Constants.Layout.tabItemHeight * 1.5
    static let maxColumns: Int = 4
}
