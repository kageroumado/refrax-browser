import AppKit
import Foundation
import UniformTypeIdentifiers

/// Runtime wrapper for an active URLSession download operation.
///
/// `DownloadTask` uses `URLSessionDataTask` to stream data directly to a `.download`
/// file in the Downloads folder. This enables:
///
/// - Real-time progress display in Finder (file grows as data arrives)
/// - NSProgress integration with actual file on disk
/// - Safari-like download experience
/// - Resumable downloads with Range header support
///
/// ## Architecture
///
/// ```
/// ┌─────────────────────────────────────────────────────────────┐
/// │                     DownloadTask                             │
/// ├─────────────────────────────────────────────────────────────┤
/// │  URLSessionDataTask ──writes──→ .download file ──rename──→ final │
/// │       │                              │                        │
/// │       ▼                              ▼                        ▼
/// │  didReceive data            NSProgress published        Quarantine
/// │  (progressive write)        (Finder shows progress)     (security)
/// └─────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Resume Support
///
/// Downloads can be resumed if the server supports Range requests (indicated by
/// `Accept-Ranges: bytes` header). Resume data includes:
/// - Byte offset where download was paused
/// - ETag or Last-Modified for content validation
/// - Temporary file path
///
/// ## Swift 6 Concurrency
///
/// URLSession delegate methods use `MainActor.assumeIsolated`
/// since we configure the delegate queue as main.
final class DownloadTask: NSObject, Identifiable {
    // MARK: - Identity

    let id: UUID

    // MARK: - State

    /// The persisted download model.
    let download: Download

    /// The active URLSession data task.
    private(set) var urlSessionTask: URLSessionDataTask?

    /// The URLSession used for this download.
    private var urlSession: URLSession?

    /// Dedicated cookie storage for this download (for privacy isolation).
    private var cookieStorage: HTTPCookieStorage?

    /// File handle for writing received data.
    private var fileHandle: FileHandle?

    /// Whether a write error has occurred (to avoid duplicate failure handling).
    private var hasWriteError: Bool = false

    // MARK: - Callbacks

    /// Callback when download completes successfully.
    var onComplete: (@MainActor (DownloadTask) -> Void)?

    /// Callback when download fails.
    var onFailed: (@MainActor (DownloadTask, any Error, Data?) -> Void)?

    /// Callback for progress updates.
    var onProgress: (@MainActor (DownloadTask) -> Void)?

    /// Callback when destination file is ready (file created, filename resolved).
    /// This is the right time to publish NSProgress for Finder integration.
    var onDestinationReady: (@MainActor (DownloadTask, URL) -> Void)?

    // MARK: - Progress Tracking

    /// Last time progress was reported to the UI.
    private var lastProgressUpdate: ContinuousClock.Instant = .now

    /// Minimum interval between progress updates.
    private let progressThrottleInterval: Duration = .milliseconds(100)

    /// Bytes received at last speed calculation.
    private var lastBytesForSpeed: Int64 = 0

    /// Time of last speed calculation.
    private var lastSpeedCalculation: ContinuousClock.Instant = .now

    /// Smoothing factor for speed calculation (lower = smoother).
    private let speedSmoothingFactor: Double = 0.3

    /// Total bytes received so far.
    private var bytesReceived: Int64 = 0

    /// Expected total bytes (from Content-Length).
    private var expectedBytes: Int64?

    // MARK: - File Handling

    /// URL of the temporary download file (.download suffix).
    private var tempFileURL: URL?

    /// URL of the final destination file.
    private var finalFileURL: URL?

    // MARK: - Source Info

    /// URL of the page that initiated the download.
    private var originatingURL: URL?

    // MARK: - Resume Support

    /// Whether the server supports resumable downloads (Accept-Ranges: bytes).
    private var serverSupportsResume: Bool = false

    /// ETag from the server response for resume validation.
    private var etag: String?

    /// Last-Modified from the server response for resume validation.
    private var lastModified: String?

    /// Starting byte offset when resuming a download.
    private var resumeOffset: Int64 = 0

    // MARK: - Initialization

    init(download: Download, originatingURL: URL? = nil) {
        self.id = download.id
        self.download = download
        self.originatingURL = originatingURL
        super.init()
    }

    deinit {
        try? fileHandle?.close()
    }

    // MARK: - Download Control

    /// Starts the download from the source URL.
    ///
    /// - Parameter cookies: Cookies to include with the request.
    func start(cookies: [HTTPCookie] = []) async throws {
        try await startDownload(cookies: cookies, resumeFrom: nil)
    }

