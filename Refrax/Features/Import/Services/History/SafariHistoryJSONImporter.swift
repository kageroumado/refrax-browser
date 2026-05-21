import Foundation

/// Imports browsing history from Safari's exported History.json file.
///
/// Safari's File > Export Browsing Data produces a zip containing `History.json`
/// with this format:
///
/// ```json
/// {
///   "metadata": { "version": 1, ... },
///   "history": [
///     {
///       "url": "https://example.com",
///       "time_usec": 1742249993771250,
///       "visit_count": 1,
///       "title": "Example Domain"
///     }
///   ]
/// }
/// ```
///
/// ## Timestamp Format
///
/// `time_usec` is microseconds since the Unix epoch (January 1, 1970).
enum SafariHistoryJSONImporter {
    /// Imports history entries from a Safari History.json file.
    ///
    /// - Parameters:
    ///   - fileURL: URL of the History.json file.
    ///   - dateRange: Optional date range filter. If `nil`, imports all entries.
    /// - Returns: Array of imported history entries.
    static func importHistory(
        from fileURL: URL,
        dateRange: ClosedRange<Date>?,
    ) async throws -> [ImportedHistoryEntry] {
        let data = try Data(contentsOf: fileURL)
        let export = try JSONDecoder().decode(SafariHistoryJSON.self, from: data)

        var entries: [ImportedHistoryEntry] = []

        for item in export.history {
            guard let url = URL(string: item.url),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https"
            else {
                continue
            }

            let visitDate = Date(
                timeIntervalSince1970: Double(item.timeUsec) / 1_000_000
            )

            if let dateRange, !dateRange.contains(visitDate) {
                continue
            }

            entries.append(ImportedHistoryEntry(
                url: url,
                title: item.title,
                visitCount: item.visitCount ?? 1,
                lastVisited: visitDate,
            ))
        }

        return entries
    }

    /// Returns the date range of entries in a History.json file.
    ///
    /// - Parameter fileURL: URL of the History.json file.
    /// - Returns: A tuple of (earliest date, latest date), or `nil` if empty.
    static func getDateRange(from fileURL: URL) async throws -> (min: Date, max: Date)? {
        let data = try Data(contentsOf: fileURL)
        let export = try JSONDecoder().decode(SafariHistoryJSON.self, from: data)

        guard !export.history.isEmpty else { return nil }

        var minUsec = Int64.max
        var maxUsec = Int64.min

        for item in export.history {
            if item.timeUsec < minUsec { minUsec = item.timeUsec }
            if item.timeUsec > maxUsec { maxUsec = item.timeUsec }
        }

        let minDate = Date(timeIntervalSince1970: Double(minUsec) / 1_000_000)
        let maxDate = Date(timeIntervalSince1970: Double(maxUsec) / 1_000_000)

        return (min: minDate, max: maxDate)
    }
}

// MARK: - JSON Structure

private struct SafariHistoryJSON: Decodable {
    let history: [HistoryItem]

    struct HistoryItem: Decodable {
        let url: String
        let timeUsec: Int64
        let visitCount: Int?
        let title: String?

        enum CodingKeys: String, CodingKey {
            case url
            case timeUsec = "time_usec"
            case visitCount = "visit_count"
            case title
        }
    }
}
