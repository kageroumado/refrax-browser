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

    /// A reference pane tab to switch to.
    ///
    /// When selected, opens the reference pane (if closed) and activates the tab.
    ///
    /// - Parameter tabID: The unique identifier of the reference tab.
    case referenceTab(tabID: UUID)

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

    /// An AI query to send to the agent chat system.
    ///
    /// When selected, activates AI mode and sends the query through
    /// `AgentChatManager` for streaming response.
    case askAI

    /// An app-level action (feedback, update check, etc.)
    ///
    /// Used by `ActionsProvider` for browser-level operations that aren't
    /// navigation, search, or settings toggles.
    case appAction(AppAction)
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
}

/// Scope of a setting (global or per-site).
enum SettingScope: Hashable, Sendable {
    /// Applies to all websites.
    case global

    /// Applies to a specific domain.
    case perSite(domain: String)
}
