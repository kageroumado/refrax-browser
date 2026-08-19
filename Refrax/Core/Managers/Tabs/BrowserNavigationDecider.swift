import SwiftUI
import WebKit

/// Coordinates navigation policy decisions for a browser tab page.
///
/// `BrowserNavigationDecider` implements WebKit's `NavigationDeciding` protocol,
/// acting as the bridge between WebKit navigation events and the browser's
/// policy system. It delegates to a chain of specialized handlers for modular,
/// testable navigation logic.
///
/// ## Architecture
///
/// Rather than implementing all navigation logic in one place, this class
/// coordinates a pipeline of ``NavigationActionHandler`` and
/// ``NavigationResponseHandler`` instances:
///
/// ```
/// WebKit Navigation Event
///        ↓
/// ┌──────────────────────────────┐
/// │  BrowserNavigationDecider    │
/// │  ┌────────────────────────┐  │
/// │  │ Magnet Link Check      │──┼──→ aria2 download (if BT enabled)
/// │  ├────────────────────────┤  │
/// │  │ SubframeHandler        │──┼──→ .allow (subframes)
/// │  ├────────────────────────┤  │
/// │  │ ExternalSchemeHandler  │──┼──→ .cancel (mailto:, tel:, magnet: if BT off)
/// │  ├────────────────────────┤  │
/// │  │ DataURLScriptHandler   │──┼──→ .cancel (scripts in data:)
/// │  ├────────────────────────┤  │
/// │  │ BlobURLHandler         │──┼──→ .cancel (script-initiated)
/// │  ├────────────────────────┤  │
/// │  │ FileSchemeHandler      │──┼──→ .cancel (from web content)
/// │  ├────────────────────────┤  │
/// │  │ DownloadActionHandler  │──┼──→ .download (download attr)
/// │  ├────────────────────────┤  │
/// │  │ ModifierClickHandler   │──┼──→ .openInNewTab (⌘/middle)
/// │  ├────────────────────────┤  │
/// │  │ PopupHandler           │──┼──→ .openInNewTab / .cancel
/// │  ├────────────────────────┤  │
/// │  │ DeepLinkHandler        │──┼──→ .allow (refrax://)
/// │  ├────────────────────────┤  │
/// │  │ LinkProtectionHandler  │──┼──→ .redirect (cleaned URL)
/// │  ├────────────────────────┤  │
/// │  │ URLShortenerHandler    │──┼──→ .redirect (expanded URL)
/// │  ├────────────────────────┤  │
/// │  │ CustomRedirectHandler  │──┼──→ .redirect (user rules)
/// │  ├────────────────────────┤  │
/// │  │ AppRedirectHandler     │──┼──→ .cancel (open in app)
/// │  └────────────────────────┘  │
/// │            ↓                 │
/// │        .allow                │
/// └──────────────────────────────┘
/// ```
///
/// ## Handler Chain Order
///
/// The order of handlers matters. Early handlers can short-circuit evaluation:
///
/// 1. **SubframeNavigationHandler** — Allow iframes early (embedded content, silent token refresh)
/// 2. **ExternalSchemeHandler** — Delegate non-web URLs to system
/// 3. **DataURLScriptHandler** — Block data: URLs with script content (XSS prevention)
/// 4. **BlobURLHandler** — Restrict blob: URLs to user-initiated only
/// 5. **FileSchemeHandler** — Restrict file: URLs to user-initiated only
/// 6. **DownloadActionHandler** — Handle `<a download>` links
/// 7. **ModifierClickHandler** — Middle-click and Cmd+click → new tab
/// 8. **PopupHandler** — Manage new window/tab requests (`target="_blank"`, `window.open()`)
/// 9. **DeepLinkHandler** — Route internal URLs
/// 10. **LinkProtectionHandler** — Clean tracking/AMP URLs
/// 11. **URLShortenerHandler** — Expand shortened URLs (bit.ly, t.co, etc.)
/// 12. **CustomRedirectHandler** — Apply user-defined URL transformations
/// 13. **AppRedirectHandler** — Open URLs in external applications
///
/// ## Response Handling
///
/// Similar chain for responses (MIME types, downloads):
///
/// 1. **DownloadResponseHandler** — Detect downloads
///
/// ## HTTPS Upgrade
///
/// WebKit handles HTTPS upgrades automatically via `NavigationPreferences`.
/// We configure `preferredHTTPSNavigationPolicy` to `.automaticFallbackToHTTP`
/// for seamless upgrades with fallback for sites that don't support HTTPS.
///
/// ## Thread Safety
///
/// All handler evaluation is `async` and runs on WebKit's internal queue.
/// Handlers must be `Sendable` and avoid main actor access unless explicitly
/// dispatched.
///
/// ## Usage
///
/// Created by ``WebPagePool`` when instantiating a new ``WebPage``:
///
/// ```swift
/// let decider = BrowserNavigationDecider(
///     tabManager: tabManager,
///     tabPage: tabPage,
///     tab: tab,
///     settings: settings
/// )
///
/// let webPage = WebPage(
///     tabPage: tabPage,
///     navigationDecider: decider,
///     ...
/// )
/// ```
final class BrowserNavigationDecider: WebPage.NavigationDeciding {
    // MARK: - Dependencies

