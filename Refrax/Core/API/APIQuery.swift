import Foundation

/// Queries for reading browser state.
///
/// Queries are read-only operations that return information about
/// the current browser state without modifying it.
public enum APIQuery: Sendable {
    // MARK: - Tab Queries

    /// Gets all tabs, optionally filtered by space.
    ///
    /// - Parameter spaceID: Filter to tabs in this space (all spaces if nil).
    case tabs(spaceID: UUID?)

    /// Gets a specific tab by ID.
    ///
    /// - Parameter id: The tab ID.
    case tab(id: UUID)

    /// Gets the currently active tab in the active window.
    case activeTab

    /// Gets tabs in the reference pane for a space.
    ///
    /// - Parameter spaceID: The space (uses active space if nil).
    case referenceTabs(spaceID: UUID?)

    /// Gets page content (HTML/text) for a tab.
    ///
    /// - Note: Requires `contentRead` permission and domain approval.
    ///
    /// - Parameters:
    ///   - tabID: The tab to extract content from.
    ///   - includeHTML: Whether to include raw HTML.
    ///   - includeText: Whether to include extracted text.
    case tabContent(tabID: UUID, includeHTML: Bool, includeText: Bool)

    // MARK: - Space Queries

    /// Gets all spaces.
    case spaces

    /// Gets a specific space by ID.
    ///
    /// - Parameter id: The space ID.
    case space(id: UUID)

    /// Gets the currently active space in the active window.
    case activeSpace

    // MARK: - Group Queries

    /// Gets all groups in a space.
    ///
    /// - Parameter spaceID: The space (uses active space if nil).
    case groups(spaceID: UUID?)

    /// Gets a specific group by ID.
    ///
    /// - Parameter id: The group ID.
    case group(id: UUID)

    // MARK: - History Queries

    /// Gets browsing history.
    ///
    /// - Parameters:
    ///   - range: Optional date range filter.
    ///   - limit: Maximum entries to return (default 100).
    ///   - offset: Pagination offset (default 0).
    ///   - domain: Filter by domain.
    case history(range: DateInterval?, limit: Int, offset: Int, domain: String?)

    /// Searches history by text query.
    ///
    /// - Parameters:
    ///   - query: Search text.
    ///   - limit: Maximum entries to return.
    case searchHistory(query: String, limit: Int)

    // MARK: - Browser State Queries

    /// Gets current browser state summary.
    case browserState
}

// MARK: - Permission Requirements

public extension APIQuery {
    /// Permission requirements for executing this query.
    var permissionRequirements: PermissionRequirements {
        switch self {
        case .tabs, .tab, .activeTab, .referenceTabs:
            .tabsRead
        case .tabContent:
            .contentRead
        case .spaces, .space, .activeSpace:
            .spacesRead
        case .groups, .group:
            .tabsRead
        case .history, .searchHistory:
            .historyRead
        case .browserState:
            PermissionRequirements(scopes: [.tabsRead, .spacesRead])
        }
    }
}

// MARK: - Query Result

/// Result of executing an API query.
public enum QueryResult: Sendable {
    /// Single tab information.
    case tab(TabInfo)

    /// Multiple tabs.
    case tabs([TabInfo])

    /// Tab page content.
    case content(PageContentInfo)

    /// Single space information.
    case space(SpaceInfo)

    /// Multiple spaces.
    case spaces([SpaceInfo])

    /// Single group information.
    case group(TabGroupInfo)

    /// Multiple groups.
    case groups([TabGroupInfo])

    /// History entries.
    case history([HistoryEntryInfo])

    /// Browser state summary.
    case browserState(BrowserStateInfo)
}

// MARK: - Browser State Info

/// Summary of current browser state for API responses.
public struct BrowserStateInfo: Codable, Sendable {
    /// Total number of tabs across all spaces.
    public let totalTabCount: Int

    /// Number of spaces.
    public let spaceCount: Int

    /// ID of the active space in the active window.
    public let activeSpaceID: UUID?

    /// ID of the active tab in the active window.
    public let activeTabID: UUID?

    /// Whether content blocking is ready.
    public let isContentBlockingReady: Bool

    /// Tab list version counter (for change detection).
    public let tabListVersion: UInt64

    /// Tab content version counter (for change detection).
    public let tabContentVersion: UInt64

    public init(
        totalTabCount: Int,
        spaceCount: Int,
        activeSpaceID: UUID?,
        activeTabID: UUID?,
        isContentBlockingReady: Bool,
        tabListVersion: UInt64,
        tabContentVersion: UInt64,
    ) {
        self.totalTabCount = totalTabCount
        self.spaceCount = spaceCount
        self.activeSpaceID = activeSpaceID
        self.activeTabID = activeTabID
        self.isContentBlockingReady = isContentBlockingReady
        self.tabListVersion = tabListVersion
        self.tabContentVersion = tabContentVersion
    }
}
