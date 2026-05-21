import Foundation

/// The organizational status of a tab within the browser.
///
/// Tabs have three possible states that affect their visibility, persistence,
/// and behavior:
///
/// - **Regular**: Standard tabs that live within a specific space. Subject to
///   automatic cleanup based on age and can be closed normally.
///
/// - **Pinned**: Tabs pinned to the top of their space's tab list. Exempt from
///   automatic cleanup and visually distinguished. Cannot be in a group.
///
/// - **Live Favorite**: Global tabs that appear in the favorites grid across all
///   spaces. These are persistent, space-independent tabs linked to a favorited
///   bookmark. They use global website data storage regardless of space settings.
///
/// ## Storage
///
/// Live favorite tabs are stored globally in ``BrowserState/liveTabs`` rather than
/// in a specific space's tab array. Regular and pinned tabs remain in their
/// space's ``Space/tabs`` collection.
enum TabStatus: String, Codable, Sendable, Hashable, CaseIterable {
    /// Standard tab within a specific space.
    ///
    /// Regular tabs:
    /// - Belong to exactly one space
    /// - Can be organized into groups
    /// - Subject to automatic cleanup based on ``Tab/ageCategory``
    /// - Sorted after pinned tabs in the sidebar
    case regular

    /// Pinned tab at the top of a space's tab list.
    ///
    /// Pinned tabs:
    /// - Belong to exactly one space
    /// - Cannot be in a group
    /// - Exempt from automatic cleanup
    /// - Always sorted before regular tabs
    /// - Visually distinguished in the sidebar
    case pinned

    /// Global favorite tab visible in the favorites grid across all spaces.
    ///
    /// Live favorite tabs:
    /// - Not attached to any specific space
    /// - Appear in the favorites grid at the top of the sidebar
    /// - Always use global website data storage
    /// - Linked to a favorited ``Bookmark`` via ``Tab/linkedBookmark``
    /// - Persistent until the user removes them from favorites
    case liveFavorite

    /// Whether this status makes the tab exempt from automatic cleanup.
    ///
    /// Both `.pinned` and `.liveFavorite` tabs are exempt from auto-cleanup
    /// and have special positioning in the UI.
    var isExemptFromCleanup: Bool {
        self != .regular
    }

    /// Whether this tab should use global website data storage.
    ///
    /// Live favorite tabs always use global storage to maintain consistent
    /// sessions across spaces. Regular and pinned tabs use their space's data store.
    var usesGlobalDataStore: Bool {
        self == .liveFavorite
    }
}
