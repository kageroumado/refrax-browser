import Foundation

/// Synthesizes root domain suggestions from subpage visit history.
///
/// When a user has visited subpages of a domain (e.g., `github.com/user/repo`)
/// but never the root domain itself, this provider suggests navigating to the
/// base domain. This handles the common case where users discover sites via
/// deep links but may want to explore the homepage.
struct BaseDomainSynthesisProvider: CommandLensSuggestionProvider {
    let id = "base-domain-synthesis"
    let priority = 145
    let groupHeader: String? = nil
    let maxSuggestions = 2

    private let frequentDestinations: FrequentDestinationsCache

    init(frequentDestinations: FrequentDestinationsCache) {
        self.frequentDestinations = frequentDestinations
    }

    func shouldProvide(for context: SuggestionContext) -> Bool {
        guard !context.isEmptyInput else { return false }
        guard !context.isDirectURL else { return false }
        return true
    }

    func suggestions(for context: SuggestionContext) async -> [CommandLensSuggestion] {
        let domains = frequentDestinations.baseDomainSuggestions(query: context.input)

        return domains.prefix(maxSuggestions).compactMap { entry in
            guard let url = URL(string: "https://\(entry.domain)") else { return nil }

            return CommandLensSuggestion(
                type: .url,
                text: entry.domain,
                description: "Go to website",
                iconName: "globe.badge.chevron.backward",
                groupHeader: groupHeader,
                isRemovable: false,
                keywordAction: nil,
                url: url,
            )
        }
    }
}
