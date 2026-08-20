import Foundation
import WebKit

/// Extracts content from cross-origin iframes by injecting a `WKUserScript` into all frames.
///
/// WebKit's native `_requestTextExtraction` enforces same-origin policy in the web process,
/// returning empty children for cross-origin `WKTextExtractionIFrameItem` nodes. This extractor
/// works around that limitation by injecting a content script into every frame (including
/// cross-origin ones) via `WKUserScript` with `injectedFrames: .allFrames`.
///
/// The injected script walks the DOM inside each subframe, collects interactive elements with
/// bounding rects, and posts the results back via `webkit.messageHandlers.refraxFrameContent`.
///
/// ## Usage
///
/// ```swift
/// // During app setup (before creating web pages)
/// FrameContentExtractor.shared.install(on: userContentController)
///
/// // When building the page content tree, query for frame content
/// let content = FrameContentExtractor.shared.content(forOrigin: "https://consent.cookiebot.com")
/// ```
@MainActor
final class FrameContentExtractor: NSObject {
    /// Singleton instance.
    static let shared = FrameContentExtractor()

    /// Message handler name matching the JavaScript constant.
    static let messageHandlerName = "refraxFrameContent"

    // MARK: - Stored Frame Content

    /// Content extracted from frames, keyed by frame origin.
    ///
    /// Each entry contains the elements and metadata posted by the injected script.
    /// Entries are replaced on each new message from the same origin (latest wins).
    private var frameContents: [String: FrameContent] = [:]

    /// Auto-incrementing frame identifier for stable ref prefixes.
    private var nextFrameID = 1

    /// Maps frame origins to their assigned frame IDs (e.g., "f1", "f2").
    private var frameIDMap: [String: String] = [:]

    // MARK: - Installation

    private var isInstalled = false

    /// Installs the frame content extraction script and message handler on a `WKUserContentController`.
    ///
    /// Call this once during app initialization, before creating any web pages.
    /// The script is injected into all frames (including cross-origin) at document end.
    ///
    /// - Parameter controller: The user content controller shared across all web pages.
    func install(on controller: WKUserContentController) {
        guard !isInstalled else { return }
        isInstalled = true

        // Register the message handler
        controller.add(self, name: Self.messageHandlerName)

        // Load and inject the content script
        let scriptSource = loadScript()
        let script = WKUserScript(
            source: scriptSource,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false,
        )
        controller.addUserScript(script)

        Logger.debug("[FrameContentExtractor] Installed script + message handler", category: Logger.agent)
    }

    // MARK: - Content Access

    /// Returns the extracted content for a frame matching the given origin.
    ///
    /// - Parameter origin: The frame's origin (e.g., "https://consent.cookiebot.com").
    /// - Returns: The frame content if available, or nil if the frame hasn't reported yet.
    func content(forOrigin origin: String) -> FrameContent? {
        // Try exact match first
        if let content = frameContents[origin] {
            return content
        }
        // Try matching by origin substring (handles port differences, etc.)
        for (key, content) in frameContents {
            if key.contains(origin) || origin.contains(key) {
                return content
            }
        }
        return nil
    }

    /// Returns all stored frame contents.
    var allFrameContents: [String: FrameContent] {
        frameContents
    }

    /// Returns the frame ID (e.g., "f1") for a given origin, creating one if needed.
    func frameID(forOrigin origin: String) -> String {
        if let existing = frameIDMap[origin] {
            return existing
        }
        let id = "f\(nextFrameID)"
        nextFrameID += 1
        frameIDMap[origin] = id
        return id
    }

    /// Looks up a frame origin by its frame ID prefix.
    ///
    /// - Parameter frameID: The frame ID (e.g., "f1").
    /// - Returns: The origin string, or nil if not found.
    func origin(forFrameID frameID: String) -> String? {
        frameIDMap.first(where: { $0.value == frameID })?.key
    }

    /// Clears all stored frame content. Called on page navigation.
    func clearAll() {
        frameContents.removeAll()
        frameIDMap.removeAll()
        nextFrameID = 1
    }

    /// Clears content for a specific origin.
    func clear(origin: String) {
        frameContents.removeValue(forKey: origin)
    }

