import Foundation
import SwiftData

/// A single page visit in the browser's history.
///
/// Each `HistoryEntry` represents exactly one visit to a URL. Multiple visits to the same URL
/// create multiple entries, which can be grouped via queries when needed (by domain, by URL, etc.).
///
/// ## Overview
///
/// History entries form a tree structure where each entry can have:
/// - One parent (the page that led to this one via link or navigation)
/// - Multiple children (pages opened from this entry)
/// - No parent (root navigation - typed URL, bookmark, etc.)
///
/// ## Tree Structure Example
///
/// ```
/// Entry A (root: typed google.com)
///   ├─ Entry B (clicked search result)
///   │   └─ Entry C (followed link)
///   └─ Entry D (opened in background)
/// ```
///
/// ## Usage
///
/// Create entries through `HistoryManager.recordNavigation()`:
///
/// ```swift
/// let entry = historyManager.recordNavigation(
///     url: url,
///     title: "Page Title",
///     tabID: tab.id,
///     spaceID: space.id,
///     parentEntry: previousEntry
/// )
/// ```
///
/// ## Temporal Tracking
///
/// Each entry tracks:
/// - `visitedAt`: When the page was visited (immutable)
/// - `closedAt`: When user navigated away (nil if still open)
/// - `timeSpent`: Accumulated viewing time in seconds
///
/// ## Space Association
///
/// The `spaceID` field associates entries with workspaces for:
/// - Color-coding in graph visualizations
/// - Filtering history by workspace
/// - Understanding browsing context
///
/// - Important: Private mode browsing is never recorded. `HistoryManager` checks
///   the space's `DataStoreMode` and skips recording entirely for private spaces.
@Model
final class HistoryEntry {
    // Primary indexes for common query patterns:
    // - visitedAt: Date range queries
    // - domain: Per-domain history views
    // - closedAt: Orphan cleanup on startup
    // - (domain, visitedAt): Per-domain date-filtered queries
    #Index<HistoryEntry>(
        [\.visitedAt],
        [\.domain],
        [\.closedAt],
        [\.domain, \.visitedAt],
    )

    // MARK: - Primary Data

    /// Unique identifier for this history entry.
    @Attribute(.unique, .preserveValueOnDeletion)
    var id: UUID
    
    /// The URL that was visited.
    ///
    /// URLs are normalized (www. prefix removed, trailing slash cleaned) for deduplication.
    var url: URL
    
    /// Page title extracted from the HTML `<title>` tag.
    ///
    /// May be `nil` initially and updated after page load completes.
    /// Updated via ``updateTitle(_:)``.
    var title: String?
    
    /// The domain extracted from the URL for fast filtering.
    ///
    /// Used for:
    /// - Domain-based color coding in graph view
    /// - Grouping related pages
    /// - Quick domain filtering
    ///
    /// Example: `"developer.apple.com"` for `https://developer.apple.com/documentation/`
    var domain: String

    /// Lowercased searchable text combining title, domain, and path.
    ///
    /// This field enables efficient database-level text search without loading
    /// all entries into memory. Updated whenever title changes.
    ///
    /// Format: `"{title} {domain} {path}"` (all lowercased)
    ///
    /// - Note: SwiftData can't search within URL.absoluteString, so we maintain
    ///   this denormalized field for search queries.
    @Attribute(.spotlight)
    var searchableText: String
    
    // MARK: - Temporal Metadata

    /// When this page was visited (immutable).
    ///
    /// This timestamp never changes after creation. Each visit creates a new entry.
    var visitedAt: Date

    /// When the page was closed or navigated away from.
    ///
    /// - `nil`: Page is still open
    /// - Non-nil: User closed tab or navigated elsewhere
    ///
    /// Set via ``markClosed(timeSpent:)``.
    var closedAt: Date?

    /// Last time this page was confirmed to be actively viewed.
    ///
    /// Updated every 5 seconds while the page is actively viewed. "Active" means:
    /// - The app is frontmost (not in the background)
    /// - The system is not sleeping
    /// - The page's window is key
    /// - The page is visible on screen
    ///
    /// Used as a fallback for `closedAt` if the app crashes or is force-quit while
    /// the page is still open.
    ///
    /// When calculating time spent for entries with `closedAt == nil`, use this
    /// value instead of extending to current time indefinitely.
    var lastSeenAt: Date?

    /// Total time spent on this page in seconds (accumulated).
    ///
    /// Tracks active viewing time, gated by `HistoryActivityManager` to ensure
    /// time is only accumulated when:
    /// - The app is active (frontmost)
    /// - The system is not sleeping
    /// - The page's window is key
    ///
    /// Incremented via:
    /// - ``addTimeSpent(_:)`` - Periodic updates (every 15 seconds while active)
    /// - ``markClosed(timeSpent:)`` - Final time on close/navigation
    var timeSpent: TimeInterval
    
    // MARK: - Tree Structure
    
    /// The history entry that led to this one.
    ///
    /// - `nil`: Root navigation (typed URL, bookmark, new tab page)
    /// - Non-nil: User clicked a link or was redirected from parent page
    ///
    /// ## Navigation Types
    ///
    /// **Root Navigation** (parent = nil):
    /// - User typed URL in address bar
    /// - Clicked bookmark
    /// - Used search engine
    /// - Opened new tab page
    ///
    /// **Child Navigation** (parent set):
    /// - Clicked link on parent page
    /// - Followed redirect chain
    /// - JavaScript navigation
    @Relationship(deleteRule: .nullify, inverse: \HistoryEntry.children)
    var parent: HistoryEntry?
    
    /// Child entries that were navigated to from this page.
    ///
    /// Multiple children occur when:
    /// - User opens multiple links in background tabs
    /// - Page has multiple redirects
    /// - User middle-clicks several links
    ///
    /// Uses `.nullify` delete rule so deleting a parent doesn't delete child visits.
    @Relationship(deleteRule: .nullify)
    var children: [HistoryEntry]
    
    // MARK: - Context
    
    /// The workspace (Space) this entry was created in.
    ///
    /// Used for:
    /// - Color-coding entries in graph view
    /// - Filtering history by workspace
    /// - Understanding browsing context
    ///
    /// - Note: May be `nil` for entries created before Space support was added
    var spaceID: UUID?

    /// Whether this entry was imported from another browser.
    ///
    /// Imported entries have limited functionality compared to native entries:
    /// - No parent/child navigation tree (source browsers don't provide this)
    /// - Time spent tracking is unavailable
    /// - Some metadata fields may be nil
    ///
    /// The UI can use this flag to explain these limitations to users.
    var isImported: Bool

    // MARK: - Navigation Metadata

    /// The tab ID this entry is associated with.
    ///
    /// Used for:
    /// - Correlating history with active tabs
    /// - Tracking which tab generated this entry
    /// - Closing entries when tabs close
    var tabID: UUID?

    /// Whether this page failed to load.
    ///
    /// Set to `true` when navigation fails due to network errors, DNS failures,
    /// or other loading issues. Used to display failed pages differently in the UI.
    var failedToLoad: Bool

    /// The HTTP status code if available.
    ///
    /// Examples:
    /// - `200` - OK
    /// - `404` - Not Found
    /// - `500` - Server Error
    /// - `0` - Network unreachable (pseudo-code)
    /// - `408` - Timeout (pseudo-code)
    var httpStatusCode: Int?

    /// Favicon URL if available.
    ///
    /// Typically `https://domain.com/favicon.ico` but can be specified in HTML.
    var faviconURL: URL?
    
    // MARK: - Initialization

    /// Creates a new history entry for a page visit.
    ///
    /// - Parameters:
    ///   - url: The URL being visited
    ///   - title: Optional page title (can be updated later)
    ///   - parent: The entry that led to this navigation (nil for root)
    ///   - spaceID: The workspace this entry belongs to
    ///   - tabID: The tab ID for correlation
    ///   - isImported: Whether this entry was imported from another browser
    init(
        url: URL,
        title: String? = nil,
        parent: HistoryEntry? = nil,
        spaceID: UUID? = nil,
        tabID: UUID? = nil,
        isImported: Bool = false,
    ) {
        self.id = UUID()
        self.url = url
        self.title = title
        self.domain = url.host ?? url.absoluteString
        self.searchableText = Self.buildSearchableText(title: title, url: url)
        self.visitedAt = Date()
        self.closedAt = nil
        self.lastSeenAt = Date()
        self.timeSpent = 0
        self.parent = parent
        self.children = []
        self.spaceID = spaceID
        self.isImported = isImported
        self.tabID = tabID
        self.failedToLoad = false
        self.httpStatusCode = nil
        self.faviconURL = nil
    }

    /// Creates a history entry from imported data.
    ///
    /// Preserves original timestamps from the source browser and marks the entry as imported.
    /// Creates one entry per unique URL, regardless of the source browser's visit count.
    ///
    /// - Note: Browsers like Safari and Chrome track visit counts, but since we don't have
    ///   individual timestamps for each visit, we create a single entry per URL. The
    ///   `firstVisited` becomes `visitedAt` and `lastVisited` becomes `closedAt`.
    ///
    /// - Parameter imported: The imported history entry data.
    convenience init(from imported: ImportedHistoryEntry) {
        self.init(
            url: imported.url,
            title: imported.title,
            isImported: true,
        )
        self.visitedAt = imported.firstVisited ?? imported.lastVisited
        self.closedAt = imported.lastVisited
    }

    /// Builds the searchable text from title and URL.
    private static func buildSearchableText(title: String?, url: URL) -> String {
        var parts: [String] = []
        if let title, !title.isEmpty {
            parts.append(title.lowercased())
        }
        if let host = url.host {
            parts.append(host.lowercased())
        }
        let path = url.path
        if !path.isEmpty, path != "/" {
            parts.append(path.lowercased())
        }
        return parts.joined(separator: " ")
    }
    
    // MARK: - Update Methods

    /// Updates the page title.
    ///
    /// Typically called after page load completes and title is extracted from HTML.
    /// Also updates the searchable text index.
    ///
    /// - Parameter newTitle: The new page title, or nil to clear
    func updateTitle(_ newTitle: String?) {
        title = newTitle
        searchableText = Self.buildSearchableText(title: newTitle, url: url)
    }

    /// Marks the page as closed and records final time spent.
    ///
    /// Call this when:
    /// - User closes the tab
    /// - User navigates to a different URL
    /// - Tab is destroyed
    ///
    /// - Parameter timeSpent: Final time spent in seconds
    ///
    /// - Important: After calling this, the entry should no longer be updated
    func markClosed(timeSpent: TimeInterval) {
        closedAt = Date()
        self.timeSpent += timeSpent
    }

    /// Adds time spent on this page (for periodic tracking).
    ///
    /// Called periodically (every 30 seconds) while the page is active.
    ///
    /// - Parameter duration: Time interval in seconds to add
    func addTimeSpent(_ duration: TimeInterval) {
        timeSpent += duration
    }

    /// Updates the last seen timestamp.
    ///
    /// Called periodically while the page is actively viewed. This acts as a
    /// checkpoint for crash recovery - if the app terminates unexpectedly,
    /// this value is used instead of extending time to current moment.
    func updateLastSeen() {
        lastSeenAt = Date()
    }

    /// Marks the page as failed to load.
    ///
    /// - Parameters:
    ///   - statusCode: Optional HTTP status code or pseudo-code for the error
    func markFailed(statusCode: Int? = nil) {
        failedToLoad = true
        httpStatusCode = statusCode
    }
}

// MARK: - Computed Properties

extension HistoryEntry {
    /// Whether this is a root navigation (no parent).
    ///
    /// Root navigations include:
    /// - Typed URLs
    /// - Bookmarks
    /// - New tab page links
    /// - Search engine results
    var isRoot: Bool {
        parent == nil
    }

    /// The display URL (formatted for UI).
    ///
    /// Returns the full URL string suitable for display in lists or details.
    var displayURL: String {
        url.absoluteString
    }

    /// Whether this entry is still active (not closed).
    ///
    /// Active entries have `closedAt == nil` and may still be updated.
    var isActive: Bool {
        closedAt == nil
    }

    /// Time elapsed since this visit.
    ///
    /// Useful for:
    /// - Sorting by recency
    /// - Filtering old entries
    /// - Age-based styling in UI
    var age: TimeInterval {
        Date().timeIntervalSince(visitedAt)
    }
}
