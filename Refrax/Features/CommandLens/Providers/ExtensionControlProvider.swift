import Foundation

/// Provides browser extension toggle suggestions for Command Lens.
///
/// Queries `ExtensionManager.installedExtensions` and fuzzy-matches the input
/// against extension display names, letting users quickly enable or disable extensions.
struct ExtensionControlProvider: CommandLensSuggestionProvider {
    let id = "extension-control"
    let priority = 20
    let groupHeader: String? = "Extensions"
    let maxSuggestions = 5

    private let extensionManager: ExtensionManager

    init(extensionManager: ExtensionManager) {
        self.extensionManager = extensionManager
    }

    func shouldProvide(for context: SuggestionContext) -> Bool {
        !context.isEmptyInput && !context.isDirectURL
    }

    func suggestions(for context: SuggestionContext) async -> [CommandLensSuggestion] {
        let query = context.input.lowercased()
        let extensions = extensionManager.installedExtensions

        guard !extensions.isEmpty else { return [] }

        var matches: [(ext: InstalledExtension, score: Double)] = []

        for ext in extensions {
            let terms = [ext.displayName, "extension", "addon", "plugin"]
            let score = FuzzyMatcher.match(query: query, against: terms)

            if score >= FuzzyMatcher.minimumMatchScore {
                matches.append((ext, score))
            }
        }

        let topMatches = matches
            .sorted { $0.score > $1.score }
            .prefix(maxSuggestions)

        return topMatches.enumerated().map { index, match -> CommandLensSuggestion in
            let statusText = match.ext.isEnabled ? "Enabled" : "Disabled"
            return CommandLensSuggestion(
                type: .setting(key: "ext:\(match.ext.id.uuidString)", scope: .global),
                text: match.ext.displayName,
                description: "Extension \(statusText)",
                iconName: "puzzlepiece.extension.fill",
                groupHeader: index == 0 ? groupHeader : nil,
                isRemovable: false,
                keywordAction: nil,
                url: nil,
            )
        }
    }
}
