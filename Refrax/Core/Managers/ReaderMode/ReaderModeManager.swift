import Foundation
import Observation
import WebKit

/// Manages Reader Mode functionality for extracting and displaying article content.
///
/// `ReaderModeManager` uses Mozilla's Readability.js library to detect article-like
/// pages and extract their content for distraction-free reading. The manager handles:
///
/// - Detecting if a page is suitable for Reader Mode
/// - Extracting article content on demand
/// - Caching extracted articles per URL
/// - Managing reader preferences
///
/// ## Design Rationale
///
/// - Uses Readability.js (Apache 2.0 license) for proven article extraction
/// - Scripts run in an isolated content world to avoid page interference
/// - Per-page state allows different tabs to have independent reader states
/// - Availability check is lightweight; full extraction happens on demand
///
/// ## Integration
///
/// ReaderModeManager is created by AppDelegate and injected into the environment.
/// It requires BrowserState for configuration access and ScriptRegistry for
/// content script management.
///
/// ```swift
/// // During app setup
/// let readerModeManager = ReaderModeManager(state: browserState)
/// Task { await readerModeManager.setup() }
///
/// // Check availability after navigation
/// let isAvailable = await readerModeManager.checkAvailability(for: webPage)
///
/// // Extract and display article
/// if let article = try await readerModeManager.extractArticle(from: webPage) {
///     // Show in ReaderView
/// }
/// ```
@Observable
final class ReaderModeManager {
    // MARK: - Properties

    /// Reference to browser state for script registry access.
    private unowned let state: BrowserState

    // MARK: - State

    /// User preferences for reader appearance.
    var preferences: ReaderPreferences = .load() {
        didSet {
            preferences.save()
        }
    }

    // MARK: - Active Reader State

    /// Active reader mode state per tab page, keyed by `TabPage.id`.
    ///
    /// When a tab enters reader mode, its extracted article is stored here.
    /// WebViewContainer observes this to show/hide the reader overlay.
    private(set) var activeReaderStates: [UUID: ExtractedArticle] = [:]

    /// Checks if reader mode is active for a specific tab page.
    ///
    /// - Parameter tabPageID: The `TabPage.id` to check.
    func isReaderActive(for tabPageID: UUID) -> Bool {
        activeReaderStates[tabPageID] != nil
    }

    /// Returns the active article for a tab page, if reader mode is active.
    ///
    /// - Parameter tabPageID: The `TabPage.id` to look up.
    func activeArticle(for tabPageID: UUID) -> ExtractedArticle? {
        activeReaderStates[tabPageID]
    }

    /// Activates reader mode for a tab page with the given article.
    ///
    /// - Parameters:
    ///   - tabPageID: The `TabPage.id` to activate reader mode for.
    ///   - article: The extracted article content.
    func activateReader(for tabPageID: UUID, article: ExtractedArticle) {
        activeReaderStates[tabPageID] = article
    }

    /// Deactivates reader mode for a tab page.
    ///
    /// - Parameter tabPageID: The `TabPage.id` to deactivate reader mode for.
    func deactivateReader(for tabPageID: UUID) {
        activeReaderStates.removeValue(forKey: tabPageID)
    }

    /// Toggles reader mode for a tab page. If active, deactivates. Otherwise, extracts and activates.
    func toggleReader(for webPage: WebPage) async {
        let tabPageID = webPage.tabPage.id

        if isReaderActive(for: tabPageID) {
            deactivateReader(for: tabPageID)
        } else {
            if let article = await extractArticle(from: webPage) {
                activateReader(for: tabPageID, article: article)
            }
        }
    }

    // MARK: - Per-Page State

    /// Cached availability status per URL.
    private var availabilityCache: [URL: Bool] = [:]

    /// Cached extracted articles per URL.
    private var articleCache: [URL: ExtractedArticle] = [:]

    /// Pending extraction continuations waiting for results.
    private var pendingExtractions: [URL: CheckedContinuation<ExtractedArticle?, Never>] = [:]

