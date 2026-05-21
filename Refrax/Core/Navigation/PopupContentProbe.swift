import Foundation
import os

/// Probes URLs to determine if they should be downloaded or displayed.
///
/// When a popup (`target="_blank"`) link is clicked, we don't know if it leads
/// to a webpage or a downloadable file. This actor performs a lightweight HEAD
/// request to inspect the response headers before deciding.
///
/// ## When Probing Occurs
///
/// To avoid wasting network requests, we only probe URLs that look like they
/// might be downloads (have a file extension matching common download types).
/// URLs without extensions or with web extensions (`.html`, `.php`) skip probing.
///
/// ## Flow
///
/// ```
/// User clicks target="_blank" link
///        ↓
/// URL has download-like extension?
///    No → Open tab immediately
///    Yes ↓
/// ┌──────────────────────────────────┐
/// │ HEAD request (follows redirects) │
/// │  • Check Content-Disposition     │
/// │  • Check MIME type               │
/// └──────────────────────────────────┘
///        ↓
/// ┌─────────────┐     ┌─────────────┐
/// │  Download   │ OR  │  Open Tab   │
/// └─────────────┘     └─────────────┘
/// ```
///
/// ## Fallback
///
/// If probing fails or times out, the caller should fall back to opening
/// a normal tab (letting response handling close it if it's a download).
actor PopupContentProbe {
    static let shared = PopupContentProbe()

    /// Result of probing a URL.
    enum ProbeResult: Sendable {
        /// URL leads to a downloadable file.
        ///
        /// - Parameters:
        ///   - url: Final URL after redirects.
        ///   - suggestedFilename: Filename from response, if available.
        case download(url: URL, suggestedFilename: String?)

        /// URL leads to displayable web content.
        ///
        /// - Parameter url: Final URL after redirects.
        case webpage(url: URL)

        /// URL doesn't look like a download, skip probing.
        case skipProbe

        /// Probing failed or timed out.
        case unknown
    }

    /// File extensions that suggest a URL might be a download.
    ///
    /// Only URLs with these extensions trigger a HEAD probe. This avoids
    /// unnecessary network requests for obvious webpage URLs.
    private static let downloadLikeExtensions: Set<String> = [
        // Disk images and installers
        "dmg", "iso", "img", "pkg", "mpkg", "app",
        // Windows executables and installers
        "exe", "msi", "msix",
        // Linux packages
        "deb", "rpm", "appimage", "flatpak", "snap",
        // Archives
        "zip", "rar", "7z", "tar", "gz", "bz2", "xz", "tgz", "tbz2",
        // Documents
        "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        // Other binary formats
        "bin", "jar", "war", "apk", "ipa", "crx", "xpi",
        // Media (sometimes downloaded)
        "mp3", "mp4", "mov", "avi", "mkv", "flac", "wav",
    ]

    /// MIME types that indicate a download.
    ///
    /// If the response has one of these MIME types, treat it as a download.
    private static let downloadMIMETypes: Set<String> = [
        "application/octet-stream",
        "application/x-msdownload",
        "application/x-apple-diskimage",
        "application/zip",
        "application/x-rar-compressed",
        "application/x-7z-compressed",
        "application/gzip",
        "application/x-tar",
        "application/x-bzip2",
    ]

    /// MIME types that are definitely displayable webpages.
    private static let webpageMIMETypes: Set<String> = [
        "text/html",
        "application/xhtml+xml",
    ]

    /// Ephemeral session for privacy-preserving requests.
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
        ]

        self.session = URLSession(configuration: config)
    }

    /// Probes a URL to determine if it should be downloaded or displayed.
    ///
    /// Only probes URLs that look like potential downloads (based on file extension).
    /// For other URLs, returns `.skipProbe` immediately.
    ///
    /// - Parameters:
    ///   - url: The URL to probe.
    ///   - timeout: Maximum time to wait (default 3 seconds).
    /// - Returns: Result indicating download, webpage, skipProbe, or unknown.
    func probe(_ url: URL, timeout: TimeInterval = 3.0) async -> ProbeResult {
        // Only probe URLs that look like downloads
        guard shouldProbe(url) else {
            return .skipProbe
        }

        do {
            let (finalURL, response) = try await performProbe(url, timeout: timeout)
            return analyzeResponse(response, finalURL: finalURL)
        } catch {
            Logger.debug(
                "Popup probe failed for \(url.absoluteString): \(error.localizedDescription)",
                category: Logger.navigation,
            )
            return .unknown
        }
    }

    /// Determines if a URL should be probed based on its path.
    ///
    /// Returns `true` only for URLs with download-like file extensions.
    private func shouldProbe(_ url: URL) -> Bool {
        let pathExtension = url.pathExtension.lowercased()
        guard !pathExtension.isEmpty else {
            return false
        }
        return Self.downloadLikeExtensions.contains(pathExtension)
    }

    /// Performs the HEAD request with redirect following.
    private func performProbe(_ url: URL, timeout: TimeInterval) async throws -> (URL, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout

        let delegate = RedirectTrackingDelegate()

        let localSession = URLSession(
            configuration: session.configuration,
            delegate: delegate,
            delegateQueue: nil,
        )
        defer { localSession.finishTasksAndInvalidate() }

        let (_, response) = try await localSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProbeError.notHTTPResponse
        }

        let finalURL = delegate.finalURL ?? url
        return (finalURL, httpResponse)
    }

    /// Analyzes the HTTP response to determine content type.
    private func analyzeResponse(_ response: HTTPURLResponse, finalURL: URL) -> ProbeResult {
        // Use HTTPURLResponse's built-in suggestedFilename which handles Content-Disposition
        let suggestedFilename = response.suggestedFilename

        // Check Content-Disposition for "attachment"
        if let disposition = response.value(forHTTPHeaderField: "Content-Disposition") {
            let lowercased = disposition.lowercased().trimmingCharacters(in: .whitespaces)
            if lowercased.hasPrefix("attachment") {
                Logger.debug(
                    "Popup probe: attachment disposition → download",
                    category: Logger.navigation,
                )
                return .download(url: finalURL, suggestedFilename: suggestedFilename)
            }
        }

        // Check MIME type using HTTPURLResponse's mimeType property
        if let mimeType = response.mimeType?.lowercased() {
            if Self.webpageMIMETypes.contains(mimeType) {
                Logger.debug(
                    "Popup probe: webpage MIME type (\(mimeType)) → webpage",
                    category: Logger.navigation,
                )
                return .webpage(url: finalURL)
            }

            if Self.downloadMIMETypes.contains(mimeType) {
                Logger.debug(
                    "Popup probe: download MIME type (\(mimeType)) → download",
                    category: Logger.navigation,
                )
                return .download(url: finalURL, suggestedFilename: suggestedFilename)
            }

            // For non-text, non-image types, assume download
            if !mimeType.hasPrefix("text/"), !mimeType.hasPrefix("image/") {
                Logger.debug(
                    "Popup probe: binary MIME type (\(mimeType)) → download",
                    category: Logger.navigation,
                )
                return .download(url: finalURL, suggestedFilename: suggestedFilename)
            }
        }

        // If we got here with a download-like extension but webpage MIME, it's a webpage
        Logger.debug("Popup probe: treating as webpage", category: Logger.navigation)
        return .webpage(url: finalURL)
    }

    private enum ProbeError: Error {
        case notHTTPResponse
    }
}

/// URLSession delegate that tracks the final URL after redirects.
private final class RedirectTrackingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let storage = OSAllocatedUnfairLock<URL?>(initialState: nil)

    var finalURL: URL? {
        storage.withLock { $0 }
    }

    func urlSession(
        _: URLSession,
        task _: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void,
    ) {
        storage.withLock { $0 = request.url }
        completionHandler(request)
    }
}
