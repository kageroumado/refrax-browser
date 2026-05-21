import SwiftUI
import WebKit

// MARK: - Button Style

/// Shared style for reader toolbar buttons with consistent sizing and appearance.
private struct ReaderToolbarButtonStyle: ButtonStyle {
    private let buttonSize: CGFloat = 36
    private let iconSize: CGFloat = 16

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: iconSize))
            .frame(width: buttonSize, height: buttonSize)
            .foregroundStyle(.primary)
            .contentShape(Rectangle())
    }
}

/// ViewModifier that applies glass effect styling with hover background and optional union grouping.
private struct ReaderToolbarGlassModifier: ViewModifier {
    let tintColor: Color
    let tintOpacity: Double
    let unionID: String?
    let namespace: Namespace.ID?

    @State private var isHovered = false

    func body(content: Content) -> some View {
        Group {
            if let unionID, let namespace {
                content
                    .background(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
                    .onHover { isHovered = $0 }
                    .clipShape(Circle().inset(by: 4))
                    .glassEffect(.regular.tint(tintColor.opacity(tintOpacity)))
                    .glassEffectUnion(id: unionID, namespace: namespace)
            } else {
                content
                    .background(isHovered ? Color.secondary.opacity(0.1) : Color.clear)
                    .clipShape(Circle())
                    .onHover { isHovered = $0 }
                    .glassEffect(.regular.tint(tintColor.opacity(tintOpacity)))
            }
        }
    }
}

private extension View {
    func readerToolbarGlass(
        tintColor: Color,
        tintOpacity: Double,
        unionID: String? = nil,
        namespace: Namespace.ID? = nil,
    ) -> some View {
        modifier(ReaderToolbarGlassModifier(
            tintColor: tintColor,
            tintOpacity: tintOpacity,
            unionID: unionID,
            namespace: namespace,
        ))
    }
}

/// A distraction-free view for reading extracted article content.
///
/// Displays the article title, byline, read time, and content with
/// customizable typography based on user preferences. The view uses
/// a WKWebView to render HTML content with consistent styling.
struct ReaderView: View {
    let article: ExtractedArticle
    let tabID: UUID

    @Environment(BrowserSettings.self) private var settings
    @Environment(ReaderModeManager.self) private var readerManager
    @Environment(WindowState.self) private var windowState

    @Environment(\.colorScheme) private var colorScheme
    @State private var showsPreferences = false
    @State private var speedReaderWindow: SpeedReaderWindowController?
    @State private var scrollProgress: Double = 0

    @Namespace private var glassNamespace

    // MARK: - Layout Constants

    private enum Layout {
        static let buttonSize: CGFloat = 36
        static let iconSize: CGFloat = 16
        static let buttonSpacing: CGFloat = 8
        static let groupSpacing: CGFloat = 16
        static let headerPaddingVertical: CGFloat = 16
        /// Total header height for HTML content inset
        static let headerHeight: CGFloat = buttonSize + (headerPaddingVertical * 2)
    }

    private var preferences: ReaderPreferences {
        readerManager.preferences
    }

    /// Remaining reading time based on scroll position.
    private var remainingReadTimeString: String {
        let totalMinutes = article.estimatedReadTime
        let remainingFraction = max(0, 1 - scrollProgress)
        let remainingMinutes = Int(ceil(Double(totalMinutes) * remainingFraction))

        if remainingMinutes == 0 {
            return "Finished"
        }

        if remainingMinutes < 60 {
            return "~\(remainingMinutes) min left"
        }

        let hours = remainingMinutes / 60
        let mins = remainingMinutes % 60
        if mins == 0 {
            return "~\(hours) hr left"
        }
        return "~\(hours) hr \(mins) min left"
    }

    var body: some View {
        ZStack(alignment: .top) {
            contentView
                .background(preferences.theme.backgroundColor(for: colorScheme))
                .ignoresSafeArea()

            headerView
        }
    }

    private var tintOpacity: Double {
        settings.windowBackgroundMixAmount * 0.2
    }

