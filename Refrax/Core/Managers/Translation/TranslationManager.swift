import Foundation
import NaturalLanguage
import Observation
import OSLog
import SwiftUI
import Translation

/// Manages full-page translation using Apple's Translation framework.
///
/// `TranslationManager` provides language detection and page translation capabilities,
/// mirroring Safari's translation UX with an address bar icon and popover.
///
/// ## Design
///
/// - Uses Apple's Translation framework for on-device translation (privacy-focused, offline capable)
/// - Uses NLLanguageRecognizer for language detection from page content
/// - Tracks per-page translation state via WebPage observable properties
/// - Caches detected languages per URL to avoid repeated detection
///
/// ## Translation Flow
///
/// Translation uses SwiftUI's `.translationTask` modifier:
/// 1. Manager detects language and extracts text nodes
/// 2. View layer triggers translation via `.translationTask`
/// 3. Session callback invokes manager to complete translation
/// 4. Manager injects translated content back into page
@Observable
final class TranslationManager {
    // MARK: - State

    /// Tracks pages that are currently being translated.
    private var translatingPages: Set<UUID> = .init()

    /// Cached detected languages per URL.
    private var detectedLanguageCache: [URL: Locale.Language] = .init()

    // MARK: - Target Language

    /// The user's preferred language for translations.
    ///
    /// Defaults to the system's current locale language.
    var targetLanguage: Locale.Language {
        Locale.current.language
    }

    /// Languages supported by the Translation framework.
    ///
    /// Returns common languages that Apple's framework typically supports.
    var availableLanguages: [Locale.Language] {
        [
            Locale.Language(identifier: "en"),
            Locale.Language(identifier: "es"),
            Locale.Language(identifier: "fr"),
            Locale.Language(identifier: "de"),
            Locale.Language(identifier: "it"),
            Locale.Language(identifier: "pt"),
            Locale.Language(identifier: "zh-Hans"),
            Locale.Language(identifier: "zh-Hant"),
            Locale.Language(identifier: "ja"),
            Locale.Language(identifier: "ko"),
            Locale.Language(identifier: "ar"),
            Locale.Language(identifier: "ru"),
            Locale.Language(identifier: "nl"),
            Locale.Language(identifier: "pl"),
            Locale.Language(identifier: "tr"),
            Locale.Language(identifier: "uk"),
            Locale.Language(identifier: "th"),
            Locale.Language(identifier: "vi"),
            Locale.Language(identifier: "id"),
        ]
    }

    // MARK: - Initialization

    init() {}

    // MARK: - Display Helpers

    /// Returns the localized display name for a language.
    ///
    /// - Parameter language: The language to get the display name for.
    /// - Returns: The localized language name, or the language code if unavailable.
    static func displayName(for language: Locale.Language) -> String {
        let identifier = language.languageCode?.identifier ?? "en"
        let locale = Locale(identifier: identifier)
        return locale.localizedString(forLanguageCode: identifier) ?? identifier
    }

    // MARK: - Language Detection

    /// Detects the primary language of text using NLLanguageRecognizer.
    ///
    /// - Parameter text: The text to analyze.
    /// - Returns: The detected language, or nil if detection failed.
    func detectLanguage(of text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)