    /// Reference to the tab manager for creating new tabs.
    ///
    /// Unowned because TabManager is instantiated in the app delegate and lives
    /// for the lifetime of the app. The session pool and this decider cannot
    /// outlive the TabManager.
    unowned let tabManager: TabManager

    /// Reference to the download manager for handling downloads.
    ///
    /// Unowned because DownloadManager is instantiated in the app delegate.
    unowned let downloadManager: DownloadManager

    /// The tab page this decider is associated with.
    ///
    /// Used to fetch the correct runtime session and origin metadata when
    /// multiple pages are displayed within the same tab.
    let tabPage: TabPage

    /// The tab this decider is associated with, if any.
    ///
    /// Used for context when creating new tabs (inheriting space, group).
    /// Pages may exist without a tab during background or transitional states.
    let tab: Tab?

    /// Browser settings for privacy protection handlers.
    let settings: BrowserSettings

    /// Coordinator for per-domain settings.
    unowned let siteSettingsCoordinator: SiteSettingsCoordinator

    /// Dialog presenter for routing user-facing prompts (mTLS picker) through
    /// the centralized `DialogState` system.
    unowned let dialogPresenter: BrowserDialogPresenter

    // MARK: - Handler Chains

    /// Chain of handlers for navigation action decisions.
    private let actionChain: NavigationActionChain

    /// Chain of handlers for navigation response decisions.
    private let responseChain: NavigationResponseChain

    // MARK: - SSL Bypass State

    /// URL for which SSL bypass has been approved by the user.
    ///
    /// This is validated against the challenge URL to ensure bypass
    /// only applies to the specific domain the user approved.
    /// Reset after use to prevent unintended bypasses on redirects.
    private var approvedSSLBypassURL: URL?

    // MARK: - Initialization

    /// Creates a navigation decider for a specific tab page.
    ///
    /// Initializes the handler chains with the standard set of handlers
    /// in the correct evaluation order.
    ///
    /// - Parameters:
    ///   - tabManager: The tab manager for creating new tabs.
    ///   - downloadManager: The download manager for handling downloads.
    ///   - tabPage: The tab page this decider is associated with.
    ///   - tab: The tab this decider is associated with.
    ///   - settings: Browser settings for privacy protection handlers.
    ///   - siteSettingsCoordinator: Coordinator for per-domain preferences.
    ///   - dialogPresenter: Routes user-facing prompts (e.g. mTLS picker)
    ///     through the centralized dialog state.
    init(
        tabManager: TabManager,
        downloadManager: DownloadManager,
        tabPage: TabPage,
        tab: Tab?,
        settings: BrowserSettings,
        siteSettingsCoordinator: SiteSettingsCoordinator,
        dialogPresenter: BrowserDialogPresenter,
    ) {
        self.tabManager = tabManager
        self.downloadManager = downloadManager
        self.tabPage = tabPage
        self.tab = tab
        self.settings = settings
        self.siteSettingsCoordinator = siteSettingsCoordinator
        self.dialogPresenter = dialogPresenter

        // Build action handler chain (order matters!)
        self.actionChain = NavigationActionChain(handlers: [
            // 1. Allow subframe navigations early (OAuth, embeds, etc.)
            SubframeNavigationHandler(),

            // 2. Handle external URL schemes (mailto:, tel:, etc.)
            ExternalSchemeHandler(settings: settings),

            // 3. Security: Block dangerous data: URLs with scripts
            DataURLScriptHandler(),

            // 4. Security: Restrict blob: URLs to user-initiated only
            BlobURLHandler(),

            // 5. Security: Restrict file: URLs to user-initiated only
            FileSchemeHandler(),

            // 6. Handle <a download> attribute links
            DownloadActionHandler(),

            // 7. Handle middle-click and Cmd+click → new tab
            ModifierClickHandler(),

            // 8. Arc-style containment for pinned tabs and live favorites
            // Runs before PopupHandler so target="_blank" links on contained tabs
            // show previews instead of opening new tabs directly.
            PinnedTabContainmentHandler(tab: tab),

            // 9. Handle popup/new window requests (target="_blank", window.open)
            PopupHandler(siteSettingsCoordinator: siteSettingsCoordinator),

            // 10. Route internal deep links (refrax://)
            DeepLinkHandler(),

            // 11. Focus Mode restrictions (block domains during Focus)
            FocusModeRestrictionHandler(),

            // 12. Clean URLs (remove trackers, convert AMP)
            LinkProtectionHandler(privacySettings: settings.privacyProtection),

            // 13. Expand shortened URLs (bit.ly, t.co, etc.)
            URLShortenerHandler(settings: settings),

            // 14. Apply user-defined URL transformations
            CustomRedirectHandler(settings: settings),

            // 15. Open URLs in external applications
            AppRedirectHandler(settings: settings),
        ])

        // Build response handler chain
        //
        // HTTP error status codes (4xx/5xx) are intentionally NOT intercepted here.
        // Like Chrome and Safari, we let WebKit render whatever HTML the server sends
        // for error responses. Custom error pages should only appear for network-level
        // failures (DNS, connection refused, timeout) which WebKit handles via
        // didFailProvisionalNavigation.
        self.responseChain = NavigationResponseChain(handlers: [
            // 1. Detect content that should be downloaded
            DownloadResponseHandler(),
        ])
    }

