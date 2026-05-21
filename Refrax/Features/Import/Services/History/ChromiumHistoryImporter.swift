import Foundation
import SQLite3

/// Imports browsing history from Chromium-based browsers.
///
/// Chromium browsers store history in a SQLite database called `History`
/// within each profile directory.
///
/// ## Database Schema
///
/// **urls** table:
/// - `id`: Primary key
/// - `url`: The visited URL
/// - `title`: Page title
/// - `visit_count`: Total visit count
/// - `last_visit_time`: Last visit in Windows FILETIME format
///
/// **visits** table:
/// - `id`: Primary key
/// - `url`: Foreign key to urls.id
/// - `visit_time`: Visit timestamp in Windows FILETIME format
///
/// ## Date Format
///
/// Chromium uses Windows FILETIME format: microseconds since January 1, 1601.
///
/// ## Database Locking
///
/// Chrome may lock the database while running. This importer copies the
/// database to a temporary location before reading.
///
/// ## Supported Browsers
///
/// - Google Chrome (all channels)
/// - Microsoft Edge
/// - Brave Browser
/// - Opera
/// - Vivaldi
/// - Arc Browser
final class ChromiumHistoryImporter: HistoryImporter, @unchecked Sendable {
    let browser: ThirdPartyBrowser

    init(browser: ThirdPartyBrowser) {
        self.browser = browser
    }

    func canImport(from profile: BrowserProfile) -> Bool {
        let historyDB = profile.path.appendingPathComponent("History")
        return FileManager.default.fileExists(atPath: historyDB.path)
    }

    func getHistoryDateRange(from profile: BrowserProfile) async throws -> (min: Date, max: Date)? {
        let historyDB = profile.path.appendingPathComponent("History")

        guard FileManager.default.fileExists(atPath: historyDB.path) else {
            return nil
        }

        let tempDB = try copyDatabaseToTemp(historyDB)
        defer { try? FileManager.default.removeItem(at: tempDB) }

        let connection = try openDatabase(at: tempDB)
        defer { sqlite3_close(connection) }

        return try queryDateRange(db: connection)
    }

    func importHistory(
        from profile: BrowserProfile,
        dateRange: ClosedRange<Date>?,
    ) async throws -> [ImportedHistoryEntry] {
        let historyDB = profile.path.appendingPathComponent("History")

        guard FileManager.default.fileExists(atPath: historyDB.path) else {
            throw ImportError.fileNotFound(historyDB.path)
        }

        let tempDB = try copyDatabaseToTemp(historyDB)
        defer { try? FileManager.default.removeItem(at: tempDB) }

        let connection = try openDatabase(at: tempDB)
        defer { sqlite3_close(connection) }

        return try queryHistory(db: connection, dateRange: dateRange)
    }
}

// MARK: - Database Operations

private extension ChromiumHistoryImporter {
    func copyDatabaseToTemp(_ sourceDB: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempDB = tempDir.appendingPathComponent("history_import_\(UUID().uuidString).sqlite")

        do {
            try FileManager.default.copyItem(at: sourceDB, to: tempDB)
        } catch {
            throw ImportError.permissionDenied(sourceDB.path)
        }

        copyWALFilesIfPresent(sourceDB: sourceDB, tempDB: tempDB)

        return tempDB
    }

    func copyWALFilesIfPresent(sourceDB: URL, tempDB: URL) {
        let fileManager = FileManager.default
        let walFile = URL(fileURLWithPath: sourceDB.path + "-wal")
        let shmFile = URL(fileURLWithPath: sourceDB.path + "-shm")

        if fileManager.fileExists(atPath: walFile.path) {
            try? fileManager.copyItem(
                at: walFile,
                to: URL(fileURLWithPath: tempDB.path + "-wal"),
            )
        }

        if fileManager.fileExists(atPath: shmFile.path) {
            try? fileManager.copyItem(
                at: shmFile,
                to: URL(fileURLWithPath: tempDB.path + "-shm"),
            )
        }
    }

    func openDatabase(at url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX

        let result = sqlite3_open_v2(url.path, &db, flags, nil)

        guard result == SQLITE_OK, let connection = db else {
            let errorMessage = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw ImportError.databaseError("Failed to open history database: \(errorMessage)")
        }

        return connection
    }
}

