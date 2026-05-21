import Foundation

/// Provides search suggestions from the network via the search engine's API.
///
/// This provider fetches autocomplete suggestions from the user's selected
/// search engine (Google, DuckDuckGo, Bing, etc.). It has the lowest priority
/// since network requests are slower than local lookups.
///
/// Network requests are debounced by the manager to avoid excessive API calls.
struct NetworkSearchProvider: CommandLensSuggestionProvider {
    let id = "search-network"
    let priority = 300
    let groupHeader: String? = "Search Suggestions"
    let maxSuggestions = 8

    private let searchService: SearchSuggestionService

    init(searchService: SearchSuggestionService = SearchSuggestionService()) {
        self.searchService = searchService
    }

    func shouldProvide(for context: SuggestionContext) -> Bool {
        // Don't fetch for direct URLs
        guard !context.isDirectURL else { return false }

        // Don't fetch for empty input
        return !context.isEmptyInput
    }

    func suggestions(for context: SuggestionContext) async -> [CommandLensSuggestion] {
        let searchEngine = context.selectedSearchEngine ?? context.settings.defaultSearchEngine

        let suggestions = await searchService.fetchSuggestions(
            for: context.input,
            searchEngine: searchEngine,
        )

        return Array(suggestions.prefix(maxSuggestions)).map { suggestion in
            suggestion.withGroupHeader(groupHeader ?? "Search Suggestions")
        }
    }
}