    // MARK: - WebPage.NavigationDeciding

    /// Decides the policy for a navigation action.
    ///
    /// Called by WebKit before a navigation begins. Evaluates the action
    /// through the handler chain and returns the appropriate policy.
    ///
    /// - Parameters:
    ///   - navigationAction: The WebKit navigation action to evaluate.
    ///   - preferences: Navigation preferences that can be modified (e.g., user agent).
    /// - Returns: The policy decision for this navigation.
    func decidePolicy(
        for navigationAction: WebPage.NavigationAction,
        preferences: inout WebPage.NavigationPreferences,
    ) async -> WKNavigationActionPolicy {
        let action = navigationAction

        // Configure HTTPS upgrade policy for main frame navigations
        // WebKit will automatically upgrade HTTP to HTTPS and fall back if needed
        if action.isMainFrame {
            preferences.preferredHTTPSNavigationPolicy = .automaticFallbackToHTTP

            // Apply JavaScript preference with per-site overrides
            if let url = action.url {
                let allowJavaScript = siteSettingsCoordinator.allowsJavaScript(for: url)
                preferences.allowsContentJavaScript = allowJavaScript
            }
        }

        // Intercept magnet: links for BitTorrent handling
        if let url = action.url, url.scheme?.lowercased() == "magnet" {
            if downloadManager.enableBitTorrent {
                await startMagnetDownload(url: url)
                return .cancel
            }
            // Fall through → ExternalSchemeHandler → system handler
        }

        // Evaluate through handler chain
        let policy = await actionChain.evaluate(action)

        // Convert our policy to WebKit policy
        return await handleActionPolicy(policy, for: action, preferences: &preferences)
    }

    /// Decides the policy for a navigation response.
    ///
    /// Called by WebKit after a response is received but before content
    /// is rendered. Used for download detection and error handling.
    ///
    /// - Parameter navigationResponse: The WebKit navigation response to evaluate.
    /// - Returns: The policy decision for this response.
    func decidePolicy(
        for navigationResponse: WebPage.NavigationResponse,
    ) async -> WKNavigationResponsePolicy {
        let response = NavigationResponse(webKitResponse: navigationResponse)

        // Evaluate through handler chain
        let policy = await responseChain.evaluate(response)

        // Convert our policy to WebKit policy
        return await handleResponsePolicy(policy, for: response)
    }

    /// Handles authentication challenges from servers.
    ///
    /// Supports:
    /// - **HTTP Basic/Digest Auth**: Shows a username/password dialog
    /// - **Server Trust**: Uses WebKit's default handling for valid certificates;
    ///   redirects to SSL error page for invalid certificates
    /// - **Client Certificates (mTLS)**: Looks up keychain identities matching
    ///   the server's accepted issuers and presents a picker
    ///
    /// ## Security Design
    ///
    /// For server trust challenges, we follow Apple's recommendation to avoid
    /// custom trust evaluation when possible. Valid certificates are handled
    /// by WebKit's default behavior. Invalid certificates redirect to a native
    /// error page where users can choose to proceed (if settings allow).
    ///
    /// References:
    /// - [RFC 7235 — HTTP Authentication](https://datatracker.ietf.org/doc/html/rfc7235)
    /// - [Preventing Insecure Network Connections](https://developer.apple.com/documentation/security/preventing_insecure_network_connections)
    /// - [Tech Note TN2232: HTTPS Server Trust Evaluation](https://developer.apple.com/library/archive/technotes/tn2232/_index.html)
    ///
    /// - Parameter challenge: The authentication challenge from the server.
    /// - Returns: The disposition and optional credential to use.
    func decideAuthenticationChallengeDisposition(
        for challenge: URLAuthenticationChallenge,
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let protectionSpace = challenge.protectionSpace

        switch protectionSpace.authenticationMethod {
        case NSURLAuthenticationMethodHTTPBasic,
             NSURLAuthenticationMethodHTTPDigest:
            return await showAuthenticationDialog(challenge: challenge)

        case NSURLAuthenticationMethodServerTrust:
            return await handleServerTrustChallenge(challenge)

        case NSURLAuthenticationMethodClientCertificate:
            return await showClientCertificatePicker(challenge: challenge)

        default:
            return (.performDefaultHandling, nil)
        }
    }

