import Security
import SwiftUI
import WebKit

struct AddressBar: View {
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
        addressBarContext?.isLensVisible ?? windowState.showsAddressLens
    }

    /// Extensions to display in the page menu.
    private var pageMenuExtensions: [PageMenuExtension] {
        extensionManager.installedExtensions
            .filter(\.isEnabled)
            .map { ext in
                let icon: NSImage? = if let iconData = ext.iconData {
                    NSImage(data: iconData)
                } else {
                    nil
                }
                return PageMenuExtension(
                    id: ext.uniqueIdentifier,
                    name: ext.displayName,
                    icon: icon,
                    isEnabled: true,
                )
            }
    }

    var body: some View {
        AddressBarLayout {
            navigationControls
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
                    if abs(navWidth - new) > 1 { navWidth = new }
                }
            urlDisplayView
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
                    if abs(urlWidth - new) > 1 { urlWidth = new }
                }
            hoverButtonsView
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
                    if abs(hoverButtonsWidth - new) > 1 { hoverButtonsWidth = new }
                }
            trailingControlsView
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
                    if abs(reloadWidth - new) > 1 { reloadWidth = new }
                }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { new in
            if abs(availableWidth - new) > 1 { availableWidth = new }
        }
        .padding(.horizontal, 6)
        .frame(height: Constants.AddressBar.height)
        .overlay(alignment: .bottom) {
            loadingIndicator
        }
        .adaptiveBackground(addressBarIsFloating ? .clear : .subtle, in: Capsule())
        .adaptiveBackgroundBlur()
        .contentShape(Capsule())
        .onHover { isHovered = $0 }
        .onTapGesture {
            if let context = addressBarContext {
                context.onOpenLens()
            } else if url != nil {
                // Open address lens when there's an active page with a URL
                windowState.openAddressLens()
            } else {
                // Open command lens when no tab is selected
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

        return Text(isEmpty ? "Ask, search, or go..." : displayDomain)
            .font(.system(size: Constants.Typography.bodyMediumSize))
            .foregroundStyle(isEmpty ? Color.secondary : urlTextColor)
            .lineLimit(1)
            .truncationMode(isEmpty ? .tail : .head)
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

        return Text(isEmpty ? "Ask, search, or go..." : displayDomain)
            .font(.system(size: Constants.Typography.bodyMediumSize))
            .foregroundStyle(foregroundColor)
            .lineLimit(1)
            .truncationMode(isEmpty ? .tail : .head)
            .blur(radius: shouldBlur ? 2 : 0)
            .animation(.easeInOut(duration: 0.15), value: shouldBlur)
    }

    // MARK: - Loading Indicator

    private var loadingIndicator: some View {
        LoadingIndicatorBar(isLoading: isLoading, progress: loadingProgress, horizontalInset: 8)
    }

    // MARK: - Trailing Controls

    private var certificateInfo: CertificateInfo? {
        webPage?.certificateInfo
    }

    private var serverTrust: SecTrust? {
        webPage?.serverTrust
    }

    private var currentZoom: Int {
        webPage?.currentZoom ?? 100
    }

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
                                certificateInfo: certificateInfo,
                                serverTrust: serverTrust,
                                currentZoom: currentZoom,
                                extensions: pageMenuExtensions,
                                isReaderAvailable: isReaderAvailable,
                                isReaderActive: isReaderActive,
                                isRecording: recordingCoordinator.isRecording,
                                recordingStartTime: recordingCoordinator.recordingStartTime,
                                isPageCalmed: url.map { siteSettingsManager.isCalmPage(for: $0) } ?? false,
                                onZoomChanged: { newZoom in
                                    webPage?.setZoom(newZoom)
                                },
                                onCopyURL: {
                                    showsPageMenu = false
                                    copyCleanURL()
                                },
                                onShare: {
                                    showsPageMenu = false
                                    shareCurrentPage()
                                },
                                onScreenshotFullPage: {
                                    showsPageMenu = false
                                    takeScreenshot(mode: .fullPage)
                                },
                                onScreenshotVisibleArea: {
                                    showsPageMenu = false
                                    takeScreenshot(mode: .visibleArea)
                                },
                                onScreenshotSelection: {
                                    showsPageMenu = false
                                    takeScreenshot(mode: .selection)
                                },
                                onScreenshotWindow: {
                                    showsPageMenu = false
                                    takeScreenshot(mode: .window)
                                },
                                onStartRecording: {
                                    showsPageMenu = false
                                    startRecording()
                                },
                                onStopRecording: {
                                    showsPageMenu = false
                                    stopRecording()
                                },
                                onFindOnPage: {
                                    showsPageMenu = false
                                    if let context = addressBarContext {
                                        context.onShowFindNavigator()
                                    } else {
                                        windowState.showFindNavigator()
                                    }
                                },
                                onReaderMode: {
                                    showsPageMenu = false
                                    toggleReaderMode()
                                },
                                onToggleCalm: {
                                    showsPageMenu = false
                                    toggleCalmPage()
                                },
                                onWebpageSettings: {
                                    showsPageMenu = false
                                    showsWebpageSettings = true
                                },
                                onShowCookies: {
                                    showsPageMenu = false
                                    showsSiteCookies = true
                                },
                                onExtensionAction: { extensionID in
                                    showsPageMenu = false
                                    handleExtensionAction(extensionID)
                                },
                            )
                        }
                    }
                    .if(showsWebpageSettings) { view in
                        view.popover(isPresented: $showsWebpageSettings, arrowEdge: .bottom) {
                            WebpageSettingsPopover(domain: displayDomain)
                        }
                    }
                    .sheet(isPresented: $showsSiteCookies) {
                        if let dataStore = webPage?.websiteDataStore {
                            SiteCookiesView(domain: displayDomain, dataStore: dataStore)
                        }
                    }

                // Copy link button is always rightmost for easy access
                AddressBarCopyLinkButton(copyURL: copyCleanURL, copyMarkdown: copyAsMarkdown)
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
                )
            }
        }
    }

    // MARK: - Actions

    /// Copies the current URL to the clipboard with tracking parameters removed.
    private func copyCleanURL() {
        guard let url else { return }
        let cleanURL = url.removingTrackingParameters()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cleanURL.absoluteString, forType: .string)
    }

    /// Copies the current URL as a Markdown link: `[Title](URL)`
    private func copyAsMarkdown() {
        guard let url else { return }
        let cleanURL = url.removingTrackingParameters()
        let title = webPage?.title ?? cleanURL.host ?? "Link"
        let markdown = "[\(title)](\(cleanURL.absoluteString))"
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(markdown, forType: .string)
    }

    /// Shares the current page URL using the system share sheet.
    private func shareCurrentPage() {
        guard let url else { return }
        let cleanURL = url.removingTrackingParameters()
        let title = webPage?.title
        sharingCoordinator.shareURL(cleanURL, title: title)
    }

    /// Takes a screenshot of the current page or window.
    private func takeScreenshot(mode: ScreenshotMode) {
        let window = windowState.window

        // Window mode doesn't need a webPage — it captures the entire window.
        if mode == .window {
            let customPath = webPage?.tabPage.tab?.space?.customDownloadPath
            let saveDirectory = downloadManager.downloadDirectory(for: customPath)

            Task {
                // Wait for popovers/menus to finish dismissing before capturing the window.
                try? await Task.sleep(for: .milliseconds(500))

                let result = await screenshotCoordinator.captureWindow(
                    window: window,
                    saveDirectory: saveDirectory,
                )
                if case let .failed(error) = result {
                    Logger.error("Screenshot failed: \(error)", category: Logger.navigation)
                }
            }
            return
        }

        guard let webPage else { return }

        // Resolve save directory from space settings (same as downloads)
        let customPath = webPage.tabPage.tab?.space?.customDownloadPath
        let saveDirectory = downloadManager.downloadDirectory(for: customPath)

        Task {
            let result: ScreenshotResult = switch mode {
            case .fullPage:
                await screenshotCoordinator.captureFullPage(webPage: webPage, in: window, saveDirectory: saveDirectory)
            case .visibleArea:
                await screenshotCoordinator.captureVisibleArea(webPage: webPage, in: window, saveDirectory: saveDirectory)
            case .selection:
                await screenshotCoordinator.captureSelectedElement(webPage: webPage, in: window, saveDirectory: saveDirectory)
            case .window:
                preconditionFailure("Handled above")
            }

            if case let .failed(error) = result {
                Logger.error("Screenshot failed: \(error)", category: Logger.navigation)
            }
        }
    }

    /// Starts recording the current tab.
    private func startRecording() {
        guard let webPage else { return }
        let window = windowState.window

        // Resolve save directory from space settings (same as downloads)
        let customPath = webPage.tabPage.tab?.space?.customDownloadPath
        let saveDirectory = downloadManager.downloadDirectory(for: customPath)

        recordingCoordinator.startRecording(webPage: webPage, in: window, saveDirectory: saveDirectory)
    }

    /// Stops the current recording.
    private func stopRecording() {
        Task {
            _ = await recordingCoordinator.stopRecording()
        }
    }

    /// Handles an extension action from the page menu.
    ///
    /// Triggers the extension's page action, which may show a popup.
    private func handleExtensionAction(_ extensionID: String) {
        Task {
            await extensionManager.triggerPageAction(for: extensionID, in: webPage)
        }
    }

    /// Toggles Reader Mode for the current page.
    private func toggleReaderMode() {
        guard let webPage else { return }
        Task {
            await readerModeManager.toggleReader(for: webPage)
        }
    }

    /// Toggles "Calm This Page" for the current domain and applies it to
    /// every live page of that domain.
    private func toggleCalmPage() {
        guard let url, let host = url.host else { return }
        let calmed = siteSettingsManager.toggleCalmPage(for: url)
        pagePool.applyCalm(calmed, toHost: host)
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
                await readerModeManager.toggleReader(for: webPage)
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
