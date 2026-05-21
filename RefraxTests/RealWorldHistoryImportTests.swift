import Foundation
import SQLite3
import Testing

@testable import Refrax

// MARK: - Real-World History Import Tests

/// Tests based on patterns observed in real browser history databases (Arc, Helium).
///
/// These tests exercise edge cases found in actual browser usage:
/// - Search engine query URLs with complex parameters
/// - OAuth/authentication callback URLs
/// - Chrome extension URLs (should be filtered)
/// - Unicode and special characters in titles
/// - Various internal browser URLs
@Suite("Real-World History Patterns", .tags(.historyImporter))
@MainActor
struct RealWorldHistoryPatternTests {
    @Test("Filters chrome-extension:// URLs")
    func filtersExtensionUrls() async throws {
        let entries = [
            TestHistoryEntry(
                url: "https://github.com/",
                title: "GitHub",
                visitCount: 10,
            ),
            TestHistoryEntry(
                url: "chrome-extension://cjpalhdlnbpafiamejdnhcphjbkeiagm/dashboard.html",
                title: "uBlock Origin Dashboard",
                visitCount: 5,
            ),
            TestHistoryEntry(
                url: "chrome-extension://cjpalhdlnbpafiamejdnhcphjbkeiagm/dashboard.html#settings.html",
                title: "uBlock Origin Settings",
                visitCount: 3,
            ),
        ]

        let history = try await importTestHistory(entries: entries)

        #expect(history.count == 1)
        #expect(history[0].url.host == "github.com")
    }

    @Test("Filters about:blank")
    func filtersAboutBlank() async throws {
        let entries = [
            TestHistoryEntry(url: "https://example.com", title: "Example", visitCount: 1),
            TestHistoryEntry(url: "about:blank", title: "", visitCount: 5),
        ]

        let history = try await importTestHistory(entries: entries)

        #expect(history.count == 1)
        #expect(history[0].url.absoluteString == "https://example.com")
    }

    @Test("Handles search engine URLs with complex query parameters")
    func handlesSearchEngineUrls() async throws {
        let entries = [
            TestHistoryEntry(
                url: "https://duckduckgo.com/?q=prism+album+cover+pink+floyd&iar=images&iai=http%3A%2F%2Fpinkfloydarchives.com%2FDiscog%2FAustral%2FLP%2FBS%2FPFB%2FPFB2%2FBC.jpg",
                title: "prism album cover pink floyd at DuckDuckGo",
                visitCount: 1,
            ),
            TestHistoryEntry(
                url: "https://www.google.com/search?q=swift+testing+framework&oq=swift+testing&gs_lcrp=EgZjaHJvbWUqBw&sourceid=chrome",
                title: "swift testing framework - Google Search",
                visitCount: 3,
            ),
        ]

        let history = try await importTestHistory(entries: entries)

        #expect(history.count == 2)

        let ddgEntry = history.first { $0.url.host == "duckduckgo.com" }
        #expect(ddgEntry != nil)
        #expect(ddgEntry?.url.absoluteString.contains("prism+album") == true)
    }

    @Test("Handles OAuth callback URLs")
    func handlesOAuthUrls() async throws {
        let entries = [
            TestHistoryEntry(
                url: "https://claude.ai/oauth/authorize?client_id=dae2cad8-15c5-43d2-9046-fcaecc135fa4&response_type=code&scope=user%3Aprofile+user%3Ainference+user%3Achat&redirect_uri=chrome-extension%3A%2F%2Ffcoeoabgfenejglbffodgkkbkcdhcgfn%2Foauth_callback.html",
                title: "Claude",
                visitCount: 1,
            ),
            TestHistoryEntry(
                url: "https://github.com/login/oauth/authorize?client_id=abc123&scope=repo",
                title: "Authorize GitHub",
                visitCount: 2,
            ),
        ]

        let history = try await importTestHistory(entries: entries)

        #expect(history.count == 2)
        #expect(history.contains { $0.url.host == "claude.ai" })
        #expect(history.contains { $0.url.host == "github.com" })
    }

    @Test("Handles URLs with encoded characters")
    func handlesEncodedUrls() async throws {
        let entries = [
            TestHistoryEntry(
                url: "https://example.com/path%20with%20spaces",
                title: "Path With Spaces",
                visitCount: 1,
            ),
            TestHistoryEntry(
                url: "https://example.com/日本語",
                title: "Japanese Path",
                visitCount: 1,
            ),
        ]

        let history = try await importTestHistory(entries: entries)

        #expect(history.count == 2)
    }

