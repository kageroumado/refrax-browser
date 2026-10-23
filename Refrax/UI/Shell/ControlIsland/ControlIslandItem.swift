import Foundation

/// The configurable actions and groups available in the control rail.
nonisolated enum ControlIslandItem: String, CaseIterable, Codable, Identifiable {
    case windowControls
    case navigation
    case floatingTabs
    case spaces
    case favoriteTabs
    case reload
    case copyLink
    case favorites
    case history
    case bookmarks
    case settings
    /// Media playing in any tab, with a popover of per-tab controls. On the rail only while something plays.
    case nowPlaying
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
        .windowControls, .navigation, .page, .floatingTabs, .spaces, .favoriteTabs,
        .reload, .copyLink, .favorites, .history, .bookmarks, .settings, .nowPlaying, .updates,
    ]

    var title: String {
        switch self {
        case .windowControls: "Window controls"
        case .navigation: "Back and Forward"
        case .page: "Current page"
        case .copyLink: "Copy Link"
        case .floatingTabs: "Islands"
        case .spaces: "Spaces"
        case .favoriteTabs: "Favorite tabs"
        case .reload: "Reload"
        case .favorites: "Favorites"
        case .history: "History"
        case .bookmarks: "Bookmarks"
        case .settings: "Settings"
        case .nowPlaying: "Now Playing"
        case .updates: "Update ready"
        }
    }

    var symbol: String {
        switch self {
        case .windowControls: "ellipsis.circle"
        case .navigation: "chevron.left.forwardslash.chevron.right"
        case .page: "globe"
        case .copyLink: "link"
        case .floatingTabs: "square.on.square"
        case .spaces: "square.stack"
        case .favoriteTabs: "star.square.on.square"
        case .reload: "arrow.clockwise"
        case .favorites: "star"
        case .history: "clock"
        case .bookmarks: "bookmark"
        case .settings: "gearshape"
        case .nowPlaying: "speaker.wave.2"
        case .updates: "arrow.down.circle.fill"
        }
    }

    var detail: String {
        switch self {
        case .windowControls: "Close, minimize, and full screen"
        case .navigation: "One row; Forward appears when available · ⌥-click shows history"
        case .page: "The page's icon; hover it for the page card with address, reload, favorite, and actions"
        case .copyLink: "Copy the page address"
        case .floatingTabs: "Show your islands · hold ⌥ for Recent tabs"
        case .spaces: "Grouped space icons with the current space selected"
        case .favoriteTabs: "Favorites as a column of site icons, with the rest a click away"
        case .reload: "Reload the page or stop loading · ⌘R"
        case .favorites: "Open all your favorites"
        case .history: "Browse visited pages"
        case .bookmarks: "Manage saved pages and favorites"
        case .settings: "Open browser settings · ⌘,"
        case .nowPlaying: "Play, pause, and mute the tabs playing sound · ⌃M mutes this tab; on the rail only while something plays"
        case .updates: "Restart to install a downloaded update; on the rail only while one is ready"
        }
    }

    var isGroup: Bool {
        self == .windowControls || self == .spaces || self == .favoriteTabs
    }

    var section: Section {
        switch self {
        case .windowControls, .navigation, .page, .floatingTabs, .spaces, .favoriteTabs: .main
        case .reload, .copyLink, .favorites, .history, .bookmarks, .settings, .nowPlaying, .updates: .additional
        }
    }

    /// Shown before anyone customizes the rail. Now Playing and the update badge are on by
    /// default because they occupy the rail only while something plays or an update is ready.
    var isDefault: Bool {
        section == .main || isConditional
    }

    /// On the rail only while its subject exists, so it costs no height the rest of the time.
    var isConditional: Bool {
        self == .nowPlaying || self == .updates
    }
}
