import Foundation

/// A download task backed by yt-dlp for video/audio extraction.
///
/// Manages the yt-dlp process lifecycle including:
/// - Progress parsing from stdout
/// - Pause via SIGTERM with resume capability (--continue)
/// - Error handling and cleanup
///
/// ## Progress Tracking
///
/// Progress is parsed from yt-dlp's output using a custom template:
/// ```
/// download:50.0%|100.0M/200.0M|5.0M/s|00:20
/// ```
///
/// ## Pause/Resume
///
/// yt-dlp supports resumable downloads via partial files. When paused:
/// 1. Process is terminated (SIGTERM)
/// 2. Partial file is preserved
/// 3. On resume, `--continue` flag picks up where it left off
final class YTDLPDownloadTask: Identifiable {
    // MARK: - Types

    /// Current state of the download.
    enum State: Equatable {
        case pending
        case downloading
        case paused
        case completed
        case failed(String) // Error description

        var isActive: Bool {
            switch self {
            case .pending, .downloading:
                true
            case .paused, .completed, .failed:
                false
            }
        }
    }

    /// Progress information from yt-dlp output.
    struct Progress {
        /// Percentage complete (0-100).
        let percentComplete: Double

        /// Bytes downloaded so far.
        let bytesDownloaded: Int64

        /// Total bytes expected (may be nil).
        let totalBytes: Int64?

        /// Current download speed in bytes per second.
        let bytesPerSecond: Double

        /// Estimated time remaining in seconds.
        let estimatedTimeRemaining: TimeInterval?

        /// The filename being downloaded.
        let filename: String?

        /// Progress as a fraction (0.0-1.0).
        var fractionComplete: Double {
            percentComplete / 100.0
        }
    }

    // MARK: - Properties

    let id: UUID
    let url: URL
    let mode: YTDLPService.DownloadMode
    private let binaryPath: String
    private let destinationDirectory: URL
    let cookieFile: URL?

    private(set) var state: State = .pending
    private(set) var progress: Progress?
    private(set) var outputFilePath: URL?
    private(set) var detectedTitle: String?

    /// The yt-dlp process.
    private var process: Process?

    // MARK: - Callbacks

    /// Called when progress updates.
    var onProgress: ((Progress) -> Void)?

    /// Called when download completes with the final file path.
    var onComplete: ((URL) -> Void)?

    /// Called when download fails.
    var onFailed: ((YTDLPError) -> Void)?

    /// Called when video title is detected (for UI updates before completion).
    var onTitleDetected: ((String) -> Void)?

    // MARK: - Initialization

    init(
        url: URL,
        mode: YTDLPService.DownloadMode,
        binaryPath: String,
        destinationDirectory: URL,
        cookieFile: URL? = nil,
    ) {
        self.id = UUID()
        self.url = url
        self.mode = mode
        self.binaryPath = binaryPath
        self.destinationDirectory = destinationDirectory
        self.cookieFile = cookieFile
    }

    deinit {
        process?.terminate()
    }

    // MARK: - Control

    /// Starts the download.
    func start() {
        guard state == .pending || state == .paused else { return }
        state = .downloading

        let arguments = buildArguments()

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: binaryPath)
        proc.arguments = arguments
        proc.currentDirectoryURL = destinationDirectory

        // Set up pipes for stdout/stderr
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        proc.standardOutput = stdoutPipe
        proc.standardError = stderrPipe

        process = proc

        // Track stderr for error reporting using class wrapper for Sendable capture
        let stderrCollector = StderrCollector()

        // Parse progress from stdout
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty,
                  let line = String(data: data, encoding: .utf8)
            else { return }

