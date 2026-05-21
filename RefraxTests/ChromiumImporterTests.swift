import Foundation
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for Chromium bookmark import.
    @Tag static var chromiumImporter: Self
}

// MARK: - ChromiumImporter Basic Tests

@Suite("ChromiumImporter Basic", .tags(.chromiumImporter))
@MainActor
struct ChromiumImporterBasicTests {
    @Test("Import simple Chrome bookmarks")
    func importSimpleChromeBookmarks() async throws {
        let json = """
        {
            "roots": {
                "bookmark_bar": {
                    "name": "Bookmarks bar",
                    "type": "folder",
                    "children": [
                        {
                            "name": "Example Site",
                            "type": "url",
                            "url": "https://example.com"
                        }
                    ]
                },
                "other": {
                    "name": "Other bookmarks",
                    "type": "folder",
                    "children": []
                },
                "synced": {
                    "name": "Mobile bookmarks",
                    "type": "folder",
                    "children": []
                }
            }
        }
        """

        let (profileURL, cleanup) = try createMockChromeProfile(bookmarksJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumImporter(browser: .chrome)

        #expect(importer.canImport(from: profile))

        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders.count >= 1)
        let bookmarkBar = folders.first(where: { $0.name == "Bookmarks bar" })
        #expect(bookmarkBar != nil)
        #expect(bookmarkBar?.bookmarks.count == 1)
        #expect(bookmarkBar?.bookmarks[0].title == "Example Site")
        #expect(bookmarkBar?.bookmarks[0].url.absoluteString == "https://example.com")
    }

