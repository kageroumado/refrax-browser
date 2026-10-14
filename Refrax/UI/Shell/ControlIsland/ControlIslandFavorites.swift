import SwiftUI

struct ControlIslandFavorites: View {
    @Binding var isPresented: Bool
    @Environment(BookmarksManager.self) private var bookmarksManager
    @Environment(WindowState.self) private var windowState

    var body: some View {
        VStack(spacing: 16) {
            if bookmarksManager.favorites.isEmpty {
                Image(systemName: "star")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("Your favorites, within reach")
                    .font(.headline)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Hold Control and choose Favorite to keep the current tab here. Favorites are available in every space.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView {
                    FavoritesGrid()
                }
                .frame(maxHeight: 320)
            }
            Button("Choose favorites…", systemImage: "bookmark") {
                isPresented = false
                windowState.showDetailTray(.bookmarks)
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(width: 300)
    }
}
