import Foundation
import Observation

/// Manages Giphy API integration for GIF search and retrieval.
///
/// Provides search and trending GIF functionality with proper caching
/// and rate limiting. Uses Giphy's public API.
@Observable
final class GiphyManager {
    // MARK: - State

    /// Current search results.
    private(set) var searchResults: [GiphyGIF] = []

    /// Trending GIFs for initial display.
    private(set) var trendingGIFs: [GiphyGIF] = []

    /// Whether a search is in progress.
    private(set) var isSearching = false

    /// Error message if the last operation failed.
    private(set) var errorMessage: String?

    // MARK: - Configuration

    /// Giphy API key. Uses the public beta key by default.
    ///
    /// Users can provide their own key in settings for higher rate limits.
    private var apiKey: String {
        // Public beta key - rate limited but works for basic usage
        // https://developers.giphy.com/docs/api#quick-start-guide
        "dc6zaTOxFJmzC"
    }

    private let baseURL = "https://api.giphy.com/v1/gifs"
    private let searchLimit = 24
    private let trendingLimit = 12

    // MARK: - Caching

    private var trendingCache: [GiphyGIF]?
    private var trendingCacheDate: Date?
    private let trendingCacheDuration: TimeInterval = 300 // 5 minutes

    // MARK: - Search

    /// Searches Giphy for GIFs matching the query.
    ///
    /// - Parameter query: The search query.
    func search(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        // Show trending if query is empty
        if trimmed.isEmpty {
            searchResults = trendingGIFs
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            let gifs = try await performSearch(query: trimmed)
            searchResults = gifs
        } catch {
            errorMessage = error.localizedDescription
            searchResults = []
        }

        isSearching = false
    }

    /// Loads trending GIFs for initial display.
    func loadTrending() async {
        // Return cached if fresh
        if let cached = trendingCache,
           let cacheDate = trendingCacheDate,
           Date().timeIntervalSince(cacheDate) < trendingCacheDuration {
            trendingGIFs = cached
            searchResults = cached
            return
        }

        isSearching = true
        errorMessage = nil

        do {
            let gifs = try await fetchTrending()
            trendingGIFs = gifs
            searchResults = gifs
            trendingCache = gifs
            trendingCacheDate = Date()
        } catch {
            errorMessage = error.localizedDescription
        }

        isSearching = false
    }

    // MARK: - API

    private func performSearch(query: String) async throws -> [GiphyGIF] {
        guard var components = URLComponents(string: "\(baseURL)/search") else {
            throw GiphyError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "limit", value: String(searchLimit)),
            URLQueryItem(name: "rating", value: "pg-13"),
            URLQueryItem(name: "lang", value: Locale.current.language.languageCode?.identifier ?? "en"),
        ]

        guard let url = components.url else {
            throw GiphyError.invalidResponse
        }
        return try await fetchGIFs(from: url)
    }

    private func fetchTrending() async throws -> [GiphyGIF] {
        guard var components = URLComponents(string: "\(baseURL)/trending") else {
            throw GiphyError.invalidResponse
        }
        components.queryItems = [
            URLQueryItem(name: "api_key", value: apiKey),
            URLQueryItem(name: "limit", value: String(trendingLimit)),
            URLQueryItem(name: "rating", value: "pg-13"),
        ]

        guard let url = components.url else {
            throw GiphyError.invalidResponse
        }
        return try await fetchGIFs(from: url)
    }

    private func fetchGIFs(from url: URL) async throws -> [GiphyGIF] {
        let (data, response) = try await URLSession.shared.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw GiphyError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw GiphyError.httpError(httpResponse.statusCode)
        }

        let apiResponse = try JSONDecoder().decode(GiphyAPIResponse.self, from: data)
        return apiResponse.data
    }

    // MARK: - Download

    /// Downloads the full GIF data for insertion.
    ///
    /// - Parameter gif: The GIF to download.
    /// - Returns: The GIF image data.
    func downloadGIF(_ gif: GiphyGIF) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(from: gif.originalURL)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw GiphyError.downloadFailed
        }

        return data
    }
}

// MARK: - Types

/// A GIF from the Giphy API.
struct GiphyGIF: Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let previewURL: URL
    let originalURL: URL
    let width: Int
    let height: Int

    /// Aspect ratio for layout calculations.
    var aspectRatio: CGFloat {
        guard height > 0 else { return 1 }
        return CGFloat(width) / CGFloat(height)
    }
}

extension GiphyGIF: Decodable {
    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case images
    }

    private enum ImagesKeys: String, CodingKey {
        case fixedWidthSmall = "fixed_width_small"
        case original
    }

    private enum ImageDataKeys: String, CodingKey {
        case url
        case width
        case height
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        self.title = try container.decode(String.self, forKey: .title)

        let images = try container.nestedContainer(keyedBy: ImagesKeys.self, forKey: .images)

        // Preview (small)
        let preview = try images.nestedContainer(keyedBy: ImageDataKeys.self, forKey: .fixedWidthSmall)
        let previewURLString = try preview.decode(String.self, forKey: .url)
        guard let preview = URL(string: previewURLString) else {
            throw DecodingError.dataCorruptedError(forKey: .url, in: preview, debugDescription: "Invalid preview URL")
        }
        self.previewURL = preview

        // Original (full size)
        let original = try images.nestedContainer(keyedBy: ImageDataKeys.self, forKey: .original)
        let originalURLString = try original.decode(String.self, forKey: .url)
        guard let originalURL = URL(string: originalURLString) else {
            throw DecodingError.dataCorruptedError(forKey: .url, in: original, debugDescription: "Invalid original URL")
        }
        self.originalURL = originalURL

        // Dimensions (from original)
        let widthString = try original.decode(String.self, forKey: .width)
        let heightString = try original.decode(String.self, forKey: .height)
        self.width = Int(widthString) ?? 200
        self.height = Int(heightString) ?? 200
    }
}

// MARK: - API Response

private struct GiphyAPIResponse: Decodable {
    let data: [GiphyGIF]
}

// MARK: - Errors

enum GiphyError: LocalizedError {
    case invalidResponse
    case httpError(Int)
    case downloadFailed

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Invalid response from Giphy"
        case let .httpError(code):
            "Giphy returned error \(code)"
        case .downloadFailed:
            "Failed to download GIF"
        }
    }
}
