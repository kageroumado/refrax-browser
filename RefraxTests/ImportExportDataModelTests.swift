import Foundation
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for import/export data models.
    @Tag static var importExportModels: Self
}

// MARK: - ImportedBookmark Tests

@Suite("ImportedBookmark", .tags(.importExportModels))
@MainActor
struct ImportedBookmarkTests {
    @Test("Creates with required fields")
    func createsWithRequiredFields() {
        let bookmark = ImportedBookmark(
            url: URL(string: "https://example.com")!,
            title: "Example",
        )

        #expect(bookmark.url.absoluteString == "https://example.com")
        #expect(bookmark.title == "Example")
        #expect(bookmark.dateAdded == nil)
        #expect(bookmark.folderPath.isEmpty)
    }

    @Test("Creates with all fields")
    func createsWithAllFields() {
        let date = Date()
        let bookmark = ImportedBookmark(
            url: URL(string: "https://example.com")!,
            title: "Example",
            dateAdded: date,
            folderPath: ["Root", "Child"],
        )

        #expect(bookmark.dateAdded == date)
        #expect(bookmark.folderPath == ["Root", "Child"])
    }

    @Test("Has unique ID")
    func hasUniqueId() {
        let b1 = ImportedBookmark(
            url: URL(string: "https://example.com")!,
            title: "Test",
        )
        let b2 = ImportedBookmark(
            url: URL(string: "https://example.com")!,
            title: "Test",
        )

        #expect(b1.id != b2.id)
    }

    @Test("Is Sendable")
    func isSendable() {
        let bookmark = ImportedBookmark(
            url: URL(string: "https://example.com")!,
            title: "Test",
        )

        let _: any Sendable = bookmark
        #expect(true)
    }
}

// MARK: - ImportedFolder Tests

@Suite("ImportedFolder", .tags(.importExportModels))
@MainActor
struct ImportedFolderTests {
    @Test("Creates with name only")
    func createsWithNameOnly() {
        let folder = ImportedFolder(name: "Test Folder")

        #expect(folder.name == "Test Folder")
        #expect(folder.path.isEmpty)
        #expect(folder.bookmarks.isEmpty)
        #expect(folder.subfolders.isEmpty)
    }

    @Test("Creates with all fields")
    func createsWithAllFields() {
        let bookmark = ImportedBookmark(
            url: URL(string: "https://example.com")!,
            title: "Test",
        )
        let subfolder = ImportedFolder(name: "Child")

        let folder = ImportedFolder(
            name: "Parent",
            path: ["Root"],
            bookmarks: [bookmark],
            subfolders: [subfolder],
        )

        #expect(folder.path == ["Root"])
        #expect(folder.bookmarks.count == 1)
        #expect(folder.subfolders.count == 1)
    }

    @Test("Total bookmark count includes nested")
    func totalBookmarkCountIncludesNested() {
        let folder = ImportedFolder(
            name: "Root",
            bookmarks: [
                ImportedBookmark(url: URL(string: "https://a.com")!, title: "A"),
                ImportedBookmark(url: URL(string: "https://b.com")!, title: "B"),
            ],
            subfolders: [
                ImportedFolder(
                    name: "Child",
                    bookmarks: [
                        ImportedBookmark(url: URL(string: "https://c.com")!, title: "C"),
                    ],
                ),
            ],
        )

        #expect(folder.totalBookmarkCount == 3)
    }

    @Test("Total folder count includes nested")
    func totalFolderCountIncludesNested() {
        let folder = ImportedFolder(
            name: "Root",
            subfolders: [
                ImportedFolder(
                    name: "Child1",
                    subfolders: [
                        ImportedFolder(name: "Grandchild"),
                    ],
                ),
                ImportedFolder(name: "Child2"),
            ],
        )

        #expect(folder.totalFolderCount == 4) // Root + Child1 + Child2 + Grandchild
    }

    @Test("Has unique ID")
    func hasUniqueId() {
        let f1 = ImportedFolder(name: "Test")
        let f2 = ImportedFolder(name: "Test")

        #expect(f1.id != f2.id)
    }

    @Test("Is Sendable")
    func isSendable() {
        let folder = ImportedFolder(name: "Test")

        let _: any Sendable = folder
        #expect(true)
    }
}

// MARK: - ImportResult Tests

