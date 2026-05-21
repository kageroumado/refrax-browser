import Foundation
import SQLite3
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for Firefox bookmark import.
    @Tag static var firefoxImporter: Self
}

// MARK: - FirefoxImporter Basic Tests

@Suite("FirefoxImporter Basic", .tags(.firefoxImporter))
@MainActor
struct FirefoxImporterBasicTests {
    @Test("Import simple Firefox bookmarks")
    func importSimpleBookmarks() async throws {
        let data = FirefoxTestData(
            folders: [
                FirefoxTestFolder(id: 1, name: "Toolbar", parentId: nil),
            ],
            bookmarks: [
                FirefoxTestBookmark(title: "Example", url: "https://example.com", parentId: 1),
            ],
        )

        let (profileURL, cleanup) = try createMockFirefoxProfile(data: data)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .firefox)
        let importer = FirefoxImporter()

        #expect(importer.canImport(from: profile))

        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders.count == 1)
        #expect(folders[0].name == "Toolbar")
        #expect(folders[0].bookmarks.count == 1)
        #expect(folders[0].bookmarks[0].title == "Example")
    }

    @Test("Import multiple folders")
    func importMultipleFolders() async throws {
        let data = FirefoxTestData(
            folders: [
                FirefoxTestFolder(id: 1, name: "Toolbar", parentId: nil),
                FirefoxTestFolder(id: 2, name: "Menu", parentId: nil),
            ],
            bookmarks: [
                FirefoxTestBookmark(title: "Site 1", url: "https://site1.com", parentId: 1),
                FirefoxTestBookmark(title: "Site 2", url: "https://site2.com", parentId: 2),
            ],
        )

        let (profileURL, cleanup) = try createMockFirefoxProfile(data: data)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .firefox)
        let importer = FirefoxImporter()
        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders.count == 2)
    }

    @Test("Import nested folders")
    func importNestedFolders() async throws {
        let data = FirefoxTestData(
            folders: [
                FirefoxTestFolder(id: 1, name: "Root", parentId: nil),
                FirefoxTestFolder(id: 2, name: "Child", parentId: 1),
            ],
            bookmarks: [
                FirefoxTestBookmark(title: "Nested", url: "https://nested.com", parentId: 2),
            ],
        )

        let (profileURL, cleanup) = try createMockFirefoxProfile(data: data)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .firefox)
        let importer = FirefoxImporter()
        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders[0].subfolders.count == 1)
        #expect(folders[0].subfolders[0].name == "Child")
        #expect(folders[0].subfolders[0].bookmarks.count == 1)
    }

    @Test("canImport returns false for missing file")
    func canImportReturnsFalseForMissing() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let profile = BrowserProfile(id: "default", name: "Default", path: tempDir, browser: .firefox)
        let importer = FirefoxImporter()

        #expect(!importer.canImport(from: profile))
    }
}

// MARK: - FirefoxImporter Edge Cases

@Suite("FirefoxImporter Edge Cases", .tags(.firefoxImporter))
@MainActor
struct FirefoxImporterEdgeCaseTests {
    @Test("Handle bookmark with date")
    func handleBookmarkWithDate() async throws {
        // Firefox uses microseconds since Unix epoch
        let timestamp: Int64 = 1_609_459_200_000_000

        let data = FirefoxTestData(
            folders: [
                FirefoxTestFolder(id: 1, name: "Test", parentId: nil),
            ],
            bookmarks: [
                FirefoxTestBookmark(
                    title: "Dated",
                    url: "https://dated.com",
                    parentId: 1,
                    dateAdded: timestamp,
                ),
            ],
        )

        let (profileURL, cleanup) = try createMockFirefoxProfile(data: data)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .firefox)
        let importer = FirefoxImporter()
        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders[0].bookmarks[0].dateAdded != nil)
    }

    @Test("Handle invalid URLs")
    func handleInvalidUrls() async throws {
        let data = FirefoxTestData(
            folders: [
                FirefoxTestFolder(id: 1, name: "Test", parentId: nil),
            ],
            bookmarks: [
                FirefoxTestBookmark(title: "Valid", url: "https://valid.com", parentId: 1),
                FirefoxTestBookmark(title: "Invalid", url: "not a url", parentId: 1),
            ],
        )

        let (profileURL, cleanup) = try createMockFirefoxProfile(data: data)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .firefox)
        let importer = FirefoxImporter()
        let folders = try await importer.importBookmarks(from: profile)

        // URL(string:) may accept some "invalid" URLs
        // Verify at least the valid bookmark is present
        #expect(folders[0].bookmarks.count >= 1)
        #expect(folders[0].bookmarks.contains { $0.title == "Valid" })
    }

    @Test("Handle many bookmarks")
    func handleManyBookmarks() async throws {
        var bookmarks: [FirefoxTestBookmark] = []
        for i in 0 ..< 100 {
            bookmarks.append(FirefoxTestBookmark(
                title: "Site \(i)",
                url: "https://site\(i).com",
                parentId: 1,
            ))
        }

        let data = FirefoxTestData(
            folders: [
                FirefoxTestFolder(id: 1, name: "Large", parentId: nil),
            ],
            bookmarks: bookmarks,
        )

        let (profileURL, cleanup) = try createMockFirefoxProfile(data: data)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .firefox)
        let importer = FirefoxImporter()
        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders[0].bookmarks.count == 100)
    }

    @Test("Handle deeply nested folders")
    func handleDeeplyNested() async throws {
        let data = FirefoxTestData(
            folders: [
                FirefoxTestFolder(id: 1, name: "Level 1", parentId: nil),
                FirefoxTestFolder(id: 2, name: "Level 2", parentId: 1),
                FirefoxTestFolder(id: 3, name: "Level 3", parentId: 2),
            ],
            bookmarks: [
                FirefoxTestBookmark(title: "Deep", url: "https://deep.com", parentId: 3),
            ],
        )

        let (profileURL, cleanup) = try createMockFirefoxProfile(data: data)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .firefox)
        let importer = FirefoxImporter()
        let folders = try await importer.importBookmarks(from: profile)

        let level3 = folders[0].subfolders[0].subfolders[0]
        #expect(level3.name == "Level 3")
        #expect(level3.bookmarks.count == 1)
    }

    @Test("Handle empty folders")
    func handleEmptyFolders() async throws {
        let data = FirefoxTestData(
            folders: [
                FirefoxTestFolder(id: 1, name: "Empty", parentId: nil),
                FirefoxTestFolder(id: 2, name: "HasContent", parentId: nil),
            ],
            bookmarks: [
                FirefoxTestBookmark(title: "Test", url: "https://test.com", parentId: 2),
            ],
        )

        let (profileURL, cleanup) = try createMockFirefoxProfile(data: data)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .firefox)
        let importer = FirefoxImporter()
        let folders = try await importer.importBookmarks(from: profile)

        // Empty folders should be excluded
        #expect(folders.count == 1)
        #expect(folders[0].name == "HasContent")
    }
}

