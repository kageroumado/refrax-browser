import Foundation
import SwiftData
import SwiftUI

/// A saved webpage with optional favorites display and offline reading support.
///
/// `Bookmark` is the core model for Refrax's bookmarking system, representing any webpage
/// the user has chosen to save. Bookmarks can be:
///
/// - **Organized**: Placed in hierarchical folders up to 3 levels deep
/// - **Tagged**: Multiple tags for flexible categorization
/// - **Favorited**: Displayed as tiles in the sidebar for quick access
/// - **Space-Assigned**: Optionally tied to a specific browsing space
/// - **Offline-Ready**: Downloaded for offline reading (HTML or Reader mode)
///
/// ## Favorites System
///
/// When a bookmark is marked as a favorite (`isFavorite = true`), it appears in the sidebar
/// as a tile. Favorites have two modes:
///
/// - **Shortcut** (`.shortcut`): Clicking navigates the current tab to the URL
/// - **Live Tab** (`.liveTab`): Creates/activates a persistent pinned tab (like Arc)
///
/// ## Visit Tracking
///
/// Visit counts and last visited dates are automatically synchronized from ``HistoryManager``
/// to track bookmark usage patterns. This data powers AI-based recommendations.
///
/// ## Offline Reading
///
/// Bookmarks support two offline modes:
/// - **Full HTML**: Complete page with styling and images
/// - **Reader Mode**: Extracted article text only
///
/// Offline content is downloaded asynchronously and stored locally.
@Model
final class Bookmark {
    #Index<Bookmark>([\.isFavorite], [\.folderID], [\.spaceID])

    // MARK: - Identity

    /// Unique identifier for the bookmark
    @Attribute(.unique, .preserveValueOnDeletion)
    var id: UUID
    
    /// When the bookmark was first created
    var createdAt: Date
    
    /// Last time the bookmark properties were modified
    var lastModified: Date
    
    // MARK: - Content
    
    /// The URL of the bookmarked webpage
    var url: URL
    
    /// Display title for the bookmark (editable by user)
    var title: String
    
    /// Small favicon image data from the website (~64px).
    var faviconData: Data?

    /// Large favicon image data from the website (~180px).
    ///
    /// Used in favorites grid for high-resolution display. Falls back to
    /// ``faviconData`` if unavailable.
    var largeFaviconData: Data?

    /// Custom icon override (SF Symbol, emoji, or image)
    ///
    /// Stored as JSON string. Use ``customIcon`` computed property to access.
    var customIconJSON: String?

    /// Lowercased searchable text combining title, URL, and tags.
    ///
    /// This field enables efficient database-level text search without loading
    /// all bookmarks into memory. Updated whenever title, URL, or tags change.
    ///
    /// Format: `"{title} {host} {path} {tags...}"` (all lowercased)
    var searchableText: String

    // MARK: - Organization

    /// ID of parent folder (nil = root level)
    var folderID: UUID?
    
    /// Tags for flexible categorization
    ///
    /// Tags are stored as a flat array of strings. No separate Tag model needed.
    var tags: [String]
    
    /// Optional space assignment
    ///
    /// When set, bookmark can be filtered/organized by space. Nil means available in all spaces.
    var spaceID: UUID?
    
    // MARK: - Favorites Display

    /// Whether this bookmark appears in the sidebar favorites grid
    var isFavorite: Bool
    
    /// Interaction mode when favorited
    ///
    /// - `.shortcut`: Navigate current tab
    /// - `.liveTab`: Persistent tab
    var favoriteMode: FavoriteMode
    
    /// Position in favorites grid (encoded as row * 1000 + column)
    ///
    /// Use ``favoritePosition`` computed property for 2D coordinates.
    var favoritePositionValue: Int
    
    /// Hex color for favorite tile background (e.g., "#007AFF")
    var favoriteColor: String?
    
    // MARK: - Analytics
    
    /// Number of times this bookmark has been visited
    ///
    /// Synchronized from ``HistoryManager``. Updated periodically, not real-time.
    var visitCount: Int
    
    /// Last time this bookmark was opened
    ///
    /// Updated immediately when bookmark is clicked or when corresponding URL is navigated to.
    var lastVisited: Date?
    
    // MARK: - Offline Reading

    /// Current offline availability status
    var offlineStatus: OfflineStatus

    /// Local file path to offline content (when downloaded)
    var offlineDataPath: String?

    /// When the offline content was saved
    var offlineSavedAt: Date?

    /// Size of the offline content in bytes
    var offlineFileSize: Int64?
    
    // MARK: - Relationships

    /// Parent folder containing this bookmark
    @Relationship(inverse: \BookmarkFolder.bookmarks)
    var folder: BookmarkFolder?

    /// The live favorite tab linked to this bookmark.
    ///
    /// Set when a `.liveFavorite` tab is created for this bookmark.
    /// The inverse of ``Tab/linkedBookmark``.
    var linkedTab: Tab?
    
    // MARK: - Initialization
    
    /// Create a new bookmark with the specified properties.
    ///
    /// - Parameters:
    ///   - url: The webpage URL to bookmark
    ///   - title: Display title (defaults to URL host if not provided)
    ///   - folder: Optional parent folder
    ///   - isFavorite: Whether to show in sidebar favorites (default: false)
    ///   - favoriteMode: Interaction mode if favorited (default: .liveFavorite)
    ///   - favoritePosition: Grid position if favorited (default: 0,0)
    ///   - tags: Categorization tags (default: empty)
    ///   - spaceID: Optional space assignment (default: nil)
    init(
        url: URL,
        title: String? = nil,
        folder: BookmarkFolder? = nil,
        isFavorite: Bool = false,
        favoriteMode: FavoriteMode = .liveFavorite,
        favoritePosition: FavoritePosition = FavoritePosition(row: 0, col: 0),
        tags: [String] = [],
        spaceID: UUID? = nil,
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.lastModified = Date()

        self.url = url
        let resolvedTitle = title ?? url.host ?? "Untitled"
        self.title = resolvedTitle
        self.folder = folder
        self.folderID = folder?.id

        self.isFavorite = isFavorite
        self.favoriteMode = favoriteMode
        self.favoritePositionValue = favoritePosition.rawValue

        self.tags = tags
        self.spaceID = spaceID

        self.visitCount = 0
        self.offlineStatus = .notSaved
        self.searchableText = Self.buildSearchableText(title: resolvedTitle, url: url, tags: tags)
    }