    /// Starts or resumes a download.
    ///
    /// - Parameters:
    ///   - cookies: Cookies to include with the request.
    ///   - resumeFrom: Optional resume data containing byte offset and validators.
    private func startDownload(cookies: [HTTPCookie], resumeFrom resumeData: ResumeData?) async throws {
        // Create dedicated cookie storage for privacy isolation
        // Using a unique group ID per download prevents cookie leakage between downloads
        let storage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: "download-\(id.uuidString)")
        cookieStorage = storage

        // Set cookies asynchronously to avoid priority inversion on main thread
        // HTTPCookieStorage is thread-safe
        if !cookies.isEmpty {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                Task.detached(priority: .utility) {
                    for cookie in cookies {
                        storage.setCookie(cookie)
                    }
                    continuation.resume()
                }
            }
        }

        // Create session configuration with our dedicated cookie storage
        let config = URLSessionConfiguration.default
        config.httpCookieStorage = storage

        // Create session with delegate on main queue for proper Swift 6 isolation
        let delegateQueue = OperationQueue.main
        let session = URLSession(configuration: config, delegate: self, delegateQueue: delegateQueue)
        urlSession = session

        // Create data task (not download task - we handle file writing ourselves)
        var request = URLRequest(url: download.sourceURL)
        request.httpShouldHandleCookies = true

        // If resuming, add Range header and validation headers
        if let resumeData {
            resumeOffset = resumeData.bytesReceived
            bytesReceived = resumeData.bytesReceived

            // Request bytes from where we left off
            request.setValue("bytes=\(resumeData.bytesReceived)-", forHTTPHeaderField: "Range")

            // Add conditional header for validation (If-Range with ETag or Last-Modified)
            if let etag = resumeData.etag {
                request.setValue(etag, forHTTPHeaderField: "If-Range")
            } else if let lastModified = resumeData.lastModified {
                request.setValue(lastModified, forHTTPHeaderField: "If-Range")
            }

            // Restore saved validators for this session
            etag = resumeData.etag
            lastModified = resumeData.lastModified
            tempFileURL = resumeData.tempFileURL
            finalFileURL = resumeData.finalFileURL
        }

        let task = session.dataTask(with: request)
        urlSessionTask = task

        download.markDownloading()
        task.resume()

        let resumeInfo = resumeData != nil ? " (resuming from \(resumeData!.bytesReceived) bytes)" : ""
        Logger.info(
            "Download started: \(download.sourceURL.lastPathComponent)\(resumeInfo)",
            category: Logger.downloads,
        )
    }

    /// Clears cookies from the dedicated storage for privacy.
    private func clearCookies() {
        guard let storage = cookieStorage else { return }

        // Clear asynchronously to avoid blocking
        Task.detached(priority: .utility) {
            if let cookies = storage.cookies {
                for cookie in cookies {
                    storage.deleteCookie(cookie)
                }
            }
        }
        cookieStorage = nil
    }

    /// Resumes a paused download with resume data.
    ///
    /// Resume requires:
    /// - Server support for Range requests (Accept-Ranges: bytes)
    /// - Valid ETag or Last-Modified for content validation
    /// - Existing partial download file
    ///
    /// If resume fails (content changed, server doesn't support), download restarts from beginning.
    ///
    /// - Parameters:
    ///   - resumeData: The resume data containing byte offset and validators.
    ///   - cookies: Cookies to include with the request.
    func resume(with resumeData: Data, cookies: [HTTPCookie] = []) async throws {
        guard let parsedResumeData = ResumeData.deserialize(from: resumeData) else {
            Logger.warning("Invalid resume data, restarting download", category: Logger.downloads)
            try await start(cookies: cookies)
            return
        }

        // Verify the partial file still exists
        if let tempURL = parsedResumeData.tempFileURL {
            let fm = FileManager.default
            if fm.fileExists(atPath: tempURL.path) {
                try await startDownload(cookies: cookies, resumeFrom: parsedResumeData)
                return
            } else {
                Logger.warning("Partial file missing, restarting download", category: Logger.downloads)
            }
        }

        // Fall back to fresh start if resume not possible
        try await start(cookies: cookies)
    }

    /// Pauses the download.
    ///
    /// - Returns: Resume data for later resumption, or nil if resume not supported.
    func pause() async -> Data? {
        guard let task = urlSessionTask else { return nil }

        task.cancel()

        // Close file handle but keep the partial file
        try? fileHandle?.close()
        fileHandle = nil

        // Only return resume data if server supports resume
        guard serverSupportsResume else {
            Logger.info("Server doesn't support resume, cleaning up partial file", category: Logger.downloads)
            cleanupTempFile()
            return nil
        }

        // Create resume data with all necessary information
        let resumeData = ResumeData(
            bytesReceived: bytesReceived,
            etag: etag,
            lastModified: lastModified,
            tempFileURL: tempFileURL,
            finalFileURL: finalFileURL,
        )

        return resumeData.serialize()
    }

    /// Cancels the download permanently.
    func cancel() {
        urlSessionTask?.cancel()
        urlSessionTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        try? fileHandle?.close()
        fileHandle = nil

        cleanupTempFile()
    }

    // MARK: - File Operations

    /// Prepares the destination file, resolving any conflicts.
    private func prepareDestination(suggestedFilename: String?, mimeType: String?) throws {
        let fm = FileManager.default

        // Use filename utilities for proper handling
        var filename = suggestedFilename ?? download.suggestedFilename

        // Sanitize the filename
        filename = FilenameUtilities.sanitize(filename)

        // Add extension if needed based on MIME type
        if let mimeType {
            filename = FilenameUtilities.ensureExtension(for: filename, mimeType: mimeType)
        }

        // Resolve conflicts
        filename = try FilenameUtilities.uniqueFilename(
            for: filename,
            in: download.destinationDirectory,
        )

        download.destinationFilename = filename

        // Set up file URLs
        tempFileURL = download.destinationDirectory.appendingPathComponent("\(filename).download")
        finalFileURL = download.destinationDirectory.appendingPathComponent(filename)

        // Create the .download file and open for writing
        guard let tempURL = tempFileURL else { return }

        // Ensure destination directory exists
        if !fm.fileExists(atPath: download.destinationDirectory.path) {
            try fm.createDirectory(at: download.destinationDirectory, withIntermediateDirectories: true)
        }

        // Create empty file
        fm.createFile(atPath: tempURL.path, contents: nil)

        // Open file handle for writing
        fileHandle = try FileHandle(forWritingTo: tempURL)

        // Notify that destination is ready - NSProgress can now be published
        onDestinationReady?(self, tempURL)

        Logger.info("Created download file: \(tempURL.lastPathComponent)", category: Logger.downloads)
    }

    private func cleanupTempFile() {
        guard let tempURL = tempFileURL else { return }

        try? FileManager.default.removeItem(at: tempURL)
        tempFileURL = nil
    }

    /// Finalizes the download by renaming .download to final name.
    private func finalizeDownload() throws {
        guard let tempURL = tempFileURL,
              let finalURL = finalFileURL else {
            throw DownloadError.fileOperationFailed(
                NSError(domain: "DownloadTask", code: -1, userInfo: [
                    NSLocalizedDescriptionKey: "Missing file URLs",
                ]),
            )
        }

        let fm = FileManager.default

        // Close file handle first
        try? fileHandle?.close()
        fileHandle = nil

        // Rename .download to final filename
        try fm.moveItem(at: tempURL, to: finalURL)

        // Set quarantine attributes for security
        do {
            try finalURL.setQuarantineAttributes(
                downloadURL: download.sourceURL,
                originURL: originatingURL,
            )
        } catch {
            Logger.warning(
                "Failed to set quarantine on \(finalURL.lastPathComponent): \(error)",
                category: Logger.downloads,
            )
        }

        download.markCompleted()

        // Notify Finder that file system changed
        NSWorkspace.shared.noteFileSystemChanged(finalURL.path)

        // Bounce the dock icon (like Chrome/Safari)
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.apple.DownloadFileFinished"),
            object: finalURL.path,
            userInfo: nil,
            deliverImmediately: true,
        )

        Logger.info("Download completed: \(download.destinationFilename)", category: Logger.downloads)
    }

    // MARK: - Progress Handling

    private func updateProgress() {
        let now = ContinuousClock.now

        // Throttle updates
        guard now - lastProgressUpdate >= progressThrottleInterval else { return }
        lastProgressUpdate = now

        // Calculate speed with exponential smoothing
        let timeDelta = now - lastSpeedCalculation
        let bytesDelta = bytesReceived - lastBytesForSpeed

        var speed = download.bytesPerSecond

        if timeDelta > .milliseconds(500), bytesDelta > 0 {
            let instantSpeed = Double(bytesDelta) / timeDelta.asSeconds
            speed = download.bytesPerSecond * (1 - speedSmoothingFactor)
                + instantSpeed * speedSmoothingFactor

            lastBytesForSpeed = bytesReceived
            lastSpeedCalculation = now
        }

        download.updateLiveProgress(
            bytesReceived: bytesReceived,
            totalBytes: expectedBytes,
            bytesPerSecond: speed,
        )

        onProgress?(self)
    }

    // MARK: - Response Processing

    /// Extracts filename from HTTP response headers.
    private nonisolated func extractFilename(from response: HTTPURLResponse) -> String? {
        // Try Content-Disposition first
        if let disposition = response.value(forHTTPHeaderField: "Content-Disposition"),
           let filename = FilenameUtilities.parseContentDisposition(disposition) {
            return filename
        }

        // Fall back to suggested filename
        return response.suggestedFilename
    }
}

