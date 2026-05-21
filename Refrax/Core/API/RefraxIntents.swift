import AppIntents
import AppKit

// MARK: - App Delegate Access

/// Helper to access the app delegate from App Intents.
@MainActor
private var currentAppDelegate: AppDelegate {
    NSApplication.shared.typedDelegate
}

// MARK: - Open URL Intent

/// Opens a URL in Refrax browser.
///
/// Can open in a new tab or navigate the current tab.
struct OpenURLIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Open URL in Refrax"
    nonisolated static let description = IntentDescription("Opens a URL in Refrax browser")

    @Parameter(title: "URL")
    var url: URL

    @Parameter(title: "In New Tab", default: true)
    var newTab: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        let appDelegate = currentAppDelegate

        if newTab {
            // Get active space or first space
            let windowState = appDelegate.windowManager.activeWindowController?.windowState
            let spaceID = windowState?.activeSpaceID ?? appDelegate.browserState.spaces.first?.id
            guard let space = spaceID.flatMap({ appDelegate.browserState.space(for: $0) }) else {
                throw IntentError.noActiveSpace
            }

            appDelegate.tabManager.createTab(url: url, in: space, makeActive: true)
        } else {
            // Navigate current tab
            if let windowState = appDelegate.windowManager.activeWindowController?.windowState,
               let spaceID = windowState.activeSpaceID,
               let tabID = windowState.activeTabID(for: spaceID),
               let tab = appDelegate.browserState.tab(for: tabID),
               let page = appDelegate.pagePool.existingPage(for: tab.activePage) {
                _ = page.load(url)
            } else {
                throw IntentError.noActiveTab
            }
        }

        NSApp.activate(ignoringOtherApps: true)
        return .result()
    }
}

// MARK: - Create Tab Intent

/// Creates a new tab in Refrax.
///
/// Optionally opens a URL and can target a specific space by name.
struct CreateTabIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Create New Tab"
    nonisolated static let description = IntentDescription("Creates a new tab in Refrax browser")

    @Parameter(title: "URL")
    var url: URL?

    @Parameter(title: "Space Name")
    var spaceName: String?

    @MainActor
    func perform() async throws -> some IntentResult {
        let appDelegate = currentAppDelegate

        // Find target space
        let space: Space
        if let name = spaceName {
            guard let found = appDelegate.browserState.spaces.first(where: {
                $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame
            }) else {
                throw IntentError.spaceNotFound(name)
            }
            space = found
        } else {
            // Use active space
            let windowState = appDelegate.windowManager.activeWindowController?.windowState
            let spaceID = windowState?.activeSpaceID ?? appDelegate.browserState.spaces.first?.id
            guard let found = spaceID.flatMap({ appDelegate.browserState.space(for: $0) }) else {
                throw IntentError.noActiveSpace
            }
            space = found
        }

        // Switch to space if needed
        if let windowState = appDelegate.windowManager.activeWindowController?.windowState,
           windowState.activeSpaceID != space.id {
            appDelegate.spaceManager.switchToSpaceSync(space, for: windowState)
        }

        appDelegate.tabManager.createTab(url: url ?? .blank, in: space, makeActive: true)
        NSApp.activate(ignoringOtherApps: true)

        return .result()
    }
}

// MARK: - Switch Space Intent

/// Switches to a space by name.
struct SwitchSpaceIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Switch Space"
    nonisolated static let description = IntentDescription("Switches to a different space in Refrax")

    @Parameter(title: "Space Name")
    var spaceName: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let appDelegate = currentAppDelegate

        guard let space = appDelegate.browserState.spaces.first(where: {
            $0.name.localizedCaseInsensitiveContains(spaceName)
        }) else {
            throw IntentError.spaceNotFound(spaceName)
        }

        guard let windowState = appDelegate.windowManager.activeWindowController?.windowState else {
            throw IntentError.noActiveWindow
        }

        // Check if space is locked
        if appDelegate.browserState.spaceLockManager.requiresAuth(for: space) {
            throw IntentError.spaceLocked(space.name)
        }

        appDelegate.spaceManager.switchToSpaceSync(space, for: windowState)
        NSApp.activate(ignoringOtherApps: true)

        return .result()
    }
}

// MARK: - Search Intent

/// Performs a search or opens Command Lens with a query.
struct SearchIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Search in Refrax"
    nonisolated static let description = IntentDescription("Performs a search using the default search engine")

    @Parameter(title: "Query")
    var query: String

    @MainActor
    func perform() async throws -> some IntentResult {
        let appDelegate = currentAppDelegate

        // Build search URL
        let searchEngine = appDelegate.settings.defaultSearchEngine
        guard let searchURL = searchEngine.searchURL(for: query) else {
            throw IntentError.invalidQuery
        }

        // Get active space
        let windowState = appDelegate.windowManager.activeWindowController?.windowState
        let spaceID = windowState?.activeSpaceID ?? appDelegate.browserState.spaces.first?.id
        guard let space = spaceID.flatMap({ appDelegate.browserState.space(for: $0) }) else {
            throw IntentError.noActiveSpace
        }

        appDelegate.tabManager.createTab(url: searchURL, in: space, makeActive: true)
        NSApp.activate(ignoringOtherApps: true)

        return .result()
    }
}

// MARK: - Get Current URL Intent

