import SwiftUI

/// The shared favorites collection in the browser's library drawer.
struct FavoritesTrayView: View {
    @Environment(WindowState.self) private var windowState
    @Environment(BookmarksManager.self) private var bookmarks
    @Environment(TabManager.self) private var tabs

    var body: some View {
        Group {
            if bookmarks.favorites.isEmpty {
                DetailTrayEmptyState(icon: "star", title: "Your Favorites", message: "Favorite a tab to keep it within reach in every space.")
            } else {
                ScrollView {
                    FavoritesGrid(showsTitles: true)
                        .padding(12)
                }
            }
        }
        .safeAreaBar(edge: .top) {
            DetailTrayHeader(title: "Favorites", currentMode: .favorites, onClose: { windowState.hideDetailTray() })
        }
        .safeAreaBar(edge: .bottom) {
            HStack {
                if let tab = windowState.activeTab, !tab.isFavorite {
                    Button("Favorite Current Tab", systemImage: "star.badge.plus") {
                        _ = tabs.makeFavorite(tab, in: windowState)
                    }
                }
                Spacer()
                Button("Bookmarks", systemImage: "bookmark") { windowState.showDetailTray(.bookmarks) }
            }
            .buttonStyle(.bordered)
            .padding(12)
        }
        .accessibilityIdentifier("FavoritesDrawer")
    }
}
