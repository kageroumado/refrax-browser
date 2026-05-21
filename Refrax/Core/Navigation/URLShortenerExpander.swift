import Foundation
import OrderedCollections
import os
import WebKit

/// Expands shortened URLs by following redirects without cookies.
///
/// URL shorteners like bit.ly, t.co, and tinyurl.com obscure the final destination
/// of links. This actor safely expands them by:
///
/// 1. Making a HEAD request without cookies to follow redirects
/// 2. Extracting the final destination URL
/// 3. Caching results to avoid redundant network requests
///
/// ## Privacy Approach
///
/// Unlike typical navigation, shortened URL expansion:
/// - Uses an ephemeral URLSession (no cookies, no cache)
/// - Only performs HEAD requests (no body content downloaded)
/// - Times out quickly to avoid blocking navigation
/// - Doesn't execute JavaScript or load resources
///
/// ## Usage
///
/// ```swift
/// if let expandedURL = await URLShortenerExpander.shared.expand(shortURL) {
///     // Navigate to expandedURL instead
/// }
/// ```
actor URLShortenerExpander {
    static let shared = URLShortenerExpander()

    // MARK: - Known Shorteners

    /// Domains known to be URL shorteners.
    ///
    /// This list covers major URL shortening services. URLs from these domains
    /// will be expanded automatically when the feature is enabled.
    private static let shortenerDomains: Set<String> = [
        // Major shorteners
        "bit.ly",
        "bitly.com",
        "t.co",
        "tinyurl.com",
        "goo.gl",
        "ow.ly",
        "is.gd",
        "buff.ly",
        "j.mp",
        "soo.gd",
        "s2r.co",
        "clicky.me",
        "budurl.com",
        "bc.vc",

        // Social media shorteners
        "fb.me",
        "fb.watch",
        "lnkd.in",
        "redd.it",
        "v.gd",

        // News/media shorteners
        "nyti.ms",
        "wapo.st",
        "on.wsj.com",
        "cnn.it",
        "bbc.in",
        "reut.rs",
        "bloom.bg",

        // Tech shorteners
        "amzn.to",
        "amzn.com",
        "a.co",
        "g.co",
        "apple.co",
        "msft.it",
        "aka.ms",
        "git.io",

        // Other popular shorteners
        "cutt.ly",
        "shorturl.at",
        "rb.gy",
        "trib.al",
        "dlvr.it",
        "zpr.io",
        "shor.by",
        "tiny.cc",
        "clck.ru",
        "qps.ru",
        "1url.com",
        "hyperurl.co",
    ]

    // MARK: - Properties

    /// LRU cache for expanded URLs using OrderedDictionary.
    ///
    /// Maintains insertion order for proper LRU eviction. Most recently
    /// accessed entries are moved to the end.
    private var cache: OrderedDictionary<URL, URL> = [:]

    /// Maximum cache size to prevent unbounded memory growth.
    private let maxCacheSize = 500

    /// In-flight expansion requests to avoid duplicate network calls.
    ///
    /// When multiple callers request expansion of the same URL concurrently,
    /// only one network request is made and all callers await the same result.
    private var inFlightRequests: [URL: Task<URL?, Never>] = [:]

    /// Ephemeral session for privacy-preserving requests.
    private let session: URLSession

    // MARK: - Initialization

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData

        // Set a custom user agent to appear as a regular browser
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
        ]

        self.session = URLSession(configuration: config)
    }

    // MARK: - Public API

    /// Checks if a URL is from a known URL shortener.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: `true` if the URL's host matches a known shortener domain.
    nonisolated static func isShortenerURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }

        // Check exact match
        if shortenerDomains.contains(host) {
            return true
        }

        // Check with www. prefix removed
        let withoutWWW = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        return shortenerDomains.contains(withoutWWW)
    }

    /// Expands a shortened URL by following redirects.
    ///
    /// Makes a HEAD request to the URL and follows redirects to find the
    /// final destination. Uses an ephemeral session without cookies.
    ///
    /// - Parameters:
    ///   - url: The shortened URL to expand.
    ///   - timeout: Maximum time to wait for expansion (default from settings).
    /// - Returns: The expanded URL, or `nil` if expansion failed or timed out.
    func expand(_ url: URL, timeout: TimeInterval = 5.0) async -> URL? {
        // Check cache first (and update LRU order on hit)
        if let cached = cache.removeValue(forKey: url) {
            // Re-insert at end for LRU ordering
            cache[url] = cached
            return cached
        }

        // Only expand known shortener URLs
        guard Self.isShortenerURL(url) else {
            return nil
        }

        // Check for in-flight request to avoid duplicate network calls
        if let existingTask = inFlightRequests[url] {
            return await existingTask.value
        }

        // Create a new expansion task
        let task = Task<URL?, Never> {
            await performExpansion(url, timeout: timeout)
        }

        inFlightRequests[url] = task
        let result = await task.value
        inFlightRequests.removeValue(forKey: url)

        return result
    }

    /// Performs the actual URL expansion network request.
    private func performExpansion(_ url: URL, timeout: TimeInterval) async -> URL? {
        do {
            let expandedURL = try await followRedirects(url, timeout: timeout)

            // Don't cache if we got the same URL back
            guard expandedURL != url else {
                return nil
            }

            // Cache the result
            cacheResult(original: url, expanded: expandedURL)

            Logger.debug(
                "Expanded URL: \(url.host ?? "") → \(expandedURL.host ?? "")",
                category: Logger.navigation,
            )

            return expandedURL
        } catch {
            Logger.debug(
                "Failed to expand URL \(url.absoluteString): \(error.localizedDescription)",
                category: Logger.navigation,
            )
            return nil
        }
    }

    /// Clears the expansion cache.
    func clearCache() {
        cache.removeAll()
    }

    // MARK: - Private

    /// Follows redirects to find the final URL.
    private func followRedirects(_ url: URL, timeout: TimeInterval) async throws -> URL {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = timeout

        // Create a delegate that captures redirects
        let delegate = RedirectCapturingDelegate()

        let localSession = URLSession(
            configuration: session.configuration,
            delegate: delegate,
            delegateQueue: nil,
        )
        defer { localSession.finishTasksAndInvalidate() }

        // Make the request - we don't care about the response, just the redirects
        _ = try await localSession.data(for: request)

        // Return the final URL from the delegate, or original if no redirects
        return delegate.finalURL ?? url
    }

    /// Caches an expansion result, evicting old entries if needed.
    private func cacheResult(original: URL, expanded: URL) {
        // Evict oldest entries if cache is full (LRU: front of OrderedDictionary is oldest)
        if cache.count >= maxCacheSize {
            let toRemove = maxCacheSize / 5
            cache.removeFirst(toRemove)
        }

        cache[original] = expanded
    }
}

// MARK: - Redirect Capturing Delegate

/// URLSession delegate that captures the final URL after redirects.
///
/// Thread-safe access to `finalURL` is ensured via `OSAllocatedUnfairLock`.
private final class RedirectCapturingDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    /// Thread-safe storage for the final URL.
    private let storage = OSAllocatedUnfairLock<URL?>(initialState: nil)

    /// Thread-safe accessor for the final URL.
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
        // Track the redirect destination (thread-safe)
        storage.withLock { $0 = request.url }

        // Continue following redirects
        completionHandler(request)
    }

    func urlSession(_: URLSession, task: URLSessionTask, didFinishCollecting _: URLSessionTaskMetrics) {
        // Capture final URL from response if we haven't already
        storage.withLock { url in
            if url == nil {
                url = task.currentRequest?.url
            }
        }
    }
}

// MARK: - URL Extension

extension URL {
    /// Whether this URL is from a known URL shortener service.
    var isShortenerURL: Bool {
        URLShortenerExpander.isShortenerURL(self)
    }
}
