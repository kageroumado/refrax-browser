import Foundation
import os
import WebKit

/// WKTextExtractionItem and its subclasses are only accessed on the main thread
/// (created by WebKit's callback, processed synchronously before being discarded).
extension WKTextExtractionItem: @unchecked Sendable {}

/// Extracts structured page content using WebKit's native `_WKTextExtraction` API.
///
/// Leverages WebKit's internal content tree for extraction. Benefits:
///
/// - **Visibility-aware**: WebKit handles `display:none`, `visibility:hidden`, `opacity:0`,
///   and `aria-hidden` natively. We add viewport intersection for offscreen detection.
/// - **Shadow DOM aware**: Uses composed tree traversal, handles web components.
/// - **Interactive element detection**: Event listeners, ARIA roles, and form controls
///   are identified by WebKit, not heuristic selectors.
/// - **iframe support**: Same-origin iframes are traversed automatically.
/// - **Action support**: Extracted `nodeIdentifier` values can be used with
///   `_performInteraction:` for native click/type/scroll without JavaScript.
///
/// ## Requirements
///
/// - macOS 15.0+ (API availability)
/// - `_textExtractionEnabled` must be set on WKPreferences
///
/// ## Usage
///
/// ```swift
/// let tree = try await PageContentExtractor.extract(from: webView, url: url, title: title)
/// let output = PageContentFormatter.format(tree)
/// ```
@MainActor
enum PageContentExtractor {
    // MARK: - Configuration

    /// Maximum age of a cached extraction before re-extraction.
    private static let cacheMaxAge: TimeInterval = 30

    /// Maximum cache entries before eviction.
    private static let maxCacheEntries = 50

    // MARK: - Cache

    private static var cache: [String: CachedContent] = [:]

    // MARK: - Public API

    /// Extracts a structured content tree from a WKWebView.
    ///
    /// - Parameters:
    ///   - webView: The web view to extract content from.
    ///   - url: The current page URL (used for caching).
    ///   - title: The current page title.
    /// - Returns: A ``PageContentTree`` representing the page's content.
    static func extract(
        from webView: WKWebView,
        url: URL,
        title: String,
    ) async throws -> PageContentTree {
        let urlString = url.absoluteString

        // Check cache
        if let cached = cache[urlString], !cached.isStale(maxAge: cacheMaxAge) {
            return cached.tree
        }

        var tree = try await runNativeExtraction(from: webView, url: url, title: title)

        // Inject cross-origin iframe content from the frame extraction script
        tree = injectFrameContent(into: tree)

        // Recognize text in images via Vision OCR
        let ocrResults = await ImageTextRecognizer.recognizeText(webView: webView)
        if !ocrResults.isEmpty {
            tree.imageOCR = ocrResults
            Logger.debug(
                "[TextExtraction] OCR recognized text in \(ocrResults.count) image(s)",
                category: Logger.agent,
            )
        }

        // Evict stale entries
        if cache.count > maxCacheEntries {
            let now = Date()
            cache = cache.filter { !$0.value.isStale(maxAge: cacheMaxAge, relativeTo: now) }
        }

        cache[urlString] = CachedContent(tree: tree, extractedAt: Date())
        return tree
    }

    /// Extracts content, bypassing the cache.
    static func extractFresh(
        from webView: WKWebView,
        url: URL,
        title: String,
    ) async throws -> PageContentTree {
        clearCache(for: url)
        return try await extract(from: webView, url: url, title: title)
    }

    /// Clears cache for a specific URL.
    static func clearCache(for url: URL) {
        cache.removeValue(forKey: url.absoluteString)
    }

    /// Clears all cached content.
    static func clearAllCaches() {
        cache.removeAll()
    }

    // MARK: - Cross-Origin Frame Content Injection

