import Foundation
import SwiftData

/// A browser tab containing one or more web pages.
///
/// Tabs are the primary unit of content organization in Refrax. Each tab belongs
/// to a ``Space`` (workspace) and can display one or more ``TabPage`` instances
/// in various layouts.
///
/// ## Overview
///
/// ```
/// Space
///  └─ Tab
///      ├─ TabPage (primary)    ←→ WebPage (runtime)
///      └─ TabPage (secondary)  ←→ WebPage (runtime)
/// ```
///
/// Tabs store persistent state (URL, title, organization). Runtime state like
/// loading progress lives in ``WebPage``, created on-demand by ``TabManager``.
///
/// ## Single vs Multi-Page Tabs
///
/// Most tabs display a single page. Split-view tabs show 2-4 pages side-by-side
/// for research or comparison:
///
/// ```swift
/// // Single page (default)
/// let tab = Tab(space: space, url: articleURL)
///
/// // Add second page for split view
/// let secondPage = TabPage(url: referenceURL, layoutPosition: .topRight)
/// tabManager.addPageToTab(tab, url: referenceURL, at: .topRight)
/// ```
///
/// ## Tab Status
///
/// Tabs have three organizational states via ``TabStatus``:
///
/// | Status | Description |
/// |--------|-------------|
/// | **Regular** | Standard tab in a space, subject to cleanup |
/// | **Pinned** | Stays at top, never auto-closed |
/// | **Live Favorite** | Global tab in favorites grid, visible across all spaces |
///
/// Live favorite tabs are linked to a ``Bookmark`` via ``linkedBookmark`` and
/// always use global website data storage.
///
/// ## Organization
///
/// Additional organizational features:
///
/// | Feature | Purpose |
/// |---------|---------|
/// | **Groups** | Color-coded project organization |
/// | **Reference** | Side panel for persistent reference |
///
/// ## Persistence
///
/// Tabs persist via SwiftData with their parent ``Space``. On restart:
/// - URLs, titles, and organization restore fully
/// - Navigation history (back/forward) resets
/// - Active sessions recreate on demand
///
/// ## Lifecycle
///
/// - **Creation**: ``TabManager/createTab(url:status:makeActive:)``
/// - **Activation**: ``TabManager/setActiveTab(_:)`` creates session
/// - **Closure**: ``TabManager/closeTab(_:)`` adds to recently closed
/// - **Deletion**: Cascade-deletes all child ``TabPage`` instances
///
/// - Important: Modify tabs through ``TabManager`` to ensure proper session
///   lifecycle and persistence.
@Model
final class Tab {
    #Index<Tab>([\.lastAccessed])

    // MARK: - Identity

    /// Unique identifier for this tab.
    @Attribute(.unique, .preserveValueOnDeletion)
    var id: UUID

    /// The space (workspace) containing this tab.
    ///
    /// Tabs belong to exactly one space.
    ///
    /// - Note: Live favorite tabs have `space == nil` since they exist globally.
    var space: Space?
    
    // MARK: - Content
    
    /// Web pages displayed in this tab.
    ///
    /// | Count | Layout |
    /// |-------|--------|
    /// | 1 | Standard single-page tab |
    /// | 2 | Horizontal or vertical split |
    /// | 3-4 | Grid layout |
    ///
    /// Access ``activePage`` for the main page, ``sortedPages`` for
    /// position-ordered iteration.
    ///
    /// - Important: Modify through ``TabManager/addPageToTab(_:url:at:)`` and
    ///   ``TabManager/removePageFromTab(_:page:)`` to maintain layout configuration
    ///   consistency and state synchronization.
    @Relationship(deleteRule: .cascade, inverse: \TabPage.tab)
    var pages: [TabPage]
    
