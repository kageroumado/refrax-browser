import AppKit
import Combine
import SwiftUI

/// A lightweight window controller for ephemeral browsing sessions.
///
/// Glimpse windows provide minimal UI (address bar + navigation only), no sidebar,
/// and are designed for quick browsing tasks. They can be opened via:
/// - Option+Enter from Command Lens
/// - Option+Click on a link
/// - Configured to receive external URLs from other applications
///
/// ## Naming
///
/// "Glimpse" (空一瞥) evokes light, speed, and ephemeral browsing.
/// Matches Refrax's design philosophy of quick, focused interactions.
///
/// ## Architecture
///
/// Uses `ReferencePaneWindow` for consistent styling. The SwiftUI content view
/// provides an address bar and space transfer button in a toolbar overlay.
///
/// ## Lifecycle
///
/// Glimpse windows are not restored across app restarts. When closed, the WebPage
/// is properly terminated and removed from the pool.
///
/// ## Transfer to Space
///
/// Users can transfer the current page to any space by clicking the
/// "Open in [Space]" dropdown button. This creates a new tab in the selected space
/// and closes the Glimpse window.
final class GlimpseController: NSWindowController, NSWindowDelegate {
    // MARK: - Dependencies

    /// Reference to the environment for injecting into SwiftUI views.
    private let environment: RefraxEnvironment

    /// Reference to the window manager for cleanup.
    private unowned let windowManager: WindowManager

    /// Reference to the tab manager for creating tabs on transfer.
    private unowned let tabManager: TabManager

    // MARK: - Page State

    /// The ephemeral tab page for this Glimpse window.
    ///
    /// This TabPage is not inserted into any ModelContext, making it transient.
    let tabPage: TabPage

    /// The web page rendering the content.
    ///
    /// Created from the shared WebPagePool. Removed from pool when window closes.
    private(set) var webPage: WebPage?

    /// Observable state for the Glimpse window.
    private let glimpseState: GlimpseWindowState

    /// When true, skip cleanup on close (WebPage was transferred to a new tab).
    private var skipCleanup = false

    // MARK: - Initialization