    private var tintColor: Color {
        Color(windowState.backgroundColor.color)
    }

    // MARK: - Header

    private var headerView: some View {
        HStack(spacing: Layout.groupSpacing) {
            backButton
            
            readingInfoView

            Spacer()

            // Right: Buttons with glass effects
            GlassEffectContainer(spacing: Layout.groupSpacing) {
                HStack(spacing: 16) {
                    speedReadButton
                    
                    preferencesButton
                    
                    HStack(spacing: Layout.buttonSpacing) {
                        shareButton
                        copyMarkdownButton
                        saveButton
                    }
                }
            }
        }
        .padding(Layout.headerPaddingVertical)
        .background {
            VariableBackdropBlurView(
                edge: .top,
                tintColor: tintColor,
            )
        }
    }

    // MARK: - Reading Info

    private var readingInfoView: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let siteName = article.siteName {
                Text(siteName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            // Show remaining time when scrolling, total time otherwise
            Text(scrollProgress > 0.05 ? remainingReadTimeString : article.readTimeString)
                .font(.body)
                .foregroundStyle(.secondary)
                .contentTransition(.numericText())
                .animation(.easeInOut(duration: 0.2), value: scrollProgress)
        }
    }

    // MARK: - Toolbar Buttons
    
    private var backButton: some View {
        Button(action: exitReaderMode) {
            Image(systemName: "chevron.left")
        }
        .buttonStyle(ReaderToolbarButtonStyle())
        .help("Exit Reader Mode")
        .readerToolbarGlass(tintColor: tintColor, tintOpacity: tintOpacity)
    }

    private func exitReaderMode() {
        readerManager.deactivateReader(for: tabID)
    }

    private var shareButton: some View {
        Button(action: showShareSheet) {
            Image(systemName: "square.and.arrow.up")
        }
        .buttonStyle(ReaderToolbarButtonStyle())
        .help("Share Article")
        .readerToolbarGlass(
            tintColor: tintColor,
            tintOpacity: tintOpacity,
            unionID: "export",
            namespace: glassNamespace,
        )
    }

    private var copyMarkdownButton: some View {
        Button(action: copyMarkdownToClipboard) {
            Image(systemName: "doc.on.clipboard")
        }
        .buttonStyle(ReaderToolbarButtonStyle())
        .help("Copy as Markdown")
        .readerToolbarGlass(
            tintColor: tintColor,
            tintOpacity: tintOpacity,
            unionID: "export",
            namespace: glassNamespace,
        )
    }

    private var saveButton: some View {
        Button { Task { await saveAsMarkdown() } } label: {
            Image(systemName: "arrow.down.doc")
        }
        .buttonStyle(ReaderToolbarButtonStyle())
        .help("Save as Markdown")
        .readerToolbarGlass(
            tintColor: tintColor,
            tintOpacity: tintOpacity,
            unionID: "export",
            namespace: glassNamespace,
        )
    }

    private var speedReadButton: some View {
        Button(action: openSpeedReader) {
            Image(systemName: "gauge.with.dots.needle.67percent")
        }
        .buttonStyle(ReaderToolbarButtonStyle())
        .help("Speed Read (Cmd+Shift+R)")
        .keyboardShortcut("r", modifiers: [.command, .shift])
        .readerToolbarGlass(tintColor: tintColor, tintOpacity: tintOpacity)
    }

    private var preferencesButton: some View {
        Button { showsPreferences.toggle() } label: {
            Image(systemName: "textformat.size")
        }
        .buttonStyle(ReaderToolbarButtonStyle())
        .help("Reading Preferences")
        .readerToolbarGlass(tintColor: tintColor, tintOpacity: tintOpacity)
        .if(showsPreferences) { view in
            view.popover(isPresented: $showsPreferences, arrowEdge: .bottom) {
                ReaderPreferencesPopover()
            }
        }
    }

    // MARK: - Export Actions

