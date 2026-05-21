import Foundation
import SwiftData
import UniformTypeIdentifiers

/// Represents a file download with progress tracking and persistence.
///
/// Downloads track the complete lifecycle from initiation to completion,
/// including pause/resume support and error recovery.
///
/// ## Lifecycle States
///
/// ```
/// pending → downloading → completed
///              ↓              ↓
///           paused        failed
///              ↓              ↓
///           downloading   (retry) → downloading
/// ```
///
/// ## File Handling
///
/// During download, files use a `.download` extension (Safari convention):
/// - `filename.pdf.download` → Active/paused download
/// - `filename.pdf` → Completed download
///
/// This allows Finder to show progress and prevents incomplete files
/// from appearing as finished.
///
/// ## Resume Support
///
/// Downloads can be resumed after:
/// - User-initiated pause
/// - Network interruption
/// - App restart (if resume data is persisted)
///
/// Resume data is stored in `resumeData` and used by `URLSession.downloadTask(withResumeData:)`.
@Model
final class Download {
    // MARK: - Identity

    /// Unique identifier for this download.
    @Attribute(.unique)
    var id: UUID

    // MARK: - Source

    /// The URL being downloaded.
    var sourceURL: URL

    /// The URL of the page that initiated the download.
    ///
    /// Used for displaying context in the downloads list.
    var originatingPageURL: URL?

    /// The title of the page that initiated the download.
    var originatingPageTitle: String?

    // MARK: - Destination

    /// Suggested filename from the server or download attribute.
    ///
    /// May differ from `destinationFilename` if conflicts exist.
    var suggestedFilename: String

    /// Final filename after conflict resolution.
    ///
    /// This is the actual name used on disk (without `.download` suffix).
    var destinationFilename: String

    /// Directory where the file is being saved.
    ///
    /// Typically the user's Downloads folder unless configured otherwise.
    var destinationDirectory: URL

    // MARK: - Progress

    /// Current state of the download.
    var state: DownloadState

    /// Persisted bytes received (updated only on pause/complete/fail).
    ///
    /// During active download, use `bytesReceived` computed property which
    /// returns live transient state. This is only persisted on state changes.
    var persistedBytesReceived: Int64

    /// Total expected size in bytes, if known.
    ///
    /// `nil` when server doesn't provide Content-Length (chunked transfer).
    var totalBytes: Int64?

    // MARK: - Transient Progress (not persisted)

    /// Current bytes received during active download (in-memory only).
    ///
    /// Updated ~60 times/second during download. Not persisted to avoid
    /// constant SwiftData dirty tracking. Use `bytesReceived` computed
    /// property for the effective value.
    @Transient
    var liveBytesReceived: Int64 = 0

    /// Current download speed in bytes per second (in-memory only).
    ///
    /// Only meaningful during active download. Reset to 0 on pause/complete.
    @Transient
    var liveBytesPerSecond: Double = 0

    // MARK: - Computed Progress

    /// Effective bytes received (live during download, persisted after).
    var bytesReceived: Int64 {
        // Explicit observation tracking — @Transient properties don't get
        // auto-generated observation getters from @Model, so views reading
        // this computed property wouldn't be notified of live progress changes.
        access(keyPath: \.liveBytesReceived)
        return state == .downloading ? liveBytesReceived : persistedBytesReceived
    }

    /// Download speed in bytes per second.
    ///
    /// Returns live speed during download, 0 otherwise.
    var bytesPerSecond: Double {
        access(keyPath: \.liveBytesPerSecond)
        return state == .downloading ? liveBytesPerSecond : 0
    }

    // MARK: - Timestamps

    /// When the download was created.
    var createdAt: Date

    /// When the download last changed state.
    var modifiedAt: Date

    /// When the download completed successfully.
    var completedAt: Date?

    // MARK: - Resume Support

    /// Resume data for continuing interrupted downloads.
    ///
    /// Persisted for app restart recovery. Cleared on completion.
    var resumeData: Data?

    // MARK: - Error

    /// Error message if download failed.
    var errorMessage: String?

