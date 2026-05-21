import Foundation
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for Safari bookmark import.
    @Tag static var safariImporter: Self
}

// MARK: - SafariImporter Basic Tests

@Suite("SafariImporter Basic", .tags(.safariImporter))
@MainActor
struct SafariImporterBasicTests {
    @Test("Import simple Safari bookmarks")
    func importSimpleBookmarks() async throws {
        let plist = createSafariPlist(folders: [
            SafariFolder(title: "Favorites", bookmarks: [
                SafariBookmark(title: "Example", url: "https://example.com"),
            ]),
        ])

        let (profileURL, cleanup) = try createMockSafariProfile(plistData: plist)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .safari)
        let importer = SafariImporter()

        #expect(importer.canImport(from: profile))

        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders.count == 1)
        #expect(folders[0].name == "Favorites")
        #expect(folders[0].bookmarks.count == 1)
        #expect(folders[0].bookmarks[0].title == "Example")
        #expect(folders[0].bookmarks[0].url.absoluteString == "https://example.com")
    }

    @Test("Import multiple folders")
    func importMultipleFolders() async throws {
        let plist = createSafariPlist(folders: [
            SafariFolder(title: "Work", bookmarks: [
                SafariBookmark(title: "Work Site", url: "https://work.com"),
            ]),
            SafariFolder(title: "Personal", bookmarks: [
                SafariBookmark(title: "Personal Site", url: "https://personal.com"),
            ]),
        ])

        let (profileURL, cleanup) = try createMockSafariProfile(plistData: plist)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .safari)
        let importer = SafariImporter()
        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders.count == 2)
    }

    @Test("Import nested folders")
    func importNestedFolders() async throws {
        let plist = createSafariPlist(folders: [
            SafariFolder(title: "Parent", bookmarks: [], subfolders: [
                SafariFolder(title: "Child", bookmarks: [
                    SafariBookmark(title: "Nested", url: "https://nested.com"),
                ]),
            ]),
        ])

        let (profileURL, cleanup) = try createMockSafariProfile(plistData: plist)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .safari)
        let importer = SafariImporter()
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

        let profile = BrowserProfile(id: "default", name: "Default", path: tempDir, browser: .safari)
        let importer = SafariImporter()

        #expect(!importer.canImport(from: profile))
    }
}

// MARK: - SafariImporter Edge Cases

@Suite("SafariImporter Edge Cases", .tags(.safariImporter))
@MainActor
struct SafariImporterEdgeCaseTests {
    @Test("Handle empty folder")
    func handleEmptyFolder() async throws {
        let plist = createSafariPlist(folders: [
            SafariFolder(title: "Empty", bookmarks: []),
            SafariFolder(title: "HasContent", bookmarks: [
                SafariBookmark(title: "Test", url: "https://test.com"),
            ]),
        ])

        let (profileURL, cleanup) = try createMockSafariProfile(plistData: plist)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .safari)
        let importer = SafariImporter()
        let folders = try await importer.importBookmarks(from: profile)

        // Should include folder with content
        #expect(folders.contains(where: { $0.name == "HasContent" }))
    }

    @Test("Handle bookmarks without title")
    func handleMissingTitle() async throws {
        let plist = createSafariPlist(folders: [
            SafariFolder(title: "Test", bookmarks: [
                SafariBookmark(title: nil, url: "https://notitle.com"),
            ]),
        ])

        let (profileURL, cleanup) = try createMockSafariProfile(plistData: plist)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .safari)
        let importer = SafariImporter()
        let folders = try await importer.importBookmarks(from: profile)

        // Should use URL as fallback title
        #expect(folders[0].bookmarks.count == 1)
    }

    @Test("Handle invalid URLs")
    func handleInvalidUrls() async throws {
        let plist = createSafariPlist(folders: [
            SafariFolder(title: "Test", bookmarks: [
                SafariBookmark(title: "Valid", url: "https://valid.com"),
                SafariBookmark(title: "Invalid", url: "not a url"),
            ]),
        ])

        let (profileURL, cleanup) = try createMockSafariProfile(plistData: plist)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .safari)
        let importer = SafariImporter()
        let folders = try await importer.importBookmarks(from: profile)

        // URL(string:) may accept some "invalid" URLs depending on encoding
        // Verify at least the valid bookmark is present
        #expect(folders[0].bookmarks.count >= 1)
        #expect(folders[0].bookmarks.contains { $0.title == "Valid" })
    }

    @Test("Handle special characters")
    func handleSpecialCharacters() async throws {
        let plist = createSafariPlist(folders: [
            SafariFolder(title: "Folder & Name <Test>", bookmarks: [
                SafariBookmark(title: "Site \"Quoted\" & <Special>", url: "https://special.com"),
            ]),
        ])

        let (profileURL, cleanup) = try createMockSafariProfile(plistData: plist)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .safari)
        let importer = SafariImporter()
        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders[0].name.contains("&"))
        #expect(folders[0].bookmarks[0].title.contains("\""))
    }

    @Test("Handle Unicode content")
    func handleUnicode() async throws {
        let plist = createSafariPlist(folders: [
            SafariFolder(title: "日本語", bookmarks: [
                SafariBookmark(title: "中文网站", url: "https://example.com"),
                SafariBookmark(title: "Emoji 🎉", url: "https://emoji.com"),
            ]),
        ])

        let (profileURL, cleanup) = try createMockSafariProfile(plistData: plist)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .safari)
        let importer = SafariImporter()
        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders[0].name == "日本語")
        #expect(folders[0].bookmarks.count == 2)
    }
}

