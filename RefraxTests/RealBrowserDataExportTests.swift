import Foundation
import SQLite3
import Testing

@testable import Refrax

// MARK: - Chrome History SQLite Tests

/// Tests for Chrome/Chromium history database import using real-world export patterns.
@Suite("Chrome History Export", .tags(.historyImporter))
@MainActor
struct ChromeHistoryExportTests {
    @Test("Parse Chrome history export structure")
    func parseStructure() async throws {
        let dbURL = try testResourceURL("Chrome_History_Export.sqlite")

        // Create a temp directory to simulate a profile
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Copy the test database to simulate the profile structure
        let historyPath = tempDir.appendingPathComponent("History")
        try FileManager.default.copyItem(at: dbURL, to: historyPath)

        let profile = BrowserProfile(id: "default", name: "Default", path: tempDir, browser: .chrome)
        let importer = ChromiumHistoryImporter(browser: .chrome)

        let history = try await importer.importHistory(from: profile, dateRange: nil)

        // Should have 7 valid entries:
        // github.com, stackoverflow.com, developer.apple.com, duckduckgo.com, reddit.com,
        // example.com/path%20with%20spaces, example.com/日本語パス
        // Excluded: chrome://, chrome-extension://, about:blank (internal), hidden-page.com (hidden=1)
        #expect(history.count == 7)
    }

    @Test("Filters internal browser URLs")
    func filtersInternalUrls() async throws {
        let dbURL = try testResourceURL("Chrome_History_Export.sqlite")
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let historyPath = tempDir.appendingPathComponent("History")
        try FileManager.default.copyItem(at: dbURL, to: historyPath)

        let profile = BrowserProfile(id: "default", name: "Default", path: tempDir, browser: .chrome)
        let importer = ChromiumHistoryImporter(browser: .chrome)

        let history = try await importer.importHistory(from: profile, dateRange: nil)

        // Should not contain chrome:// or chrome-extension:// URLs
        let internalUrls = history.filter {
            $0.url.absoluteString.hasPrefix("chrome://") ||
                $0.url.absoluteString.hasPrefix("chrome-extension://") ||
                $0.url.absoluteString.hasPrefix("about:")
        }
        #expect(internalUrls.isEmpty)
    }

    @Test("Preserves visit counts")
    func preservesVisitCounts() async throws {
        let dbURL = try testResourceURL("Chrome_History_Export.sqlite")
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let historyPath = tempDir.appendingPathComponent("History")
        try FileManager.default.copyItem(at: dbURL, to: historyPath)

        let profile = BrowserProfile(id: "default", name: "Default", path: tempDir, browser: .chrome)
        let importer = ChromiumHistoryImporter(browser: .chrome)

        let history = try await importer.importHistory(from: profile, dateRange: nil)

        // GitHub should have 15 visits
        let github = history.first { $0.url.host == "github.com" }
        #expect(github?.visitCount == 15)

        // Stack Overflow should have 8 visits
        let stackoverflow = history.first { $0.url.host == "stackoverflow.com" }
        #expect(stackoverflow?.visitCount == 8)
    }

    @Test("Handles encoded URLs")
    func handlesEncodedUrls() async throws {
        let dbURL = try testResourceURL("Chrome_History_Export.sqlite")
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let historyPath = tempDir.appendingPathComponent("History")
        try FileManager.default.copyItem(at: dbURL, to: historyPath)

        let profile = BrowserProfile(id: "default", name: "Default", path: tempDir, browser: .chrome)
        let importer = ChromiumHistoryImporter(browser: .chrome)

        let history = try await importer.importHistory(from: profile, dateRange: nil)

        // Should include URL with encoded spaces
        let encodedUrl = history.first { $0.url.absoluteString.contains("path%20with%20spaces") }
        #expect(encodedUrl != nil)
    }

    @Test("Skips hidden entries")
    func skipsHiddenEntries() async throws {
        let dbURL = try testResourceURL("Chrome_History_Export.sqlite")
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let historyPath = tempDir.appendingPathComponent("History")
        try FileManager.default.copyItem(at: dbURL, to: historyPath)

        let profile = BrowserProfile(id: "default", name: "Default", path: tempDir, browser: .chrome)
        let importer = ChromiumHistoryImporter(browser: .chrome)

        let history = try await importer.importHistory(from: profile, dateRange: nil)

        // Should not contain the hidden entry
        let hiddenEntry = history.first { $0.url.host == "hidden-page.com" }
        #expect(hiddenEntry == nil)
    }
}

// MARK: - Safari Password CSV Tests