// MARK: - FirefoxImporter Folder Path Tests

@Suite("FirefoxImporter Folder Paths", .tags(.firefoxImporter))
@MainActor
struct FirefoxImporterFolderPathTests {
    @Test("Bookmark folder path is correct")
    func bookmarkFolderPathCorrect() async throws {
        let data = FirefoxTestData(
            folders: [
                FirefoxTestFolder(id: 1, name: "Root", parentId: nil),
                FirefoxTestFolder(id: 2, name: "Child", parentId: 1),
            ],
            bookmarks: [
                FirefoxTestBookmark(title: "Test", url: "https://test.com", parentId: 2),
            ],
        )

        let (profileURL, cleanup) = try createMockFirefoxProfile(data: data)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .firefox)
        let importer = FirefoxImporter()
        let folders = try await importer.importBookmarks(from: profile)

        let bookmark = folders[0].subfolders[0].bookmarks[0]
        #expect(bookmark.folderPath == ["Root", "Child"])
    }
}

// MARK: - Firefox Test Helpers

private struct FirefoxTestFolder {
    let id: Int64
    let name: String
    let parentId: Int64?
}

private struct FirefoxTestBookmark {
    let title: String
    let url: String
    let parentId: Int64
    var dateAdded: Int64 = 0
}

private struct FirefoxTestData {
    let folders: [FirefoxTestFolder]
    let bookmarks: [FirefoxTestBookmark]
}

private func createMockFirefoxProfile(data: FirefoxTestData) throws -> (URL, () -> Void) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("firefox_test_\(UUID().uuidString)")

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let dbPath = tempDir.appendingPathComponent("places.sqlite")

    var db: OpaquePointer?
    guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
        throw ImportError.databaseError("Failed to create test database")
    }
    defer { sqlite3_close(db) }

    // Create moz_bookmarks table
    let createBookmarks = """
    CREATE TABLE moz_bookmarks (
        id INTEGER PRIMARY KEY,
        type INTEGER,
        fk INTEGER,
        parent INTEGER,
        title TEXT,
        dateAdded INTEGER
    )
    """
    sqlite3_exec(db, createBookmarks, nil, nil, nil)

    // Create moz_places table
    let createPlaces = """
    CREATE TABLE moz_places (
        id INTEGER PRIMARY KEY,
        url TEXT,
        title TEXT
    )
    """
    sqlite3_exec(db, createPlaces, nil, nil, nil)

    // Insert folders (type = 2)
    for folder in data.folders {
        let parentValue = folder.parentId.map { String($0) } ?? "NULL"
        let escapedName = escapeSQL(folder.name)
        let insert = "INSERT INTO moz_bookmarks (id, type, parent, title) VALUES (\(folder.id), 2, \(parentValue), '\(escapedName)')"
        sqlite3_exec(db, insert, nil, nil, nil)
    }

    // Insert bookmarks (type = 1)
    var placeId: Int64 = 1_000
    for bookmark in data.bookmarks {
        let escapedUrl = escapeSQL(bookmark.url)
        let escapedTitle = escapeSQL(bookmark.title)

        // Insert into places
        let insertPlace = "INSERT INTO moz_places (id, url, title) VALUES (\(placeId), '\(escapedUrl)', '\(escapedTitle)')"
        sqlite3_exec(db, insertPlace, nil, nil, nil)

        // Insert into bookmarks
        let insertBookmark = "INSERT INTO moz_bookmarks (id, type, fk, parent, title, dateAdded) VALUES (\(placeId), 1, \(placeId), \(bookmark.parentId), '\(escapedTitle)', \(bookmark.dateAdded))"
        sqlite3_exec(db, insertBookmark, nil, nil, nil)

        placeId += 1
    }

    let cleanup: () -> Void = {
        _ = try? FileManager.default.removeItem(at: tempDir)
    }

    return (tempDir, cleanup)
}

private func escapeSQL(_ string: String) -> String {
    string.replacingOccurrences(of: "'", with: "''")
}