    /// Handles server trust authentication challenges.
    ///
    /// This method implements a security-first approach:
    /// 1. Valid certificates → Use WebKit's default handling (don't override)
    /// 2. Previously approved bypass → Accept with credential (validates URL match)
    /// 3. Invalid certificates → Redirect to SSL error page
    ///
    /// - Parameter challenge: The server trust challenge.
    /// - Returns: The disposition and optional credential.
    private func handleServerTrustChallenge(
        _ challenge: URLAuthenticationChallenge,
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let protectionSpace = challenge.protectionSpace

        guard let serverTrust = protectionSpace.serverTrust else {
            return (.performDefaultHandling, nil)
        }

        // Evaluate the certificate to determine trust state off the main thread.
        // NOTE: We don't call SecTrustSetPolicies - WebKit has already configured
        // the appropriate SSL policy. We only evaluate to check the result.
        // SecTrust is thread-safe but not marked Sendable.
        let host = protectionSpace.host
        let sendableTrust = UncheckedSendable(serverTrust)
        let certInfo = await Task.detached {
            CertificateEvaluator.evaluate(sendableTrust.value, for: host)
        }.value

        switch certInfo.trustState {
        case .valid:
            // Certificate is trusted - use WebKit's default handling
            // Per Apple's guidance, avoid custom trust handling for valid certs.
            // WebKit will accept the certificate using system trust settings.
            return (.performDefaultHandling, nil)

        case let .invalid(error):
            // Check if user has approved bypass for this specific URL
            if checkBypassApproval(for: protectionSpace, trust: serverTrust) {
                let credential = URLCredential(trust: serverTrust)
                return (.useCredential, credential)
            }

            // Certificate has issues - redirect to SSL error page
            Logger.warning(
                "Certificate issue for \(protectionSpace.host): \(error.localizedDescription)",
                category: Logger.navigation,
            )

            // Navigate to SSL error page instead of showing alert
            var components = URLComponents()
            components.scheme = "https"
            components.host = protectionSpace.host
            if protectionSpace.port > 0, protectionSpace.port != 443 {
                components.port = protectionSpace.port
            }
            let failedURL = components.url ?? .blank

            await showSSLErrorPage(error: error, failedURL: failedURL)

            return (.cancelAuthenticationChallenge, nil)

        case .unknown:
            return (.performDefaultHandling, nil)
        }
    }

    /// Checks if SSL bypass has been approved for this protection space.
    ///
    /// Validates that:
    /// 1. There's an approved bypass URL
    /// 2. The host matches exactly (prevents bypass on redirects to other domains)
    /// 3. Clears the approval after use (one-time bypass)
    private func checkBypassApproval(
        for protectionSpace: URLProtectionSpace,
        trust _: SecTrust,
    ) -> Bool {
        guard let approvedURL = approvedSSLBypassURL else {
            return false
        }

        // Validate host matches exactly
        let challengeHost = protectionSpace.host.lowercased()
        let approvedHost = approvedURL.host?.lowercased()

        guard challengeHost == approvedHost else {
            Logger.warning(
                "SSL bypass rejected: host mismatch (\(challengeHost) != \(approvedHost ?? "nil"))",
                category: Logger.navigation,
            )
            return false
        }

        // Clear the approval - it's single-use
        approvedSSLBypassURL = nil

        Logger.info(
            "SSL bypass approved for \(challengeHost)",
            category: Logger.navigation,
        )
        return true
    }

    /// Sets the approved SSL bypass URL.
    ///
    /// Called from the SSL error page when the user chooses to proceed.
    /// The URL is validated against the next server trust challenge.
    ///
    /// This method is async to ensure the bypass is registered before the caller
    /// proceeds with navigation, preventing race conditions.
    func approveSSLBypass(for url: URL) async {
        approvedSSLBypassURL = url
        Logger.info(
            "SSL bypass queued for \(url.host ?? "unknown")",
            category: Logger.navigation,
        )
    }

    // MARK: - Policy Conversion

