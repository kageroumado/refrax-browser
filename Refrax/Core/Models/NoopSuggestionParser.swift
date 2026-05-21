import Foundation

struct NoopSuggestionParser: SuggestionParser {
    nonisolated func buildURL(for _: String, template _: String?) -> URL? { nil }
    nonisolated func parse(_: Data) -> [String]? { nil }
}
