import Foundation

/// Provides app-level action suggestions.
///
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
                groupHeader: groupHeader,
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            ))
        }

        return results
    }
}