    /// Requests re-extraction from all frames by evaluating the trigger function.
    ///
    /// - Parameter webView: The web view containing the frames.
    func requestReExtraction(from webView: WKWebView) {
        // The injected script exposes __refraxExtractFrameContent in each frame.
        // We can't call it directly in cross-origin frames, but since the script
        // is already injected, navigations/reloads will trigger it automatically.
        // For dynamic content, the caller should clear + wait for new postMessage.
        webView._evaluateJavaScriptWithoutUserGesture(
            "document.querySelectorAll('iframe').forEach(f => { try { f.contentWindow.__refraxExtractFrameContent && f.contentWindow.__refraxExtractFrameContent() } catch(e) {} })",
            completionHandler: nil,
        )
    }

    // MARK: - Script Loading

    private func loadScript() -> String {
        guard let url = Bundle.main.url(forResource: "frame-content-script", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else {
            Logger.error("[FrameContentExtractor] Failed to load frame-content-script.js from bundle", category: Logger.agent)
            return "// frame-content-script.js not found in bundle"
        }
        return source
    }
}

// MARK: - WKScriptMessageHandler

extension FrameContentExtractor: WKScriptMessageHandler {
    nonisolated func userContentController(
        _: WKUserContentController,
        didReceive message: WKScriptMessage,
    ) {
        MainActor.assumeIsolated {
            guard let body = message.body as? [String: Any],
                  let frameOrigin = body["frameOrigin"] as? String
            else { return }

            let elements = self.parseElements(from: body["elements"] as? [[String: Any]] ?? [])
            let summary = self.parseSummary(from: body["summary"] as? [String: Any])
            let viewportWidth = body["viewportWidth"] as? Int ?? 0
            let viewportHeight = body["viewportHeight"] as? Int ?? 0
            let frameURL = body["frameURL"] as? String ?? frameOrigin

            let content = FrameContent(
                origin: frameOrigin,
                url: frameURL,
                elements: elements,
                summary: summary,
                viewportSize: CGSize(width: viewportWidth, height: viewportHeight),
                receivedAt: Date(),
            )

            self.frameContents[frameOrigin] = content
            Logger.debug(
                "[FrameContentExtractor] Received \(elements.count) elements from \(frameOrigin)",
                category: Logger.agent,
            )
        }
    }

    private nonisolated func parseElements(from data: [[String: Any]]) -> [FrameElement] {
        data.compactMap { dict -> FrameElement? in
            guard let index = dict["index"] as? Int,
                  let tag = dict["tag"] as? String,
                  let rectDict = dict["rect"] as? [String: Any],
                  let x = rectDict["x"] as? Int,
                  let y = rectDict["y"] as? Int,
                  let width = rectDict["width"] as? Int,
                  let height = rectDict["height"] as? Int
            else { return nil }

            return FrameElement(
                index: index,
                tag: tag,
                role: dict["role"] as? String,
                text: dict["text"] as? String ?? "",
                href: dict["href"] as? String,
                inputType: dict["inputType"] as? String,
                value: dict["value"] as? String,
                isDisabled: dict["isDisabled"] as? Bool ?? false,
                isChecked: dict["isChecked"] as? Bool ?? false,
                rect: CGRect(x: x, y: y, width: width, height: height),
            )
        }
    }

    private nonisolated func parseSummary(from data: [String: Any]?) -> FrameContentSummary {
        guard let data else { return FrameContentSummary(headings: [], text: "") }
        let headings = data["headings"] as? [String] ?? []
        let text = data["text"] as? String ?? ""
        return FrameContentSummary(headings: headings, text: text)
    }
}

// MARK: - Data Types

/// Content extracted from a single cross-origin iframe.
struct FrameContent: Sendable {
    let origin: String
    let url: String
    let elements: [FrameElement]
    let summary: FrameContentSummary
    let viewportSize: CGSize
    let receivedAt: Date
}

/// A single interactive element inside a frame.
struct FrameElement: Sendable {
    let index: Int
    let tag: String
    let role: String?
    let text: String
    let href: String?
    let inputType: String?
    let value: String?
    let isDisabled: Bool
    let isChecked: Bool
    let rect: CGRect
}

/// Summary text content from a frame (headings + body text).
struct FrameContentSummary: Sendable {
    let headings: [String]
    let text: String
}
