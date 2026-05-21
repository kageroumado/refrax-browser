import Foundation
import Observation
import SwiftData
import SwiftUI

/// Manages bookmarks, folders, and favorites display across the application.
///
/// `BookmarksManager` is the central coordinator for Refrax's bookmarking system,
/// handling everything from creating bookmarks to managing the favorites grid in the sidebar.
///
/// ## Core Responsibilities
///
/// - **Bookmark CRUD**: Create, read, update, and delete bookmarks
/// - **Folder Management**: Hierarchical organization up to 3 levels deep
/// - **Favorites Grid**: Position management and layout calculation
/// - **Live Favorite Tabs**: Coordinate with TabManager for persistent global tabs
/// - **Visit Tracking**: Sync with HistoryManager for analytics
/// - **Search & Filter**: Query bookmarks by text, tags, folders, spaces
///
/// ## File layout
/// - `BookmarksManager+Bookmarks.swift`: create/update/delete bookmarks.
/// - `BookmarksManager+Favorites.swift`: favorites CRUD + mode changes + folder favorites.
/// - `BookmarksManager+Folders.swift`: folder CRUD + move operations.
/// - `BookmarksManager+LiveFavorites.swift`: live favorite tab creation/cleanup.
/// - `BookmarksManager+Visits.swift`: visit recording + history sync.
/// - `BookmarksManager+Search.swift`: search and filter queries.
/// - `BookmarksManager+FavoritesGrid.swift`: grid layout, positioning, favorites cache.
/// - `BookmarksManager+FolderHierarchy.swift`: hierarchy checks and depth math.
/// - `BookmarksManager+Persistence.swift`: debounced saves.
/// - `BookmarksManager+ImportExport.swift`: import/export placeholders.
/// - `BookmarksManager+Favicons.swift`: favicon fetching and reloads.
/// - `BookmarksManager+Support.swift`: cache key and timeout helper.
@Observable
final class BookmarksManager {
    // MARK: - Dependencies

    /// SwiftData model context for persistence.
    ///
    /// Warning: Not for external use.
    let _modelContext: ModelContext

    /// Tab manager for live tab coordination (unowned to avoid cycles)
    unowned let tabManager: TabManager

    /// History manager for visit tracking (unowned to avoid cycles)
    unowned let historyManager: HistoryManager

    /// Favicon cache for looking up cached favicons before network fetch.
    ///
    /// Warning: Not for external use.
    let _faviconCache: FaviconCache

    /// Offline content manager for cleanup when deleting bookmarks.
    ///
    /// Set via late binding in RefraxAppDelegate.
    var offlineContentManager: OfflineContentManager?

    // MARK: - State

    /// Cached list of favorite items for sidebar display.
    ///
    /// This cache is rebuilt when favorites change and includes live favorite tabs
    /// with their associated Tab instances from BrowserState.
    ///
    /// Warning: Not meant to be set externally.
    var favorites: [FavoriteItem] = []

    /// Cache key for favorites invalidation.
    ///
    /// Warning: Not for external use.
    @ObservationIgnored var _favoritesCacheKey: FavoritesCacheKey?

    /// Version counter that increments on any favorites change (add/remove/reorder).
    /// Used by Sidebar to detect changes that don't affect count.
    var favoritesVersion: Int = 0

    /// Flag to coalesce multiple refresh requests into a single refresh.
    ///
    /// When true, a refresh is already scheduled for the next runloop iteration.
    /// Additional refresh requests are ignored until the scheduled refresh completes.
    ///
    /// Warning: Not for external use.
    @ObservationIgnored var _refreshScheduled = false

    /// When true, `scheduleRefreshFavoritesCache()` calls `refreshFavoritesCache()` synchronously.
    ///
    /// This is used by tests that need deterministic, synchronous behavior.
    /// Production code should leave this false to benefit from refresh coalescing.
    ///
    /// Warning: Not for external use.
    var _useSynchronousRefreshes = false

    /// Counter for favorites added since last cache refresh.
    ///
    /// Used by `calculateNextFavoritePosition()` to assign sequential positions
    /// without querying the database. Reset to 0 when cache is refreshed.
    ///
    /// Warning: Not for external use.
    @ObservationIgnored var _pendingFavoriteCount = 0

    /// Set of bookmark IDs currently having their favicons loaded.
    ///
    /// Views can observe this to show loading indicators during favicon fetches.
    /// Use `isFaviconLoading(for:)` to check a specific bookmark.
    ///
    /// Warning: Not for external use. Use `isFaviconLoading(for:)` instead.
    var _loadingFaviconIDs: Set<UUID> = []

    // MARK: - Configuration

    /// Maximum number of columns in favorites grid.
    ///
    /// Warning: Not for external use.
    let _maxFavoritesGridColumns = 4

    /// Maximum number of live favorite tabs allowed.
    ///
    /// Warning: Not for external use.
    let _maxLiveFavoriteTabs = 20

    /// Debounced saver for bookmark persistence.
    ///
    /// Warning: Not for external use.
    let _saver: DebouncedModelContextSaver

    // MARK: - Initialization

    /// Initialize BookmarksManager with dependencies.
    ///
    /// - Parameters:
    ///   - modelContext: SwiftData context for persistence
    ///   - tabManager: Tab manager for live tab coordination
    ///   - historyManager: History manager for visit tracking
    ///   - faviconCache: Cache for looking up previously loaded favicons
    init(
        modelContext: ModelContext,
        tabManager: TabManager,
        historyManager: HistoryManager,
        faviconCache: FaviconCache,
    ) {
        self._modelContext = modelContext
        self.tabManager = tabManager
        self.historyManager = historyManager
        self._faviconCache = faviconCache
        self._saver = DebouncedModelContextSaver(
            modelContext: modelContext,
            debounceDelay: 1.1,
            logCategory: Logger.data,
        )

        // Heavy SwiftData work is deferred to after first frame.
        // Call performDeferredSetup() from AppDelegate after window is shown.

        Logger.info("BookmarksManager initialized", category: Logger.data)
    }

    /// Performs deferred setup operations that shouldn't block app launch.
    ///
    /// This method should be called after the first frame renders to avoid
    /// blocking app launch. It loads the favorites cache from SwiftData.
    func performDeferredSetup() {
        refreshFavoritesCache()
        Logger.info("BookmarksManager deferred setup complete", category: Logger.data)
    }
}
