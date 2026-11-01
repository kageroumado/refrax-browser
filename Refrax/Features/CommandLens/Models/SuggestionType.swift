import Foundation

/// Categorizes CommandLens suggestions by their source and behavior.
///
/// Each type determines:
/// - How the suggestion is displayed (icon, layout)
/// - What happens when the user selects it
/// - Whether additional actions are available (e.g., tab switching)
enum SuggestionType: Hashable, Sendable {
    /// A search query to execute with the current search engine.
    case search

    /// A URL from history or bookmarks to navigate to.
    case url

    /// An already-open tab to switch to.
    ///
    /// - Parameter tabID: The unique identifier of the open tab.
    case openTab(tabID: UUID)

    /// An archived tab to restore to its space and open.
    ///
    /// - Parameter tabID: The unique identifier of the archived tab.
    case archivedTab(tabID: UUID)

    /// A search engine to switch to before searching.
    ///
    /// - Parameter engine: The search engine to activate.
    case searchProvider(SearchEngine)

    /// A rich entity (e.g., knowledge panel) with preview image.
    ///
    /// - Parameter imageUrl: URL of the entity's preview image.
    case richEntity(imageUrl: URL)

    /// A recently closed tab to reopen.
    ///
    /// - Parameter index: Index in the recently closed tabs list.
    case recentlyClosed(index: Int)

    /// A browser or site setting that can be toggled or adjusted.
    ///
    /// - Parameters:
    ///   - key: The setting identifier for lookup and modification.
    ///   - scope: Whether this is a global or per-site setting.
    case setting(key: String, scope: SettingScope)

    /// A downloaded file from the downloads list.
    ///
    /// When selected, reveals the file in Finder (for completed downloads)
    /// or shows the download in progress.
    ///
    /// - Parameters:
    ///   - fileURL: The file's location on disk.
    ///   - state: Current download state (for display).
    case download(fileURL: URL, state: DownloadState)

    /// An app-level action (feedback, update check, etc.)
    ///
    /// Used by `ActionsProvider` for browser-level operations that aren't
    /// navigation, search, or settings toggles.
    case appAction(AppAction)

    /// A device on the local network with a web interface.
    ///
    /// When selected, navigates to the device's URL like ``url``.
    ///
    /// - Parameter role: Whether the device is the default gateway or a Bonjour-advertised service.
    case localDevice(LocalDeviceRole)

    /// One of the tour's tutorial pages, offered first while a tour step asks for a page.
    ///
    /// When selected, opens the page as a tab of its own, like ``url``.
    case tutorialPage(FloatingTabsTutorial.Page)
}

/// What a local network device is to the user.
enum LocalDeviceRole: Hashable, Sendable {
    /// The router this Mac sends non-local traffic through.
    case gateway

    /// Any other device advertising a web interface over Bonjour.
    case service
}

/// App-level actions triggered from the Command Lens.
nonisolated enum AppAction: Hashable, Sendable {
    /// Open the feedback composition window.
    case feedback

    /// Check for application updates.
    case checkForUpdates

    /// Open the browser data import wizard.
    case importBrowserData

    /// Open the saved-passwords window.
    case openPasswords

    /// Open the Local Devices window.
    case openLocalDevices

    /// Show or hide the floating tabs in this window.
    case toggleTabCanvas
    case favoriteCurrentPage
    case returnFromLook
    case keepPartVisible
    /// Mute or unmute the current tab.
    case setCurrentTabMuted(Bool)
    /// Mute every other tab that plays sound.
    case muteOtherTabs
    /// Move the current page to the space with this identifier.
    case moveCurrentTabToSpace(UUID)
    /// Move the current page into a new window.
    case moveCurrentTabToNewWindow
    /// Dock the current page to a side of the window.
    case dockCurrentPage(FloatingDockEdge)
    /// Return the page docked to a side to its floating place.
    case undockPage(FloatingDockEdge)
    /// Open New Space beside the island's space picker.
    case newSpace
    /// Move around the table or reshape the current slab.
    case table(TableCommand)
    /// Edit, add to, or separate the current tab's panes.
    case panes(PaneCommand)
    /// Copy the current page's address, or its Markdown link.
    case copyCurrentAddress(asMarkdown: Bool)
    /// Download the PDF or image the current page shows.
    case downloadCurrentPage
    /// Save the current page to a file in a chosen format.
    case saveCurrentPageAs
    /// Open Settings, at `category` when one is given.
    case openSettings(SettingsCategory?)
    /// List this space's open tabs in the lens.
    case showOpenTabs
    /// Keep only the tabs a quick filter matches on the islands, or every tab with `nil`.
    case filterIslands(IslandFilter?)
    /// Open the archive in the library drawer.
    case showArchive
    /// Latch the islands open with the current row chosen, for the arrow keys.
    case browseIslands
}

/// Scope of a setting (global or per-site).
enum SettingScope: Hashable, Sendable {
    /// Applies to all websites.
    case global

    /// Applies to a specific domain.
    case perSite(domain: String)
}
