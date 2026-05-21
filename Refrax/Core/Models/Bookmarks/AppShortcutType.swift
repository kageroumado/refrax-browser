import Foundation

/// Types of app feature shortcuts that can be added to favorites.
///
/// App shortcuts provide one-click access to app features like trays and settings,
/// appearing alongside web-based favorites in the grid.
nonisolated enum AppShortcutType: String, Codable, CaseIterable, Identifiable, Sendable {
    case downloads
    case bookmarks
    case history
    case settings

    var id: String { rawValue }

    /// Display name shown in the favorites grid and settings.
    var displayName: String {
        switch self {
        case .downloads:
            "Downloads"
        case .bookmarks:
            "Bookmarks"
        case .history:
            "History"
        case .settings:
            "Settings"
        }
    }

    /// SF Symbol name for this shortcut type.
    var iconName: String {
        switch self {
        case .downloads:
            "arrow.down.circle"
        case .bookmarks:
            "bookmark"
        case .history:
            "clock"
        case .settings:
            "gearshape"
        }
    }

    /// Default palette color for this shortcut type.
    var defaultColor: String {
        switch self {
        case .downloads:
            GroupColor.steel.rawValue
        case .bookmarks:
            GroupColor.mahogany.rawValue
        case .history:
            GroupColor.violet.rawValue
        case .settings:
            GroupColor.pelorus.rawValue
        }
    }
}
