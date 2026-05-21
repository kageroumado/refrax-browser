import AppKit
import SwiftUI

/// State for a reflected (mirrored) window.
///
/// Provides the state needed by SwiftUI views to display the reflected page content.
@Observable
final class ReflectedWindowState {
    /// Reference to the displayed page.
    weak var webPage: WebPage?

    /// Window reference (set after init).
    weak var window: NSWindow?

    init(webPage: WebPage) {
        self.webPage = webPage
    }

    /// Title to display in the toolbar.
    var title: String {
        webPage?.title ?? webPage?.url?.host ?? "Reflected View"
    }

    /// URL for display purposes.
    var url: URL? {
        webPage?.url
    }
}

/// Controller for a reflected view window.
///
/// A reflected window displays a WebPage in a separate window using the
/// owner/portal mechanism. When this window is key, it claims ownership
/// of the WebPage's interactive WebView. Other windows automatically
/// switch to portal mode.
///
/// ## Behavior
///
/// - Remains live even when the source tab switches to another page
/// - Fully interactive when this window is key
/// - Properly swaps ownership between windows
///
/// ## Usage
///
/// Create via `WebPage.createReflectedWindow(environment:)`.
final class ReflectedViewController: NSWindowController, NSWindowDelegate {
    // MARK: - Properties

    private let webPage: WebPage
    private let windowState: ReflectedWindowState
    private let environment: RefraxEnvironment

    /// Unique identifier for ownership tracking.
    private var ownershipID: ObjectIdentifier {
        ObjectIdentifier(self)
    }

    // MARK: - Initialization

