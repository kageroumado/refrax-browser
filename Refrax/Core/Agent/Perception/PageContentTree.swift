import CoreGraphics
import Foundation

/// A structured representation of a web page's content, built from WebKit's
/// native text extraction API.
///
/// The tree mirrors WebKit's `WKTextExtractionItem` hierarchy but adds:
/// - Viewport-based visibility classification
/// - Agent-friendly ref IDs for interactive elements
/// - Token-efficient text formatting
struct PageContentTree: Sendable, Equatable {
    /// Root node of the content tree.
    let root: PageContentNode

    /// Page metadata.
    let metadata: Metadata

    /// When the extraction was performed.
    let extractedAt: Date

    /// Text recognized in images via Vision OCR, keyed by ``ImageTextRecognizer/rectKey(_:)``.
    var imageOCR: [String: String] = [:]

    struct Metadata: Sendable, Equatable {
        let title: String
        let url: String
        let viewportSize: CGSize
    }

    init(
        root: PageContentNode,
        metadata: Metadata,
        extractedAt: Date,
        imageOCR: [String: String] = [:],
    ) {
        self.root = root
        self.metadata = metadata
        self.extractedAt = extractedAt
        self.imageOCR = imageOCR
    }
}

// MARK: - Content Node

/// A single node in the page content tree.
///
/// Each node corresponds to a `WKTextExtractionItem` from WebKit's extraction,
/// enriched with visibility classification and agent interaction refs.
struct PageContentNode: Sendable, Equatable {
    /// Agent-facing ref for interaction (e.g., "e1", "e12"). Only set on interactive elements.
    let ref: String?

    /// WebKit's native node identifier for `_performInteraction:`. Opaque, not shown to agent.
    let nativeID: String?

    /// Semantic type of this node.
    let type: NodeType

    /// ARIA role, if any.
    let role: String?

    /// Human-readable name (from aria-label, alt text, form label, etc.).
    let name: String?

    /// Bounding rect in web view coordinates.
    let rect: CGRect

    /// Visibility relative to the viewport.
    let visibility: Visibility

    /// Whether this node is interactive (clickable, typeable, etc.).
    let isInteractive: Bool

    /// Event listener categories on this element (bitmask).
    let eventListeners: UInt

    /// ARIA attributes (key-value pairs).
    let ariaAttributes: [String: String]

    /// Child nodes.
    let children: [PageContentNode]

    // MARK: - Node Type

    enum NodeType: Sendable, Equatable {
        case root
        case overlay
        case navigation
        case section
        case article
        case list
        case listItem
        case blockquote
        case button
        case canvas
        case form
        case generic

        case text(content: String)
        case link(url: String?)
        case image(alt: String?)
        case formControl(controlType: String, label: String, isDisabled: Bool, isChecked: Bool)
        case select(selectedValues: [String])
        case iframe(origin: String)
        case scrollable(contentSize: CGSize)
        case contentEditable(isFocused: Bool)
    }

    // MARK: - Visibility

    enum Visibility: String, Sendable, Equatable {
        /// Intersects the viewport — user can see it.
        case visible
        /// Below the fold or out of viewport.
        case offscreen
        /// Has `aria-expanded="false"` or zero height.
        case collapsed
        /// Zero-size or otherwise effectively hidden.
        case hidden
    }
}

// MARK: - Formatting

/// Formats a ``PageContentTree`` into token-efficient text for LLM consumption.
///
/// The output format is an indented tree inspired by Playwright's aria snapshot,
/// optimized for agent comprehension:
///
/// ```
/// # Page Title
/// URL: https://example.com
///
/// - NAV "Main Navigation" [collapsed]: 42 links
/// - MAIN
///   - SECTION "Hero"
///     - "Welcome to Example"
///     - LINK "Get Started" [ref=e1]
///   - SECTION "Features" [offscreen]
///     - "Feature highlights..."
///     - LINK "Learn more" [ref=e3]
/// - FOOTER [offscreen]: 28 links
/// ```
enum PageContentFormatter {
    /// Controls how much of the page tree is included in output.
    enum Scope {
        /// Only visible content — what the user can currently see.
        /// Offscreen elements are counted and summarized in a footer.
        case viewport
        /// Full page tree including all offscreen content.
        case full
        /// Main content only — like viewport but also filters out overlay elements
        /// (fixed headers, navigation bars, floating toolbars, etc.).
        case mainContent
    }

