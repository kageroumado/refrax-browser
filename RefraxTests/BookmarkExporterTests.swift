import Foundation
import SwiftData
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for bookmark export functionality.
    @Tag static var bookmarkExporter: Self
}

// MARK: - BookmarkExporter Tests

/// All BookmarkExporter tests in a single suite to avoid file collision issues.
/// The exporter writes to a fixed filename based on date, so tests must run serially.
@Suite("BookmarkExporter", .tags(.bookmarkExporter), .serialized)
@MainActor
struct BookmarkExporterTests {
    let container: ModelContainer

    init() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        self.container = try ModelContainer(for: schema, configurations: [config])
    }

    // MARK: - Basic Export Tests

    @Test("Export empty bookmarks produces valid HTML")
    func exportEmptyBookmarks() async throws {
        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("<!DOCTYPE NETSCAPE-Bookmark-file-1>"))
        #expect(content.contains("<TITLE>Refrax Bookmarks</TITLE>"))
        #expect(content.contains("<H1>Refrax Bookmarks</H1>"))
        #expect(content.contains("<DL><p>"))
        #expect(content.contains("</DL><p>"))
    }

    @Test("Export root bookmark")
    func exportRootBookmark() async throws {
        let context = container.mainContext
        let bookmark = Bookmark(url: URL(string: "https://example.com")!, title: "Example Site")
        context.insert(bookmark)
        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("Example Site"))
        #expect(content.contains("https://example.com"))
        #expect(content.contains("<DT><A HREF="))
        #expect(content.contains("ADD_DATE="))
    }

    @Test("Export folder with bookmarks")
    func exportFolderWithBookmarks() async throws {
        let context = container.mainContext

        let folder = BookmarkFolder(name: "My Folder", position: 0)
        context.insert(folder)

        let bookmark = Bookmark(url: URL(string: "https://test.com")!, title: "Test Site")
        bookmark.folder = folder
        context.insert(bookmark)

        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("<DT><H3"))
        #expect(content.contains("My Folder"))
        #expect(content.contains("Test Site"))
        #expect(content.contains("https://test.com"))
    }

    // MARK: - Nested Structure Tests

    @Test("Export nested folders")
    func exportNestedFolders() async throws {
        let context = container.mainContext

        let parentFolder = BookmarkFolder(name: "ParentFolder", position: 0)
        context.insert(parentFolder)

        let childFolder = BookmarkFolder(name: "ChildFolder", position: 0)
        childFolder.parentFolder = parentFolder
        context.insert(childFolder)

        let bookmark = Bookmark(url: URL(string: "https://nested.com")!, title: "Nested Bookmark")
        bookmark.folder = childFolder
        context.insert(bookmark)

        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        // Verify all elements are present
        #expect(content.contains("ParentFolder"))
        #expect(content.contains("ChildFolder"))
        #expect(content.contains("Nested Bookmark"))
        #expect(content.contains("https://nested.com"))
    }

    @Test("Export deeply nested folders")
    func exportDeeplyNestedFolders() async throws {
        let context = container.mainContext

        let level1 = BookmarkFolder(name: "Level1", position: 0)
        context.insert(level1)

        let level2 = BookmarkFolder(name: "Level2", position: 0)
        level2.parentFolder = level1
        context.insert(level2)

        let level3 = BookmarkFolder(name: "Level3", position: 0)
        level3.parentFolder = level2
        context.insert(level3)

        let bookmark = Bookmark(url: URL(string: "https://deep.com")!, title: "Deep Bookmark")
        bookmark.folder = level3
        context.insert(bookmark)

        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("Level1"))
        #expect(content.contains("Level2"))
        #expect(content.contains("Level3"))
        #expect(content.contains("Deep Bookmark"))
    }

    // MARK: - HTML Escaping Tests

    @Test("Escape ampersand in title")
    func escapeAmpersand() async throws {
        let context = container.mainContext

        let bookmark = Bookmark(
            url: URL(string: "https://example.com")!,
            title: "Tom & Jerry",
        )
        context.insert(bookmark)
        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("Tom &amp; Jerry"))
        #expect(!content.contains("Tom & Jerry</A>"))
    }

    @Test("Escape less than and greater than in title")
    func escapeLtGt() async throws {
        let context = container.mainContext

        let bookmark = Bookmark(
            url: URL(string: "https://example.com")!,
            title: "<script>alert('xss')</script>",
        )
        context.insert(bookmark)
        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("&lt;script&gt;"))
        #expect(!content.contains("<script>alert"))
    }

    @Test("Escape quotes in title")
    func escapeQuotes() async throws {
        let context = container.mainContext

        let bookmark = Bookmark(
            url: URL(string: "https://example.com")!,
            title: "Said \"Hello\"",
        )
        context.insert(bookmark)
        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("Said &quot;Hello&quot;"))
    }

    @Test("Escape special characters in folder name")
    func escapeFolderName() async throws {
        let context = container.mainContext

        let folder = BookmarkFolder(name: "Work & Personal <2024>", position: 0)
        context.insert(folder)

        let bookmark = Bookmark(url: URL(string: "https://test.com")!, title: "Test")
        bookmark.folder = folder
        context.insert(bookmark)

        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("Work &amp; Personal &lt;2024&gt;"))
    }

    @Test("Escape special characters in URL")
    func escapeUrl() async throws {
        let context = container.mainContext

        let bookmark = Bookmark(
            url: URL(string: "https://example.com/search?q=a&b=c")!,
            title: "Search",
        )
        context.insert(bookmark)
        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("https://example.com/search?q=a&amp;b=c"))
    }

    // MARK: - Unicode Tests

    @Test("Export bookmark with Unicode title")
    func exportUnicodeTitle() async throws {
        let context = container.mainContext

        let bookmark = Bookmark(
            url: URL(string: "https://example.com")!,
            title: "日本語タイトル",
        )
        context.insert(bookmark)
        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("日本語タイトル"))
    }

    @Test("Export folder with Unicode name")
    func exportUnicodeFolderName() async throws {
        let context = container.mainContext

        let folder = BookmarkFolder(name: "中文文件夹", position: 0)
        context.insert(folder)

        let bookmark = Bookmark(url: URL(string: "https://test.com")!, title: "Test")
        bookmark.folder = folder
        context.insert(bookmark)

        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("中文文件夹"))
    }

    @Test("Export bookmark with emoji in title")
    func exportEmojiTitle() async throws {
        let context = container.mainContext

        let bookmark = Bookmark(
            url: URL(string: "https://example.com")!,
            title: "Fun Site 🎉🎊",
        )
        context.insert(bookmark)
        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("Fun Site 🎉🎊"))
    }

    @Test("Export mixed languages")
    func exportMixedLanguages() async throws {
        let context = container.mainContext

        let folder = BookmarkFolder(name: "Bookmarks 书签 ブックマーク", position: 0)
        context.insert(folder)

        let bookmark = Bookmark(
            url: URL(string: "https://test.com")!,
            title: "Hello 你好 こんにちは مرحبا",
        )
        bookmark.folder = folder
        context.insert(bookmark)

        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("Bookmarks 书签 ブックマーク"))
        #expect(content.contains("Hello 你好 こんにちは مرحبا"))
    }

    // MARK: - Timestamp Tests

    @Test("Export bookmark with ADD_DATE timestamp")
    func exportBookmarkTimestamp() async throws {
        let context = container.mainContext

        let bookmark = Bookmark(
            url: URL(string: "https://example.com")!,
            title: "Test",
        )
        context.insert(bookmark)
        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        // Should contain ADD_DATE with a reasonable Unix timestamp
        let pattern = #"ADD_DATE=\"(\d+)\""#
        let regex = try NSRegularExpression(pattern: pattern)
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)

        #expect(!matches.isEmpty)

        if let match = matches.first, let timestampRange = Range(match.range(at: 1), in: content) {
            let timestamp = Int(content[timestampRange])!
            // Should be a reasonable Unix timestamp (after year 2000)
            #expect(timestamp > 946_684_800)
        }
    }

    @Test("Export folder with ADD_DATE and LAST_MODIFIED timestamps")
    func exportFolderTimestamps() async throws {
        let context = container.mainContext

        let folder = BookmarkFolder(name: "Test Folder", position: 0)
        context.insert(folder)

        let bookmark = Bookmark(url: URL(string: "https://test.com")!, title: "Test")
        bookmark.folder = folder
        context.insert(bookmark)

        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        // The H3 folder tag should have both ADD_DATE and LAST_MODIFIED
        let folderPattern = #"<DT><H3 ADD_DATE=\"\d+\" LAST_MODIFIED=\"\d+\">"#
        let regex = try NSRegularExpression(pattern: folderPattern)
        let range = NSRange(content.startIndex..., in: content)
        let matches = regex.matches(in: content, range: range)

        #expect(!matches.isEmpty)
    }

    // MARK: - File Output Tests

    @Test("Export creates file with correct name format")
    func exportCreatesFileWithCorrectName() async throws {
        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let filename = fileURL.lastPathComponent
        #expect(filename.hasPrefix("Refrax_Bookmarks_"))
        #expect(filename.hasSuffix(".html"))
    }

    @Test("Export creates file in temporary directory")
    func exportCreatesFileInTempDirectory() async throws {
        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let tempDir = FileManager.default.temporaryDirectory
        #expect(fileURL.path.hasPrefix(tempDir.path))
    }

    @Test("Export file is readable as UTF-8")
    func exportFileIsUtf8() async throws {
        let context = container.mainContext

        let bookmark = Bookmark(
            url: URL(string: "https://example.com")!,
            title: "UTF-8 Test: äöü ñ 中文",
        )
        context.insert(bookmark)
        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        // Should not throw
        let content = try String(contentsOf: fileURL, encoding: .utf8)

        #expect(content.contains("UTF-8"))
        #expect(content.contains("charset=UTF-8"))
    }

    @Test("Export produces well-formed HTML structure")
    func exportProducesWellFormedHtml() async throws {
        let context = container.mainContext

        let folder = BookmarkFolder(name: "Folder", position: 0)
        context.insert(folder)

        let bookmark = Bookmark(url: URL(string: "https://test.com")!, title: "Test")
        bookmark.folder = folder
        context.insert(bookmark)

        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        // Count opening and closing DL tags
        let openDL = content.components(separatedBy: "<DL>").count - 1
        let closeDL = content.components(separatedBy: "</DL>").count - 1

        #expect(openDL == closeDL)
    }

    // MARK: - Scale Tests

    @Test("Export many bookmarks")
    func exportManyBookmarks() async throws {
        let context = container.mainContext

        for i in 0 ..< 100 {
            let bookmark = Bookmark(
                url: URL(string: "https://site\(i).com/path/to/page")!,
                title: "Bookmark Number \(i)",
            )
            context.insert(bookmark)
        }
        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        // Verify some bookmarks are present
        #expect(content.contains("Bookmark Number 0"))
        #expect(content.contains("Bookmark Number 50"))
        #expect(content.contains("Bookmark Number 99"))
    }

    @Test("Export many folders")
    func exportManyFolders() async throws {
        let context = container.mainContext

        for i in 0 ..< 20 {
            let folder = BookmarkFolder(name: "Folder \(i)", position: i)
            context.insert(folder)

            let bookmark = Bookmark(
                url: URL(string: "https://folder\(i).com")!,
                title: "Bookmark in Folder \(i)",
            )
            bookmark.folder = folder
            context.insert(bookmark)
        }
        try context.save()

        let exporter = BookmarkExporter(modelContainer: container)
        let fileURL = try await exporter.exportToHTML().url
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let content = try String(contentsOf: fileURL, encoding: .utf8)

        // Verify some folders are present
        #expect(content.contains("Folder 0"))
        #expect(content.contains("Folder 10"))
        #expect(content.contains("Folder 19"))
    }
}
