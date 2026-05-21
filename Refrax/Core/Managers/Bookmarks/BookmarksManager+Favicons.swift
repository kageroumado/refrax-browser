import Algorithms
import Foundation
import SwiftData

// MARK: - Favicons

extension BookmarksManager {
    /// Load favicons for bookmarks that don't have them yet.
    ///
    /// Called after bookmark creation or import to ensure favicons are loaded.
    /// Updates `_loadingFaviconIDs` to track which bookmarks are currently loading,
    /// allowing views to show loading indicators.
    ///
    /// Favicon fetching runs entirely off MainActor via FaviconCache to avoid
    /// blocking the UI. Only the final bookmark update hops back to MainActor.
    ///
    /// - Parameter bookmarks: Bookmarks to check and load favicons for
    func loadFaviconsForMissing(in bookmarks: [Bookmark]) {
        let needsFavicon = bookmarks.filter { $0.faviconData == nil }

        guard !needsFavicon.isEmpty else { return }

        // Track loading state
        for bookmark in needsFavicon {
            _loadingFaviconIDs.insert(bookmark.id)
        }

        // Capture data for off-MainActor work
        let bookmarkData: [(id: UUID, url: URL)] = needsFavicon.map { ($0.id, $0.url) }
        let bookmarkIDs = Set(needsFavicon.map(\.id))
        let faviconCache = _faviconCache

        // Fire-and-forget: all work runs off MainActor, single hop back for update
        Task.detached(priority: .utility) { [weak self] in
            let results = await Self.fetchFaviconsInBatch(bookmarkData, using: faviconCache)

            // Single MainActor hop: apply results and clear loading state
            await MainActor.run { [weak self] in
                self?.applyFaviconResults(results)
                for id in bookmarkIDs {
                    self?._loadingFaviconIDs.remove(id)
                }
            }
        }
    }

    /// Check if a favicon is currently being loaded for a bookmark.
    ///
    /// - Parameter id: The bookmark ID to check
    /// - Returns: True if the favicon is currently loading
    func isFaviconLoading(for id: UUID) -> Bool {
        _loadingFaviconIDs.contains(id)
    }

    /// Set of bookmark IDs currently having their favicons loaded.
    ///
    /// Read-only access to the loading state for views that need the full set
    /// (e.g., table views that filter by loading state).
    var loadingFaviconIDs: Set<UUID> {
        _loadingFaviconIDs
    }

    /// Sync favicon from a live favorite tab's page to its linked bookmark.
    ///
    /// This ensures the bookmark's persisted favicon stays up-to-date with
    /// the tab's runtime favicon. Should be called after the tab finishes loading.
    ///
    /// - Parameter tab: Live favorite tab to sync favicon from
    func syncFaviconFromTab(_ tab: Tab) {
        guard tab.status == .liveFavorite,
              let bookmark = tab.linkedBookmark else {
            return
        }

        let page = tab.activePage
        let smallChanged = bookmark.faviconData != page.faviconData
        let largeChanged = bookmark.largeFaviconData != page.largeFaviconData

        // Only update if different to avoid unnecessary persistence churn
        if smallChanged || largeChanged {
            bookmark.faviconData = page.faviconData
            bookmark.largeFaviconData = page.largeFaviconData
            scheduleSave()
            Logger.debug("Synced favicon from tab to bookmark: \(bookmark.title)", category: Logger.data)
        }
    }