    /// Default approximate token budget for full-mode output.
    static let defaultTokenBudget = 2_000

    /// Formats the tree into agent-readable text.
    ///
    /// - Parameters:
    ///   - tree: The content tree to format.
    ///   - scope: How much content to include. `.viewport` shows only what the
    ///     user can see; `.full` includes everything. Default is `.viewport`.
    ///   - tokenBudget: Approximate target token count for `.full` mode.
    ///     In `.viewport` mode this is ignored since the output is naturally compact.
    /// - Returns: Formatted text string.
    static func format(
        _ tree: PageContentTree,
        scope: Scope = .viewport,
        tokenBudget: Int = defaultTokenBudget,
    ) -> String {
        let totalWords = countWords(in: tree.root)

        var lines: [String] = []
        var context = FormatContext(
            tokenBudget: tokenBudget,
            scope: scope,
        )

        // Build tree output
        for child in tree.root.children {
            formatNode(child, indent: 0, lines: &lines, context: &context)
        }

        // Header
        var header: [String] = []
        header.append("# \(tree.metadata.title)")
        header.append("URL: \(tree.metadata.url)")

        if scope == .viewport || scope == .mainContent, context.offscreenElements > 0 {
            let visibleWords = countWords(in: tree.root, visibleOnly: true)
            header.append("Words: \(visibleWords) visible / \(totalWords) total")
        } else {
            header.append("Words: \(totalWords)")
        }
        header.append("")

        lines.insert(contentsOf: header, at: 0)

        // Footer for viewport/mainContent mode — tell the agent what it can't see
        if scope == .viewport || scope == .mainContent, context.offscreenElements > 0 {
            lines.append("")
            lines.append("[+\(context.offscreenElements) offscreen elements not shown. Use full extraction to see all content.]")
        }

        // Image OCR results (text detected in images via Vision)
        if !tree.imageOCR.isEmpty {
            lines.append("")
            lines.append("[Text detected in images:]")
            for (label, text) in tree.imageOCR.sorted(by: { $0.key < $1.key }) {
                lines.append("- \(label): \"\(truncate(text, maxLength: 300))\"")
            }
        }

        let output = lines.joined(separator: "\n")

        // In full mode, apply progressive collapse if over budget
        if scope == .full {
            let estimatedTokens = output.count / 4
            if estimatedTokens > tokenBudget {
                return reformatWithCollapse(tree, tokenBudget: tokenBudget)
            }
        }

        return output
    }

    // MARK: - Node Formatting

