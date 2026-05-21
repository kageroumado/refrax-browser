import Foundation
import SwiftData

/// Codable representation of a browser session for import/export.
///
/// Supports exporting the current space's tabs and groups to JSON,
/// and importing previously exported sessions to restore tab configurations.
///
/// ## File Format
///
/// ```json
/// {
///   "version": 1,
///   "exportedAt": "2026-01-17T10:30:00Z",
///   "spaces": [
///     {
///       "name": "Work",
///       "groups": [
///         {
///           "name": "Research",
///           "color": "#FF5733",
///           "icon": "book.fill",
///           "isCollapsed": false,
///           "tabs": [...]
///         }
///       ],
///       "tabs": [...]
///     }
///   ]
/// }
/// ```
struct SessionExport: Codable, Sendable, Equatable {
    /// Format version for future compatibility.
    let version: Int

    /// When the export was created.
    let exportedAt: Date

    /// Exported spaces with their tabs and groups.
    let spaces: [ExportedSpace]

    /// Current format version.
    static let currentVersion = 1

    init(spaces: [ExportedSpace]) {
        self.version = Self.currentVersion
        self.exportedAt = Date()
        self.spaces = spaces
    }
}

/// Exported representation of a space.
struct ExportedSpace: Codable, Sendable, Equatable {
    /// Space name.
    let name: String

    /// Tab groups in this space.
    let groups: [ExportedTabGroup]

    /// Ungrouped tabs in this space.
    let tabs: [ExportedTab]
}

/// Exported representation of a tab group.
struct ExportedTabGroup: Codable, Sendable, Equatable {
    /// Group display name.
    let name: String

    /// Hex color string (e.g., "#007AFF").
    let color: String

    /// SF Symbol name or emoji.
    let icon: String?

    /// Whether the group is collapsed.
    let isCollapsed: Bool

    /// Whether the group is pinned.
    let isPinned: Bool

    /// Tabs within this group.
    let tabs: [ExportedTab]
}

/// Exported representation of a single tab.
struct ExportedTab: Codable, Sendable, Equatable {
    /// URL of the tab.
    let url: String

    /// Page title.
    let title: String

    /// User-provided custom name, if any.
    let customName: String?

    /// Whether the tab is pinned.
    let isPinned: Bool
}

// MARK: - Export Helpers

extension SessionExport {
    /// Creates an export from the given space.
    ///
    /// - Parameter space: The space to export.
    init(space: Space) {
        let exportedSpace = ExportedSpace(space: space)
        self.init(spaces: [exportedSpace])
    }

    /// Creates an export from multiple spaces.
    ///
    /// - Parameter spaces: The spaces to export.
    init(spaces: [Space]) {
        let exportedSpaces = spaces.map { ExportedSpace(space: $0) }
        self.init(spaces: exportedSpaces)
    }
}

extension ExportedSpace {
    /// Creates an exported space from a Space model.
    init(space: Space) {
        // Get all non-archived tabs
        let allTabs = space.tabs.filter { $0.archivedAt == nil }

        // Separate grouped and ungrouped tabs
        let ungroupedFiltered = allTabs.filter { tab in
            tab.groupID == nil && !tab.isReferenceTab && tab.status != TabStatus.liveFavorite
        }
        let ungroupedSorted = ungroupedFiltered.sorted { $0.position < $1.position }
        let ungroupedTabs = ungroupedSorted.map { ExportedTab(tab: $0) }

        // Export groups with their tabs (excluding archive groups)
        let nonArchiveGroups = space.groups.filter { !$0.isArchive }
        let sortedGroups = nonArchiveGroups.sorted { $0.position < $1.position }
        let exportedGroups: [ExportedTabGroup] = sortedGroups.map { group in
            let groupFiltered = allTabs.filter { $0.groupID == group.id }
            let groupSorted = groupFiltered.sorted { $0.position < $1.position }
            let groupTabs = groupSorted.map { ExportedTab(tab: $0) }

            return ExportedTabGroup(
                name: group.name,
                color: group.colorString,
                icon: group.iconName,
                isCollapsed: group.isCollapsed,
                isPinned: group.isPinned,
                tabs: groupTabs,
            )
        }

        self.name = space.name
        self.groups = exportedGroups
        self.tabs = ungroupedTabs
    }
}

extension ExportedTab {
    /// Creates an exported tab from a Tab model.
    init(tab: Tab) {
        self.url = tab.activePage.url.absoluteString
        self.title = tab.activePage.title
        self.customName = tab.customName
        self.isPinned = tab.isPinned
    }
}
