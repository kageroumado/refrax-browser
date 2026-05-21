import Foundation
import SwiftData

// MARK: - Live Favorite Tab Management

extension BookmarksManager {
    /// Creates a global live favorite tab for a bookmark.
    ///
    /// The tab is stored in `BrowserState.liveFavoriteTabs` and uses global website
    /// data storage. This is called when a bookmark is favorited with `.liveFavorite` mode.
    ///
    /// - Parameters:
    ///   - bookmark: Bookmark to create tab for
    ///   - loadImmediately: Whether to start loading the page immediately.
    ///     Defaults to `true` for user-initiated actions.
    func createLiveFavoriteTab(for bookmark: Bookmark, loadImmediately: Bool = true) {
        if tabManager.state.liveFavoriteTab(for: bookmark.id) != nil {
            return
        }

        let liveTabCount = tabManager.state.liveFavoriteTabs.count
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
        guard let tab = tabManager.state.liveFavoriteTab(for: bookmark.id) else { return }

        tabManager.closeLiveFavoriteTab(tab)
    }

    /// Gets the live favorite tab for a bookmark, if one exists.
    ///
    /// - Parameter bookmark: Bookmark to look up
    /// - Returns: The associated Tab, or nil if not a live favorite
    func liveFavoriteTab(for bookmark: Bookmark) -> Tab? {
        tabManager.state.liveFavoriteTab(for: bookmark.id)
    }

    /// Handle a live favorite tab being closed by user.
    ///
    /// When user closes a live favorite tab, converts the bookmark to shortcut mode
    /// or removes it from favorites entirely.
    ///
    /// - Parameters:
    ///   - tab: Tab that was closed
    ///   - convertToShortcut: If true, converts to shortcut. If false, removes from favorites.
    func handleLiveFavoriteTabClosed(_ tab: Tab, convertToShortcut: Bool = true) {
        guard let bookmark = tab.linkedBookmark else { return }

        if convertToShortcut {
            bookmark.favoriteMode = .shortcut
            scheduleSave()
            scheduleRefreshFavoritesCache()
            Logger.info("Live favorite tab converted to shortcut: \(bookmark.title)", category: Logger.data)
        } else {
            // Remove from favorites entirely
            removeFromFavorites(bookmark)
        }
    }
}
