import Foundation

struct DuckDuckGoSuggestionParser: SuggestionParser {
    nonisolated func buildURL(for query: String, template: String?) -> URL? {
        guard let template else { return nil }
        return URL(string: String(format: template, query))
    }
    
    nonisolated func parse(_ data: Data) -> [String]? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] else { return nil }
        return json.compactMap { $0["phrase"] }
    }
}
