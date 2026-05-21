import Foundation

/// Errors that can occur during yt-dlp download operations.
///
/// These errors provide user-friendly messages for common failure modes
/// encountered when downloading from video hosting sites.
enum YTDLPError: LocalizedError, Sendable {
    /// yt-dlp binary was not found in any expected location.
    case notInstalled

    /// The URL is not supported by yt-dlp.
    case unsupportedURL(URL)

    /// Video is age-restricted and requires authentication.
    case ageRestricted

    /// Video is private or requires login.
    case privateVideo

    /// Content is geo-blocked in the user's region.
    case geoRestricted

    /// Cannot download a live stream while it's live.
    case liveStream

    /// Video has been removed or is unavailable.
    case unavailable

    /// yt-dlp process failed with an error.
    case processFailed(exitCode: Int32, stderr: String)

    /// Failed to parse yt-dlp output.
    case parseError(String)

    /// Download was cancelled by the user.
    case cancelled

    /// Generic error with message from yt-dlp.
    case ytdlpError(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            "yt-dlp is not installed. Install via Homebrew: brew install yt-dlp"
        case let .unsupportedURL(url):
            "This URL is not supported: \(url.host ?? url.absoluteString)"
        case .ageRestricted:
            "This video is age-restricted. Enable cookies in settings to use your browser login."
        case .privateVideo:
            "This video is private or requires login."
        case .geoRestricted:
            "This content is not available in your region."
        case .liveStream:
            "Live streams cannot be downloaded while live."
        case .unavailable:
            "This video is unavailable or has been removed."
        case let .processFailed(exitCode, stderr):
            "Download failed (exit code \(exitCode)): \(stderr.prefix(200))"
        case let .parseError(message):
            "Failed to parse download info: \(message)"
        case .cancelled:
            "Download was cancelled"
        case let .ytdlpError(message):
            message
        }
    }

    /// Attempts to parse a yt-dlp error from stderr output.
    ///
    /// Recognizes common error patterns and returns the appropriate typed error.
    ///
    /// - Parameter stderr: The stderr output from yt-dlp.
    /// - Returns: A typed error if recognized, or nil.
    static func parse(from stderr: String) -> YTDLPError? {
        let lowercased = stderr.lowercased()

        // Age-restricted content
        if lowercased.contains("sign in to confirm your age")
            || lowercased.contains("age-restricted")
            || lowercased.contains("age restricted")
            || lowercased.contains("confirm your age") {
            return .ageRestricted
        }

        // Private videos
        if lowercased.contains("private video")
            || lowercased.contains("video is private")
            || lowercased.contains("sign in if you've been granted access")
            || lowercased.contains("this video is not available") {
            return .privateVideo
        }

        // Geo-restricted
        if lowercased.contains("not available in your country")
            || lowercased.contains("geo")
            || lowercased.contains("blocked in your")
            || lowercased.contains("not available in your region") {
            return .geoRestricted
        }

        // Live streams
        if lowercased.contains("live event will begin")
            || lowercased.contains("is live")
            || lowercased.contains("live stream") {
            return .liveStream
        }

        // Unavailable
        if lowercased.contains("video unavailable")
            || lowercased.contains("has been removed")
            || lowercased.contains("this video has been removed")
            || lowercased.contains("no longer available") {
            return .unavailable
        }

        // Unsupported URL
        if lowercased.contains("unsupported url")
            || lowercased.contains("no suitable extractor") {
            // Return nil here - let the caller handle with the URL
            return nil
        }

        return nil
    }
}
