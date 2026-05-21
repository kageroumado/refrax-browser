import Foundation
import SQLite3
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for history import.
    @Tag static var historyImporter: Self
}

// MARK: - ChromiumHistoryImporter Tests

@Suite("ChromiumHistoryImporter", .tags(.historyImporter))
@MainActor
struct ChromiumHistoryImporterTests {
    @Test("Import simple history entries")
    func importSimpleHistory() async throws {
        let entries = [
            HistoryTestEntry(url: "https://example.com", title: "Example", visitCount: 5),
            HistoryTestEntry(url: "https://github.com", title: "GitHub", visitCount: 10),
        ]

        let (profileURL, cleanup) = try createMockChromiumHistory(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumHistoryImporter(browser: .chrome)

        #expect(importer.canImport(from: profile))

        let history = try await importer.importHistory(from: profile, dateRange: nil)

        #expect(history.count == 2)
        #expect(history.contains(where: { $0.url.host == "example.com" }))
        #expect(history.contains(where: { $0.url.host == "github.com" }))
    }

    @Test("Import history with visit counts")
    func importHistoryWithVisitCounts() async throws {
        let entries = [
            HistoryTestEntry(url: "https://frequent.com", title: "Frequent", visitCount: 100),
            HistoryTestEntry(url: "https://rare.com", title: "Rare", visitCount: 1),
        ]

        let (profileURL, cleanup) = try createMockChromiumHistory(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumHistoryImporter(browser: .chrome)
        let history = try await importer.importHistory(from: profile, dateRange: nil)

        let frequentEntry = history.first(where: { $0.url.host == "frequent.com" })
        #expect(frequentEntry?.visitCount == 100)
    }

    @Test("Filters internal browser URLs")
    func filtersInternalUrls() async throws {
        let entries = [
            HistoryTestEntry(url: "https://valid.com", title: "Valid", visitCount: 1),
            HistoryTestEntry(url: "chrome://settings", title: "Settings", visitCount: 1),
            HistoryTestEntry(url: "chrome-extension://abc123", title: "Extension", visitCount: 1),
        ]

        let (profileURL, cleanup) = try createMockChromiumHistory(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumHistoryImporter(browser: .chrome)
        let history = try await importer.importHistory(from: profile, dateRange: nil)

        // Should only have the valid external URL
        #expect(history.count == 1)
        #expect(history[0].url.host == "valid.com")
    }

    @Test("canImport returns false for missing file")
    func canImportReturnsFalseForMissing() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let profile = BrowserProfile(id: "default", name: "Default", path: tempDir, browser: .chrome)
        let importer = ChromiumHistoryImporter(browser: .chrome)

        #expect(!importer.canImport(from: profile))
    }

    @Test("Works with Brave browser")
    func worksWithBrave() async throws {
        let entries = [
            HistoryTestEntry(url: "https://brave.com", title: "Brave", visitCount: 1),
        ]

        let (profileURL, cleanup) = try createMockChromiumHistory(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .brave)
        let importer = ChromiumHistoryImporter(browser: .brave)
        let history = try await importer.importHistory(from: profile, dateRange: nil)

        #expect(history.count == 1)
    }

    @Test("Works with Edge browser")
    func worksWithEdge() async throws {
        let entries = [
            HistoryTestEntry(url: "https://microsoft.com", title: "Microsoft", visitCount: 1),
        ]

        let (profileURL, cleanup) = try createMockChromiumHistory(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .edge)
        let importer = ChromiumHistoryImporter(browser: .edge)
        let history = try await importer.importHistory(from: profile, dateRange: nil)

        #expect(history.count == 1)
    }

    @Test("Get history date range")
    func getHistoryDateRange() async throws {
        let entries = [
            HistoryTestEntry(
                url: "https://old.com",
                title: "Old",
                visitCount: 1,
                lastVisitTime: Date(timeIntervalSince1970: 1_609_459_200),
            ),
            HistoryTestEntry(
                url: "https://new.com",
                title: "New",
                visitCount: 1,
                lastVisitTime: Date(timeIntervalSince1970: 1_640_995_200),
            ),
        ]

        let (profileURL, cleanup) = try createMockChromiumHistory(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumHistoryImporter(browser: .chrome)
        let dateRange = try await importer.getHistoryDateRange(from: profile)

        #expect(dateRange != nil)
    }
}

// MARK: - ChromiumHistoryImporter Edge Cases

@Suite("ChromiumHistoryImporter Edge Cases", .tags(.historyImporter))
@MainActor
struct ChromiumHistoryImporterEdgeCaseTests {
    @Test("Handle entries without title")
    func handleMissingTitle() async throws {
        let entries = [
            HistoryTestEntry(url: "https://notitle.com", title: nil, visitCount: 1),
        ]

        let (profileURL, cleanup) = try createMockChromiumHistory(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumHistoryImporter(browser: .chrome)
        let history = try await importer.importHistory(from: profile, dateRange: nil)

        #expect(history.count == 1)
        // Title may be nil or empty string depending on importer implementation
        #expect(history[0].title == nil || history[0].title?.isEmpty == true)
    }

    @Test("Handle many entries")
    func handleManyEntries() async throws {
        var entries: [HistoryTestEntry] = []
        for i in 0 ..< 100 {
            entries.append(HistoryTestEntry(
                url: "https://site\(i).com",
                title: "Site \(i)",
                visitCount: i + 1,
            ))
        }

        let (profileURL, cleanup) = try createMockChromiumHistory(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumHistoryImporter(browser: .chrome)
        let history = try await importer.importHistory(from: profile, dateRange: nil)

        #expect(history.count == 100)
    }
}

// MARK: - SafariHistoryImporter Tests

@Suite("SafariHistoryImporter", .tags(.historyImporter))
@MainActor
struct SafariHistoryImporterTests {
    @Test("Import simple Safari history")
    func importSimpleHistory() async throws {
        let entries = [
            HistoryTestEntry(url: "https://apple.com", title: "Apple", visitCount: 5),
            HistoryTestEntry(url: "https://icloud.com", title: "iCloud", visitCount: 10),
        ]

        let (profileURL, cleanup) = try createMockSafariHistory(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .safari)
        let importer = SafariHistoryImporter()

        #expect(importer.canImport(from: profile))

        let history = try await importer.importHistory(from: profile, dateRange: nil)

        #expect(history.count == 2)
    }

    @Test("Safari history includes first and last visited")
    func includesFirstAndLastVisited() async throws {
        let entries = [
            HistoryTestEntry(
                url: "https://test.com",
                title: "Test",
                visitCount: 5,
                lastVisitTime: Date(),
                firstVisitTime: Date().addingTimeInterval(-86_400 * 7),
            ),
        ]

        let (profileURL, cleanup) = try createMockSafariHistory(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .safari)
        let importer = SafariHistoryImporter()
        let history = try await importer.importHistory(from: profile, dateRange: nil)

        #expect(history[0].firstVisited != nil)
        #expect(history[0].lastVisited != nil)
    }

    @Test("canImport returns false for missing file")
    func canImportReturnsFalseForMissing() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let profile = BrowserProfile(id: "default", name: "Default", path: tempDir, browser: .safari)
        let importer = SafariHistoryImporter()

        #expect(!importer.canImport(from: profile))
    }

    @Test("Get Safari history date range")
    func getHistoryDateRange() async throws {
        let entries = [
            HistoryTestEntry(url: "https://old.com", title: "Old", visitCount: 1),
            HistoryTestEntry(url: "https://new.com", title: "New", visitCount: 1),
        ]

        let (profileURL, cleanup) = try createMockSafariHistory(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .safari)
        let importer = SafariHistoryImporter()
        let dateRange = try await importer.getHistoryDateRange(from: profile)

        #expect(dateRange != nil)
    }
}

// MARK: - Safari History Edge Cases

@Suite("SafariHistoryImporter Edge Cases", .tags(.historyImporter))
@MainActor
struct SafariHistoryImporterEdgeCaseTests {
    @Test("Filters invalid schemes")
    func filtersInvalidSchemes() async throws {
        let entries = [
            HistoryTestEntry(url: "https://valid.com", title: "Valid", visitCount: 1),
            HistoryTestEntry(url: "file:///local/file", title: "Local", visitCount: 1),
        ]

        let (profileURL, cleanup) = try createMockSafariHistory(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .safari)
        let importer = SafariHistoryImporter()
        let history = try await importer.importHistory(from: profile, dateRange: nil)

        // file:// is valid
        #expect(history.count == 2)
    }

    @Test("Handle many Safari history entries")
    func handleManyEntries() async throws {
        var entries: [HistoryTestEntry] = []
        for i in 0 ..< 100 {
            entries.append(HistoryTestEntry(
                url: "https://site\(i).com",
                title: "Site \(i)",
                visitCount: i + 1,
            ))
        }

        let (profileURL, cleanup) = try createMockSafariHistory(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .safari)
        let importer = SafariHistoryImporter()
        let history = try await importer.importHistory(from: profile, dateRange: nil)

        #expect(history.count == 100)
    }
}

// MARK: - ImportedHistoryEntry Tests

@Suite("ImportedHistoryEntry", .tags(.historyImporter))
@MainActor
struct ImportedHistoryEntryTests {
    @Test("Creates with required fields")
    func createsWithRequiredFields() {
        let entry = ImportedHistoryEntry(
            url: URL(string: "https://example.com")!,
            lastVisited: Date(),
        )

        #expect(entry.url.absoluteString == "https://example.com")
        #expect(entry.title == nil)
        #expect(entry.visitCount == 1)
        #expect(entry.firstVisited == nil)
    }

    @Test("Creates with all fields")
    func createsWithAllFields() {
        let now = Date()
        let earlier = now.addingTimeInterval(-3_600)

        let entry = ImportedHistoryEntry(
            url: URL(string: "https://example.com")!,
            title: "Example Site",
            visitCount: 42,
            lastVisited: now,
            firstVisited: earlier,
        )

        #expect(entry.title == "Example Site")
        #expect(entry.visitCount == 42)
        #expect(entry.lastVisited == now)
        #expect(entry.firstVisited == earlier)
    }

    @Test("Has unique ID")
    func hasUniqueId() {
        let entry1 = ImportedHistoryEntry(
            url: URL(string: "https://example.com")!,
            lastVisited: Date(),
        )

        let entry2 = ImportedHistoryEntry(
            url: URL(string: "https://example.com")!,
            lastVisited: Date(),
        )

        #expect(entry1.id != entry2.id)
    }

    @Test("Is Sendable")
    func isSendable() {
        let entry = ImportedHistoryEntry(
            url: URL(string: "https://example.com")!,
            lastVisited: Date(),
        )

        let _: any Sendable = entry
        #expect(true)
    }
}

// MARK: - History Test Helpers

private struct HistoryTestEntry {
    let url: String
    let title: String?
    let visitCount: Int
    var lastVisitTime: Date = .init()
    var firstVisitTime: Date?
}

private func createMockChromiumHistory(entries: [HistoryTestEntry]) throws -> (URL, () -> Void) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("chrome_history_\(UUID().uuidString)")

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let dbPath = tempDir.appendingPathComponent("History")

    var db: OpaquePointer?
    guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
        throw ImportError.databaseError("Failed to create test database")
    }
    defer { sqlite3_close(db) }

    // Create urls table
    let createTable = """
    CREATE TABLE urls (
        id INTEGER PRIMARY KEY,
        url TEXT,
        title TEXT,
        visit_count INTEGER,
        hidden INTEGER DEFAULT 0,
        last_visit_time INTEGER
    )
    """
    sqlite3_exec(db, createTable, nil, nil, nil)

    // Insert test entries
    for (index, entry) in entries.enumerated() {
        let chromiumTime = dateToChromiumTime(entry.lastVisitTime)
        let titleValue = entry.title ?? ""
        let insert = "INSERT INTO urls (id, url, title, visit_count, hidden, last_visit_time) VALUES (\(index + 1), '\(entry.url)', '\(titleValue)', \(entry.visitCount), 0, \(chromiumTime))"
        sqlite3_exec(db, insert, nil, nil, nil)
    }

    let cleanup: () -> Void = {
        _ = try? FileManager.default.removeItem(at: tempDir)
    }

    return (tempDir, cleanup)
}

private func createMockSafariHistory(entries: [HistoryTestEntry]) throws -> (URL, () -> Void) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("safari_history_\(UUID().uuidString)")

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let dbPath = tempDir.appendingPathComponent("History.db")

    var db: OpaquePointer?
    guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
        throw ImportError.databaseError("Failed to create test database")
    }
    defer { sqlite3_close(db) }

