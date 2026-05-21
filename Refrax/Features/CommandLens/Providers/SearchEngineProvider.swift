import Foundation

/// Provides suggestions for switching to different search engines.
///
/// When the user types a search engine name or alias (e.g., "google", "bing", "yt"),
/// this provider suggests switching to that engine for the current query.
/// This allows quick access to both built-in and custom search providers.
struct SearchEngineProvider: CommandLensSuggestionProvider {
    let id = "search-engines"
    let priority = 75
    let groupHeader: String? = nil
    let maxSuggestions = 3

    private let customSearchEngineManager: CustomSearchEngineManager

    init(customSearchEngineManager: CustomSearchEngineManager) {
        self.customSearchEngineManager = customSearchEngineManager
    }

    func shouldProvide(for context: SuggestionContext) -> Bool {
        // Don't show when a search engine is already selected
        guard context.selectedSearchEngine == nil else { return false }

        // Don't show for direct URLs
        guard !context.isDirectURL else { return false }

        // Don't show for empty input
        return !context.isEmptyInput
    }

    func suggestions(for context: SuggestionContext) async -> [CommandLensSuggestion] {
        let query = context.input.lowercased()

        let allEngines = SearchEngine.builtIns + customSearchEngineManager.cachedEngines

        let matchingEngines = allEngines.filter { engine in
            engine.name.lowercased().hasPrefix(query) ||
                engine.shortName.lowercased().hasPrefix(query)
        }

        return matchingEngines.prefix(maxSuggestions).map { engine in
            CommandLensSuggestion(
                type: .searchProvider(engine),
                text: context.input,
                description: "Search \(engine.name)",
                iconName: engine.iconName,
                groupHeader: groupHeader,
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            )
        }
    }
}
