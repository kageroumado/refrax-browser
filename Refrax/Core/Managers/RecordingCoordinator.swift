import AppKit
import AVFoundation
import Foundation

/// Result of a recording operation.
enum RecordingResult: Sendable {
    /// Recording completed successfully.
    case success(url: URL, duration: TimeInterval)

    /// Recording was cancelled by the user.
    case cancelled

    /// Recording failed with an error.
    case failed(any Error)
}

/// Coordinates tab video recording workflow with visual feedback.
///
/// Provides a complete recording experience:
/// - Recording indicator during capture
/// - Preview thumbnail after recording
/// - Option to open, share, or dismiss
/// - Automatic stop after maximum duration (30 minutes)
/// - Automatic stop when tab is closed
///
/// ## Usage
///
/// ```swift
/// let coordinator = RecordingCoordinator()
///
/// // Start recording
/// coordinator.startRecording(webPage: page, in: window, saveDirectory: downloadsURL)
///
/// // Stop recording
/// let result = await coordinator.stopRecording()
/// ```
///
/// ## Audio Limitation
///
/// Due to WebKit architecture, audio from web pages cannot be captured. WKWebView audio
/// runs in a separate WebContent process that ScreenCaptureKit cannot access. Recordings
/// are video-only.
@Observable
final class RecordingCoordinator {
    // MARK: - Configuration

    /// Maximum recording duration in seconds (30 minutes).
    private static let maxRecordingDuration: TimeInterval = 30 * 60

    /// Warning threshold before max duration (25 minutes).
    private static let warningDuration: TimeInterval = 25 * 60

    // MARK: - Public State

    /// The current recording preview, if any.
    ///
    /// Set after a successful recording. The preview auto-dismisses after a delay,
    /// or can be dismissed by user interaction.
    private(set) var currentPreview: RecordingPreview?

    /// Whether recording is currently in progress.
    private(set) var isRecording = false

    /// The start time of the current recording, for duration display.
    private(set) var recordingStartTime: Date?

    /// The web page being recorded, if any.
    private(set) weak var recordingWebPage: WebPage?

    /// Error message to display to the user, if any.
    private(set) var errorMessage: String?

