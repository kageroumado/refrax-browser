import Foundation

// MARK: - DTO Types

/// Serializable representation of a tab for API responses.
public struct TabInfo: Codable, Sendable, Identifiable {
    public let id: UUID
    public let spaceID: UUID?
    public let url: String
    public let title: String
    public let isSecure: Bool
    public let isPinned: Bool
    public let isReferenceTab: Bool
    public let isUnread: Bool
    public let groupID: UUID?
    public let position: Int
    public let createdAt: Date
    public let lastAccessed: Date?
    public let faviconData: Data?
    public let pageCount: Int

    /// Creates a ``TabInfo`` from a ``Tab`` model.
    @MainActor
    init(_ tab: Tab) {
        self.id = tab.id
        self.spaceID = tab.space?.id
        self.url = tab.activePage.url.absoluteString
        self.title = tab.displayTitle
        self.isSecure = tab.isSecure
        self.isPinned = tab.isPinned
        self.isReferenceTab = tab.isReferenceTab
        self.isUnread = tab.isUnread
        self.groupID = tab.groupID
        self.position = tab.position
        self.createdAt = tab.createdAt
        self.lastAccessed = tab.lastAccessed
        self.faviconData = tab.activePage.faviconData
        self.pageCount = tab.pages.count
    }
}

/// Serializable representation of a space for API responses.
public struct SpaceInfo: Codable, Sendable, Identifiable {
    public let id: UUID
    public let name: String
    public let iconName: String
    public let colorHex: String
    public let description: String?
    public let position: Int
    public let createdAt: Date
    public let tabCount: Int
    public let referenceTabCount: Int
    public let dataStoreMode: String

    /// Creates a ``SpaceInfo`` from a ``Space`` model.
    @MainActor
    init(_ space: Space) {
        self.id = space.id
        self.name = space.name
        self.iconName = space.iconName
        self.colorHex = space.colorHex
        self.description = space.spaceDescription
        self.position = space.position
        self.createdAt = space.createdAt
        self.tabCount = space.tabCount
        self.referenceTabCount = space.referenceTabCount
        self.dataStoreMode = space.dataStoreMode.rawValue
    }
}

/// Serializable representation of tab page content for API responses.
public struct PageContentInfo: Codable, Sendable {
    public let tabID: UUID
    public let pageID: UUID
    public let url: String
    public let title: String
    public let html: String?
    public let textContent: String?

    public init(
        tabID: UUID,
        pageID: UUID,
        url: String,
        title: String,
        html: String?,
        textContent: String?,
    ) {
        self.tabID = tabID
        self.pageID = pageID
        self.url = url
        self.title = title
        self.html = html
        self.textContent = textContent
    }
}

/// Serializable representation of a history entry for API responses.
public struct HistoryEntryInfo: Codable, Sendable, Identifiable {
    public let id: UUID
    public let url: String
    public let title: String?
    public let domain: String
    public let visitedAt: Date
    public let closedAt: Date?
    public let timeSpent: TimeInterval
    public let spaceID: UUID?

    @MainActor
    init(_ entry: HistoryEntry) {
        self.id = entry.id
        self.url = entry.url.absoluteString
        self.title = entry.title
        self.domain = entry.domain
        self.visitedAt = entry.visitedAt
        self.closedAt = entry.closedAt
        self.timeSpent = entry.timeSpent
        self.spaceID = entry.spaceID
    }

    /// Creates a ``HistoryEntryInfo`` from a ``HistoryEntryData`` transfer type.
    init(_ data: HistoryEntryData) {
        self.id = data.id
        self.url = data.url.absoluteString
        self.title = data.title
        self.domain = data.domain
        self.visitedAt = data.visitedAt
        self.closedAt = data.closedAt
        self.timeSpent = data.timeSpent
        self.spaceID = data.spaceID
    }
}

/// Serializable representation of a tab group for API responses.
public struct TabGroupInfo: Codable, Sendable, Identifiable {
    public let id: UUID
    public let spaceID: UUID?
    public let name: String
    public let colorString: String
    public let iconName: String?
    public let isPinned: Bool
    public let isCollapsed: Bool
    public let position: Int
    public let parentGroupID: UUID?
    public let tabCount: Int

    @MainActor
    init(_ group: TabGroup, tabCount: Int) {
        self.id = group.id
        self.spaceID = group.space?.id
        self.name = group.name
        self.colorString = group.colorString
        self.iconName = group.iconName
        self.isPinned = group.isPinned
        self.isCollapsed = group.isCollapsed
        self.position = group.position
        self.parentGroupID = group.parentGroupID
        self.tabCount = tabCount
    }
}

// MARK: - Navigation Info

/// Information about a navigation event.
public struct NavigationInfo: Codable, Sendable {
    public let tabID: UUID
    public let pageID: UUID
    public let url: String
    public let title: String?
    public let isMainFrame: Bool

    public init(
        tabID: UUID,
        pageID: UUID,
        url: String,
        title: String?,
        isMainFrame: Bool,
    ) {
        self.tabID = tabID
        self.pageID = pageID
        self.url = url
        self.title = title
        self.isMainFrame = isMainFrame
    }
}