@Suite("ImportResult", .tags(.importExportModels))
@MainActor
struct ImportResultTests {
    @Test("Creates with statistics")
    func createsWithStatistics() {
        let result = ImportResult(
            bookmarksImported: 10,
            foldersCreated: 3,
            duplicatesSkipped: 2,
            failedBookmarks: [],
        )

        #expect(result.bookmarksImported == 10)
        #expect(result.foldersCreated == 3)
        #expect(result.duplicatesSkipped == 2)
        #expect(result.failedBookmarks.isEmpty)
    }

    @Test("Is fully successful when no failures")
    func isFullySuccessfulWhenNoFailures() {
        let result = ImportResult(
            bookmarksImported: 10,
            foldersCreated: 3,
            duplicatesSkipped: 0,
            failedBookmarks: [],
        )

        #expect(result.isFullySuccessful)
    }

    @Test("Is not fully successful when has failures")
    func isNotFullySuccessfulWithFailures() {
        let failed = ImportResult.FailedBookmark(
            bookmark: ImportedBookmark(url: URL(string: "https://fail.com")!, title: "Failed"),
            reason: "Invalid URL",
        )

        let result = ImportResult(
            bookmarksImported: 9,
            foldersCreated: 3,
            duplicatesSkipped: 0,
            failedBookmarks: [failed],
        )

        #expect(!result.isFullySuccessful)
    }

    @Test("Failed bookmark has ID from bookmark")
    func failedBookmarkHasBookmarkId() {
        let bookmark = ImportedBookmark(url: URL(string: "https://fail.com")!, title: "Failed")
        let failed = ImportResult.FailedBookmark(bookmark: bookmark, reason: "Error")

        #expect(failed.id == bookmark.id)
    }
}

// MARK: - ImportedCredential Model Tests

@Suite("ImportedCredential Model", .tags(.importExportModels))
@MainActor
struct ImportedCredentialModelTests {
    @Test("Creates with required fields")
    func createsWithRequiredFields() {
        let credential = ImportedCredential(
            domain: "example.com",
            username: "user@test.com",
            password: "secret123",
        )

        #expect(credential.domain == "example.com")
        #expect(credential.username == "user@test.com")
        #expect(credential.password == "secret123")
        #expect(credential.dateCreated == nil)
        #expect(credential.dateLastUsed == nil)
        #expect(credential.notes == nil)
    }

    @Test("Creates with all fields")
    func createsWithAllFields() {
        let created = Date()
        let lastUsed = Date().addingTimeInterval(3_600)

        let credential = ImportedCredential(
            domain: "example.com",
            username: "user@test.com",
            password: "secret123",
            dateCreated: created,
            dateLastUsed: lastUsed,
            notes: "Test notes",
        )

        #expect(credential.dateCreated == created)
        #expect(credential.dateLastUsed == lastUsed)
        #expect(credential.notes == "Test notes")
    }

    @Test("Has unique ID")
    func hasUniqueId() {
        let c1 = ImportedCredential(
            domain: "example.com",
            username: "user",
            password: "pass",
        )
        let c2 = ImportedCredential(
            domain: "example.com",
            username: "user",
            password: "pass",
        )

        #expect(c1.id != c2.id)
    }

    @Test("Is Sendable")
    func isSendable() {
        let credential = ImportedCredential(
            domain: "example.com",
            username: "user",
            password: "pass",
        )

        let _: any Sendable = credential
        #expect(true)
    }
}

// MARK: - ImportedExtension Tests

@Suite("ImportedExtension", .tags(.importExportModels))
@MainActor
struct ImportedExtensionTests {
    @Test("Creates with required fields")
    func createsWithRequiredFields() {
        let ext = ImportedExtension(
            id: "ext123",
            name: "Test Extension",
            sourceBrowser: .chrome,
        )

        #expect(ext.id == "ext123")
        #expect(ext.name == "Test Extension")
        #expect(ext.version == nil)
        #expect(ext.description == nil)
        #expect(ext.homepageURL == nil)
        #expect(ext.isEnabled)
        #expect(ext.sourceBrowser == .chrome)
    }

    @Test("Creates with all fields")
    func createsWithAllFields() {
        let ext = ImportedExtension(
            id: "ext123",
            name: "Test Extension",
            version: "1.0.0",
            description: "A test extension",
            homepageURL: URL(string: "https://example.com"),
            isEnabled: false,
            sourceBrowser: .brave,
        )

        #expect(ext.version == "1.0.0")
        #expect(ext.description == "A test extension")
        #expect(ext.homepageURL?.absoluteString == "https://example.com")
        #expect(!ext.isEnabled)
    }

