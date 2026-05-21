import SwiftData
import SwiftUI

// MARK: - Bookmarks Tray View

/// Bookmarks panel for the detail tray.
///
/// Displays bookmarks with folder navigation in Apple Maps-style design:
/// - Large "Bookmarks" title with close button
/// - Folder breadcrumb navigation using NavigationStack
/// - List of bookmarks and subfolders
/// - Bottom toolbar with Add bookmark action
struct BookmarksTrayView: View {
    @Environment(WindowState.self) private var windowState
    @Environment(BookmarksManager.self) private var bookmarksManager
    @Environment(TabManager.self) private var tabManager
    @Environment(OfflineContentManager.self) private var offlineContentManager
    @Environment(\.modelContext) private var modelContext

    /// Navigation path storing folder IDs for stack-based navigation.
    @State private var folderPath: [UUID] = []
    @State private var isSelectionMode = false
    @State private var selectedBookmarks: Set<UUID> = []
    @State private var searchText = ""

    @Query(sort: \BookmarkFolder.name) private var allFolders: [BookmarkFolder]

    private enum Constants {
        static let iconSize: CGFloat = 28
        static let folderIconSize: CGFloat = 14
        static let rowVerticalPadding: CGFloat = 10
    }

    /// The current folder based on the navigation path.
    private var currentFolder: BookmarkFolder? {
        guard let lastID = folderPath.last else { return nil }
        return allFolders.first { $0.id == lastID }
    }

    var body: some View {
        NavigationStack(path: $folderPath) {
            folderContent(for: nil)
                .navigationDestination(for: UUID.self) { folderID in
                    folderContent(for: allFolders.first { $0.id == folderID })
                }
        }
        .safeAreaBar(edge: .top) { header }
        .safeAreaBar(edge: .bottom) { footer }
    }

    // MARK: - Folder Content

