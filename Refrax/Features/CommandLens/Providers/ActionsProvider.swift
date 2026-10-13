import Foundation

/// Provides app-level action suggestions: Send Feedback, open Passwords,
/// Import from Another Browser, and Check for Updates.
///
/// These are global actions not tied to any tab or page context.
/// Uses fuzzy matching against natural language terms so users can
/// discover actions by typing related words.
struct ActionsProvider: CommandLensSuggestionProvider {
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
            ("mute this tab silence sound quiet audio", "Mute This Tab", "speaker.slash", .setCurrentTabMuted(true)),
            ("unmute this tab sound audio", "Unmute This Tab", "speaker.wave.2", .setCurrentTabMuted(false)),
            ("mute other tabs silence everything else", "Mute Other Tabs", "speaker.slash", .muteOtherTabs),
        ]
        for (terms, title, icon, action) in pageActions where FuzzyMatcher.match(query: query, against: [terms]) >= FuzzyMatcher.minimumMatchScore {
            let description = switch action {
            case .setCurrentTabMuted: "Current tab  ⌃M"
            case .muteOtherTabs: "Silence every other tab"
            default: "Current page"
            }
            results.append(CommandLensSuggestion(
                type: .appAction(action),
                text: title,
                description: description,
                iconName: icon,
                groupHeader: groupHeader,
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            ))
        }

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

        // Arrange the floating tabs
        let arrangements: [(String, FloatingArrangement, String)] = [
            ("arrange grid tidy tabs lay out columns", .grid, "Every card in columns from the island's side"),
            ("stack by site stacks domain sweep tabs", .stacksBySite, "One stack per site, named by the site"),
            ("stack by group stacks fold groups", .stacksByGroup, "Every group folded to its header"),
        ]
        for (terms, arrangement, description) in arrangements
            where FuzzyMatcher.match(query: query, against: [terms, arrangement.commandTitle.lowercased()]) >= FuzzyMatcher.minimumMatchScore {
            results.append(CommandLensSuggestion(
                type: .appAction(.arrange(arrangement)),
                text: arrangement.commandTitle,
                description: description,
                iconName: arrangement.symbol,
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
}
