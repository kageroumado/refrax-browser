import AppKit
import AVFoundation
import Foundation
@preconcurrency import ScreenCaptureKit
import UniformTypeIdentifiers

/// Service for recording tab video using ScreenCaptureKit.
///
/// Records the visible web content area as a video file. Due to WebKit architecture
/// limitations, audio from the web page cannot be captured (WKWebView audio runs in
/// a separate process and is not accessible to ScreenCaptureKit).
///
/// ## Usage
///
/// ```swift
/// let recording = try await RecordingService.startRecording(
///     window: window,
///     contentRect: webViewRect,
///     saveDirectory: downloadsURL
/// )
///
/// // Later...
/// let result = await RecordingService.stopRecording(recording)
/// ```
///
/// ## Requirements
///
/// - macOS 13.0+ for ScreenCaptureKit
/// - Screen recording permission (prompted automatically on first use)
enum RecordingService {
    // MARK: - Types

    /// An active recording session.
    ///
    /// This type uses `@unchecked Sendable` because the contained ScreenCaptureKit
    /// and AVFoundation types are thread-safe but not marked Sendable.
    struct ActiveRecording: @unchecked Sendable {
        /// Unique identifier for this recording.
        let id: UUID

        /// The stream capturing video frames.
        let stream: SCStream

        /// The output handler receiving frames.
        let output: RecordingStreamOutput

        /// The asset writer encoding video.
        let assetWriter: AVAssetWriter

        /// The video input for the asset writer.
        let videoInput: AVAssetWriterInput

        /// When the recording started.
        let startTime: Date

        /// The directory to save the recording to.
        let saveDirectory: URL
    }

    /// Result of stopping a recording.
    enum StopResult: Sendable {
        /// Recording completed successfully.
        case success(URL)

        /// Recording was cancelled or failed.
        case failed(any Error)
    }

    /// Errors specific to recording.
    enum RecordingError: Error, LocalizedError, Sendable {
        case permissionDenied
        case windowNotFound
        case encoderSetupFailed
        case noFramesCaptured
        case alreadyRecording

        var errorDescription: String? {
            switch self {
            case .permissionDenied:
                "Screen recording permission is required"
            case .windowNotFound:
                "Could not find the window to record"
            case .encoderSetupFailed:
                "Failed to set up video encoder"
            case .noFramesCaptured:
                "No video frames were captured"
            case .alreadyRecording:
                "A recording is already in progress"
            }
        }
    }

    // MARK: - Recording Configuration

    /// Configuration for video recording.
    private enum Config {
        /// Target frame rate for recording.
        static let frameRate: Int = 30

        /// Video codec for encoding.
        static let codec: AVVideoCodecType = .hevc

        /// Quality preset (0.0-1.0).
        static let quality: Float = 0.8
    }

    // MARK: - Public Interface

    /// Starts recording a window's content.
    ///
    /// - Parameters:
    ///   - window: The window to record.
    ///   - contentRect: The rect within the window to capture (in window coordinates).
    ///                  If nil, captures the entire window.
    ///   - saveDirectory: Directory to save the recording to.
    /// - Returns: An active recording handle.
    /// - Throws: `RecordingError` if recording cannot be started.
    @MainActor
    static func startRecording(
        window: NSWindow,
        contentRect: CGRect? = nil,
        saveDirectory: URL,
    ) async throws -> ActiveRecording {
        // Get shareable content
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true,
        )

        // Find the matching SCWindow
        guard let scWindow = content.windows.first(where: { $0.windowID == window.windowNumber }) else {
            throw RecordingError.windowNotFound
        }

        // Create content filter for this window
        let filter = SCContentFilter(desktopIndependentWindow: scWindow)

        // Determine capture size
        let captureRect = contentRect ?? CGRect(origin: .zero, size: window.frame.size)
        let width = Int(captureRect.width * (window.backingScaleFactor))
        let height = Int(captureRect.height * (window.backingScaleFactor))

        // Ensure even dimensions for video encoding
        let evenWidth = width - (width % 2)
        let evenHeight = height - (height % 2)

