import Foundation
import SwiftData

/// A user-defined or auto-detected search engine stored in SwiftData.
///
/// Custom search engines extend the built-in set (Google, DuckDuckGo, Bing)
/// with user-added or site-detected providers. Each engine has an alias for
/// quick activation in the Command Lens (type alias + Tab).
///
/// ## Alias Activation
///
/// Users type the alias in Command Lens and press Tab to activate:
/// - "yt" + Tab → searches YouTube
/// - "gh" + Tab → searches GitHub
///
/// ## Auto-Detection
///
/// When browsing sites with search functionality (detected via URL query
/// parameters or OpenSearch descriptors), Refrax can auto-detect and offer
/// to add them as custom engines.
@Model
final class CustomSearchEngine {
    @Attribute(.unique, .preserveValueOnDeletion) var id: UUID

    /// Display name shown in the Command Lens and settings.
    var name: String

    /// Short alias for quick activation (e.g., "yt" for YouTube).
    var alias: String

    /// URL template for search results, with `%@` as query placeholder.
    var searchURLTemplate: String

    /// Optional URL template for fetching autocomplete suggestions.
    var suggestionURLTemplate: String?

    /// Raw value of ``SuggestionParserKind`` for the suggestion response format.
    var parserKindRaw: String

    /// SF Symbol name for the engine's icon.
    var iconName: String

    /// Domain this engine was detected from, used as dedup key.
    var sourceDomain: String?

    /// Display order in the engine list.
    var sortOrder: Int

    /// Whether this engine was auto-detected from browsing.
    var isAutoDetected: Bool

    /// When this engine was added.
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        alias: String,
        searchURLTemplate: String,
        suggestionURLTemplate: String? = nil,
        parserKind: SuggestionParserKind = .openSearch,
        iconName: String = "globe",
        sourceDomain: String? = nil,
        sortOrder: Int = 0,
        isAutoDetected: Bool = false,
        createdAt: Date = Date(),
    ) {
        self.id = id
        self.name = name
        self.alias = alias
        self.searchURLTemplate = searchURLTemplate
        self.suggestionURLTemplate = suggestionURLTemplate
        self.parserKindRaw = parserKind.rawValue
        self.iconName = iconName
        self.sourceDomain = sourceDomain
        self.sortOrder = sortOrder
        self.isAutoDetected = isAutoDetected
        self.createdAt = createdAt
    }
}

// MARK: - Conversion

extension CustomSearchEngine {
    /// The parser kind for this engine's suggestion responses.
    var parserKind: SuggestionParserKind {
        SuggestionParserKind(rawValue: parserKindRaw) ?? .none
    }

    /// Creates a runtime ``SearchEngine`` value type from this persisted model.
    func makeSearchEngine() -> SearchEngine {
        SearchEngine(
            id: "custom-\(id.uuidString)",
            name: name,
            shortName: alias,
            iconName: iconName,
            searchURLTemplate: searchURLTemplate,
            suggestionURLTemplate: suggestionURLTemplate,
            parserKind: parserKind,
        )
    }
}
