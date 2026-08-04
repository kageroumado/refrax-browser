import AppKit
import Foundation
import Observation
import Photos
import SwiftData
import UniformTypeIdentifiers
import WebKit

/// Coordinates all download operations across the application.
///
/// `DownloadManager` is the single entry point for download-related functionality:
///
/// - Starting downloads from navigation responses
/// - Pause/resume/cancel operations
/// - Progress aggregation for Dock icon
/// - Persistence of download history
/// - Coordinated file operations with quarantine attributes
/// - Optional aria2 integration for large files
///
/// ## Architecture
///
/// ```
/// ┌─────────────────────────────────────────────────────────────────────┐
/// │                        DownloadManager                               │
/// │                                                                      │
/// │   ┌─────────────────────┐     ┌─────────────────────────────────┐   │
/// │   │   URLSession Tasks  │     │  Aria2 Tasks (optional, large)  │   │
/// │   │   (< threshold)     │     │  (>= threshold, configurable)   │   │
/// │   └──────────┬──────────┘     └────────────────┬────────────────┘   │
/// │              │                                  │                    │
/// │              ▼                                  ▼                    │
/// │   ┌─────────────────────────────────────────────────────────────┐   │
/// │   │              Coordinated File Operations                     │   │
/// │   │   - Same-volume temp directory (instant moves)               │   │
/// │   │   - NSFileCoordinator (iCloud, Finder safety)                │   │
/// │   │   - Quarantine attributes (Gatekeeper security)              │   │
/// │   │   - File presenter (track user moves/deletes)                │   │
/// │   └─────────────────────────────────────────────────────────────┘   │
/// │                              │                                       │
/// │                              ▼                                       │
/// │   ┌─────────────────────────────────────────────────────────────┐   │
/// │   │                   SwiftData Persistence                      │   │
/// │   └─────────────────────────────────────────────────────────────┘   │
/// └─────────────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Finder/Dock Progress
///
/// Uses `NSProgress` published for each file URL to show per-file download
/// progress in Finder and the Dock's Downloads stack, with pause/resume
/// buttons (following Safari's convention).
///
/// ## Aria2 Integration
///
/// For large files (configurable threshold), aria2 provides:
/// - Multi-connection downloads (faster than single connection)
/// - Automatic chunk-level resume
/// - Better handling of slow/unreliable connections
///
/// Enable via `useAria2ForLargeFiles = true`.
///
/// ## Usage
///
/// ```swift
/// // Start a download (automatically selects URLSession or aria2)
/// try await downloadManager.startDownload(from: url, suggestedFilename: "file.pdf")
///
/// // Pause
/// await downloadManager.pause(downloadID)
///
/// // Resume
/// try await downloadManager.resume(downloadID)
///
/// // Cancel
/// downloadManager.cancel(downloadID)
/// ```
@Observable
final class DownloadManager {
    // MARK: - Dependencies

    /// Model context for persistence.
    private let modelContext: ModelContext

    /// WebKit data store for fetching cookies to share with downloads.
    private let dataStore: WKWebsiteDataStore

    // MARK: - State

    /// Active download tasks by ID.
    private var activeTasks: [UUID: DownloadTask] = [:]

    /// Downloads pending Photos import on completion.
    /// Maps download ID to whether the file should be deleted after import.
    private var photosImportPending: [UUID: Bool] = [:]

    /// All downloads (active and historical).
    private(set) var downloads: [Download] = []

    /// Total progress for Dock icon (0.0-1.0).
    private(set) var aggregateProgress: Double = 0

    /// Number of active downloads.
    var activeDownloadCount: Int {
        activeTasks.count
    }

    /// Whether any downloads are in progress.
    var hasActiveDownloads: Bool {
        !activeTasks.isEmpty
    }

    // MARK: - Settings

    /// Default download directory.
    var downloadDirectory: URL {
        didSet {
            // Validate directory exists or can be created
            let fm = FileManager.default
            if !fm.fileExists(atPath: downloadDirectory.path) {
                try? fm.createDirectory(at: downloadDirectory, withIntermediateDirectories: true)
            }
        }
    }

    /// Resolves the download directory for a given custom path.
    ///
    /// Checks for custom download path first, falling back to the global default.
    ///
    /// - Parameter customPath: Optional custom download path. Pass `nil` to use the global default.
    /// - Returns: The resolved download directory URL.
    func downloadDirectory(for customPath: String?) -> URL {
        guard let customPath, !customPath.isEmpty else {
            return downloadDirectory
        }

        let customURL = URL(fileURLWithPath: customPath)
        let fm = FileManager.default

        // Verify the directory is writable
        if fm.isWritableFile(atPath: customURL.path) {
            return customURL
        }

        // Attempt to create if it doesn't exist
        if !fm.fileExists(atPath: customURL.path) {
            do {
                try fm.createDirectory(at: customURL, withIntermediateDirectories: true)
                return customURL
            } catch {
                Logger.warning(
                    "Cannot create custom download directory: \(customPath), using default",
                    category: Logger.downloads,
                )
            }
        }

        // Fall back to global default if not writable
        Logger.warning(
            "Custom download directory not writable: \(customPath), using default",
            category: Logger.downloads,
        )
        return downloadDirectory
    }

    /// Whether to show the downloads panel when a download starts.
    var showPanelOnStart: Bool = true

    /// Whether to show the downloads panel when a download completes.
    var showPanelOnCompletion: Bool = true

    /// Whether to use aria2 for large file downloads.
    ///
    /// When enabled, downloads larger than `aria2Threshold` use aria2's
    /// multi-connection downloader for improved speed and reliability.
    var useAria2ForLargeFiles: Bool = false

    /// Size threshold (in bytes) for using aria2.
    ///
    /// Downloads >= this size will use aria2 if `useAria2ForLargeFiles` is true.
    /// Default: 50 MB
    var aria2Threshold: Int64 = 50 * 1_024 * 1_024

    /// Whether BitTorrent downloads are enabled.
    ///
    /// When enabled, magnet: links and .torrent files can be downloaded.
    var enableBitTorrent: Bool = false

    // MARK: - File Progress (Finder/Dock Integration)