    private func showShareSheet() {
        guard let window = NSApp.keyWindow else { return }
        // Position near the top-right where the share button is
        let position = CGPoint(x: window.frame.width - 100, y: window.frame.height - 60)
        ArticleShareHelper.showShareSheet(for: article, at: position, in: window)
    }

    private func saveAsMarkdown() async {
        let window = NSApp.keyWindow
        let service = ReaderExportService(article: article)
        await service.saveAsMarkdown(from: window)
    }

    private func copyMarkdownToClipboard() {
        let service = ReaderExportService(article: article)
        let markdown = service.exportAsMarkdown()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
        windowState.showToast("Copied to clipboard")
    }

    // MARK: - Speed Reader

    private func openSpeedReader() {
        // Close existing window if any
        speedReaderWindow?.close()

        // Get resume position from settings (if any)
        let startIndex = settings.speedReaderResumePosition(for: article.sourceURL) ?? 0

        // Create and show new Speed Reader panel attached to current window
        let controller = SpeedReaderWindowController(
            article: article,
            settings: settings,
            startIndex: startIndex,
            parentWindow: NSApp.keyWindow,
        )
        controller.showCentered()
        speedReaderWindow = controller
    }

    // MARK: - Content

    private var contentView: some View {
        ReaderContentWebView(
            article: article,
            preferences: preferences,
            colorScheme: colorScheme,
            headerInset: Layout.headerHeight,
            scrollProgress: $scrollProgress,
        )
    }
}

// MARK: - Content WebView

/// WebView wrapper for rendering article HTML with reader styling.
private struct ReaderContentWebView: NSViewRepresentable {
    let article: ExtractedArticle
    let preferences: ReaderPreferences
    let colorScheme: ColorScheme
    let headerInset: CGFloat
    @Binding var scrollProgress: Double

    /// Captures the inputs that affect HTML generation for efficient change detection.
    fileprivate struct ContentInputs: Equatable {
        let articleURL: URL?
        let preferences: ReaderPreferences
        let colorScheme: ColorScheme
        let headerInset: CGFloat
    }