    /// Converts our navigation action policy to WebKit's policy.
    private func handleActionPolicy(
        _ policy: NavigationActionPolicy,
        for _: WebPage.NavigationAction,
        preferences _: inout WebPage.NavigationPreferences,
    ) async -> WKNavigationActionPolicy {
        switch policy {
        case .allow:
            return .allow

        case .cancel:
            return .cancel

        case let .redirect(newURL):
            // Cancel current navigation and start a new one with the cleaned URL
            await redirectNavigation(to: newURL)
            return .cancel

        case let .openInNewTab(url, activate):
            openInNewTab(url: url, activate: activate)
            return .cancel

        case let .download(url):
            // blob: URLs can only be transferred by WebKit itself — return .download
            // so WebKit creates a WKDownload, which WKNavigationDelegateAdapter
            // adopts into DownloadManager.
            if DownloadManager.requiresWebKitTransfer(url) {
                return .download
            }
            await handleDownloadAction(for: url)
            return .cancel

        case let .showPreview(url):
            await showLinkPreview(for: url)
            return .cancel

        case .next:
            // All handlers passed; allow the navigation
            return .allow
        }
    }

    /// Converts our navigation response policy to WebKit's policy.
    private func handleResponsePolicy(
        _ policy: NavigationResponsePolicy,
        for response: NavigationResponse,
    ) async -> WKNavigationResponsePolicy {
        switch policy {
        case .allow:
            return .allow

        case .cancel:
            return .cancel

        case .download:
            // blob: URLs can only be transferred by WebKit itself — return .download
            // so WebKit creates a WKDownload, which WKNavigationDelegateAdapter
            // adopts into DownloadManager.
            if let url = response.url, DownloadManager.requiresWebKitTransfer(url) {
                return .download
            }

            // For re-requestable URLs, cancel the navigation and start a fresh
            // download through DownloadManager. This keeps progress tracking,
            // space-aware destinations, aria2 acceleration, and pause/resume.
            await handleDownload(for: response)
            return .cancel

        case let .showError(code, failedURL):
            // Load alternate HTML for the error with proper history handling.
            // This uses WebKit's _loadAlternateHTMLString to:
            // 1. Record the failed URL in the back-forward list
            // 2. Enable proper reload (retries the failed URL)
            // 3. Enable proper back/forward navigation
            // The SwiftUI view observes httpErrorCode and overlays ErrorPageView.
            let tabManager = tabManager
            let tabPageID = tabPage.id
            DispatchQueue.main.async {
                guard let session = tabManager.state.webPage(for: tabPageID) else { return }
                session.loadAlternateHTMLForError(code: code, failedURL: failedURL)
            }
            return .cancel

        case .next:
            return .allow
        }
    }

    // MARK: - Navigation Actions

    /// Redirects the current navigation to a new URL.
    ///
    /// Used when URL cleaning (tracker removal, AMP conversion) produces
    /// a different URL than originally requested.
    private func redirectNavigation(to url: URL) async {
        await MainActor.run {
            guard let session = tabManager.state.webPage(for: tabPage.id) else {
                Logger.warning("Cannot redirect: no active session", category: Logger.navigation)
                return
            }
            session.load(url)
        }
    }

    /// Opens a URL in a new tab.
    ///
    /// Used for popup handling and modifier-click handling (cmd+click, middle-click).
    /// The tab always loads immediately since this is a user-initiated action.
    /// New tabs are inserted below the active tab for contextual proximity.
    ///
    /// Before creating the tab, routing rules are evaluated. If a rule matches,
    /// its action is executed instead of the default behavior.
    private func openInNewTab(url: URL, activate: Bool) {
        // Check routing rules
        let ruleEngine = tabManager.ruleEngine
        let referrer = tabPage.url
        let currentSpaceID = tab?.space?.id

        let context = NavigationContext(
            url: url,
            referrer: referrer,
            currentSpaceID: currentSpaceID,
        )

        if let action = ruleEngine.matchingAction(for: context) {
            let executor = RoutingActionExecutor(
                tabManager: tabManager,
                windowManager: tabManager.windowManager,
                spaceManager: tabManager.spaceManager,
            )

            if executor.execute(action, url: url, context: context, makeActive: activate) {
                return
            }
            // If execution returns false, fall through to default behavior
        }

        // Default behavior
        // Pinned/live favorite tabs have stale position and group info — use prepend
        let isContained = tab?.isPinned == true || tab?.isLiveFavorite == true
        let targetSpace = tab?.space ?? tabManager.state.spaces.first
        tabManager.createTab(
            url: url,
            in: targetSpace,
            groupID: isContained ? nil : tab?.groupID,
            makeActive: activate,
            loadImmediately: true,
            insertionStrategy: isContained ? .prepend : .afterActive,
        )
    }