    @Test("Preserves high visit counts accurately")
    func preservesHighVisitCounts() async throws {
        let entries = [
            TestHistoryEntry(url: "https://njal.la/", title: "Njalla", visitCount: 8),
            TestHistoryEntry(url: "https://helium.computer/", title: "Helium Browser", visitCount: 6),
            TestHistoryEntry(url: "https://github.com/", title: "GitHub", visitCount: 2),
        ]

        let history = try await importTestHistory(entries: entries)

        let njalla = history.first { $0.url.host == "njal.la" }
        let helium = history.first { $0.url.host == "helium.computer" }
        let github = history.first { $0.url.host == "github.com" }

        #expect(njalla?.visitCount == 8)
        #expect(helium?.visitCount == 6)
        #expect(github?.visitCount == 2)
    }
}

// MARK: - Arc Browser Specific Tests

@Suite("Arc Browser History", .tags(.historyImporter))
@MainActor
struct ArcBrowserHistoryTests {
    @Test("Arc uses Chromium importer")
    func arcUsesChromiumImporter() {
        let importer = HistoryImporterFactory.createImporter(for: .arc)
        #expect(importer is ChromiumHistoryImporter)
    }

    @Test("Import Arc-style history entries")
    func importArcStyleHistory() async throws {
        // Based on real Arc history patterns
        let entries = [
            TestHistoryEntry(
                url: "https://zen-browser.app/download/",
                title: "Download - Zen",
                visitCount: 1,
            ),
            TestHistoryEntry(
                url: "https://njal.la/list/?search=refrax",
                title: "Njalla — Results",
                visitCount: 3,
            ),
        ]

        let (profileURL, cleanup) = try createMockChromiumHistoryDB(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .arc)
        let importer = ChromiumHistoryImporter(browser: .arc)

        let history = try await importer.importHistory(from: profile, dateRange: nil)

        #expect(history.count == 2)
    }

    @Test("Arc history with large entry count")
    func arcHistoryLargeCount() async throws {
        // Arc databases can have 100k+ entries
        var entries: [TestHistoryEntry] = []
        for i in 0 ..< 500 {
            entries.append(TestHistoryEntry(
                url: "https://site\(i).example.com/page/\(i)",
                title: "Site \(i) - Page Title",
                visitCount: (i % 10) + 1,
            ))
        }

        let history = try await importTestHistory(entries: entries, browser: .arc)

        #expect(history.count == 500)
    }
}

// MARK: - Chromium Time Conversion Tests

