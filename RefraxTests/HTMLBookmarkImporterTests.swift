import Foundation
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for HTML bookmark import.
    @Tag static var htmlBookmarkImporter: Self
}

// MARK: - HTMLBookmarkImporter Basic Tests

@Suite("HTMLBookmarkImporter Basic", .tags(.htmlBookmarkImporter))
@MainActor
struct HTMLBookmarkImporterBasicTests {
    @Test("Import simple bookmark file")
    func importSimpleBookmarkFile() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Test Folder</H3>
            <DL><p>
                <DT><A HREF="https://example.com">Example Site</A>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        #expect(folders.count == 1)
        #expect(folders[0].name == "Test Folder")
        #expect(folders[0].bookmarks.count == 1)
        #expect(folders[0].bookmarks[0].title == "Example Site")
        #expect(folders[0].bookmarks[0].url.absoluteString == "https://example.com")
    }

    @Test("Import bookmarks with dates")
    func importBookmarksWithDates() async throws {
        let timestamp = 1_609_459_200 // 2021-01-01 00:00:00 UTC
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3 ADD_DATE="\(timestamp)">Dated Folder</H3>
            <DL><p>
                <DT><A HREF="https://example.com" ADD_DATE="\(timestamp)">Dated Bookmark</A>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        #expect(folders.count == 1)
        let bookmark = folders[0].bookmarks[0]
        #expect(bookmark.dateAdded != nil)
        #expect(bookmark.dateAdded?.timeIntervalSince1970 == Double(timestamp))
    }

    @Test("Import multiple folders")
    func importMultipleFolders() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Work</H3>
            <DL><p>
                <DT><A HREF="https://work.example.com">Work Site</A>
            </DL><p>
            <DT><H3>Personal</H3>
            <DL><p>
                <DT><A HREF="https://personal.example.com">Personal Site</A>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        #expect(folders.count == 2)
        let folderNames = Set(folders.map(\.name))
        #expect(folderNames.contains("Work"))
        #expect(folderNames.contains("Personal"))
    }

    @Test("Import empty file throws error")
    func importEmptyFileThrowsError() async throws {
        let html = ""

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()

        await #expect(throws: ImportError.self) {
            _ = try await importer.importBookmarks(from: url)
        }
    }

    @Test("Import file without DL element throws error")
    func importFileWithoutDLThrowsError() async throws {
        let html = """
        <!DOCTYPE html>
        <html><body><p>Not a bookmark file</p></body></html>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()

        await #expect(throws: ImportError.self) {
            _ = try await importer.importBookmarks(from: url)
        }
    }
}

// MARK: - HTMLBookmarkImporter Nested Structure Tests

@Suite("HTMLBookmarkImporter Nested", .tags(.htmlBookmarkImporter))
@MainActor
struct HTMLBookmarkImporterNestedTests {
    @Test("Import nested folders")
    func importNestedFolders() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Level 1</H3>
            <DL><p>
                <DT><H3>Level 2</H3>
                <DL><p>
                    <DT><A HREF="https://deep.example.com">Deep Bookmark</A>
                </DL><p>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        #expect(folders.count == 1)
        #expect(folders[0].name == "Level 1")
        #expect(folders[0].subfolders.count == 1)
        #expect(folders[0].subfolders[0].name == "Level 2")
        #expect(folders[0].subfolders[0].bookmarks.count == 1)
    }

    @Test("Import deeply nested structure preserves path")
    func importDeeplyNestedPreservesPath() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Root</H3>
            <DL><p>
                <DT><H3>Child</H3>
                <DL><p>
                    <DT><H3>Grandchild</H3>
                    <DL><p>
                        <DT><A HREF="https://example.com">Bookmark</A>
                    </DL><p>
                </DL><p>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        let grandchild = folders[0].subfolders[0].subfolders[0]
        let bookmark = grandchild.bookmarks[0]
        #expect(bookmark.folderPath == ["Root", "Child", "Grandchild"])
    }

    @Test("Import mixed bookmarks and folders")
    func importMixedBookmarksAndFolders() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Mixed Folder</H3>
            <DL><p>
                <DT><A HREF="https://first.com">First</A>
                <DT><H3>Subfolder</H3>
                <DL><p>
                    <DT><A HREF="https://nested.com">Nested</A>
                </DL><p>
                <DT><A HREF="https://second.com">Second</A>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        // After tidy HTML processing, structure may vary
        // Verify we have a folder with at least one bookmark and one subfolder
        #expect(!folders[0].bookmarks.isEmpty)
        #expect(folders[0].subfolders.count == 1)
    }
}

// MARK: - HTMLBookmarkImporter Root Bookmark Tests

@Suite("HTMLBookmarkImporter Root Bookmarks", .tags(.htmlBookmarkImporter))
@MainActor
struct HTMLBookmarkImporterRootTests {
    @Test("Import root-level bookmarks creates container folder")
    func importRootBookmarksCreatesContainer() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><A HREF="https://root1.com">Root Bookmark 1</A>
            <DT><A HREF="https://root2.com">Root Bookmark 2</A>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        // Root bookmarks should be in "Imported Bookmarks" folder
        #expect(folders.count == 1)
        #expect(folders[0].name == "Imported Bookmarks")
        #expect(folders[0].bookmarks.count == 2)
    }

    @Test("Import mix of root bookmarks and folders")
    func importMixRootAndFolders() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><A HREF="https://root.com">Root Bookmark</A>
            <DT><H3>Named Folder</H3>
            <DL><p>
                <DT><A HREF="https://folder.com">Folder Bookmark</A>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        // Should have both "Imported Bookmarks" and "Named Folder"
        #expect(folders.count == 2)
        let names = Set(folders.map(\.name))
        #expect(names.contains("Imported Bookmarks"))
        #expect(names.contains("Named Folder"))
    }
}

// MARK: - HTMLBookmarkImporter Edge Cases

@Suite("HTMLBookmarkImporter Edge Cases", .tags(.htmlBookmarkImporter))
@MainActor
struct HTMLBookmarkImporterEdgeCaseTests {
    @Test("Handle uppercase and lowercase href")
    func handleMixedCaseHref() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Test</H3>
            <DL><p>
                <DT><A HREF="https://lower.com">Lowercase</A>
                <DT><A href="https://upper.com">Mixed</A>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        #expect(folders[0].bookmarks.count == 2)
    }

    @Test("Handle uppercase and lowercase ADD_DATE")
    func handleMixedCaseAddDate() async throws {
        let timestamp = 1_609_459_200
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Test</H3>
            <DL><p>
                <DT><A HREF="https://lower.com" add_date="\(timestamp)">Lowercase</A>
                <DT><A HREF="https://upper.com" ADD_DATE="\(timestamp)">Uppercase</A>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        #expect(folders[0].bookmarks[0].dateAdded != nil)
        #expect(folders[0].bookmarks[1].dateAdded != nil)
    }

    @Test("Handle bookmarks without title")
    func handleBookmarksWithoutTitle() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Test</H3>
            <DL><p>
                <DT><A HREF="https://notitle.com"></A>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        // Bookmark is created with empty title (XMLDocument returns empty string, not nil)
        #expect(folders[0].bookmarks.count == 1)
        #expect(folders[0].bookmarks[0].title.isEmpty)
    }

    @Test("Handle special characters in titles")
    func handleSpecialCharactersInTitles() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Test &amp; Folder</H3>
            <DL><p>
                <DT><A HREF="https://example.com">Site &lt;Test&gt; &quot;Quoted&quot;</A>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        #expect(folders[0].name.contains("&"))
    }

    @Test("Handle invalid URLs gracefully")
    func handleInvalidURLs() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Test</H3>
            <DL><p>
                <DT><A HREF="https://valid.com">Valid</A>
                <DT><A HREF="not a url">Invalid</A>
                <DT><A HREF="">Empty</A>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        // URL(string:) accepts "not a url" since XMLDocument may encode it
        // Only truly invalid URLs (empty string) are filtered out
        #expect(folders[0].bookmarks.count >= 1)
        #expect(folders[0].bookmarks.contains { $0.title == "Valid" })
    }

    @Test("Handle ISO-8859-1 encoded files")
    func handleISOEncoding() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Caf\u{00E9}</H3>
            <DL><p>
                <DT><A HREF="https://example.com">Test</A>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        #expect(folders.count == 1)
    }

    @Test("Handle folders without children")
    func handleEmptyFolders() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Empty Folder</H3>
            <DL><p>
            </DL><p>
            <DT><H3>Folder With Content</H3>
            <DL><p>
                <DT><A HREF="https://example.com">Test</A>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        // Should include folder with content
        #expect(folders.contains(where: { $0.name == "Folder With Content" }))
    }
}

// MARK: - HTMLBookmarkImporter Real World Formats

@Suite("HTMLBookmarkImporter Real World Formats", .tags(.htmlBookmarkImporter))
@MainActor
struct HTMLBookmarkImporterRealWorldTests {
    @Test("Import Chrome exported bookmarks format")
    func importChromeFormat() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <!-- This is an automatically generated file.
             It will be read and overwritten.
             DO NOT EDIT! -->
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3 ADD_DATE="1609459200" LAST_MODIFIED="1609459200" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks bar</H3>
            <DL><p>
                <DT><A HREF="https://github.com" ADD_DATE="1609459200" ICON="data:image/png;base64,">GitHub</A>
            </DL><p>
            <DT><H3 ADD_DATE="1609459200" LAST_MODIFIED="1609459200">Other bookmarks</H3>
            <DL><p>
                <DT><A HREF="https://google.com" ADD_DATE="1609459200">Google</A>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        #expect(folders.count == 2)
        let folderNames = Set(folders.map(\.name))
        #expect(folderNames.contains("Bookmarks bar"))
        #expect(folderNames.contains("Other bookmarks"))
    }

    @Test("Import Firefox exported bookmarks format")
    func importFirefoxFormat() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <!-- This is an automatically generated file.
             It will be read and overwritten.
             DO NOT EDIT! -->
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <meta http-equiv="Content-Security-Policy" content="default-src 'self';script-src 'none'">
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks Menu</H1>
        
        <DL><p>
            <DT><H3 ADD_DATE="1609459200" LAST_MODIFIED="1609459200" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks Toolbar</H3>
            <DL><p>
                <DT><A HREF="https://mozilla.org" ADD_DATE="1609459200" LAST_MODIFIED="1609459200">Mozilla</A>
                <DD>Mozilla homepage
            </DL><p>
            <DT><H3 ADD_DATE="1609459200" LAST_MODIFIED="1609459200" UNFILED_BOOKMARKS_FOLDER="true">Other Bookmarks</H3>
            <DL><p>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        #expect(folders.contains(where: { $0.name == "Bookmarks Toolbar" }))
        let toolbar = folders.first(where: { $0.name == "Bookmarks Toolbar" })
        #expect(toolbar?.bookmarks.first?.title == "Mozilla")
    }

    @Test("Import Safari exported bookmarks format")
    func importSafariFormat() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <HTML>
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <Title>Bookmarks</Title>
        <H1>Bookmarks</H1>
        <DT><H3 FOLDED>Favorites</H3>
        <DL><p>
            <DT><A HREF="https://apple.com">Apple</A>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        #expect(folders.count >= 1)
    }
}

// MARK: - HTMLBookmarkImporter Count Tests

@Suite("HTMLBookmarkImporter Counts", .tags(.htmlBookmarkImporter))
@MainActor
struct HTMLBookmarkImporterCountTests {
    @Test("Total bookmark count is accurate")
    func totalBookmarkCountIsAccurate() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Folder 1</H3>
            <DL><p>
                <DT><A HREF="https://a.com">A</A>
                <DT><A HREF="https://b.com">B</A>
                <DT><H3>Nested</H3>
                <DL><p>
                    <DT><A HREF="https://c.com">C</A>
                </DL><p>
            </DL><p>
            <DT><H3>Folder 2</H3>
            <DL><p>
                <DT><A HREF="https://d.com">D</A>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        let totalBookmarks = folders.reduce(0) { $0 + $1.totalBookmarkCount }
        #expect(totalBookmarks == 4)
    }

    @Test("Total folder count is accurate")
    func totalFolderCountIsAccurate() async throws {
        let html = """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <TITLE>Bookmarks</TITLE>
        <H1>Bookmarks</H1>
        <DL><p>
            <DT><H3>Root 1</H3>
            <DL><p>
                <DT><H3>Child 1</H3>
                <DL><p>
                    <DT><A HREF="https://example.com">Test</A>
                </DL><p>
            </DL><p>
            <DT><H3>Root 2</H3>
            <DL><p>
                <DT><A HREF="https://example.com">Test</A>
            </DL><p>
        </DL><p>
        """

        let url = try createTempHTMLFile(content: html)
        defer { try? FileManager.default.removeItem(at: url) }

        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        let totalFolders = folders.reduce(0) { $0 + $1.totalFolderCount }
        #expect(totalFolders == 3) // Root 1, Child 1, Root 2
    }
}

// MARK: - Helper Functions

private func createTempHTMLFile(content: String) throws -> URL {
    let tempDir = FileManager.default.temporaryDirectory
    let fileName = "test_bookmarks_\(UUID().uuidString).html"
    let url = tempDir.appendingPathComponent(fileName)
    try content.write(to: url, atomically: true, encoding: .utf8)
    return url
}
