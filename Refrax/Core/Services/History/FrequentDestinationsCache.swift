import Foundation

/// In-memory cache of frequently visited domains for fast URL suggestions.
///
/// `FrequentDestinationsCache` aggregates visits by domain to provide quick,
/// relevant suggestions in the CommandLens. Unlike `HistoryEntry` which tracks
/// individual page visits, this cache groups by domain and ranks by frequency.
///
/// ## Performance
///
/// - Pre-computes lowercase search text for O(1) filtering
/// - Uses lazy evaluation with early termination in search
/// - Limits results to avoid excessive UI rendering
///
/// ## Usage
///
/// ```swift
/// let cache = FrequentDestinationsCache()
///
/// // Record visits from browsing
/// cache.recordVisit(url: url, title: pageTitle)
///
/// // Search for suggestions
/// let matches = cache.search(query: "git")
/// ```
///
/// ## Rebuild from History
///
/// On app launch, rebuild the cache from persisted history entries:
///
/// ```swift
/// cache.rebuild(from: historyManager.recentEntries(limit: 1000))
/// ```
final class FrequentDestinationsCache {
    // MARK: - Properties

    /// Maximum number of destinations to keep in cache
    private let maxCacheSize: Int

    /// Cache of frequent destinations, sorted by visit frequency
    private var destinations: [CachedDestination] = []

    /// Domain to index lookup for O(1) updates
    private var domainIndex: [String: Int] = [:]

    // MARK: - Initialization

    init(maxCacheSize: Int = 100) {
        self.maxCacheSize = maxCacheSize
    }

    // MARK: - Public Methods

    /// Add or update a destination in the cache.
    func recordVisit(url: URL, title: String?) {
        let domain = url.host ?? url.absoluteString

        if let index = domainIndex[domain] {
            destinations[index].visitCount += 1
            destinations[index].lastVisited = Date()
            if let title {
                destinations[index].updateDisplayTitle(title)
            }
        } else {
            let destination = CachedDestination(
                domain: domain,
                url: url,
                displayTitle: title ?? domain,
            )
            destinations.append(destination)
            domainIndex[domain] = destinations.count - 1
        }

        sortAndTrim()
    }
    
    /// Search for destinations matching a query.
    ///
    /// Uses pre-computed lowercase search text for efficient matching without
    /// repeated string allocations.
    ///
    /// - Parameter query: Search query to match against domain and title.
    /// - Returns: Matching destinations, limited to 20 results.
    func search(query: String) -> [CachedDestination] {
        guard !query.isEmpty else { return Array(destinations.prefix(10)) }

        let lowercasedQuery = query.lowercased()

        return destinations
            .lazy
            .filter { $0.searchText.contains(lowercasedQuery) }
            .prefix(20)
            .map(\.self)
    }
    
    /// Get top N most visited destinations
    func topDestinations(limit: Int = 10) -> [CachedDestination] {
        Array(destinations.prefix(limit))
    }
    
    /// Clear all cached destinations
    func clear() {
        destinations.removeAll()
        domainIndex.removeAll()
    }

    /// Returns base domains matching a query where the cached URL has a non-trivial path.
    ///
    /// This identifies domains where the user has visited subpages (e.g.,
    /// `github.com/user/repo`) but not the root domain (`github.com`).
    /// Used by ``BaseDomainSynthesisProvider`` to suggest root domain navigation.
    ///
    /// - Parameter query: Search query to match against domain names.
    /// - Returns: Tuples of (domain, URL) for matching domains with subpage visits only.
    func baseDomainSuggestions(query: String) -> [(domain: String, url: URL)] {
        guard !query.isEmpty else { return [] }

        let lowercased = query.lowercased()

        return destinations
            .lazy
            .filter { destination in
                let path = destination.url.path
                let hasSubpagePath = !path.isEmpty && path != "/"
                return hasSubpagePath && destination.domain.lowercased().contains(lowercased)
            }
            .prefix(5)
            .map { (domain: $0.domain, url: $0.url) }
    }

    /// Rebuild cache from history entries.
    ///
    /// Groups entries by domain and counts visits. Called on app launch to
    /// restore the cache from persisted history.
    func rebuild(from historyEntries: [HistoryEntry]) {
        let items = historyEntries.map { entry in
            (domain: entry.domain, url: entry.url, title: entry.title, visitedAt: entry.visitedAt)
        }
        rebuildFromItems(items)
    }