    private var currentInputs: ContentInputs {
        ContentInputs(
            articleURL: article.sourceURL,
            preferences: preferences,
            colorScheme: colorScheme,
            headerInset: headerInset,
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(scrollProgress: $scrollProgress)
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.isElementFullscreenEnabled = false

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isInspectable = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.uiDelegate = context.coordinator

        // Enable scroll geometry updates via WebKit private API
        webView._setNeedsScrollGeometryUpdates(true)

        // Load initial content
        webView.loadHTMLString(generateHTML(), baseURL: article.sourceURL)
        context.coordinator.lastLoadedInputs = currentInputs

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        // Only reload if inputs changed - not on scroll progress updates
        let inputs = currentInputs
        guard inputs != context.coordinator.lastLoadedInputs else { return }

        webView.loadHTMLString(generateHTML(), baseURL: article.sourceURL)
        context.coordinator.lastLoadedInputs = inputs
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKUIDelegate {
        @Binding var scrollProgress: Double
        fileprivate var lastLoadedInputs: ContentInputs?

        init(scrollProgress: Binding<Double>) {
            _scrollProgress = scrollProgress
        }

        /// Private WebKit delegate method for scroll geometry changes.
        @objc(_webView:geometryDidChange:)
        func _webView(_: WKWebView!, geometryDidChange geometry: WKScrollGeometry!) {
            guard let geometry else { return }

            let contentHeight = geometry.contentSize.height
            let containerHeight = geometry.containerSize.height
            let scrollOffset = geometry.contentOffset.y
            let contentInsetTop = geometry.contentInsets.top

            // Calculate scroll progress (0 at top, 1 at bottom)
            let scrollableHeight = contentHeight - containerHeight + contentInsetTop
            guard scrollableHeight > 0 else {
                scrollProgress = 0
                return
            }

            let progress = max(0, min(1, scrollOffset / scrollableHeight))
            MainActor.assumeIsolated {
                scrollProgress = progress
            }
        }
    }

    private func generateHTML() -> String {
        let theme = preferences.theme
        let bgColor = colorToHex(theme.backgroundColor(for: colorScheme))
        let textColor = colorToHex(theme.textColor(for: colorScheme))
        let linkColor = colorToHex(theme.linkColor(for: colorScheme))

        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <style>
                * {
                    box-sizing: border-box;
                }
                html, body {
                    margin: 0;
                    padding: 0;
                    background: \(bgColor);
                    color: \(textColor);
                    font-family: \(preferences.fontFamily.cssFontFamily);
                    font-size: \(preferences.fontSize)px;
                    line-height: \(preferences.lineHeight);
                    -webkit-font-smoothing: antialiased;
                }
                .container {
                    max-width: \(preferences.maxWidth)px;
                    margin: 0 auto;
                    padding: \(Int(headerInset))px 20px 60px;
                }
                .header {
                    margin-bottom: 32px;
                }
                .title {
                    font-size: 2em;
                    font-weight: 700;
                    line-height: 1.2;
                    margin: 0 0 12px;
                }
                .byline {
                    color: \(textColor);
                    opacity: 0.7;
                    font-size: 0.9em;
                    margin: 0;
                }
                .content {
                    word-wrap: break-word;
                    overflow-wrap: break-word;
                }
                .content p {
                    margin: 0 0 1em;
                }
                .content h1, .content h2, .content h3, .content h4 {
                    font-weight: 600;
                    line-height: 1.3;
                    margin: 1.5em 0 0.5em;
                }
                .content h1 { font-size: 1.5em; }
                .content h2 { font-size: 1.3em; }
                .content h3 { font-size: 1.15em; }
                .content a {
                    color: \(linkColor);
                    text-decoration: none;
                }
                .content a:hover {
                    text-decoration: underline;
                }
                .content img {
                    max-width: 100%;
                    height: auto;
                    border-radius: 8px;
                    margin: 1em 0;
                }
                .content figure {
                    margin: 1.5em 0;
                }
                .content figcaption {
                    font-size: 0.85em;
                    opacity: 0.7;
                    margin-top: 8px;
                    text-align: center;
                }
                .content blockquote {
                    margin: 1em 0;
                    padding: 0.5em 1em;
                    border-left: 3px solid \(linkColor);
                    opacity: 0.9;
                    font-style: italic;
                }
                .content pre, .content code {
                    font-family: 'SF Mono', Menlo, Monaco, monospace;
                    font-size: 0.9em;
                    background: rgba(128, 128, 128, 0.1);
                    border-radius: 4px;
                }
                .content pre {
                    padding: 1em;
                    overflow-x: auto;
                }
                .content code {
                    padding: 0.2em 0.4em;
                }
                .content pre code {
                    padding: 0;
                    background: none;
                }
                .content ul, .content ol {
                    margin: 1em 0;
                    padding-left: 1.5em;
                }
                .content li {
                    margin: 0.3em 0;
                }
                .content table {
                    width: 100%;
                    border-collapse: collapse;
                    margin: 1em 0;
                }
                .content th, .content td {
                    border: 1px solid rgba(128, 128, 128, 0.3);
                    padding: 8px 12px;
                    text-align: left;
                }
                .content th {
                    background: rgba(128, 128, 128, 0.1);
                }
            </style>
        </head>
        <body>
            <div class="container">
                <header class="header">
                    <h1 class="title">\(escapeHTML(article.title))</h1>
                    \(article.byline.map { "<p class=\"byline\">\(escapeHTML($0))</p>" } ?? "")
                </header>
                <article class="content">
                    \(article.content)
                </article>
            </div>
        </body>
        </html>
        """
    }

    private func colorToHex(_ color: Color) -> String {
        let nsColor = NSColor(color)
        guard let rgb = nsColor.usingColorSpace(.sRGB) else {
            return "#000000"
        }
        let r = Int(rgb.redComponent * 255)
        let g = Int(rgb.greenComponent * 255)
        let b = Int(rgb.blueComponent * 255)
        return String(format: "#%02X%02X%02X", r, g, b)
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