    /// Serialized ``LayoutConfiguration`` for multi-page tabs.
    ///
    /// Stores pane positions, sizes, and active pane selection.
    /// `nil` for single-page tabs. Use ``layoutConfiguration`` computed
    /// property for type-safe access.
    var layoutConfigurationData: Data? {
        didSet {
            cachedLayoutConfiguration = nil
            cachedSortedPageIDs = nil // Sort order may have changed
        }
    }

    /// Cached decoded layout configuration to avoid repeated JSON parsing.
    ///
    /// Invalidated when ``layoutConfigurationData`` changes.
    @Transient
    private var cachedLayoutConfiguration: LayoutConfiguration??

    /// Cached sorted page IDs to avoid recomputation during Equatable checks.
    ///
    /// Invalidated when pages or layout configuration changes.
    /// This is a performance optimization for TabView's equality comparison.
    @Transient
    private var cachedSortedPageIDs: [UUID]?

    /// Preview page for link preview popover.
    ///
    /// This transient property holds a TabPage used for Shift+Click link previews.
    /// The preview page has a back-reference to this tab via its `tab` relationship,
    /// ensuring it gets proper content blocking, site settings, and can be converted
    /// to a real tab page.
    ///
    /// - Note: Managed by ``TabManager/createPreviewPage(for:in:)`` and cleared
    ///   when the preview is dismissed or converted.
    @Transient
    var previewPage: TabPage?

    // MARK: - Display
    
    /// User-provided name overriding the page title.
    ///
    /// When set, displays in tab list instead of ``TabPage/title``.
    /// Useful for memorable names on frequently-accessed tabs.
    var customName: String?
    
    // MARK: - Organization

    /// The organizational status of this tab.
    ///
    /// Determines where the tab appears and its behavior:
    /// - `.regular`: Normal tab in a space, can be in groups
    /// - `.pinned`: At top of space's tab list, exempt from cleanup
    /// - `.live`: Global tab in favorites grid, visible across all spaces
    var status: TabStatus

    /// Whether this tab appears in the reference pane.
    ///
    /// Reference tabs display in a persistent side panel (max 4 per space),
    /// separate from the main tab list. Useful for documentation or
    /// reference material while working.
    var isReferenceTab: Bool

    /// Whether this tab has unread content.
    ///
    /// Set `true` when created in background (e.g., "Open in New Tab").
    /// Cleared automatically when tab is activated via ``TabManager/setActiveTab(_:)``.
    var isUnread: Bool

    /// Whether the unread status was set automatically by badge detection.
    ///
    /// When `true`, the unread indicator will be automatically cleared if the
    /// badge counter disappears from the page title (e.g., user read messages
    /// on another device). When `false`, the unread status was set manually
    /// by the user or by opening a tab in the background, and will only be
    /// cleared by activating the tab.
    var unreadFromBadge: Bool

    /// The last detected badge count from the page title.
    ///
    /// Used to track notification patterns like "(3) Gmail" and only mark as unread
    /// when the count increases. Reset to `nil` when the tab is activated.
    var lastBadgeCount: Int?

    /// ID of the group containing this tab, if any.
    ///
    /// Groups provide color-coded visual organization. See ``TabGroup``.
    /// Only valid for `.regular` status tabs.
    var groupID: UUID?

    /// The group object (inverse relationship).
    var group: TabGroup?

    /// The bookmark this live tab is linked to.
    ///
    /// Set for `.liveFavorite` status tabs to maintain bidirectional relationship
    /// between the favorites grid bookmark and its underlying tab. When the
    /// bookmark is deleted, this is automatically set to nil.
    @Relationship(deleteRule: .nullify, inverse: \Bookmark.linkedTab)
    var linkedBookmark: Bookmark?
    
    // MARK: - Ordering
    
    /// Zero-based position in the space's tab list.
    ///
    /// Maintained by ``TabManager`` during reordering operations.
    /// Pinned and unpinned tabs maintain separate position sequences.
    var position: Int
    
    // MARK: - Timestamps
    