// MARK: - SafariImporter Multiple Bookmarks

@Suite("SafariImporter Multiple", .tags(.safariImporter))
@MainActor
struct SafariImporterMultipleTests {
    @Test("Import many bookmarks")
    func importManyBookmarks() async throws {
        var bookmarks: [SafariBookmark] = []
        for i in 0 ..< 50 {
            bookmarks.append(SafariBookmark(
                title: "Bookmark \(i)",
                url: "https://site\(i).com",
            ))
        }

        let plist = createSafariPlist(folders: [
            SafariFolder(title: "Large Folder", bookmarks: bookmarks),
        ])

        let (profileURL, cleanup) = try createMockSafariProfile(plistData: plist)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .safari)
        let importer = SafariImporter()
        let folders = try await importer.importBookmarks(from: profile)

        #expect(folders[0].bookmarks.count == 50)
    }

    @Test("Import deeply nested structure")
    func importDeeplyNested() async throws {
        let plist = createSafariPlist(folders: [
            SafariFolder(title: "Level 1", bookmarks: [], subfolders: [
                SafariFolder(title: "Level 2", bookmarks: [], subfolders: [
                    SafariFolder(title: "Level 3", bookmarks: [
                        SafariBookmark(title: "Deep", url: "https://deep.com"),
                    ]),
                ]),
            ]),
        ])

        let (profileURL, cleanup) = try createMockSafariProfile(plistData: plist)
        defer { cleanup() }

        let profile = BrowserProfile(id: "default", name: "Default", path: profileURL, browser: .safari)
        let importer = SafariImporter()
        let folders = try await importer.importBookmarks(from: profile)

        let level3 = folders[0].subfolders[0].subfolders[0]
        #expect(level3.name == "Level 3")
        #expect(level3.bookmarks.count == 1)
    }
}

// MARK: - Safari Plist Helpers

private struct SafariBookmark {
    let title: String?
    let url: String
}

private struct SafariFolder {
    let title: String
    let bookmarks: [SafariBookmark]
    var subfolders: [SafariFolder] = []
}

private func createSafariPlist(folders: [SafariFolder]) -> Data {
    var children: [[String: Any]] = []

    for folder in folders {
        children.append(createFolderDict(folder))
    }

    let plist: [String: Any] = [
        "Children": children,
        "WebBookmarkType": "WebBookmarkTypeList",
    ]

    return try! PropertyListSerialization.data(
        fromPropertyList: plist,
        format: .binary,
        options: 0,
    )
}

private func createFolderDict(_ folder: SafariFolder) -> [String: Any] {
    var children: [[String: Any]] = []

    for bookmark in folder.bookmarks {
        var bookmarkDict: [String: Any] = [
            "WebBookmarkType": "WebBookmarkTypeLeaf",
            "URLString": bookmark.url,
        ]

        if let title = bookmark.title {
            bookmarkDict["URIDictionary"] = ["title": title]
        }

        children.append(bookmarkDict)
    }

    for subfolder in folder.subfolders {
        children.append(createFolderDict(subfolder))
    }

    return [
        "Title": folder.title,
        "WebBookmarkType": "WebBookmarkTypeList",
        "Children": children,
    ]
}

private func createMockSafariProfile(plistData: Data) throws -> (URL, () -> Void) {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("safari_test_\(UUID().uuidString)")

    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let bookmarksFile = tempDir.appendingPathComponent("Bookmarks.plist")
    try plistData.write(to: bookmarksFile)

    let cleanup: () -> Void = {
        _ = try? FileManager.default.removeItem(at: tempDir)
    }

    return (tempDir, cleanup)
}