    /// Rebuild cache from transferable destination data.
    ///
    /// Used when rebuilding from a background actor where `@Model` objects
    /// can't be passed across actor boundaries.
    func rebuild(from data: [FrequentDestinationData]) {
        let items = data.map { entry in
            (domain: entry.domain, url: entry.url, title: entry.title, visitedAt: entry.visitedAt)
        }
        rebuildFromItems(items)
    }

    /// Core rebuild implementation shared by both public rebuild methods.
    private func rebuildFromItems(_ items: [(domain: String, url: URL, title: String?, visitedAt: Date)]) {
        destinations.removeAll()
        domainIndex.removeAll()

        // Group by domain and count entries (each entry is one visit)
        var domainMap: [String: (url: URL, title: String?, count: Int, lastVisited: Date)] = [:]

        for item in items {
            if let existing = domainMap[item.domain] {
                domainMap[item.domain] = (
                    url: existing.url,
                    title: item.title ?? existing.title,
                    count: existing.count + 1,
                    lastVisited: max(existing.lastVisited, item.visitedAt),
                )
            } else {
                domainMap[item.domain] = (
                    url: item.url,
                    title: item.title,
                    count: 1,
                    lastVisited: item.visitedAt,
                )
            }
        }

        // Convert to cached destinations
        destinations = domainMap.map { domain, info in
            CachedDestination(
                domain: domain,
                url: info.url,
                displayTitle: info.title ?? domain,
                visitCount: info.count,
                lastVisited: info.lastVisited,
            )
        }

        sortAndTrim()
    }

    // MARK: - Private Methods

    /// Sort destinations by visit frequency and trim to max size.
    ///
    /// After sorting, rebuilds the domain index since array positions change.
    private func sortAndTrim() {
        destinations.sort { lhs, rhs in
            if lhs.visitCount != rhs.visitCount {
                return lhs.visitCount > rhs.visitCount
            }
            return lhs.lastVisited > rhs.lastVisited
        }

        if destinations.count > maxCacheSize {
            destinations = Array(destinations.prefix(maxCacheSize))
        }

        rebuildDomainIndex()
    }

    /// Rebuilds the domain-to-index lookup after sorting.
    private func rebuildDomainIndex() {
        domainIndex.removeAll(keepingCapacity: true)
        for (index, destination) in destinations.enumerated() {
            domainIndex[destination.domain] = index
        }
    }
}

// MARK: - CachedDestination

/// A frequently visited destination stored in memory.
///
/// Pre-computes lowercase search text for efficient filtering without repeated
/// string allocations during search operations.
struct CachedDestination: Identifiable {
    let id = UUID()
    let domain: String
    let url: URL
    private(set) var displayTitle: String
    var visitCount: Int
    var lastVisited: Date

    /// Pre-computed lowercase search text for efficient filtering.
    private(set) var searchText: String

    init(
        domain: String,
        url: URL,
        displayTitle: String,
        visitCount: Int = 1,
        lastVisited: Date = Date(),
    ) {
        self.domain = domain
        self.url = url
        self.displayTitle = displayTitle
        self.visitCount = visitCount
        self.lastVisited = lastVisited
        self.searchText = Self.buildSearchText(domain: domain, displayTitle: displayTitle)
    }

    /// Updates display title and rebuilds search text.
    mutating func updateDisplayTitle(_ newTitle: String) {
        displayTitle = newTitle
        searchText = Self.buildSearchText(domain: domain, displayTitle: newTitle)
    }

    private static func buildSearchText(domain: String, displayTitle: String) -> String {
        "\(domain.lowercased()) \(displayTitle.lowercased())"
    }
}

// MARK: - Scoring

extension CachedDestination {
    /// Calculate a relevance score for ranking (frequency + recency)
    var relevanceScore: Double {
        let frequencyScore = Double(visitCount)
        let recencyScore = max(0, 1.0 - lastVisited.timeIntervalSinceNow / (86_400 * 30)) // Decay over 30 days
        return frequencyScore * 0.7 + recencyScore * 0.3
    }
}