    /// Error code for categorizing failures.
    var errorCode: Int?

    // MARK: - aria2 / BitTorrent

    /// Type of download (HTTP, magnet, torrent).
    var downloadTypeRaw: String

    /// Type-safe accessor for download type.
    var downloadType: DownloadType {
        get { DownloadType(rawValue: downloadTypeRaw) ?? .http }
        set { downloadTypeRaw = newValue.rawValue }
    }

    /// aria2 Global ID for tracking aria2-managed downloads.
    ///
    /// Set when a download is handled by aria2. Used for resuming
    /// downloads after app restart and for status queries.
    var aria2GID: String?

    /// Number of BitTorrent peers/seeders connected.
    ///
    /// Only populated for magnet/torrent downloads. `nil` for HTTP downloads.
    var btPeers: Int?

    /// BitTorrent torrent name from metadata.
    ///
    /// For magnet links, this is populated after metadata is fetched.
    /// May differ from the filename initially set.
    var btName: String?

    // MARK: - yt-dlp

    /// yt-dlp download mode (video, audio, etc.).
    ///
    /// Only populated for `.ytdlp` download type.
    var ytdlpModeRaw: String?

    /// Type-safe accessor for yt-dlp mode.
    var ytdlpMode: YTDLPDownloadMode? {
        get { ytdlpModeRaw.flatMap { YTDLPDownloadMode(rawValue: $0) } }
        set { ytdlpModeRaw = newValue?.rawValue }
    }

    /// Video title detected by yt-dlp.
    ///
    /// Updated during download as yt-dlp extracts metadata.
    var ytdlpTitle: String?

    // MARK: - Content Type

    /// MIME type from the server response.
    var mimeType: String?

    // MARK: - Space Context

    /// ID of the space that initiated the download.
    ///
    /// Used for filtering downloads by space and applying space-specific settings
    /// like color tags. `nil` for downloads not associated with a space.
    var spaceID: UUID?

    /// Name of the originating space.
    ///
    /// Cached for display even after space deletion.
    var spaceName: String?

    /// Finder color tag to apply when download completes.
    ///
    /// Uses macOS Finder label colors (1-7). `nil` or 0 means no tag.
    var colorTag: Int?

    // MARK: - Computed Properties

    /// Uniform Type Identifier for the file content.
    ///
    /// Derived from MIME type or file extension.
    var contentType: UTType? {
        // Try MIME type first
        if let mimeType, let type = UTType.fromMIMEType(mimeType) {
            return type
        }

        // Fall back to file extension
        let ext = (destinationFilename as NSString).pathExtension
        return ext.isEmpty ? nil : UTType(filenameExtension: ext)
    }

    /// Whether the download is an executable or potentially dangerous file.
    var isPotentiallyDangerous: Bool {
        guard let type = contentType else { return false }

        let dangerousTypes: [UTType] = [
            .executable,
            .unixExecutable,
            .application,
            .applicationBundle,
            .package,
            .shellScript,
        ]

        return dangerousTypes.contains { type.conforms(to: $0) }
    }

    /// File extension based on content type.
    var suggestedExtension: String? {
        contentType?.preferredFilenameExtension
    }

    /// Progress as a fraction from 0.0 to 1.0.
    ///
    /// Returns `nil` if total size is unknown.
    var progress: Double? {
        guard let total = totalBytes, total > 0 else { return nil }
        return Double(bytesReceived) / Double(total)
    }

    /// Estimated time remaining in seconds.
    ///
    /// Returns `nil` if speed is unknown or zero.
    var estimatedTimeRemaining: TimeInterval? {
        guard let total = totalBytes,
              bytesPerSecond > 0 else { return nil }
        let remaining = total - bytesReceived
        return Double(remaining) / bytesPerSecond
    }

    /// Full path to the download file (with `.download` suffix if incomplete).
    var currentFileURL: URL {
        // Incomplete downloads (pending, downloading, paused) use .download suffix
        // Only completed (and failed with no resume) downloads use final filename
        let isIncomplete = state == .pending || state == .downloading || state == .paused
        let filename = isIncomplete ? "\(destinationFilename).download" : destinationFilename
        return destinationDirectory.appendingPathComponent(filename)
    }

