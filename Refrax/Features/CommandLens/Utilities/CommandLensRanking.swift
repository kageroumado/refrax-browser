import Foundation

/// The lens's rules for which provider rows an input keeps and which of them lead the list.
enum CommandLensRanking {
    /// Whether a row takes the person somewhere: a website, an open, archived, or recently closed
    /// tab, history, a bookmark, a local device, or a search. Address-shaped input lists only these.
    static func isNavigation(_ type: SuggestionType) -> Bool {
        switch type {
        case .search, .url, .openTab, .archivedTab, .recentlyClosed, .richEntity, .localDevice:
            true
        case .searchProvider, .setting, .download, .appAction, .tutorialPage:
            false
        }
    }

    /// Whether a row runs a command: an app action or a setting.
    static func isCommand(_ type: SuggestionType) -> Bool {
        switch type {
        case .appAction, .setting: true
        default: false
        }
    }

    /// Whether the typed text names a command's title outright: the same words in any case, a
    /// trailing ellipsis aside, one slip in a longer title, or all but its last two letters.
    ///
    /// "move to work" names Move to Work, "new space" names New Space…, "copy adress" names
    /// Copy Address; "copy" names none of them.
    static func isExactCommandMatch(query: String, title: String) -> Bool {
        let query = normalized(query)
        let title = normalized(title)
        guard !query.isEmpty, !title.isEmpty else { return false }
        if query == title {
            return true
        }
        if title.count >= Constants.slipMinimumLength,
           FuzzyMatcher.levenshteinDistance(query, title) <= 1 {
            return true
        }
        return title.hasPrefix(query)
            && query.count >= max(Constants.slipMinimumLength, title.count - Constants.unfinishedLetters)
    }

    /// Splits provider rows into the commands the typed text names outright, which lead the list
    /// above the web search, and everything else in its original order.
    static func partitionExactCommands(
        _ suggestions: [CommandLensSuggestion],
        query: String,
    ) -> (exact: [CommandLensSuggestion], rest: [CommandLensSuggestion]) {
        var exact: [CommandLensSuggestion] = []
        var rest: [CommandLensSuggestion] = []
        for suggestion in suggestions {
            if isCommand(suggestion.type), isExactCommandMatch(query: query, title: suggestion.text) {
                exact.append(suggestion.withGroupHeader(nil))
            } else {
                rest.append(suggestion)
            }
        }
        return (exact, rest)
    }

    /// Lowercased, with the trailing ellipsis gone and runs of whitespace as single spaces.
    private static func normalized(_ text: String) -> String {
        var text = text.lowercased()
        for ellipsis in ["…", "..."] where text.hasSuffix(ellipsis) {
            text.removeLast(ellipsis.count)
        }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    private enum Constants {
        /// The shortest title that tolerates a slip or an unfinished word.
        static let slipMinimumLength = 5
        /// How many letters a title may still lack and count as named.
        static let unfinishedLetters = 2
    }
}