    /// Duration of the current recording in seconds.
    var recordingDuration: TimeInterval {
        guard let startTime = recordingStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    // MARK: - Private State

    /// The active recording session.
    private var activeRecording: RecordingService.ActiveRecording?

    /// Task for the recording startup process.
    private var startupTask: Task<Void, Never>?

    /// Task for monitoring recording duration and lifecycle.
    private var durationLimitTask: Task<Void, Never>?

    /// Preview data shown after recording.
    struct RecordingPreview: Identifiable {
        let id = UUID()
        let thumbnailImage: NSImage
        let fileURL: URL
        let duration: TimeInterval

        /// Timer task for auto-dismiss.
        var dismissTask: Task<Void, Never>?

        /// Formatted duration string (e.g., "0:32").
        var formattedDuration: String {
            let minutes = Int(duration) / 60
            let seconds = Int(duration) % 60
            return String(format: "%d:%02d", minutes, seconds)
        }
    }

    // MARK: - Recording Control

    /// Starts recording a web page.
    ///
    /// - Parameters:
    ///   - webPage: The WebPage to record.
    ///   - window: The window containing the web view.
    ///   - saveDirectory: Directory to save the recording to.
    func startRecording(webPage: WebPage, in window: NSWindow?, saveDirectory: URL) {
        guard !isRecording else {
            Logger.warning("Recording already in progress", category: Logger.navigation)
            return
        }

        guard let window else {
            errorMessage = "No window available for recording"
            Logger.error("No window to record", category: Logger.navigation)
            return
        }

        // Clear any previous error
        errorMessage = nil

        // Set recording state - but mark as "starting" by not setting activeRecording yet
        isRecording = true
        recordingStartTime = Date()
        recordingWebPage = webPage

        // Get the web view's frame in window coordinates
        let webViewFrame = webPage.backingWebView.frame

        // Cancel any previous startup task
        startupTask?.cancel()

        startupTask = Task { @MainActor [weak self] in
            guard let self, !Task.isCancelled else { return }

            do {
                let recording = try await RecordingService.startRecording(
                    window: window,
                    contentRect: webViewFrame,
                    saveDirectory: saveDirectory,
                )

                // Check if we were cancelled during startup
                guard !Task.isCancelled, isRecording else {
                    // We were cancelled, stop the recording we just started
                    _ = await RecordingService.stopRecording(recording)
                    try? FileManager.default.removeItem(at: recording.assetWriter.outputURL)
                    return
                }

                activeRecording = recording
                Logger.info("Recording started", category: Logger.navigation)

                // Start monitoring for duration limit and tab closure
                startRecordingMonitoring()

            } catch {
                guard !Task.isCancelled else { return }

                Logger.error("Failed to start recording: \(error)", category: Logger.navigation)
                errorMessage = error.localizedDescription
                resetRecordingState()
            }
        }
    }

    /// Monitors recording duration and web page lifecycle.
    ///
    /// Periodically checks:
    /// - If we've hit the maximum duration (auto-stops)
    /// - If the web page has been deallocated (auto-stops)
    private func startRecordingMonitoring() {
        durationLimitTask?.cancel()

        durationLimitTask = Task { @MainActor [weak self] in
            guard let self else { return }

            // Check every second
            while !Task.isCancelled, isRecording {
                try? await Task.sleep(for: .seconds(1))

                guard !Task.isCancelled, isRecording else { break }

                // Check if web page was deallocated (tab closed)
                if recordingWebPage == nil {
                    Logger.info("Tab closed during recording, stopping automatically", category: Logger.navigation)
                    _ = await stopRecording()
                    break
                }

                // Check if we've hit the maximum duration
                if recordingDuration >= Self.maxRecordingDuration {
                    Logger.info("Recording reached maximum duration (\(Int(Self.maxRecordingDuration / 60)) minutes), stopping automatically", category: Logger.navigation)
                    _ = await stopRecording()
                    break
                }
            }
        }
    }

    /// Resets all recording state.
    private func resetRecordingState() {
        isRecording = false
        recordingStartTime = nil
        recordingWebPage = nil
        activeRecording = nil
        startupTask?.cancel()
        startupTask = nil
        durationLimitTask?.cancel()
        durationLimitTask = nil
    }

    /// Stops the current recording.
    ///
    /// - Returns: The recording result.
    @discardableResult
    func stopRecording() async -> RecordingResult {
        guard isRecording else {
            return .cancelled
        }

        let duration = recordingDuration

        // Cancel startup task if still running
        startupTask?.cancel()
        startupTask = nil

        // If we don't have an active recording yet (still starting up), just reset state
        guard let recording = activeRecording else {
            resetRecordingState()
            return .cancelled
        }

        // Reset state immediately to prevent re-entry
        resetRecordingState()

        // Stop the recording
        let result = await RecordingService.stopRecording(recording)

        switch result {
        case let .success(url):
            // Generate thumbnail and show preview
            if let thumbnail = await generateThumbnail(from: url) {
                showPreview(thumbnailImage: thumbnail, fileURL: url, duration: duration)
            }
            return .success(url: url, duration: duration)

        case let .failed(error):
            Logger.error("Recording failed: \(error)", category: Logger.navigation)
            return .failed(error)
        }
    }

    /// Cancels the current recording without saving.
    func cancelRecording() {
        guard isRecording else { return }

        // Cancel startup task if still running
        startupTask?.cancel()

        let recording = activeRecording
        resetRecordingState()

        if let recording {
            Task {
                _ = await RecordingService.stopRecording(recording)
                // Delete the file since we're cancelling
                try? FileManager.default.removeItem(at: recording.assetWriter.outputURL)
                Logger.info("Recording cancelled", category: Logger.navigation)
            }
        }
    }

    // MARK: - Preview Actions

    /// Opens the recorded video in the default application.
    func openPreview() {
        guard let preview = currentPreview else { return }
        NSWorkspace.shared.open(preview.fileURL)
        dismissPreview()
    }

    /// Reveals the recorded video in Finder.
    func revealPreviewInFinder() {
        guard let preview = currentPreview else { return }
        NSWorkspace.shared.activateFileViewerSelecting([preview.fileURL])
        dismissPreview()
    }

    /// Dismisses the current preview.
    func dismissPreview() {
        currentPreview?.dismissTask?.cancel()
        currentPreview = nil
    }

    // MARK: - Private Implementation

    /// Shows the recording preview thumbnail.
    private func showPreview(thumbnailImage: NSImage, fileURL: URL, duration: TimeInterval) {
        // Cancel any existing preview dismiss task
        currentPreview?.dismissTask?.cancel()

        var preview = RecordingPreview(
            thumbnailImage: thumbnailImage,
            fileURL: fileURL,
            duration: duration,
        )

        // Auto-dismiss after 8 seconds (longer than screenshots due to potential longer review)
        preview.dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard !Task.isCancelled else { return }
            self?.dismissPreview()
        }

        currentPreview = preview
    }

    /// Generates a thumbnail image from a video file.
    private func generateThumbnail(from url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)

        // Get a frame from 1 second in, or the first frame if video is shorter
        let time = CMTime(seconds: 1, preferredTimescale: 600)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 240, height: 240)

        do {
            let cgImage = try await generator.image(at: time).image
            return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        } catch {
            // Try the first frame instead
            do {
                let cgImage = try await generator.image(at: .zero).image
                return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            } catch {
                Logger.warning("Failed to generate recording thumbnail: \(error)", category: Logger.navigation)
                return nil
            }
        }
    }
}
