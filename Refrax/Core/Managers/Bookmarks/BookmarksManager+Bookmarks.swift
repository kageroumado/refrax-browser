import Foundation
import SwiftData

// MARK: - Bookmark Operations

extension BookmarksManager {
    /// Create a new bookmark with the specified properties.
    ///
    /// The bookmark is immediately persisted to SwiftData and added to the specified
    /// folder if provided. If favorited as a live favorite, creates the associated
    /// global tab.
    ///
    /// - Parameters:
    ///   - url: The webpage URL to bookmark
    ///   - title: Display title (defaults to URL host if nil)
    ///   - folder: Optional parent folder
    ///   - isFavorite: Whether to show in sidebar favorites
    ///   - favoriteMode: Interaction mode if favorited (default: .liveFavorite)
    ///   - tags: Categorization tags
    ///   - spaceID: Optional space assignment
    ///   - faviconData: Optional small favicon data to set immediately
    ///   - largeFaviconData: Optional large favicon data to set immediately
    /// - Returns: The created bookmark
    @discardableResult
    func createBookmark(
        url: URL,
        title: String? = nil,
        folder: BookmarkFolder? = nil,
        isFavorite: Bool = false,
        favoriteMode: FavoriteMode = .liveFavorite,
        tags: [String] = [],
        spaceID: UUID? = nil,
        faviconData: Data? = nil,
        largeFaviconData: Data? = nil,
    ) -> Bookmark {
        let favoritePosition: FavoritePosition = if isFavorite {
            calculateNextFavoritePosition()
        } else {
            FavoritePosition(row: 0, col: 0)
        }

        let bookmark = Bookmark(
            url: url,
            title: title,
            folder: folder,
            isFavorite: isFavorite,
            favoriteMode: favoriteMode,
            favoritePosition: favoritePosition,
            tags: tags,
            spaceID: spaceID,
        )

        folder?.addBookmark(bookmark)
        _modelContext.insert(bookmark)

        if isFavorite, favoriteMode == .liveFavorite {
            createLiveFavoriteTab(for: bookmark)
        }

        // Set favicon data if provided (before refreshFavoritesCache to avoid flash)
        if faviconData != nil || largeFaviconData != nil {
            bookmark.updateFavicon(small: faviconData, large: largeFaviconData)
        }
        // Load favicon for shortcut favorites only if not already provided.
        // Live favorites get favicon via WebKit's IconLoadingDelegateAdapter,
        // which is synced to bookmark via syncFaviconFromTab.
        else if isFavorite, favoriteMode == .shortcut {
            let bookmarkID = bookmark.id
            Task.detached(priority: .utility) { [weak self] in
                await self?.loadFavicon(forID: bookmarkID, url: url)
            }
        }

        scheduleSave()
        scheduleRefreshFavoritesCache()

        return bookmark
    }

    /// Delete a bookmark entirely.
    ///
    /// Removes from folder, favorites cache, and persistence. If the bookmark has a
    /// live favorite tab, removes it from BrowserState.
    ///
    /// - Parameter bookmark: Bookmark to delete
    func deleteBookmark(_ bookmark: Bookmark) {
        if bookmark.favoriteMode == .liveFavorite {
            removeLiveFavoriteTab(for: bookmark)
        }

        // Clean up offline content if present
        offlineContentManager?.deleteOfflineContent(for: bookmark)

        bookmark.folder?.removeBookmark(bookmark)
        _modelContext.delete(bookmark)
        scheduleSave()

        // Refresh favorites if was favorited
        if bookmark.isFavorite {
            scheduleRefreshFavoritesCache()
        }

        Logger.info("Bookmark deleted: \(bookmark.title)", category: Logger.data)
    }

    /// Update a bookmark's properties.
    ///
    /// - Parameters:
    ///   - bookmark: Bookmark to update
    ///   - title: New title (optional)
    ///   - url: New URL (optional)
    ///   - tags: New tags (optional)
    ///   - folder: New parent folder (optional, pass explicit nil to remove from folder)
    func updateBookmark(
        _ bookmark: Bookmark,
        title: String? = nil,
        url: URL? = nil,
        tags: [String]? = nil,
        folder: BookmarkFolder?? = nil,
    ) {
        if let title {
            bookmark.updateTitle(title)
        }

        if let url {
            bookmark.updateURL(url)
            if let tab = tabManager.state.liveFavoriteTab(for: bookmark.id) {
                tab.activePage.url = url
            }
        }

        if let tags {
            bookmark.tags = tags
            bookmark.lastModified = Date()
        }

        if let folder {
            bookmark.folder?.removeBookmark(bookmark)
            folder?.addBookmark(bookmark)
        }

        scheduleSave()

        if bookmark.isFavorite {
            scheduleRefreshFavoritesCache()
        }
    }
}