    /// When this tab was created.
    var createdAt: Date
    
    /// When this tab was last activated, or `nil` if never accessed.
    ///
    /// Updated by ``TabManager/setActiveTab(_:)``. Used for:
    /// - LRU session eviction
    /// - "Recently used" sorting
    /// - Age-based UI styling
    ///
    /// Tabs opened in the background have `nil` until first activated.
    /// When sorting, `nil` is treated as "older than any date" (least recently used).
    var lastAccessed: Date?

    /// When this tab was moved to the archive, or `nil` if not archived.
    ///
    /// Set when a tab is closed with archive enabled. The tab moves to the
    /// Archive group and is unloaded from memory. After a configurable period
    /// (and the user activating the app), the tab is permanently deleted.
    ///
    /// - Note: Archived tabs are non-activatable. Clicking shows a restore prompt.
    var archivedAt: Date?

    /// The URL this tab was pinned at. Used for navigation containment.
    ///
    /// When a pinned tab navigates within the same domain, this stores the original
    /// URL so users can return to it. For live favorites, use ``linkedBookmark?.url``
    /// instead as that represents the bookmark's canonical URL.
    var originURL: URL?

    // MARK: - Initialization

    /// Creates a new tab with a single page.
    ///
    /// - Parameters:
    ///   - space: The space to contain this tab. Use `nil` for live favorite tabs.
    ///   - url: Initial URL to load. Defaults to `about:blank`.
    ///   - title: Initial page title. Defaults to "New Tab".
    ///   - status: The organizational status. Defaults to `.regular`.
    ///   - isReferenceTab: Whether to show in reference pane. Defaults to `false`.
    ///   - groupID: Optional group to assign (only valid for `.regular` status).
    ///   - linkedBookmark: Bookmark this tab is linked to (for `.liveFavorite` status tabs).
    ///   - position: Position in tab list. Defaults to `0`.
    init(
        space: Space?,
        url: URL = .blank,
        title: String = "New Tab",
        status: TabStatus = .regular,
        isReferenceTab: Bool = false,
        groupID: UUID? = nil,
        linkedBookmark: Bookmark? = nil,
        position: Int = 0,
    ) {
        self.id = UUID()
        self.space = space
        self.pages = [TabPage(url: url, title: title, layoutPosition: .single)]
        self.layoutConfigurationData = nil
        self.customName = nil
        self.status = status
        self.isReferenceTab = isReferenceTab
        self.isUnread = false
        self.unreadFromBadge = false
        self.lastBadgeCount = nil
        self.groupID = status == .regular ? groupID : nil
        self.linkedBookmark = linkedBookmark
        self.position = position
        self.createdAt = Date()
        self.lastAccessed = nil
    }

    // MARK: - Page Access

    /// The currently active page in a multi-page layout.
    ///
    /// Returns the first page for single-page tabs or when no active
    /// pane is explicitly set.
    var activePage: TabPage {
        guard let config = layoutConfiguration,
              let activeID = config.activePaneID,
              let page = pages.first(where: { $0.id == activeID }) else {
            return firstPage
        }
        return page
    }

    /// All pages sorted by layout position.
    ///
    /// Order: single → topLeft → topRight → bottomLeft → bottomRight
    var sortedPages: [TabPage] {
        guard let config = layoutConfiguration else { return pages }
        return pages.sorted { lhs, rhs in
            let lhsPos = config.panePositions[lhs.id] ?? .single
            let rhsPos = config.panePositions[rhs.id] ?? .single
            return lhsPos.sortOrder < rhsPos.sortOrder
        }
    }

    /// Cached sorted page IDs for efficient equality checks.
    ///
    /// This avoids recomputing ``sortedPages`` and mapping to IDs on every
    /// ``TabView`` equality comparison. The cache is invalidated when pages
    /// are added or removed.
    var sortedPageIDs: [UUID] {
        if let cached = cachedSortedPageIDs {
            return cached
        }
        let ids = sortedPages.map(\.id)
        cachedSortedPageIDs = ids
        return ids
    }

