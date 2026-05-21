import Foundation
import SwiftData

// MARK: - Favorites Management

extension BookmarksManager {
    /// Add a bookmark to favorites.
    ///
    /// Marks the bookmark as a favorite and assigns it the next available grid position.
    /// For live favorites (default), creates a global tab. For shortcuts without a favicon,
    /// triggers an async fetch.
    ///
    /// - Parameters:
    ///   - bookmark: Bookmark to favorite
    ///   - mode: Favorite mode (default: .liveFavorite)
    func addToFavorites(_ bookmark: Bookmark, mode: FavoriteMode = .liveFavorite) {
        guard !bookmark.isFavorite else { return }

        bookmark.isFavorite = true
        bookmark.favoriteMode = mode
        bookmark.favoritePosition = calculateNextFavoritePosition()

        if mode == .liveFavorite {
            createLiveFavoriteTab(for: bookmark)
        }

        // Load favicon for shortcuts only if missing.
        // Live favorites get favicon via WebKit's IconLoadingDelegateAdapter.
        if mode == .shortcut, bookmark.faviconData == nil {
            let bookmarkID = bookmark.id
            let url = bookmark.url
            Task.detached(priority: .utility) { [weak self] in
                await self?.loadFavicon(forID: bookmarkID, url: url)
            }
        }

        scheduleSave()
        scheduleRefreshFavoritesCache()
    }

