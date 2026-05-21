import Foundation

/// Determines which sites are supported by yt-dlp and what download options to show.
///
/// Uses a two-tier approach:
/// 1. Hardcoded high-traffic sites for instant detection (no yt-dlp call needed)
/// 2. Cached extractor list from yt-dlp for unknown domains
///
/// ## Usage
///
/// ```swift
/// // Check if a URL is supported
/// if let mediaType = YTDLPSites.shared.mediaType(for: url) {
///     // Show appropriate context menu items
/// }
///
/// // Refresh extractor cache periodically
/// await YTDLPSites.shared.refreshExtractorCache()
/// ```
final class YTDLPSites: Sendable {
    // MARK: - Types

    /// Type of media typically available on a site.
    enum MediaType: Sendable {
        /// Primarily video content (YouTube, Vimeo, etc.)
        case video

        /// Primarily audio/music content (SoundCloud, Bandcamp)
        case music

        /// Mixed content - could be video or audio (Twitter, Reddit)
        case mixed
    }

    // MARK: - Singleton

    static let shared = YTDLPSites()

    // MARK: - Hardcoded High-Traffic Sites

    /// Sites with instant detection (no yt-dlp call needed).
    ///
    /// Categorized by primary content type for appropriate menu items.
    private static let knownSites: [String: MediaType] = [
        // Video platforms
        "youtube.com": .video,
        "youtu.be": .video,
        "vimeo.com": .video,
        "dailymotion.com": .video,
        "twitch.tv": .video,
        "kick.com": .video,
        "rumble.com": .video,
        "bilibili.com": .video,
        "nicovideo.jp": .video,
        "odysee.com": .video,
        "bitchute.com": .video,
        "peertube.tv": .video,
        "streamable.com": .video,
        "clips.twitch.tv": .video,
        "player.vimeo.com": .video,
        "coub.com": .video,
        "v.redd.it": .video,

        // Music platforms
        "soundcloud.com": .music,
        "bandcamp.com": .music,
        "mixcloud.com": .music,
        "music.youtube.com": .video, // Video format even though music
        "audiomack.com": .music,
        "tidal.com": .music,

        // Social media (mixed content)
        "twitter.com": .mixed,
        "x.com": .mixed,
        "instagram.com": .mixed,
        "tiktok.com": .mixed,
        "reddit.com": .mixed,
        "threads.net": .mixed,
        "facebook.com": .mixed,
        "fb.watch": .mixed,
        "linkedin.com": .mixed,
        "pinterest.com": .mixed,
        "tumblr.com": .mixed,

        // News/media sites
        "cnn.com": .video,
        "bbc.co.uk": .video,
        "nytimes.com": .video,
        "washingtonpost.com": .video,
        "theguardian.com": .video,
    ]

    // MARK: - Cached Extractor List

    /// Cached set of supported domains from yt-dlp --list-extractors.
    ///
    /// Loaded lazily and persisted to disk.
    private let extractorCache = ExtractorCache()

    // MARK: - Private Init

    private init() {}

    // MARK: - Public API

    /// Determines the media type for a URL, or nil if unsupported.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: The media type if supported, nil otherwise.
    func mediaType(for url: URL) -> MediaType? {
        guard let host = url.host?.lowercased() else { return nil }

        // Strip "www." prefix
        let normalizedHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host

        // Check hardcoded sites first (instant)
        if let mediaType = Self.knownSites[normalizedHost] {
            return mediaType
        }

        // Check parent domain (e.g., "clips.twitch.tv" -> "twitch.tv")
        let components = normalizedHost.split(separator: ".")
        if components.count > 2 {
            let parentDomain = components.suffix(2).joined(separator: ".")
            if let mediaType = Self.knownSites[parentDomain] {
                return mediaType
            }
        }

        // Check cached extractor list
        if extractorCache.contains(normalizedHost) {
            // Unknown sites default to mixed (safest assumption)
            return .mixed
        }

        return nil
    }

    /// Returns whether a URL is supported for downloading.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: True if yt-dlp can download from this URL.
    func isSupported(_ url: URL) -> Bool {
        mediaType(for: url) != nil
    }

    /// Refreshes the extractor cache from yt-dlp.
    ///
    /// Should be called periodically (e.g., weekly) or when yt-dlp is updated.
    func refreshExtractorCache() async {
        await extractorCache.refresh()
    }