            DispatchQueue.main.async {
                self?.parseOutput(line)
            }
        }

        // Collect stderr
        stderrPipe.fileHandleForReading.readabilityHandler = { [stderrCollector] handle in
            let data = handle.availableData
            if let text = String(data: data, encoding: .utf8) {
                stderrCollector.append(text)
            }
        }

        // Set up termination handler
        proc.terminationHandler = { [weak self, stderrCollector] process in
            stdoutPipe.fileHandleForReading.readabilityHandler = nil
            stderrPipe.fileHandleForReading.readabilityHandler = nil

            DispatchQueue.main.async {
                self?.handleProcessTermination(process, stderrOutput: stderrCollector.output)
            }
        }

        do {
            try proc.run()
            Logger.info("yt-dlp download started: \(url.absoluteString)", category: Logger.downloads)
        } catch {
            state = .failed(error.localizedDescription)
            onFailed?(.ytdlpError(error.localizedDescription))
        }
    }

    /// Handles process termination.
    private func handleProcessTermination(_ proc: Process, stderrOutput: String) {
        let exitCode = proc.terminationStatus

        // Check if we were still downloading (not paused/cancelled)
        guard state == .downloading else { return }

        if exitCode == 0 {
            // Find the output file
            if let outputPath = findOutputFile() {
                outputFilePath = outputPath
                state = .completed
                onComplete?(outputPath)
                Logger.info("yt-dlp download completed: \(outputPath.lastPathComponent)", category: Logger.downloads)
            } else {
                let error = YTDLPError.parseError("Could not find downloaded file")
                state = .failed(error.localizedDescription)
                onFailed?(error)
            }
        } else {
            // Process failed or was killed
            let error: YTDLPError = if let parsedError = YTDLPError.parse(from: stderrOutput) {
                parsedError
            } else if exitCode == 15 || exitCode == 143 { // SIGTERM
                .cancelled
            } else {
                .processFailed(exitCode: exitCode, stderr: stderrOutput)
            }

            state = .failed(error.localizedDescription)
            onFailed?(error)
            Logger.warning("yt-dlp download failed: \(error.localizedDescription)", category: Logger.downloads)
        }
    }

    /// Pauses the download.
    ///
    /// Sends SIGTERM to yt-dlp. Resume with `resume()`.
    func pause() {
        guard state == .downloading, let proc = process, proc.isRunning else { return }
        state = .paused
        proc.terminate()
        Logger.info("yt-dlp download paused", category: Logger.downloads)
    }

    /// Resumes a paused download.
    func resume() {
        guard state == .paused else { return }
        state = .pending
        start() // --continue flag handles resume
    }

    /// Cancels the download permanently.
    func cancel() {
        let wasActive = state.isActive
        state = .failed("Cancelled")

        if let proc = process, proc.isRunning {
            proc.terminate()
        }

        // Clean up partial files
        if wasActive {
            cleanupPartialFiles()
        }

        Logger.info("yt-dlp download cancelled", category: Logger.downloads)
    }

    /// Cleans up resources (cookie file).
    func cleanup() {
        if let cookieFile {
            try? FileManager.default.removeItem(at: cookieFile)
        }
    }

    // MARK: - Private Helpers

    /// Builds command-line arguments for yt-dlp.
    private func buildArguments() -> [String] {
        var args: [String] = []

        // Output template with predictable filename
        args.append(contentsOf: ["-o", "%(title)s.%(ext)s"])

        // Continue partial downloads
        args.append("--continue")

        // No playlist (single video)
        args.append("--no-playlist")

        // Progress output for parsing
        args.append("--newline")
        args.append("--progress-template")
        args.append("download:%(progress._percent_str)s|%(progress._downloaded_bytes_str)s/%(progress._total_bytes_str)s|%(progress._speed_str)s|%(progress._eta_str)s")

        // Print final filename after completion
        args.append("--print")
        args.append("after_move:filepath")

        // Format selection based on mode
        switch mode {
        case .video, .saveToPhotos:
            // Best video + audio merged to mp4
            args.append("-f")
            args.append("bestvideo[ext=mp4]+bestaudio[ext=m4a]/bestvideo+bestaudio/best")
            args.append("--merge-output-format")
            args.append("mp4")

        case .videoOnly:
            // Video without audio
            args.append("-f")
            args.append("bestvideo[ext=mp4]/bestvideo")

        case .audioOnly:
            // Extract audio to mp3
            args.append("-x")
            args.append("--audio-format")
            args.append("mp3")
            args.append("--audio-quality")
            args.append("0") // Best quality
        }

        // Use cookies if provided
        if let cookieFile {
            args.append("--cookies")
            args.append(cookieFile.path)
        }

        // The URL to download
        args.append(url.absoluteString)

        return args
    }

    /// Parses output from yt-dlp to extract progress and title.
    private func parseOutput(_ line: String) {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

        // Check for title line: [download] Destination: filename.mp4
        if trimmed.hasPrefix("[download] Destination:") {
            let filename = trimmed
                .replacingOccurrences(of: "[download] Destination:", with: "")
                .trimmingCharacters(in: .whitespaces)

            // Extract title from filename (remove extension)
            let title = (filename as NSString).deletingPathExtension
            detectedTitle = title
            onTitleDetected?(title)
            return
        }

        // Check for final filepath after download
        if trimmed.hasPrefix("/") || trimmed.contains(".mp4") || trimmed.contains(".mp3") {
            let url = URL(fileURLWithPath: trimmed)
            if FileManager.default.fileExists(atPath: url.path) {
                outputFilePath = url
            }
            return
        }

        // Parse progress line: download:50.0%|100.0M/200.0M|5.0M/s|00:20
        if trimmed.hasPrefix("download:") {
            let progressPart = trimmed.replacingOccurrences(of: "download:", with: "")
            let components = progressPart.split(separator: "|").map(String.init)

            guard !components.isEmpty else { return }

            // Parse percentage
            let percentStr = components[0].replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces)
            let percent = Double(percentStr) ?? 0

            // Parse bytes (if available)
            var downloaded: Int64 = 0
            var total: Int64?
            if components.count >= 2 {
                let bytesStr = components[1]
                let byteParts = bytesStr.split(separator: "/").map(String.init)
                if !byteParts.isEmpty {
                    downloaded = parseByteString(byteParts[0])
                }
                if byteParts.count >= 2 {
                    total = parseByteString(byteParts[1])
                }
            }

            // Parse speed
            var speed: Double = 0
            if components.count >= 3 {
                speed = parseSpeedString(components[2])
            }

            // Parse ETA
            var eta: TimeInterval?
            if components.count >= 4 {
                eta = parseETAString(components[3])
            }

            let newProgress = Progress(
                percentComplete: percent,
                bytesDownloaded: downloaded,
                totalBytes: total,
                bytesPerSecond: speed,
                estimatedTimeRemaining: eta,
                filename: detectedTitle,
            )

            progress = newProgress
            onProgress?(newProgress)
        }
    }

    /// Parses a byte string like "100.5M" or "1.2G" to bytes.
    private func parseByteString(_ str: String) -> Int64 {
        let trimmed = str.trimmingCharacters(in: .whitespaces)

        var multiplier: Double = 1
        var numStr = trimmed

        if trimmed.hasSuffix("K") || trimmed.hasSuffix("KiB") {
            multiplier = 1_024
            numStr = trimmed.replacingOccurrences(of: "KiB", with: "").replacingOccurrences(of: "K", with: "")
        } else if trimmed.hasSuffix("M") || trimmed.hasSuffix("MiB") {
            multiplier = 1_024 * 1_024
            numStr = trimmed.replacingOccurrences(of: "MiB", with: "").replacingOccurrences(of: "M", with: "")
        } else if trimmed.hasSuffix("G") || trimmed.hasSuffix("GiB") {
            multiplier = 1_024 * 1_024 * 1_024
            numStr = trimmed.replacingOccurrences(of: "GiB", with: "").replacingOccurrences(of: "G", with: "")
        } else if trimmed.hasSuffix("B") {
            numStr = trimmed.replacingOccurrences(of: "B", with: "")
        }

        if let num = Double(numStr.trimmingCharacters(in: .whitespaces)) {
            return Int64(num * multiplier)
        }
        return 0
    }

    /// Parses a speed string like "5.0M/s" to bytes per second.
    private func parseSpeedString(_ str: String) -> Double {
        let trimmed = str.replacingOccurrences(of: "/s", with: "").trimmingCharacters(in: .whitespaces)
        return Double(parseByteString(trimmed))
    }

    /// Parses an ETA string like "00:20" or "01:30:45" to seconds.
    private func parseETAString(_ str: String) -> TimeInterval? {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        if trimmed == "N/A" || trimmed.isEmpty {
            return nil
        }

        let parts = trimmed.split(separator: ":").compactMap { Int($0) }
        switch parts.count {
        case 1: // seconds
            return TimeInterval(parts[0])
        case 2: // mm:ss
            return TimeInterval(parts[0] * 60 + parts[1])
        case 3: // hh:mm:ss
            return TimeInterval(parts[0] * 3_600 + parts[1] * 60 + parts[2])
        default:
            return nil
        }
    }

    /// Finds the output file after download completes.
    private func findOutputFile() -> URL? {
        // Check if we captured it from output
        if let captured = outputFilePath,
           FileManager.default.fileExists(atPath: captured.path) {
            return captured
        }

        // Search the destination directory
        let fm = FileManager.default
        let expectedExt = switch mode {
        case .video, .videoOnly, .saveToPhotos:
            "mp4"
        case .audioOnly:
            "mp3"
        }

        // Find most recently modified file with expected extension
        do {
            let contents = try fm.contentsOfDirectory(
                at: destinationDirectory,
                includingPropertiesForKeys: [.contentModificationDateKey],
            )

            let candidates = contents.filter { $0.pathExtension.lowercased() == expectedExt }

            // Sort by modification date, newest first
            let sorted = candidates.sorted { url1, url2 in
                let date1 = (try? url1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                let date2 = (try? url2.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                return date1 > date2
            }

            // Return the most recent file created in the last minute
            if let newest = sorted.first {
                let date = (try? newest.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
                if Date().timeIntervalSince(date) < 60 {
                    return newest
                }
            }
        } catch {
            Logger.warning("Failed to search for output file: \(error)", category: Logger.downloads)
        }

        return nil
    }

    /// Cleans up partial download files.
    private func cleanupPartialFiles() {
        let fm = FileManager.default

        // yt-dlp creates .part files for partial downloads
        do {
            let contents = try fm.contentsOfDirectory(
                at: destinationDirectory,
                includingPropertiesForKeys: nil,
            )

            for file in contents where file.pathExtension == "part" {
                // Only delete files created in the last hour (safety check)
                let attrs = try? fm.attributesOfItem(atPath: file.path)
                if let created = attrs?[.creationDate] as? Date,
                   Date().timeIntervalSince(created) < 3_600 {
                    try? fm.removeItem(at: file)
                }
            }
        } catch {
            Logger.warning("Failed to cleanup partial files: \(error)", category: Logger.downloads)
        }
    }
}

// MARK: - Stderr Collector

/// Thread-safe collector for stderr output.
/// Uses NSLock for synchronization since it's called from file handle callbacks.
/// Marked nonisolated to avoid MainActor inference from project settings.
private final nonisolated class StderrCollector: @unchecked Sendable {
    private var buffer = ""
    private let lock = NSLock()

    var output: String {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    func append(_ text: String) {
        lock.lock()
        defer { lock.unlock() }
        buffer += text
    }
}
