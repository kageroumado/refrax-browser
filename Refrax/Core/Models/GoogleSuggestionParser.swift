import Foundation

struct GoogleSuggestionParser: SuggestionParser {
    nonisolated func buildURL(for query: String, template: String?) -> URL? {
        guard let template else { return nil }
        return URL(string: String(format: template, query))
    }
    
    nonisolated func parse(_ data: Data) -> [String]? {
        guard let arr = try? JSONSerialization.jsonObject(with: data) as? [Any],
              arr.count >= 2,
              let list = arr[1] as? [String] else { return nil }
        return list
    }
}