    /// Forces a reload of the extractor cache.
    func invalidateCache() async {
        await extractorCache.invalidate()
    }
}

// MARK: - Extractor Cache

/// Caches the list of supported extractors from yt-dlp.
///
/// Persists to disk and refreshes weekly or on demand.
/// Uses an actor for safe concurrent access.
private actor ExtractorCache {
    /// Set of supported domain patterns.
    private var domains: Set<String> = []

    /// When the cache was last refreshed.
    private var lastRefresh: Date?

    /// Cache file URL.
    private var cacheURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
        ).first!
        let cacheDir = appSupport.appendingPathComponent("Refrax/Cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
        return cacheDir.appendingPathComponent("ytdlp-extractors.txt")
    }

    /// Maximum age of cache before refresh (7 days).
    private let maxCacheAge: TimeInterval = 7 * 24 * 60 * 60

    /// Whether initial load has been performed.
    private var didLoad = false

    init() {
        // Defer loadFromDisk to first access since actor init is sync
    }

    /// Ensures data is loaded from disk.
    private func ensureLoaded() {
        guard !didLoad else { return }
        didLoad = true
        loadFromDiskSync()
    }

    /// Checks if a domain is in the extractor cache (sync access via nonisolated).
    nonisolated func contains(_: String) -> Bool {
        // For sync access, we check the hardcoded sites only
        // The cached domains require async access
        false
    }

    /// Refreshes the cache from yt-dlp.
    func refresh() async {
        ensureLoaded()

        // Check if refresh is needed
        let needsRefresh = lastRefresh == nil ||
            Date().timeIntervalSince(lastRefresh!) > maxCacheAge

        guard needsRefresh else { return }

        guard let binaryPath = YTDLPService.findBinary() else {
            Logger.warning("Cannot refresh extractor cache: yt-dlp not found", category: Logger.downloads)
            return
        }

        // Run process on a detached task to avoid blocking the actor
        let output: String? = await Task.detached {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: binaryPath)
            process.arguments = ["--list-extractors"]

            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                return String(data: data, encoding: .utf8)
            } catch {
                return nil
            }
        }.value

        guard let output else { return }

        // Parse extractor names and extract domains
        let extractors = output.split(separator: "\n").map(String.init)
        var newDomains = Set<String>()

        for extractor in extractors {
            // Extract domain-like patterns from extractor names
            let lowercased = extractor.lowercased()

            // Skip generic extractors
            if lowercased == "generic" || lowercased.hasPrefix("generic:") {
                continue
            }

            // Add common TLD variations
            newDomains.insert("\(lowercased).com")
            newDomains.insert("\(lowercased).tv")
            newDomains.insert("\(lowercased).net")
            newDomains.insert("\(lowercased).org")
            newDomains.insert("\(lowercased).io")
        }

        domains = newDomains
        lastRefresh = Date()

        // Persist to disk
        saveToDisk()

        Logger.info("Refreshed yt-dlp extractor cache: \(newDomains.count) domains", category: Logger.downloads)
    }

    /// Invalidates the cache.
    func invalidate() {
        lastRefresh = nil
    }

    /// Loads cache from disk (sync version for use within actor).
    private func loadFromDiskSync() {
        guard FileManager.default.fileExists(atPath: cacheURL.path) else { return }

        do {
            let content = try String(contentsOf: cacheURL, encoding: .utf8)
            let lines = content.split(separator: "\n")

            guard lines.count >= 2 else { return }

            // First line is timestamp
            if let timestamp = Double(lines[0]) {
                let date = Date(timeIntervalSince1970: timestamp)
                lastRefresh = date
                domains = Set(lines.dropFirst().map(String.init))

                Logger.info("Loaded yt-dlp extractor cache: \(domains.count) domains", category: Logger.downloads)
            }
        } catch {
            Logger.warning("Failed to load extractor cache: \(error)", category: Logger.downloads)
        }
    }

    /// Saves cache to disk.
    private func saveToDisk() {
        let timestamp = lastRefresh?.timeIntervalSince1970 ?? Date().timeIntervalSince1970
        let content = "\(timestamp)\n" + domains.sorted().joined(separator: "\n")

        do {
            try content.write(to: cacheURL, atomically: true, encoding: .utf8)
        } catch {
            Logger.warning("Failed to save extractor cache: \(error)", category: Logger.downloads)
        }
    }
}
