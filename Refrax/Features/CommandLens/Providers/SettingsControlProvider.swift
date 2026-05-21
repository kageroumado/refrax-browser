import Foundation

/// Provides settings control suggestions for natural language queries.
///
/// Uses the ``BrowserSettingKey`` registry as its single source of truth,
/// making all registered settings searchable and toggleable via Command Lens.
struct SettingsControlProvider: CommandLensSuggestionProvider {
    let id = "settings-control"
    let priority = 25
    let groupHeader: String? = "Settings"
    let maxSuggestions = 5

    private let settings: BrowserSettings

    init(settings: BrowserSettings) {
        self.settings = settings
    }

    func shouldProvide(for context: SuggestionContext) -> Bool {
        !context.isEmptyInput && !context.isDirectURL
    }

    func suggestions(for context: SuggestionContext) async -> [CommandLensSuggestion] {
        let query = context.input.lowercased()

        var matches: [(key: BrowserSettingKey, score: Double)] = []

        for key in BrowserSettingKey.allCases {
            let meta = key.metadata
            let terms = [meta.displayName] + meta.keywords
            let score = FuzzyMatcher.match(query: query, against: terms)

            if score >= FuzzyMatcher.minimumMatchScore {
                matches.append((key, score))
            }
        }

        let topMatches = matches
            .sorted { $0.score > $1.score }
            .prefix(maxSuggestions)

        return topMatches.enumerated().map { index, match -> CommandLensSuggestion in
            let meta = match.key.metadata

            return CommandLensSuggestion(
                type: .setting(key: match.key.rawValue, scope: .global),
                text: meta.displayName,
                description: meta.description,
                iconName: meta.icon,
                groupHeader: index == 0 ? groupHeader : nil,
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            )
        }
    }
}