    /// Gets the page at a specific layout position.
    ///
    /// - Parameter position: The position to query.
    /// - Returns: The page at that position, or `nil` if none exists.
    func page(at position: PanePosition) -> TabPage? {
        guard let config = layoutConfiguration else {
            return position == .single ? firstPage : nil
        }
        return pages.first { config.panePositions[$0.id] == position }
    }
    
    /// Returns a blank fallback page if pages have been cascade-deleted during
    /// tab deletion (SwiftUI may still hold a reference and try to render).
    private var firstPage: TabPage {
        pages.first ?? TabPage(url: .blank, title: "", layoutPosition: .single)
    }

    // MARK: - Display Properties

    /// The URL string for display in UI.
    ///
    /// For multi-page tabs showing individual page URLs, access ``TabPage/url`` directly.
    /// Returns empty string during deletion (when pages are cascade-deleted).
    var displayURL: String {
        guard !pages.isEmpty else { return "" }
        let url = activePage.url
        guard url != .blank else { return "" }
        return url.absoluteString
    }

    /// Whether the primary page uses HTTPS.
    ///
    /// Used for security indicator in address bar.
    var isSecure: Bool {
        activePage.isSecure
    }

    /// All display properties computed in a single pass.
    ///
    /// Use this for equality comparisons to avoid redundant computation.
    /// Computes `displayTitle`, `displayTitleIsURL`, and `cleanedDisplayURL` together.
    var displayInfo: TabDisplayInfo {
        guard !pages.isEmpty else {
            return TabDisplayInfo(title: "", titleIsURL: false, cleanedURL: "")
        }

        // Custom name takes priority
        if let customName, !customName.isEmpty {
            return TabDisplayInfo(title: customName, titleIsURL: false, cleanedURL: "")
        }

        let page = activePage
        let url = page.url

        // Blank page has no meaningful content
        guard url != .blank else {
            return TabDisplayInfo(title: "", titleIsURL: false, cleanedURL: "")
        }

        // Compute cleaned URL once (needed for both title fallback and comparison)
        let cleanedURL = Self.cleanURL(url)

        // Check if page title is meaningful
        let pageTitle = page.title
        let hasMeaningfulTitle = !pageTitle.isEmpty
            && pageTitle != "New Tab"
            && pageTitle != url.host

        if hasMeaningfulTitle {
            return TabDisplayInfo(title: pageTitle, titleIsURL: false, cleanedURL: cleanedURL)
        } else {
            return TabDisplayInfo(title: cleanedURL, titleIsURL: true, cleanedURL: cleanedURL)
        }
    }

    /// The display title for UI rendering.
    ///
    /// Priority: custom name → meaningful page title → cleaned URL.
    ///
    /// A title is "meaningful" if it's not empty, not "New Tab", and
    /// not just the hostname.
    ///
    /// Returns empty string during deletion to avoid flashing "about:blank".
    var displayTitle: String {
        displayInfo.title
    }

    /// Whether ``displayTitle`` is showing a URL rather than a title.
    ///
    /// Use this to adjust text styling (e.g., secondary color for URLs).
    var displayTitleIsURL: Bool {
        displayInfo.titleIsURL
    }

    /// URL formatted for display (protocol and www removed).
    ///
    /// Examples:
    /// - `https://www.example.com/` → `example.com`
    /// - `https://docs.swift.org/guide` → `docs.swift.org/guide`
    ///
    /// Returns empty string during deletion.
    var cleanedDisplayURL: String {
        displayInfo.cleanedURL
    }

    /// Cleans a URL for display by removing protocol and www prefix.
    private static func cleanURL(_ url: URL) -> String {
        url.displayString
    }
    
    // MARK: - Layout Configuration
    
