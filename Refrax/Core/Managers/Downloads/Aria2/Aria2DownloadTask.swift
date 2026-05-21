import Foundation

/// A download task backed by aria2 for high-performance multi-connection downloads.
///
/// Use for large files where aria2's capabilities provide benefits:
/// - Multi-connection downloads (faster than single connection)
/// - Automatic resume on network failure
/// - Chunk-level integrity with metalinks
///
/// ## When to Use aria2 vs URLSession
///
/// | Scenario | Recommendation |
/// |----------|---------------|
/// | Large files (>50MB) | aria2 |
/// | Slow/unreliable connections | aria2 |
/// | Small files (<10MB) | URLSession |
/// | Authentication required | URLSession |
/// | WebSocket/streaming | URLSession |
///
/// ## Usage
///
/// ```swift
/// let task = Aria2DownloadTask(
///     url: downloadURL,
///     destination: destinationURL,
///     rpc: aria2RPC
/// )
///
/// task.onProgress = { progress in
///     print("Progress: \(progress.fractionCompleted)")
/// }
///
/// try await task.start()
/// ```
final class Aria2DownloadTask: Identifiable {
    // MARK: - Types

    enum State: Sendable, Equatable {
        case pending
        case downloading
        case paused
        case completed
        case failed(any Error)

        var isActive: Bool {
            switch self {
            case .pending, .downloading:
                true
            case .paused, .completed, .failed:
                false
            }
        }

        // Custom Equatable since Error doesn't conform
        static func == (lhs: State, rhs: State) -> Bool {
            switch (lhs, rhs) {
            case (.pending, .pending),
                 (.downloading, .downloading),
                 (.paused, .paused),
                 (.completed, .completed):
                true
            case (.failed, .failed):
                true // Consider all failed states equal for comparison
            default:
                false
            }
        }
    }

    struct Progress: Sendable {
        let totalBytes: Int64
        let completedBytes: Int64
        let downloadSpeed: Int64
        let connections: Int

        var fractionCompleted: Double {
            guard totalBytes > 0 else { return 0 }
            return Double(completedBytes) / Double(totalBytes)
        }

        var estimatedTimeRemaining: TimeInterval? {
            guard downloadSpeed > 0 else { return nil }
            let remaining = totalBytes - completedBytes
            return Double(remaining) / Double(downloadSpeed)
        }
    }

    // MARK: - Properties

    let id: UUID
    let sourceURL: URL
    let destinationURL: URL
    private(set) var state: State = .pending
    private(set) var gid: String?
    private(set) var progress: Progress?

    /// Callback for progress updates.
    var onProgress: ((Progress) -> Void)?

    /// Callback on completion.
    var onComplete: ((URL) -> Void)?

    /// Callback on failure.
    var onFailed: ((any Error) -> Void)?

    private let rpc: Aria2RPC
    private let cookies: String?
    private let headers: [String: String]
    private var pollingTask: Task<Void, Never>?

    // MARK: - Initialization

    /// Creates an aria2 download task.
    ///
    /// - Parameters:
    ///   - url: The URL to download.
    ///   - destination: Where to save the file.
    ///   - rpc: The aria2 RPC client.
    ///   - cookies: Cookies string (name=value; name2=value2).
    ///   - headers: Additional HTTP headers.
    init(
        url: URL,
        destination: URL,
        rpc: Aria2RPC,
        cookies: String? = nil,
        headers: [String: String] = [:],
    ) {
        self.id = UUID()
        self.sourceURL = url
        self.destinationURL = destination
        self.rpc = rpc
        self.cookies = cookies
        self.headers = headers
    }

    deinit {
        pollingTask?.cancel()
    }

    // MARK: - Control

    /// Starts the download.
    func start() async throws {
        guard state == .pending else { return }

        state = .downloading

        // Build options
        var options = Aria2RPC.DownloadOptions()
        _ = options.setDirectory(destinationURL.deletingLastPathComponent().path)
        _ = options.setFilename(destinationURL.lastPathComponent)
        _ = options.setConnections(16)
        _ = options.enableResume()
        _ = options.setReferer(sourceURL.absoluteString)

        if let cookies {
            _ = options.setCookies(cookies)
        }

        // Add custom headers
        if !headers.isEmpty {
            _ = options.setHeaders(headers)
        }

        // Add to aria2
        let gid = try await rpc.addUri([sourceURL.absoluteString], options: options.build())
        self.gid = gid

        // Start polling for progress
        startPolling()
    }