    /// Initiates a download for the given response.
    ///
    /// Extracts the suggested filename from the response headers and
    /// starts the download through the DownloadManager.
    ///
    /// If the tab has no navigation history (e.g., was opened via `target="_blank"`
    /// for a download link), the tab is closed after starting the download to avoid
    /// leaving an empty tab behind.
    private func handleDownload(for response: NavigationResponse) async {
        guard let url = response.url else {
            Logger.warning("Cannot download: no URL in response", category: Logger.navigation)
            return
        }

        // Route torrent files to aria2 if BitTorrent is enabled
        if downloadManager.enableBitTorrent, isTorrentResponse(url: url, mimeType: response.mimeType) {
            await startTorrentFileDownload(from: url)
            return
        }

        Logger.info("Download (response): \(url.absoluteString)", category: Logger.navigation)

        // Extract suggested filename from Content-Disposition or URL
        let suggestedFilename = response.suggestedFilename ?? url.lastPathComponent

        // Get originating page info for context
        let originatingURL = tabPage.url
        let originatingTitle = tabPage.title

        // Check if this tab should be closed after download starts.
        // A tab is considered "download-only" if:
        // 1. It has no back history (was just opened for this URL)
        // 2. The download URL matches the tab's current URL
        // This handles the case of clicking a target="_blank" download link.
        let shouldCloseTab = await MainActor.run {
            shouldCloseTabAfterDownload(downloadURL: url)
        }

        // Get space download settings
        let (customDownloadPath, spaceID, spaceName, colorTag): (String?, UUID?, String?, Int?) = await MainActor.run {
            guard let space = tabPage.tab?.space else {
                return (nil, nil, nil, nil)
            }
            return (space.customDownloadPath, space.id, space.name, space.downloadColorTag)
        }

        do {
            try await downloadManager.startDownload(
                from: url,
                suggestedFilename: suggestedFilename,
                originatingURL: originatingURL,
                originatingTitle: originatingTitle,
                dataStore: tabManager.state.webPage(for: tabPage.id)?.websiteDataStore,
                customDownloadPath: customDownloadPath,
                spaceID: spaceID,
                spaceName: spaceName,
                colorTag: colorTag,
            )

            if shouldCloseTab {
                await MainActor.run { closeTabAfterDownload() }
            }
        } catch {
            Logger.error("Failed to start download: \(error)", category: Logger.navigation)
            // Fallback to opening in system browser
            NSWorkspace.shared.open(url)
        }
    }

    /// Determines if the tab should be closed after a download starts.
    ///
    /// Returns `true` if the tab was created solely to handle this download
    /// (e.g., from a `target="_blank"` link to a downloadable file).
    private func shouldCloseTabAfterDownload(downloadURL: URL) -> Bool {
        guard let session = tabManager.state.webPage(for: tabPage.id) else {
            return false
        }

        // If the tab has back history, it has real content - don't close it
        if session.canGoBack {
            return false
        }

        // The tab has no history and the download URL matches the tab's URL.
        // This indicates the tab was opened specifically for this download.
        let tabURL = tabPage.url
        return tabURL.absoluteString == downloadURL.absoluteString
            || tabURL.absoluteString == "about:blank"
    }

    /// Closes the current tab after a download has started.
    ///
    /// Called when a tab was created solely to handle a download (e.g., from
    /// a `target="_blank"` link to a downloadable file).
    private func closeTabAfterDownload() {
        guard let tab else {
            Logger.warning("Skipping download-only tab close: no tab context", category: Logger.navigation)
            return
        }
        Logger.info("Closing download-only tab: \(tab.id)", category: Logger.navigation)
        tabManager.closeTab(tab)
    }

    /// Initiates a download for a navigation action with download attribute.
    ///
    /// Called when a link has the HTML5 `download` attribute set.
    ///
    /// - Parameter url: The URL to download.
    private func handleDownloadAction(for url: URL) async {
        // Route torrent files to aria2 if BitTorrent is enabled
        if downloadManager.enableBitTorrent, isTorrentResponse(url: url, mimeType: nil) {
            await startTorrentFileDownload(from: url)
            return
        }

        Logger.info("Download (action): \(url.absoluteString)", category: Logger.navigation)

        // Extract filename from URL (download attribute may provide better name via response)
        let suggestedFilename = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent

        // Get originating page info for context
        let originatingURL = tabPage.url
        let originatingTitle = tabPage.title

        // Get space download settings
        let (customDownloadPath, spaceID, spaceName, colorTag): (String?, UUID?, String?, Int?) = await MainActor.run {
            guard let space = tabPage.tab?.space else {
                return (nil, nil, nil, nil)
            }
            return (space.customDownloadPath, space.id, space.name, space.downloadColorTag)
        }

        do {
            try await downloadManager.startDownload(
                from: url,
                suggestedFilename: suggestedFilename,
                originatingURL: originatingURL,
                originatingTitle: originatingTitle,
                dataStore: tabManager.state.webPage(for: tabPage.id)?.websiteDataStore,
                customDownloadPath: customDownloadPath,
                spaceID: spaceID,
                spaceName: spaceName,
                colorTag: colorTag,
            )
        } catch {
            Logger.error("Failed to start download: \(error)", category: Logger.navigation)
            // Fallback to opening in system browser
            NSWorkspace.shared.open(url)
        }
    }

