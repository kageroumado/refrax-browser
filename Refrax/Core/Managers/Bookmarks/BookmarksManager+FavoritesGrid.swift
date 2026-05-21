import Foundation
import SwiftData

// MARK: - Favorites Grid Helpers

extension BookmarksManager {
    /// Calculate optimal grid layout for current favorites.
    ///
    /// Determines number of columns (1-4) based on favorites count and calculates
    /// 2D item array for rendering.
    ///
    /// - Returns: Grid layout with columns, rows, and positioned items
    func calculateFavoritesLayout() -> FavoritesGridLayout {
        let sortedFavorites = favorites.sorted { $0.position < $1.position }

        // Calculate columns (1-4 based on count)
        let columns = min(max(1, sortedFavorites.count), _maxFavoritesGridColumns)
        let rows = (sortedFavorites.count + columns - 1) / columns

        // Build 2D array
        var items: [[FavoriteItem?]] = Array(
            repeating: Array(repeating: nil, count: columns),
            count: rows,
        )

        for favorite in sortedFavorites {
            let row = favorite.position.row
            let col = favorite.position.column

            if row < rows, col < columns {
                items[row][col] = favorite
            }
        }

        return FavoritesGridLayout(columns: columns, rows: rows, items: items)
    }

    /// Calculate next available favorite position.
    ///
    /// Uses a running counter for O(1) performance. The counter is synced with
    /// actual favorites count when the cache is refreshed.
    ///
    /// - Returns: Next available position
    func calculateNextFavoritePosition() -> FavoritePosition {
        // Use simple counter based on current favorites count + pending additions
        // The cache refresh will normalize positions if there are gaps
        let index = favorites.count + _pendingFavoriteCount
        _pendingFavoriteCount += 1

        return FavoritePosition(
            row: index / _maxFavoritesGridColumns,
            col: index % _maxFavoritesGridColumns,
        )
    }

    /// Normalize favorite positions to eliminate gaps and overlaps.
    ///
    /// Reorders all favorites sequentially from 0, maintaining relative order.
    func normalizeFavoritePositions() {
        let sortedFavorites = favorites.sorted { $0.position < $1.position }

        for (index, favorite) in sortedFavorites.enumerated() {
            let newPosition = FavoritePosition(
                row: index / _maxFavoritesGridColumns,
                col: index % _maxFavoritesGridColumns,
            )

            switch favorite.type {
            case let .liveFavorite(bookmark, _), let .shortcut(bookmark):
                if bookmark.favoritePosition != newPosition {
                    bookmark.favoritePosition = newPosition
                }
            case let .folder(folder):
                if folder.favoritePosition != newPosition {
                    folder.favoritePosition = newPosition
                }
            case let .appShortcut(shortcut):
                if shortcut.position != newPosition {
                    shortcut.position = newPosition
                }
            }
        }
    }

    /// Schedule a coalesced favorites cache refresh.
    ///
    /// Multiple calls within the same runloop iteration are coalesced into a single refresh.
    /// This prevents redundant cache rebuilds during bulk operations (e.g., initial data seeding).
    ///
    /// Use this method for mutation operations. Use `refreshFavoritesCache()` directly only
    /// when an immediate refresh is required (e.g., initial setup).
    func scheduleRefreshFavoritesCache() {
        // Tests can opt into synchronous refreshes for deterministic behavior
        if _useSynchronousRefreshes {
            refreshFavoritesCache()
            return
        }

        guard !_refreshScheduled else { return }
        _refreshScheduled = true

        DispatchQueue.main.async {
            self._refreshScheduled = false
            self.refreshFavoritesCache()
        }
    }

    /// Refresh favorites cache from persistence.
    ///
    /// Queries all favorited bookmarks, folders, and app shortcuts and rebuilds the cache.
    /// For live favorites, includes the associated Tab from BrowserState and syncs
    /// favicons from tabs to their linked bookmarks.
    ///
    /// Only increments `favoritesVersion` if the structure actually changed (items added,
    /// removed, or reordered). Favicon-only syncs don't trigger version increment.
    func refreshFavoritesCache() {
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

        var items: [FavoriteItem] = []

        for bookmark in favoriteBookmarks {
            let itemType: FavoriteItem.ItemType
            if bookmark.favoriteMode == .liveFavorite {
                // Check if tab already exists in runtime state
                if let existingTab = tabManager.state.liveFavoriteTab(for: bookmark.id) {
                    // Sync favicon from tab to bookmark for persistence
                    syncFaviconFromTab(existingTab)
                    itemType = .liveFavorite(bookmark, existingTab)
                } else if let persistedTab = bookmark.linkedTab {
                    // Tab was persisted but not yet in runtime state - restore it
                    tabManager.state.addLiveFavoriteTab(persistedTab)
                    syncFaviconFromTab(persistedTab)
                    itemType = .liveFavorite(bookmark, persistedTab)
                } else {
                    // No existing tab - create new one (lazy load for launch performance)
                    let tab = tabManager.createLiveFavoriteTab(for: bookmark, loadImmediately: false)
                    itemType = .liveFavorite(bookmark, tab)
                }
            } else {
                itemType = .shortcut(bookmark)
            }

            items.append(FavoriteItem(
                id: bookmark.id,
                type: itemType,
                position: bookmark.favoritePosition,
            ))
        }

        for folder in favoriteFolders {
            items.append(FavoriteItem(
                id: folder.id,
                type: .folder(folder),
                position: folder.favoritePosition,
            ))
        }

        for shortcut in appShortcuts {
            items.append(FavoriteItem(
                id: shortcut.id,
                type: .appShortcut(shortcut),
                position: shortcut.position,
            ))
        }

        // Capture old structure for comparison
        let oldFavoriteIDs = favorites.map(\.id)
        let newItems = items.sorted { $0.position < $1.position }
        let newFavoriteIDs = newItems.map(\.id)

        // Check if structure changed (IDs or order)
        let structureChanged = oldFavoriteIDs != newFavoriteIDs

        favorites = newItems

        // Reset pending counter now that cache is current
        _pendingFavoriteCount = 0

        // Update cache key
        _favoritesCacheKey = FavoritesCacheKey(
            count: items.count,
            lastModified: Date(),
            favoriteIDs: Set(items.map(\.id)),
        )

        // Only increment version if structure actually changed (not just favicon sync)
        if structureChanged {
            favoritesVersion += 1
            Logger.debug("Favorites structure changed: \(items.count) items, version=\(favoritesVersion)", category: Logger.data)
        }
    }
}