    /// Decoded layout configuration for multi-page tabs.
    ///
    /// `nil` for single-page tabs. Contains pane positions, sizes,
    /// and active pane selection.
    ///
    /// - Note: Uses an internal cache to avoid repeated JSON decoding.
    ///   The cache is invalidated automatically when the underlying data changes.
    var layoutConfiguration: LayoutConfiguration? {
        get {
            if let cached = cachedLayoutConfiguration {
                return cached
            }
            guard let data = layoutConfigurationData else {
                cachedLayoutConfiguration = .some(nil)
                return nil
            }
            let decoded = try? JSONDecoder().decode(LayoutConfiguration.self, from: data)
            cachedLayoutConfiguration = .some(decoded)
            return decoded
        }
        set {
            layoutConfigurationData = try? JSONEncoder().encode(newValue)
            cachedLayoutConfiguration = .some(newValue)
        }
    }
    
    /// Whether this tab has multiple pages in a layout.
    var isMultiPage: Bool {
        layoutConfiguration != nil && pages.count > 1
    }

    // MARK: - Status Convenience Properties

    /// Whether this tab is pinned to the top of its space's tab list.
    ///
    /// Pinned tabs sort before regular tabs and are exempt from auto-cleanup.
    var isPinned: Bool {
        get { status == .pinned }
        set { status = newValue ? .pinned : .regular }
    }

    /// Whether this tab is a global live favorite.
    ///
    /// Live favorite tabs appear in the favorites grid across all spaces
    /// and use global website data storage.
    var isLiveFavorite: Bool {
        status == .liveFavorite
    }

    /// Whether this tab was created as a popup via `window.open()`.
    ///
    /// Popup tabs have an ``TabPage/openerTabPageID`` set on their primary page,
    /// linking them to the page that opened them. This relationship is used for:
    /// - Refocusing the opener when the popup closes via `window.close()`
    /// - Grouping linked popups (OAuth, payment flows) with their opener
    var isPopup: Bool {
        activePage.openerTabPageID != nil
    }

    /// The URL this tab should be contained to for navigation containment.
    ///
    /// Used for Arc-style navigation behavior where pinned tabs and live favorites
    /// are kept focused on their designated sites. Cross-domain navigations are
    /// shown in a preview panel instead of navigating the tab.
    ///
    /// | Status | Home URL |
    /// |--------|----------|
    /// | **Pinned** | ``originURL`` (captured when pinned) |
    /// | **Live Favorite** | ``linkedBookmark?.url`` |
    /// | **Regular** | `nil` (no containment) |
    var homeURL: URL? {
        switch status {
        case .liveFavorite:
            linkedBookmark?.url
        case .pinned:
            originURL
        case .regular:
            nil
        }
    }

    /// Whether the current URL differs from the home URL.
    ///
    /// When `true`, a "back to origin" button should be shown to allow
    /// returning to the original pinned/favorite URL.
    ///
    /// Returns `false` for regular tabs or when the current page is blank.
    var hasNavigatedFromHome: Bool {
        guard let home = homeURL else { return false }
        let currentURL = activePage.url
        guard currentURL != .blank else { return false }
        return currentURL != home
    }

    /// Whether this tab is in the archive (pending permanent deletion).
    ///
    /// Archived tabs are unloaded from memory, displayed with a trash icon,
    /// and are non-activatable until restored.
    var isArchived: Bool {
        archivedAt != nil
    }

    // MARK: - Age Classification

    /// Cached age category to avoid expensive recomputation on every render.
    ///
    /// The cache is invalidated after 60 seconds or when `lastAccessed` changes.
    /// This prevents thousands of updates per second during tab list rendering
    /// while still updating age indicators at a reasonable frequency.
    @Transient
    private var cachedAgeCategory: (category: TabAgeCategory, computedAt: Date, baseline: Date)?