    /// Shows a link preview panel for navigation containment.
    ///
    /// When the user follows a cross-domain link from a pinned tab or live
    /// favorite, this method shows the URL in a preview panel instead of
    /// navigating the tab. The user can then choose to open in a new tab
    /// or dismiss.
    ///
    /// - Parameter url: The URL to preview.
    private func showLinkPreview(for url: URL) async {
        await MainActor.run {
            guard let session = tabManager.state.webPage(for: tabPage.id),
                  let linkPreviewManager = session.backingWebView.linkPreviewManager
            else {
                // Fallback: open in new tab if preview unavailable
                Logger.warning("Link preview unavailable, opening in new tab", category: Logger.navigation)
                openInNewTab(url: url, activate: true)
                return
            }
            linkPreviewManager.showPreview(for: url)
        }
    }

    /// Shows an SSL error page for certificate failures.
    ///
    /// Navigates to the internal SSL error deep link which renders a native
    /// security warning with certificate details and bypass option.
    private func showSSLErrorPage(error: CertificateInfo.TrustError, failedURL: URL) async {
        let errorType = SSLErrorType(from: error)
        let sslErrorDeepLink = DeepLink.sslError(error: errorType, failedURL: failedURL)

        await MainActor.run {
            guard let session = tabManager.state.webPage(for: tabPage.id) else {
                return
            }
            session.load(sslErrorDeepLink.url)
        }
    }

    // MARK: - BitTorrent Handling

    /// Starts a magnet link download via aria2.
    private func startMagnetDownload(url: URL) async {
        let (customDownloadPath, spaceID, spaceName) = await MainActor.run {
            guard let space = tabPage.tab?.space else {
                return (nil as String?, nil as UUID?, nil as String?)
            }
            return (space.customDownloadPath, space.id, space.name)
        }

        do {
            try await downloadManager.startMagnetDownload(
                magnetURL: url,
                customDownloadPath: customDownloadPath,
                spaceID: spaceID,
                spaceName: spaceName,
            )
        } catch {
            Logger.error(
                "Failed to start magnet download, falling back to system handler: \(error)",
                category: Logger.navigation,
            )
            _ = await MainActor.run { NSWorkspace.shared.open(url) }
        }
    }

    /// Detects torrent files by MIME type or file extension.
    private func isTorrentResponse(url: URL, mimeType: String?) -> Bool {
        if let mime = mimeType?.lowercased(), mime == "application/x-bittorrent" {
            return true
        }
        return url.pathExtension.lowercased() == "torrent"
    }

    /// Downloads a .torrent metadata file and starts a BitTorrent download via aria2.
    private func startTorrentFileDownload(from url: URL) async {
        Logger.info("Torrent file detected, routing to aria2: \(url.absoluteString)", category: Logger.navigation)

        let (customDownloadPath, spaceID, spaceName) = await MainActor.run {
            guard let space = tabPage.tab?.space else {
                return (nil as String?, nil as UUID?, nil as String?)
            }
            return (space.customDownloadPath, space.id, space.name)
        }

        do {
            // Download the .torrent metadata file to a temp location
            let torrentFileURL = try await downloadTorrentMetadata(from: url)

            try await downloadManager.startTorrentDownload(
                torrentFile: torrentFileURL,
                customDownloadPath: customDownloadPath,
                spaceID: spaceID,
                spaceName: spaceName,
            )

            // Clean up temp file (aria2 has already read and base64-encoded it)
            try? FileManager.default.removeItem(at: torrentFileURL)
        } catch {
            Logger.error(
                "Failed to start torrent download, falling back to regular download: \(error)",
                category: Logger.navigation,
            )
            await saveAsFallbackDownload(url: url)
        }
    }

    /// Downloads the .torrent metadata file to a temporary location.
    ///
    /// Uses cookies from the current WebKit session to support authenticated
    /// private tracker downloads.
    private func downloadTorrentMetadata(from url: URL) async throws -> URL {
        // Fetch cookies from WebKit data store for authenticated tracker support
        let cookies = await fetchWebKitCookies(for: url)

        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage?.setCookies(cookies, for: url, mainDocumentURL: nil)

        let session = URLSession(configuration: config)
        let (tempURL, response) = try await session.download(from: url)

        // Verify we got a valid response
        if let httpResponse = response as? HTTPURLResponse,
           !(200 ... 299).contains(httpResponse.statusCode) {
            throw URLError(.badServerResponse)
        }

        // Move to a named temp file (URLSession gives a random name)
        let torrentDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("refrax-torrents", isDirectory: true)
        try FileManager.default.createDirectory(at: torrentDir, withIntermediateDirectories: true)

        let filename = url.lastPathComponent.isEmpty ? "download.torrent" : url.lastPathComponent
        let destURL = torrentDir.appendingPathComponent(filename)
        if FileManager.default.fileExists(atPath: destURL.path) {
            try FileManager.default.removeItem(at: destURL)
        }
        try FileManager.default.moveItem(at: tempURL, to: destURL)

        return destURL
    }

