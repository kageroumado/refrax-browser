import Foundation
import SwiftData

/// Actor that handles SwiftData operations during import.
///
/// This actor ensures that all ModelContext operations during import are
/// properly isolated to a single actor, preventing data races and ensuring
/// thread safety. Heavy I/O work (file reads, SQLite queries) still happens
/// in the importers; this actor only handles the SwiftData persistence.
@ModelActor
final actor ImportDataActor {
    /// Imports history entries into the database.
    ///
    /// - Parameter entries: The imported history entries to persist.
    /// - Returns: The number of entries successfully imported.
    func importHistoryEntries(_ entries: [ImportedHistoryEntry]) throws -> Int {
        var importedCount = 0

        for entry in entries {
            let historyEntry = HistoryEntry(from: entry)
            modelContext.insert(historyEntry)
            importedCount += 1
        }

        try modelContext.save()
        return importedCount
    }

    /// Fetches existing bookmark URLs to check for duplicates.
    ///
    /// - Returns: A set of URLs that already exist as bookmarks.
    func fetchExistingBookmarkURLs() -> Set<URL> {
        let descriptor = FetchDescriptor<Bookmark>()
        guard let bookmarks = try? modelContext.fetch(descriptor) else {
            return []
        }
        return Set(bookmarks.map(\.url))
    }
}