    /// Full path to the final destination file.
    var finalFileURL: URL {
        destinationDirectory.appendingPathComponent(destinationFilename)
    }

    /// Whether the download can be resumed.
    ///
    /// A download can be resumed if:
    /// - It's paused with resume data, OR
    /// - It failed but has resume data (server supported Range requests)
    var canResume: Bool {
        (state == .paused || state == .failed) && resumeData != nil
    }

    /// Whether the download can be retried after failure.
    ///
    /// Failed downloads can always be retried (from the beginning if no resume data).
    var canRetry: Bool {
        state == .failed
    }

    // MARK: - Initialization

    init(
        sourceURL: URL,
        suggestedFilename: String,
        destinationDirectory: URL,
        originatingPageURL: URL? = nil,
        originatingPageTitle: String? = nil,
        mimeType: String? = nil,
        spaceID: UUID? = nil,
        spaceName: String? = nil,
        colorTag: Int? = nil,
        downloadType: DownloadType = .http,
        ytdlpMode: YTDLPDownloadMode? = nil,
    ) {
        self.id = UUID()
        self.sourceURL = sourceURL
        self.suggestedFilename = suggestedFilename
        self.destinationFilename = suggestedFilename
        self.destinationDirectory = destinationDirectory
        self.originatingPageURL = originatingPageURL
        self.originatingPageTitle = originatingPageTitle
        self.mimeType = mimeType
        self.spaceID = spaceID
        self.spaceName = spaceName
        self.colorTag = colorTag
        self.downloadTypeRaw = downloadType.rawValue
        self.aria2GID = nil
        self.btPeers = nil
        self.btName = nil
        self.ytdlpModeRaw = ytdlpMode?.rawValue
        self.ytdlpTitle = nil
        self.state = .pending
        self.persistedBytesReceived = 0
        self.totalBytes = nil
        self.createdAt = Date()
        self.modifiedAt = Date()
        self.completedAt = nil
        self.resumeData = nil
        self.errorMessage = nil
        self.errorCode = nil
    }

    // MARK: - State Updates

    /// Marks the download as actively downloading.
    func markDownloading() {
        // Initialize live state from persisted state when resuming
        liveBytesReceived = persistedBytesReceived
        liveBytesPerSecond = 0
        state = .downloading
        modifiedAt = Date()
    }

    /// Updates live progress (in-memory only, no persistence).
    ///
    /// Called ~60 times/second during download. Only updates transient
    /// properties to avoid SwiftData dirty tracking overhead.
    /// Uses explicit `withMutation` to fire observation notifications since
    /// `@Transient` properties don't get auto-generated observation setters.
    func updateLiveProgress(bytesReceived: Int64, totalBytes: Int64?, bytesPerSecond: Double) {
        if liveBytesReceived != bytesReceived {
            withMutation(keyPath: \.liveBytesReceived) {
                liveBytesReceived = bytesReceived
            }
        }
        if liveBytesPerSecond != bytesPerSecond {
            withMutation(keyPath: \.liveBytesPerSecond) {
                liveBytesPerSecond = bytesPerSecond
            }
        }
        // totalBytes rarely changes and is already persisted, so update it
        if self.totalBytes != totalBytes {
            self.totalBytes = totalBytes
        }
        // NO modifiedAt update - this is transient progress
    }

    /// Persists current progress to SwiftData.
    ///
    /// Call this before state transitions (pause, complete, fail) to ensure
    /// progress is saved for resume or history display.
    private func persistProgress() {
        persistedBytesReceived = liveBytesReceived
        liveBytesPerSecond = 0
        modifiedAt = Date()
    }

    /// Marks the download as paused with resume data.
    func markPaused(resumeData: Data?) {
        persistProgress()
        state = .paused
        self.resumeData = resumeData
    }

    /// Marks the download as completed.
    func markCompleted() {
        persistProgress()
        state = .completed
        completedAt = Date()
        resumeData = nil
    }