@Suite("Chromium Time Conversion", .tags(.historyImporter))
@MainActor
struct ChromiumTimeConversionTests {
    @Test("Converts real Chromium timestamps correctly")
    func convertsRealTimestamps() async throws {
        // Real timestamp from Arc history database
        // Chromium time = microseconds since January 1, 1601 (Windows FILETIME)
        // 13412800511062237 converts to approximately January 13, 2026 18:55 UTC
        let realTimestamp: Int64 = 13_412_800_511_062_237

        let entries = [
            TestHistoryEntry(
                url: "https://example.com",
                title: "Example",
                visitCount: 1,
                chromiumTime: realTimestamp,
            ),
        ]

        let (profileURL, cleanup) = try createMockChromiumHistoryDBWithRawTime(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumHistoryImporter(browser: .chrome)

        let history = try await importer.importHistory(from: profile, dateRange: nil)

        #expect(history.count == 1)

        // Verify the timestamp converts to a reasonable recent date
        let calendar = Calendar.current
        let year = calendar.component(.year, from: history[0].lastVisited)
        #expect(year == 2_026)

        // Verify it's not the Unix epoch (1970) or Windows epoch (1601)
        let month = calendar.component(.month, from: history[0].lastVisited)
        let day = calendar.component(.day, from: history[0].lastVisited)
        #expect(month == 1) // January
        #expect(day == 13 || day == 14) // 13th or 14th depending on timezone
    }

    @Test("Date range filtering with Chromium time")
    func dateRangeFilteringWithChromiumTime() async throws {
        let now = Date()
        let oneWeekAgo = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let twoWeeksAgo = now.addingTimeInterval(-14 * 24 * 60 * 60)

        let entries = [
            TestHistoryEntry(
                url: "https://recent.com",
                title: "Recent",
                visitCount: 1,
                lastVisitTime: now,
            ),
            TestHistoryEntry(
                url: "https://old.com",
                title: "Old",
                visitCount: 1,
                lastVisitTime: twoWeeksAgo,
            ),
        ]

        let (profileURL, cleanup) = try createMockChromiumHistoryDB(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumHistoryImporter(browser: .chrome)

        // Filter to only last week
        let dateRange = oneWeekAgo ... now
        let history = try await importer.importHistory(from: profile, dateRange: dateRange)

        #expect(history.count == 1)
        #expect(history[0].url.host == "recent.com")
    }

    @Test("Get date range returns correct min/max")
    func getDateRangeReturnsCorrectMinMax() async throws {
        let now = Date()
        let oneMonthAgo = now.addingTimeInterval(-30 * 24 * 60 * 60)

        let entries = [
            TestHistoryEntry(url: "https://new.com", title: "New", visitCount: 1, lastVisitTime: now),
            TestHistoryEntry(url: "https://old.com", title: "Old", visitCount: 1, lastVisitTime: oneMonthAgo),
        ]

        let (profileURL, cleanup) = try createMockChromiumHistoryDB(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumHistoryImporter(browser: .chrome)

        let range = try await importer.getHistoryDateRange(from: profile)

        #expect(range != nil)

        // Min should be approximately one month ago
        let minDiff = abs(range!.min.timeIntervalSince(oneMonthAgo))
        #expect(minDiff < 60) // Within a minute tolerance

        // Max should be approximately now
        let maxDiff = abs(range!.max.timeIntervalSince(now))
        #expect(maxDiff < 60)
    }
}

// MARK: - URL Filtering Edge Cases

@Suite("URL Filtering Edge Cases", .tags(.historyImporter))
@MainActor
struct URLFilteringEdgeCaseTests {
    @Test("Filters all browser-specific schemes")
    func filtersAllBrowserSchemes() async throws {
        let entries = [
            TestHistoryEntry(url: "https://valid.com", title: "Valid", visitCount: 1),
            TestHistoryEntry(url: "chrome://settings", title: "Chrome Settings", visitCount: 1),
            TestHistoryEntry(url: "chrome://extensions", title: "Extensions", visitCount: 1),
            TestHistoryEntry(url: "edge://settings", title: "Edge Settings", visitCount: 1),
            TestHistoryEntry(url: "brave://settings", title: "Brave Settings", visitCount: 1),
            TestHistoryEntry(url: "opera://settings", title: "Opera Settings", visitCount: 1),
            TestHistoryEntry(url: "vivaldi://settings", title: "Vivaldi Settings", visitCount: 1),
        ]

        let history = try await importTestHistory(entries: entries)

        #expect(history.count == 1)
        #expect(history[0].url.absoluteString == "https://valid.com")
    }

    @Test("Allows file:// URLs")
    func allowsFileUrls() async throws {
        let entries = [
            TestHistoryEntry(url: "https://web.com", title: "Web", visitCount: 1),
            TestHistoryEntry(url: "file:///Users/test/document.html", title: "Local Doc", visitCount: 1),
        ]

        let history = try await importTestHistory(entries: entries)

        #expect(history.count == 2)
        #expect(history.contains { $0.url.scheme == "file" })
    }

    @Test("Handles malformed URLs gracefully")
    func handlesMalformedUrls() async throws {
        let entries = [
            TestHistoryEntry(url: "https://valid.com", title: "Valid", visitCount: 1),
            TestHistoryEntry(url: "not a valid url", title: "Invalid", visitCount: 1),
            TestHistoryEntry(url: "", title: "Empty", visitCount: 1),
        ]

        let history = try await importTestHistory(entries: entries)

        // Should only have the valid URL
        #expect(history.count == 1)
        #expect(history[0].url.absoluteString == "https://valid.com")
    }

    @Test("Skips hidden entries")
    func skipsHiddenEntries() async throws {
        let entries = [
            TestHistoryEntry(url: "https://visible.com", title: "Visible", visitCount: 1, hidden: false),
            TestHistoryEntry(url: "https://hidden.com", title: "Hidden", visitCount: 1, hidden: true),
        ]

        let (profileURL, cleanup) = try createMockChromiumHistoryDBWithHidden(entries: entries)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumHistoryImporter(browser: .chrome)

        let history = try await importer.importHistory(from: profile, dateRange: nil)

        #expect(history.count == 1)
        #expect(history[0].url.host == "visible.com")
    }
}

// MARK: - Test Helpers

private struct TestHistoryEntry {
    let url: String
    let title: String?
    let visitCount: Int
    var lastVisitTime: Date = .init()
    var chromiumTime: Int64?
    var hidden: Bool = false
}

@MainActor
private func importTestHistory(
    entries: [TestHistoryEntry],
    browser: ThirdPartyBrowser = .chrome,
) async throws -> [ImportedHistoryEntry] {
    let (profileURL, cleanup) = try createMockChromiumHistoryDB(entries: entries)
    defer { cleanup() }

    let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: browser)
    let importer = ChromiumHistoryImporter(browser: browser)

    return try await importer.importHistory(from: profile, dateRange: nil)
}

private func createMockChromiumHistoryDB(entries: [TestHistoryEntry]) throws -> (URL, () -> Void) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("chrome_history_\(UUID().uuidString)")

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let dbPath = tempDir.appendingPathComponent("History")

    var db: OpaquePointer?
    guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
        throw ImportError.databaseError("Failed to create test database")
    }
    defer { sqlite3_close(db) }

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