    /// Creates a Glimpse window for the given URL.
    ///
    /// - Parameters:
    ///   - url: The URL to load.
    ///   - environment: The environment for SwiftUI injection.
    ///   - windowManager: The window manager for lifecycle management.
    ///   - tabManager: The tab manager for page pool access and tab creation.
    init(
        url: URL,
        environment: RefraxEnvironment,
        windowManager: WindowManager,
        tabManager: TabManager,
    ) {
        self.environment = environment
        self.windowManager = windowManager
        self.tabManager = tabManager

        // Create ephemeral TabPage (not inserted into ModelContext)
        self.tabPage = TabPage(url: url, title: "Loading...")
        self.glimpseState = GlimpseWindowState(
            tabPage: tabPage,
            allSpaces: tabManager.state.spaces,
            activeSpace: windowManager.activeWindowController?.windowState.activeSpace,
        )

        // Use the same window class as reference pane
        let window = ReferencePaneWindow()
        super.init(window: window)

        window.delegate = self
        setupWebPage()
        setupContentView()

        // We don't need to load the URL, the WebPage init calls load automatically.
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Setup

    private func setupWebPage() {
        webPage = tabManager.pagePool.page(for: tabPage)
        glimpseState.webPage = webPage
    }

    private func setupContentView() {
        guard let window else { return }

        let contentView = GlimpseContentView(
            onTransferToSpace: { [weak self] space in
                self?.transferToSpace(space)
            },
        )
        .environment(glimpseState)
        .refraxEnvironment(environment)

        let hostingController = NSHostingController(rootView: contentView)
        window.contentViewController = hostingController
    }

    // MARK: - Window Actions

    /// Shows the Glimpse window centered on screen.
    func showCentered() {
        guard let window else { return }

        window.setContentSize(NSSize(width: 1_280, height: 720))
        window.center()
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    /// Shows the Glimpse window relative to a source window.
    ///
    /// - Parameters:
    ///   - size: Initial size for the window.
    ///   - sourceWindow: The window to position relative to.
    func showWindow(size: NSSize, relativeTo sourceWindow: NSWindow?) {
        guard let window else { return }

        window.setContentSize(size)

        if let sourceWindow {
            let sourceFrame = sourceWindow.frame
            let newOrigin = NSPoint(
                x: sourceFrame.maxX + 20,
                y: sourceFrame.midY - size.height / 2,
            )
            window.setFrameOrigin(newOrigin)
        } else {
            window.center()
        }

        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - Transfer to Space

    /// Transfers the current page to a new tab in the specified space.
    ///
    /// - Parameter space: The space to transfer the page to. If `nil`, uses the active space.
    func transferToSpace(_ space: Space?) {
        guard let url = webPage?.url ?? tabPage.url as URL? else { return }

        let targetSpace = space ?? windowManager.activeWindowController?.windowState.activeSpace
            ?? tabManager.state.spaces.first

        // Check storage mode compatibility
        // Glimpse windows always use global data store (ephemeral, no isolation)
        let sourceMode: DataStoreMode = .global
        let targetMode = targetSpace?.dataStoreMode ?? .global
        let needsReload = sourceMode != targetMode && targetMode != .global

        if needsReload, let targetSpace {
            // Show alert about reload requirement
            presentCompatibilityAlert(space: targetSpace, url: url)
        } else {
            performTransfer(to: targetSpace, url: url)
        }
    }

    private func presentCompatibilityAlert(space: Space, url: URL) {
        guard let window else { return }

        let alert = NSAlert()
        alert.messageText = "Storage Mode Incompatible"
        alert.informativeText = "This page will be reloaded because it was loaded with a different storage mode than \"\(space.name)\"."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reload and Transfer")
        alert.addButton(withTitle: "Cancel")

        alert.beginSheetModal(for: window) { [weak self] response in
            if response == .alertFirstButtonReturn {
                self?.performTransfer(to: space, url: url)
            }
        }
    }

    private func performTransfer(to space: Space?, url: URL) {
        guard let targetSpace = space ?? tabManager.state.spaces.first else { return }

        if webPage != nil {
            // Create tab without loading (we'll transfer the existing WebPage)
            let tab = tabManager.createTab(
                url: url,
                in: targetSpace,
                makeActive: true,
                loadImmediately: false,
            )

            // Transfer the WebPage from Glimpse's ephemeral TabPage to the new Tab's TabPage
            tabManager.pagePool.transferPage(
                from: tabPage,
                to: tab.activePage,
                preserveHistory: true,
            )

            // Close window without cleanup (WebPage is now owned by new tab)
            skipCleanup = true
            close()
        } else {
            // Fallback if not loaded yet - just create and load fresh
            tabManager.createTab(
                url: url,
                in: targetSpace,
                makeActive: true,
                loadImmediately: true,
            )
            close()
        }
    }

    // MARK: - Cleanup

    private func cleanup() {
        if !skipCleanup {
            tabManager.pagePool.removePage(for: tabPage)
        }
        windowManager.removeGlimpseWindow(self)
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_: Notification) {
        cleanup()
    }

    func windowWillResize(_: NSWindow, to frameSize: NSSize) -> NSSize {
        var newSize = frameSize
        newSize.width = max(newSize.width, ReferencePaneWindow.minimumWidth)
        newSize.height = max(newSize.height, ReferencePaneWindow.minimumHeight)
        return newSize
    }
}

// MARK: - Glimpse Window State

/// Observable state for a Glimpse window.
///
/// Provides the state needed for the toolbar and content views to display
/// the current page's information and available spaces for transfer.
@Observable
final class GlimpseWindowState {
    let tabPage: TabPage
    var webPage: WebPage?

    /// All available spaces for the transfer dropdown.
    let allSpaces: [Space]

    /// The default space to transfer to (currently active space).
    let activeSpace: Space?

    var url: URL {
        webPage?.url ?? tabPage.url
    }

    var title: String {
        webPage?.title ?? tabPage.title
    }

    var isLoading: Bool {
        webPage?.isLoading ?? false
    }

    var canGoBack: Bool {
        webPage?.canGoBack ?? false
    }

    var canGoForward: Bool {
        webPage?.canGoForward ?? false
    }

    init(tabPage: TabPage, allSpaces: [Space], activeSpace: Space?) {
        self.tabPage = tabPage
        self.allSpaces = allSpaces
        self.activeSpace = activeSpace
    }
}

// MARK: - Glimpse Content View

/// SwiftUI content view for Glimpse windows.
///
/// Contains the web content with a toolbar overlay at top.
private struct GlimpseContentView: View {
    @Environment(GlimpseWindowState.self) private var glimpseState

    let onTransferToSpace: (Space?) -> Void

    private enum Layout {
        static let toolbarHeight: CGFloat = 40
        static let minWindowWidth: CGFloat = 450
        static let minWindowHeight: CGFloat = 400
        static let blurRadius: CGFloat = 8
        static let tintOpacity: CGFloat = 0.2
    }

    /// Whether the page has a sticky header (WebKit or JS detected fixed-position elements).
    private var hasStickyHeader: Bool {
        glimpseState.webPage?.hasStickyHeader ?? false
    }

    /// The tint color for the toolbar blur.
    /// Uses sampled page top color if available, otherwise falls back to clear.
    private var toolbarTintColor: Color {
        glimpseState.webPage?.sampledPageTopColor ?? .clear
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Web content - extends under toolbar
            webContentView
            // Toolbar at top
            toolbarArea.zIndex(1)
        }
        .frame(minWidth: Layout.minWindowWidth, minHeight: Layout.minWindowHeight)
        .task(id: glimpseState.webPage?.url) {
            await glimpseState.webPage?.detectStickyHeader()
        }
    }

    // MARK: - Web Content

    @ViewBuilder
    private var webContentView: some View {
        if let webPage = glimpseState.webPage {
            WebViewContainer(page: webPage)
                .ignoresSafeArea()
                // Disable automatic content inset adjustment - we manually set the inset
                // to match the toolbar height. Automatic adjustment would conflict and
                // cause insets to reset during window drag operations.
                .webViewAutomaticallyAdjustsContentInsets(false)
                .webViewTopContentInset(Layout.toolbarHeight)
                // Enable automatic content inset background fill for scroll pocket system.
                .webViewUsesAutomaticContentInsetBackgroundFill(true)
        } else {
            Color.clear
        }
    }

    // MARK: - Toolbar Area

    private var toolbarArea: some View {
        VStack(spacing: 0) {
            GlimpseToolbar(
                glimpseState: glimpseState,
                onTransferToSpace: onTransferToSpace,
            )
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

// MARK: - Glimpse Toolbar

/// SwiftUI toolbar for Glimpse windows.
/// Contains address bar and space transfer button.
private struct GlimpseToolbar: View {
    let glimpseState: GlimpseWindowState
    let onTransferToSpace: (Space?) -> Void

    private enum Layout {
        static let horizontalPadding: CGFloat = 12
        static let trafficLightWidth: CGFloat = 78
        static let spacing: CGFloat = 8
        static let buttonHeight: CGFloat = 24
    }

    private var addressBarContext: AddressBarContext {
        AddressBarContext(
            webPage: glimpseState.webPage,
            tabPage: glimpseState.tabPage,
            onOpenLens: {
                // Glimpse windows don't have a full command lens
            },
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
        HStack(spacing: Layout.spacing) {
            // Space transfer button with dropdown
            // Glimpse windows always use global data store mode
            SpaceTransferButton(
                activeSpace: glimpseState.activeSpace,
                allSpaces: glimpseState.allSpaces,
                onTransfer: onTransferToSpace,
            )
        }
        .padding(.trailing, Layout.horizontalPadding)
    }
}

// MARK: - Space Transfer Button

/// A dropdown button for transferring the Glimpse page to a space.
///
/// Shows "Open in [Space Name]" as the primary action with a dropdown
/// for selecting other spaces. Spaces with non-global storage modes are marked
/// since Glimpse windows use global mode.
///
/// When only one space exists, shows a simple button without dropdown.
private struct SpaceTransferButton: View {
    let activeSpace: Space?
    let allSpaces: [Space]
    let onTransfer: (Space?) -> Void

    private enum Layout {
        static let buttonHeight: CGFloat = 24
    }

    private var defaultSpaceName: String {
        activeSpace?.name ?? "Space"
    }

    var body: some View {
        if allSpaces.count > 1 {
            // Multiple spaces: show dropdown menu
            Menu {
                ForEach(allSpaces) { space in
                    Button {
                        onTransfer(space)
                    } label: {
                        HStack {
                            SpaceIcon(space: space)
                            Text(space.name)
                            // Glimpse uses global mode; non-global spaces need reload
                            if space.dataStoreMode != .global {
                                Image(systemName: "arrow.clockwise")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } label: {
                buttonLabel
            } primaryAction: {
                onTransfer(activeSpace)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .frame(height: Layout.buttonHeight)
            .glassEffect()
            .help("Open this page in a new tab")
        } else {
            // Single space: show simple button
            Button {
                onTransfer(activeSpace)
            } label: {
                buttonLabel
            }
            .buttonStyle(.plain)
            .frame(height: Layout.buttonHeight)
            .glassEffect()
            .help("Open this page in a new tab")
        }
    }

    private var buttonLabel: some View {
        Label("Open in \(defaultSpaceName)", systemImage: "arrow.up.forward.app")
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 8)
    }
}

// MARK: - Space Icon

/// Displays a space's icon (SF Symbol or emoji).
private struct SpaceIcon: View {
    let space: Space

    var body: some View {
        if space.iconName.count == 1, space.iconName.unicodeScalars.first?.properties.isEmoji == true {
            Text(space.iconName)
        } else {
            Image(systemName: space.iconName)
        }
    }
}