/// Returns the URL of the active tab.
struct GetCurrentURLIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Get Current URL"
    nonisolated static let description = IntentDescription("Returns the URL of the currently active tab")

    @MainActor
    func perform() async throws -> some ReturnsValue<URL?> {
        let appDelegate = currentAppDelegate

        guard let windowState = appDelegate.windowManager.activeWindowController?.windowState,
              let spaceID = windowState.activeSpaceID,
              let tabID = windowState.activeTabID(for: spaceID),
              let tab = appDelegate.browserState.tab(for: tabID)
        else {
            return .result(value: nil)
        }

        return .result(value: tab.activePage.url)
    }
}

// MARK: - Get Tab List Intent

/// Returns a list of open tabs.
struct GetTabListIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Get Tab List"
    nonisolated static let description = IntentDescription("Returns a list of all open tabs")

    @Parameter(title: "Space Name")
    var spaceName: String?

    @MainActor
    func perform() async throws -> some ReturnsValue<[String]> {
        let appDelegate = currentAppDelegate

        var tabs: [Tab] = []

        if let name = spaceName {
            // Filter to specific space
            guard let space = appDelegate.browserState.spaces.first(where: {
                $0.name.localizedCaseInsensitiveContains(name)
            }) else {
                throw IntentError.spaceNotFound(name)
            }
            tabs = space.mainTabs
        } else {
            // All tabs from all spaces
            for space in appDelegate.browserState.spaces {
                tabs.append(contentsOf: space.mainTabs)
            }
        }

        let descriptions = tabs.map { tab in
            "\(tab.displayTitle) - \(tab.activePage.url.absoluteString)"
        }

        return .result(value: descriptions)
    }
}

// MARK: - Close Tab Intent

/// Closes the active tab.
struct CloseTabIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Close Tab"
    nonisolated static let description = IntentDescription("Closes the currently active tab")

    @MainActor
    func perform() async throws -> some IntentResult {
        let appDelegate = currentAppDelegate

        guard let windowState = appDelegate.windowManager.activeWindowController?.windowState,
              let spaceID = windowState.activeSpaceID,
              let tabID = windowState.activeTabID(for: spaceID),
              let tab = appDelegate.browserState.tab(for: tabID)
        else {
            throw IntentError.noActiveTab
        }

        appDelegate.tabManager.closeTab(tab)
        return .result()
    }
}

// MARK: - Reload Tab Intent

/// Reloads the active tab.
struct ReloadTabIntent: AppIntent {
    nonisolated static let title: LocalizedStringResource = "Reload Tab"
    nonisolated static let description = IntentDescription("Reloads the currently active tab")

    @Parameter(title: "Bypass Cache", default: false)
    var bypassCache: Bool

    @MainActor
    func perform() async throws -> some IntentResult {
        let appDelegate = currentAppDelegate

        guard let windowState = appDelegate.windowManager.activeWindowController?.windowState,
              let spaceID = windowState.activeSpaceID,
              let tabID = windowState.activeTabID(for: spaceID),
              let tab = appDelegate.browserState.tab(for: tabID),
              let page = appDelegate.pagePool.existingPage(for: tab.activePage)
        else {
            throw IntentError.noActiveTab
        }

        _ = page.reload(fromOrigin: bypassCache)
        return .result()
    }
}

// MARK: - Intent Errors

/// Errors that can occur during intent execution.
enum IntentError: Error, CustomLocalizedStringResourceConvertible {
    case noActiveWindow
    case noActiveSpace
    case noActiveTab
    case spaceNotFound(String)
    case spaceLocked(String)
    case invalidQuery

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noActiveWindow:
            "No active Refrax window"
        case .noActiveSpace:
            "No active space"
        case .noActiveTab:
            "No active tab"
        case let .spaceNotFound(name):
            "Space '\(name)' not found"
        case let .spaceLocked(name):
            "Space '\(name)' is locked"
        case .invalidQuery:
            "Invalid search query"
        }
    }
}

// MARK: - App Shortcuts Provider

/// Provides app shortcuts for the Shortcuts app.
///
/// These shortcuts appear in the Shortcuts app with suggested phrases
/// for Siri and Spotlight.
///
/// Note: Uses fully qualified name to avoid conflict with Refrax.AppShortcut model.
struct RefraxShortcuts: AppShortcutsProvider {
    @AppShortcutsBuilder
    static var appShortcuts: [AppIntents.AppShortcut] {
        AppIntents.AppShortcut(
            intent: OpenURLIntent(),
            phrases: [
                "Open URL in \(.applicationName)",
            ],
            shortTitle: "Open URL",
            systemImageName: "link",
        )
        AppIntents.AppShortcut(
            intent: CreateTabIntent(),
            phrases: [
                "Create new tab in \(.applicationName)",
            ],
            shortTitle: "New Tab",
            systemImageName: "plus.square",
        )
        AppIntents.AppShortcut(
            intent: SearchIntent(),
            phrases: [
                "Search in \(.applicationName)",
            ],
            shortTitle: "Search",
            systemImageName: "magnifyingglass",
        )
        AppIntents.AppShortcut(
            intent: SwitchSpaceIntent(),
            phrases: [
                "Switch space in \(.applicationName)",
            ],
            shortTitle: "Switch Space",
            systemImageName: "square.stack",
        )
        AppIntents.AppShortcut(
            intent: GetCurrentURLIntent(),
            phrases: [
                "Get current URL from \(.applicationName)",
            ],
            shortTitle: "Get URL",
            systemImageName: "doc.on.clipboard",
        )
    }
}
