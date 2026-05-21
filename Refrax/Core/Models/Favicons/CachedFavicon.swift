import Foundation
import SwiftData

/// A cached favicon for a website domain.
///
/// `CachedFavicon` stores favicon images at multiple resolutions to optimize display
/// across different UI contexts. Favicons are cached per domain (host) rather than
/// per URL, since most sites use the same favicon across all pages.
///
/// ## Size Categories
///
/// Two sizes are stored to balance quality and storage:
///
/// - **Small (64px)**: Used in tab bars, address bars, history lists (32pt @ 2x retina)
/// - **Large (180px)**: Used in favorites grid, bookmarks, new tab page (Apple Touch Icon size)
///
/// ## Cache Lifecycle
///
/// Favicons are refreshed after ``CachedFavicon/cacheValidityDuration`` (7 days).
/// The ``isStale`` property indicates when a refresh is recommended.
///
/// ## Usage
///
/// ```swift
/// // Fetch from cache
/// let favicon = faviconCache.favicon(for: "apple.com")
///
/// // Get appropriate size
/// let tabIcon = favicon?.smallImage  // For tab bar
/// let favoriteIcon = favicon?.largeImage  // For favorites
/// ```
@Model
final class CachedFavicon {
    #Index<CachedFavicon>([\.host], [\.lastFetched])

    // MARK: - Properties

    /// The domain this favicon belongs to.
    ///
    /// Stored as the URL host (e.g., "apple.com", "developer.apple.com").
    /// Subdomains are treated as separate entries since they may have different favicons.
    @Attribute(.unique)
    var host: String

    /// Small favicon image data (64px for 32pt @ 2x retina).
    ///
    /// Optimized for tab bars, breadcrumbs, and compact UI elements.
    /// May be nil if the site has no favicon or extraction failed.
    var smallImageData: Data?

    /// Large favicon image data (180px, Apple Touch Icon size).
    ///
    /// Optimized for favorites grid, bookmarks panel, and prominent displays.
    /// Falls back to ``smallImageData`` if no high-resolution icon is available.
    /// Only populated when icons >= 64px are found; nil if only small icons exist.
    var largeImageData: Data?

    /// When this favicon was last fetched from the web.
    ///
    /// Used for cache invalidation. Favicons older than ``cacheValidityDuration``
    /// should be refreshed on next access.
    var lastFetched: Date

    // MARK: - Constants

    /// How long a cached favicon is considered fresh.
    ///
    /// After this duration, the favicon will be re-fetched on next navigation
    /// to that domain. Default is 7 days.
    static let cacheValidityDuration: TimeInterval = 7 * 24 * 60 * 60

    /// Target size for small favicons (32pt @ 2x retina = 64px).
    static let smallSize: CGFloat = 64

    /// Target size for large favicons (Apple Touch Icon size).
    static let largeSize: CGFloat = 180

    // MARK: - Initialization

    /// Creates a new cached favicon entry.
    ///
    /// - Parameters:
    ///   - host: The domain for this favicon.
    ///   - smallImageData: Small (64px) favicon data for tabs/lists.
    ///   - largeImageData: Large (180px) favicon data for favorites grid.
    init(
        host: String,
        smallImageData: Data? = nil,
        largeImageData: Data? = nil,
    ) {
        self.host = host
        self.smallImageData = smallImageData
        self.largeImageData = largeImageData
        self.lastFetched = Date()
    }

    // MARK: - Computed Properties

    /// Whether this cached favicon should be refreshed.
    ///
    /// Returns `true` if the favicon hasn't been fetched in the last
    /// ``cacheValidityDuration`` (7 days).
    var isStale: Bool {
        Date().timeIntervalSince(lastFetched) > Self.cacheValidityDuration
    }

    /// Whether this entry has any favicon data.
    var hasFavicon: Bool {
        smallImageData != nil || largeImageData != nil
    }

    // MARK: - Update Methods

    /// Updates the cached favicon data and refresh timestamp.
    ///
    /// - Parameters:
    ///   - small: New small favicon data (nil to keep existing).
    ///   - large: New large favicon data (nil to keep existing).
    func update(small: Data?, large: Data?) {
        if let small {
            smallImageData = small
        }
        if let large {
            largeImageData = large
        }
        lastFetched = Date()
    }

    /// Clears all favicon data from this entry.
    ///
    /// Use this when forcing a refresh to ensure the old data is removed
    /// before fetching new data.
    func clearData() {
        smallImageData = nil
        largeImageData = nil
    }
}

// MARK: - Size Category

extension CachedFavicon {
    /// Favicon size categories for different UI contexts.
    enum SizeCategory: Sendable {
        /// Small favicon for tabs, lists (64px for 32pt @ 2x retina)
        case small

        /// Large favicon for favorites grid (180px, Apple Touch Icon size)
        case large

        /// Target pixel size for this category.
        var targetSize: CGFloat {
            switch self {
            case .small: CachedFavicon.smallSize
            case .large: CachedFavicon.largeSize
            }
        }
    }
}