    /// Pending availability checks waiting for results.
    private var pendingAvailabilityChecks: [URL: CheckedContinuation<Bool, Never>] = [:]

    // MARK: - Private State

    private var isSetUp = false
    private var availabilityScriptID: UUID?
    private var messageHandler: ReaderModeMessageHandler?

    /// Content world for scripts (isolated from page scripts).
    private let scriptWorld = WKContentWorld.world(name: "RefraxScripts")

    // MARK: - Constants

    private static let messageHandlerName = "readerMode"

    // MARK: - Initialization

    init(state: BrowserState) {
        self.state = state
    }

    // MARK: - Setup

    /// Performs async setup of the Reader Mode system.
    ///
    /// Registers scripts and message handlers. Call this during app
    /// initialization before creating any WebPages.
    func setup() async {
        guard !isSetUp else { return }
        isSetUp = true

        registerMessageHandler()
        await registerAvailabilityScript()

        Logger.info("ReaderModeManager setup complete", category: Logger.tabs)
    }

    // MARK: - Message Handler

    private func registerMessageHandler() {
        let handler = ReaderModeMessageHandler { [weak self] event in
            self?.handleEvent(event)
        }
        messageHandler = handler
        state.webPageConfiguration.userContentController.add(
            handler,
            contentWorld: scriptWorld,
            name: Self.messageHandlerName,
        )
    }

    // MARK: - Script Registration

    private func registerAvailabilityScript() async {
        guard availabilityScriptID == nil else { return }

        let scriptSource = await generateAvailabilityScript()
        let script = WKUserScript(
            source: scriptSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: scriptWorld,
        )

        availabilityScriptID = state.scriptRegistry.register(
            script,
            source: .system(name: "reader-availability"),
            priority: ScriptRegistry.Priority.system,
        )

        state.scriptRegistry.apply(to: state.webPageConfiguration.userContentController)
    }

    // MARK: - Availability Check

    /// Checks if a page is suitable for Reader Mode.
    ///
    /// Uses Readability.js's `isProbablyReaderable()` heuristic to determine
    /// if the page contains article-like content.
    ///
    /// - Parameter webPage: The WebPage to check.
    /// - Returns: Whether Reader Mode is available for this page.
    func checkAvailability(for webPage: WebPage) async -> Bool {
        guard let url = webPage.url else { return false }

        // Return cached result if available
        if let cached = availabilityCache[url] {
            return cached
        }

        // If there's already a pending check for this URL, wait for it to complete
        // rather than creating a duplicate that would leak the existing continuation.
        if pendingAvailabilityChecks[url] != nil {
            // Poll until the pending check completes (slightly longer than the 3s timeout)
            for _ in 0 ..< 12 {
                try? await Task.sleep(for: .milliseconds(300))
                if let cached = availabilityCache[url] {
                    return cached
                }
                if pendingAvailabilityChecks[url] == nil {
                    break
                }
            }
            return availabilityCache[url] ?? false
        }

        // The availability script runs automatically on page load and posts result.
        // If we don't have a result yet, trigger a manual check.
        return await withCheckedContinuation { continuation in
            pendingAvailabilityChecks[url] = continuation

            // Inject and run availability check
            let script = generateAvailabilityCheckScript()
            webPage.backingWebView.evaluateJavaScript(script, in: nil, in: scriptWorld) { _ in }

            // Timeout after 3 seconds
            Task {
                try? await Task.sleep(for: .seconds(3))
                if let pending = self.pendingAvailabilityChecks.removeValue(forKey: url) {
                    pending.resume(returning: false)
                }
            }
        }
    }

    /// Returns cached availability for a URL without triggering a check.
    func cachedAvailability(for url: URL?) -> Bool {
        guard let url else { return false }
        return availabilityCache[url] ?? false
    }

    // MARK: - Article Extraction