    /// Builds the searchable text from title, URL, and tags.
    private static func buildSearchableText(title: String, url: URL, tags: [String]) -> String {
        var parts: [String] = []
        if !title.isEmpty {
            parts.append(title.lowercased())
        }
        if let host = url.host {
            parts.append(host.lowercased())
        }
        let path = url.path
        if !path.isEmpty, path != "/" {
            parts.append(path.lowercased())
        }
        for tag in tags {
            parts.append(tag.lowercased())
        }
        return parts.joined(separator: " ")
    }

    /// Rebuilds searchable text from current property values.
    private func rebuildSearchableText() {
        searchableText = Self.buildSearchableText(title: title, url: url, tags: tags)
    }
    
    // MARK: - Computed Properties
    
    /// Custom icon (decoded from JSON)
    var customIcon: BookmarkIcon? {
        get {
            BookmarkIcon.from(jsonString: customIconJSON)
        }
        set {
            customIconJSON = newValue?.jsonString
            lastModified = Date()
        }
    }
    
    /// 2D position in favorites grid
    var favoritePosition: FavoritePosition {
        get {
            favoritePositionValue.asFavoritePosition
        }
        set {
            favoritePositionValue = newValue.rawValue
            lastModified = Date()
        }
    }
    
    /// Display name for UI (title or cleaned URL if title is empty).
    ///
    /// Uses `URL.displayString` for consistent URL formatting across
    /// tabs, bookmarks, and drag overlays.
    var displayName: String {
        title.isEmpty ? url.displayString : title
    }
    
    /// Domain of the bookmarked URL
    var domain: String {
        url.host ?? url.absoluteString
    }
    
    /// Whether offline content is available for reading
    var isOfflineAvailable: Bool {
        offlineStatus == .availableHTML || offlineStatus == .availableReader
    }

    /// Whether offline content is currently being downloaded
    var isDownloadingOffline: Bool {
        offlineStatus == .downloadingHTML || offlineStatus == .downloadingReader
    }

    // MARK: - Modification Methods
    
    /// Update the bookmark's title
    ///
    /// - Parameter newTitle: New display title
    func updateTitle(_ newTitle: String) {
        title = newTitle
        rebuildSearchableText()
        lastModified = Date()
    }

    /// Update the bookmark's URL
    ///
    /// - Parameter newURL: New URL
    /// - Note: This resets favicon data and offline content
    func updateURL(_ newURL: URL) {
        url = newURL
        faviconData = nil
        offlineStatus = .notSaved
        offlineDataPath = nil
        rebuildSearchableText()
        lastModified = Date()
    }

    /// Add a tag to the bookmark
    ///
    /// - Parameter tag: Tag to add (case-insensitive, trimmed)
    func addTag(_ tag: String) {
        let normalizedTag = tag.trimmingCharacters(in: .whitespaces).lowercased()
        guard !normalizedTag.isEmpty, !tags.contains(normalizedTag) else { return }
        tags.append(normalizedTag)
        rebuildSearchableText()
        lastModified = Date()
    }

    /// Remove a tag from the bookmark
    ///
    /// - Parameter tag: Tag to remove
    func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag.lowercased() }
        rebuildSearchableText()
        lastModified = Date()
    }
    
    /// Record a visit to this bookmark
    ///
    /// Increments visit count and updates last visited date.
    func recordVisit() {
        visitCount += 1
        lastVisited = Date()
        lastModified = Date()
    }
    
    /// Update favicon from image data.
    ///
    /// - Parameters:
    ///   - small: Small favicon data (~64px) for lists.
    ///   - large: Large favicon data (~180px) for favorites grid. Optional.
    func updateFavicon(small: Data?, large: Data? = nil) {
        faviconData = small
        largeFaviconData = large
        lastModified = Date()
    }
}

// MARK: - Supporting Enums

/// Interaction mode for favorited bookmarks.
///
/// Determines what happens when a favorited bookmark is clicked in the sidebar grid.
enum FavoriteMode: String, Codable {
    /// Creates/activates a persistent global tab visible across all spaces.
    ///
    /// Live favorites are actual `Tab` instances stored in `BrowserState.liveFavoriteTabs`.
    /// They appear in the favorites grid as tiles and when clicked, switch to that tab
    /// while staying in the current space.
    ///
    /// This is the default mode for favorited bookmarks.
    case liveFavorite

    /// Opens URL in the current active tab (lightweight shortcut).
    ///
    /// Useful for folders of bookmarks where creating individual tabs isn't desired.
    /// Simply navigates the current tab to the bookmark's URL.
    case shortcut
}

/// Offline reading availability status
enum OfflineStatus: String, Codable {
    /// Not downloaded for offline reading
    case notSaved
    
    /// Currently downloading full HTML
    case downloadingHTML
    
    /// Currently downloading reader mode
    case downloadingReader
    
    /// Full HTML available offline
    case availableHTML
    
    /// Reader mode available offline
    case availableReader
    
    /// Download failed
    case failed
}
