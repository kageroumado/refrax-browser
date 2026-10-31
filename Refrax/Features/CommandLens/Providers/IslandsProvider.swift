import Foundation

/// The islands' own commands: the quick filters and showing every tab again, the archive in
/// the library drawer, and moving through the rows with the keyboard.
struct IslandsProvider: CommandLensSuggestionProvider {
    weak var windowState: WindowState?

    let id = "islands"
    let priority = 44
    let groupHeader: String? = "Islands"
    let maxSuggestions = 4

    func shouldProvide(for context: SuggestionContext) -> Bool {
        !context.isEmptyInput && !context.isDirectURL
    }

    func suggestions(for context: SuggestionContext) async -> [CommandLensSuggestion] {
        guard let windowState, let islands = windowState.islandController else { return [] }
        let query = context.input.lowercased()
        func matches(_ terms: [String]) -> Bool {
            FuzzyMatcher.match(query: query, against: terms) >= FuzzyMatcher.minimumMatchScore
        }
        func suggestion(_ action: AppAction, _ title: String, _ description: String, _ icon: String) -> CommandLensSuggestion {
            CommandLensSuggestion(
                type: .appAction(action), text: title, description: description, iconName: icon, groupHeader: groupHeader,
                isRemovable: false, keywordAction: nil, url: nil,
            )
        }
        var results: [CommandLensSuggestion] = []
        for filter in IslandFilter.allCases where islands.filter != filter && matches(filter.terms) {
            results.append(suggestion(.filterIslands(filter), "Show \(filter.title)", "Only these keep their rows on the islands", filter.symbol))
        }
        if islands.filter != nil, matches(["show all tabs", "all tabs", "clear filter", "remove filter", "unfilter"]) {
            results.append(suggestion(.filterIslands(nil), "Show All Tabs", "Every tab's row comes back", "line.3.horizontal.decrease.circle"))
        }
        if matches(["archive", "archived tabs", "show archive", "open archive", "empty archive", "restore archived"]) {
            results.append(suggestion(.showArchive, "Show Archive", "Archived tabs in the library drawer", "archivebox"))
        }
        if islands.currentTab != nil, matches(["browse tabs", "keyboard", "move through tabs", "choose tab with keyboard", "tab list", "go to tab"]) {
            results.append(suggestion(.browseIslands, "Browse Tabs with the Keyboard", "↑↓ choose · ←→ islands · Return opens · Esc leaves", "keyboard"))
        }
        return results
    }
}
