import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Full-page bookmarks manager with folder sidebar, grid/list views, and inspector.
///
/// Follows SF Symbols app design: full-height NavigationSplitView, toolbar, inspector panel.
///
/// ## Visual Layout
///
/// ```
/// ┌──────────────┬────────────────────────────────┬──────────────────┐
/// │   Sidebar    │         Content Area           │    Inspector     │
/// │              │                                │                  │
/// │ All Bookmarks│ ┌──[Grid][List]──[Search]──┐   │ Bookmark Details │
/// │              │ │                            │  │                  │
/// │ ⭐ Favorites │ │  Grid/Table content        │  │ URL: ...         │
/// │              │ │                            │  │ Created: ...     │
/// │ 📁 Programming│ │                            │  │ Visits: ...      │
/// │   📁 Languages│ └────────────────────────────┘  │ Tags: ...        │
/// └──────────────┴────────────────────────────────┴──────────────────┘
/// ```
///
/// ## Features
///
/// - **Sidebar**: Folder tree with drag-drop support
/// - **View Modes**: Grid and List toggle
/// - **Search**: Full-text search via .searchable
/// - **Inspector**: Detailed bookmark information, persisted visibility
/// - **Multi-selection**: Select and batch-operate on bookmarks
struct BookmarksView: View {
    @Environment(BookmarksManager.self) private var bookmarksManager
    @Environment(TabManager.self) private var tabManager
    @Environment(WindowState.self) private var windowState
    @Environment(OfflineContentManager.self) private var offlineContentManager
    @Environment(\.modelContext) private var modelContext

    // MARK: - Data

    @Query(
        filter: #Predicate<BookmarkFolder> { $0.parentFolderID == nil },
        sort: \BookmarkFolder.position,
    )
    private var rootFolders: [BookmarkFolder]

    @Query(sort: \Bookmark.createdAt, order: .reverse)
    private var allBookmarks: [Bookmark]

    @Query(
        filter: #Predicate<Bookmark> { $0.isFavorite },
        sort: \Bookmark.favoritePositionValue,
    )
    private var favoriteBookmarks: [Bookmark]

    // MARK: - State

    @State private var searchText = ""
    @State private var selectedFolder: BookmarkFolder?
    @State private var showFavoritesOnly = false
    @State private var viewMode: ViewMode = .grid
    @State private var sortOrder: SortOrder = .dateAdded
    @State private var sortAscending = false
    @State private var selectedBookmark: Bookmark?
    @State private var selectionManager = BookmarkSelectionManager()
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    @State private var showCreateBookmarkSheet = false
    @State private var showCreateFolderSheet = false
    @State private var bookmarkToEdit: Bookmark?
    @State private var showImportSheet = false

    @State private var errorMessage: String?
    @State private var showError = false

    @AppStorage("bookmarksInspectorVisible") private var showInspector = true

    enum ViewMode {
        case grid
        case list
    }

    enum SortOrder {
        case dateAdded
        case title
        case visitCount
    }

