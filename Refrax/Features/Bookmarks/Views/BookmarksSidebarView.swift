import SwiftData
import SwiftUI

/// Sidebar for the Bookmarks window showing folder hierarchy.
///
/// Displays a tree of bookmark folders with favorites section.
///
/// ## Visual Layout
///
/// ```
/// ┌─────────────────────────┐
/// │ Bookmarks            📁+│
/// ├─────────────────────────┤
/// │ 📚 All Bookmarks        │
/// ├─────────────────────────┤
/// │ Favorites               │
/// │   ⭐ Favorites      (4) │
/// ├─────────────────────────┤
/// │ Folders                 │
/// │   📁 Programming    (2) │
/// │     📁 Languages    (4) │
/// │       📁 Functional (3) │
/// │     📁 Frameworks   (3) │
/// │   📁 Reference      (3) │
/// └─────────────────────────┘
/// ```
struct BookmarksSidebarView: View {
    @Binding var selectedFolder: BookmarkFolder?
    @Binding var showFavoritesOnly: Bool
    let onCreateFolder: () -> Void

    @Query(
        filter: #Predicate<BookmarkFolder> { $0.parentFolderID == nil },
        sort: \BookmarkFolder.position,
    )
    private var rootFolders: [BookmarkFolder]

    @Query(filter: #Predicate<Bookmark> { $0.isFavorite })
    private var favoriteBookmarks: [Bookmark]

    @State private var isFavoritesDropTarget = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            sidebarList
        }
        .frame(minWidth: 180)
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("Bookmarks")
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            Button(action: onCreateFolder) {
                Image(systemName: "folder.badge.plus")
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("New Folder")
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
    }

    // MARK: - Sidebar List

    private var sidebarList: some View {
        List(selection: $selectedFolder) {
            // All Bookmarks
            Button(action: {
                selectedFolder = nil
                showFavoritesOnly = false
            }) {
                Label("All Bookmarks", systemImage: "book.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(selectedFolder == nil && !showFavoritesOnly ? Color.appAccentColor : .primary)
            .listRowBackground(Color.clear)

            // Favorites Section
            Section("Favorites") {
                favoritesRow
            }

            // Folders Section
            if !rootFolders.isEmpty {
                Section("Folders") {
                    ForEach(rootFolders) { folder in
                        FolderTreeNode(
                            folder: folder,
                            selectedFolder: $selectedFolder,
                            showFavoritesOnly: $showFavoritesOnly,
                            showCreateFolderSheet: .constant(false),
                        )
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    // MARK: - Favorites Row

    private var favoritesRow: some View {
        Button(action: {
            showFavoritesOnly = true
            selectedFolder = nil
        }) {
            HStack(spacing: 8) {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)

                Text("Favorites")

                Spacer()

                Text("\(favoriteBookmarks.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .flash(isFavoritesDropTarget)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(showFavoritesOnly ? Color.appAccentColor : .primary)
        .listRowBackground(isFavoritesDropTarget ? Color.appAccentColor.opacity(0.1) : Color.clear)
        .dropDestination(for: BookmarkDragItem.self) { items, _ in
            handleFavoritesDrop(items: items)
        } isTargeted: { isTarget in
            isFavoritesDropTarget = isTarget
        }
    }

    // MARK: - Drag & Drop

    private func handleFavoritesDrop(items: [BookmarkDragItem]) -> Bool {
        guard let firstItem = items.first else { return false }
        // Note: Actual implementation needs BookmarksManager from environment
        // This is handled by the parent BookmarksView
        return !firstItem.bookmarkIDs.isEmpty
    }
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    @Previewable @State var selectedFolder: BookmarkFolder?
    @Previewable @State var showFavoritesOnly = false

    BookmarksSidebarView(
        selectedFolder: $selectedFolder,
        showFavoritesOnly: $showFavoritesOnly,
        onCreateFolder: {},
    )
    .frame(width: 220, height: 400)
}