    for (index, entry) in entries.enumerated() {
        let chromiumTime = dateToChromiumTimeValue(entry.lastVisitTime)
        let titleValue = entry.title?.replacingOccurrences(of: "'", with: "''") ?? ""
        let urlValue = entry.url.replacingOccurrences(of: "'", with: "''")
        let insert = """
        INSERT INTO urls (id, url, title, visit_count, hidden, last_visit_time)
        VALUES (\(index + 1), '\(urlValue)', '\(titleValue)', \(entry.visitCount), 0, \(chromiumTime))
        """
        sqlite3_exec(db, insert, nil, nil, nil)
    }

    let cleanup: () -> Void = {
        _ = try? FileManager.default.removeItem(at: tempDir)
    }

    return (tempDir, cleanup)
}

private func createMockChromiumHistoryDBWithRawTime(entries: [TestHistoryEntry]) throws -> (URL, () -> Void) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("chrome_history_\(UUID().uuidString)")

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let dbPath = tempDir.appendingPathComponent("History")

    var db: OpaquePointer?
    guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
        throw ImportError.databaseError("Failed to create test database")
    }
    defer { sqlite3_close(db) }

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

    for (index, entry) in entries.enumerated() {
        let chromiumTime = entry.chromiumTime ?? dateToChromiumTimeValue(entry.lastVisitTime)
        let titleValue = entry.title?.replacingOccurrences(of: "'", with: "''") ?? ""
        let urlValue = entry.url.replacingOccurrences(of: "'", with: "''")
        let insert = """
        INSERT INTO urls (id, url, title, visit_count, hidden, last_visit_time)
        VALUES (\(index + 1), '\(urlValue)', '\(titleValue)', \(entry.visitCount), 0, \(chromiumTime))
        """
        sqlite3_exec(db, insert, nil, nil, nil)
    }

    let cleanup: () -> Void = {
        _ = try? FileManager.default.removeItem(at: tempDir)
    }

    return (tempDir, cleanup)
}

private func createMockChromiumHistoryDBWithHidden(entries: [TestHistoryEntry]) throws -> (URL, () -> Void) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("chrome_history_\(UUID().uuidString)")

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let dbPath = tempDir.appendingPathComponent("History")

    var db: OpaquePointer?
    guard sqlite3_open(dbPath.path, &db) == SQLITE_OK else {
        throw ImportError.databaseError("Failed to create test database")
    }
    defer { sqlite3_close(db) }

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

    for (index, entry) in entries.enumerated() {
        let chromiumTime = dateToChromiumTimeValue(entry.lastVisitTime)
        let titleValue = entry.title?.replacingOccurrences(of: "'", with: "''") ?? ""
        let urlValue = entry.url.replacingOccurrences(of: "'", with: "''")
        let hiddenValue = entry.hidden ? 1 : 0
        let insert = """
        INSERT INTO urls (id, url, title, visit_count, hidden, last_visit_time)
        VALUES (\(index + 1), '\(urlValue)', '\(titleValue)', \(entry.visitCount), \(hiddenValue), \(chromiumTime))
        """
        sqlite3_exec(db, insert, nil, nil, nil)
    }

    let cleanup: () -> Void = {
        _ = try? FileManager.default.removeItem(at: tempDir)
    }

    return (tempDir, cleanup)
}

private func dateToChromiumTimeValue(_ date: Date) -> Int64 {
    let windowsEpochOffset: TimeInterval = 11_644_473_600
    let seconds = date.timeIntervalSince1970 + windowsEpochOffset
    return Int64(seconds * 1_000_000)
}
