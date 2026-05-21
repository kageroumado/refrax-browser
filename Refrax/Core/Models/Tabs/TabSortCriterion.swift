import Foundation

/// Criteria for one-time sorting of tabs in a space.
///
/// Each criterion defines how tabs (and groups) should be reordered.
/// The sort operation updates `position` values to persist the new order.
///
/// ## Usage
///
/// ```swift
/// tabManager.sortTabs(by: .nameAscending, in: space)
/// ```
///
/// ## Sorting Behavior
///
/// - **Tabs**: Sorted by their properties (title, domain, dates)
/// - **Groups**: Sorted by `group.name` for name/domain sorts, `group.createdAt` for date sorts
/// - **Hierarchy**: Pinned and unpinned items are sorted separately
enum TabSortCriterion: CaseIterable, Sendable {
    /// Sort alphabetically by display title (A → Z)
    case nameAscending

    /// Sort alphabetically by display title (Z → A)
    case nameDescending

    /// Sort alphabetically by domain (A → Z)
    case domainAscending

    /// Sort alphabetically by domain (Z → A)
    case domainDescending

    /// Sort by last accessed date (most recent first)
    case recentFirst

    /// Sort by last accessed date (oldest first)
    case oldestFirst

    /// Sort by creation date (newest first)
    case createdNewest

    /// Sort by creation date (oldest first)
    case createdOldest

    /// Display name for menu items.
    var displayName: String {
        switch self {
        case .nameAscending: "Name (A → Z)"
        case .nameDescending: "Name (Z → A)"
        case .domainAscending: "Domain (A → Z)"
        case .domainDescending: "Domain (Z → A)"
        case .recentFirst: "Recently Visited"
        case .oldestFirst: "Least Recently Visited"
        case .createdNewest: "Recently Created"
        case .createdOldest: "Oldest Created"
        }
    }

    /// SF Symbol icon for menu items.
    var iconName: String {
        switch self {
        case .nameAscending: "textformat.abc"
        case .nameDescending: "textformat.abc"
        case .domainAscending: "globe"
        case .domainDescending: "globe"
        case .recentFirst: "clock.arrow.circlepath"
        case .oldestFirst: "clock"
        case .createdNewest: "calendar.badge.plus"
        case .createdOldest: "calendar"
        }
    }

    /// Whether this criterion sorts in descending order.
    var isDescending: Bool {
        switch self {
        case .nameDescending, .domainDescending, .recentFirst, .createdNewest:
            true
        case .nameAscending, .domainAscending, .oldestFirst, .createdOldest:
            false
        }
    }

    /// The category of this sort criterion for menu grouping.
    var category: Category {
        switch self {
        case .nameAscending, .nameDescending:
            .name
        case .domainAscending, .domainDescending:
            .domain
        case .recentFirst, .oldestFirst:
            .lastVisited
        case .createdNewest, .createdOldest:
            .created
        }
    }

    /// Categories for grouping sort criteria in menus.
    enum Category: CaseIterable {
        case name
        case domain
        case lastVisited
        case created

        var displayName: String {
            switch self {
            case .name: "By Name"
            case .domain: "By Domain"
            case .lastVisited: "By Last Visited"
            case .created: "By Creation Date"
            }
        }

        /// The sort criteria belonging to this category.
        var criteria: [TabSortCriterion] {
            TabSortCriterion.allCases.filter { $0.category == self }
        }
    }
}