        // Create stream configuration
        let streamConfig = SCStreamConfiguration()
        streamConfig.width = evenWidth
        streamConfig.height = evenHeight
        streamConfig.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(Config.frameRate))
        streamConfig.showsCursor = true
        streamConfig.pixelFormat = kCVPixelFormatType_32BGRA

        // If we have a content rect, configure the source rect
        if let rect = contentRect {
            streamConfig.sourceRect = rect
        }

        // Set up output file
        let recordingID = UUID()
        let filename = generateFilename()
        let fileURL = saveDirectory.appendingPathComponent(filename)

        // Ensure directory exists
        let fm = FileManager.default
        if !fm.fileExists(atPath: saveDirectory.path) {
            try fm.createDirectory(at: saveDirectory, withIntermediateDirectories: true)
        }

        // Set up AVAssetWriter
        let assetWriter = try AVAssetWriter(outputURL: fileURL, fileType: .mp4)

        let videoSettings: [String: Any] = [
            AVVideoCodecKey: Config.codec,
            AVVideoWidthKey: evenWidth,
            AVVideoHeightKey: evenHeight,
            AVVideoCompressionPropertiesKey: [
                AVVideoQualityKey: Config.quality,
                AVVideoExpectedSourceFrameRateKey: Config.frameRate,
            ],
        ]

        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        videoInput.expectsMediaDataInRealTime = true

        guard assetWriter.canAdd(videoInput) else {
            throw RecordingError.encoderSetupFailed
        }
        assetWriter.add(videoInput)

        // Create the stream output handler
        let output = RecordingStreamOutput(assetWriter: assetWriter, videoInput: videoInput)

        // Create and start the stream with a delegate to handle errors
        let streamDelegate = RecordingStreamDelegate()
        let stream = SCStream(filter: filter, configuration: streamConfig, delegate: streamDelegate)
        try stream.addStreamOutput(output, type: .screen, sampleHandlerQueue: output.queue)

        // Store delegate reference in output to keep it alive
        output.streamDelegate = streamDelegate

        // Start the asset writer
        assetWriter.startWriting()
        assetWriter.startSession(atSourceTime: .zero)

        // Start the stream
        try await stream.startCapture()

        Logger.info("Started recording to \(fileURL.path)", category: Logger.navigation)

        return ActiveRecording(
            id: recordingID,
            stream: stream,
            output: output,
            assetWriter: assetWriter,
            videoInput: videoInput,
            startTime: Date(),
            saveDirectory: saveDirectory,
        )
    }

    /// Stops an active recording and saves the video file.
    ///
    /// - Parameter recording: The active recording to stop.
    /// - Returns: The result of the stop operation.
    static func stopRecording(_ recording: ActiveRecording) async -> StopResult {
        do {
            // Stop the capture stream
            try await recording.stream.stopCapture()

            // Mark the video input as finished
            recording.videoInput.markAsFinished()

            // Finish writing the asset
            await recording.assetWriter.finishWriting()

            // Check for errors
            if let error = recording.assetWriter.error {
                throw error
            }

            // Verify the file was written
            let outputURL = recording.assetWriter.outputURL
            let fm = FileManager.default

            guard fm.fileExists(atPath: outputURL.path) else {
                throw RecordingError.noFramesCaptured
            }

            // Get file attributes to check size
            let attrs = try fm.attributesOfItem(atPath: outputURL.path)
            let size = attrs[.size] as? UInt64 ?? 0

            if size == 0 {
                try? fm.removeItem(at: outputURL)
                throw RecordingError.noFramesCaptured
            }

            Logger.info(
                "Recording saved to \(outputURL.path) (\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))",
                category: Logger.navigation,
            )

            return .success(outputURL)
        } catch {
            Logger.error("Failed to stop recording: \(error)", category: Logger.navigation)

            // Clean up partial file if it exists
            let outputURL = recording.assetWriter.outputURL
            try? FileManager.default.removeItem(at: outputURL)

            return .failed(error)
        }
    }

    /// Checks if screen recording permission is granted.
    ///
    /// - Returns: `true` if permission is granted, `false` otherwise.
    static func hasScreenRecordingPermission() async -> Bool {
        do {
            _ = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            return true
        } catch {
            return false
        }
    }

    // MARK: - Private Helpers

    /// Generates a timestamped filename for recordings.
    private static func generateFilename() -> String {
        // Use static class method to avoid formatter allocation
        let timestamp = ISO8601DateFormatter.string(
            from: Date(),
            timeZone: .current,
            formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime],
        ).replacingOccurrences(of: ":", with: ".")
        return "Recording \(timestamp).mp4"
    }
}

// MARK: - Recording Stream Delegate

/// Handles stream lifecycle events and errors.
final class RecordingStreamDelegate: NSObject, SCStreamDelegate, @unchecked Sendable {
    /// Called when the stream stops unexpectedly.
    func stream(_: SCStream, didStopWithError error: any Error) {
        Logger.error("Recording stream stopped with error: \(error)", category: Logger.navigation)
    }
}

// MARK: - Recording Stream Output

/// Handles video frames from ScreenCaptureKit and writes them to an AVAssetWriter.
final class RecordingStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    /// The queue for processing frames.
    let queue = DispatchQueue(label: "com.refrax.recording", qos: .userInitiated)

    /// Reference to the stream delegate to keep it alive.
    var streamDelegate: RecordingStreamDelegate?

    /// The asset writer for encoding video.
    private let assetWriter: AVAssetWriter
    private let videoInput: AVAssetWriterInput
    private let pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor

    /// Whether we've received the first frame (for timing).
    private var hasStarted = false
    private var firstFrameTime: CMTime = .zero
    private var frameCount = 0
    private var droppedFrameCount = 0

    init(assetWriter: AVAssetWriter, videoInput: AVAssetWriterInput) {
        self.assetWriter = assetWriter
        self.videoInput = videoInput

        // Create pixel buffer adaptor for efficient frame handling
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        self.pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: attributes,
        )

        super.init()
    }

    func stream(_: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        guard type == .screen else { return }
        guard assetWriter.status == .writing else { return }

        // Get the pixel buffer from the sample
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        // Get presentation time
        var presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

        // Adjust timing relative to first frame
        if !hasStarted {
            firstFrameTime = presentationTime
            hasStarted = true
        }
        presentationTime = CMTimeSubtract(presentationTime, firstFrameTime)

        // Append the frame
        if videoInput.isReadyForMoreMediaData {
            pixelBufferAdaptor.append(pixelBuffer, withPresentationTime: presentationTime)
            frameCount += 1
        } else {
            droppedFrameCount += 1
            // Log occasionally if we're dropping many frames
            if droppedFrameCount == 10 || droppedFrameCount == 100 {
                Logger.warning("Recording dropped \(droppedFrameCount) frames (encoder backpressure)", category: Logger.navigation)
            }
        }
    }
}