    /// Per-file progress objects for Finder/Dock integration.
    ///
    /// Each downloading file gets an `NSProgress` published with its file URL.
    /// Finder automatically shows progress bars on these files in the Downloads
    /// stack and folder, with pause/resume buttons (like Safari).
    private var fileProgressObjects: [UUID: Progress] = [:]

    // MARK: - Persistence

    /// Debounced saver for download state.
    private let saver: DebouncedModelContextSaver

    // MARK: - Callbacks

    /// Called when a download starts.
    var onDownloadStarted: ((Download) -> Void)?

    /// Called when a download completes.
    var onDownloadCompleted: ((Download) -> Void)?

    /// Called when a download fails.
    var onDownloadFailed: ((Download, any Error) -> Void)?

    /// Called when aggregate progress changes.
    var onProgressChanged: (() -> Void)?

    // MARK: - Initialization

    init(modelContext: ModelContext, dataStore: WKWebsiteDataStore = .default()) {
        self.modelContext = modelContext
        self.dataStore = dataStore
        self.saver = DebouncedModelContextSaver(
            modelContext: modelContext,
            debounceDelay: 1.7,
            logCategory: Logger.downloads,
        )

        // Default to user's Downloads folder
        self.downloadDirectory = FileManager.default.urls(
            for: .downloadsDirectory,
            in: .userDomainMask,
        ).first ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")

        // Heavy SwiftData work is deferred to after first frame.
        // Call performDeferredSetup() from AppDelegate after window is shown.

        Logger.info("DownloadManager initialized", category: Logger.downloads)
    }

    /// Performs deferred setup operations that shouldn't block app launch.
    ///
    /// This method should be called after the first frame renders to avoid
    /// blocking app launch. It loads persisted downloads from SwiftData.
    func performDeferredSetup() {
        loadDownloads()
        resumeAria2Downloads()
        Logger.info("DownloadManager deferred setup complete", category: Logger.downloads)
    }

    /// Resumes aria2-managed downloads that were active before app restart.
    private func resumeAria2Downloads() {
        // Find downloads with aria2GID that were active or paused
        let aria2Downloads = downloads.filter { download in
            download.aria2GID != nil && (download.state == .downloading || download.state == .paused)
        }

        guard !aria2Downloads.isEmpty else { return }

        Task {
            // Ensure daemon is running with current settings
            syncAria2Settings()

            do {
                try await Aria2DownloadCoordinator.shared.ensureDaemonRunning()
            } catch {
                Logger.warning("Failed to start aria2 daemon for resume: \(error)", category: Logger.downloads)
                // Mark all aria2 downloads as paused since we can't resume
                for download in aria2Downloads {
                    download.state = .paused
                }
                scheduleSave()
                return
            }

            guard let rpc = await Aria2DownloadCoordinator.shared.getRPCClient() else {
                return
            }

            for download in aria2Downloads {
                guard let gid = download.aria2GID else { continue }

                do {
                    // Check if the GID still exists in aria2
                    let status = try await rpc.tellStatus(gid: gid)

                    switch status.status {
                    case .active, .waiting:
                        // Still active, resume polling
                        download.state = .downloading
                        startAria2Polling(for: download, gid: gid)
                        Logger.info("Resumed polling for aria2 download: \(download.destinationFilename)", category: Logger.downloads)

                    case .paused:
                        // Paused in aria2, keep our state synced
                        download.state = .paused

                    case .complete:
                        // Completed while we were away
                        download.markCompleted()
                        onDownloadCompleted?(download)

                    case .error:
                        // Failed while we were away
                        let error = Aria2RPC.Error.rpcError(
                            code: status.errorCode ?? -1,
                            message: status.errorMessage ?? "Unknown error",
                        )
                        download.markFailed(error: error, resumeData: nil)
                        onDownloadFailed?(download, error)

                    case .removed:
                        download.markFailed(error: DownloadError.cancelled, resumeData: nil)
                    }

                } catch let Aria2RPC.Error.rpcError(code, _) where code == 1 {
                    // GID not found - download was cleared from aria2 session
                    // Mark as paused so user can retry
                    download.aria2GID = nil
                    download.state = .paused
                    Logger.info("aria2 GID not found for \(download.destinationFilename), marking as paused", category: Logger.downloads)

                } catch {
                    Logger.warning("Failed to check aria2 status for \(download.destinationFilename): \(error)", category: Logger.downloads)
                    download.state = .paused
                }
            }

            scheduleSave()
            updateAggregateProgress()
        }
    }

    deinit {
        // Unpublish all file progress objects
        // Use assumeIsolated since DownloadManager is @MainActor and deinit runs on main
        MainActor.assumeIsolated {
            for progress in fileProgressObjects.values {
                progress.unpublish()
            }
        }
    }

    // MARK: - Download Lifecycle

