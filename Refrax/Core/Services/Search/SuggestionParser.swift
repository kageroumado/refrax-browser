import Foundation

protocol SuggestionParser: Sendable {
    nonisolated func buildURL(for query: String, template: String?) -> URL?
    nonisolated func parse(_ data: Data) -> [String]?
}

enum SuggestionParserKind: String, Codable, Sendable {
    case google
    case duckDuckGo
    case bing
    case openSearch
    case none
}