    /// Add a bookmark to favorites by ID (for drag-and-drop).
    ///
    /// - Parameters:
    ///   - bookmarkID: ID of bookmark to favorite
    ///   - mode: Favorite mode (.shortcut or .liveTab)
    func addToFavorites(_ bookmarkID: UUID, mode: FavoriteMode) {
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.id == bookmarkID },
        )
        guard let bookmark = try? _modelContext.fetch(descriptor).first else {
            Logger.warning("Bookmark not found for favorites: \(bookmarkID)", category: Logger.data)
            return
        }
        addToFavorites(bookmark, mode: mode)
    }

    /// Add multiple bookmarks to favorites by IDs (for batch drag-and-drop).
    ///
    /// - Parameters:
    ///   - bookmarkIDs: IDs of bookmarks to favorite
    ///   - mode: Favorite mode (.shortcut or .liveTab)
    func addMultipleToFavorites(_ bookmarkIDs: [UUID], mode: FavoriteMode) {
        for id in bookmarkIDs {
            addToFavorites(id, mode: mode)
        }
    }

    /// Remove a bookmark from favorites.
    ///
    /// The bookmark still exists, just no longer shown in sidebar. If it's a live
    /// favorite, the tab is converted to a regular tab in the active space rather
    /// than being closed.
    ///
    /// - Parameter bookmark: Bookmark to unfavorite
    func removeFromFavorites(_ bookmark: Bookmark) {
        guard bookmark.isFavorite else { return }

        bookmark.isFavorite = false

        if bookmark.favoriteMode == .liveFavorite,
           let tab = tabManager.state.liveFavoriteTab(for: bookmark.id) {
            // Try to convert to regular tab; fall back to removal if no active window
            if !tabManager.convertLiveFavoriteToTab(tab, bookmark: bookmark) {
                removeLiveFavoriteTab(for: bookmark)
            }
        }

        scheduleSave()
        scheduleRefreshFavoritesCache()
    }

    /// Switch a favorite bookmark's mode between shortcut and live favorite.
    ///
    /// When switching to live favorite, creates the global tab. When switching to
    /// shortcut, removes the global tab.
    ///
    /// - Parameters:
    ///   - bookmark: Favorited bookmark to modify
    ///   - mode: New favorite mode
    func changeFavoriteMode(_ bookmark: Bookmark, to mode: FavoriteMode) {
        guard bookmark.isFavorite else { return }
        guard bookmark.favoriteMode != mode else { return }

        let oldMode = bookmark.favoriteMode
        bookmark.favoriteMode = mode

        switch (oldMode, mode) {
        case (.shortcut, .liveFavorite):
            createLiveFavoriteTab(for: bookmark)
        case (.liveFavorite, .shortcut):
            removeLiveFavoriteTab(for: bookmark)
        default:
            break
        }

        scheduleSave()
        scheduleRefreshFavoritesCache()

        Logger.debug("Changed favorite mode: \(bookmark.title) → \(mode)", category: Logger.data)
    }

    /// Reorder a favorite item in the grid.
    ///
    /// Updates the position and normalizes all favorite positions to maintain consistency.
    ///
    /// - Parameters:
    ///   - item: Favorite item to reorder
    ///   - from: Original position
    ///   - to: Target position
    func reorderFavorite(
        _ item: FavoriteItem,
        from: (row: Int, col: Int),
        to: (row: Int, col: Int),
    ) {
        guard from != to else { return }

        let toIndex = to.row * _maxFavoritesGridColumns + to.col

        // Get all favorite models sorted by current position
        let bookmarkDescriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.isFavorite },
        )
        let favoriteBookmarks = (try? _modelContext.fetch(bookmarkDescriptor)) ?? []

        let folderDescriptor = FetchDescriptor<BookmarkFolder>(
            predicate: #Predicate { $0.isFavorite },
        )
        let favoriteFolders = (try? _modelContext.fetch(folderDescriptor)) ?? []

        let appShortcutDescriptor = FetchDescriptor<AppShortcut>()
        let appShortcuts = (try? _modelContext.fetch(appShortcutDescriptor)) ?? []

        // Build array of (position, setter) pairs for all favorites
        var positionedItems: [(index: Int, id: UUID, name: String, setPosition: (FavoritePosition) -> Void)] = []

        for bookmark in favoriteBookmarks {
            let pos = bookmark.favoritePosition
            let idx = pos.row * _maxFavoritesGridColumns + pos.column
            positionedItems.append((idx, bookmark.id, bookmark.title, { bookmark.favoritePosition = $0 }))
        }

        for folder in favoriteFolders {
            let pos = folder.favoritePosition
            let idx = pos.row * _maxFavoritesGridColumns + pos.column
            positionedItems.append((idx, folder.id, folder.name, { folder.favoritePosition = $0 }))
        }

        for shortcut in appShortcuts {
            let pos = shortcut.position
            let idx = pos.row * _maxFavoritesGridColumns + pos.column
            positionedItems.append((idx, shortcut.id, shortcut.displayName, { shortcut.position = $0 }))
        }

        // Sort by current index
        positionedItems.sort { $0.index < $1.index }

        // Find the item being moved
        guard let movingItemIndex = positionedItems.firstIndex(where: { $0.id == item.id }) else {
            Logger.warning("Favorite item not found for reorder: \(item.id)", category: Logger.data)
            return
        }

        // Remove from current position and insert at new position
        let movingItem = positionedItems.remove(at: movingItemIndex)
        let insertAt = min(toIndex, positionedItems.count)
        positionedItems.insert(movingItem, at: insertAt)

        // Reassign sequential positions
        for (newIndex, posItem) in positionedItems.enumerated() {
            let newPosition = FavoritePosition(
                row: newIndex / _maxFavoritesGridColumns,
                col: newIndex % _maxFavoritesGridColumns,
            )
            posItem.setPosition(newPosition)
        }

        scheduleSave()
        scheduleRefreshFavoritesCache()

        Logger.debug("Favorite reordered: \(from) → \(to)", category: Logger.data)
    }

    /// Add a folder to favorites.
    ///
    /// - Parameter folder: Folder to favorite
    func addFolderToFavorites(_ folder: BookmarkFolder) {
        guard !folder.isFavorite else { return }

        folder.isFavorite = true
        folder.favoritePosition = calculateNextFavoritePosition()

        scheduleSave()
        scheduleRefreshFavoritesCache()
    }

    /// Remove a folder from favorites.
    ///
    /// - Parameter folder: Folder to unfavorite
    func removeFolderFromFavorites(_ folder: BookmarkFolder) {
        guard folder.isFavorite else { return }

        folder.isFavorite = false

        scheduleSave()
        scheduleRefreshFavoritesCache()
    }

    // MARK: - App Shortcuts

    /// Add an app shortcut to favorites.
    ///
    /// - Parameter type: The type of app shortcut to add.
    /// - Returns: The created app shortcut.
    @discardableResult
    func addAppShortcut(_ type: AppShortcutType) -> AppShortcut {
        if let existing = allAppShortcuts().first(where: { $0.shortcutType == type }) {
            return existing
        }

        let position = calculateNextFavoritePosition()
        let shortcut = AppShortcut(type: type, position: position)

        _modelContext.insert(shortcut)
        scheduleSave()
        scheduleRefreshFavoritesCache()

        return shortcut
    }

    /// Remove an app shortcut from favorites.
    ///
    /// - Parameter shortcut: The app shortcut to remove.
    func removeAppShortcut(_ shortcut: AppShortcut) {
        _modelContext.delete(shortcut)
        scheduleSave()
        scheduleRefreshFavoritesCache()
    }

    /// Get all app shortcuts.
    func allAppShortcuts() -> [AppShortcut] {
        let descriptor = FetchDescriptor<AppShortcut>(sortBy: [SortDescriptor(\.positionValue)])
        return (try? _modelContext.fetch(descriptor)) ?? []
    }
}