    /// Starts a new download from a URL.
    ///
    /// Automatically selects between URLSession and aria2 based on:
    /// - `useAria2ForLargeFiles` setting
    /// - Expected content length vs `aria2Threshold`
    /// - MIME type (some types like disk images typically benefit from aria2)
    ///
    /// - Parameters:
    ///   - url: The URL to download.
    ///   - suggestedFilename: Optional filename hint.
    ///   - mimeType: Optional MIME type hint (helps with extension and aria2 decision).
    ///   - contentLength: Optional content length (helps with aria2 decision).
    ///   - originatingURL: The page that initiated the download.
    ///   - originatingTitle: Title of the originating page.
    ///   - dataStore: Optional data store to pull cookies from (defaults to manager data store).
    ///   - customDownloadPath: Optional custom download path (from space settings). Pass `nil` to use the global default.
    ///   - spaceID: Optional ID of the space initiating the download.
    ///   - spaceName: Optional name of the space (cached for display after deletion).
    ///   - colorTag: Optional Finder color tag to apply on completion (1-7).
    /// - Returns: The created Download model.
    @discardableResult
    func startDownload(
        from url: URL,
        suggestedFilename: String? = nil,
        mimeType: String? = nil,
        contentLength: Int64? = nil,
        originatingURL: URL? = nil,
        originatingTitle: String? = nil,
        dataStore: WKWebsiteDataStore? = nil,
        customDownloadPath: String? = nil,
        spaceID: UUID? = nil,
        spaceName: String? = nil,
        colorTag: Int? = nil,
        saveToPhotos: Bool = false,
        deleteAfterPhotosImport: Bool = false,
    ) async throws -> Download {
        // Sanitize and prepare filename
        var filename = suggestedFilename ?? url.lastPathComponent.removingPercentEncoding ?? "download"
        filename = FilenameUtilities.sanitize(filename)

        // Add extension based on MIME type if needed
        if let mimeType {
            filename = FilenameUtilities.ensureExtension(for: filename, mimeType: mimeType)
        }

        // For Save to Photos, use a temp directory to avoid triggering file system
        // permission prompts for the Downloads folder.
        let destinationDir: URL
        if saveToPhotos {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("RefraxPhotosImport", isDirectory: true)
            try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            destinationDir = tempDir
        } else {
            destinationDir = downloadDirectory(for: customDownloadPath)
        }

        let download = Download(
            sourceURL: url,
            suggestedFilename: filename,
            destinationDirectory: destinationDir,
            originatingPageURL: originatingURL,
            originatingPageTitle: originatingTitle,
            mimeType: mimeType,
            spaceID: spaceID,
            spaceName: spaceName,
            colorTag: colorTag,
        )

        // Set total bytes if known
        if let contentLength {
            download.totalBytes = contentLength
        }

        if saveToPhotos {
            // Don't persist or show in downloads list — this is a transient transfer
            photosImportPending[download.id] = deleteAfterPhotosImport
        } else {
            modelContext.insert(download)
            downloads.insert(download, at: 0)
            scheduleSave()
        }

        // Fetch cookies from WebKit
        let cookies = await fetchCookies(for: url, dataStore: dataStore ?? self.dataStore)

        // Decide whether to use aria2 for this download
        let shouldUseAria2 = useAria2ForLargeFiles &&
            Aria2DownloadCoordinator.shared.shouldUseAria2(
                contentLength: contentLength,
                mimeType: mimeType,
            )

        if shouldUseAria2 {
            try await startAria2Download(download: download, cookies: cookies, originatingURL: originatingURL)
        } else {
            try await startURLSessionDownload(download: download, cookies: cookies, originatingURL: originatingURL)
        }

        updateAggregateProgress()
        onDownloadStarted?(download)

        Logger.info("Download started: \(filename) (aria2: \(shouldUseAria2))", category: Logger.downloads)
        return download
    }

    /// Starts a download using URLSession.
    private func startURLSessionDownload(
        download: Download,
        cookies: [HTTPCookie],
        originatingURL: URL?,
    ) async throws {
        let task = DownloadTask(download: download, originatingURL: originatingURL)
        setupTaskCallbacks(task)
        activeTasks[download.id] = task

        try await task.start(cookies: cookies)
    }

    /// Starts a download using aria2.
    private func startAria2Download(
        download: Download,
        cookies: [HTTPCookie],
        originatingURL _: URL?,
    ) async throws {
        // Format cookies for aria2
        let cookieString = cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")

        // Resolve filename conflicts before starting
        let filename = try FilenameUtilities.uniqueFilename(
            for: download.destinationFilename,
            in: download.destinationDirectory,
        )
        download.destinationFilename = filename

        let destinationURL = download.destinationDirectory.appendingPathComponent(filename)

        let aria2Task = try await Aria2DownloadCoordinator.shared.createAria2Task(
            url: download.sourceURL,
            destination: destinationURL,
            cookies: cookieString.isEmpty ? nil : cookieString,
        )

        // Set up callbacks
        aria2Task.onProgress = { [weak self, weak download] progress in
            guard let self, let download else { return }
            download.updateLiveProgress(
                bytesReceived: progress.completedBytes,
                totalBytes: progress.totalBytes,
                bytesPerSecond: Double(progress.downloadSpeed),
            )
            updateFileProgress(for: download)
            updateAggregateProgress()
            onProgressChanged?()
            // Note: NO scheduleSave() here - progress is transient
        }

        aria2Task.onComplete = { [weak self, weak download] _ in
            guard let self, let download else { return }
            download.markCompleted()
            applyColorTagIfNeeded(to: download)
            unpublishFileProgress(for: download.id)
            updateAggregateProgress()
            scheduleSave()
            onDownloadCompleted?(download)
            Aria2DownloadCoordinator.shared.removeTask(aria2Task.id)
        }

        aria2Task.onFailed = { [weak self, weak download] error in
            guard let self, let download else { return }
            download.markFailed(error: error, resumeData: nil)
            unpublishFileProgress(for: download.id)
            updateAggregateProgress()
            scheduleSave()
            onDownloadFailed?(download, error)
            Aria2DownloadCoordinator.shared.removeTask(aria2Task.id)
        }

        // Publish file progress - aria2 creates the file at destinationURL
        publishFileProgress(for: download, fileURL: destinationURL)

        try await aria2Task.start()
    }

    /// Pauses an active download.
    ///
    /// - Parameter id: The download ID to pause.
    func pause(_ id: UUID) async {
        // Check for yt-dlp download first
        if let ytdlpTask = ytdlpTasks[id] {
            ytdlpTask.pause()
            if let download = downloads.first(where: { $0.id == id }) {
                download.markPaused(resumeData: nil)
                unpublishFileProgress(for: id)
                updateAggregateProgress()
                scheduleSave()
                Logger.info("yt-dlp download paused: \(download.destinationFilename)", category: Logger.downloads)
            }
            return
        }

        guard let task = activeTasks[id] else {
            Logger.warning("Cannot pause: download not active", category: Logger.downloads)
            return
        }

        let resumeData = await task.pause()
        task.download.markPaused(resumeData: resumeData)
        activeTasks.removeValue(forKey: id)

        // Unpublish file progress when paused (will republish on resume)
        unpublishFileProgress(for: id)

        updateAggregateProgress()
        scheduleSave()

        Logger.info("Download paused: \(task.download.destinationFilename)", category: Logger.downloads)
    }

