import Foundation

/// Provides action suggestions: the current page's verbs (favorite, move to a space or a new
/// window), New Space, Send Feedback, open Passwords, Import from Another Browser, and Check
/// for Updates.
///
/// Uses fuzzy matching against natural language terms so users can
/// discover actions by typing related words.
struct ActionsProvider: CommandLensSuggestionProvider {
    let tabs: TabManager
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
        var results = everydaySuggestions(for: query)

        let favorite: (String, String, String, AppAction) = if windowState?.activeTab?.isFavorite == true {
            ("remove from favorites unfavorite unstar", "Remove from Favorites", "star.slash", .favoriteCurrentPage)
        } else {
            ("favorite current page star add to favorites every space", "Favorite", "star", .favoriteCurrentPage)
        }
        var pageActions: [(String, String, String, AppAction)] = []
        if let tab = windowState?.activeTab, !tab.isFavorite, tab.space != nil {
            pageActions.append(
                tab.isPinned
                    ? ("unpin tab remove pin forget home", "Unpin Tab", "pin.slash", .pinCurrentTab)
                    : ("pin tab keep home address stay", "Pin Tab", "pin", .pinCurrentTab),
            )
        }
        pageActions += [
            favorite,
            ("return look go back activity", "Return to Activity", "arrow.uturn.backward", .returnFromLook),
            ("keep part visible crop region", "Keep Part Visible…", "crop", .keepPartVisible),
            ("mute this tab silence sound quiet audio", "Mute This Tab", "speaker.slash", .setCurrentTabMuted(true)),
            ("unmute this tab sound audio", "Unmute This Tab", "speaker.wave.2", .setCurrentTabMuted(false)),
            ("mute other tabs silence everything else", "Mute Other Tabs", "speaker.slash", .muteOtherTabs),
        ]
        for (terms, title, icon, action) in pageActions where FuzzyMatcher.match(query: query, against: [terms]) >= FuzzyMatcher.minimumMatchScore {
            let description = switch action {
            case .setCurrentTabMuted: "Current tab  ⌃M"
            case .pinCurrentTab: "Current tab  ⌘D"
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

        // Show or hide the islands
        let islandsTerms = [
            "show islands", "hide islands", "islands", "all tabs", "show all tabs", "tab list", "sidebar", "tab overview",
            "overview", "see all tabs", "floating tabs",
        ]
        if FuzzyMatcher.match(query: query, against: islandsTerms) >= FuzzyMatcher.minimumMatchScore {
            let canvas = (windowState?.window?.windowController as? RefraxWindowController)?.tabCanvasManager
            results.append(CommandLensSuggestion(
                type: .appAction(.toggleTabCanvas),
                text: canvas?.floatingVisibility.isLatched == true ? "Hide Islands" : "Show Islands",
                description: "The tabs of this space, over the page  ⌘S",
                iconName: ControlIslandItem.floatingTabs.symbol,
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

    /// "switch to <space>", "move to <space>", "move to new window", and "new space".
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
        // A locked space's name stays out of the suggestions until it is unlocked.
        let lock = tabs.state.spaceLockManager
        if let windowState {
            for (index, space) in tabs.spaceManager.spaces.enumerated()
                where space.id != windowState.activeSpaceID && !lock.requiresAuth(for: space) {
                let name = space.name.lowercased()
                if matches(["switch to \(name)", "go to \(name)", "\(name) space", "space \(name)"]) {
                    let key = NumberKey.space(at: index).map { "  \($0)" } ?? ""
                    results.append(suggestion(.switchToSpace(space.id), "Switch to \(space.name)", "Space\(key)", "square.stack"))
                }
            }
        }
        if let tab = windowState?.activeTab, !tab.isFavorite, let current = tab.space, !lock.requiresAuth(for: current) {
            for space in tabs.spaceManager.spaces where space.id != current.id && !lock.requiresAuth(for: space) {
                let name = space.name.lowercased()
                if matches(["move to \(name)", "move tab to \(name)", "send to \(name)"]) {
                    results.append(suggestion(.moveCurrentTabToSpace(space.id), "Move to \(space.name)", "Current page", "square.stack.3d.up"))
                }
            }
            if matches(["move to new window", "move tab to new window", "tear off tab", "own window"]) {
                results.append(suggestion(.moveCurrentTabToNewWindow, "Move to New Window", "Current page  ⌥⇧⌘N", "macwindow.badge.plus"))
            }
        }
        results += dockSuggestions(matching: matches, suggestion: suggestion)
        results += tableSuggestions(for: query, matching: matches, suggestion: suggestion)
        results += paneSuggestions(matching: matches, suggestion: suggestion)
        if matches(["new space", "create space", "add space"]) {
            results.append(suggestion(.newSpace, "New Space…", "A place for its own set of tabs  ⌃⌘N", "plus.square.on.square"))
        }
        return results
    }

    /// Dock the current page to a side, and Undock for each side that holds a page.
    private func dockSuggestions(
        matching matches: ([String]) -> Bool,
        suggestion: (AppAction, String, String, String) -> CommandLensSuggestion,
    ) -> [CommandLensSuggestion] {
        guard let windowState, windowState.activeTab != nil,
              let canvas = (windowState.window?.windowController as? RefraxWindowController)?.tabCanvasManager else { return [] }
        var results: [CommandLensSuggestion] = []
        for edge in FloatingDockEdge.allCases {
            let side = edge.title.lowercased()
            let key = edge == .leading ? "⌃⌥←" : "⌃⌥→"
            if matches(["dock \(side)", "dock page \(side)", "dock to \(side)", "side by side \(side)", "tile \(side)", "reference \(side)"]) {
                let symbol = edge == .leading ? "rectangle.lefthalf.inset.filled" : "rectangle.righthalf.inset.filled"
                results.append(suggestion(.dockCurrentPage(edge), "Dock \(edge.title)", "Current page  \(key)", symbol))
            }
            if let docked = canvas.dockedTab(on: edge), matches(["undock", "undock \(side)", "undock page"]) {
                results.append(suggestion(.undockPage(edge), "Undock \(docked.displayTitle)", "Docked \(side)", "arrow.uturn.backward"))
            }
        }
        return results
    }
}
