import Foundation
import SQLite3

/// Imports bookmarks from Firefox-based browsers.
///
/// Firefox stores bookmarks in a SQLite database called `places.sqlite`
/// within each profile directory. This importer reads the database using
/// the SQLite3 C API.
///
/// ## Database Schema
///
/// Firefox uses two main tables for bookmarks:
///
/// **moz_bookmarks**:
/// - `id`: Primary key
/// - `parent`: Parent folder ID
/// - `type`: 1 = bookmark, 2 = folder
/// - `title`: Display name
/// - `fk`: Foreign key to moz_places (for bookmarks)
/// - `dateAdded`: Timestamp in microseconds since Unix epoch
///
/// **moz_places**:
/// - `id`: Primary key
/// - `url`: Actual web address
/// - `title`: Page title
///
/// ## Special Folder GUIDs
///
/// Firefox uses special GUIDs for built-in folders:
/// - `toolbar_____`: Bookmarks Toolbar
/// - `menu________`: Bookmarks Menu
/// - `unfiled_____`: Other Bookmarks
/// - `mobile______`: Mobile Bookmarks
///
/// ## Database Locking
///
/// Firefox may have the database locked while running. This importer
/// copies the database to a temporary location before reading to avoid
/// lock conflicts.
///
/// - SeeAlso: [Firefox places.sqlite](https://developer.mozilla.org/en-US/docs/Mozilla/Tech/Places)
final class FirefoxImporter: DataImporter, @unchecked Sendable {
    let browser: ThirdPartyBrowser

    init(browser: ThirdPartyBrowser = .firefox) {
        self.browser = browser
    }

    func canImport(from profile: BrowserProfile) -> Bool {
        let placesDB = profile.path.appendingPathComponent("places.sqlite")
        return FileManager.default.fileExists(atPath: placesDB.path)
    }

    func importBookmarks(from profile: BrowserProfile) async throws -> [ImportedFolder] {
        let placesDB = profile.path.appendingPathComponent("places.sqlite")

        guard FileManager.default.fileExists(atPath: placesDB.path) else {
            throw ImportError.fileNotFound(placesDB.path)
        }

        let tempDB = try copyDatabaseToTemp(placesDB)
        defer {
            let fm = FileManager.default
            try? fm.removeItem(at: tempDB)
            try? fm.removeItem(at: URL(fileURLWithPath: tempDB.path + "-wal"))
            try? fm.removeItem(at: URL(fileURLWithPath: tempDB.path + "-shm"))
        }

        let connection = try openDatabase(at: tempDB)
        defer { sqlite3_close(connection) }

        let folderMap = try buildFolderMap(db: connection)
        return try fetchAndBuildBookmarks(db: connection, folderMap: folderMap)
    }
}

// MARK: - Database Operations

private extension FirefoxImporter {
    func copyDatabaseToTemp(_ sourceDB: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempDB = tempDir.appendingPathComponent("places_import_\(UUID().uuidString).sqlite")

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
        let sourcePath = sourceDB.path
        let tempPath = tempDB.path

        // SQLite WAL files use dash suffix: places.sqlite-wal, not places.sqlite.wal
        let walSource = URL(fileURLWithPath: sourcePath + "-wal")
        let shmSource = URL(fileURLWithPath: sourcePath + "-shm")
        let walDest = URL(fileURLWithPath: tempPath + "-wal")
        let shmDest = URL(fileURLWithPath: tempPath + "-shm")

        if fileManager.fileExists(atPath: walSource.path) {
            try? fileManager.copyItem(at: walSource, to: walDest)
        }

        if fileManager.fileExists(atPath: shmSource.path) {
            try? fileManager.copyItem(at: shmSource, to: shmDest)
        }
    }

    func openDatabase(at url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX

        let result = sqlite3_open_v2(url.path, &db, flags, nil)

        guard result == SQLITE_OK, let connection = db else {
            let errorMessage = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw ImportError.databaseError("Failed to open database: \(errorMessage)")
        }

        return connection
    }
}

// MARK: - Folder Map Building

private extension FirefoxImporter {
    struct FolderInfo {
        let name: String
        let parentID: Int64?
    }

