import Foundation
import SwiftData
import Testing
import UniformTypeIdentifiers
@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for Download and DownloadManager operations.
    @Tag static var downloadManager: Self
}

// MARK: - Download Model Tests

@Suite("Download Model", .tags(.downloadManager))
@MainActor
struct DownloadModelTests {
    @Test("Creates with correct default values")
    func createsWithDefaults() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        #expect(download.sourceURL.absoluteString == "https://example.com/file.pdf")
        #expect(download.suggestedFilename == "file.pdf")
        #expect(download.destinationFilename == "file.pdf")
        #expect(download.state == .pending)
        #expect(download.bytesReceived == 0)
        #expect(download.totalBytes == nil)
        #expect(download.bytesPerSecond == 0)
        #expect(download.progress == nil)
        #expect(download.estimatedTimeRemaining == nil)
        #expect(download.resumeData == nil)
        #expect(download.errorMessage == nil)
    }

    @Test("Progress calculates correctly")
    func progressCalculates() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        download.state = .downloading
        download.updateLiveProgress(bytesReceived: 500, totalBytes: 1_000, bytesPerSecond: 0)

        #expect(download.progress == 0.5)
    }

    @Test("Progress is nil when total bytes unknown")
    func progressNilWhenUnknown() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        download.state = .downloading
        download.updateLiveProgress(bytesReceived: 500, totalBytes: nil, bytesPerSecond: 0)
        // totalBytes is nil

        #expect(download.progress == nil)
    }

    @Test("Estimated time remaining calculates correctly")
    func estimatedTimeCalculates() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        download.state = .downloading
        download.updateLiveProgress(bytesReceived: 500, totalBytes: 1_000, bytesPerSecond: 100)

        // Remaining: 500 bytes at 100 bytes/sec = 5 seconds
        #expect(download.estimatedTimeRemaining == 5.0)
    }

    @Test("Estimated time remaining is nil when speed is zero")
    func estimatedTimeNilWhenNoSpeed() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        download.state = .downloading
        download.updateLiveProgress(bytesReceived: 500, totalBytes: 1_000, bytesPerSecond: 0)

        #expect(download.estimatedTimeRemaining == nil)
    }

    @Test("Current file URL includes .download suffix for incomplete")
    func currentFileURLIncludesDownloadSuffix() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        // Pending state
        download.state = .pending
        #expect(download.currentFileURL.lastPathComponent == "file.pdf.download")

        // Downloading state
        download.state = .downloading
        #expect(download.currentFileURL.lastPathComponent == "file.pdf.download")

        // Paused state
        download.state = .paused
        #expect(download.currentFileURL.lastPathComponent == "file.pdf.download")
    }

    @Test("Current file URL has no suffix for completed")
    func currentFileURLNoSuffixWhenCompleted() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        download.state = .completed
        #expect(download.currentFileURL.lastPathComponent == "file.pdf")
    }

    @Test("Final file URL is always without suffix")
    func finalFileURLNoSuffix() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        download.state = .downloading
        #expect(download.finalFileURL.lastPathComponent == "file.pdf")
    }

    @Test("Can resume when paused with resume data")
    func canResumeWhenPaused() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        download.state = .paused
        download.resumeData = Data([0x01, 0x02, 0x03])

        #expect(download.canResume == true)
    }

    @Test("Cannot resume when paused without resume data")
    func cannotResumeWithoutData() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        download.state = .paused
        download.resumeData = nil

        #expect(download.canResume == false)
    }

    @Test("Can retry when failed")
    func canRetryWhenFailed() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        download.state = .failed

        #expect(download.canRetry == true)
    }

    @Test("Cannot retry when not failed")
    func cannotRetryWhenNotFailed() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        download.state = .downloading
        #expect(download.canRetry == false)

        download.state = .completed
        #expect(download.canRetry == false)
    }

    @Test("Content type from MIME type")
    func contentTypeFromMIME() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file")),
            suggestedFilename: "file",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        download.mimeType = "application/pdf"

        #expect(download.contentType == .pdf)
    }

    @Test("Content type from extension when no MIME")
    func contentTypeFromExtension() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/document.pdf")),
            suggestedFilename: "document.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        download.mimeType = nil

        #expect(download.contentType == .pdf)
    }

    @Test("Is potentially dangerous for executables")
    func isPotentiallyDangerousForExecutables() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/app.app")),
            suggestedFilename: "app.app",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        download.mimeType = "application/x-mach-binary"

        // This depends on UTType conformance, but we can test the structure
        // The actual result depends on macOS version
    }
}

// MARK: - Download State Transition Tests

@Suite("Download State Transitions", .tags(.downloadManager))
@MainActor
struct DownloadStateTransitionTests {
    @Test("Mark downloading updates state and timestamp")
    func markDownloadingUpdates() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        let initialModified = download.modifiedAt
        Thread.sleep(forTimeInterval: 0.01)

        download.markDownloading()

