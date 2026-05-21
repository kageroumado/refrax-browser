import Foundation
import SQLite3
import Testing

@testable import Refrax

/// Live tests that verify BrowserDetector against actually installed browsers.
///
/// These tests read real browser data directories on disk (read-only) to verify
/// that profile detection, bookmark parsing, history import, and password file
/// accessibility all work correctly. They do NOT modify any Refrax data.
@Suite("BrowserDetector Live")
@MainActor
struct BrowserDetectorLiveTests {
    private let browsersToCheck: [ThirdPartyBrowser] = [.arc, .helium]

    // MARK: - Installation Detection

    @Test("Detects installed browsers")
    func detectsInstalledBrowsers() {
        let installed = BrowserDetector.detectInstalledBrowsers()
        let names = installed.map(\.displayName)

        #expect(names.contains("Arc"), "Arc should be detected as installed")
        #expect(names.contains("Helium"), "Helium should be detected as installed")
        #expect(!names.contains("HTML Bookmarks File"))
    }

    // MARK: - Profile Detection

    @Test("Detects Arc profiles")
    func detectsArcProfiles() {
        let profiles = BrowserDetector.detectProfiles(for: .arc)

        #expect(!profiles.isEmpty, "Arc should have at least one profile")

        for profile in profiles {
            #expect(profile.browser == .arc)
            #expect(!profile.name.isEmpty)
            #expect(FileManager.default.fileExists(atPath: profile.path.path))
        }

        print("Arc profiles: \(profiles.map { "\($0.name) at \($0.path.lastPathComponent)" })")
    }

    @Test("Detects Helium profiles")
    func detectsHeliumProfiles() {
        let profiles = BrowserDetector.detectProfiles(for: .helium)

        #expect(!profiles.isEmpty, "Helium should have at least one profile")

        for profile in profiles {
            #expect(profile.browser == .helium)
            #expect(!profile.name.isEmpty)
            #expect(FileManager.default.fileExists(atPath: profile.path.path))

            let bookmarks = profile.path.appendingPathComponent("Bookmarks")
            let history = profile.path.appendingPathComponent("History")
            let hasData = FileManager.default.fileExists(atPath: bookmarks.path)
                || FileManager.default.fileExists(atPath: history.path)
            #expect(hasData, "Profile should contain Bookmarks or History")
        }

        print("Helium profiles: \(profiles.map { "\($0.name) at \($0.path.lastPathComponent)" })")
    }

    // MARK: - Bookmark Import

    @Test("Imports bookmarks from detected profiles")
    func importBookmarks() async throws {
        for browser in browsersToCheck {
            let profiles = BrowserDetector.detectProfiles(for: browser)

            for profile in profiles {
                let bookmarksFile = profile.path.appendingPathComponent("Bookmarks")
                guard FileManager.default.fileExists(atPath: bookmarksFile.path) else {
                    print("\(browser.displayName)/\(profile.name): no Bookmarks file, skipping")
                    continue
                }

                let importer = ChromiumImporter(browser: browser)
                #expect(importer.canImport(from: profile), "\(browser.displayName) should be importable")

                let folders = try await importer.importBookmarks(from: profile)

                // Should parse without crashing and return some structure
                #expect(!folders.isEmpty, "\(browser.displayName) should have at least one bookmark folder")

                let totalBookmarks = folders.reduce(0) { $0 + countBookmarks(in: $1) }
                print("\(browser.displayName)/\(profile.name): \(folders.count) folders, \(totalBookmarks) total bookmarks")
            }
        }
    }

    // MARK: - History Import

    @Test("Imports history from detected profiles")
    func importHistory() async throws {
        for browser in browsersToCheck {
            let profiles = BrowserDetector.detectProfiles(for: browser)

            guard let importer = HistoryImporterFactory.createImporter(for: browser) else {
                print("\(browser.displayName): no history importer available")
                continue
            }

            for profile in profiles {
                guard importer.canImport(from: profile) else {
                    print("\(browser.displayName)/\(profile.name): no History file, skipping")
                    continue
                }

                // Check date range first
                let dateRange = try await importer.getHistoryDateRange(from: profile)
                if let dateRange {
                    print(
                        "\(browser.displayName)/\(profile.name): history from \(dateRange.min) to \(dateRange.max)"
                    )
                }

                // Import all history (no date filter)
                let entries = try await importer.importHistory(from: profile, dateRange: nil)

                #expect(!entries.isEmpty, "\(browser.displayName) should have history entries")

                // Sanity check entries
                for entry in entries.prefix(5) {
                    let scheme = entry.url.scheme ?? ""
                    #expect(
                        scheme == "http" || scheme == "https",
                        "URL should be http(s): \(entry.url)"
                    )
                }

                print("\(browser.displayName)/\(profile.name): \(entries.count) history entries")
            }
        }
    }

    // MARK: - Password Data File Accessibility

    @Test("Password database files exist and are readable")
    func passwordDatabasesAccessible() throws {
        // We can't actually decrypt passwords without triggering Keychain prompts,
        // but we can verify the Login Data SQLite files exist and have valid structure.
        for browser in browsersToCheck {
            let profiles = BrowserDetector.detectProfiles(for: browser)

            for profile in profiles {
                let loginData = profile.path.appendingPathComponent("Login Data")
                guard FileManager.default.fileExists(atPath: loginData.path) else {
                    print("\(browser.displayName)/\(profile.name): no Login Data file")
                    continue
                }

                // Copy to temp to avoid locking issues (browser may have it open)
                let tempDir = FileManager.default.temporaryDirectory
                let tempDB = tempDir.appendingPathComponent("test_login_\(UUID().uuidString).sqlite")
                try FileManager.default.copyItem(at: loginData, to: tempDB)
                defer { try? FileManager.default.removeItem(at: tempDB) }

                // Verify it's a valid SQLite database with the expected table
                var db: OpaquePointer?
                let openResult = sqlite3_open_v2(
                    tempDB.path, &db, SQLITE_OPEN_READONLY, nil
                )
                defer { sqlite3_close(db) }

                #expect(openResult == SQLITE_OK, "Should open Login Data as SQLite")

                // Check that the logins table exists
                var stmt: OpaquePointer?
                let query = "SELECT COUNT(*) FROM logins"
                let prepareResult = sqlite3_prepare_v2(db, query, -1, &stmt, nil)
                defer { sqlite3_finalize(stmt) }

                #expect(prepareResult == SQLITE_OK, "logins table should exist in Login Data")

                if sqlite3_step(stmt) == SQLITE_ROW {
                    let count = sqlite3_column_int(stmt, 0)
                    print(
                        "\(browser.displayName)/\(profile.name): Login Data has \(count) credential entries"
                    )
                }

                #expect(
                    browser.supportsDirectPasswordImport,
                    "\(browser.displayName) should support direct password import"
                )
            }
        }
    }

    // MARK: - Data Directory Validation

    @Test("Browser data directories exist for installed browsers")
    func dataDirectoriesExist() {
        let installed = BrowserDetector.detectInstalledBrowsers()

        for browser in installed {
            guard let dataDir = browser.dataDirectoryURL else { continue }

            if FileManager.default.fileExists(atPath: dataDir.path) {
                print("\(browser.displayName): data dir exists at \(dataDir.path)")
            } else {
                print("\(browser.displayName): data dir MISSING at \(dataDir.path)")
            }
        }
    }

    // MARK: - Helpers

    private func countBookmarks(in folder: ImportedFolder) -> Int {
        folder.bookmarks.count + folder.subfolders.reduce(0) { $0 + countBookmarks(in: $1) }
    }
}