    private static func formatNode(
        _ node: PageContentNode,
        indent: Int,
        lines: inout [String],
        context: inout FormatContext,
    ) {
        // Skip hidden nodes entirely
        if node.visibility == .hidden { return }

        // In mainContent mode, skip overlay nodes (fixed headers, navbars, floating toolbars)
        if context.scope == .mainContent, node.type == .overlay {
            return
        }

        // In viewport/mainContent mode, skip offscreen content and count it
        if context.scope == .viewport || context.scope == .mainContent, node.visibility == .offscreen {
            context.offscreenElements += 1 + countAllChildren(node)
            return
        }

        let prefix = String(repeating: "  ", count: indent)

        switch node.type {
        case .root:
            // Root is transparent, just format children
            for child in node.children {
                formatNode(child, indent: indent, lines: &lines, context: &context)
            }

        case let .text(content):
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let truncated = truncate(trimmed, maxLength: 200)
            lines.append("\(prefix)- \"\(truncated)\"")

        case let .link(url):
            let label = collectTextContent(node)
            let refTag = node.ref.map { " [ref=\($0)]" } ?? ""
            let visTag = visibilityTag(node.visibility)
            let urlTag = url.map { " → \(shortenURL($0))" } ?? ""
            if label.isEmpty {
                lines.append("\(prefix)- LINK\(refTag)\(visTag)\(urlTag)")
            } else {
                lines.append("\(prefix)- LINK \"\(truncate(label, maxLength: 80))\"\(refTag)\(visTag)\(urlTag)")
            }

        case let .image(alt):
            let refTag = node.ref.map { " [ref=\($0)]" } ?? ""
            if let alt, !alt.isEmpty {
                lines.append("\(prefix)- IMG \"\(truncate(alt, maxLength: 100))\"\(refTag)")
            } else {
                lines.append("\(prefix)- IMG [no alt]\(refTag)")
            }

        case .navigation:
            formatLandmarkNode(node, tag: "NAV", indent: indent, lines: &lines, context: &context)

        case .section:
            formatContainerNode(node, tag: "SECTION", indent: indent, lines: &lines, context: &context)

        case .article:
            formatContainerNode(node, tag: "ARTICLE", indent: indent, lines: &lines, context: &context)

        case .list:
            formatContainerNode(node, tag: "LIST", indent: indent, lines: &lines, context: &context)

        case .listItem:
            let text = collectTextContent(node)
            let refTag = node.ref.map { " [ref=\($0)]" } ?? ""
            if text.isEmpty {
                // Has children with structure — format them
                lines.append("\(prefix)- ITEM\(refTag)")
                for child in node.children {
                    formatNode(child, indent: indent + 1, lines: &lines, context: &context)
                }
            } else {
                lines.append("\(prefix)- ITEM \"\(truncate(text, maxLength: 120))\"\(refTag)")
            }

        case .blockquote:
            formatContainerNode(node, tag: "QUOTE", indent: indent, lines: &lines, context: &context)

        case .button:
            let label = node.name ?? collectTextContent(node)
            let refTag = node.ref.map { " [ref=\($0)]" } ?? ""
            let visTag = visibilityTag(node.visibility)
            lines.append("\(prefix)- BTN \"\(truncate(label, maxLength: 80))\"\(refTag)\(visTag)")

        case let .formControl(controlType, label, isDisabled, isChecked):
            let refTag = node.ref.map { " [ref=\($0)]" } ?? ""
            let disabledTag = isDisabled ? " [disabled]" : ""
            let checkedTag = isChecked ? " [checked]" : ""
            let typeTag = controlType.isEmpty ? "INPUT" : controlType.uppercased()
            if label.isEmpty {
                lines.append("\(prefix)- \(typeTag)\(refTag)\(disabledTag)\(checkedTag)")
            } else {
                lines.append("\(prefix)- \(typeTag) \"\(truncate(label, maxLength: 80))\"\(refTag)\(disabledTag)\(checkedTag)")
            }

        case let .select(selectedValues):
            let refTag = node.ref.map { " [ref=\($0)]" } ?? ""
            let valueTag = selectedValues.isEmpty ? "" : " [\(selectedValues.joined(separator: ", "))]"
            lines.append("\(prefix)- SELECT\(refTag)\(valueTag)")

        case .form:
            formatContainerNode(node, tag: "FORM", indent: indent, lines: &lines, context: &context)

        case let .iframe(origin):
            let refTag = node.ref.map { " [ref=\($0)]" } ?? ""
            let hasExtractedContent = !node.children.isEmpty
            if hasExtractedContent {
                // Frame content was extracted via FrameContentExtractor
                let frameID = node.children.first?.ref?.split(separator: ":").first.map(String.init) ?? ""
                let idTag = frameID.isEmpty ? "" : " (\(frameID))"
                lines.append("\(prefix)- IFRAME \"\(origin)\"\(idTag)\(refTag)")
                for child in node.children {
                    formatNode(child, indent: indent + 1, lines: &lines, context: &context)
                }
            } else {
                // Cross-origin iframe with no extracted content
                lines.append("\(prefix)- IFRAME \"\(origin)\"\(refTag) [cross-origin — use dismiss_cookies or coordinate click]")
            }

        case .overlay:
            // Viewport-constrained elements (fixed headers, modals, etc.)
            formatContainerNode(node, tag: "OVERLAY", indent: indent, lines: &lines, context: &context)

        case .canvas:
            lines.append("\(prefix)- CANVAS")

        case .scrollable:
            for child in node.children {
                formatNode(child, indent: indent, lines: &lines, context: &context)
            }

        case .contentEditable:
            let refTag = node.ref.map { " [ref=\($0)]" } ?? ""
            lines.append("\(prefix)- EDITABLE\(refTag)")
            for child in node.children {
                formatNode(child, indent: indent + 1, lines: &lines, context: &context)
            }

        case .generic:
            // Footer landmark (not a WKTextExtractionContainer case, detected via ARIA role)
            if node.role == "contentinfo" {
                formatLandmarkNode(node, tag: "FOOTER", indent: indent, lines: &lines, context: &context)
                return
            }

            // Generic containers are transparent — just format children
            // Unless they have a meaningful name
            if let name = node.name, !name.isEmpty {
                let refTag = node.ref.map { " [ref=\($0)]" } ?? ""
                let visTag = visibilityTag(node.visibility)
                lines.append("\(prefix)- \"\(truncate(name, maxLength: 120))\"\(refTag)\(visTag)")
                for child in node.children {
                    formatNode(child, indent: indent + 1, lines: &lines, context: &context)
                }
            } else {
                for child in node.children {
                    formatNode(child, indent: indent, lines: &lines, context: &context)
                }
            }
        }
    }

