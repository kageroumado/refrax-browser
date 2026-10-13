import Foundation

/// The configurable actions and groups available in the control rail.
nonisolated enum ControlIslandItem: String, CaseIterable, Codable, Identifiable {
    case windowControls
    case navigation
    case commandLens
    case floatingTabs
    case recentTabs
    case desk
    case spaces
    case favoriteTabs
    case reload
    case copyLink
    case favorites
    case history
    case downloads
    case bookmarks
    case settings
    /// A downloaded update waiting for a restart. On the rail only while one is ready.
    case updates
    /// The current page's icon, which unfolds the page card. Stored under its original name.
    case page = "address"

    /// Where an item renders on the rail.
    enum Section: Equatable {
        /// The browsing controls, in their customized order.
        case main
        /// Additional controls, after a divider at the bottom, in their customized order.
        case additional
    }

    var id: String {
        rawValue
    }

    /// The rail's order before anyone customizes it.
    static let defaultOrder: [ControlIslandItem] = [
        .windowControls, .navigation, .page, .commandLens, .floatingTabs, .desk, .spaces, .favoriteTabs,
        .reload, .copyLink, .favorites, .history, .downloads, .bookmarks, .settings, .recentTabs, .updates,
    ]

    var title: String {
        switch self {
        case .windowControls: "Window controls"
        case .navigation: "Back and Forward"
        case .page: "Current page"
        case .copyLink: "Copy Link"
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
        case .updates: "Update ready"
        }
    }

    var symbol: String {
        switch self {
        case .windowControls: "ellipsis.circle"
        case .navigation: "chevron.left.forwardslash.chevron.right"
        case .page: "globe"
        case .copyLink: "link"
        case .commandLens: "sparkle.magnifyingglass"
        case .floatingTabs: "square.on.square"
        case .recentTabs: "clock.arrow.circlepath"
        case .desk: "rectangle.3.group"
        case .spaces: "square.stack"
        case .favoriteTabs: "star.square.on.square"
        case .reload: "arrow.clockwise"
        case .favorites: "star"
        case .history: "clock"
        case .downloads: "arrow.down.circle"
        case .bookmarks: "bookmark"
        case .settings: "gearshape"
        case .updates: "arrow.down.circle.fill"
        }
    }

    var detail: String {
        switch self {
        case .windowControls: "Close, minimize, and full screen"
        case .navigation: "One row; Forward appears when available · ⌥-click shows history"
        case .page: "The page's icon; hover it for the page card with address, reload, favorite, and actions"
        case .copyLink: "Copy the page address"
        case .commandLens: "Search pages, tabs, and commands · ⌘T"
        case .floatingTabs: "Reveal your tabs · ⌥-click for recent tabs · Hold Control to peek"
        case .recentTabs: "Switch between recent tabs · ⌃Tab"
        case .desk: "Organize tabs on the desk · ⌘⇧\\ · ⌥-click opens the desk with the lab menu in debug builds"
        case .spaces: "Grouped space icons with the current space selected"
        case .favoriteTabs: "Live favorite tabs as a scrolling column of site icons"
        case .reload: "Reload the page or stop loading · ⌘R"
        case .favorites: "Open all your favorites"
        case .history: "Browse visited pages"
        case .downloads: "See your downloads"
        case .bookmarks: "Manage saved pages and favorites"
        case .settings: "Open browser settings · ⌘,"
        case .updates: "Restart to install a downloaded update; on the rail only while one is ready"
        }
    }

    var isGroup: Bool {
        self == .windowControls || self == .spaces || self == .favoriteTabs
    }

    var section: Section {
        switch self {
        case .windowControls, .navigation, .page, .commandLens, .floatingTabs, .desk, .spaces, .favoriteTabs: .main
        case .reload, .copyLink, .favorites, .history, .downloads, .bookmarks, .settings, .recentTabs, .updates: .additional
        }
    }

    /// Shown before anyone customizes the rail. The update badge is on by default because it
    /// occupies the rail only while an update is ready.
    var isDefault: Bool {
        section == .main || self == .updates
    }
}
