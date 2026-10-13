import Foundation

/// Provides action suggestions: the current page's verbs (favorite, move to a space or a new
/// window), New Space, Send Feedback, open Passwords, Import from Another Browser, and Check
/// for Updates.
///
/// Uses fuzzy matching against natural language terms so users can
/// discover actions by typing related words.
struct ActionsProvider: CommandLensSuggestionProvider {
    let spaces: SpaceManager
    weak var windowState: WindowState?

    let id = "actions"
    let priority = 45
    let groupHeader: String? = "Actions"
    let maxSuggestions = 4

    func shouldProvide(for context: SuggestionContext) -> Bool {
        !context.isEmptyInput && !context.isDirectURL
    }

    func suggestions(for context: SuggestionContext) async -> [CommandLensSuggestion] {
        let query = context.input.lowercased()
        var results: [CommandLensSuggestion] = []

        let pageActions: [(String, String, String, AppAction)] = [
            ("favorite current page", "Favorite Current Page", "star", .favoriteCurrentPage),
            ("return look go back activity", "Return to Activity", "arrow.uturn.backward", .returnFromLook),
            ("keep part visible crop region", "Keep Part Visible…", "crop", .keepPartVisible),
        ]
        for (terms, title, icon, action) in pageActions where FuzzyMatcher.match(query: query, against: [terms]) >= FuzzyMatcher.minimumMatchScore {
            results.append(CommandLensSuggestion(
                type: .appAction(action),
                text: title,
                description: "Current page",
                iconName: icon,
                groupHeader: groupHeader,
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            ))
        }
        results += tabPlacementSuggestions(for: query)

        // Feedback is always shown when user has typed anything
        results.append(CommandLensSuggestion(
            type: .appAction(.feedback),
            text: "Send Feedback",
            description: "Report bugs, suggest features, or share thoughts",
            iconName: "envelope",
            groupHeader: groupHeader,
            isRemovable: false,
            keywordAction: nil,
            url: nil,
        ))

        // Open Passwords window
        let passwordTerms = [
            "passwords", "password", "saved passwords", "logins", "login",
            "credentials", "keychain", "my passwords", "view passwords",
            "manage passwords", "autofill passwords",
        ]
        let passwordScore = FuzzyMatcher.match(query: query, against: passwordTerms)

        if passwordScore >= FuzzyMatcher.minimumMatchScore {
            results.append(CommandLensSuggestion(
                type: .appAction(.openPasswords),
                text: "Passwords",
                description: "View and manage your saved passwords",
                iconName: "key.fill",
                groupHeader: nil,
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            ))
        }

        // Local Devices window
        let localDevicesTerms = [
            "local devices", "devices", "network map", "local network", "lan",
            "network", "bonjour", "my devices", "smart home", "iot",
        ]
        let localDevicesScore = FuzzyMatcher.match(query: query, against: localDevicesTerms)

        if localDevicesScore >= FuzzyMatcher.minimumMatchScore {
            results.append(CommandLensSuggestion(
                type: .appAction(.openLocalDevices),
                text: "Local Devices",
                description: "Map of your router and the devices around it",
                iconName: "network",
                groupHeader: nil,
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            ))
        }

        // Tab Canvas
        let canvasTerms = [
            "canvas", "tab canvas", "desk", "all tabs", "show all tabs", "tab overview",
            "overview", "board", "spatial", "zoom out", "see all tabs",
        ]
        if FuzzyMatcher.match(query: query, against: canvasTerms) >= FuzzyMatcher.minimumMatchScore {
            results.append(CommandLensSuggestion(
                type: .appAction(.toggleTabCanvas),
                text: "Tab Canvas",
                description: "Every tab of this space on one desk  ⌘⇧\\",
                iconName: TabCanvasManager.symbolName,
                groupHeader: nil,
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            ))
        }

        // Import from Another Browser
        let importTerms = [
            "import", "import browser", "import bookmarks", "import passwords",
            "import history", "migrate", "switch browser", "from chrome",
            "from safari", "from firefox", "from brave", "from arc",
        ]
        let importScore = FuzzyMatcher.match(query: query, against: importTerms)

        if importScore >= FuzzyMatcher.minimumMatchScore {
            results.append(CommandLensSuggestion(
                type: .appAction(.importBrowserData),
                text: "Import from Another Browser",
                description: "Import bookmarks, history, and passwords",
                iconName: "square.and.arrow.down",
                groupHeader: nil,
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            ))
        }

        // Check for Updates
        let updateTerms = [
            "update", "check for updates", "version", "upgrade",
            "new version",
        ]
        let updateScore = FuzzyMatcher.match(query: query, against: updateTerms)

        if updateScore >= FuzzyMatcher.minimumMatchScore {
            results.append(CommandLensSuggestion(
                type: .appAction(.checkForUpdates),
                text: "Check for Updates",
                description: "Check if a newer version is available",
                iconName: "arrow.triangle.2.circlepath",
                groupHeader: nil,
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            ))
        }

        return results
    }

    /// "move to <space>", "move to new window", and "new space".
    private func tabPlacementSuggestions(for query: String) -> [CommandLensSuggestion] {
        func matches(_ terms: [String]) -> Bool {
            FuzzyMatcher.match(query: query, against: terms) >= FuzzyMatcher.minimumMatchScore
        }
        func suggestion(_ action: AppAction, _ title: String, _ description: String, _ icon: String) -> CommandLensSuggestion {
            CommandLensSuggestion(
                type: .appAction(action),
                text: title,
                description: description,
                iconName: icon,
                groupHeader: groupHeader,
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            )
        }

        var results: [CommandLensSuggestion] = []
        if let tab = windowState?.activeTab, !tab.isLiveFavorite, let current = tab.space {
            for space in spaces.spaces where space.id != current.id {
                let name = space.name.lowercased()
                if matches(["move to \(name)", "move tab to \(name)", "send to \(name)"]) {
                    results.append(suggestion(.moveCurrentTabToSpace(space.id), "Move to \(space.name)", "Current page", "square.stack.3d.up"))
                }
            }
            if matches(["move to new window", "move tab to new window", "tear off tab", "own window"]) {
                results.append(suggestion(.moveCurrentTabToNewWindow, "Move to New Window", "Current page  ⌥⌘N", "macwindow.badge.plus"))
            }
        }
        if matches(["new space", "create space", "add space"]) {
            results.append(suggestion(.newSpace, "New Space…", "A place for its own set of tabs  ⌃⌘N", "plus.square.on.square"))
        }
        return results
    }
}