    @Test("Import bookmarks with dates")
    func importBookmarksWithDates() async throws {
        // Chromium uses Windows FILETIME: microseconds since Jan 1, 1601
        // Jan 1, 2021 00:00:00 UTC = 13252108800000000 in FILETIME
        let chromiumTimestamp = "13252108800000000"

        let json = """
        {
            "roots": {
                "bookmark_bar": {
                    "name": "Bookmarks bar",
                    "type": "folder",
                    "children": [
                        {
                            "name": "Dated Bookmark",
                            "type": "url",
                            "url": "https://example.com",
                            "date_added": "\(chromiumTimestamp)"
                        }
                    ]
                },
                "other": { "name": "Other", "type": "folder", "children": [] },
                "synced": { "name": "Mobile", "type": "folder", "children": [] }
            }
        }
        """

        let (profileURL, cleanup) = try createMockChromeProfile(bookmarksJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumImporter(browser: .chrome)
        let folders = try await importer.importBookmarks(from: profile)

        let bookmark = folders.first?.bookmarks.first
        #expect(bookmark?.dateAdded != nil)
    }

    @Test("Import nested folders")
    func importNestedFolders() async throws {
        let json = """
        {
            "roots": {
                "bookmark_bar": {
                    "name": "Bookmarks bar",
                    "type": "folder",
                    "children": [
                        {
                            "name": "Parent Folder",
                            "type": "folder",
                            "children": [
                                {
                                    "name": "Child Folder",
                                    "type": "folder",
                                    "children": [
                                        {
                                            "name": "Deep Bookmark",
                                            "type": "url",
                                            "url": "https://deep.example.com"
                                        }
                                    ]
                                }
                            ]
                        }
                    ]
                },
                "other": { "name": "Other", "type": "folder", "children": [] },
                "synced": { "name": "Mobile", "type": "folder", "children": [] }
            }
        }
        """

        let (profileURL, cleanup) = try createMockChromeProfile(bookmarksJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumImporter(browser: .chrome)
        let folders = try await importer.importBookmarks(from: profile)

        let bookmarkBar = folders.first(where: { $0.name == "Bookmarks bar" })
        #expect(bookmarkBar?.subfolders.count == 1)
        #expect(bookmarkBar?.subfolders[0].name == "Parent Folder")
        #expect(bookmarkBar?.subfolders[0].subfolders[0].name == "Child Folder")
        #expect(bookmarkBar?.subfolders[0].subfolders[0].bookmarks[0].title == "Deep Bookmark")
    }

    @Test("canImport returns false for missing file")
    func canImportReturnsFalseForMissingFile() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let profile = BrowserProfile(id: "default", name: "Default", path: tempDir, browser: .chrome)
        let importer = ChromiumImporter(browser: .chrome)

        #expect(!importer.canImport(from: profile))
    }
}

// MARK: - ChromiumImporter Multiple Browsers

@Suite("ChromiumImporter Browsers", .tags(.chromiumImporter))
@MainActor
struct ChromiumImporterBrowserTests {
    @Test("Works with Brave browser")
    func worksWithBrave() async throws {
        let json = createMinimalBookmarksJSON(title: "Brave Test", url: "https://brave.com")

        let (profileURL, cleanup) = try createMockChromeProfile(bookmarksJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumImporter(browser: .brave)

        let folders = try await importer.importBookmarks(from: profile)
        #expect(folders.first?.bookmarks.first?.title == "Brave Test")
    }

    @Test("Works with Edge browser")
    func worksWithEdge() async throws {
        let json = createMinimalBookmarksJSON(title: "Edge Test", url: "https://microsoft.com")

        let (profileURL, cleanup) = try createMockChromeProfile(bookmarksJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumImporter(browser: .edge)

        let folders = try await importer.importBookmarks(from: profile)
        #expect(folders.first?.bookmarks.first?.title == "Edge Test")
    }

    @Test("Works with Opera browser")
    func worksWithOpera() async throws {
        let json = createMinimalBookmarksJSON(title: "Opera Test", url: "https://opera.com")

        let (profileURL, cleanup) = try createMockChromeProfile(bookmarksJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumImporter(browser: .opera)

        let folders = try await importer.importBookmarks(from: profile)
        #expect(folders.first?.bookmarks.first?.title == "Opera Test")
    }

    @Test("Works with Vivaldi browser")
    func worksWithVivaldi() async throws {
        let json = createMinimalBookmarksJSON(title: "Vivaldi Test", url: "https://vivaldi.com")

        let (profileURL, cleanup) = try createMockChromeProfile(bookmarksJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumImporter(browser: .vivaldi)

        let folders = try await importer.importBookmarks(from: profile)
        #expect(folders.first?.bookmarks.first?.title == "Vivaldi Test")
    }
}

// MARK: - ChromiumImporter Edge Cases

@Suite("ChromiumImporter Edge Cases", .tags(.chromiumImporter))
@MainActor
struct ChromiumImporterEdgeCaseTests {
    @Test("Handle empty children arrays")
    func handleEmptyChildren() async throws {
        let json = """
        {
            "roots": {
                "bookmark_bar": {
                    "name": "Bookmarks bar",
                    "type": "folder",
                    "children": []
                },
                "other": { "name": "Other", "type": "folder", "children": [] },
                "synced": { "name": "Mobile", "type": "folder", "children": [] }
            }
        }
        """

        let (profileURL, cleanup) = try createMockChromeProfile(bookmarksJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumImporter(browser: .chrome)
        let folders = try await importer.importBookmarks(from: profile)

        // Empty folders should be created
        #expect(folders.count == 3)
    }

    @Test("Handle missing name field")
    func handleMissingNameField() async throws {
        let json = """
        {
            "roots": {
                "bookmark_bar": {
                    "name": "Bookmarks bar",
                    "type": "folder",
                    "children": [
                        {
                            "type": "url",
                            "url": "https://example.com"
                        }
                    ]
                },
                "other": { "name": "Other", "type": "folder", "children": [] },
                "synced": { "name": "Mobile", "type": "folder", "children": [] }
            }
        }
        """

        let (profileURL, cleanup) = try createMockChromeProfile(bookmarksJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumImporter(browser: .chrome)
        let folders = try await importer.importBookmarks(from: profile)

        // Should use URL as fallback title
        let bookmark = folders.first?.bookmarks.first
        #expect(bookmark?.title == "https://example.com")
    }

    @Test("Handle invalid URLs")
    func handleInvalidURLs() async throws {
        let json = """
        {
            "roots": {
                "bookmark_bar": {
                    "name": "Bookmarks bar",
                    "type": "folder",
                    "children": [
                        {
                            "name": "Valid",
                            "type": "url",
                            "url": "https://valid.com"
                        },
                        {
                            "name": "Invalid",
                            "type": "url",
                            "url": "not a valid url"
                        },
                        {
                            "name": "Empty",
                            "type": "url",
                            "url": ""
                        }
                    ]
                },
                "other": { "name": "Other", "type": "folder", "children": [] },
                "synced": { "name": "Mobile", "type": "folder", "children": [] }
            }
        }
        """

        let (profileURL, cleanup) = try createMockChromeProfile(bookmarksJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumImporter(browser: .chrome)
        let folders = try await importer.importBookmarks(from: profile)

        // URL(string:) may accept some "invalid" URLs
        // Verify at least the valid bookmark is present
        #expect(folders.first?.bookmarks.count ?? 0 >= 1)
        #expect(folders.first?.bookmarks.contains { $0.title == "Valid" } == true)
    }

    @Test("Handle missing roots key throws error")
    func handleMissingRootsKeyThrowsError() async throws {
        let json = """
        {
            "version": 1,
            "checksum": "abc123"
        }
        """

        let (profileURL, cleanup) = try createMockChromeProfile(bookmarksJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumImporter(browser: .chrome)

        await #expect(throws: ImportError.self) {
            _ = try await importer.importBookmarks(from: profile)
        }
    }

    @Test("Handle invalid JSON throws error")
    func handleInvalidJSONThrowsError() async throws {
        let invalidJSON = "{ this is not valid json }"

        let (profileURL, cleanup) = try createMockChromeProfile(bookmarksJSON: invalidJSON)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumImporter(browser: .chrome)

        // JSON parsing errors come as NSError from JSONSerialization
        await #expect(throws: (any Error).self) {
            _ = try await importer.importBookmarks(from: profile)
        }
    }

    @Test("Handle special characters in bookmarks")
    func handleSpecialCharacters() async throws {
        let json = """
        {
            "roots": {
                "bookmark_bar": {
                    "name": "Bookmarks bar",
                    "type": "folder",
                    "children": [
                        {
                            "name": "Test <with> 'special' & \\"quotes\\"",
                            "type": "url",
                            "url": "https://example.com/path?query=test&other=value"
                        }
                    ]
                },
                "other": { "name": "Other", "type": "folder", "children": [] },
                "synced": { "name": "Mobile", "type": "folder", "children": [] }
            }
        }
        """

        let (profileURL, cleanup) = try createMockChromeProfile(bookmarksJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumImporter(browser: .chrome)
        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders.first?.bookmarks.count == 1)
    }

    @Test("Handle Unicode characters")
    func handleUnicodeCharacters() async throws {
        let json = """
        {
            "roots": {
                "bookmark_bar": {
                    "name": "日本語フォルダ",
                    "type": "folder",
                    "children": [
                        {
                            "name": "中文网站",
                            "type": "url",
                            "url": "https://example.com"
                        },
                        {
                            "name": "Emojiサイト 🎉",
                            "type": "url",
                            "url": "https://emoji.example.com"
                        }
                    ]
                },
                "other": { "name": "Other", "type": "folder", "children": [] },
                "synced": { "name": "Mobile", "type": "folder", "children": [] }
            }
        }
        """

        let (profileURL, cleanup) = try createMockChromeProfile(bookmarksJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumImporter(browser: .chrome)
        let folders = try await importer.importBookmarks(from: profile)

        let bookmarkBar = folders.first(where: { $0.name == "日本語フォルダ" })
        #expect(bookmarkBar != nil)
        #expect(bookmarkBar?.bookmarks.count == 2)
    }
}

// MARK: - ChromiumImporter All Root Folders

@Suite("ChromiumImporter Root Folders", .tags(.chromiumImporter))
@MainActor
struct ChromiumImporterRootFoldersTests {
    @Test("Imports all three root folders")
    func importsAllRootFolders() async throws {
        let json = """
        {
            "roots": {
                "bookmark_bar": {
                    "name": "Bookmarks bar",
                    "type": "folder",
                    "children": [
                        { "name": "Bar Bookmark", "type": "url", "url": "https://bar.com" }
                    ]
                },
                "other": {
                    "name": "Other bookmarks",
                    "type": "folder",
                    "children": [
                        { "name": "Other Bookmark", "type": "url", "url": "https://other.com" }
                    ]
                },
                "synced": {
                    "name": "Mobile bookmarks",
                    "type": "folder",
                    "children": [
                        { "name": "Mobile Bookmark", "type": "url", "url": "https://mobile.com" }
                    ]
                }
            }
        }
        """

        let (profileURL, cleanup) = try createMockChromeProfile(bookmarksJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumImporter(browser: .chrome)
        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders.count == 3)
        #expect(folders.contains(where: { $0.name == "Bookmarks bar" }))
        #expect(folders.contains(where: { $0.name == "Other bookmarks" }))
        #expect(folders.contains(where: { $0.name == "Mobile bookmarks" }))
    }
}

// MARK: - ChromiumImporter Folder Path Tests

@Suite("ChromiumImporter Folder Paths", .tags(.chromiumImporter))
@MainActor
struct ChromiumImporterFolderPathTests {
    @Test("Folder paths are correctly set")
    func folderPathsCorrectlySet() async throws {
        let json = """
        {
            "roots": {
                "bookmark_bar": {
                    "name": "Bookmarks bar",
                    "type": "folder",
                    "children": [
                        {
                            "name": "Level 1",
                            "type": "folder",
                            "children": [
                                {
                                    "name": "Level 2",
                                    "type": "folder",
                                    "children": [
                                        { "name": "Deep", "type": "url", "url": "https://deep.com" }
                                    ]
                                }
                            ]
                        }
                    ]
                },
                "other": { "name": "Other", "type": "folder", "children": [] },
                "synced": { "name": "Mobile", "type": "folder", "children": [] }
            }
        }
        """

        let (profileURL, cleanup) = try createMockChromeProfile(bookmarksJSON: json)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .chrome)
        let importer = ChromiumImporter(browser: .chrome)
        let folders = try await importer.importBookmarks(from: profile)

        let bookmarkBar = folders.first(where: { $0.name == "Bookmarks bar" })
        let level2 = bookmarkBar?.subfolders.first?.subfolders.first
        let bookmark = level2?.bookmarks.first

        #expect(bookmark?.folderPath == ["Bookmarks bar", "Level 1", "Level 2"])
    }
}

// MARK: - Helper Functions

private func createMinimalBookmarksJSON(title: String, url: String) -> String {
    """
    {
        "roots": {
            "bookmark_bar": {
                "name": "Bookmarks bar",
                "type": "folder",
                "children": [
                    { "name": "\(title)", "type": "url", "url": "\(url)" }
                ]
            },
            "other": { "name": "Other", "type": "folder", "children": [] },
            "synced": { "name": "Mobile", "type": "folder", "children": [] }
        }
    }
    """
}

private func createMockChromeProfile(bookmarksJSON: String) throws -> (URL, () -> Void) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("chrome_test_\(UUID().uuidString)")

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let bookmarksFile = tempDir.appendingPathComponent("Bookmarks")
    try bookmarksJSON.write(to: bookmarksFile, atomically: true, encoding: .utf8)

    let cleanup: () -> Void = {
        _ = try? FileManager.default.removeItem(at: tempDir)
    }

    return (tempDir, cleanup)
}