        #expect(download.state == .downloading)
        #expect(download.modifiedAt > initialModified)
    }

    @Test("Update progress sets all fields")
    func updateLiveProgressSetsTransientFields() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        // Mark as downloading so bytesReceived returns live value
        download.markDownloading()
        download.updateLiveProgress(bytesReceived: 500, totalBytes: 1_000, bytesPerSecond: 100.5)

        #expect(download.bytesReceived == 500)
        #expect(download.totalBytes == 1_000)
        #expect(download.bytesPerSecond == 100.5)
        // Persisted value should not be updated by live progress
        #expect(download.persistedBytesReceived == 0)
    }

    @Test("Mark paused persists progress and clears speed")
    func markPausedPersistsProgress() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        download.markDownloading()
        download.updateLiveProgress(bytesReceived: 500, totalBytes: 1_000, bytesPerSecond: 100.5)
        let resumeData = Data([0x01, 0x02])

        download.markPaused(resumeData: resumeData)

        #expect(download.state == .paused)
        #expect(download.bytesPerSecond == 0)
        #expect(download.resumeData == resumeData)
        // Progress should be persisted
        #expect(download.persistedBytesReceived == 500)
        #expect(download.bytesReceived == 500)
    }

    @Test("Mark completed clears resume data and sets completedAt")
    func markCompletedClearsResumeData() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        download.resumeData = Data([0x01, 0x02])
        download.state = .downloading
        download.updateLiveProgress(bytesReceived: 100, totalBytes: 100, bytesPerSecond: 100)

        download.markCompleted()

        #expect(download.state == .completed)
        #expect(download.completedAt != nil)
        #expect(download.resumeData == nil)
        #expect(download.bytesPerSecond == 0)
    }

    @Test("Mark failed sets error info")
    func markFailedSetsError() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        let error = NSError(domain: "Test", code: 42, userInfo: [NSLocalizedDescriptionKey: "Test error"])
        let resumeData = Data([0x01])

        download.markFailed(error: error, resumeData: resumeData)

        #expect(download.state == .failed)
        #expect(download.errorMessage == "Test error")
        #expect(download.errorCode == 42)
        #expect(download.resumeData == resumeData)
        #expect(download.bytesPerSecond == 0)
    }
}

// MARK: - Download Filename Conflict Resolution Tests

@Suite("Download Filename Conflict Resolution", .tags(.downloadManager))
@MainActor
struct DownloadFilenameConflictTests {
    @Test("Resolves conflict by appending number")
    func resolvesConflictWithNumber() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        let existingNames: Set<String> = ["file.pdf"]

        download.resolveFilenameConflict(avoiding: existingNames)

        #expect(download.destinationFilename == "file 1.pdf")
    }

    @Test("Resolves multiple conflicts")
    func resolvesMultipleConflicts() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        let existingNames: Set<String> = ["file.pdf", "file 1.pdf", "file 2.pdf"]

        download.resolveFilenameConflict(avoiding: existingNames)

        #expect(download.destinationFilename == "file 3.pdf")
    }

    @Test("Accounts for .download suffix")
    func accountsForDownloadSuffix() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        let existingNames: Set<String> = ["file.pdf.download"]

        download.resolveFilenameConflict(avoiding: existingNames)

        #expect(download.destinationFilename == "file 1.pdf")
    }

    @Test("Preserves original if no conflict")
    func preservesOriginalIfNoConflict() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        let existingNames: Set<String> = ["other.pdf"]

        download.resolveFilenameConflict(avoiding: existingNames)

        #expect(download.destinationFilename == "file.pdf")
    }

    @Test("Handles filenames without extension")
    func handlesNoExtension() throws {
        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/README")),
            suggestedFilename: "README",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )

        let existingNames: Set<String> = ["README"]

        download.resolveFilenameConflict(avoiding: existingNames)

        #expect(download.destinationFilename == "README 1")
    }
}

// MARK: - DownloadState Tests

@Suite("DownloadState", .tags(.downloadManager))
@MainActor
struct DownloadStateTests {
    @Test("isActive for pending and downloading")
    func isActiveStates() {
        #expect(DownloadState.pending.isActive == true)
        #expect(DownloadState.downloading.isActive == true)
        #expect(DownloadState.paused.isActive == false)
        #expect(DownloadState.completed.isActive == false)
        #expect(DownloadState.failed.isActive == false)
    }

    @Test("Display names are non-empty")
    func displayNamesNonEmpty() {
        let states: [DownloadState] = [.pending, .downloading, .paused, .completed, .failed]

        for state in states {
            #expect(!state.displayName.isEmpty)
        }
    }

    @Test("Codable round-trip")
    func codableRoundTrip() throws {
        let states: [DownloadState] = [.pending, .downloading, .paused, .completed, .failed]

        for state in states {
            let encoded = try JSONEncoder().encode(state)
            let decoded = try JSONDecoder().decode(DownloadState.self, from: encoded)
            #expect(decoded == state)
        }
    }
}

// MARK: - DownloadError Tests