    /// Pauses the download.
    func pause() async throws {
        guard let gid, state == .downloading else { return }

        try await rpc.pause(gid: gid)
        state = .paused
        stopPolling()
    }

    /// Resumes a paused download.
    func resume() async throws {
        guard let gid, state == .paused else { return }

        try await rpc.unpause(gid: gid)
        state = .downloading
        startPolling()
    }

    /// Cancels the download.
    func cancel() async {
        stopPolling()

        if let gid {
            _ = try? await rpc.forceRemove(gid: gid)
        }

        state = .failed(CancellationError())
    }

    // MARK: - Polling

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            await self?.pollProgress()
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func pollProgress() async {
        guard let gid else { return }

        while !Task.isCancelled {
            do {
                let status = try await rpc.tellStatus(gid: gid)

                let progress = Progress(
                    totalBytes: status.totalLength,
                    completedBytes: status.completedLength,
                    downloadSpeed: status.downloadSpeed,
                    connections: status.connections,
                )
                self.progress = progress
                onProgress?(progress)

                switch status.status {
                case .complete:
                    await handleCompletion()
                    return

                case .error:
                    let error = Aria2RPC.Error.rpcError(
                        code: status.errorCode ?? -1,
                        message: status.errorMessage ?? "Unknown error",
                    )
                    await handleFailure(error)
                    return

                case .removed:
                    await handleFailure(CancellationError())
                    return

                case .paused:
                    state = .paused
                    return

                case .active, .waiting:
                    break
                }

                // Poll every second
                try await Task.sleep(for: .seconds(1))

            } catch {
                if !Task.isCancelled {
                    await handleFailure(error)
                }
                return
            }
        }
    }

    private func handleCompletion() async {
        state = .completed
        stopPolling()

        // Set quarantine attributes
        do {
            try QuarantineManager.setQuarantine(
                onFileAt: destinationURL,
                downloadedFrom: sourceURL,
                originPage: nil,
            )
        } catch {
            Logger.warning("Failed to set quarantine: \(error)", category: Logger.downloads)
        }

        onComplete?(destinationURL)
    }

    private func handleFailure(_ error: any Error) async {
        state = .failed(error)
        stopPolling()
        onFailed?(error)
    }
}

// MARK: - Aria2 Download Coordinator

/// Coordinates downloads between URLSession and aria2 based on file size and preferences.
final class Aria2DownloadCoordinator {
    // MARK: - Configuration

    /// Threshold in bytes above which aria2 is used.
    var largeFileThreshold: Int64 = 50 * 1_024 * 1_024 // 50 MB

    /// Whether aria2 is enabled.
    var isAria2Enabled: Bool = false

    /// Whether BitTorrent support is enabled.
    var isBitTorrentEnabled: Bool = false

    /// Download directory for aria2.
    var downloadDirectory: String?

    /// The aria2 daemon.
    private var daemon: Aria2Daemon?

    /// Active aria2 tasks.
    private var aria2Tasks: [UUID: Aria2DownloadTask] = [:]