    func buildFolderMap(db: OpaquePointer) throws -> [Int64: FolderInfo] {
        let query = """
        SELECT id, parent, title
        FROM moz_bookmarks
        WHERE type = 2 AND title IS NOT NULL
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw ImportError.databaseError("Failed to prepare folder query")
        }
        defer { sqlite3_finalize(statement) }

        var map: [Int64: FolderInfo] = [:]

        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            let parentID = sqlite3_column_int64(statement, 1)
            let title = extractString(from: statement, column: 2) ?? "Untitled"

            map[id] = FolderInfo(
                name: title,
                parentID: parentID == 0 ? nil : parentID,
            )
        }

        return map
    }
}

// MARK: - Bookmark Fetching

private extension FirefoxImporter {
    func fetchAndBuildBookmarks(
        db: OpaquePointer,
        folderMap: [Int64: FolderInfo],
    ) throws -> [ImportedFolder] {
        let query = """
        SELECT b.parent, b.title, b.dateAdded, p.url
        FROM moz_bookmarks b
        JOIN moz_places p ON b.fk = p.id
        WHERE b.type = 1 AND p.url NOT LIKE 'place:%'
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            throw ImportError.databaseError("Failed to prepare bookmarks query")
        }
        defer { sqlite3_finalize(statement) }

        var bookmarksByFolder: [Int64: [ImportedBookmark]] = [:]

        while sqlite3_step(statement) == SQLITE_ROW {
            if let bookmark = parseBookmarkRow(statement, folderMap: folderMap) {
                let parentID = sqlite3_column_int64(statement, 0)
                bookmarksByFolder[parentID, default: []].append(bookmark)
            }
        }

        return buildFolderTree(folderMap: folderMap, bookmarksByFolder: bookmarksByFolder)
    }

    func parseBookmarkRow(
        _ statement: OpaquePointer?,
        folderMap: [Int64: FolderInfo],
    ) -> ImportedBookmark? {
        guard let statement else { return nil }

        let parentID = sqlite3_column_int64(statement, 0)
        let title = extractString(from: statement, column: 1) ?? "Untitled"
        let dateAdded = sqlite3_column_int64(statement, 2)
        let urlString = extractString(from: statement, column: 3)

        guard
            let urlString,
            let url = URL(string: urlString)
        else {
            return nil
        }

        let folderPath = buildFolderPath(for: parentID, folderMap: folderMap)
        let date = Date(timeIntervalSince1970: Double(dateAdded) / 1_000_000)

        return ImportedBookmark(
            url: url,
            title: title,
            dateAdded: date,
            folderPath: folderPath,
        )
    }

    func buildFolderPath(for folderID: Int64, folderMap: [Int64: FolderInfo]) -> [String] {
        var path: [String] = []
        var currentID: Int64? = folderID

        while let id = currentID, let folder = folderMap[id] {
            path.insert(folder.name, at: 0)
            currentID = folder.parentID
        }

        return path
    }
}

// MARK: - Folder Tree Building

private extension FirefoxImporter {
    func buildFolderTree(
        folderMap: [Int64: FolderInfo],
        bookmarksByFolder: [Int64: [ImportedBookmark]],
    ) -> [ImportedFolder] {
        let rootFolderIDs = folderMap.filter { _, info in
            info.parentID == nil || folderMap[info.parentID!] == nil
        }.map(\.key)

        return rootFolderIDs.compactMap { folderID in
            buildFolder(
                id: folderID,
                folderMap: folderMap,
                bookmarksByFolder: bookmarksByFolder,
                path: [],
            )
        }
    }

    func buildFolder(
        id: Int64,
        folderMap: [Int64: FolderInfo],
        bookmarksByFolder: [Int64: [ImportedBookmark]],
        path: [String],
    ) -> ImportedFolder? {
        guard let info = folderMap[id] else { return nil }

        let currentPath = path + [info.name]
        let bookmarks = bookmarksByFolder[id] ?? []

        let childFolderIDs = folderMap.filter { $0.value.parentID == id }.map(\.key)

        let subfolders = childFolderIDs.compactMap { childID in
            buildFolder(
                id: childID,
                folderMap: folderMap,
                bookmarksByFolder: bookmarksByFolder,
                path: currentPath,
            )
        }

        if bookmarks.isEmpty, subfolders.isEmpty {
            return nil
        }

        return ImportedFolder(
            name: info.name,
            path: path,
            bookmarks: bookmarks,
            subfolders: subfolders,
        )
    }
}

// MARK: - SQLite Helpers

private extension FirefoxImporter {
    func extractString(from statement: OpaquePointer?, column: Int32) -> String? {
        guard let textPointer = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: textPointer)
    }
}