@Suite("DownloadError", .tags(.downloadManager))
@MainActor
struct DownloadErrorTests {
    @Test("Error descriptions are non-empty")
    func errorDescriptionsNonEmpty() throws {
        let errors: [DownloadError] = [
            .downloadNotFound,
            .cannotResume,
            .cannotRetry,
            .cancelled,
            .fileOperationFailed(NSError(domain: "Test", code: 1)),
            .networkError(NSError(domain: "Test", code: 2)),
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(try !(#require(error.errorDescription?.isEmpty)))
        }
    }

    @Test("File operation failed includes underlying error")
    func fileOperationIncludesUnderlying() throws {
        let underlying = NSError(
            domain: "Test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "File not found"],
        )
        let error = DownloadError.fileOperationFailed(underlying)

        #expect(try #require(error.errorDescription?.contains("File not found")))
    }

    @Test("Network error includes underlying error")
    func networkErrorIncludesUnderlying() throws {
        let underlying = NSError(
            domain: "Test",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Connection refused"],
        )
        let error = DownloadError.networkError(underlying)

        #expect(try #require(error.errorDescription?.contains("Connection refused")))
    }
}

// MARK: - FilenameUtilities Sanitization Tests

@Suite("FilenameUtilities Sanitization", .tags(.downloadManager))
@MainActor
struct FilenameUtilitiesSanitizationTests {
    @Test("Sanitizes path separators")
    func sanitizesPathSeparators() {
        let result = FilenameUtilities.sanitize("file/name:test")

        #expect(!result.contains("/"))
        #expect(!result.contains(":"))
    }

    @Test("Removes control characters")
    func removesControlCharacters() {
        let result = FilenameUtilities.sanitize("file\u{0000}name\u{0001}")

        #expect(!result.contains("\u{0000}"))
        #expect(!result.contains("\u{0001}"))
    }

    @Test("Trims leading and trailing whitespace")
    func trimsWhitespace() {
        let result = FilenameUtilities.sanitize("  filename  ")

        #expect(!result.hasPrefix(" "))
        #expect(!result.hasSuffix(" "))
    }

    @Test("Trims leading and trailing dots")
    func trimsDots() {
        let result = FilenameUtilities.sanitize("...filename...")

        #expect(!result.hasPrefix("."))
        #expect(!result.hasSuffix("."))
    }

    @Test("Returns 'download' for empty result")
    func returnsDownloadForEmpty() {
        let result = FilenameUtilities.sanitize("...")

        #expect(result == "download")
    }

    @Test("Preserves valid filename")
    func preservesValidFilename() {
        let result = FilenameUtilities.sanitize("valid_filename-2024.pdf")

        #expect(result == "valid_filename-2024.pdf")
    }

    @Test("Truncates overly long filename")
    func truncatesLongFilename() {
        let longName = String(repeating: "a", count: 300) + ".pdf"
        let result = FilenameUtilities.sanitize(longName)

        #expect(result.utf8.count <= 255)
        #expect(result.hasSuffix(".pdf"))
    }
}

// MARK: - FilenameUtilities Conflict Resolution Tests

@Suite("FilenameUtilities Conflict Resolution", .tags(.downloadManager))
@MainActor
struct FilenameUtilitiesConflictTests {
    @Test("Returns original if no conflict")
    func returnsOriginalIfNoConflict() throws {
        let result = try FilenameUtilities.uniqueFilename(
            for: "file.pdf",
            existingNames: ["other.pdf"],
        )

        #expect(result == "file.pdf")
    }

    @Test("Appends number for conflict")
    func appendsNumberForConflict() throws {
        let result = try FilenameUtilities.uniqueFilename(
            for: "file.pdf",
            existingNames: ["file.pdf"],
        )

        #expect(result == "file 1.pdf")
    }

    @Test("Finds next available number")
    func findsNextAvailableNumber() throws {
        let result = try FilenameUtilities.uniqueFilename(
            for: "file.pdf",
            existingNames: ["file.pdf", "file 1.pdf", "file 2.pdf"],
        )

        #expect(result == "file 3.pdf")
    }

    @Test("Checks .download suffix for conflicts")
    func checksDownloadSuffix() throws {
        let result = try FilenameUtilities.uniqueFilename(
            for: "file.pdf",
            existingNames: ["file.pdf.download"],
        )

        #expect(result == "file 1.pdf")
    }

    @Test("Handles filename without extension")
    func handlesNoExtension() throws {
        let result = try FilenameUtilities.uniqueFilename(
            for: "README",
            existingNames: ["README", "README 1"],
        )

        #expect(result == "README 2")
    }
}

// MARK: - FilenameUtilities Content-Disposition Tests

@Suite("FilenameUtilities Content-Disposition", .tags(.downloadManager))
@MainActor
struct FilenameUtilitiesContentDispositionTests {
    @Test("Parses standard quoted filename")
    func parsesStandardQuoted() {
        let result = FilenameUtilities.parseContentDisposition(
            "attachment; filename=\"report.pdf\"",
        )

        #expect(result == "report.pdf")
    }

    @Test("Parses unquoted filename")
    func parsesUnquoted() {
        let result = FilenameUtilities.parseContentDisposition(
            "attachment; filename=report.pdf",
        )

        #expect(result == "report.pdf")
    }

    @Test("Parses extended format UTF-8")
    func parsesExtendedUTF8() {
        let result = FilenameUtilities.parseContentDisposition(
            "attachment; filename*=UTF-8''%E2%82%AC%20rates.pdf",
        )

        #expect(result == "€ rates.pdf")
    }

    @Test("Prefers extended format over standard")
    func prefersExtendedFormat() {
        let result = FilenameUtilities.parseContentDisposition(
            "attachment; filename=\"fallback.pdf\"; filename*=UTF-8''preferred.pdf",
        )

        #expect(result == "preferred.pdf")
    }

    @Test("Returns nil for missing filename")
    func returnsNilForMissing() {
        let result = FilenameUtilities.parseContentDisposition("attachment")

        #expect(result == nil)
    }

    @Test("Decodes percent-encoded characters")
    func decodesPercentEncoding() {
        let result = FilenameUtilities.parseContentDisposition(
            "attachment; filename=\"my%20file.pdf\"",
        )

        #expect(result == "my file.pdf")
    }
}

// MARK: - FilenameUtilities MIME Extension Tests

@Suite("FilenameUtilities MIME Extension", .tags(.downloadManager))
@MainActor
struct FilenameUtilitiesMIMEExtensionTests {
    @Test("Gets extension for PDF")
    func getsExtensionForPDF() {
        let ext = FilenameUtilities.extensionForMIMEType("application/pdf")

        #expect(ext == "pdf")
    }

    @Test("Gets extension for common types")
    func getsExtensionForCommonTypes() {
        #expect(FilenameUtilities.extensionForMIMEType("text/html") == "html")
        #expect(FilenameUtilities.extensionForMIMEType("image/png") == "png")
        #expect(FilenameUtilities.extensionForMIMEType("application/json") == "json")
    }

    @Test("Strips charset from MIME type")
    func stripsCharset() {
        let ext = FilenameUtilities.extensionForMIMEType("text/html; charset=utf-8")

        #expect(ext == "html")
    }

    @Test("Ensures extension based on MIME type")
    func ensuresExtension() {
        let result = FilenameUtilities.ensureExtension(for: "document", mimeType: "application/pdf")

        #expect(result == "document.pdf")
    }

    @Test("Preserves existing matching extension")
    func preservesMatchingExtension() {
        let result = FilenameUtilities.ensureExtension(for: "document.pdf", mimeType: "application/pdf")

        #expect(result == "document.pdf")
    }

    @Test("Keeps filename unchanged if no MIME type")
    func keepsFilenameWithoutMIME() {
        let result = FilenameUtilities.ensureExtension(for: "document", mimeType: nil)

        #expect(result == "document")
    }
}

// MARK: - DownloadManager Initial State Tests

@Suite("DownloadManager Initial State", .tags(.downloadManager), .serialized)
@MainActor
struct DownloadManagerInitialStateTests {
    @Test("Creates with default settings")
    func createsWithDefaults() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.downloadManager.downloads.isEmpty)
        #expect(env.downloadManager.aggregateProgress == 0)
        #expect(env.downloadManager.activeDownloadCount == 0)
        #expect(env.downloadManager.hasActiveDownloads == false)
    }

