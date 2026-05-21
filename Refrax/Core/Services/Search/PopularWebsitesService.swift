import Foundation

/// Provides fast search over a curated list of popular websites.
///
/// The list is loaded lazily from a bundled JSON resource on first access.
/// Search text is pre-computed at load time for efficient prefix matching.
nonisolated enum PopularWebsitesService {
    /// Pre-computed entry with lowercase search text.
    struct SearchableEntry: Sendable {
        let website: PopularWebsite
        /// Pre-computed lowercase domain without TLD, plus lowercase name.
        let searchText: String
    }

    /// Lazily loaded and pre-processed website list.
    private static let entries: [SearchableEntry] = {
        guard let url = Bundle.main.url(forResource: "popular-websites", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let websites = try? JSONDecoder().decode([PopularWebsite].self, from: data)
        else {
            return []
        }

        return websites.map { website in
            let domainWithoutTLD = stripTLD(from: website.domain)
            let searchText = "\(domainWithoutTLD) \(website.name.lowercased())"
            return SearchableEntry(website: website, searchText: searchText)
        }
    }()

    /// Searches popular websites by prefix matching on domain and name.
    ///
    /// - Parameters:
    ///   - query: The search query to match.
    ///   - limit: Maximum number of results to return.
    /// - Returns: Matching websites, ordered by match quality.
    static func search(query: String, limit: Int = 5) -> [PopularWebsite] {
        guard !query.isEmpty else { return [] }

        let lowercased = query.lowercased()

        return entries
            .lazy
            .filter { $0.searchText.contains(lowercased) }
            .prefix(limit)
            .map(\.website)
    }

    /// Returns the total number of websites in the database.
    static var count: Int {
        entries.count
    }

    /// Strips the TLD from a domain for search purposes.
    ///
    /// "github.com" → "github", "docs.swift.org" → "docs.swift"
    private static func stripTLD(from domain: String) -> String {
        let parts = domain.lowercased().split(separator: ".")
        guard parts.count >= 2 else { return domain.lowercased() }

        // Common TLDs to strip
        let tlds: Set<String> = ["com", "org", "net", "io", "co", "tv", "app", "so", "ai"]
        if let last = parts.last, tlds.contains(String(last)) {
            return parts.dropLast().joined(separator: ".")
        }

        return domain.lowercased()
    }
}