    /// Walks the tree looking for `.iframe(origin:)` nodes with empty children and injects
    /// content extracted by ``FrameContentExtractor`` via its injected WKUserScript.
    ///
    /// Cross-origin iframes are opaque to WebKit's `_requestTextExtraction` — they appear
    /// as `WKTextExtractionIFrameItem` with only an origin string and no children. The
    /// frame content script runs inside those frames and posts interactive elements back
    /// to the native side. This method merges that data into the content tree.
    private static func injectFrameContent(into tree: PageContentTree) -> PageContentTree {
        let extractor = FrameContentExtractor.shared

        // Quick check: if no frame content is available, skip the walk entirely
        guard !extractor.allFrameContents.isEmpty else { return tree }

        let newRoot = injectFrameContentRecursive(node: tree.root, extractor: extractor)
        return PageContentTree(
            root: newRoot,
            metadata: tree.metadata,
            extractedAt: tree.extractedAt,
            imageOCR: tree.imageOCR,
        )
    }

    private static func injectFrameContentRecursive(
        node: PageContentNode,
        extractor: FrameContentExtractor,
    ) -> PageContentNode {
        // Recurse into children first
        let newChildren: [PageContentNode]

        if case let .iframe(origin) = node.type, node.children.isEmpty || !hasInteractiveChildren(node) {
            // This is a cross-origin iframe with no extracted content from native API.
            // Try to inject content from the frame extraction script.
            if let frameContent = extractor.content(forOrigin: origin) {
                let frameID = extractor.frameID(forOrigin: origin)
                newChildren = buildSyntheticChildren(from: frameContent, frameID: frameID, parentRect: node.rect)
            } else {
                // No frame content available — keep as-is
                newChildren = node.children
            }
        } else {
            newChildren = node.children.map { child in
                injectFrameContentRecursive(node: child, extractor: extractor)
            }
        }

        guard newChildren != node.children else { return node }

        return PageContentNode(
            ref: node.ref,
            nativeID: node.nativeID,
            type: node.type,
            role: node.role,
            name: node.name,
            rect: node.rect,
            visibility: node.visibility,
            isInteractive: node.isInteractive,
            eventListeners: node.eventListeners,
            ariaAttributes: node.ariaAttributes,
            children: newChildren,
        )
    }

    /// Checks if a node has any interactive children (indicating native extraction succeeded).
    private static func hasInteractiveChildren(_ node: PageContentNode) -> Bool {
        for child in node.children {
            if child.isInteractive { return true }
            if hasInteractiveChildren(child) { return true }
        }
        return false
    }

    /// Builds synthetic `PageContentNode` children from frame extraction script data.
    ///
    /// Each element gets a ref prefixed by the frame ID (e.g., "f1:e0", "f1:e1").
    /// The refs use the element's index within the frame, not the global ref counter,
    /// since these elements don't have native node identifiers.
    private static func buildSyntheticChildren(
        from content: FrameContent,
        frameID: String,
        parentRect: CGRect,
    ) -> [PageContentNode] {
        // Add a summary text node if available
        var children: [PageContentNode] = []

        let summaryText = content.summary.headings.joined(separator: " | ")
            + (content.summary.text.isEmpty ? "" : " — \(content.summary.text)")
        if !summaryText.isEmpty {
            children.append(PageContentNode(
                ref: nil,
                nativeID: nil,
                type: .text(content: String(summaryText.prefix(300))),
                role: nil,
                name: nil,
                rect: .zero,
                visibility: .visible,
                isInteractive: false,
                eventListeners: 0,
                ariaAttributes: [:],
                children: [],
            ))
        }

        // Convert each frame element to a synthetic node
        for element in content.elements {
            let ref = "\(frameID):e\(element.index)"

            // Map element rect from iframe-local to parent page coordinates
            let mappedRect = CGRect(
                x: parentRect.origin.x + element.rect.origin.x,
                y: parentRect.origin.y + element.rect.origin.y,
                width: element.rect.width,
                height: element.rect.height,
            )

            let nodeType: PageContentNode.NodeType = switch element.tag {
            case "a":
                .link(url: element.href)
            case "button":
                .button
            case "input", "textarea":
                .formControl(
                    controlType: element.inputType ?? "text",
                    label: element.text,
                    isDisabled: element.isDisabled,
                    isChecked: element.isChecked,
                )
            case "select":
                .select(selectedValues: element.value.map { [$0] } ?? [])
            default:
                element.role == "button" ? .button : .generic
            }

            children.append(PageContentNode(
                ref: ref,
                nativeID: nil,
                type: nodeType,
                role: element.role,
                name: element.text.isEmpty ? nil : element.text,
                rect: mappedRect,
                visibility: mappedRect.width > 0 && mappedRect.height > 0 ? .visible : .hidden,
                isInteractive: true,
                eventListeners: 0,
                ariaAttributes: [:],
                children: [],
            ))
        }

        return children
    }