    /// Extracts article content from a web page.
    ///
    /// Uses Readability.js to parse the page and extract the main article content,
    /// title, byline, and other metadata.
    ///
    /// - Parameter webPage: The WebPage to extract from.
    /// - Returns: The extracted article, or nil if extraction failed.
    func extractArticle(from webPage: WebPage) async -> ExtractedArticle? {
        guard let url = webPage.url else { return nil }

        // Return cached article if available
        if let cached = articleCache[url] {
            return cached
        }

        // If there's already a pending extraction for this URL, wait for it to complete
        // rather than creating a duplicate that would leak the existing continuation.
        if pendingExtractions[url] != nil {
            // Poll until the pending extraction completes (slightly longer than the 10s timeout)
            for _ in 0 ..< 35 {
                try? await Task.sleep(for: .milliseconds(300))
                if let cached = articleCache[url] {
                    return cached
                }
                if pendingExtractions[url] == nil {
                    break
                }
            }
            return articleCache[url]
        }

        // Generate extraction script on background thread before entering continuation
        let script = await generateExtractionScript()

        return await withCheckedContinuation { continuation in
            pendingExtractions[url] = continuation

            // Inject and run extraction
            webPage.backingWebView.evaluateJavaScript(script, in: nil, in: scriptWorld) { _ in }

            // Timeout after 10 seconds
            Task {
                try? await Task.sleep(for: .seconds(10))
                if let pending = self.pendingExtractions.removeValue(forKey: url) {
                    pending.resume(returning: nil)
                }
            }
        }
    }

    /// Returns cached article for a URL without triggering extraction.
    func cachedArticle(for url: URL?) -> ExtractedArticle? {
        guard let url else { return nil }
        return articleCache[url]
    }

    /// Clears cached data for a URL.
    ///
    /// Call this when a page is reloaded or navigated away from.
    func clearCache(for url: URL) {
        availabilityCache.removeValue(forKey: url)
        articleCache.removeValue(forKey: url)
    }

    /// Clears all cached data.
    func clearAllCaches() {
        availabilityCache.removeAll()
        articleCache.removeAll()
    }

    // MARK: - Script Generation

    private func generateAvailabilityScript() async -> String {
        guard let readabilityURL = Bundle.main.url(forResource: "Readability-readerable", withExtension: "js") else {
            Logger.error("Failed to load Readability-readerable.js", category: Logger.tabs)
            return ""
        }

        // Load script file on background thread to avoid blocking main thread
        let readabilitySource: String? = await Task.detached(priority: .userInitiated) {
            try? String(contentsOf: readabilityURL, encoding: .utf8)
        }.value

        guard let readabilitySource else {
            Logger.error("Failed to load Readability-readerable.js", category: Logger.tabs)
            return ""
        }

        return """
        (() => {
            'use strict';
        
            // Readability-readerable.js
            \(readabilitySource)
        
            // Check availability after page loads
            function checkAvailability() {
                try {
                    const isReaderable = isProbablyReaderable(document, {
                        minContentLength: 140,
                        minScore: 20
                    });
                    window.webkit.messageHandlers.\(Self.messageHandlerName).postMessage({
                        type: 'availability',
                        available: isReaderable,
                        url: location.href
                    });
                } catch (e) {
                    window.webkit.messageHandlers.\(Self.messageHandlerName).postMessage({
                        type: 'availability',
                        available: false,
                        url: location.href,
                        error: e.message
                    });
                }
            }
        
            // Run check when DOM is ready
            if (document.readyState === 'complete' || document.readyState === 'interactive') {
                setTimeout(checkAvailability, 100);
            } else {
                document.addEventListener('DOMContentLoaded', () => setTimeout(checkAvailability, 100));
            }
        })();
        """
    }

    private func generateAvailabilityCheckScript() -> String {
        """
        (() => {
            'use strict';
            try {
                if (typeof isProbablyReaderable === 'function') {
                    const isReaderable = isProbablyReaderable(document, {
                        minContentLength: 140,
                        minScore: 20
                    });
                    window.webkit.messageHandlers.\(Self.messageHandlerName).postMessage({
                        type: 'availability',
                        available: isReaderable,
                        url: location.href
                    });
                }
            } catch (e) {}
        })();
        """
    }