    /// Session file path for resuming downloads.
    private var sessionFilePath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let aria2Dir = appSupport.appendingPathComponent("Refrax/aria2", isDirectory: true)
        try? FileManager.default.createDirectory(at: aria2Dir, withIntermediateDirectories: true)
        return aria2Dir.appendingPathComponent("session.txt").path
    }

    // MARK: - Singleton

    static let shared = Aria2DownloadCoordinator()

    private init() {}

    // MARK: - Daemon Management

    /// Starts the aria2 daemon if not already running.
    func ensureDaemonRunning() async throws {
        if let daemon, await daemon.isRunning {
            return
        }

        var config = Aria2Daemon.Configuration()
        config.enableBitTorrent = isBitTorrentEnabled
        config.downloadDirectory = downloadDirectory
        config.sessionFile = sessionFilePath

        let newDaemon = Aria2Daemon()
        try await newDaemon.start(configuration: config)
        daemon = newDaemon
    }

    /// Returns the running daemon, throwing if not available.
    private func runningDaemon() async throws -> Aria2Daemon {
        try await ensureDaemonRunning()
        guard let daemon, await daemon.isRunning else {
            throw Aria2Daemon.Error.notRunning
        }
        return daemon
    }

    /// Stops the aria2 daemon gracefully.
    func stopDaemon() async {
        await daemon?.stop()
        daemon = nil
    }

    /// Restarts the daemon with updated configuration.
    ///
    /// Call this when settings change (e.g., BitTorrent enabled/disabled).
    func restartDaemonIfNeeded() async throws {
        guard daemon != nil else { return }

        await stopDaemon()
        try await ensureDaemonRunning()
    }

    // MARK: - Download Decision

    /// Determines whether to use aria2 for a download.
    ///
    /// - Parameters:
    ///   - contentLength: Expected file size, if known.
    ///   - mimeType: MIME type of the content.
    /// - Returns: Whether aria2 should be used.
    func shouldUseAria2(contentLength: Int64?, mimeType: String?) -> Bool {
        guard isAria2Enabled else { return false }

        // Use aria2 for large files
        if let length = contentLength, length >= largeFileThreshold {
            return true
        }

        // Certain file types are typically large
        let largeMimeTypes = [
            "application/zip",
            "application/x-gzip",
            "application/x-tar",
            "application/x-7z-compressed",
            "application/x-rar-compressed",
            "application/x-apple-diskimage",
            "video/",
            "application/octet-stream",
        ]

        if let mime = mimeType?.lowercased() {
            for prefix in largeMimeTypes {
                if mime.hasPrefix(prefix) {
                    return true
                }
            }
        }

        return false
    }

    /// Creates an aria2 download task.
    func createAria2Task(
        url: URL,
        destination: URL,
        cookies: String? = nil,
        headers: [String: String] = [:],
    ) async throws -> Aria2DownloadTask {
        let daemon = try await runningDaemon()
        let rpc = await daemon.createRPCClient()

        let task = Aria2DownloadTask(
            url: url,
            destination: destination,
            rpc: rpc,
            cookies: cookies,
            headers: headers,
        )

        aria2Tasks[task.id] = task
        return task
    }

    /// Creates an aria2 task for a magnet link.
    ///
    /// - Parameters:
    ///   - magnetURI: The magnet: URI to download.
    ///   - destinationDirectory: Directory to save the downloaded files.
    /// - Returns: GID of the created download.
    func addMagnetDownload(
        magnetURI: String,
        destinationDirectory: URL,
    ) async throws -> String {
        let rpc = try await bitTorrentRPCClient()
        let options: [String: Any] = ["dir": destinationDirectory.path]
        return try await rpc.addMagnet(magnetURI, options: options)
    }

    /// Creates an aria2 task for a .torrent file.
    ///
    /// - Parameters:
    ///   - torrentFile: URL to the .torrent file.
    ///   - destinationDirectory: Directory to save the downloaded files.
    /// - Returns: GID of the created download.
    func addTorrentDownload(
        torrentFile: URL,
        destinationDirectory: URL,
    ) async throws -> String {
        let rpc = try await bitTorrentRPCClient()

        // Read and base64 encode the torrent file off the main thread
        let base64Data = try await Task.detached {
            let torrentData = try Data(contentsOf: torrentFile)
            return torrentData.base64EncodedString()
        }.value

        let options: [String: Any] = ["dir": destinationDirectory.path]
        return try await rpc.addTorrent(base64Data, options: options)
    }

    /// Returns an RPC client for BitTorrent operations, ensuring BitTorrent is enabled.
    private func bitTorrentRPCClient() async throws -> Aria2RPC {
        guard isBitTorrentEnabled else {
            throw Aria2Daemon.Error.startupFailed("BitTorrent is not enabled")
        }
        let daemon = try await runningDaemon()
        return await daemon.createRPCClient()
    }

    /// Gets the RPC client for direct status queries.
    ///
    /// Returns `nil` if the daemon is not running.
    func getRPCClient() async -> Aria2RPC? {
        guard let daemon, await daemon.isRunning else { return nil }
        return await daemon.createRPCClient()
    }

    /// Removes a completed task.
    func removeTask(_ id: UUID) {
        aria2Tasks.removeValue(forKey: id)
    }
}
