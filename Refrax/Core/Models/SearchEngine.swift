import Foundation

/// Configuration for a web search engine with suggestion support.
///
/// Represents a search provider like Google, DuckDuckGo, or Bing, including
/// URL templates for performing searches and fetching suggestions as the user types.
///
/// ## Built-in Engines
///
/// Refrax includes three pre-configured engines:
///
/// - ``google``: Google Search with autocomplete
/// - ``duckDuckGo``: Privacy-focused DuckDuckGo
/// - ``bing``: Microsoft Bing
///
/// ## Custom Engines
///
/// Users can potentially add custom search engines by providing URL templates
/// with `%@` as the query placeholder:
///
/// ```swift
/// let myEngine = SearchEngine(
///     id: "custom-engine",
///     name: "My Search",
///     searchURLTemplate: "https://example.com/search?q=%@",
///     suggestionURLTemplate: "https://example.com/suggest?q=%@",
///     parserKind: .none
/// )
/// ```
///
/// ## Suggestion Parsers
///
/// Each engine specifies a ``SuggestionParserKind`` that knows how to parse
/// that provider's suggestion API response format.
///
/// - Note: The `%@` placeholder in URL templates is automatically replaced with
///   the URL-encoded search query.
struct SearchEngine: Identifiable, Codable, Hashable, Sendable {
    let id: String
    var name: String
    var shortName: String
    var iconName: String
    
    /// URL template for search results.
    ///
    /// Use `%@` as a placeholder for the query string. Example:
    /// `"https://www.google.com/search?q=%@"`
    var searchURLTemplate: String
    
    /// Optional URL template for fetching suggestions.
    ///
    /// When provided, enables real-time search suggestions as the user types.
    /// Use `%@` as the query placeholder.
    var suggestionURLTemplate: String?
    
    /// Type of parser to use for this engine's suggestion responses.
    var parserKind: SuggestionParserKind
    
    /// Creates a suggestion parser instance for this engine.
    var suggestionParser: any SuggestionParser {
        parserKind.makeParser()
    }
    
    nonisolated init(
        id: String,
        name: String,
        shortName: String? = nil,
        iconName: String = "magnifyingglass",
        searchURLTemplate: String,
        suggestionURLTemplate: String? = nil,
        parserKind: SuggestionParserKind,
    ) {
        self.id = id
        self.name = name
        self.shortName = shortName ?? name
        self.iconName = iconName
        self.searchURLTemplate = searchURLTemplate
        self.suggestionURLTemplate = suggestionURLTemplate
        self.parserKind = parserKind
    }
}

// MARK: - Built‑in Engines

extension SearchEngine {
    static let google = SearchEngine(
        id: "built-in-google",
        name: "Google",
        searchURLTemplate: "https://www.google.com/search?q=%@",
        suggestionURLTemplate: "https://www.google.com/complete/search?q=%@&client=firefox",
        parserKind: .google,
    )
    
    static let duckDuckGo = SearchEngine(
        id: "built-in-duckDuckGo",
        name: "DuckDuckGo",
        shortName: "DDG",
        searchURLTemplate: "https://duckduckgo.com/?q=%@",
        suggestionURLTemplate: "https://duckduckgo.com/ac/?q=%@",
        parserKind: .duckDuckGo,
    )
    
    static let bing = SearchEngine(
        id: "built-in-bing",
        name: "Bing",
        searchURLTemplate: "https://www.bing.com/search?q=%@",
        suggestionURLTemplate: "https://api.bing.com/osjson.aspx?query=%@",
        parserKind: .bing,
    )
    
    static var builtIns: [SearchEngine] {
        [google, duckDuckGo, bing]
    }
}

// MARK: - Convenience

extension SearchEngine {
    /// Builds a search URL for the given query string.
    ///
    /// Encodes the query and injects it into the search URL template.
    ///
    /// - Parameter query: The search terms entered by the user.
    /// - Returns: A URL for the search results, or `nil` if the template is invalid.
    func searchURL(for query: String) -> URL? {
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: String(format: searchURLTemplate, encoded))
    }
}

extension SuggestionParserKind {
    /// Creates a parser instance appropriate for this kind.
    ///
    /// Each parser knows how to decode that search provider's specific
    /// suggestion response format.
    func makeParser() -> any SuggestionParser {
        switch self {
        case .google: GoogleSuggestionParser()
        case .duckDuckGo: DuckDuckGoSuggestionParser()
        case .bing: BingSuggestionParser()
        case .openSearch: OpenSearchSuggestionParser()
        case .none: NoopSuggestionParser()
        }
    }
}
