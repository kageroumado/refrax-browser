import Foundation

/// Provides async search suggestion fetching for various search engines.
/// Builds the appropriate URL for each provider, performs the network call,
/// and parses responses into a unified list of `CommandLensSuggestion`s.
final class SearchSuggestionService: Sendable {
    private let session = URLSession.shared
    
    /// Fetches suggestions for the given query from the selected engine.
    /// Cancels silently on error or empty input. Uses the correct API format
    /// per engine (DuckDuckGo, Google, Bing) and returns parsed suggestions.
    func fetchSuggestions(for query: String, searchEngine: SearchEngine) async -> [CommandLensSuggestion] {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return [] }

        // Build URL via parser + template
        let parser = searchEngine.suggestionParser
        guard let url = parser.buildURL(for: query, template: searchEngine.suggestionURLTemplate) else {
            return []
        }

        do {
            let (data, _) = try await session.data(from: url)
            let phrases = parser.parse(data) ?? []

            // Filter out suggestions that match the query exactly (search APIs often echo the query)
            let lowercaseQuery = query.lowercased()
            return phrases
                .filter { $0.lowercased() != lowercaseQuery }
                .map { phrase in
                    CommandLensSuggestion(
                        type: .search,
                        text: phrase,
                        description: "",
                        iconName: "magnifyingglass",
                        groupHeader: "Search Suggestions",
                        isRemovable: false,
                        keywordAction: nil,
                        url: nil,
                    )
                }
        } catch {
            return []
        }
    }
}