    private func generateExtractionScript() async -> String {
        guard let readabilityURL = Bundle.main.url(forResource: "Readability", withExtension: "js") else {
            Logger.error("Failed to load Readability.js", category: Logger.tabs)
            return ""
        }

        // Load script file on background thread to avoid blocking main thread
        let readabilitySource: String? = await Task.detached(priority: .userInitiated) {
            try? String(contentsOf: readabilityURL, encoding: .utf8)
        }.value

        guard let readabilitySource else {
            Logger.error("Failed to load Readability.js", category: Logger.tabs)
            return ""
        }

        return """
        (() => {
            'use strict';
        
            // Readability.js
            \(readabilitySource)
        
            try {
                // Clone document to avoid modifying the original
                const documentClone = document.cloneNode(true);
                const reader = new Readability(documentClone);
                const article = reader.parse();
        
                if (article) {
                    window.webkit.messageHandlers.\(Self.messageHandlerName).postMessage({
                        type: 'extracted',
                        url: location.href,
                        article: {
                            title: article.title || '',
                            byline: article.byline || null,
                            content: article.content || '',
                            textContent: article.textContent || '',
                            excerpt: article.excerpt || null,
                            siteName: article.siteName || null,
                            publishedTime: article.publishedTime || null
                        }
                    });
                } else {
                    window.webkit.messageHandlers.\(Self.messageHandlerName).postMessage({
                        type: 'extracted',
                        url: location.href,
                        article: null,
                        error: 'Extraction returned null'
                    });
                }
            } catch (e) {
                window.webkit.messageHandlers.\(Self.messageHandlerName).postMessage({
                    type: 'extracted',
                    url: location.href,
                    article: null,
                    error: e.message
                });
            }
        })();
        """
    }

    // MARK: - Event Handling

    private func handleEvent(_ event: ReaderModeEvent) {
        switch event {
        case let .availability(urlString, available):
            guard let url = URL(string: urlString) else { return }
            availabilityCache[url] = available

            // Resume any pending availability check
            if let continuation = pendingAvailabilityChecks.removeValue(forKey: url) {
                continuation.resume(returning: available)
            }

        case let .extracted(urlString, articleJSON):
            guard let url = URL(string: urlString) else { return }

            var article: ExtractedArticle?
            if let json = articleJSON {
                article = ExtractedArticle.from(json: json, sourceURL: url)
            }

            if let article {
                articleCache[url] = article
            }

            // Resume any pending extraction
            if let continuation = pendingExtractions.removeValue(forKey: url) {
                continuation.resume(returning: article)
            }

        case let .error(urlString, message):
            Logger.error(
                "Reader Mode error for \(urlString): \(message)",
                category: Logger.tabs,
            )
        }
    }
}

// MARK: - Event Types

enum ReaderModeEvent {
    case availability(url: String, available: Bool)
    case extracted(url: String, article: [String: Any]?)
    case error(url: String, message: String)
}

// MARK: - Message Handler

final class ReaderModeMessageHandler: NSObject, WKScriptMessageHandler {
    private let onEvent: (ReaderModeEvent) -> Void

    init(onEvent: @escaping (ReaderModeEvent) -> Void) {
        self.onEvent = onEvent
    }

    func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any],
              let type = body["type"] as? String,
              let urlString = body["url"] as? String
        else { return }

        switch type {
        case "availability":
            let available = body["available"] as? Bool ?? false
            onEvent(.availability(url: urlString, available: available))

        case "extracted":
            let article = body["article"] as? [String: Any]
            onEvent(.extracted(url: urlString, article: article))

        case "error":
            let message = body["error"] as? String ?? "Unknown error"
            onEvent(.error(url: urlString, message: message))

        default:
            break
        }
    }
}