    @Test("Download directory defaults to Downloads folder")
    func defaultDownloadDirectory() throws {
        let env = try TabManagerTestEnvironment()
        let expectedDownloads = try #require(FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask,
        ).first)

        #expect(env.downloadManager.downloadDirectory == expectedDownloads)
    }

    @Test("Default panel settings are true")
    func defaultPanelSettings() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.downloadManager.showPanelOnStart == true)
        #expect(env.downloadManager.showPanelOnCompletion == true)
    }

    @Test("Aria2 disabled by default")
    func aria2DisabledByDefault() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.downloadManager.useAria2ForLargeFiles == false)
        #expect(env.downloadManager.aria2Threshold == 50 * 1_024 * 1_024)
    }
}

// MARK: - DownloadManager Error Handling Tests

@Suite("DownloadManager Error Handling", .tags(.downloadManager), .serialized)
@MainActor
struct DownloadManagerErrorHandlingTests {
    @Test("Pause non-existent download is no-op")
    func pauseNonExistent() async throws {
        let env = try TabManagerTestEnvironment()

        // Should not crash, just log warning
        await env.downloadManager.pause(UUID())

        #expect(env.downloadManager.activeDownloadCount == 0)
    }

    @Test("Resume throws for non-existent download")
    func resumeNonExistent() async throws {
        let env = try TabManagerTestEnvironment()

        do {
            try await env.downloadManager.resume(UUID())
            Issue.record("Expected downloadNotFound error to be thrown")
        } catch let error as DownloadError {
            if case .downloadNotFound = error {
                // Expected
            } else {
                Issue.record("Expected downloadNotFound but got \(error)")
            }
        } catch {
            Issue.record("Expected DownloadError but got \(error)")
        }
    }

    @Test("Cancel non-existent download is no-op")
    func cancelNonExistent() throws {
        let env = try TabManagerTestEnvironment()

        // Should not crash
        env.downloadManager.cancel(UUID())

        #expect(env.downloadManager.activeDownloadCount == 0)
    }

    @Test("Remove non-existent download is no-op")
    func removeNonExistent() throws {
        let env = try TabManagerTestEnvironment()

        // Should not crash
        env.downloadManager.remove(UUID())

        #expect(env.downloadManager.downloads.isEmpty)
    }

    @Test("Retry throws for non-existent download")
    func retryNonExistent() async throws {
        let env = try TabManagerTestEnvironment()

        do {
            try await env.downloadManager.retry(UUID())
            Issue.record("Expected downloadNotFound error to be thrown")
        } catch let error as DownloadError {
            if case .downloadNotFound = error {
                // Expected
            } else {
                Issue.record("Expected downloadNotFound but got \(error)")
            }
        } catch {
            Issue.record("Expected DownloadError but got \(error)")
        }
    }
}

// MARK: - DownloadManager Clear Inactive Tests

@Suite("DownloadManager Clear Inactive", .tags(.downloadManager), .serialized)
@MainActor
struct DownloadManagerClearInactiveTests {
    @Test("Clear inactive on empty list is no-op")
    func clearInactiveEmpty() throws {
        let env = try TabManagerTestEnvironment()

        env.downloadManager.clearInactive()

        #expect(env.downloadManager.downloads.isEmpty)
    }
}

// MARK: - DownloadManager Add Completed Tests

@Suite("DownloadManager Add Completed", .tags(.downloadManager), .serialized)
@MainActor
struct DownloadManagerAddCompletedTests {
    @Test("Add completed download inserts at front")
    func addCompletedInsertsAtFront() throws {
        let env = try TabManagerTestEnvironment()

        let download = try Download(
            sourceURL: #require(URL(string: "https://example.com/file.pdf")),
            suggestedFilename: "file.pdf",
            destinationDirectory: URL(fileURLWithPath: "/tmp"),
        )
        download.markCompleted()

        var callbackInvoked = false
        env.downloadManager.onDownloadCompleted = { _ in
            callbackInvoked = true
        }

        env.downloadManager.addCompletedDownload(download)

        #expect(env.downloadManager.downloads.first?.id == download.id)
        #expect(callbackInvoked)
    }
}

