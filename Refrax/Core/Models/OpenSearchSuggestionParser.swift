import Foundation

/// Parses search suggestions in OpenSearch JSON format.
///
/// The OpenSearch suggestion format is the same `[query, [suggestions]]` JSON
/// array used by most search engines (including Google and Bing), making this
/// parser suitable for the majority of auto-detected engines.
///
/// Response format:
/// ```json
/// ["query", ["suggestion1", "suggestion2", "suggestion3"]]
/// ```
struct OpenSearchSuggestionParser: SuggestionParser {
    nonisolated func buildURL(for query: String, template: String?) -> URL? {
        guard let template else { return nil }
        let encoded = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return URL(string: String(format: template, encoded))
    }

    nonisolated func parse(_ data: Data) -> [String]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count >= 2,
              let suggestions = json[1] as? [String]
        else {
            return nil
        }

        return suggestions
    }
}