        guard let languageCode = recognizer.dominantLanguage?.rawValue else {
            return nil
        }
        return Locale.Language(identifier: languageCode)
    }

    /// Detects the page language from HTML attributes and content.
    ///
    /// Detection priority:
    /// 1. HTML `lang` attribute on `<html>` or `<body>`
    /// 2. Content analysis of visible text
    ///
    /// - Parameter webPage: The WebPage to analyze.
    /// - Returns: The detected language, or nil if detection failed.
    func detectPageLanguage(webPage: WebPage) async -> Locale.Language? {
        guard let url = webPage.url else { return nil }

        // Return cached result if available
        if let cached = detectedLanguageCache[url] {
            return cached
        }

        // Priority 1: HTML lang attribute
        if let htmlLang = try? await webPage.evaluateJavaScript(
            "document.documentElement.lang || document.body.lang",
        ) as? String, !htmlLang.isEmpty {
            let language = Locale.Language(identifier: htmlLang)
            detectedLanguageCache[url] = language
            return language
        }

        // Priority 2: Detect from visible text (sample first 2000 chars)
        if let visibleText = try? await webPage.evaluateJavaScript(
            "document.body.innerText.substring(0, 2000)",
        ) as? String, !visibleText.isEmpty {
            if let detected = detectLanguage(of: visibleText) {
                detectedLanguageCache[url] = detected
                return detected
            }
        }

        return nil
    }

    /// Returns the cached detected language for a URL.
    func cachedLanguage(for url: URL?) -> Locale.Language? {
        guard let url else { return nil }
        return detectedLanguageCache[url]
    }

    /// Clears the language detection cache for a URL.
    func clearCache(for url: URL) {
        detectedLanguageCache.removeValue(forKey: url)
    }

    // MARK: - Translation Availability

    /// Checks if translation is available for a language pair.
    ///
    /// - Parameters:
    ///   - source: The source language.
    ///   - target: The target language (defaults to user's preferred language).
    /// - Returns: Whether translation is available (installed or downloadable).
    func canTranslate(from source: Locale.Language, to target: Locale.Language? = nil) async -> Bool {
        let targetLang = target ?? targetLanguage
        let availability = LanguageAvailability()
        let status = await availability.status(from: source, to: targetLang)
        return status == .installed || status == .supported
    }

    /// Checks if the language pair is installed (ready for immediate translation).
    func isInstalled(from source: Locale.Language, to target: Locale.Language? = nil) async -> Bool {
        let targetLang = target ?? targetLanguage
        let availability = LanguageAvailability()
        let status = await availability.status(from: source, to: targetLang)
        return status == .installed
    }

    /// Checks if the language pair needs to download a language pack.
    func needsDownload(from source: Locale.Language, to target: Locale.Language? = nil) async -> Bool {
        let targetLang = target ?? targetLanguage
        let availability = LanguageAvailability()
        let status = await availability.status(from: source, to: targetLang)
        return status == .supported
    }

    // MARK: - Translation State

    /// Whether a page is currently being translated.
    func isTranslating(pageID: UUID) -> Bool {
        translatingPages.contains(pageID)
    }

    // MARK: - Full Page Translation

    /// Prepares text nodes for translation by extracting them from the page.
    ///
    /// - Parameter webPage: The WebPage to extract text from.
    /// - Returns: Array of translation requests with client identifiers.
    func prepareTranslationRequests(for webPage: WebPage) async throws -> [TranslationSession.Request] {
        let pageID = webPage.tabPage.id

        // Mark as translating
        translatingPages.insert(pageID)
        webPage.isTranslating = true

        // Detect source language if not already known
        if webPage.detectedLanguage == nil {
            webPage.detectedLanguage = await detectPageLanguage(webPage: webPage)
        }

        // Extract text nodes from the page
        let textNodes = try await extractTextNodes(from: webPage)

        guard !textNodes.isEmpty else {
            translatingPages.remove(pageID)
            webPage.isTranslating = false
            throw TranslationError.noContentToTranslate
        }

        // Create batch translation requests
        var requests: [TranslationSession.Request] = []

        for node in textNodes {
            guard let index = node["index"] as? Int,
                  let text = node["text"] as? String,
                  !text.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).isEmpty
            else { continue }

            let clientID = String(index)
            requests.append(TranslationSession.Request(sourceText: text, clientIdentifier: clientID))
        }

        return requests
    }

    /// Completes translation by injecting translated responses into the page.
    ///
    /// - Parameters:
    ///   - responses: The translated responses from TranslationSession.
    ///   - webPage: The WebPage to inject into.
    ///   - targetLanguage: The target language used for translation.
    func completeTranslation(
        responses: [TranslationSession.Response],
        for webPage: WebPage,
        targetLanguage: Locale.Language?,
    ) async throws {
        let pageID = webPage.tabPage.id

        defer {
            translatingPages.remove(pageID)
            webPage.isTranslating = false
        }

        // Build translations map
        var translations: [Int: String] = [:]
        for response in responses {
            if let clientID = response.clientIdentifier,
               let index = Int(clientID) {
                translations[index] = response.targetText
            }
        }

        // Inject translations back into page
        try await injectTranslations(translations, into: webPage)

        // Update page state
        webPage.isTranslated = true
        webPage.originalLanguage = webPage.detectedLanguage
        webPage.translatedToLanguage = targetLanguage

        // Install mutation observer for dynamic content (SPA support)
        try? await installMutationObserver(on: webPage)

        Logger.info(
            "Translated page from \(webPage.detectedLanguage?.languageCode?.identifier ?? "?") to \(targetLanguage?.languageCode?.identifier ?? "?")",
            category: Logger.tabs,
        )
    }

    /// Cancels an in-progress translation.
    func cancelTranslation(for webPage: WebPage) {
        let pageID = webPage.tabPage.id
        translatingPages.remove(pageID)
        webPage.isTranslating = false
    }

    /// Restores the original page content by reloading.
    ///
    /// - Parameter webPage: The WebPage to restore.
    func restoreOriginalPage(_ webPage: WebPage) {
        webPage.isTranslated = false
        webPage.originalLanguage = nil
        webPage.translatedToLanguage = nil
        webPage.reload()
    }

    // MARK: - Text Extraction

    /// Extracts translatable text nodes from the page.
    ///
    /// Returns an array of dictionaries with `index` and `text` keys.
    /// Each node is marked with a data attribute for later injection.
    private func extractTextNodes(from webPage: WebPage) async throws -> [[String: Any]] {
        let script = """
        (function() {
            const nodes = [];
            const walker = document.createTreeWalker(
                document.body,
                NodeFilter.SHOW_TEXT,
                {
                    acceptNode: function(node) {
                        const parent = node.parentElement;
                        if (!parent) return NodeFilter.FILTER_REJECT;
        
                        const tag = parent.tagName.toLowerCase();
                        if (['script', 'style', 'noscript', 'code', 'pre'].includes(tag)) {
                            return NodeFilter.FILTER_REJECT;
                        }
        
                        const text = node.textContent.trim();
                        if (text.length < 2) {
                            return NodeFilter.FILTER_REJECT;
                        }
        
                        // Skip if already translated
                        if (parent.dataset.refraxTranslated) {
                            return NodeFilter.FILTER_REJECT;
                        }
        
                        return NodeFilter.FILTER_ACCEPT;
                    }
                }
            );
        
            let index = 0;
            while (walker.nextNode()) {
                const node = walker.currentNode;
                const parent = node.parentElement;
        
                // Store original text for potential restoration
                if (!parent.dataset.refraxOriginal) {
                    parent.dataset.refraxOriginal = node.textContent;
                }
                parent.dataset.refraxIndex = index;
        
                nodes.push({
                    index: index++,
                    text: node.textContent
                });
            }
            return nodes;
        })()
        """

        guard let result = try await webPage.evaluateJavaScript(script) as? [[String: Any]] else {
            return []
        }
        return result
    }

    /// Injects translated content back into the page.
    private func injectTranslations(_ translations: [Int: String], into webPage: WebPage) async throws {
        // Encode translations as JSON
        let translationsDict = translations.reduce(into: [String: String]()) { result, pair in
            result[String(pair.key)] = pair.value
        }
        let jsonData = try JSONEncoder().encode(translationsDict)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw TranslationError.translationFailed(underlying: nil)
        }

        let script = """
        (function(translations) {
            const walker = document.createTreeWalker(
                document.body,
                NodeFilter.SHOW_TEXT
            );
        
            while (walker.nextNode()) {
                const node = walker.currentNode;
                const parent = node.parentElement;
                const index = parent?.dataset.refraxIndex;
        
                if (index && translations[index]) {
                    node.textContent = translations[index];
                    parent.dataset.refraxTranslated = 'true';
                }
            }
        })(\(jsonString))
        """

        _ = try await webPage.evaluateJavaScript(script)
    }

    // MARK: - Dynamic Content (SPA Support)

    /// Injects a mutation observer to track new content added after translation.
    ///
    /// The observer watches for new text nodes and marks them for translation.
    /// Call `extractNewTextNodes(from:)` to get text that was added after
    /// the initial translation.
    func installMutationObserver(on webPage: WebPage) async throws {
        let script = """
        (function() {
            // Don't install twice
            if (window._refraxTranslationObserver) return;
        
            // Track the highest index used
            let maxIndex = 0;
            document.querySelectorAll('[data-refrax-index]').forEach(el => {
                const idx = parseInt(el.dataset.refraxIndex, 10);
                if (idx > maxIndex) maxIndex = idx;
            });
            window._refraxNextIndex = maxIndex + 1;
            window._refraxNewNodes = [];
        
            const observer = new MutationObserver(mutations => {
                for (const mutation of mutations) {
                    for (const node of mutation.addedNodes) {
                        if (node.nodeType === Node.ELEMENT_NODE) {
                            // Walk added element for text nodes
                            const walker = document.createTreeWalker(
                                node,
                                NodeFilter.SHOW_TEXT,
                                {
                                    acceptNode: (textNode) => {
                                        const parent = textNode.parentElement;
                                        if (!parent) return NodeFilter.FILTER_REJECT;
                                        const tag = parent.tagName.toLowerCase();
                                        if (['script', 'style', 'noscript', 'code', 'pre'].includes(tag)) {
                                            return NodeFilter.FILTER_REJECT;
                                        }
                                        const text = textNode.textContent.trim();
                                        if (text.length < 2) return NodeFilter.FILTER_REJECT;
                                        if (parent.dataset.refraxTranslated) return NodeFilter.FILTER_REJECT;
                                        return NodeFilter.FILTER_ACCEPT;
                                    }
                                }
                            );
        
                            while (walker.nextNode()) {
                                const textNode = walker.currentNode;
                                const parent = textNode.parentElement;
                                if (!parent.dataset.refraxIndex) {
                                    parent.dataset.refraxIndex = window._refraxNextIndex;
                                    parent.dataset.refraxOriginal = textNode.textContent;
                                    window._refraxNewNodes.push({
                                        index: window._refraxNextIndex++,
                                        text: textNode.textContent
                                    });
                                }
                            }
                        }
                    }
                }
            });
        
            observer.observe(document.body, {
                childList: true,
                subtree: true
            });
        
            window._refraxTranslationObserver = observer;
        })()
        """

        _ = try await webPage.evaluateJavaScript(script)
    }

    /// Extracts new text nodes added after initial translation.
    ///
    /// - Parameter webPage: The WebPage to extract from.
    /// - Returns: Array of new nodes with index and text.
    func extractNewTextNodes(from webPage: WebPage) async throws -> [[String: Any]] {
        let script = """
        (function() {
            const nodes = window._refraxNewNodes || [];
            window._refraxNewNodes = [];
            return nodes;
        })()
        """

        guard let result = try await webPage.evaluateJavaScript(script) as? [[String: Any]] else {
            return []
        }
        return result
    }

    /// Checks if there are new untranslated nodes on the page.
    func hasNewContent(on webPage: WebPage) async -> Bool {
        let script = "(window._refraxNewNodes || []).length > 0"
        return await (try? webPage.evaluateJavaScript(script) as? Bool) ?? false
    }
}

// MARK: - Translation Errors

/// Errors that can occur during translation.
enum TranslationError: LocalizedError {
    case languageDetectionFailed
    case languageNotSupported(source: Locale.Language, target: Locale.Language)
    case noContentToTranslate
    case translationFailed(underlying: (any Error)?)
    case downloadRequired

    var errorDescription: String? {
        switch self {
        case .languageDetectionFailed:
            "Could not detect page language"
        case let .languageNotSupported(source, target):
            "Translation from \(source.languageCode?.identifier ?? "unknown") to \(target.languageCode?.identifier ?? "unknown") is not supported"
        case .noContentToTranslate:
            "No translatable content found on page"
        case let .translationFailed(underlying):
            if let underlying {
                "Translation failed: \(underlying.localizedDescription)"
            } else {
                "Translation failed"
            }
        case .downloadRequired:
            "Language pack needs to be downloaded"
        }
    }
}