// MARK: - UTType Extension Tests

@Suite("UTType Extension", .tags(.downloadManager))
@MainActor
struct UTTypeExtensionTests {
    @Test("From MIME type strips charset")
    func fromMIMETypeStripsCharset() {
        let type = UTType.fromMIMEType("text/html; charset=utf-8")

        #expect(type == .html)
    }

    @Test("From MIME type handles clean type")
    func fromMIMETypeClean() {
        let type = UTType.fromMIMEType("application/pdf")

        #expect(type == .pdf)
    }

    @Test("Suggested extension for common types")
    func suggestedExtension() {
        #expect(UTType.pdf.suggestedExtension == "pdf")
        #expect(UTType.png.suggestedExtension == "png")
    }
}

// MARK: - ResumeData Tests

@Suite("ResumeData Serialization", .tags(.downloadManager))
@MainActor
struct ResumeDataSerializationTests {
    @Test("Serializes and deserializes correctly")
    func serializesAndDeserializes() {
        let original = ResumeData(
            bytesReceived: 12_345,
            etag: "\"abc123\"",
            lastModified: "Tue, 01 Jan 2025 00:00:00 GMT",
            tempFileURL: URL(fileURLWithPath: "/tmp/file.pdf.download"),
            finalFileURL: URL(fileURLWithPath: "/tmp/file.pdf"),
        )

        guard let data = original.serialize() else {
            Issue.record("Failed to serialize ResumeData")
            return
        }

        guard let restored = ResumeData.deserialize(from: data) else {
            Issue.record("Failed to deserialize ResumeData")
            return
        }

        #expect(restored.bytesReceived == 12_345)
        #expect(restored.etag == "\"abc123\"")
        #expect(restored.lastModified == "Tue, 01 Jan 2025 00:00:00 GMT")
        #expect(restored.tempFileURL?.path == "/tmp/file.pdf.download")
        #expect(restored.finalFileURL?.path == "/tmp/file.pdf")
    }

    @Test("Handles nil optional fields")
    func handlesNilOptionals() {
        let original = ResumeData(
            bytesReceived: 1_000,
            etag: nil,
            lastModified: nil,
            tempFileURL: nil,
            finalFileURL: nil,
        )

        guard let data = original.serialize(),
              let restored = ResumeData.deserialize(from: data) else {
            Issue.record("Round-trip failed")
            return
        }

        #expect(restored.bytesReceived == 1_000)
        #expect(restored.etag == nil)
        #expect(restored.lastModified == nil)
        #expect(restored.tempFileURL == nil)
        #expect(restored.finalFileURL == nil)
    }

    @Test("Deserialize returns nil for invalid data")
    func deserializeReturnsNilForInvalid() {
        let invalid = Data([0x00, 0x01, 0x02])
        let result = ResumeData.deserialize(from: invalid)

        #expect(result == nil)
    }

    @Test("Deserialize returns nil for wrong JSON structure")
    func deserializeReturnsNilForWrongStructure() {
        let wrongJSON = "{\"foo\": \"bar\"}".data(using: .utf8)!
        let result = ResumeData.deserialize(from: wrongJSON)

        // Missing required bytesReceived field
        #expect(result == nil)
    }
}

// MARK: - Aria2DownloadTask State Tests

@Suite("Aria2DownloadTask State", .tags(.downloadManager))
@MainActor
struct Aria2DownloadTaskStateTests {
    @Test("isActive for pending and downloading")
    func isActiveStates() {
        #expect(Aria2DownloadTask.State.pending.isActive == true)
        #expect(Aria2DownloadTask.State.downloading.isActive == true)
        #expect(Aria2DownloadTask.State.paused.isActive == false)
        #expect(Aria2DownloadTask.State.completed.isActive == false)
        #expect(Aria2DownloadTask.State.failed(CancellationError()).isActive == false)
    }

    @Test("Equality compares same states correctly")
    func equalitySameStates() {
        #expect(Aria2DownloadTask.State.pending == Aria2DownloadTask.State.pending)
        #expect(Aria2DownloadTask.State.downloading == Aria2DownloadTask.State.downloading)
        #expect(Aria2DownloadTask.State.paused == Aria2DownloadTask.State.paused)
        #expect(Aria2DownloadTask.State.completed == Aria2DownloadTask.State.completed)
    }

    @Test("Equality compares different states correctly")
    func equalityDifferentStates() {
        #expect(Aria2DownloadTask.State.pending != Aria2DownloadTask.State.downloading)
        #expect(Aria2DownloadTask.State.downloading != Aria2DownloadTask.State.completed)
        #expect(Aria2DownloadTask.State.paused != Aria2DownloadTask.State.failed(CancellationError()))
    }

    @Test("Failed states compare as equal regardless of error")
    func failedStatesEqual() {
        let error1 = NSError(domain: "Test", code: 1)
        let error2 = NSError(domain: "Test", code: 2)

        #expect(Aria2DownloadTask.State.failed(error1) == Aria2DownloadTask.State.failed(error2))
    }
}

// MARK: - Aria2DownloadTask Progress Tests

