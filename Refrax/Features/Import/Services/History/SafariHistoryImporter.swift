import Foundation
import SQLite3

/// Imports browsing history from Safari.
///
/// Safari stores history in a SQLite database called `History.db`
/// located in `~/Library/Safari/`.
///
/// ## Database Schema
///
/// **history_items** table:
/// - `id`: Primary key
/// - `url`: The visited URL
/// - `visit_count`: Number of visits (may be NULL)
///
/// **history_visits** table:
/// - `id`: Primary key
/// - `history_item`: Foreign key to history_items.id
/// - `visit_time`: Visit timestamp (Core Data timestamp)
/// - `title`: Page title at time of visit
///
/// ## Date Format
///
/// Safari uses Core Data timestamps: seconds since January 1, 2001 (Mac epoch).
///
/// ## Permissions
///
/// Safari's History.db requires Full Disk Access to read directly.
/// The importer attempts to read the database and throws a permission
/// error if access is denied.
final class SafariHistoryImporter: HistoryImporter, @unchecked Sendable {
    let browser: ThirdPartyBrowser = .safari

    func canImport(from profile: BrowserProfile) -> Bool {
        let historyDB = profile.path.appendingPathComponent("History.db")
        return FileManager.default.fileExists(atPath: historyDB.path)
    }

    func getHistoryDateRange(from profile: BrowserProfile) async throws -> (min: Date, max: Date)? {
        let historyDB = profile.path.appendingPathComponent("History.db")

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
        let historyDB = profile.path.appendingPathComponent("History.db")

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

private extension SafariHistoryImporter {
    func copyDatabaseToTemp(_ sourceDB: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempDB = tempDir.appendingPathComponent("safari_history_\(UUID().uuidString).db")

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
            throw ImportError.databaseError("Failed to open Safari history: \(errorMessage)")
        }

        return connection
    }
}

// MARK: - Date Range Query

private extension SafariHistoryImporter {
    func queryDateRange(db: OpaquePointer) throws -> (min: Date, max: Date)? {
        let query = """
        SELECT MIN(visit_time), MAX(visit_time)
        FROM history_visits
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw ImportError.databaseError("Failed to prepare date range query")
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW else {
            return nil
        }

        let minTime = sqlite3_column_double(statement, 0)
        let maxTime = sqlite3_column_double(statement, 1)

        guard minTime > 0, maxTime > 0 else {
            return nil
        }

        let minDate = safariTimeToDate(minTime)
        let maxDate = safariTimeToDate(maxTime)

        return (min: minDate, max: maxDate)
    }
}

// MARK: - History Query

private extension SafariHistoryImporter {
    func queryHistory(
        db: OpaquePointer,
        dateRange: ClosedRange<Date>?,
    ) throws -> [ImportedHistoryEntry] {
        var query = """
        SELECT h.url, v.title, h.visit_count, MAX(v.visit_time) as last_visit, MIN(v.visit_time) as first_visit
        FROM history_items h
        JOIN history_visits v ON h.id = v.history_item
        """

        if let dateRange {
            let minTime = dateToSafariTime(dateRange.lowerBound)
            let maxTime = dateToSafariTime(dateRange.upperBound)
            query += " WHERE v.visit_time >= \(minTime) AND v.visit_time <= \(maxTime)"
        }

        query += " GROUP BY h.id ORDER BY last_visit DESC"

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
        let lastVisitTime = sqlite3_column_double(statement, 3)
        let firstVisitTime = sqlite3_column_double(statement, 4)

        let lastVisited = safariTimeToDate(lastVisitTime)
        let firstVisited = firstVisitTime > 0 ? safariTimeToDate(firstVisitTime) : nil

        return ImportedHistoryEntry(
            url: url,
            title: title,
            visitCount: max(1, visitCount),
            lastVisited: lastVisited,
            firstVisited: firstVisited,
        )
    }

    func isValidHistoryURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }

        let validSchemes = ["http", "https", "file"]
        return validSchemes.contains(scheme)
    }
}

// MARK: - Time Conversion

private extension SafariHistoryImporter {
    /// Converts Safari/Core Data time (seconds since Mac epoch) to Swift Date.
    ///
    /// Mac epoch (reference date) is January 1, 2001 00:00:00 UTC.
    func safariTimeToDate(_ safariTime: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: safariTime)
    }

    func dateToSafariTime(_ date: Date) -> Double {
        date.timeIntervalSinceReferenceDate
    }
}

// MARK: - SQLite Helpers

private extension SafariHistoryImporter {
    func extractString(from statement: OpaquePointer?, column: Int32) -> String? {
        guard let textPointer = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: textPointer)
    }
}