    /// Creates a reflected window controller for the given WebPage.
    ///
    /// - Parameters:
    ///   - webPage: The WebPage to display.
    ///   - environment: The Refrax environment for SwiftUI injection.
    init(webPage: WebPage, environment: RefraxEnvironment) {
        self.webPage = webPage
        self.environment = environment
        self.windowState = ReflectedWindowState(webPage: webPage)

        // Use ReferencePaneWindow for consistent appearance with Glimpse
        let window = ReferencePaneWindow()
        super.init(window: window)

        windowState.window = window
        window.delegate = self
        setupContentView()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupContentView() {
        guard let window else { return }

        let view = ReflectedContentView(
            webPage: webPage,
            windowState: windowState,
            ownershipID: ownershipID,
        )
        .refraxEnvironment(environment)

        window.contentViewController = NSHostingController(rootView: view)
    }

    // MARK: - Public Interface

    /// Shows the reflected window relative to a source window.
    ///
    /// Matches the size of the source WebView if available.
    ///
    /// - Parameter sourceWindow: The window to position relative to.
    func showRelativeTo(_ sourceWindow: NSWindow?) {
        guard let window else { return }

        // Claim ownership BEFORE showing the window.
        // This prevents a race condition where the main window's WebViewContainer
        // might reclaim the WebView during the gap between makeKeyAndOrderFront
        // and windowDidBecomeKey.
        webPage.claimOwnership(id: ownershipID)

        // Use the WebView's actual bounds for size
        let webViewBounds = webPage.backingWebView.bounds
        var size = NSSize(width: webViewBounds.width, height: webViewBounds.height)

        // Fallback to default if bounds are invalid
        if size.width < 100 || size.height < 100 {
            size = NSSize(width: 800, height: 600)
        }

        window.setContentSize(size)

        if let source = sourceWindow {
            let origin = NSPoint(
                x: source.frame.maxX + 20,
                y: source.frame.midY - size.height / 2,
            )
            window.setFrameOrigin(origin)
        } else {
            window.center()
        }

        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - NSWindowDelegate

    func windowDidBecomeKey(_: Notification) {
        // Reinforce ownership when window becomes key (in case it was lost)
        if webPage.ownerWindowID != ownershipID {
            webPage.claimOwnership(id: ownershipID)
        }
    }

    func windowWillClose(_: Notification) {
        // Release ownership back to wherever it came from
        webPage.releaseOwnership(id: ownershipID)
        // Remove from tracking
        webPage.reflectedWindowDidClose(self)
    }
}

// MARK: - Reflected Content View

/// SwiftUI content view for reflected windows.
///
/// Displays the WebPage with a minimal toolbar showing the page title.
private struct ReflectedContentView: View {
    let webPage: WebPage
    let windowState: ReflectedWindowState
    let ownershipID: ObjectIdentifier

    private enum Layout {
        static let toolbarHeight: CGFloat = 40
        static let minWindowWidth: CGFloat = 450
        static let minWindowHeight: CGFloat = 400
        static let blurRadius: CGFloat = 8
        static let tintOpacity: CGFloat = 0.2
    }

    /// Whether the page has a sticky header (WebKit or JS detected fixed-position elements).
    private var hasStickyHeader: Bool {
        webPage.hasStickyHeader
    }

    /// The tint color for the toolbar blur.
    /// Uses sampled page top color if available, otherwise falls back to clear.
    private var toolbarTintColor: Color {
        webPage.sampledPageTopColor ?? .clear
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Web content - extends under toolbar
            webContent
            // Toolbar with address bar
            toolbarArea.zIndex(1)
        }
        .frame(minWidth: Layout.minWindowWidth, minHeight: Layout.minWindowHeight)
        .task(id: webPage.url) {
            await webPage.detectStickyHeader()
        }
    }

    private var webContent: some View {
        // Use WebViewContainer for full browser chrome integration (link previews,
        // dialog handling, etc.). The custom ownership ID enables the container
        // to work with controller-managed ownership rather than WindowState.
        WebViewContainer(page: webPage)
            .webViewOwnershipID(ownershipID)
            .ignoresSafeArea()
            // Disable automatic content inset adjustment - we manually set the inset
            // to match the toolbar height. Automatic adjustment would conflict and
            // cause insets to reset during window drag operations.
            .webViewAutomaticallyAdjustsContentInsets(false)
            .webViewTopContentInset(Layout.toolbarHeight)
            // Enable automatic content inset background fill for scroll pocket system.
            .webViewUsesAutomaticContentInsetBackgroundFill(true)
    }

    private var toolbarArea: some View {
        VStack(spacing: 0) {
            ReflectedWindowToolbar(windowState: windowState)
                .frame(height: Layout.toolbarHeight)
                .background { toolbarBackground }
        }
        .frame(maxWidth: .infinity)
        .ignoresSafeArea()
    }

    private var toolbarBackground: some View {
        ZStack {
            // Blur layer - variable for smooth scroll effect, uniform for sticky headers
            if hasStickyHeader {
                BackdropBlurView(blurRadius: Layout.blurRadius)
            } else {
                VariableBackdropBlurView(edge: .top, maxBlurRadius: Layout.blurRadius)
            }

            // Color tint overlay
            toolbarTintColor.opacity(Layout.tintOpacity)
        }
    }
}

// MARK: - Reflected Window Toolbar

/// Toolbar for reflected windows with address bar.
///
/// Matches the Reference Pane and Glimpse toolbar pattern.
private struct ReflectedWindowToolbar: View {
    let windowState: ReflectedWindowState

    private enum Layout {
        static let horizontalPadding: CGFloat = 12
        static let trafficLightWidth: CGFloat = 78
        static let spacing: CGFloat = 8
        static let buttonHeight: CGFloat = 24
    }

    private var addressBarContext: AddressBarContext {
        AddressBarContext(
            webPage: windowState.webPage,
            tabPage: nil, // No TabPage for reflected windows
            onOpenLens: {}, // No lens for reflected windows
            isLensVisible: false,
            onShowFindNavigator: {},
        )
    }

    var body: some View {
        CenteredMiddleLayout {
            leadingContent
            centerContent
            trailingContent
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    private var leadingContent: some View {
        Color.clear.frame(width: Layout.trafficLightWidth)
    }

    private var centerContent: some View {
        AddressBar()
            .environment(\.addressBarContext, addressBarContext)
            .environment(\.addressBarIsFloating, true)
            .frame(height: Layout.buttonHeight)
            .frame(minWidth: 150, maxWidth: 400)
            .glassEffect()
    }

    private var trailingContent: some View {
        Color.clear.frame(width: Layout.horizontalPadding)
    }
}