    // MARK: - Landmark & Container Formatting

    /// Formats a landmark node (NAV, FOOTER) with smart summarization.
    ///
    /// Collapsed or offscreen landmarks with many links get a one-line summary
    /// instead of full enumeration. This is the key noise reduction strategy.
    private static func formatLandmarkNode(
        _ node: PageContentNode,
        tag: String,
        indent: Int,
        lines: inout [String],
        context: inout FormatContext,
    ) {
        let prefix = String(repeating: "  ", count: indent)
        let name = node.name.map { " \"\($0)\"" } ?? ""
        let visTag = visibilityTag(node.visibility)
        let refTag = node.ref.map { " [ref=\($0)]" } ?? ""

        // Summarize collapsed or offscreen navs/footers
        if node.visibility == .collapsed || node.visibility == .offscreen {
            let linkCount = countInteractiveChildren(node, role: "link")
            let itemCount = linkCount > 0 ? linkCount : countAllChildren(node)
            if itemCount > 5 {
                lines.append("\(prefix)- \(tag)\(name)\(refTag)\(visTag): \(itemCount) items")
                return
            }
        }

        // Full rendering for visible landmarks or small ones
        lines.append("\(prefix)- \(tag)\(name)\(refTag)\(visTag)")
        for child in node.children {
            formatNode(child, indent: indent + 1, lines: &lines, context: &context)
        }
    }

    /// Formats a container node with standard heading + children pattern.
    private static func formatContainerNode(
        _ node: PageContentNode,
        tag: String,
        indent: Int,
        lines: inout [String],
        context: inout FormatContext,
    ) {
        let prefix = String(repeating: "  ", count: indent)
        let name = node.name.map { " \"\($0)\"" } ?? ""
        let visTag = visibilityTag(node.visibility)
        let refTag = node.ref.map { " [ref=\($0)]" } ?? ""

        // Skip empty containers
        guard !node.children.isEmpty || node.name != nil else { return }

        lines.append("\(prefix)- \(tag)\(name)\(refTag)\(visTag)")
        for child in node.children {
            formatNode(child, indent: indent + 1, lines: &lines, context: &context)
        }
    }