    /// Resumes a paused download.
    ///
    /// - Parameter id: The download ID to resume.
    func resume(_ id: UUID) async throws {
        guard let download = downloads.first(where: { $0.id == id }) else {
            throw DownloadError.downloadNotFound
        }

        // Check for yt-dlp download
        if download.downloadType == .ytdlp {
            if let ytdlpTask = ytdlpTasks[id] {
                ytdlpTask.resume()
                download.markDownloading()
                updateAggregateProgress()
                Logger.info("yt-dlp download resumed: \(download.destinationFilename)", category: Logger.downloads)
            }
            return
        }

        guard download.canResume, let resumeData = download.resumeData else {
            throw DownloadError.cannotResume
        }

        let task = DownloadTask(download: download)
        setupTaskCallbacks(task)
        activeTasks[download.id] = task

        // Fetch cookies from WebKit
        let cookies = await fetchCookies(for: download.sourceURL, dataStore: dataStore)

        // Resume with URLSession
        try await task.resume(with: resumeData, cookies: cookies)

        updateAggregateProgress()

        Logger.info("Download resumed: \(download.destinationFilename)", category: Logger.downloads)
    }

    /// Cancels a download permanently.
    ///
    /// - Parameter id: The download ID to cancel.
    func cancel(_ id: UUID) {
        unpublishFileProgress(for: id)
        photosImportPending.removeValue(forKey: id)

        // Check for yt-dlp download first
        if let ytdlpTask = ytdlpTasks.removeValue(forKey: id) {
            ytdlpTask.cancel()
            ytdlpTask.cleanup()
            if let download = downloads.first(where: { $0.id == id }) {
                download.markFailed(
                    error: DownloadError.cancelled,
                    resumeData: nil,
                )
            }
            updateAggregateProgress()
            scheduleSave()
            Logger.info("yt-dlp download cancelled", category: Logger.downloads)
            return
        }

        if let task = activeTasks.removeValue(forKey: id) {
            task.cancel()
            task.download.markFailed(
                error: DownloadError.cancelled,
                resumeData: nil,
            )
            updateAggregateProgress()
            scheduleSave()

            Logger.info("Download cancelled: \(task.download.destinationFilename)", category: Logger.downloads)
        }
    }

    /// Retries a failed download.
    ///
    /// - Parameter id: The download ID to retry.
    func retry(_ id: UUID) async throws {
        guard let download = downloads.first(where: { $0.id == id }) else {
            throw DownloadError.downloadNotFound
        }

        guard download.canRetry else {
            throw DownloadError.cannotRetry
        }

        // Handle yt-dlp downloads - always start fresh (yt-dlp handles resume internally)
        if download.downloadType == .ytdlp {
            guard let mode = download.ytdlpMode else {
                throw DownloadError.cannotRetry
            }

            // Create new yt-dlp task
            let ytdlpMode: YTDLPService.DownloadMode = switch mode {
            case .video: .video
            case .videoOnly: .videoOnly
            case .audioOnly: .audioOnly
            case .saveToPhotos: .saveToPhotos
            }

            let task = try await YTDLPService.shared.createDownloadTask(
                url: download.sourceURL,
                mode: ytdlpMode,
                destination: download.destinationDirectory,
                dataStore: dataStore,
                useCookies: true,
            )

            // Wire up callbacks
            task.onProgress = { [weak self, weak download] progress in
                guard let self, let download else { return }
                download.updateLiveProgress(
                    bytesReceived: progress.bytesDownloaded,
                    totalBytes: progress.totalBytes,
                    bytesPerSecond: progress.bytesPerSecond,
                )
                updateAggregateProgress()
            }

            task.onTitleDetected = { [weak download] title in
                download?.ytdlpTitle = title
            }

            task.onComplete = { [weak self, weak download] outputPath in
                guard let self, let download else { return }
                download.destinationFilename = outputPath.lastPathComponent
                download.markCompleted()
                ytdlpTasks.removeValue(forKey: download.id)
                updateAggregateProgress()
                scheduleSave()

                if mode == .saveToPhotos {
                    Task {
                        await self.importToPhotos(fileURL: outputPath, download: download)
                    }
                }
            }

            task.onFailed = { [weak self, weak download] error in
                guard let self, let download else { return }
                download.markFailed(error: error, resumeData: nil)
                ytdlpTasks.removeValue(forKey: download.id)
                updateAggregateProgress()
                scheduleSave()
            }

            ytdlpTasks[download.id] = task
            download.markDownloading()
            task.start()
            updateAggregateProgress()

            Logger.info("yt-dlp download retried: \(download.destinationFilename)", category: Logger.downloads)
            return
        }

        // If we have resume data, use it
        if download.resumeData != nil {
            try await resume(id)
        } else {
            // Start fresh
            let task = DownloadTask(download: download)
            setupTaskCallbacks(task)
            activeTasks[download.id] = task

            // Fetch cookies from WebKit
            let cookies = await fetchCookies(for: download.sourceURL, dataStore: dataStore)

            // Start fresh download
            try await task.start(cookies: cookies)

            updateAggregateProgress()
        }

        Logger.info("Download retried: \(download.destinationFilename)", category: Logger.downloads)
    }