    /// Fetches cookies from the current WebKit session for a URL.
    private func fetchWebKitCookies(for url: URL) async -> [HTTPCookie] {
        guard let dataStore = await MainActor.run(body: {
            tabManager.state.webPage(for: tabPage.id)?.websiteDataStore
        }) else {
            return []
        }

        return await withCheckedContinuation { continuation in
            dataStore.httpCookieStore.getAllCookies { cookies in
                let applicable = cookies.filter { cookie in
                    guard let host = url.host?.lowercased() else { return false }
                    let domain = cookie.domain.lowercased()
                    return domain.hasPrefix(".")
                        ? (host.hasSuffix(domain) || host == String(domain.dropFirst()))
                        : host == domain
                }
                continuation.resume(returning: applicable)
            }
        }
    }

    /// Falls back to saving the URL as a regular download.
    private func saveAsFallbackDownload(url: URL) async {
        let suggestedFilename = url.lastPathComponent
        let (customDownloadPath, spaceID, spaceName, colorTag): (String?, UUID?, String?, Int?) = await MainActor.run {
            guard let space = tabPage.tab?.space else { return (nil, nil, nil, nil) }
            return (space.customDownloadPath, space.id, space.name, space.downloadColorTag)
        }

        _ = try? await downloadManager.startDownload(
            from: url,
            suggestedFilename: suggestedFilename,
            originatingURL: tabPage.url,
            originatingTitle: tabPage.title,
            dataStore: tabManager.state.webPage(for: tabPage.id)?.websiteDataStore,
            customDownloadPath: customDownloadPath,
            spaceID: spaceID,
            spaceName: spaceName,
            colorTag: colorTag,
        )
    }

    // MARK: - Authentication UI

    /// Shows a dialog for HTTP Basic/Digest authentication.
    ///
    /// Presents a modal dialog asking for username and password.
    /// The dialog is displayed on the main thread.
    private func showAuthenticationDialog(
        challenge: URLAuthenticationChallenge,
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Authentication Required"
                alert.informativeText = challenge.protectionSpace.host
                alert.alertStyle = .informational

                // Create input fields
                let usernameField = NSTextField(frame: NSRect(x: 0, y: 24, width: 300, height: 24))
                usernameField.placeholderString = "Username"

                let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
                passwordField.placeholderString = "Password"

                let stackView = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 56))
                stackView.orientation = .vertical
                stackView.spacing = 8
                stackView.addArrangedSubview(usernameField)
                stackView.addArrangedSubview(passwordField)

                alert.accessoryView = stackView
                alert.addButton(withTitle: "Sign In")
                alert.addButton(withTitle: "Cancel")
                alert.window.initialFirstResponder = usernameField

                let response = alert.runModal()

                if response == .alertFirstButtonReturn {
                    let username = usernameField.stringValue
                    let password = passwordField.stringValue

                    if !username.isEmpty || !password.isEmpty {
                        let credential = URLCredential(
                            user: username,
                            password: password,
                            persistence: .forSession,
                        )
                        continuation.resume(returning: (.useCredential, credential))
                    } else {
                        continuation.resume(returning: (.cancelAuthenticationChallenge, nil))
                    }
                } else {
                    continuation.resume(returning: (.cancelAuthenticationChallenge, nil))
                }
            }
        }
    }

    /// Shows a picker for client certificate (mTLS) authentication.
    ///
    /// Queries the user's keychain for identities matching the server's
    /// accepted issuer DNs (`protectionSpace.distinguishedNames`). If none
    /// match, falls back to `.performDefaultHandling` so WebKit can respond
    /// without a certificate. Otherwise routes through the dialog presenter,
    /// which shows `SFChooseIdentityPanel` as a window sheet.
    private func showClientCertificatePicker(
        challenge: URLAuthenticationChallenge,
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        let protectionSpace = challenge.protectionSpace
        let identities = ClientCertificateService.identities(
            matchingIssuers: protectionSpace.distinguishedNames,
        )

        guard !identities.isEmpty else {
            Logger.info(
                "No client identities available for \(protectionSpace.host); performing default handling",
                category: Logger.security,
            )
            return (.performDefaultHandling, nil)
        }

        let chosen = await dialogPresenter.handleClientCertificateChallenge(
            host: protectionSpace.host,
            identities: identities,
        )

        guard let chosen else {
            return (.cancelAuthenticationChallenge, nil)
        }

        let credential = URLCredential(
            identity: chosen,
            certificates: nil,
            persistence: .forSession,
        )
        return (.useCredential, credential)
    }
}

// MARK: - Sendability Helpers

/// Wraps a non-Sendable value for transfer across isolation boundaries.
private nonisolated struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) {
        self.value = value
    }
}
