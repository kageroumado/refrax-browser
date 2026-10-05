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
/// - Availability check is lightweight and capped by element count; full extraction happens on demand
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
/// if case let .article(article) = await readerModeManager.extractArticle(from: webPage) {
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
    ///
    /// - Returns: The extraction outcome when Reader was opening, or `nil` when it closed.
    @discardableResult
    func toggleReader(for webPage: WebPage) async -> ReaderExtraction? {
        let tabPageID = webPage.tabPage.id

        if isReaderActive(for: tabPageID) {
            deactivateReader(for: tabPageID)
            return nil
        }
        let extraction = await extractArticle(from: webPage)
        if case let .article(article) = extraction {
            activateReader(for: tabPageID, article: article)
        }
        return extraction
    }

    // MARK: - Limits

    /// Bounds on the work Reader does in a page, so a huge page costs a quick refusal
    /// instead of seconds of parsing.
    enum Limits {
        /// Pages with more DOM elements than this are too long for Reader. Both the
        /// availability check and extraction count elements (under 1 ms even at 335,000)
        /// before running Readability, whose parse grows with the element count: on an
        /// M1 Max, 48 ms at 8,000 elements, 275 ms at 49,000, 1.8 s at 335,000 (the
        /// single-page HTML spec), and 2.5 s at 120,000 in a deeply nested HN thread. This
        /// bound keeps the nested case near 1 s. Text length tracks the element count on
        /// these pages, so it gets no limit of its own.
        static let maxElements = 50_000

        /// How long extraction may run before Reader gives up and reports the page as too long.
        static let extractionTimeout: Duration = .seconds(5)

        /// How long a manual availability check may run before it reports the page as unavailable.
        static let availabilityTimeout: Duration = .seconds(3)
    }

    // MARK: - Per-Page State

    /// Cached availability status per URL.
    private var availabilityCache: [URL: Bool] = [:]

    /// Cached extracted articles per URL.
    private var articleCache: [URL: ExtractedArticle] = [:]

    /// Running availability checks, shared by every caller asking about the same URL.
    private var availabilityChecks: [URL: Task<Bool, Never>] = [:]

    /// Running extractions, shared by every caller asking about the same URL.
    private var extractions: [URL: Task<ReaderExtraction, Never>] = [:]

    // MARK: - Private State

    private var isSetUp = false
    private var availabilityScriptID: UUID?

    /// The extraction script, built once from the bundled Readability.js.
    private var extractionScript: String?

    /// Content world for scripts (isolated from page scripts).
    private static let scriptWorldName = "RefraxScripts"
    private let scriptWorld = WKContentWorld.world(name: scriptWorldName)

    // MARK: - Constants

    private static let messageHandlerName = "readerMode"

    /// The function the availability script defines in the reader content world.
    private static let availabilityFunctionName = "refraxReaderAvailable"

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
        state.scriptChannels.register(Self.messageHandlerName, world: .isolated(name: Self.scriptWorldName)) { [weak self] message, _ in
            guard let event = ReaderModeEvent(message.body) else { return }
            self?.handleEvent(event)
        }
    }

    // MARK: - Script Registration

    private func registerAvailabilityScript() async {
        guard availabilityScriptID == nil,
              let readerableSource = await Self.loadScript(named: "Readability-readerable")
        else { return }

        let script = WKUserScript(
            source: Self.availabilityScript(readerableSource: readerableSource),
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
            in: scriptWorld,
        )

        availabilityScriptID = state.scriptRegistry.register(
            script,
            source: .system(name: "reader-availability"),
            priority: ScriptRegistry.Priority.system,
            world: scriptWorld,
        )

        state.scriptRegistry.apply(to: state.webPageConfiguration.userContentController)
    }

    // MARK: - Availability Check

    /// Checks if a page is suitable for Reader Mode.
    ///
    /// Uses Readability.js's `isProbablyReaderable()` heuristic to determine
    /// if the page contains article-like content. Pages above ``Limits/maxElements``
    /// are unavailable.
    ///
    /// - Parameter webPage: The WebPage to check.
    /// - Returns: Whether Reader Mode is available for this page.
    func checkAvailability(for webPage: WebPage) async -> Bool {
        guard let url = webPage.url else { return false }

        if let cached = availabilityCache[url] {
            return cached
        }
        if let running = availabilityChecks[url] {
            return await running.value
        }

        let check = Task {
            let script = "typeof \(Self.availabilityFunctionName) === 'function' && \(Self.availabilityFunctionName)()"
            let evaluation: ScriptEvaluation<Bool> = await evaluate(script, in: webPage, timeout: Limits.availabilityTimeout)
            guard case let .finished(available) = evaluation else { return false }
            return available ?? false
        }
        availabilityChecks[url] = check
        let available = await check.value
        availabilityChecks[url] = nil
        availabilityCache[url] = available
        return available
    }

    /// Returns cached availability for a URL without triggering a check.
    func cachedAvailability(for url: URL?) -> Bool {
        guard let url else { return false }
        return availabilityCache[url] ?? false
    }

    // MARK: - Article Extraction

    /// Extracts article content from a web page.
    ///
    /// Readability.js parses a copy of the page in the web content process; the report it
    /// returns is decoded, and the article's statistics computed, off the main actor. A page
    /// above ``Limits/maxElements``, or one whose extraction outlasts
    /// ``Limits/extractionTimeout``, is reported as ``ReaderExtraction/tooLong`` and marked
    /// unavailable.
    ///
    /// - Parameter webPage: The WebPage to extract from.
    func extractArticle(from webPage: WebPage) async -> ReaderExtraction {
        guard let url = webPage.url else { return .failed }

        if let cached = articleCache[url] {
            return .article(cached)
        }
        if let running = extractions[url] {
            return await running.value
        }

        let extraction = Task { await runExtraction(in: webPage, url: url) }
        extractions[url] = extraction
        let result = await extraction.value
        extractions[url] = nil

        switch result {
        case let .article(article):
            articleCache[url] = article
        case .tooLong:
            availabilityCache[url] = false
        case .failed:
            break
        }
        return result
    }

    private func runExtraction(in webPage: WebPage, url: URL) async -> ReaderExtraction {
        guard let script = await loadExtractionScript() else { return .failed }

        let evaluation: ScriptEvaluation<String> = await evaluate(script, in: webPage, timeout: Limits.extractionTimeout)
        switch evaluation {
        case let .finished(report?):
            return await ReaderExtraction.decode(report, sourceURL: url)
        case .finished(nil):
            return .failed
        case .timedOut:
            Logger.info("Reader extraction timed out after \(Limits.extractionTimeout)", category: Logger.tabs)
            return .tooLong
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

    // MARK: - Script Evaluation

    /// A script's result, or the timeout that passed first.
    private enum ScriptEvaluation<Value: Sendable>: Sendable {
        case finished(Value?)
        case timedOut
    }

    /// Evaluates `script` in the reader content world, giving up after `timeout`.
    ///
    /// A continuation rather than `withTimeout(seconds:operation:)`: a task group returns only
    /// once every child has, and WebKit cannot cancel a script that is running, so the group
    /// would wait out the whole evaluation. Past the timeout the script keeps running in the
    /// web content process; only the wait ends.
    private func evaluate<Value: Sendable>(
        _ script: String,
        in webPage: WebPage,
        timeout: Duration,
    ) async -> ScriptEvaluation<Value> {
        await withCheckedContinuation { continuation in
            let race = FirstFinisher(continuation)
            race.timer = Task {
                try? await Task.sleep(for: timeout)
                race.finish(with: .timedOut)
            }
            Task {
                let result = try? await webPage.evaluateJavaScript(script, contentWorld: scriptWorld)
                race.finish(with: .finished(result as? Value))
            }
        }
    }

    // MARK: - Script Generation

    /// Reads a bundled script off the main actor.
    @concurrent
    private static func loadScript(named name: String) async -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            Logger.error("Failed to load \(name).js", category: Logger.tabs)
            return nil
        }
        return source
    }

    private func loadExtractionScript() async -> String? {
        if let extractionScript {
            return extractionScript
        }
        guard let readabilitySource = await Self.loadScript(named: "Readability") else { return nil }
        let script = Self.extractionScript(readabilitySource: readabilitySource)
        extractionScript = script
        return script
    }

    /// Defines the availability function in the reader content world and reports the
    /// result once the DOM is ready.
    private static func availabilityScript(readerableSource: String) -> String {
        """
        (() => {
            'use strict';
        
            // Readability-readerable.js
            \(readerableSource)
        
            function isReaderAvailable() {
                try {
                    if (document.getElementsByTagName('*').length > \(Limits.maxElements)) {
                        return false;
                    }
                    return isProbablyReaderable(document, {
                        minContentLength: 140,
                        minScore: 20
                    });
                } catch (e) {
                    return false;
                }
            }
        
            // ReaderModeManager.checkAvailability calls this from the same content world.
            window.\(availabilityFunctionName) = isReaderAvailable;
        
            function reportAvailability() {
                window.webkit.messageHandlers.\(messageHandlerName).postMessage({
                    type: 'availability',
                    available: isReaderAvailable(),
                    url: location.href
                });
            }
        
            if (document.readyState === 'complete' || document.readyState === 'interactive') {
                setTimeout(reportAvailability, 100);
            } else {
                document.addEventListener('DOMContentLoaded', () => setTimeout(reportAvailability, 100));
            }
        })();
        """
    }

    /// Runs Readability on a copy of the page and returns a JSON report for
    /// ``ReaderExtraction/decode(_:sourceURL:)``.
    private static func extractionScript(readabilitySource: String) -> String {
        """
        (() => {
            'use strict';
        
            // Readability.js
            \(readabilitySource)
        
            const maxElements = \(Limits.maxElements);
            try {
                if (document.getElementsByTagName('*').length > maxElements) {
                    return JSON.stringify({ status: 'tooLong' });
                }
                const reader = new Readability(document.cloneNode(true), { maxElemsToParse: maxElements });
                const article = reader.parse();
                if (!article) {
                    return JSON.stringify({ status: 'failed' });
                }
                return JSON.stringify({
                    status: 'extracted',
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
            } catch (e) {
                // Readability throws "Aborting parsing document; N elements found" past maxElemsToParse.
                const tooLong = String(e && e.message).startsWith('Aborting parsing document');
                return JSON.stringify({ status: tooLong ? 'tooLong' : 'failed' });
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
        }
    }
}

// MARK: - First Finisher

/// Resumes a continuation with the first of several racing results and drops the rest.
private final class FirstFinisher<Value: Sendable> {
    private var continuation: CheckedContinuation<Value, Never>?

    /// The timeout task, cancelled once a result arrives.
    var timer: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<Value, Never>) {
        self.continuation = continuation
    }

    func finish(with value: Value) {
        guard let continuation else { return }
        self.continuation = nil
        timer?.cancel()
        continuation.resume(returning: value)
    }
}

// MARK: - Event Types

enum ReaderModeEvent {
    case availability(url: String, available: Bool)
}

// MARK: - Message Parsing

extension ReaderModeEvent {
    /// Parses a message from the reader-mode scripts. Returns `nil` for malformed or unknown messages.
    init?(_ body: ScriptValue) {
        guard body["type"]?.stringValue == "availability", let url = body["url"]?.stringValue else { return nil }
        self = .availability(url: url, available: body["available"]?.boolValue ?? false)
    }
}