    /// Age category based on time since last access.
    ///
    /// Used for visual styling (e.g., fading old tabs) and cleanup policies.
    /// If the tab has never been accessed, uses creation date as the baseline.
    ///
    /// - Note: Results are cached for 60 seconds to prevent excessive recomputation.
    ///   The visual difference between age categories spans hours, so sub-minute
    ///   precision is unnecessary.
    var ageCategory: TabAgeCategory {
        let baseline = lastAccessed ?? createdAt
        let now = Date()

        // Check if cache is valid (same baseline, computed within last 60 seconds)
        if let cached = cachedAgeCategory,
           cached.baseline == baseline,
           now.timeIntervalSince(cached.computedAt) < 60 {
            return cached.category
        }

        // Compute fresh
        let elapsed = now.timeIntervalSince(baseline)
        let category: TabAgeCategory = if elapsed >= 43_200 { .old12h } // 12+ hours
        else if elapsed >= 21_600 { .old6h } // 6-12 hours
        else { .recent } // < 6 hours

        cachedAgeCategory = (category, now, baseline)
        return category
    }
    
    // MARK: - Mutation Methods
    
    /// Updates the last accessed timestamp to now.
    ///
    /// Called by ``TabManager/setActiveTab(_:)``.
    func updateLastAccessed() {
        lastAccessed = Date()
    }
    
    /// Adds a page to this tab at the specified position.
    ///
    /// Converts a single-page tab into a multi-page layout. Updates
    /// ``layoutConfiguration`` to track the new page's position.
    ///
    /// - Parameters:
    ///   - page: The page to add.
    ///   - position: Where to place the page in the layout.
    ///
    /// - Important: Internal use only. Call ``TabManager/addPageToTab(_:url:at:)``
    ///   to ensure proper state synchronization.
    func _addPage(_ page: TabPage, at position: PanePosition) {
        page.position = position
        pages.append(page)
        cachedSortedPageIDs = nil // Invalidate cache

        var config = layoutConfiguration ?? LayoutConfiguration(panePositions: [:])
        config.panePositions[page.id] = position
        layoutConfiguration = config
    }
    
    /// Removes a page from this tab.
    ///
    /// If only one page remains after removal, clears the layout configuration
    /// and resets that page to `.single` position.
    ///
    /// - Parameter page: The page to remove.
    ///
    /// - Important: Internal use only. Call ``TabManager/removePageFromTab(_:page:)``
    ///   to ensure proper session cleanup and state synchronization.
    func _removePage(_ page: TabPage) {
        pages.removeAll { $0.id == page.id }
        cachedSortedPageIDs = nil // Invalidate cache

        var config = layoutConfiguration
        config?.panePositions.removeValue(forKey: page.id)

        // Revert to single-page if only one remains
        if pages.count == 1 {
            layoutConfiguration = nil
            pages[0].position = .single
        } else {
            layoutConfiguration = config
        }
    }
    
    /// Sets the active page in a multi-page layout.
    ///
    /// The active page receives keyboard focus and is the target for
    /// address bar navigation.
    ///
    /// - Parameter page: The page to make active.
    ///
    /// - Important: Internal use only. Call ``TabManager/setActivePage(in:page:)``
    ///   to ensure proper state synchronization.
    func _setActivePage(_ page: TabPage) {
        guard var config = layoutConfiguration else { return }
        config.activePaneID = page.id
        layoutConfiguration = config
    }
}

// MARK: - TabDisplayInfo

/// Computed display properties for a tab, calculated in a single pass.
///
/// Use ``Tab/displayInfo`` to get all display properties efficiently.
/// This avoids redundant computation when comparing tabs for equality.
struct TabDisplayInfo: Equatable {
    /// The display title (custom name, page title, or cleaned URL).
    let title: String

    /// Whether the title is showing a URL rather than a meaningful title.
    let titleIsURL: Bool

    /// The cleaned URL string (protocol and www removed).
    let cleanedURL: String
}
