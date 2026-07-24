import Foundation

/// Provides app-level action suggestions: Send Feedback and Check for Updates.
///
/// These are global actions not tied to any tab or page context.
/// Uses fuzzy matching against natural language terms so users can
/// discover actions by typing related words.
struct ActionsProvider: CommandLensSuggestionProvider {
    let id = "actions"
    let priority = 45
    let groupHeader: String? = "Actions"
    let maxSuggestions = 3

    func shouldProvide(for context: SuggestionContext) -> Bool {
        !context.isEmptyInput && !context.isDirectURL
    }

    func suggestions(for context: SuggestionContext) async -> [CommandLensSuggestion] {
        let query = context.input.lowercased()
        var results: [CommandLensSuggestion] = []

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