// MARK: - URLSessionDataDelegate

extension DownloadTask: URLSessionDataDelegate {
    nonisolated func urlSession(
        _: URLSession,
        dataTask _: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void,
    ) {
        // Extract response info before entering MainActor context (nonisolated work)
        let suggestedFilename: String?
        let mimeType = response.mimeType
        let contentLength = response.expectedContentLength

        // Extract HTTP-specific information
        var acceptRanges: String?
        var etagValue: String?
        var lastModifiedValue: String?
        var statusCode = 200
        var isPartialContent = false

        if let httpResponse = response as? HTTPURLResponse {
            suggestedFilename = extractFilename(from: httpResponse)
            acceptRanges = httpResponse.value(forHTTPHeaderField: "Accept-Ranges")
            etagValue = httpResponse.value(forHTTPHeaderField: "ETag")
            lastModifiedValue = httpResponse.value(forHTTPHeaderField: "Last-Modified")
            statusCode = httpResponse.statusCode
            isPartialContent = statusCode == 206
        } else {
            suggestedFilename = response.suggestedFilename
        }

        // Perform MainActor-isolated work and capture the result
        let disposition: URLSession.ResponseDisposition = MainActor.assumeIsolated {
            // Check if server supports resume (Accept-Ranges: bytes)
            if let ranges = acceptRanges?.lowercased(), ranges.contains("bytes") {
                serverSupportsResume = true
            }

            // Store validators for potential future resume
            if let etag = etagValue {
                self.etag = etag
            }
            if let lastMod = lastModifiedValue {
                self.lastModified = lastMod
            }

            // Handle resume response
            if isPartialContent {
                // Server accepted our Range request - we're resuming
                Logger.info("Resuming download from byte \(resumeOffset)", category: Logger.downloads)

                // For partial content, total bytes = current position + remaining content length
                if contentLength > 0 {
                    expectedBytes = resumeOffset + contentLength
                    download.totalBytes = expectedBytes
                }

                // Re-open existing temp file for appending
                if let tempURL = tempFileURL {
                    do {
                        fileHandle = try FileHandle(forWritingTo: tempURL)
                        try fileHandle?.seekToEnd()
                        onDestinationReady?(self, tempURL)
                    } catch {
                        Logger.error("Failed to open temp file for resume: \(error)", category: Logger.downloads)
                        return URLSession.ResponseDisposition.cancel
                    }
                }

                return URLSession.ResponseDisposition.allow

            } else if statusCode == 200, resumeOffset > 0 {
                // Server sent 200 instead of 206 - content changed or resume not supported
                // We need to restart from beginning
                Logger.warning(
                    "Server returned 200 instead of 206, content may have changed. Restarting download.",
                    category: Logger.downloads,
                )
                resumeOffset = 0
                bytesReceived = 0

                // Clean up old partial file
                if let tempURL = tempFileURL {
                    try? FileManager.default.removeItem(at: tempURL)
                    tempFileURL = nil
                }
            }

            // Extract expected content length for fresh downloads
            if contentLength > 0 {
                expectedBytes = contentLength
                download.totalBytes = contentLength
            }

            // Prepare destination file on first response (fresh download)
            if tempFileURL == nil {
                do {
                    try prepareDestination(suggestedFilename: suggestedFilename, mimeType: mimeType)
                } catch {
                    Logger.error("Failed to prepare destination: \(error)", category: Logger.downloads)
                    return URLSession.ResponseDisposition.cancel
                }
            }

            return URLSession.ResponseDisposition.allow
        }

        // Call completion handler outside of MainActor.assumeIsolated
        completionHandler(disposition)
    }