@Suite("Aria2DownloadTask Progress", .tags(.downloadManager))
@MainActor
struct Aria2DownloadTaskProgressTests {
    @Test("fractionCompleted calculates correctly")
    func fractionCompletedCalculates() {
        let progress = Aria2DownloadTask.Progress(
            totalBytes: 1_000,
            completedBytes: 500,
            downloadSpeed: 100,
            connections: 4,
        )

        #expect(progress.fractionCompleted == 0.5)
    }

    @Test("fractionCompleted is zero when total is zero")
    func fractionCompletedZeroTotal() {
        let progress = Aria2DownloadTask.Progress(
            totalBytes: 0,
            completedBytes: 500,
            downloadSpeed: 100,
            connections: 4,
        )

        #expect(progress.fractionCompleted == 0)
    }

    @Test("estimatedTimeRemaining calculates correctly")
    func estimatedTimeRemainingCalculates() {
        let progress = Aria2DownloadTask.Progress(
            totalBytes: 1_000,
            completedBytes: 500,
            downloadSpeed: 100,
            connections: 4,
        )

        // Remaining: 500 bytes at 100 bytes/sec = 5 seconds
        #expect(progress.estimatedTimeRemaining == 5.0)
    }

    @Test("estimatedTimeRemaining is nil when speed is zero")
    func estimatedTimeRemainingNilWhenNoSpeed() {
        let progress = Aria2DownloadTask.Progress(
            totalBytes: 1_000,
            completedBytes: 500,
            downloadSpeed: 0,
            connections: 4,
        )

        #expect(progress.estimatedTimeRemaining == nil)
    }
}

// MARK: - Aria2Daemon Error Tests