// MARK: - Date Range Query

private extension ChromiumHistoryImporter {
    func queryDateRange(db: OpaquePointer) throws -> (min: Date, max: Date)? {
        let query = """
        SELECT MIN(last_visit_time), MAX(last_visit_time)
        FROM urls
        WHERE last_visit_time > 0
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw ImportError.databaseError("Failed to prepare date range query")
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        let minTime = sqlite3_column_int64(statement, 0)
        let maxTime = sqlite3_column_int64(statement, 1)

        guard minTime > 0, maxTime > 0 else {
            return nil
        }

        let minDate = chromiumTimeToDate(minTime)
        let maxDate = chromiumTimeToDate(maxTime)

        return (min: minDate, max: maxDate)
    }
}

// MARK: - History Query

private extension ChromiumHistoryImporter {
    func queryHistory(
        db: OpaquePointer,
        dateRange: ClosedRange<Date>?,
    ) throws -> [ImportedHistoryEntry] {
        var query = """
        SELECT url, title, visit_count, last_visit_time
        FROM urls
        WHERE hidden = 0 AND last_visit_time > 0
        """

        if let dateRange {
            let minTime = dateToChromiumTime(dateRange.lowerBound)
            let maxTime = dateToChromiumTime(dateRange.upperBound)
            query += " AND last_visit_time >= \(minTime) AND last_visit_time <= \(maxTime)"
        }

        query += " ORDER BY last_visit_time DESC"

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw ImportError.databaseError("Failed to prepare history query")
        }
        defer { sqlite3_finalize(statement) }

        var entries: [ImportedHistoryEntry] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            if let entry = parseHistoryRow(statement) {
                entries.append(entry)
            }
        }

        if entries.isEmpty {
            throw ImportError.noHistoryFound
        }

        return entries
    }

    func parseHistoryRow(_ statement: OpaquePointer?) -> ImportedHistoryEntry? {
        guard let statement else { return nil }

        guard let urlString = extractString(from: statement, column: 0),
              let url = URL(string: urlString),
              isValidHistoryURL(url)
        else {
            return nil
        }

        let title = extractString(from: statement, column: 1)
        let visitCount = Int(sqlite3_column_int(statement, 2))
        let lastVisitTime = sqlite3_column_int64(statement, 3)

        let lastVisited = chromiumTimeToDate(lastVisitTime)

        return ImportedHistoryEntry(
            url: url,
            title: title,
            visitCount: max(1, visitCount),
            lastVisited: lastVisited,
            firstVisited: nil,
        )
    }

    func isValidHistoryURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }

        let validSchemes = ["http", "https", "file"]
        guard validSchemes.contains(scheme) else { return false }

        let invalidPrefixes = [
            "chrome://",
            "chrome-extension://",
            "edge://",
            "brave://",
            "opera://",
            "vivaldi://",
        ]

        let urlString = url.absoluteString.lowercased()
        for prefix in invalidPrefixes {
            if urlString.hasPrefix(prefix) {
                return false
            }
        }

        return true
    }
}

// MARK: - Time Conversion

private extension ChromiumHistoryImporter {
    /// Converts Chromium time (microseconds since Windows epoch) to Swift Date.
    ///
    /// Windows FILETIME epoch is January 1, 1601 UTC.
    /// Unix epoch is January 1, 1970 UTC.
    /// Offset between them is 11,644,473,600 seconds.
    func chromiumTimeToDate(_ chromiumTime: Int64) -> Date {
        let windowsEpochOffset: TimeInterval = 11_644_473_600
        let seconds = Double(chromiumTime) / 1_000_000 - windowsEpochOffset
        return Date(timeIntervalSince1970: seconds)
    }

    func dateToChromiumTime(_ date: Date) -> Int64 {
        let windowsEpochOffset: TimeInterval = 11_644_473_600
        let seconds = date.timeIntervalSince1970 + windowsEpochOffset
        return Int64(seconds * 1_000_000)
    }
}

// MARK: - SQLite Helpers

private extension ChromiumHistoryImporter {
    func extractString(from statement: OpaquePointer?, column: Int32) -> String? {
        guard let textPointer = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: textPointer)
    }
}