    nonisolated func urlSession(
        _: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data,
    ) {
        // Use MainActor.assumeIsolated since delegate runs on main queue
        MainActor.assumeIsolated {
            // Skip if we've already encountered a write error
            guard !hasWriteError else { return }

            guard let handle = fileHandle else {
                Logger.error("File handle is nil, cannot write data", category: Logger.downloads)
                hasWriteError = true
                dataTask.cancel()
                return
            }

            do {
                // Write data to file
                try handle.write(contentsOf: data)

                // Update progress
                bytesReceived += Int64(data.count)
                updateProgress()

            } catch {
                // Mark that we've had a write error to prevent further attempts
                hasWriteError = true

                Logger.error("Failed to write data: \(error)", category: Logger.downloads)

                // Cancel the task - the error will be handled in didCompleteWithError
                dataTask.cancel()
            }
        }
    }

    nonisolated func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        didCompleteWithError error: (any Error)?,
    ) {
        // Use MainActor.assumeIsolated since delegate runs on main queue
        MainActor.assumeIsolated {
            // Close file handle first
            try? fileHandle?.close()
            fileHandle = nil

            // Check for write errors first
            if hasWriteError {
                let writeError = DownloadError.fileOperationFailed(
                    NSError(
                        domain: "DownloadTask",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "Failed to write download data to disk"],
                    ),
                )
                handleDownloadFailure(writeError)
                return
            }

            if let error {
                handleDownloadFailure(error)
            } else {
                handleDownloadSuccess()
            }
        }
    }

    /// Handles download failure with proper cleanup and resume data generation.
    private func handleDownloadFailure(_ error: any Error) {
        // Generate resume data if possible
        var resumeDataForStorage: Data?

        if serverSupportsResume, bytesReceived > 0, etag != nil || lastModified != nil {
            let resumeData = ResumeData(
                bytesReceived: bytesReceived,
                etag: etag,
                lastModified: lastModified,
                tempFileURL: tempFileURL,
                finalFileURL: finalFileURL,
            )
            resumeDataForStorage = resumeData.serialize()

            // Don't cleanup temp file if we have valid resume data
            Logger.info(
                "Download interrupted with resume capability at \(bytesReceived) bytes",
                category: Logger.downloads,
            )
        } else {
            // No resume capability, clean up partial file
            cleanupTempFile()
        }

        download.markFailed(error: error, resumeData: resumeDataForStorage)

        urlSessionTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil

        // Clear cookies for privacy
        clearCookies()

        onFailed?(self, error, resumeDataForStorage)

        Logger.warning(
            "Download failed: \(download.destinationFilename) - \(error.localizedDescription)",
            category: Logger.downloads,
        )
    }

    /// Handles successful download completion.
    private func handleDownloadSuccess() {
        do {
            try finalizeDownload()

            urlSessionTask = nil
            urlSession?.finishTasksAndInvalidate()
            urlSession = nil

            // Clear cookies for privacy
            clearCookies()

            onComplete?(self)

        } catch {
            download.markFailed(error: error, resumeData: nil)
            clearCookies()
            onFailed?(self, error, nil)
            Logger.error("Download finalization failed: \(error)", category: Logger.downloads)
        }
    }
}