    // MARK: - Native Extraction

    /// Calls WebKit's `_requestTextExtraction` and builds a `PageContentTree` from the result.
    ///
    /// The `_WKTextExtraction` API is evolving rapidly in WebKit trunk. On shipped macOS,
    /// the callback may return a `_WKTextExtractionResult` (text-only) instead of the
    /// `WKTextExtractionItem` tree that trunk declares. We detect the actual type at
    /// runtime and handle both cases.
    ///
    /// Includes a 10-second timeout to guard against WebKit edge cases where the
    /// extraction callback is never invoked.
    private static func runNativeExtraction(
        from webView: WKWebView,
        url: URL,
        title: String,
    ) async throws -> PageContentTree {
        let config = buildExtractionConfig()
        let viewportSize = webView.bounds.size

        let guard_ = ContinuationGuard()

        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task {
                try await Task.sleep(for: .seconds(10))
                guard guard_.claim() else { return }
                continuation.resume(throwing: ExtractionError.timeout)
            }

            webView._requestTextExtraction(config) { item in
                MainActor.assumeIsolated {
                    timeoutTask.cancel()
                    guard guard_.claim() else { return }

                    guard let item else {
                        Logger.debug("[TextExtraction] Callback received nil", category: Logger.agent)
                        continuation.resume(throwing: ExtractionError.nativeExtractionFailed)
                        return
                    }

                    let obj = item as NSObject
                    let className = NSStringFromClass(type(of: obj))
                    Logger.debug("[TextExtraction] Callback received: \(className)", category: Logger.agent)

                    // Resolve the actual WKTextExtractionItem root.
                    // On WebKit trunk, the callback returns a WKTextExtractionItem directly.
                    // On shipped macOS, it returns a WKTextExtractionResult wrapper with
                    // a `rootItem` property containing the item tree.
                    let rootItem: WKTextExtractionItem
                    if obj.responds(to: NSSelectorFromString("rectInWebView")) {
                        // Direct WKTextExtractionItem (trunk API)
                        rootItem = item
                        Logger.debug("[TextExtraction] Direct item tree", category: Logger.agent)
                    } else if obj.responds(to: NSSelectorFromString("rootItem")),
                              let unwrapped = obj.value(forKey: "rootItem") as? WKTextExtractionItem {
                        // WKTextExtractionResult wrapper (shipped macOS) — unwrap
                        rootItem = unwrapped
                        Logger.debug("[TextExtraction] Unwrapped rootItem from \(className)", category: Logger.agent)
                    } else {
                        Logger.debug("[TextExtraction] No usable data from \(className)", category: Logger.agent)
                        continuation.resume(throwing: ExtractionError.nativeExtractionFailed)
                        return
                    }

                    let visibleRect = CGRect(origin: .zero, size: viewportSize)
                    var refCounter = RefCounter()
                    let rootNode = Self.buildNode(from: rootItem, visibleRect: visibleRect, refCounter: &refCounter)

                    let tree = PageContentTree(
                        root: rootNode,
                        metadata: .init(title: title, url: url.absoluteString, viewportSize: viewportSize),
                        extractedAt: Date(),
                    )
                    continuation.resume(returning: tree)
                }
            }
        }
    }

    // MARK: - Configuration

    /// Builds an extraction configuration, guarding each property setter against
    /// unshipped selectors. Many config properties exist in WebKit trunk but aren't
    /// yet available in released macOS builds.
    private static func buildExtractionConfig() -> _WKTextExtractionConfiguration {
        let config = _WKTextExtractionConfiguration()
        var configured: [String] = []

        if config.responds(to: Selector(("setIncludeURLs:"))) {
            config.includeURLs = true
            configured.append("includeURLs")
        }
        if config.responds(to: Selector(("setIncludeRects:"))) {
            config.includeRects = true
            configured.append("includeRects")
        }
        if config.responds(to: Selector(("setIncludeEventListeners:"))) {
            config.includeEventListeners = true
            configured.append("includeEventListeners")
        }
        if config.responds(to: Selector(("setIncludeAccessibilityAttributes:"))) {
            config.includeAccessibilityAttributes = true
            configured.append("includeAccessibilityAttributes")
        }
        if config.responds(to: Selector(("setSkipNearlyTransparentContent:"))) {
            config.skipNearlyTransparentContent = true
            configured.append("skipNearlyTransparentContent")
        }
        if config.responds(to: Selector(("setNodeIdentifierInclusion:"))) {
            config.nodeIdentifierInclusion = .interactive
            configured.append("nodeIdentifierInclusion")
        }

        Logger.debug("[TextExtraction] Config class: \(NSStringFromClass(type(of: config))), properties: \(configured.joined(separator: ", "))", category: Logger.agent)
        return config
    }

    // MARK: - Tree Building (nonisolated — pure functions)

    /// Converts a `WKTextExtractionItem` hierarchy into our `PageContentNode` tree.
    private nonisolated static func buildNode(
        from item: WKTextExtractionItem,
        visibleRect: CGRect,
        refCounter: inout RefCounter,
    ) -> PageContentNode {
        let rect = item.rectInWebView
        let ariaAttrs = item.ariaAttributes as [String: String]
        let visibility = classifyVisibility(rect: rect, visibleRect: visibleRect, ariaAttributes: ariaAttrs)

        let eventListenerMask = item.eventListeners.rawValue
        let isInteractive = item.eventListeners.contains(.click)
            || isInteractiveRole(item.accessibilityRole)
            || item.nodeIdentifier != nil

        let ref: String? = if isInteractive {
            refCounter.next()
        } else {
            nil
        }

        let nodeType = classifyNodeType(item)
        let name = extractName(from: item, ariaAttributes: ariaAttrs)

        let children = item.children.map { child in
            buildNode(from: child, visibleRect: visibleRect, refCounter: &refCounter)
        }

        return PageContentNode(
            ref: ref,
            nativeID: item.nodeIdentifier,
            type: nodeType,
            role: item.accessibilityRole.isEmpty ? nil : item.accessibilityRole,
            name: name,
            rect: rect,
            visibility: visibility,
            isInteractive: isInteractive,
            eventListeners: eventListenerMask,
            ariaAttributes: ariaAttrs,
            children: children,
        )
    }

    // MARK: - Node Classification

    private nonisolated static func classifyNodeType(_ item: WKTextExtractionItem) -> PageContentNode.NodeType {
        if let container = item as? WKTextExtractionContainerItem {
            return switch container.container {
            case .root: .root
            case .viewportConstrained: .overlay
            case .list: .list
            case .listItem: .listItem
            case .blockQuote: .blockquote
            case .article: .article
            case .section: .section
            case .nav: .navigation
            case .button: .button
            case .canvas: .canvas
            case .subscript, .superscript: .generic
            case .generic: .generic
            @unknown default: .generic
            }
        }

        if let text = item as? WKTextExtractionTextItem {
            return .text(content: text.content)
        }

        if let link = item as? WKTextExtractionLinkItem {
            return .link(url: link.url?.absoluteString)
        }

        if let image = item as? WKTextExtractionImageItem {
            return .image(alt: image.altText.isEmpty ? nil : image.altText)
        }

        if let formControl = item as? WKTextExtractionTextFormControlItem {
            return .formControl(
                controlType: formControl.controlType,
                label: formControl.label,
                isDisabled: formControl.isDisabled,
                isChecked: formControl.isChecked,
            )
        }

        if let select = item as? WKTextExtractionSelectItem {
            return .select(selectedValues: select.selectedValues as [String])
        }

        // WKTextExtractionFormItem and WKTextExtractionIFrameItem exist in WebKit source
        // but aren't shipped in the current macOS binary. Use runtime class name checks
        // so they're picked up automatically when Apple ships them.
        let className = NSStringFromClass(type(of: item))

        if className == "WKTextExtractionFormItem" {
            return .form
        }

        if className == "WKTextExtractionIFrameItem" {
            let origin = (item as NSObject).value(forKey: "origin") as? String ?? ""
            return .iframe(origin: origin)
        }

        if let scrollable = item as? WKTextExtractionScrollableItem {
            return .scrollable(contentSize: scrollable.contentSize)
        }

        if let editable = item as? WKTextExtractionContentEditableItem {
            return .contentEditable(isFocused: editable.isFocused)
        }

        return .generic
    }

    /// Extracts a human-readable name from an item's ARIA attributes and content.
    ///
    /// Priority: `aria-label` > `aria-description` > type-specific labels (alt text, form label).
    /// Text items never produce a name since their content is carried by ``PageContentNode/NodeType/text(content:)``.
    private nonisolated static func extractName(
        from item: WKTextExtractionItem,
        ariaAttributes: [String: String],
    ) -> String? {
        if let label = ariaAttributes["aria-label"], !label.isEmpty {
            return label
        }
        if let desc = ariaAttributes["aria-description"], !desc.isEmpty {
            return desc
        }

        if item is WKTextExtractionTextItem {
            return nil
        }

        if let image = item as? WKTextExtractionImageItem, !image.altText.isEmpty {
            return image.altText
        }

        if let control = item as? WKTextExtractionTextFormControlItem, !control.label.isEmpty {
            return control.label
        }

        return nil
    }

    // MARK: - Visibility

    private nonisolated static func classifyVisibility(
        rect: CGRect,
        visibleRect: CGRect,
        ariaAttributes: [String: String],
    ) -> PageContentNode.Visibility {
        if ariaAttributes["aria-expanded"] == "false" {
            return .collapsed
        }

        // Zero-size items are effectively hidden (WebKit already filters truly hidden elements)
        if rect.width < 1 || rect.height < 1 {
            return .hidden
        }

        if rect.intersects(visibleRect) {
            return .visible
        }

        return .offscreen
    }

    private nonisolated static func isInteractiveRole(_ role: String) -> Bool {
        switch role {
        case "button", "link", "textbox", "checkbox", "radio", "combobox",
             "listbox", "menuitem", "option", "searchbox", "slider",
             "spinbutton", "switch", "tab", "treeitem", "menuitemcheckbox",
             "menuitemradio":
            true
        default:
            false
        }
    }
}

