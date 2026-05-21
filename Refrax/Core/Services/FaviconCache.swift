import Foundation
import SwiftData

/// Thread-safe cache for website favicons with memory and disk persistence.
///
/// `FaviconCache` provides a two-tier caching system:
///
/// 1. **Memory cache**: Fast in-memory dictionary for immediate access
/// 2. **Disk cache**: SwiftData persistence for cross-session retention
///
/// ## Domain-Based Caching
///
/// Favicons are cached per domain (host), not per URL. This means all pages
/// on `apple.com` share the same cached favicon, reducing storage and network usage.
///
/// ## Cache Lifecycle
///
/// ```
/// Request favicon for URL
///        ↓
/// ┌─────────────────────────────────┐
/// │ Check memory cache              │ → Hit → Return immediately
/// └─────────────────────────────────┘
///        ↓ Miss
/// ┌─────────────────────────────────┐
/// │ Check disk cache (SwiftData)    │ → Hit → Populate memory, return
/// └─────────────────────────────────┘
///        ↓ Miss or stale
/// ┌─────────────────────────────────┐
/// │ Fetch from web                  │ → Save to both caches
/// └─────────────────────────────────┘
/// ```
///
/// ## Usage
///
/// ```swift
/// let cache = FaviconCache(modelContainer: container)
///
/// // Get cached favicon (may be nil)
/// let favicon = await cache.cachedFaviconData(forHost: "apple.com", size: .small)
///
/// // Get or fetch favicon
/// let data = await cache.faviconData(for: url, size: .small)
/// ```
///
/// ## Thread Safety
///
/// Uses `@ModelActor` to ensure the `ModelContext` is created and used on the
/// actor's dedicated serial executor. This keeps all SwiftData operations off
/// the main thread while maintaining thread safety.
///
/// ## Performance Optimization
///
/// Disk saves are debounced with 1 second delay and utility priority, allowing
/// the system to defer saves during resource pressure (e.g., heavy page loads).
@ModelActor
actor FaviconCache {
    // MARK: - Types

    /// In-memory cached favicon data.
    ///
    /// Stores only the raw data instead of SwiftData model objects to avoid
    /// issues with model contexts being deallocated while cached objects are
    /// still referenced.
    private struct CachedEntry: Sendable {
        let smallImageData: Data?
        let largeImageData: Data?
        let lastFetched: Date

        var isStale: Bool {
            Date().timeIntervalSince(lastFetched) > CachedFavicon.cacheValidityDuration
        }

        init(smallImageData: Data?, largeImageData: Data?, lastFetched: Date = Date()) {
            self.smallImageData = smallImageData
            self.largeImageData = largeImageData
            self.lastFetched = lastFetched
        }

        init(from cachedFavicon: CachedFavicon) {
            self.smallImageData = cachedFavicon.smallImageData
            self.largeImageData = cachedFavicon.largeImageData
            self.lastFetched = cachedFavicon.lastFetched
        }
    }

    // MARK: - Constants

    private enum Constants {
        /// Maximum age for stale entry cleanup (30 days).
        static let staleEntryMaxAge: TimeInterval = 30 * 24 * 60 * 60
    }

    // MARK: - Properties

    /// In-memory cache for fast access.
    ///
    /// Stores only data values, not SwiftData model objects, to prevent issues
    /// with model context lifecycle.
    private var memoryCache: [String: CachedEntry] = [:]

    /// Hosts currently being fetched (prevents duplicate requests).
    private var fetchingHosts: Set<String> = []

    // MARK: - Debounced Save

    /// Debounce task for batched saves.
    ///
    /// Multiple rapid save requests (e.g., fetching favicons for multiple tabs)
    /// are coalesced into a single save after the debounce delay.
    private var saveTask: Task<Void, any Error>?

    /// Delay before executing debounced save (1 second).
    ///
    /// Favicons are stored in memory immediately, so disk persistence can be
    /// deferred without affecting user experience.
    private let saveDebounceDelay: TimeInterval = 1.0

    // MARK: - Public API

    /// Gets cached favicon data for a URL, fetching if needed.
    ///
    /// This is the primary method for obtaining favicons. It checks the cache first,
    /// then fetches from the web if not cached or stale.
    ///
    /// - Parameters:
    ///   - url: The URL to get the favicon for.
    ///   - size: The size category needed.
    ///   - forceRefresh: If true, fetches even if cached.
    /// - Returns: Favicon image data, or nil if unavailable.
    func faviconData(
        for url: URL,
        size: CachedFavicon.SizeCategory,
        forceRefresh: Bool = false,
    ) async -> Data? {
        guard let host = url.host else { return nil }

        // Check cache first
        if !forceRefresh, let cached = getCachedEntry(forHost: host) {
            if !cached.isStale {
                return faviconData(from: cached, size: size)
            }
        }

        // Fetch from web
        await fetchAndCacheFavicon(for: url, host: host)

        // Return from cache
        if let cached = getCachedEntry(forHost: host) {
            return faviconData(from: cached, size: size)
        }

        return nil
    }

    /// Gets cached favicon data for a host and size without fetching.
    ///
    /// Returns nil if the cache entry is stale (older than 7 days).
    ///
    /// - Parameters:
    ///   - host: The domain to look up.
    ///   - size: The size category needed.
    /// - Returns: Cached favicon image data, or nil if not cached or stale.
    func cachedFaviconData(forHost host: String, size: CachedFavicon.SizeCategory) async -> Data? {
        guard let cached = getCachedEntry(forHost: host),
              !cached.isStale else {
            return nil
        }
        return faviconData(from: cached, size: size)
    }

    /// Prefetches favicons for multiple URLs in the background.
    ///
    /// Useful for preloading favicons for bookmarks or favorites.
    ///
    /// - Parameters:
    ///   - urls: URLs to prefetch favicons for.
    ///   - maxConcurrent: Maximum concurrent fetches (default 3).
    func prefetchFavicons(for urls: [URL], maxConcurrent: Int = 3) async {
        // Group by host to avoid duplicate fetches
        let uniqueHosts = Set(urls.compactMap(\.host))

        await withTaskGroup(of: Void.self) { group in
            var activeCount = 0

            for host in uniqueHosts {
                // Throttle concurrent fetches
                if activeCount >= maxConcurrent {
                    await group.next()
                    activeCount -= 1
                }

                // Skip if already cached and fresh
                if let cached = getCachedEntry(forHost: host), !cached.isStale {
                    continue
                }

                // Find a URL for this host
                guard let url = urls.first(where: { $0.host == host }) else { continue }

                group.addTask {
                    await self.fetchAndCacheFavicon(for: url, host: host)
                }
                activeCount += 1
            }

            // Wait for remaining tasks
            await group.waitForAll()
        }
    }

    /// Clears stale entries from the cache.
    ///
    /// Removes entries older than 30 days to prevent unbounded growth.
    func cleanupStaleEntries() async {
        let cutoffDate = Date().addingTimeInterval(-Constants.staleEntryMaxAge)

        do {
            let staleEntries = try modelContext.fetch(
                FetchDescriptor<CachedFavicon>(
                    predicate: #Predicate { $0.lastFetched < cutoffDate },
                ),
            )

            for entry in staleEntries {
                memoryCache.removeValue(forKey: entry.host)
                modelContext.delete(entry)
            }

            // Maintenance cleanup: use immediate save
            saveImmediately()
            Logger.debug("Cleaned \(staleEntries.count) stale favicon entries", category: Logger.data)
        } catch {
            Logger.error("Failed to cleanup stale favicons: \(error)", category: Logger.data)
        }
    }

    /// Clears all cached favicons.
    ///
    /// Use sparingly, as this forces re-fetching all favicons.
    func clearAll() async {
        memoryCache.removeAll()

        do {
            try modelContext.delete(model: CachedFavicon.self)
            // Critical user-triggered operation: use immediate save
            saveImmediately()
        } catch {
            Logger.error("Failed to clear favicon cache: \(error)", category: Logger.data)
        }
    }

    /// Clears cached favicon data for a specific host.
    ///
    /// - Parameter host: The domain to clear favicon data for.
    func clearFavicon(forHost host: String) async {
        memoryCache.removeValue(forKey: host)

        let predicate = #Predicate<CachedFavicon> { $0.host == host }

        do {
            let entries = try modelContext.fetch(FetchDescriptor<CachedFavicon>(predicate: predicate))
            for entry in entries {
                modelContext.delete(entry)
            }
            // User-triggered operation: use immediate save
            saveImmediately()
        } catch {
            Logger.error("Failed to clear favicon for \(host): \(error)", category: Logger.data)
        }
    }

    /// Updates cached favicon data for a host.
    ///
    /// - Parameters:
    ///   - host: The domain to update favicon for.
    ///   - small: Small favicon data (nil to keep existing or clear if both nil).
    ///   - large: Large favicon data (nil to keep existing or clear if both nil).
    func updateFavicon(forHost host: String, small: Data?, large: Data?) async {
        await saveFavicon(host: host, small: small, large: large)
    }

    // MARK: - Private Methods

    /// Gets a cached entry from memory, loading from disk if needed.
    private func getCachedEntry(forHost host: String) -> CachedEntry? {
        // Check memory cache first
        if let cached = memoryCache[host] {
            return cached
        }

        // Check disk cache
        let predicate = #Predicate<CachedFavicon> { $0.host == host }

        do {
            let results = try modelContext.fetch(FetchDescriptor<CachedFavicon>(predicate: predicate))
            if let cached = results.first {
                // Populate memory cache with data copy
                let entry = CachedEntry(from: cached)
                memoryCache[host] = entry
                return entry
            }
        } catch {
            Logger.error("Failed to fetch cached favicon: \(error)", category: Logger.data)
        }

        return nil
    }

    /// Fetches and caches a favicon from the web.
    private func fetchAndCacheFavicon(for url: URL, host: String) async {
        // Prevent duplicate concurrent fetches for same host
        guard !fetchingHosts.contains(host) else { return }
        fetchingHosts.insert(host)
        defer { fetchingHosts.remove(host) }

        do {
            // Fetch both sizes using FaviconService (no WebPage available)
            let (small, large) = try await FaviconService.fetchFavicons(for: url)

            // Save to cache
            await saveFavicon(host: host, small: small, large: large)
        } catch {
            Logger.debug("Favicon fetch failed for \(host): \(error)", category: Logger.data)

            // Cache negative result to avoid repeated failures
            await saveFavicon(host: host, small: nil, large: nil)
        }
    }

    /// Saves favicon data to both memory and disk cache.
    ///
    /// Memory cache is updated immediately for instant access.
    /// Disk persistence is debounced to batch multiple rapid saves.
    private func saveFavicon(host: String, small: Data?, large: Data?) async {
        // Update memory cache immediately for fast access
        memoryCache[host] = CachedEntry(smallImageData: small, largeImageData: large)

        // Check if entry exists in disk cache
        let predicate = #Predicate<CachedFavicon> { $0.host == host }
        let existingEntries = try? modelContext.fetch(FetchDescriptor<CachedFavicon>(predicate: predicate))

        if let existing = existingEntries?.first {
            existing.update(small: small, large: large)
        } else {
            let entry = CachedFavicon(host: host, smallImageData: small, largeImageData: large)
            modelContext.insert(entry)
        }

        // Hot path: use debounced save since favicon fetches happen frequently
        scheduleSave()
    }

    /// Extracts the appropriate size data from a cached entry.
    private func faviconData(from cached: CachedEntry, size: CachedFavicon.SizeCategory) -> Data? {
        switch size {
        case .small:
            // Small size: prefer small, fall back to large
            cached.smallImageData ?? cached.largeImageData
        case .large:
            // Large size: prefer large, fall back to small
            cached.largeImageData ?? cached.smallImageData
        }
    }

    // MARK: - Persistence

    /// Schedules a debounced save with utility priority.
    ///
    /// Multiple calls within the debounce window are coalesced into a single
    /// save operation. This is critical for performance when fetching favicons
    /// for multiple tabs simultaneously (e.g., session restore, bookmark folder).
    ///
    /// Uses `Task.priority(.utility)` so the system can defer the save when
    /// under resource pressure.
    ///
    /// - Note: The `@ModelActor` ensures all SwiftData operations run on the
    ///   actor's dedicated serial executor, keeping disk I/O off the main thread.
    private func scheduleSave() {
        saveTask?.cancel()
        let delay = saveDebounceDelay
        saveTask = Task(priority: .utility) { [weak self] in
            try await Task.sleep(for: .seconds(delay))
            // Re-enter actor context for modelContext access
            await self?.performSave()
        }
    }

    /// Actually performs the save operation.
    private func performSave() {
        guard modelContext.hasChanges else { return }

        do {
            try modelContext.save()
        } catch {
            Logger.error("Failed to save favicon cache: \(error)", category: Logger.data)
        }
    }

    /// Performs an immediate save, cancelling any pending debounced save.
    ///
    /// Use for critical operations where data loss is unacceptable:
    /// - Clear all favicons
    /// - Clear specific favicon (user action)
    /// - Cleanup stale entries
    private func saveImmediately() {
        saveTask?.cancel()
        saveTask = nil

        guard modelContext.hasChanges else { return }

        do {
            try modelContext.save()
        } catch {
            Logger.error("Failed to save favicon cache immediately: \(error)", category: Logger.data)
        }
    }
}