    /// Load missing favicons for shortcut favorites.
    ///
    /// Called during app startup to ensure shortcut favorites have favicons.
    /// Skips live favorites (they get favicons from their tabs via IconLoadingDelegateAdapter)
    /// and bookmarks that already have favicon data.
    ///
    /// This method is optimized for minimal MainActor usage:
    /// 1. Gather bookmark data on MainActor (required for SwiftData)
    /// 2. Fetch all favicons via FaviconCache off MainActor (network + caching)
    /// 3. Batch update bookmarks on MainActor (single hop back)
    ///
    /// This reduces thread hops from O(n × 5) per bookmark to O(2) total.
    func loadFaviconsForFavorites() {
        // Phase 1: Gather data on MainActor (required for SwiftData fetch)
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.isFavorite },
        )

        guard let favoriteBookmarks = try? _modelContext.fetch(descriptor) else {
            return
        }

        // Filter to shortcuts only - live favorites get favicons from their tabs
        let shortcutFavorites = favoriteBookmarks.filter { $0.favoriteMode == .shortcut }
        // Load if missing either small or large favicon
        let needsFavicon = shortcutFavorites.filter { $0.faviconData == nil || $0.largeFaviconData == nil }

        guard !needsFavicon.isEmpty else { return }

        // Capture Sendable data for off-MainActor work
        let bookmarkData: [(id: UUID, url: URL)] = needsFavicon.map { ($0.id, $0.url) }
        let faviconCache = _faviconCache

        Logger.info("Loading favicons for \(bookmarkData.count) shortcut favorites", category: Logger.data)

        // Phase 2 & 3: Fire-and-forget detached task
        // All fetching runs off MainActor, single hop back for batch update
        Task.detached(priority: .utility) { [weak self] in
            let results = await Self.fetchFaviconsInBatch(bookmarkData, using: faviconCache)

            // Phase 3: Batch update on MainActor (single hop)
            await self?.applyFaviconResults(results)
        }
    }

    /// Reload favicon for an existing bookmark.
    ///
    /// Useful for updating favicons that may have changed or failed to load initially.
    /// Tracks loading state via `_loadingFaviconIDs` for UI feedback.
    ///
    /// - Parameter bookmark: Bookmark to reload favicon for
    func reloadFavicon(for bookmark: Bookmark) {
        let bookmarkID = bookmark.id
        let url = bookmark.url

        // Clear existing favicons and cached data
        bookmark.faviconData = nil
        bookmark.largeFaviconData = nil

        // Track loading state
        _loadingFaviconIDs.insert(bookmarkID)

        let faviconCache = _faviconCache

        // Fetch off MainActor, hop back once for update
        Task.detached(priority: .utility) { [weak self] in
            // Clear cache for this host to force fresh fetch
            if let host = url.host {
                await faviconCache.clearFavicon(forHost: host)
            }

            // Fetch via FaviconCache (handles network + caching)
            let small = await faviconCache.faviconData(for: url, size: .small)
            let large = await faviconCache.faviconData(for: url, size: .large)

            // Single hop to MainActor for update and loading state cleanup
            await MainActor.run { [weak self] in
                self?.applyFaviconResult(id: bookmarkID, small: small, large: large)
                self?._loadingFaviconIDs.remove(bookmarkID)
            }
        }
    }

    /// Load favicon for a single bookmark.
    ///
    /// Fetches via FaviconCache (handles caching + network) and updates the bookmark.
    /// Designed to be called from a detached task context.
    ///
    /// - Parameters:
    ///   - id: The bookmark's ID
    ///   - url: The bookmark's URL to fetch favicon for
    nonisolated func loadFavicon(forID id: UUID, url: URL) async {
        let small = await _faviconCache.faviconData(for: url, size: .small)
        let large = await _faviconCache.faviconData(for: url, size: .large)

        await applyFaviconResult(id: id, small: small, large: large)
    }

    // MARK: - Private Helpers

    /// Fetch favicons for multiple bookmarks in batch, entirely off MainActor.
    ///
    /// Uses FaviconCache for all fetching, which handles:
    /// - Memory and disk caching
    /// - Deduplication of concurrent requests for same host
    /// - Network I/O on its own actor
    ///
    /// - Parameters:
    ///   - bookmarkData: Array of (id, url) tuples to fetch favicons for
    ///   - faviconCache: The FaviconCache actor to use
    /// - Returns: Array of (id, small, large) results
    private static func fetchFaviconsInBatch(
        _ bookmarkData: [(id: UUID, url: URL)],
        using faviconCache: FaviconCache,
    ) async -> [(id: UUID, small: Data?, large: Data?)] {
        await withTaskGroup(of: (id: UUID, small: Data?, large: Data?).self) { group in
            for (id, url) in bookmarkData {
                group.addTask {
                    // FaviconCache.faviconData handles cache check + network fetch + storage
                    // First call fetches both sizes, second is cache hit
                    let small = await faviconCache.faviconData(for: url, size: .small)
                    let large = await faviconCache.faviconData(for: url, size: .large)
                    return (id: id, small: small, large: large)
                }
            }

            var results: [(id: UUID, small: Data?, large: Data?)] = []
            results.reserveCapacity(bookmarkData.count)
            for await result in group {
                results.append(result)
            }
            return results
        }
    }

    /// Apply fetched favicon results to bookmarks in a single batch.
    ///
    /// This is the only MainActor hop after all favicon fetching completes.
    private func applyFaviconResults(_ results: [(id: UUID, small: Data?, large: Data?)]) {
        var updatedCount = 0

        for (id, small, large) in results {
            guard small != nil || large != nil else { continue }

            let descriptor = FetchDescriptor<Bookmark>(
                predicate: #Predicate { $0.id == id },
            )

            if let bookmark = try? _modelContext.fetch(descriptor).first {
                if let small { bookmark.faviconData = small }
                if let large { bookmark.largeFaviconData = large }
                updatedCount += 1
            }
        }

        if updatedCount > 0 {
            scheduleSave()
            Logger.debug("Updated favicons for \(updatedCount) bookmarks", category: Logger.data)
        }
    }

    /// Apply a single favicon result to a bookmark.
    private func applyFaviconResult(id: UUID, small: Data?, large: Data?) {
        guard small != nil || large != nil else { return }

        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.id == id },
        )

        if let bookmark = try? _modelContext.fetch(descriptor).first {
            if let small { bookmark.faviconData = small }
            if let large { bookmark.largeFaviconData = large }
            scheduleSave()
        }
    }
}