/// Tests for Safari password CSV export import.
@Suite("Safari Password Export", .tags(.passwordImporter))
@MainActor
struct SafariPasswordExportTests {
    @Test("Parse Safari password CSV structure")
    func parseStructure() async throws {
        let csvURL = try testResourceURL("Safari_Passwords_Export.csv")
        let importer = CSVPasswordImporter()

        let credentials = try await importer.importPasswords(from: csvURL)

        // Should have 8 credentials
        #expect(credentials.count == 8)
    }

    @Test("Detects Safari CSV format")
    func detectsSafariFormat() async throws {
        let csvURL = try testResourceURL("Safari_Passwords_Export.csv")
        let importer = CSVPasswordImporter()

        let credentials = try await importer.importPasswords(from: csvURL)

        // All credentials should have valid domains
        for credential in credentials {
            #expect(!credential.domain.isEmpty)
        }
    }

    @Test("Extracts domains correctly")
    func extractsDomains() async throws {
        let csvURL = try testResourceURL("Safari_Passwords_Export.csv")
        let importer = CSVPasswordImporter()

        let credentials = try await importer.importPasswords(from: csvURL)

        let domains = Set(credentials.map(\.domain))
        #expect(domains.contains("github.com"))
        #expect(domains.contains("gitlab.com"))
        #expect(domains.contains("stackoverflow.com"))
        #expect(domains.contains("developer.apple.com"))
    }

    @Test("Preserves usernames")
    func preservesUsernames() async throws {
        let csvURL = try testResourceURL("Safari_Passwords_Export.csv")
        let importer = CSVPasswordImporter()

        let credentials = try await importer.importPasswords(from: csvURL)

        let github = credentials.first { $0.domain == "github.com" }
        #expect(github?.username == "developer@example.com")
    }

    @Test("Handles notes field")
    func handlesNotesField() async throws {
        let csvURL = try testResourceURL("Safari_Passwords_Export.csv")
        let importer = CSVPasswordImporter()

        let credentials = try await importer.importPasswords(from: csvURL)

        // Notion entry has notes
        let notion = credentials.first { $0.domain == "notion.so" }
        #expect(notion?.notes == "Work notes")
    }
}

// MARK: - Safari History JSON Tests

/// Tests for Safari history JSON export format.
@Suite("Safari History JSON Export")
struct SafariHistoryJSONExportTests {
    @Test("Parse Safari history JSON structure")
    func parseStructure() throws {
        let jsonURL = try testResourceURL("Safari_History_Export.json")
        let data = try Data(contentsOf: jsonURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json != nil)

        // Verify metadata
        let metadata = json?["metadata"] as? [String: Any]
        #expect(metadata?["browser_name"] as? String == "Safari")
        #expect(metadata?["data_type"] as? String == "history")

        // Verify history array
        let history = json?["history"] as? [[String: Any]]
        #expect(history?.count == 8)
    }

    @Test("Parse Safari history entries")
    func parseHistoryEntries() throws {
        let jsonURL = try testResourceURL("Safari_History_Export.json")
        let data = try Data(contentsOf: jsonURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let history = json?["history"] as? [[String: Any]]
        let firstEntry = history?.first

        #expect(firstEntry?["url"] as? String == "https://github.com/")
        #expect(firstEntry?["title"] as? String == "GitHub")
        #expect(firstEntry?["visit_count"] as? Int == 25)
        #expect(firstEntry?["time_usec"] as? Int64 != nil)
    }

    @Test("Safari history contains various URL patterns")
    func containsVariousUrlPatterns() throws {
        let jsonURL = try testResourceURL("Safari_History_Export.json")
        let data = try Data(contentsOf: jsonURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let history = json?["history"] as? [[String: Any]]
        let urls = history?.compactMap { $0["url"] as? String } ?? []

        // Should contain search URL
        let hasSearchUrl = urls.contains { $0.contains("duckduckgo.com") && $0.contains("?q=") }
        #expect(hasSearchUrl)

        // Should contain encoded URL
        let hasEncodedUrl = urls.contains { $0.contains("%20") || $0.contains("日本語") }
        #expect(hasEncodedUrl)
    }
}

// MARK: - Firefox History SQLite Tests

/// Tests for Firefox/Zen history database structure.
/// Note: Firefox history import is not currently supported in production,
/// but these tests verify the test resource is correctly formatted.
@Suite("Firefox History Export")
struct FirefoxHistoryExportTests {
    @Test("Firefox history database structure is valid")
    func databaseStructureIsValid() throws {
        let dbURL = try testResourceURL("Firefox_History_Export.sqlite")

        var db: OpaquePointer?
        let result = sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(db) }

        #expect(result == SQLITE_OK)

        // Verify moz_places table exists
        let query = "SELECT COUNT(*) FROM moz_places"
        var statement: OpaquePointer?
        let prepareResult = sqlite3_prepare_v2(db, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }

        #expect(prepareResult == SQLITE_OK)
    }

    @Test("Firefox history has expected entries")
    func hasExpectedEntries() throws {
        let dbURL = try testResourceURL("Firefox_History_Export.sqlite")

        var db: OpaquePointer?
        sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(db) }

        let query = "SELECT url, title, visit_count FROM moz_places WHERE hidden = 0"
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }

