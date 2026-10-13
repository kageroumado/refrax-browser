import Security
import SwiftUI
import WebKit

struct AddressBar: View {
    var onPresentationChange: ((Bool) -> Void)?

    @Environment(WindowState.self) private var windowState: WindowState
    @Environment(TabManager.self) private var tabManager: TabManager
    @Environment(BrowserSettings.self) private var settings: BrowserSettings
    @Environment(SharingCoordinator.self) private var sharingCoordinator: SharingCoordinator
    @Environment(ExtensionManager.self) private var extensionManager: ExtensionManager
    @Environment(ReaderModeManager.self) private var readerModeManager: ReaderModeManager
    @Environment(AutoFillState.self) private var autoFillState: AutoFillState
    @Environment(SiteSettingsManager.self) private var siteSettingsManager: SiteSettingsManager
    @Environment(ScreenshotCoordinator.self) private var screenshotCoordinator: ScreenshotCoordinator
    @Environment(RecordingCoordinator.self) private var recordingCoordinator: RecordingCoordinator
    @Environment(EngineRegistry.self) private var engineRegistry: EngineRegistry
    @Environment(DownloadManager.self) private var downloadManager: DownloadManager
    @Environment(WebPagePool.self) private var pagePool: WebPagePool
    @Environment(\.addressBarContext) private var addressBarContext: AddressBarContext?
    @Environment(\.addressBarIsFloating) private var addressBarIsFloating: Bool

    @State private var isHovered = false
    @State private var showsPageMenu = false
    @State private var showsWebpageSettings = false
    @State private var showsSiteCookies = false
    @State private var isReaderAvailable = false

    // Layout measurements for compact mode detection
    @State private var availableWidth: CGFloat = 0
    @State private var navWidth: CGFloat = 0
    @State private var urlWidth: CGFloat = 0
    @State private var hoverButtonsWidth: CGFloat = 0
    @State private var reloadWidth: CGFloat = 0

    /// Cached WebPage to reduce observation chain depth
    @State private var cachedWebPage: WebPage?

    /// Whether compact mode is active (URL and buttons would overlap).
    /// In compact mode, URL dims when hovering to make room for buttons.
    private var isCompactMode: Bool {
        guard availableWidth > 0 else { return false }
        return addressBarIsCompactMode(
            availableWidth: availableWidth,
            navWidth: navWidth,
            urlWidth: urlWidth,
            hoverButtonsWidth: hoverButtonsWidth,
            reloadWidth: reloadWidth,
        )
    }

    private var webPage: WebPage? {
        cachedWebPage
    }

    private var tabID: UUID? {
        webPage?.tabPage.id
    }

    /// Whether reader mode is currently active for this page.
    private var isReaderActive: Bool {
        guard let tabID else { return false }
        return readerModeManager.isReaderActive(for: tabID)
    }

    private var canGoBack: Bool {
        webPage?.canGoBack == true
    }
    private var canGoForward: Bool {
        webPage?.canGoForward == true
    }
    private var isLoading: Bool {
        webPage?.isLoading == true
    }
    private var loadingProgress: Double {
        webPage?.estimatedProgress ?? 0
    }

    private var pageMenuButtonVisible: Bool {
        isHovered || showsPageMenu || showsWebpageSettings
    }

    private var url: URL? {
        (addressBarContext?.tabPage ?? windowState.focusedPage)?.url
    }

    private var displayDomain: String {
        url?.safeDisplayDomain ?? ""
    }

    private var isLensVisible: Bool {
        addressBarContext?.isLensVisible ?? windowState.showsAnchoredLens
    }

    /// The page menu's actions, bound to the page this bar shows.
    private var pageMenuActions: PageMenuActions {
        PageMenuActions(
            webPage: webPage,
            url: url,
            windowState: windowState,
            sharing: sharingCoordinator,
            screenshots: screenshotCoordinator,
            recording: recordingCoordinator,
            downloads: downloadManager,
            extensions: extensionManager,
            readerMode: readerModeManager,
            siteSettings: siteSettingsManager,
            pagePool: pagePool,
        )
    }