// MARK: - Duration Extension

private extension Duration {
    var asSeconds: Double {
        let (seconds, attoseconds) = components
        return Double(seconds) + Double(attoseconds) / 1e18
    }
}

// MARK: - Resume Data

/// Data structure for resuming interrupted downloads.
///
/// Contains all information needed to resume a download from where it left off:
/// - Current byte offset
/// - Server validators (ETag or Last-Modified) for content validation
/// - File paths for the partial and final files
///
/// This is serialized to `Data` for storage in the `Download` model.
struct ResumeData: Codable {
    /// Number of bytes already downloaded.
    let bytesReceived: Int64

    /// ETag from the original response for content validation.
    let etag: String?

    /// Last-Modified from the original response for content validation.
    let lastModified: String?

    /// Path to the partial download file (.download suffix).
    let tempFilePath: String?

    /// Path to the final destination file.
    let finalFilePath: String?

    /// URL of the temporary file.
    var tempFileURL: URL? {
        tempFilePath.map { URL(fileURLWithPath: $0) }
    }

    /// URL of the final file.
    var finalFileURL: URL? {
        finalFilePath.map { URL(fileURLWithPath: $0) }
    }

    init(
        bytesReceived: Int64,
        etag: String?,
        lastModified: String?,
        tempFileURL: URL?,
        finalFileURL: URL?,
    ) {
        self.bytesReceived = bytesReceived
        self.etag = etag
        self.lastModified = lastModified
        self.tempFilePath = tempFileURL?.path
        self.finalFilePath = finalFileURL?.path
    }

    /// Serializes the resume data to `Data` for storage.
    func serialize() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// Deserializes resume data from stored `Data`.
    static func deserialize(from data: Data) -> ResumeData? {
        try? JSONDecoder().decode(ResumeData.self, from: data)
    }
}