        var entries: [(url: String, title: String?, visitCount: Int)] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let url = String(cString: sqlite3_column_text(statement, 0))
            let title = sqlite3_column_text(statement, 1).map { String(cString: $0) }
            let visitCount = Int(sqlite3_column_int(statement, 2))
            entries.append((url, title, visitCount))
        }

        // Should have 6 visible entries (hidden = 0)
        #expect(entries.count == 6)

        // Verify specific entries
        let github = entries.first { $0.url.contains("github.com") }
        #expect(github?.title == "GitHub")
        #expect(github?.visitCount == 20)
    }

    @Test("Firefox uses Unix timestamps")
    func usesUnixTimestamps() throws {
        let dbURL = try testResourceURL("Firefox_History_Export.sqlite")

        var db: OpaquePointer?
        sqlite3_open_v2(dbURL.path, &db, SQLITE_OPEN_READONLY, nil)
        defer { sqlite3_close(db) }

        let query = "SELECT last_visit_date FROM moz_places WHERE url = 'https://github.com/'"
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }

        #expect(sqlite3_step(statement) == SQLITE_ROW)

        let timestamp = sqlite3_column_int64(statement, 0)

        // Firefox timestamps are microseconds since Unix epoch
        // 1768318500000000 should be around Jan 2026
        let seconds = Double(timestamp) / 1_000_000
        let date = Date(timeIntervalSince1970: seconds)
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)

        #expect(year == 2_026)
    }
}

// MARK: - Firefox Password JSON Tests

/// Tests for Firefox logins.json structure.
/// Note: Firefox passwords are encrypted, so these tests verify structure only.
@Suite("Firefox Password Export")
struct FirefoxPasswordExportTests {
    @Test("Parse Firefox logins.json structure")
    func parseStructure() throws {
        let jsonURL = try testResourceURL("Firefox_Passwords_Export.json")
        let data = try Data(contentsOf: jsonURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        #expect(json != nil)

        // Verify version
        #expect(json?["version"] as? Int == 3)

        // Verify nextId
        #expect(json?["nextId"] as? Int == 5)

        // Verify logins array
        let logins = json?["logins"] as? [[String: Any]]
        #expect(logins?.count == 4)
    }

    @Test("Firefox login entries have required fields")
    func loginEntriesHaveRequiredFields() throws {
        let jsonURL = try testResourceURL("Firefox_Passwords_Export.json")
        let data = try Data(contentsOf: jsonURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let logins = json?["logins"] as? [[String: Any]]
        let firstLogin = logins?.first

        // Required fields for Firefox logins
        #expect(firstLogin?["id"] as? Int != nil)
        #expect(firstLogin?["hostname"] as? String != nil)
        #expect(firstLogin?["formSubmitURL"] as? String != nil)
        #expect(firstLogin?["usernameField"] as? String != nil)
        #expect(firstLogin?["passwordField"] as? String != nil)
        #expect(firstLogin?["encryptedUsername"] as? String != nil)
        #expect(firstLogin?["encryptedPassword"] as? String != nil)
        #expect(firstLogin?["guid"] as? String != nil)
        #expect(firstLogin?["encType"] as? Int != nil)
    }

    @Test("Firefox logins have timestamp metadata")
    func loginsHaveTimestamps() throws {
        let jsonURL = try testResourceURL("Firefox_Passwords_Export.json")
        let data = try Data(contentsOf: jsonURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let logins = json?["logins"] as? [[String: Any]]

        for login in logins ?? [] {
            #expect(login["timeCreated"] as? Int64 != nil)
            #expect(login["timeLastUsed"] as? Int64 != nil)
            #expect(login["timePasswordChanged"] as? Int64 != nil)
            #expect(login["timesUsed"] as? Int != nil)
        }
    }

    @Test("Firefox logins contain expected hostnames")
    func containsExpectedHostnames() throws {
        let jsonURL = try testResourceURL("Firefox_Passwords_Export.json")
        let data = try Data(contentsOf: jsonURL)
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]

        let logins = json?["logins"] as? [[String: Any]]
        let hostnames = logins?.compactMap { $0["hostname"] as? String } ?? []

        #expect(hostnames.contains("https://github.com"))
        #expect(hostnames.contains("https://gitlab.com"))
        #expect(hostnames.contains("https://stackoverflow.com"))
        #expect(hostnames.contains("https://twitter.com"))
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var passwordImporter: Self
}