    var body: some View {
        AddressBarLayout {
            navigationControls
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
                    if abs(navWidth - new) > 1 {
                        navWidth = new
                    }
                }
            urlDisplayView
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
                    if abs(urlWidth - new) > 1 {
                        urlWidth = new
                    }
                }
            hoverButtonsView
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
                    if abs(hoverButtonsWidth - new) > 1 {
                        hoverButtonsWidth = new
                    }
                }
            trailingControlsView
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
                    if abs(reloadWidth - new) > 1 {
                        reloadWidth = new
                    }
                }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
            if abs(availableWidth - new) > 1 {
                availableWidth = new
            }
        }
        .padding(.horizontal, 6)
        .frame(height: Constants.AddressBar.height)
        .overlay(alignment: .bottom) {
            loadingIndicator
        }
        .glassEffect(addressBarIsFloating ? .identity : .regular, in: Capsule())
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
        .onChange(of: showsPageMenu || showsWebpageSettings || showsSiteCookies) { _, presented in
            onPresentationChange?(presented)
        }
        .onDisappear { onPresentationChange?(false) }
        .onTapGesture {
            if let context = addressBarContext {
                context.onOpenLens()
            } else if url != nil {
                windowState.editAddress()
            } else {
                windowState.openCommandLens()
            }
        }
        .accessibilityIdentifier("addressbar")
        .opacity(isLensVisible ? 0 : 1)
        .background(frameReader)
        .task {
            await PublicSuffixList.shared.loadIfNeeded()
        }
        .onChange(of: url) { _, _ in
            // Deactivate reader mode when URL changes (guard to avoid redundant mutations)
            if let tabID, readerModeManager.isReaderActive(for: tabID) {
                readerModeManager.deactivateReader(for: tabID)
            }
            checkReaderAvailability()
        }
        .onChange(of: isLoading) { wasLoading, nowLoading in
            // Check reader availability when page finishes loading
            if wasLoading, !nowLoading {
                checkReaderAvailability()
            }
        }
        .onAppear {
            updateCachedWebPage()
            checkReaderAvailability()
        }
        .task(id: windowState.focusedPageID) {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            updateCachedWebPage()
            checkReaderAvailability()
        }
        .onChange(of: addressBarContext?.tabPage?.id) { _, _ in
            updateCachedWebPage()
        }
    }

    /// Updates the cached WebPage based on current context.
    private func updateCachedWebPage() {
        cachedWebPage = addressBarContext?.webPage ?? windowState.focusedWebPage
    }

    // MARK: - Navigation Controls

    /// Navigation controls using specialized buttons with explicit state parameters.
    ///
    /// By passing `canGoBack`/`canGoForward` explicitly, SwiftUI can detect when
    /// navigation state changes and re-render the buttons. The webPage reference
    /// alone isn't sufficient since it stays the same during navigation.
    private var navigationControls: some View {
        HStack(spacing: 0) {
            AddressBarBackButton(webPage: webPage, canGoBack: canGoBack)
            AddressBarForwardButton(webPage: webPage, canGoForward: canGoForward)
        }
        .animation(.snappy(duration: 0.2), value: canGoForward)
    }

    // MARK: - URL Display

    /// The current security state from the WebPage.
    private var securityState: WebPage.SecurityState {
        webPage?.securityState ?? .insecure
    }

    /// Determines the URL text color based on connection security.
    ///
    /// In 2025, HTTP and mixed content are considered security risks. Color coding:
    /// - Red: Invalid certificate or mixed content (only when certificate is evaluated)
    /// - Yellow/Orange: Local network address (192.168.x.x, localhost, etc.)
    /// - Secondary: Secure HTTPS or not yet evaluated (default state)
    ///
    /// The default state before certificate evaluation is secondary (normal) to avoid
    /// a flash of red text during initial navigation. Once the certificate is evaluated,
    /// insecure connections will show the appropriate warning color.
    ///
    /// Mixed content (HTTP resources on HTTPS pages) is shown in red because
    /// major browsers now treat it as a security warning.
    ///
    /// References:
    /// - [Chromium: Marking HTTP as Non-Secure](https://www.chromium.org/Home/chromium-security/marking-http-as-non-secure/)
    /// - [MDN: Mixed Content](https://developer.mozilla.org/en-US/docs/Web/Security/Mixed_content)
    private var urlTextColor: Color {
        // If we don't have certificate info yet (still loading), use secondary
        guard let cert = webPage?.certificateInfo else {
            return .secondary
        }

        // For HTTP pages, only show red if we're sure it's not just loading
        switch securityState {
        case .secure:
            return .secondary
        case .mixedContent:
            // Mixed content is a security risk
            return .red
        case .insecure:
            // Only show red for actual certificate errors, not during loading
            if case .invalid = cert.trustState {
                return .red
            }
            // HTTP connections show as secondary (gray) - not alarming
            return .secondary
        case .localNetwork:
            // Local addresses get a pass (dev/home servers)
            return .orange
        }
    }

    /// URL display for measurement (no styling changes).
    private var urlDisplay: some View {
        let isEmpty = displayDomain.isEmpty

        return HStack(spacing: 0) {
            engineBadge
            Text(isEmpty ? "Search or go..." : displayDomain)
                .font(.system(size: Constants.Typography.bodyMediumSize))
                .foregroundStyle(isEmpty ? Color.secondary : urlTextColor)
                .lineLimit(1)
                .truncationMode(isEmpty ? .tail : .head)
        }
    }

    /// The engine rendering the page, when it isn't system WebKit.
    @ViewBuilder
    private var engineBadge: some View {
        if let engineID = webPage?.activeEngineID, engineID != .systemWebKit,
           let icon = engineRegistry.icon(for: engineID) {
            let descriptor = engineRegistry.descriptor(for: engineID)
            AddressBarEngineBadge(
                icon: icon,
                engineName: descriptor.map { "\($0.displayName) (\($0.engineVersion))" } ?? engineID.rawValue,
            )
        }
    }

    /// URL display with blur effect when hover buttons overlay in compact mode.
    private var urlDisplayView: some View {
        let isEmpty = displayDomain.isEmpty
        // In compact mode, blur the URL when hovering to make room for overlay buttons
        let shouldBlur = isCompactMode && pageMenuButtonVisible
        let foregroundColor = if isEmpty {
            Color.secondary.opacity(0.75)
        } else if shouldBlur {
            Color.secondary.opacity(0.5)
        } else {
            urlTextColor
        }

        return HStack(spacing: 0) {
            engineBadge
            Text(isEmpty ? "Search or go..." : displayDomain)
                .font(.system(size: Constants.Typography.bodyMediumSize))
                .foregroundStyle(foregroundColor)
                .lineLimit(1)
                .truncationMode(isEmpty ? .tail : .head)
        }
        .blur(radius: shouldBlur ? 2 : 0)
        .animation(.easeInOut(duration: 0.15), value: shouldBlur)
    }

    // MARK: - Loading Indicator

    private var loadingIndicator: some View {
        LoadingIndicatorBar(isLoading: isLoading, progress: loadingProgress, horizontalInset: 8)
    }

    // MARK: - Trailing Controls

    private var hasActivePage: Bool {
        url != nil
    }

    /// Hover buttons that appear on hover - may be inline or overlay depending on available space.
    @ViewBuilder
    private var hoverButtons: some View {
        if hasActivePage {
            HStack(spacing: 0) {
                // Translation button - shows when foreign language detected
                AddressBarTranslationButton(webPage: webPage)

                if isReaderAvailable {
                    AddressBarReaderButton(
                        isActive: isReaderActive,
                        action: toggleReaderMode,
                    )
                }

                AddressBarPageMenuButton(showsMenu: $showsPageMenu)
                    .if(showsPageMenu) { view in
                        view.popover(isPresented: $showsPageMenu, arrowEdge: .bottom) {
                            PageMenuContent(
                                actions: pageMenuActions,
                                isReaderAvailable: isReaderAvailable,
                                dismiss: { showsPageMenu = false },
                                onFindOnPage: {
                                    if let context = addressBarContext {
                                        context.onShowFindNavigator()
                                    } else {
                                        windowState.showFindNavigator()
                                    }
                                },
                                onReaderMode: toggleReaderMode,
                                onWebpageSettings: { showsWebpageSettings = true },
                                onShowCookies: { showsSiteCookies = true },
                            )
                        }
                    }
                    .if(showsWebpageSettings) { view in
                        view.popover(isPresented: $showsWebpageSettings, arrowEdge: .bottom) {
                            WebpageSettingsPopover(domain: displayDomain, origin: url.flatMap(WebOrigin.init(url:)))
                        }
                    }
                    .sheet(isPresented: $showsSiteCookies) {
                        if let dataStore = webPage?.websiteDataStore {
                            SiteCookiesView(domain: displayDomain, dataStore: dataStore)
                        }
                    }

                // Copy link button is always rightmost for easy access
                AddressBarCopyLinkButton(copyURL: pageMenuActions.copyCleanURL, copyMarkdown: pageMenuActions.copyAsMarkdown)
            }
        }
    }

    /// Hover buttons with opacity animation based on hover state.
    private var hoverButtonsView: some View {
        hoverButtons
            .opacity(pageMenuButtonVisible ? 1 : 0)
            .animation(.easeInOut(duration: 0.15), value: pageMenuButtonVisible)
    }

    /// Trailing controls: autofill icons and reload button combined for layout.
    ///
    /// These are grouped together because AddressBarLayout expects exactly 4 subviews.
    @ViewBuilder
    private var trailingControlsView: some View {
        if hasActivePage {
            HStack(spacing: 0) {
                // Save password button - shows when there's a pending save request (builtIn mode only)
                if autoFillState.hasPendingSaveRequest, settings.autoFillMode == .builtIn {
                    AddressBarSavePasswordButton()
                }

                // Reload/stop button
                AddressBarReloadButton(
                    isLoading: isLoading,
                    onReload: {
                        if isLoading {
                            webPage?.stopLoading()
                        } else {
                            webPage?.reload()
                        }
                    },
                    onReloadFromOrigin: {
                        webPage?.reload(fromOrigin: true)
                    },
                    onReloadWithoutContentBlockers: {
                        webPage?.reloadWithoutContentBlockers()
                    },
                    otherEngines: engineRegistry.descriptors.filter { $0.id != (webPage?.activeEngineID ?? .systemWebKit) },
                    onReloadInEngine: { engine in
                        webPage?.reload(in: engine, registry: engineRegistry)
                    },
                )
            }
        }
    }

    // MARK: - Actions

    /// Toggles Reader Mode for the current page.
    private func toggleReaderMode() {
        Task(name: "Toggle Reader from the address bar") {
            await toggleReader()
        }
    }

    /// Toggles Reader Mode and, when the page is too long for Reader, hides the button.
    private func toggleReader() async {
        guard await pageMenuActions.toggleReader() == .tooLong else { return }
        isReaderAvailable = false
    }

    /// Checks if Reader Mode is available for the current page.
    ///
    /// Also auto-activates reader mode if the site has `useReaderWhenAvailable` enabled.
    /// Guards against redundant state mutations to prevent observation cascades.
    private func checkReaderAvailability() {
        guard let webPage else {
            if isReaderAvailable {
                isReaderAvailable = false
            }
            return
        }

        // First check cached availability (guard against redundant mutation)
        let cached = readerModeManager.cachedAvailability(for: webPage.url)
        if isReaderAvailable != cached {
            isReaderAvailable = cached
        }

        // Then perform async check for fresh result
        Task {
            let available = await readerModeManager.checkAvailability(for: webPage)
            if isReaderAvailable != available {
                isReaderAvailable = available
            }

            // Auto-activate reader mode if site setting is enabled
            if available,
               !isReaderActive,
               let url = webPage.url,
               let settings = siteSettingsManager.settings(for: url),
               settings.useReaderWhenAvailable {
                await toggleReader()
            }
        }
    }

    // MARK: - Frame Reader

    private var frameReader: some View {
        GeometryReader { geo in
            Color.clear
                .onAppear {
                    windowState.addressBarFrame = geo.frame(in: .global)
                }
                .onChange(of: geo.frame(in: .global)) { _, newFrame in
                    windowState.addressBarFrame = newFrame
                }
        }
    }
}