    /// Removes a download from history.
    ///
    /// Active downloads are cancelled first.
    ///
    /// - Parameter id: The download ID to remove.
    func remove(_ id: UUID) {
        // Cancel if active (handles both regular and yt-dlp downloads)
        if activeTasks[id] != nil || ytdlpTasks[id] != nil {
            cancel(id)
        }

        // Remove from list and persistence
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            let download = downloads.remove(at: index)
            modelContext.delete(download)
            scheduleSave()

            Logger.info("Download removed: \(download.destinationFilename)", category: Logger.downloads)
        }
    }

    /// Clears completed and failed downloads from history.
    func clearInactive() {
        let inactive = downloads.filter { !$0.state.isActive }

        for download in inactive {
            modelContext.delete(download)
        }

        downloads.removeAll { !$0.state.isActive }
        scheduleSave()

        Logger.info("Cleared \(inactive.count) inactive downloads", category: Logger.downloads)
    }

    /// Opens the downloaded file in Finder.
    func revealInFinder(_ id: UUID) {
        guard let download = downloads.first(where: { $0.id == id }),
              download.state == .completed else {
            return
        }

        NSWorkspace.shared.selectFile(
            download.finalFileURL.path,
            inFileViewerRootedAtPath: download.destinationDirectory.path,
        )
    }

    /// Opens the downloaded file with the default application.
    func openFile(_ id: UUID) {
        guard let download = downloads.first(where: { $0.id == id }),
              download.state == .completed else {
            return
        }

        NSWorkspace.shared.open(download.finalFileURL)
    }

    /// Opens the Downloads folder in Finder.
    func openDownloadsFolder() {
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: downloadDirectory.path)
    }

    // MARK: - BitTorrent Downloads

    /// Starts a download from a magnet link.
    ///
    /// - Parameters:
    ///   - magnetURL: The magnet: URL.
    ///   - customDownloadPath: Optional custom download path.
    ///   - spaceID: Optional space ID.
    ///   - spaceName: Optional space name.
    /// - Returns: The created Download model.
    @discardableResult
    func startMagnetDownload(
        magnetURL: URL,
        customDownloadPath: String? = nil,
        spaceID: UUID? = nil,
        spaceName: String? = nil,
    ) async throws -> Download {
        let magnetString = magnetURL.absoluteString
        let displayName = extractMagnetDisplayName(from: magnetString)
            ?? "magnet-\(UUID().uuidString.prefix(8))"

        let download = createBitTorrentDownload(
            sourceURL: magnetURL,
            displayName: displayName,
            downloadType: .magnet,
            customDownloadPath: customDownloadPath,
            spaceID: spaceID,
            spaceName: spaceName,
        )

        let gid = try await Aria2DownloadCoordinator.shared.addMagnetDownload(
            magnetURI: magnetString,
            destinationDirectory: download.destinationDirectory,
        )

        finalizeBitTorrentDownload(download, gid: gid)
        Logger.info("Magnet download started: \(displayName)", category: Logger.downloads)
        return download
    }

    /// Starts a download from a .torrent file.
    ///
    /// - Parameters:
    ///   - torrentFile: URL to the .torrent file.
    ///   - customDownloadPath: Optional custom download path.
    ///   - spaceID: Optional space ID.
    ///   - spaceName: Optional space name.
    /// - Returns: The created Download model.
    @discardableResult
    func startTorrentDownload(
        torrentFile: URL,
        customDownloadPath: String? = nil,
        spaceID: UUID? = nil,
        spaceName: String? = nil,
    ) async throws -> Download {
        let displayName = torrentFile.deletingPathExtension().lastPathComponent

        let download = createBitTorrentDownload(
            sourceURL: torrentFile,
            displayName: displayName,
            downloadType: .torrent,
            customDownloadPath: customDownloadPath,
            spaceID: spaceID,
            spaceName: spaceName,
        )

        let gid = try await Aria2DownloadCoordinator.shared.addTorrentDownload(
            torrentFile: torrentFile,
            destinationDirectory: download.destinationDirectory,
        )

        finalizeBitTorrentDownload(download, gid: gid)
        Logger.info("Torrent download started: \(displayName)", category: Logger.downloads)
        return download
    }

    /// Creates and persists a BitTorrent download model.
    private func createBitTorrentDownload(
        sourceURL: URL,
        displayName: String,
        downloadType: DownloadType,
        customDownloadPath: String?,
        spaceID: UUID?,
        spaceName: String?,
    ) -> Download {
        let destinationDir = downloadDirectory(for: customDownloadPath)

        let download = Download(
            sourceURL: sourceURL,
            suggestedFilename: displayName,
            destinationDirectory: destinationDir,
            spaceID: spaceID,
            spaceName: spaceName,
            downloadType: downloadType,
        )

        modelContext.insert(download)
        downloads.insert(download, at: 0)
        scheduleSave()
        syncAria2Settings()

        return download
    }

    /// Finalizes a BitTorrent download after aria2 accepts it.
    private func finalizeBitTorrentDownload(_ download: Download, gid: String) {
        download.aria2GID = gid
        download.markDownloading()
        scheduleSave()

        startAria2Polling(for: download, gid: gid)
        updateAggregateProgress()
        onDownloadStarted?(download)
    }

    // MARK: - yt-dlp Downloads

    /// Active yt-dlp download tasks by download ID.
    private var ytdlpTasks: [UUID: YTDLPDownloadTask] = [:]

    /// Starts a download using yt-dlp for video/audio extraction.
    ///
    /// - Parameters:
    ///   - url: The video page URL (YouTube, Vimeo, etc.).
    ///   - mode: The download mode (video, audio, etc.).
    ///   - customDownloadPath: Optional custom download path.
    ///   - spaceID: Optional space ID.
    ///   - spaceName: Optional space name.
    ///   - colorTag: Optional Finder color tag.
    /// - Returns: The created Download model.
    @discardableResult
    func startYTDLPDownload(
        url: URL,
        mode: YTDLPDownloadMode,
        useCookies: Bool = true,
        deleteAfterPhotosImport: Bool = false,
        customDownloadPath: String? = nil,
        spaceID: UUID? = nil,
        spaceName: String? = nil,
        colorTag: Int? = nil,
    ) async throws -> Download {
        // Determine filename based on mode
        let suggestedFilename = switch mode {
        case .video, .videoOnly, .saveToPhotos:
            "video-\(UUID().uuidString.prefix(8)).mp4"
        case .audioOnly:
            "audio-\(UUID().uuidString.prefix(8)).mp3"
        }

        let destinationDir = downloadDirectory(for: customDownloadPath)

        // Create download model
        let download = Download(
            sourceURL: url,
            suggestedFilename: suggestedFilename,
            destinationDirectory: destinationDir,
            spaceID: spaceID,
            spaceName: spaceName,
            colorTag: colorTag,
            downloadType: .ytdlp,
            ytdlpMode: mode,
        )

        modelContext.insert(download)
        downloads.insert(download, at: 0)
        scheduleSave()

        // Create yt-dlp task
        let ytdlpMode: YTDLPService.DownloadMode = switch mode {
        case .video: .video
        case .videoOnly: .videoOnly
        case .audioOnly: .audioOnly
        case .saveToPhotos: .saveToPhotos
        }

        let task = try await YTDLPService.shared.createDownloadTask(
            url: url,
            mode: ytdlpMode,
            destination: destinationDir,
            dataStore: dataStore,
            useCookies: useCookies,
        )

        ytdlpTasks[download.id] = task

        // Set up callbacks
        task.onTitleDetected = { [weak self, weak download] title in
            guard let download else { return }
            download.ytdlpTitle = title

            // Update filename with actual title
            let ext = mode == .audioOnly ? "mp3" : "mp4"
            download.suggestedFilename = "\(title).\(ext)"
            download.destinationFilename = "\(title).\(ext)"

            self?.scheduleSave()
        }

        task.onProgress = { [weak self, weak download] progress in
            guard let download else { return }

            download.updateLiveProgress(
                bytesReceived: progress.bytesDownloaded,
                totalBytes: progress.totalBytes,
                bytesPerSecond: progress.bytesPerSecond,
            )

            self?.updateAggregateProgress()
            self?.onProgressChanged?()
        }

        task.onComplete = { [weak self, weak download] fileURL in
            guard let self, let download else { return }

            download.destinationFilename = fileURL.lastPathComponent
            download.markCompleted()
            scheduleSave()
            ytdlpTasks.removeValue(forKey: download.id)
            updateAggregateProgress()
            onDownloadCompleted?(download)

            // Handle Save to Photos mode
            if mode == .saveToPhotos {
                Task {
                    await self.importToPhotos(fileURL: fileURL, download: download, deleteAfterImport: deleteAfterPhotosImport)
                }
            }

            Logger.info("yt-dlp download completed: \(fileURL.lastPathComponent)", category: Logger.downloads)
        }

        task.onFailed = { [weak self, weak download] error in
            guard let self, let download else { return }

            download.errorMessage = error.localizedDescription
            download.state = .failed
            scheduleSave()
            ytdlpTasks.removeValue(forKey: download.id)
            updateAggregateProgress()
            onDownloadFailed?(download, error)

            Logger.warning("yt-dlp download failed: \(error.localizedDescription)", category: Logger.downloads)
        }

        // Start the download
        download.markDownloading()
        task.start()

        updateAggregateProgress()
        onDownloadStarted?(download)

        Logger.info("yt-dlp download started: \(url.absoluteString)", category: Logger.downloads)
        return download
    }

    /// Imports a downloaded file to the Photos library.
    ///
    /// Detects whether the file is an image or video based on extension and uses
    /// the appropriate PHAssetCreationRequest API.
    ///
    /// - Parameters:
    ///   - fileURL: Path to the media file.
    ///   - download: The download model (for logging context).
    ///   - deleteAfterImport: Whether to delete the file after successful import.
    private func importToPhotos(fileURL: URL, download: Download, deleteAfterImport: Bool = false) async {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)

        switch status {
        case .notDetermined:
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            guard newStatus == .authorized || newStatus == .limited else {
                Logger.warning("Photos access denied", category: Logger.downloads)
                return
            }

        case .restricted, .denied:
            Logger.warning("Photos access not authorized", category: Logger.downloads)
            return

        case .authorized, .limited:
            break

        @unknown default:
            break
        }

        let ext = fileURL.pathExtension.lowercased()
        let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic", "heif", "gif", "webp", "tiff", "tif", "bmp", "avif"]
        let isImage = imageExtensions.contains(ext)

        do {
            try await PHPhotoLibrary.shared().performChanges { @Sendable in
                if isImage {
                    let request = PHAssetCreationRequest.forAsset()
                    request.addResource(with: .photo, fileURL: fileURL, options: nil)
                } else {
                    PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
                }
            }

            Logger.info("Media imported to Photos: \(download.destinationFilename)", category: Logger.downloads)

            if deleteAfterImport {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    Logger.info("Deleted file after Photos import: \(download.destinationFilename)", category: Logger.downloads)
                } catch {
                    Logger.warning("Failed to delete file after Photos import: \(error)", category: Logger.downloads)
                }
            }
        } catch {
            Logger.error("Failed to import to Photos: \(error)", category: Logger.downloads)
        }
    }

    /// Pauses a yt-dlp download.
    func pauseYTDLPDownload(_ downloadID: UUID) {
        guard let task = ytdlpTasks[downloadID] else { return }
        task.pause()

        if let download = downloads.first(where: { $0.id == downloadID }) {
            download.state = .paused
            scheduleSave()
        }
    }

    /// Resumes a yt-dlp download.
    func resumeYTDLPDownload(_ downloadID: UUID) {
        guard let task = ytdlpTasks[downloadID] else { return }
        task.resume()

        if let download = downloads.first(where: { $0.id == downloadID }) {
            download.markDownloading()
            scheduleSave()
        }
    }

    /// Cancels a yt-dlp download.
    func cancelYTDLPDownload(_ downloadID: UUID) {
        guard let task = ytdlpTasks.removeValue(forKey: downloadID) else { return }
        task.cancel()
        task.cleanup()

        if let download = downloads.first(where: { $0.id == downloadID }) {
            download.state = .failed
            download.errorMessage = "Cancelled"
            scheduleSave()
        }
    }

    /// Extracts a display name from a magnet URI.
    private func extractMagnetDisplayName(from magnetURI: String) -> String? {
        guard let range = magnetURI.range(of: "dn=") else { return nil }
        let remaining = magnetURI[range.upperBound...]
        let endIndex = remaining.firstIndex(of: "&") ?? remaining.endIndex
        return String(remaining[..<endIndex]).removingPercentEncoding
    }

    /// Syncs aria2 settings from the coordinator.
    private func syncAria2Settings() {
        Aria2DownloadCoordinator.shared.isAria2Enabled = useAria2ForLargeFiles
        Aria2DownloadCoordinator.shared.isBitTorrentEnabled = enableBitTorrent
        Aria2DownloadCoordinator.shared.largeFileThreshold = aria2Threshold
        Aria2DownloadCoordinator.shared.downloadDirectory = downloadDirectory.path
    }

    /// Applies aria2 settings from BrowserSettings.
    ///
    /// Call this on startup or when settings change.
    func applySettings(from settings: BrowserSettings) {
        useAria2ForLargeFiles = settings.useAria2ForLargeFiles
        aria2Threshold = Int64(settings.aria2ThresholdMB) * 1_024 * 1_024
        enableBitTorrent = settings.enableBitTorrent
        syncAria2Settings()
    }

    /// Starts polling aria2 for download progress.
    private func startAria2Polling(for download: Download, gid: String) {
        Task {
            await pollAria2Progress(for: download, gid: gid)
        }
    }

    /// Polls aria2 for download progress.
    private func pollAria2Progress(for download: Download, gid: String) async {
        guard let rpc = await Aria2DownloadCoordinator.shared.getRPCClient() else {
            return
        }

        while !Task.isCancelled {
            do {
                let status = try await rpc.tellStatus(gid: gid)

                download.updateLiveProgress(
                    bytesReceived: status.completedLength,
                    totalBytes: status.totalLength > 0 ? status.totalLength : nil,
                    bytesPerSecond: Double(status.downloadSpeed),
                )

                // Update BitTorrent-specific info
                if download.downloadType.isBitTorrent {
                    if let btStatus = try? await rpc.getBtStatus(gid: gid) {
                        download.updateBitTorrentInfo(peers: btStatus.numPeers, name: btStatus.name)
                    }
                }

                updateAggregateProgress()
                onProgressChanged?()

                switch status.status {
                case .complete:
                    download.markCompleted()
                    scheduleSave()
                    onDownloadCompleted?(download)
                    Logger.info("aria2 download completed: \(download.destinationFilename)", category: Logger.downloads)
                    return

                case .error:
                    let error = Aria2RPC.Error.rpcError(
                        code: status.errorCode ?? -1,
                        message: status.errorMessage ?? "Unknown error",
                    )
                    download.markFailed(error: error, resumeData: nil)
                    scheduleSave()
                    onDownloadFailed?(download, error)
                    return

                case .removed:
                    download.markFailed(error: DownloadError.cancelled, resumeData: nil)
                    scheduleSave()
                    return

                case .paused:
                    download.state = .paused
                    scheduleSave()
                    return

                case .active, .waiting:
                    break
                }

                try await Task.sleep(for: .seconds(1))

            } catch {
                if !Task.isCancelled {
                    download.markFailed(error: error, resumeData: nil)
                    scheduleSave()
                    onDownloadFailed?(download, error)
                }
                return
            }
        }
    }

    /// Adds a completed download to the history without starting a new download.
    ///
    /// Use this for externally completed downloads that should appear in download
    /// history but weren't managed by DownloadManager's task system.
    ///
    /// - Parameter download: The completed download to add to history.
    func addCompletedDownload(_ download: Download) {
        modelContext.insert(download)
        downloads.insert(download, at: 0)
        scheduleSave()
        onDownloadCompleted?(download)

        Logger.info("Added completed download: \(download.destinationFilename)", category: Logger.downloads)
    }

    /// Saves data that WebKit already fetched as a completed download.
    ///
    /// Some WebKit callbacks deliver the file contents directly instead of
    /// creating a `WKDownload` — the PDF viewer HUD's download button arrives
    /// as `_webView:saveDataToFile:suggestedFilename:mimeType:originatingURL:`.
    /// The file lands in the resolved download folder with conflict-free
    /// naming and quarantine attributes, and appears in history as a
    /// completed download.
    ///
    /// - Parameters:
    ///   - data: The file contents.
    ///   - suggestedFilename: Filename hint from WebKit.
    ///   - mimeType: MIME type of the data.
    ///   - sourceURL: The URL the data was originally loaded from.
    ///   - originatingTitle: Title of the originating page.
    ///   - customDownloadPath: Optional custom download path (from space settings).
    ///   - spaceID: Optional ID of the space initiating the save.
    ///   - spaceName: Optional name of the space (cached for display after deletion).
    ///   - colorTag: Optional Finder color tag to apply (1-7).
    /// - Returns: The completed Download model.
    @discardableResult
    func saveCompletedData(
        _ data: Data,
        suggestedFilename: String,
        mimeType: String?,
        sourceURL: URL,
        originatingTitle: String? = nil,
        customDownloadPath: String? = nil,
        spaceID: UUID? = nil,
        spaceName: String? = nil,
        colorTag: Int? = nil,
    ) throws -> Download {
        var filename = FilenameUtilities.sanitize(suggestedFilename)
        filename = FilenameUtilities.ensureExtension(for: filename, mimeType: mimeType)

        let destinationDirectory = downloadDirectory(for: customDownloadPath)
        let fm = FileManager.default
        if !fm.fileExists(atPath: destinationDirectory.path) {
            try fm.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)
        }

        filename = try FilenameUtilities.uniqueFilename(for: filename, in: destinationDirectory)
        let fileURL = destinationDirectory.appendingPathComponent(filename)
        try data.write(to: fileURL)

        do {
            try fileURL.setQuarantineAttributes(downloadURL: sourceURL, originURL: sourceURL)
        } catch {
            Logger.warning(
                "Failed to set quarantine on \(filename): \(error)",
                category: Logger.downloads,
            )
        }

        let download = Download(
            sourceURL: sourceURL,
            suggestedFilename: filename,
            destinationDirectory: destinationDirectory,
            originatingPageURL: sourceURL,
            originatingPageTitle: originatingTitle,
            mimeType: mimeType,
            spaceID: spaceID,
            spaceName: spaceName,
            colorTag: colorTag,
        )
        download.updateLiveProgress(
            bytesReceived: Int64(data.count),
            totalBytes: Int64(data.count),
            bytesPerSecond: 0,
        )
        download.markCompleted()
        addCompletedDownload(download)
        applyColorTagIfNeeded(to: download)
        return download
    }

    // MARK: - Private Helpers

    private func setupTaskCallbacks(_ task: DownloadTask) {
        // Publish file progress when destination file is ready
        // This ensures the file exists and filename is resolved before publishing
        task.onDestinationReady = { [weak self] task, fileURL in
            guard let self else { return }
            publishFileProgress(for: task.download, fileURL: fileURL)
        }

        task.onProgress = { [weak self] task in
            guard let self else { return }
            updateFileProgress(for: task.download)
            updateAggregateProgress()
            onProgressChanged?()
        }

        task.onComplete = { [weak self] task in
            guard let self else { return }
            applyColorTagIfNeeded(to: task.download)
            unpublishFileProgress(for: task.id)
            activeTasks.removeValue(forKey: task.id)
            updateAggregateProgress()
            scheduleSave()
            onDownloadCompleted?(task.download)

            // Handle Save to Photos
            if let deleteAfterImport = photosImportPending.removeValue(forKey: task.id) {
                let fileURL = task.download.finalFileURL
                let download = task.download
                Task {
                    await self.importToPhotos(fileURL: fileURL, download: download, deleteAfterImport: deleteAfterImport)
                }
            }

            Logger.info("Download completed: \(task.download.destinationFilename)", category: Logger.downloads)
        }

        task.onFailed = { [weak self] task, error, _ in
            guard let self else { return }
            unpublishFileProgress(for: task.id)
            activeTasks.removeValue(forKey: task.id)
            updateAggregateProgress()
            scheduleSave()
            onDownloadFailed?(task.download, error)

            Logger.warning(
                "Download failed: \(task.download.destinationFilename) - \(error.localizedDescription)",
                category: Logger.downloads,
            )
        }
    }

    /// Fetches cookies from a WebKit data store for a URL.
    ///
    /// This ensures downloads can use the same authentication/session cookies
    /// as the browser's WebViews.
    private func fetchCookies(for url: URL, dataStore: WKWebsiteDataStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { cookies in
                // Filter cookies that apply to this URL's domain
                let applicableCookies = cookies.filter { cookie in
                    guard let urlHost = url.host?.lowercased() else { return false }
                    let cookieDomain = cookie.domain.lowercased()

                    // Cookie domain can be ".example.com" for all subdomains
                    // or "example.com" for exact match
                    if cookieDomain.hasPrefix(".") {
                        return urlHost.hasSuffix(cookieDomain) ||
                            urlHost == String(cookieDomain.dropFirst())
                    } else {
                        return urlHost == cookieDomain
                    }
                }

                continuation.resume(returning: applicableCookies)
            }
        }
    }

    private func updateAggregateProgress() {
        guard !activeTasks.isEmpty else {
            aggregateProgress = 0
            return
        }

        var totalBytes: Int64 = 0
        var receivedBytes: Int64 = 0
        var unknownCount = 0

        for task in activeTasks.values {
            let download = task.download
            receivedBytes += download.bytesReceived

            if let total = download.totalBytes {
                totalBytes += total
            } else {
                unknownCount += 1
            }
        }

        // Calculate aggregate progress for UI (e.g., downloads panel)
        if unknownCount > 0 || totalBytes == 0 {
            aggregateProgress = -1 // Indeterminate
        } else {
            aggregateProgress = Double(receivedBytes) / Double(totalBytes)
        }
    }

    // MARK: - File Progress Management

    /// Creates and publishes an NSProgress for a download file.
    ///
    /// This enables Finder to show progress bars on the file in the Downloads
    /// folder and Dock stack, with pause/cancel buttons.
    ///
    /// - Parameters:
    ///   - download: The download model.
    ///   - fileURL: The actual URL of the `.download` file (must exist on disk).
    private func publishFileProgress(for download: Download, fileURL: URL) {
        let downloadID = download.id

        // Don't publish if already published
        guard fileProgressObjects[downloadID] == nil else { return }

        // Use -1 for indeterminate if total unknown, otherwise Finder shows 0%
        let total = download.totalBytes ?? -1
        let progress = Progress(totalUnitCount: total)
        progress.kind = .file
        progress.fileOperationKind = .downloading
        progress.fileURL = fileURL
        progress.isCancellable = true
        progress.isPausable = true

        // Set file-specific metadata for Finder
        progress.setUserInfoObject(1 as NSNumber, forKey: .fileTotalCountKey)
        progress.setUserInfoObject(0 as NSNumber, forKey: .fileCompletedCountKey)

        // Set current progress if we already have data
        if download.bytesReceived > 0 {
            progress.completedUnitCount = download.bytesReceived
        }

        // Set up cancellation handler
        progress.cancellationHandler = { [weak self] in
            DispatchQueue.main.async { self?.cancel(downloadID) }
        }

        // Set up pause handler
        progress.pausingHandler = { [weak self] in
            Task { @MainActor in
                await self?.pause(downloadID)
            }
        }

        // Set up resume handler
        progress.resumingHandler = { [weak self] in
            Task { @MainActor in
                try? await self?.resume(downloadID)
            }
        }

        progress.publish()
        fileProgressObjects[downloadID] = progress

        Logger.info("Published file progress for \(fileURL.lastPathComponent)", category: Logger.downloads)
    }

    /// Updates the published file progress for a download.
    private func updateFileProgress(for download: Download) {
        guard let progress = fileProgressObjects[download.id] else { return }

        if let total = download.totalBytes {
            progress.totalUnitCount = total
        }
        progress.completedUnitCount = download.bytesReceived

        // Update file URL if it changed (e.g., user renamed file)
        if progress.fileURL != download.currentFileURL {
            progress.fileURL = download.currentFileURL
        }
    }

    /// Unpublishes and removes the file progress for a download.
    private func unpublishFileProgress(for downloadID: UUID) {
        if let progress = fileProgressObjects.removeValue(forKey: downloadID) {
            progress.unpublish()
        }
    }

    // MARK: - Finder Color Tags

    /// Applies the download's color tag to the completed file, if specified.
    private func applyColorTagIfNeeded(to download: Download) {
        guard let tagValue = download.colorTag, tagValue > 0 else { return }

        let fileURL = download.finalFileURL
        fileURL.applyFinderColorTag(rawValue: tagValue)

        Logger.info(
            "Applied Finder color tag \(tagValue) to \(download.destinationFilename)",
            category: Logger.downloads,
        )
    }

    // MARK: - Persistence

    private func loadDownloads() {
        do {
            let descriptor = FetchDescriptor<Download>(
                sortBy: [SortDescriptor(\.createdAt, order: .reverse)],
            )
            downloads = try modelContext.fetch(descriptor)

            Logger.info("Loaded \(downloads.count) downloads from persistence", category: Logger.downloads)
        } catch {
            Logger.error("Failed to load downloads: \(error)", category: Logger.downloads)
            downloads = []
        }
    }

    private func scheduleSave() {
        saver.scheduleSave()
    }
}

// MARK: - Download Errors

/// Errors that can occur during download operations.
enum DownloadError: LocalizedError {
    case downloadNotFound
    case cannotResume
    case cannotRetry
    case cancelled
    case fileOperationFailed(any Error)
    case networkError(any Error)

    var errorDescription: String? {
        switch self {
        case .downloadNotFound:
            "Download not found"
        case .cannotResume:
            "Download cannot be resumed"
        case .cannotRetry:
            "Download cannot be retried"
        case .cancelled:
            "Download was cancelled"
        case let .fileOperationFailed(error):
            "File operation failed: \(error.localizedDescription)"
        case let .networkError(error):
            "Network error: \(error.localizedDescription)"
        }
    }
}
