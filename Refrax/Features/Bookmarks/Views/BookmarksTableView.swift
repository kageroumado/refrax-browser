import SwiftUI

/// Table view for displaying bookmarks in list mode.
///
/// Features:
/// - 8-column layout: offline status, favorite indicator, favicon, title, URL, tags, visits, date added
/// - Multi-selection support via `selectedBookmarkIDs` binding
/// - Drag support for bookmark reordering and external drops
/// - Context menus for single and multiple selection
struct BookmarksTableView: View {
    let bookmarks: [Bookmark]
    @Binding var selectedBookmarkIDs: Set<Bookmark.ID>
    let loadingFavicons: Set<UUID>
    let onCreateBookmark: () -> Void
    let singleBookmarkMenu: (Bookmark) -> AnyView
    let multipleBookmarksMenu: (Set<Bookmark.ID>) -> AnyView
    let createDragItem: (Set<Bookmark.ID>) -> BookmarkDragItem

    var body: some View {
        Table(bookmarks, selection: $selectedBookmarkIDs) {
            // Offline column (first)
            TableColumn("") { bookmark in
                if bookmark.isOfflineAvailable {
                    Image(systemName: "arrow.down.circle.fill")
                        .foregroundStyle(.green)
                        .help("Available Offline")
                } else if bookmark.isDownloadingOffline {
                    ProgressView()
                        .scaleEffect(0.5)
                }
            }
            .width(20)

            // Favorite column
            TableColumn("") { bookmark in
                if bookmark.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.secondary)
                }
            }
            .width(20)

            // Favicon column
            TableColumn("") { bookmark in
                faviconView(for: bookmark, size: 16)
            }
            .width(20)

            // Title column
            TableColumn("Title") { bookmark in
                Text(bookmark.title)
            }
            .width(min: 150, ideal: 250)

            // URL column
            TableColumn("URL") { bookmark in
                Text(bookmark.url.absoluteString)
                    .foregroundStyle(.secondary)
            }
            .width(min: 150, ideal: 300)

            // Tags column
            TableColumn("Tags") { bookmark in
                if !bookmark.tags.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(bookmark.tags.prefix(3), id: \.self) { tag in
                            Text(tag)
                                .font(.caption2)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(Color.appAccentColor.opacity(0.15))
                                .foregroundStyle(Color.appAccentColor)
                                .clipShape(Capsule())
                        }
                    }
                }
            }
            .width(min: 100, ideal: 150)

            // Visits column
            TableColumn("Visits") { bookmark in
                if bookmark.visitCount > 0 {
                    Text("\(bookmark.visitCount)")
                        .foregroundStyle(.secondary)
                }
            }
            .width(60)

            // Date column
            TableColumn("Added") { bookmark in
                Text(bookmark.createdAt, format: .dateTime.month().day())
                    .foregroundStyle(.secondary)
            }
            .width(80)
        }
        .draggable(createDragItem(selectedBookmarkIDs))
        .contextMenu(forSelectionType: Bookmark.ID.self) { ids in
            if ids.isEmpty {
                // Context menu when clicking empty space
                Button("New Bookmark") {
                    onCreateBookmark()
                }
            } else if ids.count == 1, let bookmark = bookmarks.first(where: { $0.id == ids.first }) {
                // Single selection context menu
                singleBookmarkMenu(bookmark)
            } else {
                // Multiple selection context menu
                multipleBookmarksMenu(ids)
            }
        }
    }

    // MARK: - Favicon View Helper

    @ViewBuilder
    private func faviconView(for bookmark: Bookmark, size: CGFloat) -> some View {
        if loadingFavicons.contains(bookmark.id) {
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: size, height: size)
        } else if let customIcon = bookmark.customIcon {
            customIcon.view(size: size)
        } else {
            FaviconView(data: bookmark.faviconData, url: bookmark.url, size: size)
        }
    }
}
