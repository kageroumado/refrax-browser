import Foundation
import Observation

/// Service for managing the extension gallery.
///
/// Provides curated extension listings and web store integration.
/// For MVP, uses bundled JSON data. Future versions may fetch from a server.
@Observable
final class ExtensionGalleryService {
    // MARK: - Properties

    /// Cached gallery data.
    private var cachedGallery: GalleryResponse?

    /// Last time we checked for updates.
    private var lastFetchDate: Date?

    /// Cache duration (24 hours).
    private let cacheDuration: TimeInterval = 86_400

    // MARK: - Public API

    /// Fetches the extension gallery.
    ///
    /// Returns cached data if available and not stale, otherwise loads fresh data.
    ///
    /// - Returns: The gallery response with all extensions.
    func fetchGallery() throws -> GalleryResponse {
        // Return cached if still valid
        if let cached = cachedGallery,
           let fetchDate = lastFetchDate,
           Date().timeIntervalSince(fetchDate) < cacheDuration {
            return cached
        }

        // Load from bundled JSON for MVP
        let gallery = try loadBundledGallery()
        cachedGallery = gallery
        lastFetchDate = Date()

        return gallery
    }

    /// Gets extensions in a specific category.
    ///
    /// - Parameter category: The category to filter by.
    /// - Returns: Extensions in that category, sorted by popularity.
    func extensions(in category: ExtensionCategory) throws -> [GalleryExtension] {
        let gallery = try fetchGallery()
        return gallery.extensions
            .filter { $0.category == category }
            .sorted { $0.popularityRank < $1.popularityRank }
    }

    /// Gets featured/recommended extensions.
    ///
    /// - Returns: Featured extensions across all categories.
    func featuredExtensions() throws -> [GalleryExtension] {
        let gallery = try fetchGallery()
        return gallery.extensions
            .filter(\.isFeatured)
            .sorted { $0.popularityRank < $1.popularityRank }
    }

    /// Searches for extensions by query.
    ///
    /// - Parameter query: Search query to match against name, description, and tags.
    /// - Returns: Matching extensions, sorted by relevance.
    func search(query: String) throws -> [GalleryExtension] {
        let gallery = try fetchGallery()
        let lowercasedQuery = query.lowercased()

        return gallery.extensions
            .filter { ext in
                ext.name.lowercased().contains(lowercasedQuery) ||
                    ext.description.lowercased().contains(lowercasedQuery) ||
                    ext.tags.contains { $0.lowercased().contains(lowercasedQuery) }
            }
            .sorted { $0.popularityRank < $1.popularityRank }
    }

    /// Gets categories that have extensions.
    ///
    /// - Returns: Categories with at least one extension, sorted by extension count.
    func availableCategories() throws -> [ExtensionCategory] {
        let gallery = try fetchGallery()
        let categoryCounts = Dictionary(grouping: gallery.extensions, by: \.category)
            .mapValues(\.count)

        return ExtensionCategory.allCases
            .filter { categoryCounts[$0, default: 0] > 0 }
            .sorted { categoryCounts[$0, default: 0] > categoryCounts[$1, default: 0] }
    }

    /// Gets the download URL for an extension.
    ///
    /// - Parameter extension_: The gallery extension to get download URL for.
    /// - Returns: URL to download the extension, or nil if not available.
    func downloadURL(for extension_: GalleryExtension) -> URL? {
        switch extension_.source {
        case let .chrome(extensionID):
            // Chrome Web Store CRX download URL
            // Note: Direct CRX downloads from Chrome Web Store require special handling
            // Users should be directed to the store page for now
            URL(string: "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=120.0&acceptformat=crx2,crx3&x=id%3D\(extensionID)%26uc")

        case let .firefox(extensionID):
            // Firefox Add-ons has a public API for downloads
            URL(string: "https://addons.mozilla.org/firefox/downloads/latest/\(extensionID)/")

        case let .directDownload(url):
            url
        }
    }

    /// Forces a refresh of the gallery data.
    func refresh() throws {
        cachedGallery = nil
        lastFetchDate = nil
        _ = try fetchGallery()
    }

    // MARK: - Private

    /// Loads the bundled gallery JSON.
    private func loadBundledGallery() throws -> GalleryResponse {
        guard let url = Bundle.main.url(forResource: "curated-extensions", withExtension: "json") else {
            // Return empty gallery if file not found
            Logger.warning("curated-extensions.json not found, returning empty gallery", category: Logger.extensions)
            return GalleryResponse(
                version: 1,
                lastUpdated: Date(),
                extensions: [],
            )
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(GalleryResponse.self, from: data)
    }
}

// MARK: - Gallery Errors

/// Errors that can occur with gallery operations.
enum GalleryError: Error, LocalizedError {
    /// Failed to load the gallery data.
    case loadFailed(any Error)

    /// Failed to download an extension.
    case downloadFailed(any Error)

    /// Extension not found in gallery.
    case extensionNotFound

    var errorDescription: String? {
        switch self {
        case let .loadFailed(error):
            "Failed to load extension gallery: \(error.localizedDescription)"
        case let .downloadFailed(error):
            "Failed to download extension: \(error.localizedDescription)"
        case .extensionNotFound:
            "Extension not found in gallery"
        }
    }
}
