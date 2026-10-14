import Foundation
import SwiftData

// MARK: - Live Favorite Tab Management

extension BookmarksManager {
    /// Creates a global live favorite tab for a bookmark.
    ///
    /// The tab is stored in `BrowserState.favoriteTabs` and uses global website
    /// data storage. This is called when a bookmark is favorited in `.liveFavorite` mode.
    ///
    /// - Parameters:
    ///   - bookmark: Bookmark to create tab for
    ///   - loadImmediately: Whether to start loading the page immediately.
    ///     Defaults to `true` for user-initiated actions.
    func createLiveFavoriteTab(for bookmark: Bookmark, loadImmediately: Bool = true) {
        if tabManager.state.favoriteTab(for: bookmark.id) != nil {
            return
        }

        let liveTabCount = tabManager.state.favoriteTabs.count
        if liveTabCount >= _maxLiveFavoriteTabs {
            Logger.warning("Live favorite tab limit reached (\(_maxLiveFavoriteTabs))", category: Logger.data)
            return
        }

        tabManager.createLiveFavoriteTab(for: bookmark, loadImmediately: loadImmediately)
    }

    /// Removes the live favorite tab associated with a bookmark.
    ///
    /// - Parameter bookmark: Bookmark whose tab should be removed
    func removeLiveFavoriteTab(for bookmark: Bookmark) {
        guard let tab = tabManager.state.favoriteTab(for: bookmark.id) else { return }

        tabManager.closeLiveFavoriteTab(tab)
    }

    /// Gets the live favorite tab for a bookmark, if one exists.
    ///
    /// - Parameter bookmark: Bookmark to look up
    /// - Returns: The associated Tab, or nil if not a live favorite
    func favoriteTab(for bookmark: Bookmark) -> Tab? {
        tabManager.state.favoriteTab(for: bookmark.id)
    }

    /// Favorites an existing tab: a favorited bookmark at `home`, linked to the tab.
    ///
    /// The caller has already made the tab a favorite (``TabManager/makeFavorite(_:home:in:)``).
    @discardableResult
    func createFavoriteBookmark(for tab: Tab, home: URL) -> Bookmark {
        let bookmark = Bookmark(
            url: home,
            title: tab.displayTitle,
            isFavorite: true,
            favoriteMode: .liveFavorite,
            favoritePosition: calculateNextFavoritePosition(),
        )
        _modelContext.insert(bookmark)
        tab.linkedBookmark = bookmark
        bookmark.linkedTab = tab
        bookmark.updateFavicon(small: tab.activePage.faviconData, large: tab.activePage.largeFaviconData)
        scheduleSave()
        scheduleRefreshFavoritesCache()
        return bookmark
    }
}
