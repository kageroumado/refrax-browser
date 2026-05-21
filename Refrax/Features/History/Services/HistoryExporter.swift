import Foundation
import SwiftData

// Exports browsing history to Safari-compatible JSON format.
//
// The export format is designed to be compatible with Safari's history export
// for interoperability while including additional Refrax-specific metadata.

struct HistoryExporter {
    private let historyManager: HistoryManager

    init(historyManager: HistoryManager) {
        self.historyManager = historyManager
    }

    // MARK: - Public API

    /// Returns the count of history entries in the specified date range.
    func entryCount(from startDate: Date, to endDate: Date) async -> Int {
        let entries = await historyManager.entries(from: startDate, to: endDate)
        return entries.count
    }

    /// Exports history entries within the specified date range to JSON.
    ///
    /// - Parameters:
    ///   - startDate: Beginning of the export range (inclusive)
    ///   - endDate: End of the export range (inclusive)
    /// - Returns: URL of the exported file in the temporary directory
    func exportToJSON(from startDate: Date, to endDate: Date) async throws -> URL {
        let entries = await historyManager.entries(from: startDate, to: endDate)
        let exportData = buildExportData(entries: entries, from: startDate, to: endDate)

        // Encode on MainActor where the types are isolated
        let jsonData = try Self.encodeJSON(from: exportData)

        // Write file on background thread
        return try await Task.detached(priority: .userInitiated) { [jsonData] in
            try Self.writeJSONFile(jsonData)
        }.value
    }

    // MARK: - Private Helpers

    private func buildExportData(
        entries: [HistoryEntryData],
        from startDate: Date,
        to endDate: Date,
    ) -> SafariHistoryExport {
        let exportEntries = entries.map { entry in
            SafariHistoryEntry(
                url: entry.url.absoluteString,
                title: entry.title,
                visitTime: entry.visitedAt.timeIntervalSince1970,
                visitCount: 1,
                domain: entry.domain,
            )
        }

        return SafariHistoryExport(
            version: 1,
            exportedAt: Date(),
            dateRange: SafariHistoryExport.DateRange(from: startDate, to: endDate),
            entries: exportEntries,
        )
    }

    static func encodeJSON(from exportData: SafariHistoryExport) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(exportData)
    }

    nonisolated static func writeJSONFile(_ jsonData: Data) throws -> URL {
        let dateString = Date().formatted(.iso8601.year().month().day())

        let filename = "Refrax History \(dateString).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)

        try jsonData.write(to: tempURL)
        return tempURL
    }
}

// MARK: - Export Data Types

/// Safari-compatible history export format.
struct SafariHistoryExport: Codable, Sendable {
    let version: Int
    let exportedAt: Date
    let dateRange: DateRange?
    let entries: [SafariHistoryEntry]

    struct DateRange: Codable, Sendable {
        let from: Date
        let to: Date
    }
}

/// Individual history entry in export format.
struct SafariHistoryEntry: Codable, Sendable {
    let url: String
    let title: String?
    let visitTime: TimeInterval
    let visitCount: Int
    let domain: String
}