    @Test("Is Sendable")
    func isSendable() {
        let ext = ImportedExtension(
            id: "ext123",
            name: "Test",
            sourceBrowser: .chrome,
        )

        let _: any Sendable = ext
        #expect(true)
    }
}

// MARK: - ComprehensiveImportResult Tests

@Suite("ComprehensiveImportResult", .tags(.importExportModels))
@MainActor
struct ComprehensiveImportResultTests {
    @Test("Default values are zero")
    func defaultValuesAreZero() {
        let result = ComprehensiveImportResult()

        #expect(result.bookmarksImported == 0)
        #expect(result.foldersCreated == 0)
        #expect(result.bookmarkDuplicatesSkipped == 0)
        #expect(result.historyEntriesImported == 0)
        #expect(result.credentialsImported == 0)
        #expect(result.credentialConflictsResolved == 0)
        #expect(result.extensionsFound == 0)
        #expect(result.failedBookmarks.isEmpty)
        #expect(result.extensionsList.isEmpty)
    }

    @Test("Is fully successful when no failures")
    func isFullySuccessfulWhenNoFailures() {
        var result = ComprehensiveImportResult()
        result.bookmarksImported = 10
        result.historyEntriesImported = 100
        result.credentialsImported = 5

        #expect(result.isFullySuccessful)
    }

    @Test("Converts to bookmark result")
    func convertsToBookmarkResult() {
        var result = ComprehensiveImportResult()
        result.bookmarksImported = 10
        result.foldersCreated = 3
        result.bookmarkDuplicatesSkipped = 2

        let bookmarkResult = result.asBookmarkResult

        #expect(bookmarkResult.bookmarksImported == 10)
        #expect(bookmarkResult.foldersCreated == 3)
        #expect(bookmarkResult.duplicatesSkipped == 2)
    }
}

// MARK: - ImportError Tests

@Suite("ImportError", .tags(.importExportModels))
@MainActor
struct ImportErrorTests {
    @Test("File not found error has path")
    func fileNotFoundHasPath() {
        let error = ImportError.fileNotFound("/path/to/file")

        #expect(error.errorDescription?.contains("/path/to/file") == true)
    }

    @Test("Parse error has detail")
    func parseErrorHasDetail() {
        let error = ImportError.parseError("Invalid JSON")

        #expect(error.errorDescription?.contains("Invalid JSON") == true)
    }

    @Test("Database error has detail")
    func databaseErrorHasDetail() {
        let error = ImportError.databaseError("Connection failed")

        #expect(error.errorDescription?.contains("Connection failed") == true)
    }

    @Test("Permission denied error has path")
    func permissionDeniedHasPath() {
        let error = ImportError.permissionDenied("/protected/file")

        #expect(error.errorDescription?.contains("/protected/file") == true)
    }

    @Test("All error cases have descriptions")
    func allCasesHaveDescriptions() {
        let errors: [ImportError] = [
            .fileNotFound("path"),
            .parseError("detail"),
            .databaseError("detail"),
            .permissionDenied("path"),
            .unsupportedFormat,
            .noBookmarksFound,
            .noHistoryFound,
            .noCredentialsFound,
            .notImplemented("feature"),
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(!error.errorDescription!.isEmpty)
        }
    }

    @Test("Is Sendable")
    func isSendable() {
        let error: ImportError = .noBookmarksFound

        let _: any Sendable = error
        #expect(true)
    }
}

// MARK: - ImportedHistoryEntry Model Tests

@Suite("ImportedHistoryEntry Model", .tags(.importExportModels))
@MainActor
struct ImportedHistoryEntryModelTests {
    @Test("Default visit count is 1")
    func defaultVisitCountIsOne() {
        let entry = ImportedHistoryEntry(
            url: URL(string: "https://example.com")!,
            lastVisited: Date(),
        )

        #expect(entry.visitCount == 1)
    }

    @Test("First visited can be nil")
    func firstVisitedCanBeNil() {
        let entry = ImportedHistoryEntry(
            url: URL(string: "https://example.com")!,
            lastVisited: Date(),
        )

        #expect(entry.firstVisited == nil)
    }

    @Test("Title is optional")
    func titleIsOptional() {
        let entry = ImportedHistoryEntry(
            url: URL(string: "https://example.com")!,
            lastVisited: Date(),
        )

        #expect(entry.title == nil)
    }
}