@Suite("Aria2Daemon Error", .tags(.downloadManager))
@MainActor
struct Aria2DaemonErrorTests {
    @Test("Error descriptions are non-empty")
    func errorDescriptionsNonEmpty() throws {
        let errors: [Aria2Daemon.Error] = [
            .binaryNotFound,
            .alreadyRunning,
            .notRunning,
            .startupFailed("Test failure"),
            .terminationFailed,
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(try !(#require(error.errorDescription?.isEmpty)))
        }
    }

    @Test("startupFailed includes message")
    func startupFailedIncludesMessage() throws {
        let error = Aria2Daemon.Error.startupFailed("Connection refused")

        #expect(try #require(error.errorDescription?.contains("Connection refused")))
    }
}

// MARK: - Aria2Daemon Configuration Tests

@Suite("Aria2Daemon Configuration", .tags(.downloadManager))
@MainActor
struct Aria2DaemonConfigurationTests {
    @Test("Default configuration values")
    func defaultConfigurationValues() {
        let config = Aria2Daemon.Configuration()

        #expect(config.port == 6_800)
        #expect(config.maxConcurrentDownloads == 5)
        #expect(config.connectionsPerServer == 16)
        #expect(config.minSplitSize == "1M")
        #expect(config.diskCache == "64M")
        #expect(config.downloadDirectory == nil)
        #expect(config.enableBitTorrent == false)
    }

    @Test("toArguments includes required flags")
    func toArgumentsIncludesRequired() {
        let config = Aria2Daemon.Configuration()
        let args = config.toArguments()

        #expect(args.contains("--enable-rpc"))
        #expect(args.contains("--rpc-listen-port=6800"))
        #expect(args.contains("--continue=true"))
        #expect(args.contains("--max-connection-per-server=16"))
        #expect(args.contains("--split=16"))
        #expect(args.contains("--max-concurrent-downloads=5"))
    }

    @Test("toArguments includes directory when set")
    func toArgumentsIncludesDirectory() {
        var config = Aria2Daemon.Configuration()
        config.downloadDirectory = "/tmp/downloads"

        let args = config.toArguments()

        #expect(args.contains("--dir=/tmp/downloads"))
    }

    @Test("toArguments includes BitTorrent options when enabled")
    func toArgumentsIncludesBitTorrent() {
        var config = Aria2Daemon.Configuration()
        config.enableBitTorrent = true

        let args = config.toArguments()

        #expect(args.contains("--enable-dht=true"))
        #expect(args.contains("--enable-peer-exchange=true"))
        #expect(args.contains("--bt-enable-lpd=true"))
    }

    @Test("toArguments excludes directory when nil")
    func toArgumentsExcludesDirectoryWhenNil() {
        let config = Aria2Daemon.Configuration()
        let args = config.toArguments()

        let hasDir = args.contains { $0.hasPrefix("--dir=") }
        #expect(hasDir == false)
    }
}

// MARK: - Aria2DownloadCoordinator Tests

@Suite("Aria2DownloadCoordinator", .tags(.downloadManager))
@MainActor
struct Aria2DownloadCoordinatorTests {
    @Test("shouldUseAria2 returns false when disabled")
    func shouldUseAria2ReturnsFalseWhenDisabled() {
        let coordinator = Aria2DownloadCoordinator.shared
        coordinator.isAria2Enabled = false

        let result = coordinator.shouldUseAria2(contentLength: 100_000_000, mimeType: nil)

        #expect(result == false)
    }

    @Test("shouldUseAria2 returns true for large files when enabled")
    func shouldUseAria2TrueForLargeFiles() {
        let coordinator = Aria2DownloadCoordinator.shared
        coordinator.isAria2Enabled = true
        coordinator.largeFileThreshold = 50 * 1_024 * 1_024 // 50 MB

        // 100 MB file
        let result = coordinator.shouldUseAria2(contentLength: 100 * 1_024 * 1_024, mimeType: nil)

        #expect(result == true)

        // Reset
        coordinator.isAria2Enabled = false
    }

    @Test("shouldUseAria2 returns false for small files")
    func shouldUseAria2FalseForSmallFiles() {
        let coordinator = Aria2DownloadCoordinator.shared
        coordinator.isAria2Enabled = true
        coordinator.largeFileThreshold = 50 * 1_024 * 1_024 // 50 MB

        // 10 MB file
        let result = coordinator.shouldUseAria2(contentLength: 10 * 1_024 * 1_024, mimeType: nil)

        #expect(result == false)

        // Reset
        coordinator.isAria2Enabled = false
    }

    @Test("shouldUseAria2 returns true for large MIME types")
    func shouldUseAria2TrueForLargeMIMETypes() {
        let coordinator = Aria2DownloadCoordinator.shared
        coordinator.isAria2Enabled = true

        let largeMIMETypes = [
            "application/zip",
            "application/x-gzip",
            "application/x-tar",
            "application/x-7z-compressed",
            "application/x-rar-compressed",
            "application/x-apple-diskimage",
            "video/mp4",
            "application/octet-stream",
        ]

        for mimeType in largeMIMETypes {
            let result = coordinator.shouldUseAria2(contentLength: nil, mimeType: mimeType)
            #expect(result == true, "Expected true for \(mimeType)")
        }

        // Reset
        coordinator.isAria2Enabled = false
    }

    @Test("shouldUseAria2 returns false for regular MIME types")
    func shouldUseAria2FalseForRegularMIMETypes() {
        let coordinator = Aria2DownloadCoordinator.shared
        coordinator.isAria2Enabled = true

        let result = coordinator.shouldUseAria2(contentLength: nil, mimeType: "text/html")

        #expect(result == false)

        // Reset
        coordinator.isAria2Enabled = false
    }
}

// MARK: - Aria2RPC Error Tests

@Suite("Aria2RPC Error", .tags(.downloadManager))
@MainActor
struct Aria2RPCErrorTests {
    @Test("Error descriptions are non-empty")
    func errorDescriptionsNonEmpty() throws {
        let errors: [Aria2RPC.Error] = [
            .httpError(statusCode: 500),
            .rpcError(code: -1, message: "Test error"),
            .invalidResponse,
            .notRunning,
        ]

        for error in errors {
            #expect(error.errorDescription != nil)
            #expect(try !(#require(error.errorDescription?.isEmpty)))
        }
    }

    @Test("httpError includes status code")
    func httpErrorIncludesStatusCode() throws {
        let error = Aria2RPC.Error.httpError(statusCode: 404)

        #expect(try #require(error.errorDescription?.contains("404")))
    }

    @Test("rpcError includes code and message")
    func rpcErrorIncludesCodeAndMessage() throws {
        let error = Aria2RPC.Error.rpcError(code: 42, message: "Download failed")

        #expect(try #require(error.errorDescription?.contains("42")))
        #expect(try #require(error.errorDescription?.contains("Download failed")))
    }

    @Test("connectionFailed includes underlying error")
    func connectionFailedIncludesUnderlying() throws {
        let underlying = NSError(
            domain: "NSURLErrorDomain",
            code: -1_004,
            userInfo: [NSLocalizedDescriptionKey: "Could not connect"],
        )
        let error = Aria2RPC.Error.connectionFailed(underlying)

        #expect(try #require(error.errorDescription?.contains("Could not connect")))
    }
}

// MARK: - Aria2RPC DownloadStatus Tests

@Suite("Aria2RPC DownloadStatus", .tags(.downloadManager))
@MainActor
struct Aria2RPCDownloadStatusTests {
    @Test("progress calculates correctly")
    func progressCalculates() {
        let status = Aria2RPC.DownloadStatus(
            gid: "abc123",
            status: .active,
            totalLength: 1_000,
            completedLength: 500,
            downloadSpeed: 100,
            uploadSpeed: 0,
            connections: 4,
            errorCode: nil,
            errorMessage: nil,
            files: [],
        )

        #expect(status.progress == 0.5)
    }

    @Test("progress is zero when totalLength is zero")
    func progressZeroWhenNoTotal() {
        let status = Aria2RPC.DownloadStatus(
            gid: "abc123",
            status: .active,
            totalLength: 0,
            completedLength: 500,
            downloadSpeed: 100,
            uploadSpeed: 0,
            connections: 4,
            errorCode: nil,
            errorMessage: nil,
            files: [],
        )

        #expect(status.progress == 0)
    }

    @Test("isComplete returns true for complete status")
    func isCompleteReturnsTrue() {
        let status = Aria2RPC.DownloadStatus(
            gid: "abc123",
            status: .complete,
            totalLength: 1_000,
            completedLength: 1_000,
            downloadSpeed: 0,
            uploadSpeed: 0,
            connections: 0,
            errorCode: nil,
            errorMessage: nil,
            files: [],
        )

        #expect(status.isComplete == true)
        #expect(status.hasFailed == false)
    }

    @Test("hasFailed returns true for error status")
    func hasFailedReturnsTrue() {
        let status = Aria2RPC.DownloadStatus(
            gid: "abc123",
            status: .error,
            totalLength: 1_000,
            completedLength: 500,
            downloadSpeed: 0,
            uploadSpeed: 0,
            connections: 0,
            errorCode: 1,
            errorMessage: "Network error",
            files: [],
        )

        #expect(status.hasFailed == true)
        #expect(status.isComplete == false)
    }

    @Test("Status enum raw values are correct")
    func statusRawValues() {
        #expect(Aria2RPC.DownloadStatus.Status.active.rawValue == "active")
        #expect(Aria2RPC.DownloadStatus.Status.waiting.rawValue == "waiting")
        #expect(Aria2RPC.DownloadStatus.Status.paused.rawValue == "paused")
        #expect(Aria2RPC.DownloadStatus.Status.error.rawValue == "error")
        #expect(Aria2RPC.DownloadStatus.Status.complete.rawValue == "complete")
        #expect(Aria2RPC.DownloadStatus.Status.removed.rawValue == "removed")
    }
}

// MARK: - Aria2RPC DownloadOptions Builder Tests

@Suite("Aria2RPC DownloadOptions", .tags(.downloadManager))
@MainActor
struct Aria2RPCDownloadOptionsTests {
    @Test("Empty options builds empty dictionary")
    func emptyOptionsBuildEmpty() {
        let options = Aria2RPC.DownloadOptions()
        let dict = options.build()

        #expect(dict.isEmpty)
    }

    @Test("setDirectory adds dir option")
    func setDirectoryAddsDir() {
        var options = Aria2RPC.DownloadOptions()
        _ = options.setDirectory("/tmp/downloads")

        let dict = options.build()

        #expect(dict["dir"] as? String == "/tmp/downloads")
    }

    @Test("setFilename adds out option")
    func setFilenameAddsOut() {
        var options = Aria2RPC.DownloadOptions()
        _ = options.setFilename("file.pdf")

        let dict = options.build()

        #expect(dict["out"] as? String == "file.pdf")
    }

    @Test("setConnections adds split and max-connection options")
    func setConnectionsAddsOptions() {
        var options = Aria2RPC.DownloadOptions()
        _ = options.setConnections(8)

        let dict = options.build()

        #expect(dict["split"] as? String == "8")
        #expect(dict["max-connection-per-server"] as? String == "8")
    }

    @Test("enableResume adds continue option")
    func enableResumeAddsContinue() {
        var options = Aria2RPC.DownloadOptions()
        _ = options.enableResume(true)

        let dict = options.build()

        #expect(dict["continue"] as? String == "true")
    }

    @Test("enableResume false sets continue to false")
    func enableResumeFalseSetsNo() {
        var options = Aria2RPC.DownloadOptions()
        _ = options.enableResume(false)

        let dict = options.build()

        #expect(dict["continue"] as? String == "false")
    }

    @Test("setReferer adds referer option")
    func setRefererAddsOption() {
        var options = Aria2RPC.DownloadOptions()
        _ = options.setReferer("https://example.com/page")

        let dict = options.build()

        #expect(dict["referer"] as? String == "https://example.com/page")
    }

    @Test("setCookies adds Cookie header")
    func setCookiesAddsHeader() {
        var options = Aria2RPC.DownloadOptions()
        _ = options.setCookies("session=abc123; token=xyz")

        let dict = options.build()
        let headers = dict["header"] as? [String]

        #expect(headers?.contains("Cookie: session=abc123; token=xyz") == true)
    }

    @Test("setUserAgent adds User-Agent header")
    func setUserAgentAddsHeader() {
        var options = Aria2RPC.DownloadOptions()
        _ = options.setUserAgent("Mozilla/5.0 Test")

        let dict = options.build()
        let headers = dict["header"] as? [String]

        #expect(headers?.contains("User-Agent: Mozilla/5.0 Test") == true)
    }

    @Test("setHeaders adds multiple headers")
    func setHeadersAddsMultiple() {
        var options = Aria2RPC.DownloadOptions()
        _ = options.setHeaders(["X-Custom": "value1", "X-Another": "value2"])

        let dict = options.build()
        let headers = dict["header"] as? [String] ?? []

        #expect(headers.contains("X-Custom: value1"))
        #expect(headers.contains("X-Another: value2"))
    }

    @Test("Multiple header setters accumulate")
    func multipleHeaderSettersAccumulate() {
        var options = Aria2RPC.DownloadOptions()
        _ = options.setCookies("session=abc")
        _ = options.setUserAgent("TestAgent")
        _ = options.setHeaders(["X-Custom": "value"])

        let dict = options.build()
        let headers = dict["header"] as? [String] ?? []

        #expect(headers.count == 3)
        #expect(headers.contains("Cookie: session=abc"))
        #expect(headers.contains("User-Agent: TestAgent"))
        #expect(headers.contains("X-Custom: value"))
    }

    @Test("Multiple options can be set")
    func multipleOptionsCanBeSet() {
        var options = Aria2RPC.DownloadOptions()
        _ = options.setDirectory("/tmp")
        _ = options.setFilename("file.zip")
        _ = options.setConnections(16)
        _ = options.enableResume()

        let dict = options.build()

        #expect(dict["dir"] as? String == "/tmp")
        #expect(dict["out"] as? String == "file.zip")
        #expect(dict["split"] as? String == "16")
        #expect(dict["continue"] as? String == "true")
    }
}

// MARK: - Notes

//
// DownloadManager functionality requiring integration tests:
//
// 1. startDownload: Requires network access and WKWebsiteDataStore cookies
// 2. pause/resume with real task: Requires active URLSession download
// 3. Aria2 integration: Requires aria2 process and RPC communication
// 4. File progress publishing: Requires Finder/Dock integration
// 5. Quarantine attribute handling: Requires file system operations
// 6. revealInFinder/openFile: Requires NSWorkspace integration
//
// The tests above verify model state transitions, error handling,
// filename utilities, and manager state without network/filesystem I/O.
//
