import Foundation

/// A search engine detected from browsing activity.
struct DetectedSearchEngine: Sendable, Equatable {
    let name: String
    let domain: String
    let searchURLTemplate: String
    let suggestionURLTemplate: String?
    let parserKind: SuggestionParserKind
}

/// Detects search engines from URL patterns and OpenSearch descriptors.
///
/// Two detection methods:
///
/// 1. **URL pattern detection**: Analyzes navigation URLs for known search query
///    parameters (`q`, `query`, `search`, etc.) and constructs a template.
///
/// 2. **OpenSearch descriptor parsing**: Parses `<link rel="search">` XML
///    descriptors to extract search and suggestion URL templates.
nonisolated enum SearchEngineDetectionService {
    /// Known query parameter names that indicate a search URL.
    private static let searchQueryKeys: Set<String> = [
        "q", "query", "search", "s", "keyword", "search_query",
        "searchTerms", "p", "text", "k", "w",
    ]

    /// Domains of built-in engines that should not be detected.
    private static let builtInDomains: Set<String> = [
        "google.com", "www.google.com",
        "duckduckgo.com", "www.duckduckgo.com",
        "bing.com", "www.bing.com",
    ]

    // MARK: - URL Pattern Detection

    /// Attempts to detect a search engine from a navigation URL.
    ///
    /// Looks for known search query parameters and constructs a template by
    /// replacing the matched query value with `%@`.
    ///
    /// - Parameter url: The navigation URL to analyze.
    /// - Returns: A detected search engine, or `nil` if no pattern matches.
    static func detectFromURL(_ url: URL) -> DetectedSearchEngine? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = components.host,
              let queryItems = components.queryItems,
              !queryItems.isEmpty
        else {
            return nil
        }

        // Skip built-in engine domains
        let baseDomain = extractBaseDomain(from: host)
        if builtInDomains.contains(host) || builtInDomains.contains(baseDomain) {
            return nil
        }

        // Find a matching search query parameter
        guard let matchedItem = queryItems.first(where: { searchQueryKeys.contains($0.name) }),
              let queryValue = matchedItem.value,
              !queryValue.isEmpty
        else {
            return nil
        }

        // Build the search URL template by replacing the query value with %@
        var templateComponents = components
        templateComponents.queryItems = queryItems.map { item in
            if item.name == matchedItem.name {
                return URLQueryItem(name: item.name, value: "%@")
            }
            return item
        }

        guard let templateURL = templateComponents.url else { return nil }

        // The template URL will have %25@ (percent-encoded %) — decode it back to %@
        let template = templateURL.absoluteString
            .replacingOccurrences(of: "%25@", with: "%@")
            .replacingOccurrences(of: "%25%40", with: "%@")

        let name = prettifyDomainName(host)

        return DetectedSearchEngine(
            name: name,
            domain: baseDomain,
            searchURLTemplate: template,
            suggestionURLTemplate: nil,
            parserKind: .none,
        )
    }

    // MARK: - OpenSearch Descriptor Parsing

    /// Parses an OpenSearch description XML document.
    ///
    /// Extracts search and suggestion URL templates from the XML, converting
    /// `{searchTerms}` placeholders to `%@`.
    ///
    /// - Parameters:
    ///   - data: The raw XML data of the OpenSearch description.
    ///   - sourceURL: The URL of the page where the descriptor was found.
    /// - Returns: A detected search engine, or `nil` if parsing fails.
    static func parseOpenSearchDescription(_ data: Data, sourceURL: URL) -> DetectedSearchEngine? {
        let parser = OpenSearchXMLParser(data: data)
        guard parser.parse() else { return nil }

        guard let searchTemplate = parser.searchTemplate else { return nil }

        let domain = sourceURL.host ?? "unknown"
        let baseDomain = extractBaseDomain(from: domain)

        // Skip built-in engines
        if builtInDomains.contains(domain) || builtInDomains.contains(baseDomain) {
            return nil
        }

        // Convert {searchTerms} to %@
        let normalizedSearch = searchTemplate
            .replacingOccurrences(of: "{searchTerms}", with: "%@")
        let normalizedSuggestion = parser.suggestionTemplate?
            .replacingOccurrences(of: "{searchTerms}", with: "%@")

        let name = parser.shortName ?? prettifyDomainName(domain)

        return DetectedSearchEngine(
            name: name,
            domain: baseDomain,
            searchURLTemplate: normalizedSearch,
            suggestionURLTemplate: normalizedSuggestion,
            parserKind: normalizedSuggestion != nil ? .openSearch : .none,
        )
    }

    // MARK: - Helpers

    /// Extracts the base registrable domain from a host.
    ///
    /// Strips `www.` and subdomains for common patterns.
    static func extractBaseDomain(from host: String) -> String {
        var domain = host.lowercased()
        if domain.hasPrefix("www.") {
            domain = String(domain.dropFirst(4))
        }
        return domain
    }

    /// Converts a domain name to a human-readable display name.
    ///
    /// "github.com" → "Github", "stackoverflow.com" → "Stackoverflow"
    private static func prettifyDomainName(_ host: String) -> String {
        var domain = extractBaseDomain(from: host)

        // Remove TLD
        if let dotIndex = domain.lastIndex(of: ".") {
            domain = String(domain[domain.startIndex ..< dotIndex])
        }

        // Capitalize first letter
        return domain.prefix(1).uppercased() + domain.dropFirst()
    }
}

// MARK: - OpenSearch XML Parser

/// Minimal XML parser for OpenSearch description documents.
private final nonisolated class OpenSearchXMLParser: NSObject, XMLParserDelegate {
    private let data: Data

    var shortName: String?
    var searchTemplate: String?
    var suggestionTemplate: String?

    private var currentText: String = ""

    init(data: Data) {
        self.data = data
    }

    func parse() -> Bool {
        let parser = XMLParser(data: data)
        parser.delegate = self
        return parser.parse()
    }

    // MARK: - XMLParserDelegate

    func parser(
        _: XMLParser,
        didStartElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
        attributes: [String: String],
    ) {
        currentText = ""

        if elementName == "Url" || elementName.hasSuffix(":Url") {
            let type = attributes["type"] ?? ""
            let template = attributes["template"] ?? ""

            if type == "text/html" {
                searchTemplate = template
            } else if type == "application/x-suggestions+json" {
                suggestionTemplate = template
            }
        }
    }

    func parser(_: XMLParser, foundCharacters string: String) {
        currentText += string
    }

    func parser(
        _: XMLParser,
        didEndElement elementName: String,
        namespaceURI _: String?,
        qualifiedName _: String?,
    ) {
        let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)

        if elementName == "ShortName" || elementName.hasSuffix(":ShortName") {
            if !trimmed.isEmpty {
                shortName = trimmed
            }
        }
    }
}
