import Foundation

/// The configurable actions and groups available in the control rail.
nonisolated enum ControlIslandItem: String, CaseIterable, Codable, Identifiable {
    case windowControls, navigation, address, commandLens, floatingTabs, recentTabs, desk, spaces, favoriteTabs
    case reload, favorites, history, downloads, bookmarks, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windowControls: "Window controls"
        case .navigation: "Back and Forward"
        case .address: "Address"
        case .commandLens: "Command Lens"
        case .floatingTabs: "Floating tabs"
        case .recentTabs: "Recent tabs"
        case .desk: "Desk"
        case .spaces: "Spaces"
        case .favoriteTabs: "Favorite tabs"
        case .reload: "Reload"
        case .favorites: "Favorites"
        case .history: "History"
        case .downloads: "Downloads"
        case .bookmarks: "Bookmarks"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .windowControls: "ellipsis.circle"
        case .navigation: "chevron.left.forwardslash.chevron.right"
        case .address: "link"
        case .commandLens: "sparkle.magnifyingglass"
        case .floatingTabs: "square.on.square"
        case .recentTabs: "clock.arrow.circlepath"
        case .desk: "square.grid.3x3.topleft.filled"
        case .spaces: "square.stack"
        case .favoriteTabs: "star.square.on.square"
        case .reload: "arrow.clockwise"
        case .favorites: "star"
        case .history: "clock"
        case .downloads: "arrow.down.circle"
        case .bookmarks: "bookmark"
        case .settings: "gearshape"
        }
    }

    var detail: String {
        switch self {
        case .windowControls: "Close, minimize, and full screen"
        case .navigation: "One row; Forward appears when available"
        case .address: "Edit the address or reveal page controls"
        case .commandLens: "Search pages, tabs, and commands · ⌘T"
        case .floatingTabs: "Reveal your tabs · Hold Control to peek"
        case .recentTabs: "Switch between recent tabs · ⌃Tab"
        case .desk: "Organize tabs on the desk · ⌘⇧\\"
        case .spaces: "Grouped space icons with the current space selected"
        case .favoriteTabs: "Live favorite tabs as a scrolling column of site icons"
        case .reload: "Reload the page or stop loading · ⌘R"
        case .favorites: "Open all your favorites"
        case .history: "Browse visited pages"
        case .downloads: "See your downloads"
        case .bookmarks: "Manage saved pages and favorites"
        case .settings: "Open browser settings · ⌘,"
        }
    }

    var isGroup: Bool {
        self == .windowControls || self == .spaces || self == .favoriteTabs
    }

    var isDefault: Bool {
        switch self {
        case .reload, .favorites, .history, .downloads, .bookmarks, .settings: false
        default: true
        }
    }
}