    /// Marks the download as failed with error information.
    func markFailed(error: any Error, resumeData: Data?) {
        persistProgress()
        state = .failed
        errorMessage = error.localizedDescription
        errorCode = (error as NSError).code
        self.resumeData = resumeData
    }

    /// Updates BitTorrent-specific information.
    func updateBitTorrentInfo(peers: Int?, name: String?) {
        if let peers {
            btPeers = peers
        }
        if let name, btName == nil {
            btName = name
            // Update filename if we got the actual torrent name
            if suggestedFilename.hasPrefix("magnet-") {
                suggestedFilename = name
                destinationFilename = name
            }
        }
        modifiedAt = Date()
    }

    /// Resolves filename conflicts by appending a number.
    ///
    /// Transforms "file.pdf" → "file 1.pdf" → "file 2.pdf" etc.
    ///
    /// - Parameter avoiding: Set of filenames to avoid collisions with.
    func resolveFilenameConflict(avoiding existingNames: Set<String>) {
        var candidate = suggestedFilename
        var counter = 1

        let baseName: String
        let ext: String

        if let dotIndex = suggestedFilename.lastIndex(of: ".") {
            baseName = String(suggestedFilename[..<dotIndex])
            ext = String(suggestedFilename[dotIndex...])
        } else {
            baseName = suggestedFilename
            ext = ""
        }

        while existingNames.contains(candidate) || existingNames.contains("\(candidate).download") {
            candidate = "\(baseName) \(counter)\(ext)"
            counter += 1

            // Safety limit
            if counter > 10_000 {
                candidate = "\(baseName) \(UUID().uuidString.prefix(8))\(ext)"
                break
            }
        }

        destinationFilename = candidate
    }
}

// MARK: - Download State

/// Current state of a download.
enum DownloadState: String, Codable {
    /// Download created but not started.
    case pending

    /// Actively receiving data.
    case downloading

    /// User paused or network interrupted with resume capability.
    case paused

    /// Successfully finished.
    case completed

    /// Failed with error (may be retryable).
    case failed

    /// Whether the download is actively transferring or waiting.
    var isActive: Bool {
        self == .pending || self == .downloading
    }

    /// Human-readable description.
    var displayName: String {
        switch self {
        case .pending: "Waiting"
        case .downloading: "Downloading"
        case .paused: "Paused"
        case .completed: "Completed"
        case .failed: "Failed"
        }
    }
}

// MARK: - Download Type

/// Type of download based on source.
enum DownloadType: String, Codable, Sendable {
    /// Standard HTTP/HTTPS download.
    case http

    /// BitTorrent magnet link.
    case magnet

    /// BitTorrent .torrent file.
    case torrent

    /// yt-dlp video/audio extraction.
    case ytdlp

    /// Whether this is a BitTorrent download type.
    var isBitTorrent: Bool {
        self == .magnet || self == .torrent
    }

    /// SF Symbol name for this download type.
    var iconName: String {
        switch self {
        case .http:
            "arrow.down.circle"
        case .magnet, .torrent:
            "point.3.connected.trianglepath.dotted"
        case .ytdlp:
            "play.rectangle"
        }
    }
}

// MARK: - yt-dlp Mode

/// Download mode for yt-dlp downloads.
enum YTDLPDownloadMode: String, Codable, Sendable {
    /// Best video + best audio merged into mp4.
    case video

    /// Video only, no audio track.
    case videoOnly

    /// Audio extracted to mp3.
    case audioOnly

    /// Same as video, then import to Photos library.
    case saveToPhotos

    /// Human-readable description.
    var displayName: String {
        switch self {
        case .video: "Video"
        case .videoOnly: "Video Only"
        case .audioOnly: "Audio"
        case .saveToPhotos: "Save to Photos"
        }
    }

    /// SF Symbol name.
    var iconName: String {
        switch self {
        case .video, .videoOnly, .saveToPhotos:
            "video"
        case .audioOnly:
            "music.note"
        }
    }
}