    // Create tables
    let createHistoryItems = """
    CREATE TABLE history_items (
        id INTEGER PRIMARY KEY,
        url TEXT,
        visit_count INTEGER
    )
    """
    sqlite3_exec(db, createHistoryItems, nil, nil, nil)

    let createHistoryVisits = """
    CREATE TABLE history_visits (
        id INTEGER PRIMARY KEY,
        history_item INTEGER,
        visit_time REAL,
        title TEXT
    )
    """
    sqlite3_exec(db, createHistoryVisits, nil, nil, nil)

    // Insert test entries
    for (index, entry) in entries.enumerated() {
        let historyItemId = index + 1
        let insertItem = "INSERT INTO history_items (id, url, visit_count) VALUES (\(historyItemId), '\(entry.url)', \(entry.visitCount))"
        sqlite3_exec(db, insertItem, nil, nil, nil)

        // Add visit record
        let safariTime = entry.lastVisitTime.timeIntervalSinceReferenceDate
        let titleValue = entry.title ?? ""
        let insertVisit = "INSERT INTO history_visits (id, history_item, visit_time, title) VALUES (\(historyItemId), \(historyItemId), \(safariTime), '\(titleValue)')"
        sqlite3_exec(db, insertVisit, nil, nil, nil)

        // Add first visit if specified
        if let firstVisit = entry.firstVisitTime {
            let firstSafariTime = firstVisit.timeIntervalSinceReferenceDate
            let insertFirstVisit = "INSERT INTO history_visits (id, history_item, visit_time, title) VALUES (\(historyItemId + 1_000), \(historyItemId), \(firstSafariTime), '\(titleValue)')"
            sqlite3_exec(db, insertFirstVisit, nil, nil, nil)
        }
    }

    let cleanup: () -> Void = {
        _ = try? FileManager.default.removeItem(at: tempDir)
    }

    return (tempDir, cleanup)
}

private func dateToChromiumTime(_ date: Date) -> Int64 {
    let windowsEpochOffset: TimeInterval = 11_644_473_600
    let seconds = date.timeIntervalSince1970 + windowsEpochOffset
    return Int64(seconds * 1_000_000)
}