    // MARK: - Progressive Collapse

    /// Re-formats with aggressive collapse of offscreen content.
    private static func reformatWithCollapse(_ tree: PageContentTree, tokenBudget: Int) -> String {
        var lines: [String] = []
        lines.append("# \(tree.metadata.title)")
        lines.append("URL: \(tree.metadata.url)")
        lines.append("Words: \(countWords(in: tree.root))")
        lines.append("")

        var context = FormatContext(
            tokenBudget: tokenBudget,
            scope: .full,
        )

        for child in tree.root.children {
            formatNodeCollapsed(child, indent: 0, lines: &lines, context: &context)
        }

        return lines.joined(separator: "\n")
    }

    /// Formats with aggressive offscreen collapsing.
    private static func formatNodeCollapsed(
        _ node: PageContentNode,
        indent: Int,
        lines: inout [String],
        context: inout FormatContext,
    ) {
        if node.visibility == .hidden { return }

        // Collapse offscreen containers to summaries (but keep text nodes intact)
        if node.visibility == .offscreen, !node.type.isText {
            let childCount = countAllChildren(node)
            if childCount > 3 {
                let prefix = String(repeating: "  ", count: indent)
                let tag = tagForNodeType(node.type)
                let name = node.name.map { " \"\($0)\"" } ?? ""
                let refTag = node.ref.map { " [ref=\($0)]" } ?? ""
                lines.append("\(prefix)- \(tag)\(name)\(refTag) [offscreen]: \(childCount) items")
                return
            }
        }

        formatNode(node, indent: indent, lines: &lines, context: &context)
    }

    // MARK: - Helpers

    private static func visibilityTag(_ visibility: PageContentNode.Visibility) -> String {
        switch visibility {
        case .visible: ""
        case .offscreen: " [offscreen]"
        case .collapsed: " [collapsed]"
        case .hidden: " [hidden]"
        }
    }

    /// Collects all direct text content from a node's children, joining inline text.
    private static func collectTextContent(_ node: PageContentNode) -> String {
        var parts: [String] = []
        collectTextRecursive(node, into: &parts, depth: 0)
        return parts.joined(separator: " ")
    }

    private static func collectTextRecursive(_ node: PageContentNode, into parts: inout [String], depth: Int) {
        guard depth < 4 else { return } // Don't go too deep

        if case let .text(content) = node.type {
            let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                parts.append(trimmed)
            }
            return
        }

        for child in node.children {
            collectTextRecursive(child, into: &parts, depth: depth + 1)
        }
    }

    private static func countInteractiveChildren(_ node: PageContentNode, role: String) -> Int {
        var count = 0
        if node.role == role || (role == "link" && node.type.isLink) {
            count += 1
        }
        for child in node.children {
            count += countInteractiveChildren(child, role: role)
        }
        return count
    }

    private static func countAllChildren(_ node: PageContentNode) -> Int {
        node.children.reduce(0) { $0 + 1 + countAllChildren($1) }
    }

    /// Counts words across all text nodes in a subtree.
    private static func countWords(in node: PageContentNode, visibleOnly: Bool = false) -> Int {
        if visibleOnly, node.visibility == .offscreen || node.visibility == .hidden {
            return 0
        }
        var count = 0
        if case let .text(content) = node.type {
            count += content.split(whereSeparator: \.isWhitespace).count
        }
        for child in node.children {
            count += countWords(in: child, visibleOnly: visibleOnly)
        }
        return count
    }

    private static func truncate(_ string: String, maxLength: Int) -> String {
        if string.count <= maxLength { return string }
        return String(string.prefix(maxLength - 1)) + "…"
    }

    private static func shortenURL(_ urlString: String) -> String {
        guard urlString.count > 60 else { return urlString }
        // Just show domain + path start
        if let url = URL(string: urlString), let host = url.host {
            let path = url.path
            if path.count > 30 {
                return "\(host)\(String(path.prefix(30)))…"
            }
            return "\(host)\(path)"
        }
        return String(urlString.prefix(60)) + "…"
    }

    private static func tagForNodeType(_ type: PageContentNode.NodeType) -> String {
        switch type {
        case .root: "ROOT"
        case .overlay: "OVERLAY"
        case .navigation: "NAV"
        case .section: "SECTION"
        case .article: "ARTICLE"
        case .list: "LIST"
        case .listItem: "ITEM"
        case .blockquote: "QUOTE"
        case .button: "BTN"
        case .canvas: "CANVAS"
        case .form: "FORM"
        case .generic: "BLOCK"
        case .text: "TEXT"
        case .link: "LINK"
        case .image: "IMG"
        case .formControl: "INPUT"
        case .select: "SELECT"
        case .iframe: "IFRAME"
        case .scrollable: "SCROLL"
        case .contentEditable: "EDITABLE"
        }
    }
}