    @ViewBuilder
    private func folderContent(for folder: BookmarkFolder?) -> some View {
        let folderBookmarks = bookmarksManager.bookmarks(in: folder)
        let folderSubfolders = subfoldersFor(folder)

        Group {
            if isSearching {
                searchResults
            } else if folderBookmarks.isEmpty, folderSubfolders.isEmpty {
                emptyState(for: folder)
            } else {
                bookmarksList(bookmarks: folderBookmarks, subfolders: folderSubfolders)
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(spacing: 0) {
            DetailTrayHeader(
                title: isSelectionMode ? "Select Bookmarks" : headerTitle,
                currentMode: .bookmarks,
                onBack: canNavigateBack ? { navigateBack() } : nil,
                onExpand: isSelectionMode ? nil : { openFullBookmarksView() },
                onClose: {
                    if isSelectionMode {
                        isSelectionMode = false
                        selectedBookmarks.removeAll()
                    } else {
                        windowState.hideDetailTray()
                    }
                },
            )

            // Search field (stays visible during selection mode to preserve item positions)
            DetailTraySearchField(text: $searchText, placeholder: "Search Bookmarks")
        }
    }

    private var headerTitle: String {
        currentFolder?.name ?? "Bookmarks"
    }

    private var canNavigateBack: Bool {
        !folderPath.isEmpty && !isSelectionMode
    }

    // MARK: - Empty State

    private func emptyState(for folder: BookmarkFolder?) -> some View {
        DetailTrayEmptyState(
            icon: "bookmark",
            title: folder == nil ? "No Bookmarks" : "Empty Folder",
            message: folder == nil
                ? "Pages you bookmark will appear here"
                : "This folder has no bookmarks yet",
        )
    }

    // MARK: - Bookmarks List

    private func bookmarksList(bookmarks: [Bookmark], subfolders: [BookmarkFolder]) -> some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                // Subfolders
                if !subfolders.isEmpty {
                    ForEach(subfolders) { folder in
                        folderRow(folder)
                    }

                    if !bookmarks.isEmpty {
                        Divider()
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }

                // Bookmarks
                ForEach(bookmarks) { bookmark in
                    bookmarkRow(bookmark)
                }
            }
            .padding(.bottom, 8)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    // MARK: - Search Results

    private var searchResults: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(searchResultBookmarks) { bookmark in
                    bookmarkRow(bookmark)
                }
            }
            .padding(.bottom, 8)
        }
        .scrollEdgeEffectStyle(.soft, for: .all)
    }

    // MARK: - Folder Row

    private func folderRow(_ folder: BookmarkFolder) -> some View {
        let folderColor = folder.swiftUIColor

        return NavigationLink(value: folder.id) {
            HStack(spacing: 12) {
                ZStack {
                    SquircleShape()
                        .fill(folderColor.opacity(0.15))
                        .frame(width: Constants.iconSize, height: Constants.iconSize)

                    Image(systemName: "folder.fill")
                        .font(.system(size: Constants.folderIconSize))
                        .foregroundStyle(folderColor)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(folder.name)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)

                    Text("\(bookmarksInFolder(folder).count) items")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, Constants.rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Bookmark Row

    private func bookmarkRow(_ bookmark: Bookmark) -> some View {
        Button {
            if isSelectionMode {
                toggleSelection(bookmark.id)
            } else {
                openBookmark(bookmark)
            }
        } label: {
            HStack(spacing: 12) {
                if isSelectionMode {
                    selectionIndicator(isSelected: selectedBookmarks.contains(bookmark.id))
                }

                faviconView(for: bookmark)

                VStack(alignment: .leading, spacing: 2) {
                    Text(bookmark.title)
                        .font(.system(size: 14, weight: .medium))
                        .lineLimit(1)

                    Text(bookmark.url.host ?? bookmark.url.absoluteString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if !isSelectionMode {
                    HStack(spacing: 6) {
                        if bookmark.isOfflineAvailable {
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.green)
                                .help("Available Offline")
                        } else if bookmark.isDownloadingOffline {
                            ProgressView()
                                .scaleEffect(0.5)
                                .frame(width: 12, height: 12)
                        }

                        if bookmark.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 12))
                                .foregroundStyle(.yellow)
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, Constants.rowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            bookmarkContextMenu(bookmark)
        }
    }

    // MARK: - Selection Indicator

    private func selectionIndicator(isSelected: Bool) -> some View {
        ZStack {
            if isSelected {
                Circle()
                    .fill(.blue)
                    .frame(width: 22, height: 22)

                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Circle()
                    .stroke(.secondary.opacity(0.3), lineWidth: 1.5)
                    .frame(width: 22, height: 22)
            }
        }
    }

    // MARK: - Favicon View

    private func faviconView(for bookmark: Bookmark) -> some View {
        FaviconView(data: bookmark.faviconData, url: bookmark.url, size: Constants.iconSize)
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func bookmarkContextMenu(_ bookmark: Bookmark) -> some View {
        Button("Open") {
            openBookmark(bookmark)
        }

        Button("Open in New Tab") {
            tabManager.createTab(url: bookmark.url, makeActive: false)
        }

        Divider()

        Button(bookmark.isFavorite ? "Remove from Favorites" : "Add to Favorites") {
            if bookmark.isFavorite {
                bookmarksManager.removeFromFavorites(bookmark)
            } else {
                bookmarksManager.addToFavorites(bookmark)
            }
        }

        Divider()

        offlineMenuSection(for: bookmark)

        Divider()

        Button("Delete", role: .destructive) {
            bookmarksManager.deleteBookmark(bookmark)
        }
    }

    @ViewBuilder
    private func offlineMenuSection(for bookmark: Bookmark) -> some View {
        switch bookmark.offlineStatus {
        case .notSaved, .failed:
            Button("Save Offline") {
                offlineContentManager.saveBookmarkOffline(
                    bookmark,
                    activePageID: windowState.activePageID,
                    tabManager: tabManager,
                )
            }
        case .downloadingHTML, .downloadingReader:
            Button("Saving...") {}
                .disabled(true)
        case .availableHTML, .availableReader:
            if let savedAt = bookmark.offlineSavedAt {
                Text("Saved \(savedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let fileSize = bookmark.offlineFileSize {
                Text(ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button("Remove Offline Copy") {
                offlineContentManager.deleteOfflineContent(for: bookmark)
            }
        }
    }

    // MARK: - Footer

    @ViewBuilder
    private var footer: some View {
        if isSelectionMode {
            DetailTraySelectionFooter(
                deleteAction: deleteSelectedBookmarks,
                doneAction: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isSelectionMode = false
                    }
                    selectedBookmarks.removeAll()
                },
                hasSelection: !selectedBookmarks.isEmpty,
            )
            .transition(.opacity)
        } else {
            DetailTrayFooter {
                DetailTrayToolbar {
                    DetailTrayToolbarButton(
                        icon: "plus",
                        action: bookmarkCurrentPage,
                        help: "Bookmark Current Page",
                    )

                    DetailTrayToolbarButton(
                        icon: "circle.grid.2x2.topleft.checkmark.filled",
                        action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isSelectionMode = true
                            }
                        },
                        isDisabled: currentFolderBookmarks.isEmpty && currentFolderSubfolders.isEmpty,
                        help: "Select Bookmarks",
                    )
                }
            }
            .transition(.opacity)
        }
    }

    // MARK: - Computed Properties

    private var isSearching: Bool {
        !searchText.isEmpty
    }

    /// Bookmarks in the current folder (for footer disable state).
    private var currentFolderBookmarks: [Bookmark] {
        bookmarksManager.bookmarks(in: currentFolder)
    }

    /// Subfolders of the current folder (for footer disable state).
    private var currentFolderSubfolders: [BookmarkFolder] {
        subfoldersFor(currentFolder)
    }

    private func subfoldersFor(_ folder: BookmarkFolder?) -> [BookmarkFolder] {
        let parentID = folder?.id
        return allFolders.filter { $0.parentFolderID == parentID }
    }

    private var searchResultBookmarks: [Bookmark] {
        bookmarksManager.search(query: searchText, limit: 50)
    }

    private func bookmarksInFolder(_ folder: BookmarkFolder) -> [Bookmark] {
        bookmarksManager.bookmarks(in: folder)
    }

    // MARK: - Navigation

    private func navigateBack() {
        guard !folderPath.isEmpty else { return }
        folderPath.removeLast()
    }

    // MARK: - Actions

    private func openFullBookmarksView() {
        NSApp.typedDelegate.bookmarksWindowController.showWindow()
        windowState.hideDetailTray()
    }

    private func openBookmark(_ bookmark: Bookmark) {
        if let pageID = windowState.activePageID,
           let page = tabManager.state.webPage(for: pageID) {
            page.load(bookmark.url)
        } else {
            tabManager.createTab(url: bookmark.url, makeActive: true)
        }
        windowState.hideDetailTray()
    }

    private func toggleSelection(_ id: UUID) {
        if selectedBookmarks.contains(id) {
            selectedBookmarks.remove(id)
        } else {
            selectedBookmarks.insert(id)
        }
    }

    private func deleteSelectedBookmarks() {
        for id in selectedBookmarks {
            if let bookmark = currentFolderBookmarks.first(where: { $0.id == id }) {
                bookmarksManager.deleteBookmark(bookmark)
            }
        }
        selectedBookmarks.removeAll()
        isSelectionMode = false
    }

    private func bookmarkCurrentPage() {
        guard let pageID = windowState.activePageID,
              let page = tabManager.state.webPage(for: pageID),
              let url = page.url else { return }

        let title = page.title
        bookmarksManager.createBookmark(url: url, title: title, folder: currentFolder)
    }
}
