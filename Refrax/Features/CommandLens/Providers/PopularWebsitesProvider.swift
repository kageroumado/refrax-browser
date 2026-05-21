import Foundation

/// Provides suggestions from a curated list of popular websites.
///
/// Acts as a fallback when the user's browsing history doesn't have enough
/// matches for a query. Only shown when ``FrequentDestinationsCache`` returns
/// fewer than 3 results, ensuring personal history is always prioritized.
struct PopularWebsitesProvider: CommandLensSuggestionProvider {
    let id = "popular-websites"
    let priority = 175
    let groupHeader: String? = "Suggested Sites"
    let maxSuggestions = 3

    private let frequentDestinations: FrequentDestinationsCache

    init(frequentDestinations: FrequentDestinationsCache) {
        self.frequentDestinations = frequentDestinations
    }

    func shouldProvide(for context: SuggestionContext) -> Bool {
        guard !context.isEmptyInput else { return false }
        guard !context.isDirectURL else { return false }
        guard context.selectedSearchEngine == nil else { return false }
        return true
    }

    func suggestions(for context: SuggestionContext) async -> [CommandLensSuggestion] {
        let historyMatches = frequentDestinations.search(query: context.input)
        guard historyMatches.count < 3 else { return [] }

        let websites = PopularWebsitesService.search(query: context.input, limit: maxSuggestions)

        return websites.compactMap { website in
            guard let url = URL(string: "https://\(website.domain)") else { return nil }

            return CommandLensSuggestion(
                type: .url,
                text: website.name,
                description: website.domain,
                iconName: "globe",
                groupHeader: groupHeader,
                isRemovable: false,
                keywordAction: nil,
                url: url,
            )
        }
    }
}
