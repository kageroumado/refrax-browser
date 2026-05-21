import Foundation
import WebKit

/// Service for yt-dlp video downloads.
///
/// Handles binary discovery, cookie export, and download coordination.
///
/// ## Binary Discovery
///
/// yt-dlp is not bundled with the app — users install it via Homebrew.
/// The service checks well-known system paths and `PATH` for the binary.
///
/// ## Cookie Export
///
/// Cookies are exported from WKWebView's cookie store in Netscape format
/// for authenticated downloads (age-restricted content, private playlists).
///
/// ## Usage
///
/// ```swift
/// let service = YTDLPService.shared
///
/// // Check if yt-dlp is available
/// guard service.isAvailable else {
///     // Show install instructions
///     return
/// }
///
/// // Start a download
/// let task = try await service.createDownloadTask(
///     url: videoURL,
///     mode: .video,
///     destination: downloadDirectory,
///     dataStore: webView.configuration.websiteDataStore
/// )
/// ```
actor YTDLPService {
    // MARK: - Types

    /// Download mode determining output format.
    enum DownloadMode: String, Codable, Sendable {
        /// Best video + best audio merged into mp4.
        case video

        /// Video only, no audio track (for editing/bandwidth).
        case videoOnly

        /// Audio extracted to mp3.
        case audioOnly

        /// Same as video, then import to Photos library.
        case saveToPhotos
    }

    /// Video information extracted by yt-dlp.
    struct VideoInfo: Sendable {
        let title: String
        let duration: TimeInterval?
        let uploader: String?
        let thumbnailURL: URL?
        let fileExtension: String
        let estimatedSize: Int64?
    }

    // MARK: - Singleton

    /// Shared service instance.
    static let shared = YTDLPService()

    // MARK: - Properties

    /// Cached binary path.
    private var cachedBinaryPath: String?

    /// Cached yt-dlp version.
    private var cachedVersion: String?

    // MARK: - Initialization

    private init() {}

    // MARK: - Binary Discovery

    /// Whether yt-dlp is available.
    var isAvailable: Bool {
        get async {
            await binaryPath() != nil
        }
    }

    /// Returns the path to the yt-dlp binary.
    ///
    /// Caches the result after first lookup.
    func binaryPath() async -> String? {
        if let cached = cachedBinaryPath {
            return cached
        }

        let path = Self.findBinary()
        cachedBinaryPath = path
        return path
    }

    /// Finds the yt-dlp binary on the system.
    ///
    /// Checks Homebrew paths, common system locations, and `PATH`.
    /// yt-dlp is not bundled — users install it via Homebrew or manually.
    ///
    /// - Returns: The binary path if found, nil otherwise.
    nonisolated static func findBinary() -> String? {
        let fm = FileManager.default
        let systemPaths = [
            "/opt/homebrew/bin/yt-dlp",
            "/usr/local/bin/yt-dlp",
            "/usr/bin/yt-dlp",
        ]

        for path in systemPaths {
            if fm.isExecutableFile(atPath: path) {
                return path
            }
        }

        // PATH fallback
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["yt-dlp"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !path.isEmpty, fm.isExecutableFile(atPath: path) else { return nil }
            return path
        } catch {
            return nil
        }
    }

    /// Installs yt-dlp via Homebrew.
    ///
    /// - Returns: The installed version string on success.
    /// - Throws: If Homebrew is not found or installation fails.
    nonisolated static func installWithHomebrew() async throws -> String {
        let brewPath = findHomebrew()
        guard let brewPath else {
            throw YTDLPError.processFailed(
                exitCode: 1,
                stderr: "Homebrew not found. Install it from https://brew.sh",
            )
        }

        let (_, stderr, exitCode) = await runProcess(brewPath, arguments: ["install", "yt-dlp"])

        guard exitCode == 0 else {
            throw YTDLPError.processFailed(exitCode: exitCode, stderr: stderr)
        }

        // Verify installation and get version
        guard let binary = findBinary() else {
            throw YTDLPError.processFailed(
                exitCode: 1,
                stderr: "yt-dlp was installed but binary not found in PATH",
            )
        }

        let (stdout, _, versionExit) = await runProcess(binary, arguments: ["--version"])
        guard versionExit == 0 else {
            return "installed"
        }

        return stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Clears the cached binary path so the next lookup re-discovers it.
    func invalidateBinaryCache() {
        cachedBinaryPath = nil
        cachedVersion = nil
    }

    // MARK: - Homebrew

    private nonisolated static func findHomebrew() -> String? {
        let paths = [
            "/opt/homebrew/bin/brew",
            "/usr/local/bin/brew",
        ]
        return paths.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    private nonisolated static func runProcess(
        _ path: String,
        arguments: [String],
    ) async -> (stdout: String, stderr: String, exitCode: Int32) {
        await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try? process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            return (
                String(data: stdoutData, encoding: .utf8) ?? "",
                String(data: stderrData, encoding: .utf8) ?? "",
                process.terminationStatus
            )
        }.value
    }

    /// Gets the yt-dlp version string.
    func version() async throws -> String {
        if let cached = cachedVersion {
            return cached
        }

        guard let binaryPath = await binaryPath() else {
            throw YTDLPError.notInstalled
        }

        let versionOutput: String? = await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = ["--version"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            try? process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }.value

        guard let version = versionOutput else {
            throw YTDLPError.parseError("Could not parse version")
        }

        cachedVersion = version
        return version
    }

    // MARK: - Cookie Export

    /// Exports cookies from a WKWebsiteDataStore in Netscape format.
    ///
    /// The cookie file is written to a temporary location and should be
    /// deleted after the download completes.
    ///
    /// - Parameters:
    ///   - dataStore: The WebKit data store containing cookies.
    ///   - domains: Domains to include (e.g., ["youtube.com", "google.com"]).
    /// - Returns: Path to the cookie file, or nil if no relevant cookies.
    @MainActor
    func exportCookies(
        from dataStore: WKWebsiteDataStore,
        forDomains domains: [String],
    ) async -> URL? {
        let cookies = await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }

        // Filter cookies for relevant domains
        let relevantCookies = cookies.filter { cookie in
            let cookieDomain = cookie.domain.lowercased()
            return domains.contains { domain in
                let normalizedDomain = domain.lowercased()
                if cookieDomain.hasPrefix(".") {
                    return cookieDomain == ".\(normalizedDomain)" ||
                        cookieDomain.hasSuffix(".\(normalizedDomain)")
                } else {
                    return cookieDomain == normalizedDomain ||
                        cookieDomain.hasSuffix(".\(normalizedDomain)")
                }
            }
        }

        guard !relevantCookies.isEmpty else { return nil }

        // Convert to Netscape format
        var lines = ["# Netscape HTTP Cookie File"]
        lines.append("# https://curl.se/docs/http-cookies.html")
        lines.append("")

        for cookie in relevantCookies {
            let domain = cookie.domain.hasPrefix(".") ? cookie.domain : ".\(cookie.domain)"
            let includeSubdomains = domain.hasPrefix(".") ? "TRUE" : "FALSE"
            let path = cookie.path.isEmpty ? "/" : cookie.path
            let secure = cookie.isSecure ? "TRUE" : "FALSE"
            let expiry = cookie.expiresDate.map { Int($0.timeIntervalSince1970) } ?? 0
            let name = cookie.name
            let value = cookie.value

            lines.append("\(domain)\t\(includeSubdomains)\t\(path)\t\(secure)\t\(expiry)\t\(name)\t\(value)")
        }

        // Write to temp file
        let tempDir = FileManager.default.temporaryDirectory
        let cookieFile = tempDir.appendingPathComponent("ytdlp-cookies-\(UUID().uuidString).txt")

        do {
            try lines.joined(separator: "\n").write(to: cookieFile, atomically: true, encoding: .utf8)
            return cookieFile
        } catch {
            Logger.warning("Failed to write cookie file: \(error)", category: Logger.downloads)
            return nil
        }
    }

    /// Deletes a cookie file after download completes.
    nonisolated func deleteCookieFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Video Info Extraction

    /// Extracts video information without downloading.
    ///
    /// - Parameters:
    ///   - url: The video URL.
    ///   - cookieFile: Optional cookie file for authenticated content.
    /// - Returns: Video information.
    func extractVideoInfo(from url: URL, cookieFile: URL? = nil) async throws -> VideoInfo {
        guard let binaryPath = await binaryPath() else {
            throw YTDLPError.notInstalled
        }

        var arguments = [
            "--dump-json",
            "--no-playlist", // Single video only
            url.absoluteString,
        ]

        if let cookieFile {
            arguments.insert(contentsOf: ["--cookies", cookieFile.path], at: 0)
        }

        let result: (stdout: Data, stderr: Data, exitCode: Int32) = await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = arguments

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            try? process.run()
            process.waitUntilExit()

            let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
            let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()

            return (stdoutData, stderrData, process.terminationStatus)
        }.value

        if result.exitCode != 0 {
            let stderr = String(data: result.stderr, encoding: .utf8) ?? ""
            if let parsedError = YTDLPError.parse(from: stderr) {
                throw parsedError
            }
            throw YTDLPError.processFailed(exitCode: result.exitCode, stderr: stderr)
        }

        // Parse JSON output
        guard let json = try? JSONSerialization.jsonObject(with: result.stdout) as? [String: Any] else {
            throw YTDLPError.parseError("Invalid JSON response")
        }

        let title = json["title"] as? String ?? "Unknown"
        let duration = json["duration"] as? Double
        let uploader = json["uploader"] as? String
        let thumbnail = (json["thumbnail"] as? String).flatMap { URL(string: $0) }
        let ext = json["ext"] as? String ?? "mp4"
        let filesize = json["filesize"] as? Int64 ?? json["filesize_approx"] as? Int64

        return VideoInfo(
            title: title,
            duration: duration,
            uploader: uploader,
            thumbnailURL: thumbnail,
            fileExtension: ext,
            estimatedSize: filesize,
        )
    }

    // MARK: - Download Task Management

    /// Creates a download task for a video URL.
    ///
    /// Must be called from MainActor to access cookie store.
    ///
    /// - Parameters:
    ///   - url: The video URL.
    ///   - mode: The download mode (video, audio, etc.).
    ///   - destination: The destination directory.
    ///   - dataStore: WebKit data store for cookie export (optional).
    ///   - useCookies: Whether to export and use browser cookies.
    /// - Returns: The created download task.
    @MainActor
    func createDownloadTask(
        url: URL,
        mode: DownloadMode,
        destination: URL,
        dataStore: WKWebsiteDataStore? = nil,
        useCookies: Bool = true,
    ) async throws -> YTDLPDownloadTask {
        guard let binaryPath = Self.findBinary() else {
            throw YTDLPError.notInstalled
        }

        // Export cookies if requested (already on MainActor)
        var cookieFile: URL?
        if useCookies, let dataStore {
            // Get domains for cookie filtering based on URL
            let domains = Self.cookieDomainsForURL(url)
            cookieFile = await exportCookies(from: dataStore, forDomains: domains)
        }

        let task = YTDLPDownloadTask(
            url: url,
            mode: mode,
            binaryPath: binaryPath,
            destinationDirectory: destination,
            cookieFile: cookieFile,
        )

        return task
    }

    // MARK: - Private Helpers

    /// Returns relevant cookie domains for a URL.
    private nonisolated static func cookieDomainsForURL(_ url: URL) -> [String] {
        guard let host = url.host?.lowercased() else { return [] }

        // Map specific sites to their auth domains
        if host.contains("youtube") || host.contains("youtu.be") {
            return ["youtube.com", "google.com", "accounts.google.com"]
        }
        if host.contains("twitter") || host.contains("x.com") {
            return ["twitter.com", "x.com"]
        }
        if host.contains("instagram") {
            return ["instagram.com", "facebook.com"]
        }
        if host.contains("tiktok") {
            return ["tiktok.com"]
        }
        if host.contains("vimeo") {
            return ["vimeo.com"]
        }
        if host.contains("twitch") {
            return ["twitch.tv"]
        }
        if host.contains("soundcloud") {
            return ["soundcloud.com"]
        }
        if host.contains("reddit") || host.contains("redd.it") {
            return ["reddit.com"]
        }

        // Default: use the host itself
        let normalizedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return [normalizedHost]
    }
}