// MARK: - Format Context

private struct FormatContext {
    let tokenBudget: Int
    let scope: PageContentFormatter.Scope
    var offscreenElements = 0
}

// MARK: - NodeType Helpers

extension PageContentNode.NodeType {
    var isLink: Bool {
        if case .link = self { return true }
        return false
    }

    var isText: Bool {
        if case .text = self { return true }
        return false
    }
}

// MARK: - Ref Lookup

extension PageContentTree {
    /// Finds a node by its agent-facing ref (e.g., "e1").
    func findNode(byRef ref: String) -> PageContentNode? {
        findNodeRecursive(in: root, ref: ref)
    }

    private func findNodeRecursive(in node: PageContentNode, ref: String) -> PageContentNode? {
        if node.ref == ref { return node }
        for child in node.children {
            if let found = findNodeRecursive(in: child, ref: ref) {
                return found
            }
        }
        return nil
    }

    /// Returns the native node identifier for a given agent ref.
    ///
    /// Used to bridge between the agent's `[ref=eN]` references and WebKit's
    /// `_performInteraction:` API. Returns nil for frame-prefixed refs since
    /// cross-origin iframe elements don't have native identifiers.
    func nativeID(forRef ref: String) -> String? {
        findNode(byRef: ref)?.nativeID
    }

    /// Whether a ref points to an element inside a cross-origin iframe.
    ///
    /// Frame-prefixed refs have the format `f<N>:e<M>` (e.g., "f1:e3").
    static func isFrameRef(_ ref: String) -> Bool {
        ref.contains(":") && ref.hasPrefix("f")
    }

    /// Splits a frame-prefixed ref into its frame ID and element index.
    ///
    /// - Parameter ref: A frame-prefixed ref (e.g., "f1:e3").
    /// - Returns: A tuple of (frameID: "f1", elementIndex: 3), or nil if not a frame ref.
    static func parseFrameRef(_ ref: String) -> (frameID: String, elementIndex: Int)? {
        guard isFrameRef(ref) else { return nil }
        let parts = ref.split(separator: ":")
        guard parts.count == 2,
              let index = Int(parts[1].dropFirst()) // drop "e" prefix
        else { return nil }
        return (frameID: String(parts[0]), elementIndex: index)
    }

    /// Summary of an interactive element for agent use.
    struct InteractiveElement: Sendable {
        let ref: String
        let nativeID: String?
        let name: String?
        let type: PageContentNode.NodeType
    }

    /// All interactive nodes with refs, as a flat list.
    var interactiveElements: [InteractiveElement] {
        var result: [InteractiveElement] = []
        collectInteractive(from: root, into: &result)
        return result
    }

    private func collectInteractive(
        from node: PageContentNode,
        into result: inout [InteractiveElement],
    ) {
        if let ref = node.ref {
            result.append(InteractiveElement(ref: ref, nativeID: node.nativeID, name: node.name, type: node.type))
        }
        for child in node.children {
            collectInteractive(from: child, into: &result)
        }
    }
}