// MARK: - Ref Counter

private nonisolated struct RefCounter {
    private var count = 0

    mutating func next() -> String {
        count += 1
        return "e\(count)"
    }
}

// MARK: - Cache

private struct CachedContent {
    let tree: PageContentTree
    let extractedAt: Date

    func isStale(maxAge: TimeInterval, relativeTo now: Date = Date()) -> Bool {
        now.timeIntervalSince(extractedAt) > maxAge
    }
}

// MARK: - Errors

extension PageContentExtractor {
    enum ExtractionError: LocalizedError {
        case timeout
        case nativeExtractionFailed

        var errorDescription: String? {
            switch self {
            case .timeout: "Page content extraction timed out"
            case .nativeExtractionFailed: "WebKit text extraction returned no result"
            }
        }
    }
}

// MARK: - Continuation Guard

/// Ensures a continuation is resumed exactly once when racing extraction vs timeout.
///
/// Uses `OSAllocatedUnfairLock` for lock-based synchronization, ensuring
/// correctness even when the timeout task and extraction callback run
/// on different executors.
private final class ContinuationGuard: Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: false)

    /// Attempts to claim the guard. Returns `true` if this is the first claim,
    /// `false` if another path already claimed it.
    func claim() -> Bool {
        lock.withLock { resumed in
            if resumed { return false }
            resumed = true
            return true
        }
    }
}