    // MARK: - Body

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            BookmarksSidebarView(
                selectedFolder: $selectedFolder,
                showFavoritesOnly: $showFavoritesOnly,
                onCreateFolder: { showCreateFolderSheet = true },
            )
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 250)
        } detail: {
            contentArea
        }
        .inspector(isPresented: $showInspector) {
            inspectorContent
                .inspectorColumnWidth(min: 250, ideal: 280, max: 350)
        }
        .searchable(text: $searchText, placement: .toolbar, prompt: "Search bookmarks")
        .toolbar { toolbarContent }
        .sheet(isPresented: $showCreateBookmarkSheet) {
            bookmarksManager.loadFaviconsForMissing(in: allBookmarks)
        } content: {
            CreateBookmarkSheet(selectedFolder: selectedFolder)
        }
        .sheet(isPresented: $showCreateFolderSheet) {
            CreateFolderSheet(parentFolder: selectedFolder)
        }
        .sheet(item: $bookmarkToEdit) { bookmark in
            EditBookmarkSheet(bookmark: bookmark)
        }
        .sheet(isPresented: $showImportSheet) {
            bookmarksManager.loadFaviconsForMissing(in: allBookmarks)
        } content: {
            ImportWizardView()
        }
        .onChange(of: rootFolders) { _, _ in
            validateSelectedFolder()
        }
        .onChange(of: selectedFolder) { _, newFolder in
            if newFolder != nil {
                showFavoritesOnly = false
            }
        }
        .onChange(of: searchText) { _, _ in
            selectionManager.clearSelection()
        }
        .onChange(of: selectionManager.selectedIDs) { _, newSelection in
            // Update inspector when single selection
            if newSelection.count == 1, let id = newSelection.first {
                selectedBookmark = sortedBookmarks.first { $0.id == id }
            } else {
                selectedBookmark = nil
            }
        }
        .overlay(alignment: .topTrailing) {
            if showError, let message = errorMessage {
                ErrorToast(message: message, isPresented: $showError)
                    .padding(16)
            }
        }
    }

    // MARK: - Content Area

    @ViewBuilder
    private var contentArea: some View {
        VStack(spacing: 0) {
            contentHeader
            Divider()

            if filteredBookmarks.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                switch viewMode {
                case .grid:
                    ScrollView {
                        bookmarksGrid
                            .padding()
                    }
                case .list:
                    bookmarksTable
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }

    // MARK: - Content Header

    private var contentHeader: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(contentTitle)
                .font(.title2)
                .fontWeight(.semibold)

            Spacer()

            if selectionManager.hasSelection {
                Text("\(selectionManager.selectionCount) selected")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Picker("View Mode", selection: $viewMode) {
                Label("Grid", systemImage: "square.grid.2x2")
                    .tag(ViewMode.grid)
                Label("List", systemImage: "list.bullet")
                    .tag(ViewMode.list)
            }
            .pickerStyle(.segmented)
            .fixedSize()
            .help("Toggle view mode")

            sortMenu
        }
        .frame(height: 44)
        .padding(.horizontal, 16)
    }

    private var contentTitle: String {
        if showFavoritesOnly {
            "Favorites"
        } else if let folder = selectedFolder {
            folder.name
        } else if !searchText.isEmpty {
            "Search Results"
        } else {
            "All Bookmarks"
        }
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $sortOrder) {
                Label("Date Added", systemImage: "calendar")
                    .tag(SortOrder.dateAdded)
                Label("Title", systemImage: "textformat")
                    .tag(SortOrder.title)
                Label("Most Visited", systemImage: "chart.bar")
                    .tag(SortOrder.visitCount)
            }

            Divider()

            Picker("Order", selection: $sortAscending) {
                Label("Descending", systemImage: "arrow.down")
                    .tag(false)
                Label("Ascending", systemImage: "arrow.up")
                    .tag(true)
            }
        } label: {
            Image(systemName: "arrow.up.arrow.down")
                .frame(width: 24, height: 24)
        }
        .help("Sort bookmarks")
    }

    // MARK: - Grid View

    private var bookmarksGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 12) {
            ForEach(sortedBookmarks) { bookmark in
                BookmarkGridCard(
                    bookmark: bookmark,
                    isLoadingFavicon: bookmarksManager.isFaviconLoading(for: bookmark.id),
                    isSelected: selectionManager.isSelected(bookmark.id),
                    selectedBookmarkIDs: selectionManager.selectedIDs,
                ) {
                    handleGridCardTap(bookmark)
                }
                .contextMenu {
                    bookmarkContextMenu(bookmark)
                }
            }
        }
    }

    /// Fixed-count grid columns for consistent item sizing.
    private var gridColumns: [GridItem] {
        // Use flexible items within a calculated column count for even sizing
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)
    }

    // MARK: - Table View

    private var bookmarksTable: some View {
        BookmarksTableView(
            bookmarks: sortedBookmarks,
            selectedBookmarkIDs: $selectionManager.selectedIDs,
            loadingFavicons: bookmarksManager.loadingFaviconIDs,
            onCreateBookmark: { showCreateBookmarkSheet = true },
            singleBookmarkMenu: { bookmark in
                AnyView(bookmarkContextMenu(bookmark))
            },
            multipleBookmarksMenu: { ids in
                AnyView(multipleBookmarksContextMenu(ids))
            },
            createDragItem: { ids in
                createDragItem(for: ids)
            },
        )
    }

    // MARK: - Inspector

    @ViewBuilder
    private var inspectorContent: some View {
        BookmarkInspectorView(
            bookmark: selectedBookmark,
            onOpen: { bookmark in
                openBookmark(bookmark)
            },
            onEdit: { bookmark in
                bookmarkToEdit = bookmark
            },
            onDelete: { bookmark in
                bookmarksManager.deleteBookmark(bookmark)
                selectedBookmark = nil
            },
            onToggleFavorite: { bookmark in
                if bookmark.isFavorite {
                    bookmarksManager.removeFromFavorites(bookmark)
                } else {
                    bookmarksManager.addToFavorites(bookmark, mode: .shortcut)
                }
            },
            onSaveOffline: { bookmark in
                offlineContentManager.saveBookmarkOffline(
                    bookmark,
                    activePageID: windowState.activePageID,
                    tabManager: tabManager,
                )
            },
            onRemoveOffline: { bookmark in
                offlineContentManager.deleteOfflineContent(for: bookmark)
            },
            folderPath: folderPath(for: selectedBookmark),
        )
    }

    private func folderPath(for bookmark: Bookmark?) -> String? {
        guard let bookmark, let folder = bookmark.folder else { return nil }

        var path = [folder.name]
        var current = folder
        while let parent = current.parentFolder {
            path.insert(parent.name, at: 0)
            current = parent
        }
        return path.joined(separator: " > ")
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label(showFavoritesOnly ? "No Favorites" : "No Bookmarks", systemImage: "bookmark")
        } description: {
            if searchText.isEmpty {
                if showFavoritesOnly {
                    Text("Add bookmarks to favorites to see them here")
                } else if selectedFolder != nil {
                    Text("This folder is empty")
                } else {
                    Text("Create a bookmark to get started")
                }
            } else {
                Text("No bookmarks match '\(searchText)'")
            }
        } actions: {
            if searchText.isEmpty, !showFavoritesOnly {
                Button("New Bookmark") {
                    showCreateBookmarkSheet = true
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            if selectionManager.hasSelection {
                let selectedCount = selectionManager.selectionCount
                let bookmarks = sortedBookmarks.filter { selectionManager.isSelected($0.id) }

                Button("Open All (\(selectedCount))") {
                    openMultipleBookmarks(bookmarks)
                }

                Button("Delete \(selectedCount)", role: .destructive) {
                    deleteMultipleBookmarks(bookmarks)
                }
            }

            // Inspector toggle
            Button {
                showInspector.toggle()
            } label: {
                Label("Inspector", systemImage: showInspector ? "sidebar.right" : "sidebar.right")
            }
            .help(showInspector ? "Hide Inspector" : "Show Inspector")

            Menu {
                Button("New Bookmark...") {
                    showCreateBookmarkSheet = true
                }
                .keyboardShortcut("n", modifiers: .command)

                Button("New Folder...") {
                    showCreateFolderSheet = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Divider()

                Button("Import…") {
                    showImportSheet = true
                }

                Button("Export Bookmarks...") {
                    exportBookmarks()
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
            .help("More actions")
        }
    }

    // MARK: - Computed Properties

    private var filteredBookmarks: [Bookmark] {
        var result = allBookmarks

        if showFavoritesOnly {
            result = result.filter(\.isFavorite)
        } else if let selectedFolder {
            let folderID = selectedFolder.id
            result = result.filter { $0.folderID == folderID }
        }

        if !searchText.isEmpty {
            result = result.filter { bookmark in
                bookmark.title.localizedCaseInsensitiveContains(searchText)
                    || bookmark.url.absoluteString.localizedCaseInsensitiveContains(searchText)
                    || bookmark.tags.contains(where: { $0.localizedCaseInsensitiveContains(searchText) })
            }
        }

        return result
    }

    private var sortedBookmarks: [Bookmark] {
        let sorted: [Bookmark] = switch sortOrder {
        case .dateAdded:
            filteredBookmarks.sorted { $0.createdAt < $1.createdAt }
        case .title:
            filteredBookmarks.sorted {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            }
        case .visitCount:
            filteredBookmarks.sorted {
                if $0.visitCount == $1.visitCount {
                    return $0.createdAt < $1.createdAt
                }
                return $0.visitCount < $1.visitCount
            }
        }

        return sortAscending ? sorted : sorted.reversed()
    }

    // MARK: - Actions

    private func handleGridCardTap(_ bookmark: Bookmark) {
        let shouldOpenBookmark = selectionManager.handleClick(
            on: bookmark.id,
            in: sortedBookmarks.map(\.id),
            commandDown: NSEvent.modifierFlags.contains(.command),
            shiftDown: NSEvent.modifierFlags.contains(.shift),
        )

        if shouldOpenBookmark {
            openBookmark(bookmark)
        }
    }

    private func openBookmark(_ bookmark: Bookmark) {
        tabManager.createTab(url: bookmark.url, makeActive: false, loadImmediately: true)
        bookmarksManager.recordVisit(for: bookmark)
    }

    private func openBookmarkInCurrentTab(_ bookmark: Bookmark) {
        if let activePage = windowState.activePage {
            activePage.url = bookmark.url
            bookmarksManager.recordVisit(for: bookmark)
        }
    }

    private func openMultipleBookmarks(_ bookmarks: [Bookmark]) {
        for bookmark in bookmarks {
            tabManager.createTab(url: bookmark.url, makeActive: false, loadImmediately: true)
            bookmarksManager.recordVisit(for: bookmark)
        }
    }

    private func deleteMultipleBookmarks(_ bookmarks: [Bookmark]) {
        for bookmark in bookmarks {
            bookmarksManager.deleteBookmark(bookmark)
        }
        selectionManager.clearSelection()
        selectedBookmark = nil
    }

    private func exportBookmarks() {
        Task {
            do {
                let exporter = BookmarkExporter(modelContainer: modelContext.container)
                let result = try await exporter.exportToHTML()
                let tempURL = result.url

                guard let window = NSApp.keyWindow else {
                    try? FileManager.default.removeItem(at: tempURL)
                    return
                }

                let savePanel = NSSavePanel()
                savePanel.allowedContentTypes = [.html]
                savePanel.nameFieldStringValue = tempURL.lastPathComponent
                savePanel.canCreateDirectories = true

                let response = await savePanel.beginSheetModal(for: window)

                if response == .OK, let destinationURL = savePanel.url {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destinationURL)
                    Logger.info("Exported \(result.count) bookmarks to: \(destinationURL)", category: Logger.data)
                } else {
                    try? FileManager.default.removeItem(at: tempURL)
                }
            } catch {
                Logger.error("Export failed: \(error)", category: Logger.data)
                showErrorToast("Failed to export bookmarks")
            }
        }
    }

    private func validateSelectedFolder() {
        guard let selected = selectedFolder else { return }

        let selectedID = selected.id
        let descriptor = FetchDescriptor<BookmarkFolder>(
            predicate: #Predicate { $0.id == selectedID },
        )

        let exists = (try? modelContext.fetch(descriptor).first) != nil

        if !exists {
            selectedFolder = nil
        }
    }

    // MARK: - Drag & Drop

    private func createDragItem(for bookmark: Bookmark) -> BookmarkDragItem {
        BookmarkDragItem(
            bookmarkIDs: [bookmark.id],
            primaryURL: bookmark.url,
            primaryTitle: bookmark.title,
        )
    }

    private func createDragItem(for bookmarkIDs: Set<Bookmark.ID>) -> BookmarkDragItem {
        let ids = Array(bookmarkIDs)
        let firstBookmark = sortedBookmarks.first { bookmarkIDs.contains($0.id) }

        return BookmarkDragItem(
            bookmarkIDs: ids,
            primaryURL: firstBookmark?.url,
            primaryTitle: firstBookmark?.title,
        )
    }

    private func showErrorToast(_ message: String) {
        errorMessage = message
        showError = true

        Task {
            try? await Task.sleep(for: .seconds(3))
            showError = false
        }
    }

    // MARK: - Context Menus

    @ViewBuilder
    private func multipleBookmarksContextMenu(_ ids: Set<Bookmark.ID>) -> some View {
        let bookmarks = sortedBookmarks.filter { ids.contains($0.id) }

        Button("Open All (\(bookmarks.count))") {
            openMultipleBookmarks(bookmarks)
        }

        Divider()

        Button("Delete \(bookmarks.count) Bookmarks", role: .destructive) {
            deleteMultipleBookmarks(bookmarks)
        }
    }

    @ViewBuilder
    private func bookmarkContextMenu(_ bookmark: Bookmark) -> some View {
        Button("Open") {
            openBookmark(bookmark)
        }

        Button("Open in Current Tab") {
            openBookmarkInCurrentTab(bookmark)
        }

        Divider()

        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(bookmark.url.absoluteString, forType: .string)
        }

        Divider()

        Button("Reload Favicon") {
            bookmarksManager.reloadFavicon(for: bookmark)
        }

        Divider()

        if bookmark.isFavorite {
            Button("Remove from Favorites") {
                bookmarksManager.removeFromFavorites(bookmark)
            }
        } else {
            Button("Add to Favorites") {
                bookmarksManager.addToFavorites(bookmark, mode: .shortcut)
            }
        }

        Divider()

        offlineMenuSection(for: bookmark)

        Divider()

        Button("Edit...") {
            bookmarkToEdit = bookmark
        }

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
}

// MARK: - Preview

#Preview(traits: .modifier(RefraxPreviewModifier())) {
    BookmarksView()
        .frame(width: 1_000, height: 600)
}
