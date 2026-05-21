import SwiftUI

/// Wrapper view for the reference pane window content.
///
/// Contains the web content, toolbar overlay at top, and command lens.
/// The toolbar is implemented in SwiftUI (not NSToolbar) for better control
/// over the Liquid Glass aesthetic.
struct ReferencePaneWindowContentView: View {
    @Environment(TabManager.self) private var tabManager
    @Environment(WindowState.self) private var windowState
    @Environment(CommandLensManager.self) private var commandLensManager

    private enum Layout {
        static let toolbarHeight: CGFloat = 40
        static let minWindowWidth: CGFloat = 450
        static let minWindowHeight: CGFloat = 400
        static let blurRadius: CGFloat = 8
        static let tintOpacity: CGFloat = 0.2
    }

    private var displayedTab: Tab? {
        windowState.activeReferenceTab
    }

    private var activeWebPage: WebPage? {
        guard let tab = displayedTab else { return nil }
        return tabManager.pagePool.existingPage(for: tab.activePage)
    }

    /// Whether the page has a sticky header (WebKit or JS detected fixed-position elements).
    private var hasStickyHeader: Bool {
        activeWebPage?.hasStickyHeader ?? false
    }

    /// The tint color for the toolbar blur.
    /// Uses sampled page top color if available, otherwise falls back to space background.
    private var toolbarTintColor: Color {
        activeWebPage?.sampledPageTopColor ?? Color(windowState.backgroundColor.color)
    }

    var body: some View {
        // Read tabListVersion to establish observation dependency.
        // This ensures the view re-renders when reference tabs change,
        // since displayedTab uses computed properties on Space (@Model) which
        // don't participate in SwiftUI observation.
        // swiftlint:disable:next redundant_discardable_let
        let _ = tabManager.state.tabListVersion

        ZStack(alignment: .top) {
            webContent
            toolbarArea.zIndex(1)

            if windowState.showsReferencePaneLens {
                commandLensOverlay.zIndex(2)
            }
        }
        .frame(minWidth: Layout.minWindowWidth, minHeight: Layout.minWindowHeight)
        .animation(.spring(duration: 0.2), value: windowState.showsReferencePaneLens)
        .task(id: activeWebPage?.url) {
            await activeWebPage?.detectStickyHeader()
        }
    }

    // MARK: - Web Content

    private var webContent: some View {
        ReferencePaneContentView(isInSeparateWindow: true)
            .ignoresSafeArea()
            // Disable automatic content inset adjustment - we manually set the inset
            // to match the toolbar height. Automatic adjustment would conflict and
            // cause insets to reset during window drag operations.
            .webViewAutomaticallyAdjustsContentInsets(false)
            .webViewTopContentInset(Layout.toolbarHeight)
            // Enable automatic content inset background fill for scroll pocket system.
            // This enables sticky header detection via prefersSolidColorHardScrollPocket.
            .webViewUsesAutomaticContentInsetBackgroundFill(true)
    }

    // MARK: - Toolbar Area

    private var toolbarArea: some View {
        VStack(spacing: 0) {
            ReferencePaneWindowToolbar(onReturnToDock: returnToDock)
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

    // MARK: - Command Lens Overlay

    private var commandLensOverlay: some View {
        ZStack {
            clickCaptureBackground
            commandLensContent
        }
        .transition(.opacity.combined(with: .scale(scale: 0.95)))
    }

    private var clickCaptureBackground: some View {
        Color.clear
            .contentShape(Rectangle())
            .ignoresSafeArea()
            .onTapGesture {
                commandLensManager.reset()
                windowState.closeReferencePaneLens()
            }
    }

    private var commandLensContent: some View {
        VStack {
            CommandLensView()
                .smallStyle()
                .frame(maxWidth: 600)
                .padding(.horizontal, 20)
                .padding(.top, 60)
                .shadow(color: .black.opacity(0.3), radius: 40, y: 20)

            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func returnToDock() {
        guard let controller = tabManager.windowManager.activeWindowController else { return }
        tabManager.windowManager.returnReferencePaneToDock(for: controller)
    }
}
