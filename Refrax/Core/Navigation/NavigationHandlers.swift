import AppKit
import Foundation
import os
import RegexBuilder
import WebKit

// MARK: - External Scheme Handler

/// Protocol for opening URLs externally, enabling testability.
///
/// In production, `NSWorkspace` conforms to this protocol.
/// Tests can provide a mock implementation to avoid actually opening apps.
protocol ExternalURLOpener: Sendable {
    @MainActor
    func openExternal(_ url: URL)
}

extension NSWorkspace: ExternalURLOpener {
    @MainActor
    func openExternal(_ url: URL) {
        let _: Bool = self.open(url)
    }
}

/// A stub URL opener that records opened URLs without launching apps.
///
/// Used in tests to verify that external URLs are handled correctly
/// without side effects.
final class StubURLOpener: ExternalURLOpener, @unchecked Sendable {
    private let _openedURLs = OSAllocatedUnfairLock(initialState: [URL]())

    var openedURLs: [URL] {
        _openedURLs.withLock { $0 }
    }

    @MainActor
    func openExternal(_ url: URL) {
        _openedURLs.withLock { $0.append(url) }
    }
}

/// Opens external URL schemes in the appropriate system application.
///
/// Web browsers handle `http`, `https`, `file`, and a few special schemes
/// internally. All other schemes should be delegated to the operating system,
/// which routes them to registered handlers.
///
/// ## Supported Internal Schemes
///
/// - `http`, `https` — Standard web protocols
/// - `file` — Local filesystem access
/// - `about` — Browser-specific pages (about:blank)
/// - `data` — Inline data URLs ([RFC 2397](https://datatracker.ietf.org/doc/html/rfc2397))
/// - `blob` — Binary large objects created via JavaScript
/// - `javascript` — JavaScript execution (handled specially)
/// - `refrax` — Internal browser deep links
///
/// ## External Scheme Examples
///
/// - `mailto:user@example.com` → Mail application (or web mail if configured)
/// - `tel:+1234567890` → Phone/FaceTime
/// - `sms:+1234567890` → Messages
/// - `facetime:user@example.com` → FaceTime
/// - `slack://open` → Slack application
/// - `vscode://file/path` → VS Code
///
/// ## Web Mail Support
///
/// When `BrowserSettings.preferredMailHandler` is set to a web mail service
/// (Gmail, Outlook, etc.), `mailto:` links are redirected to the service's
/// compose URL instead of opening the system mail app.
///
/// Reference: [IANA URI Schemes](https://www.iana.org/assignments/uri-schemes/uri-schemes.xhtml)
struct ExternalSchemeHandler: NavigationActionHandler {
    /// URL schemes the browser handles internally.
    private static let internalSchemes: Set<String> = [
        "http",
        "https",
        "file",
        "about",
        "data",
        "blob",
        "javascript",
        "ws",
        "wss",
        DeepLink.scheme, // "refrax"
    ]

    /// The URL opener used to launch external applications.
    ///
    /// Defaults to `NSWorkspace.shared` in production.
    /// Tests can inject a `StubURLOpener` to avoid side effects.
    let urlOpener: any ExternalURLOpener

    /// Browser settings for mail handler preference.
    let settings: BrowserSettings?

    /// Creates an external scheme handler.
    ///
    /// - Parameters:
    ///   - urlOpener: The URL opener to use. Defaults to `NSWorkspace.shared`.
    ///   - settings: Browser settings for mail handler preference. Optional for tests.
    init(urlOpener: some ExternalURLOpener = NSWorkspace.shared, settings: BrowserSettings? = nil) {
        self.urlOpener = urlOpener
        self.settings = settings
    }

    func evaluate(_ action: some NavigationActionInput) async -> NavigationActionPolicy {
        guard let url = action.url,
              let scheme = url.scheme?.lowercased()
        else {
            return .next
        }

        // Internal schemes are handled by other parts of the browser
        guard !Self.internalSchemes.contains(scheme) else {
            return .next
        }

        // Special handling for mailto: with web mail preference
        if scheme == "mailto" {
            return await handleMailto(url)
        }

        // Delegate to system handler
        Logger.info("Opening external scheme: \(scheme)", category: Logger.navigation)

        urlOpener.openExternal(url)

        return .cancel
    }

    /// Handles mailto: URLs based on user preference.
    ///
    /// If a web mail service is configured, redirects to the compose URL.
    /// Otherwise, opens with the system mail handler.
    private func handleMailto(_ url: URL) async -> NavigationActionPolicy {
        // Get mail handler preference (must access settings on main actor)
        let handler = await MainActor.run {
            settings?.preferredMailHandler ?? .system
        }

        // If using a web mail service, redirect to compose URL
        if handler != .system, let composeURL = handler.buildComposeURL(from: url) {
            Logger.info("Opening mailto in web mail: \(handler.displayName)", category: Logger.navigation)
            return .openInNewTab(composeURL, activate: true)
        }

        // Default: open with system mail handler
        Logger.info("Opening mailto with system handler", category: Logger.navigation)
        urlOpener.openExternal(url)
        return .cancel
    }
}

// MARK: - Modifier Click Handler

/// Opens links in new tabs when middle-click or Cmd+click is used.
///
/// This handler implements standard browser behavior for opening links:
///
/// - **Middle-click** → Open in new background tab
/// - **Cmd+click** → Open in new background tab
/// - **Cmd+Shift+click** → Open in new tab and switch to it
///
/// ## Order in Handler Chain
///
/// This handler should run before the popup handler to intercept
/// modifier-key navigations before they're processed as regular navigations.
///
/// ## Reference
///
/// This follows the de facto standard established by major browsers.
/// See [MDN: Opening links in new tabs](https://developer.mozilla.org/en-US/docs/Web/HTML/Element/a#opening_links_in_a_new_tab)
struct ModifierClickHandler: NavigationActionHandler {
    func evaluate(_ action: some NavigationActionInput) async -> NavigationActionPolicy {
        // Only handle link activations with modifier keys
        guard action.isLinkActivated else {
            return .next
        }

        // Check for middle-click or Cmd+click
        guard action.isMiddleClick || action.isCommandClick else {
            return .next
        }

        guard let url = action.url else {
            return .next
        }

        // Don't open internal schemes in new tabs
        if url.scheme == DeepLink.scheme || url.scheme == "javascript" {
            return .next
        }

        let activate = action.shouldActivateNewTab
        Logger.info(
            "Modifier-click opening in new tab (activate: \(activate)): \(url.absoluteString)",
            category: Logger.navigation,
        )

        return .openInNewTab(url, activate: activate)
    }
}

// MARK: - Download Action Handler

/// Handles navigation actions that should become downloads.
///
/// Detects when the HTML content indicates a download via the `download`
/// attribute on anchor elements, per
/// [HTML Living Standard § 4.6.5](https://html.spec.whatwg.org/multipage/links.html#downloading-resources).
///
/// ## Example HTML
///
/// ```html
/// <a href="report.pdf" download>Download Report</a>
/// <a href="data.csv" download="export.csv">Export Data</a>
/// ```
///
/// ## Flow
///
/// When detected, returns `.download(url)` and the caller is responsible for
/// initiating the download through the download manager.
///
/// ## Note on target="_blank" Downloads
///
/// Links with `target="_blank"` pointing to downloadable content are handled
/// by ``PopupHandler``, which probes the URL via HEAD request before deciding
/// whether to download or open a tab. This avoids UI flicker from creating
/// then immediately closing empty tabs.
struct DownloadActionHandler: NavigationActionHandler {
    func evaluate(_ action: some NavigationActionInput) async -> NavigationActionPolicy {
        guard action.shouldPerformDownload else {
            return .next
        }

        guard let url = action.url else {
            return .next
        }

        Logger.info("Download attribute detected: \(url.absoluteString)", category: Logger.navigation)

        return .download(url)
    }
}

// MARK: - Popup Handler

/// Manages new window/tab requests from web content.
///
/// When web content requests a new window (via `target="_blank"` links or
/// `window.open()` calls), WebKit signals this with a `nil` target frame.
/// This handler decides whether to allow, block, or redirect these requests.
///
/// ## Download Detection
///
/// For user-initiated popups, we probe the URL with a HEAD request to check
/// if it leads to a downloadable file. This avoids UI flicker from creating
/// a tab that immediately becomes a download.
///
/// ```
/// target="_blank" click → HEAD probe → download or webpage?
///                              ↓
///              ┌───────────────┴───────────────┐
///              ↓                               ↓
///        .download(url)              .openInNewTab(url)
/// ```
///
/// ## Policy
///
/// 1. **User-initiated navigations** (link clicks, form submissions) always
///    bypass popup blocking. This matches browser convention: clicking a link
///    is fundamentally different from script-initiated popups.
///
/// 2. **Script-initiated popups** (window.open() without user gesture) are
///    subject to the site's popup policy. If the policy is `.allow`, the popup
///    opens; otherwise it's blocked.
///
/// ## User Gesture Detection
///
/// Per the [HTML Living Standard § User Activation](https://html.spec.whatwg.org/multipage/interaction.html#tracking-user-activation),
/// user activation is a transient state that enables privileged operations
/// like opening new windows.
struct PopupHandler: NavigationActionHandler {
    let policyProvider: any PopUpPolicyProviding
    let contentProbe: any PopupContentProbing

    /// Creates a PopupHandler with the specified dependencies.
    ///
    /// - Parameters:
    ///   - policyProvider: Provider for popup policy lookups. Use `SiteSettingsCoordinator` in production.
    ///   - contentProbe: Probe for determining popup content type. Defaults to `PopupContentProbe.shared`.
    init(
        policyProvider: some PopUpPolicyProviding,
        contentProbe: some PopupContentProbing = PopupContentProbe.shared,
    ) {
        self.policyProvider = policyProvider
        self.contentProbe = contentProbe
    }

    /// Creates a PopupHandler with a `SiteSettingsCoordinator`.
    ///
    /// Convenience initializer for production code.
    init(siteSettingsCoordinator: SiteSettingsCoordinator) {
        self.policyProvider = siteSettingsCoordinator
        self.contentProbe = PopupContentProbe.shared
    }

    func evaluate(_ action: some NavigationActionInput) async -> NavigationActionPolicy {
        // Only handle new window requests (nil target frame)
        guard action.isNewWindowRequest else {
            return .next
        }

        guard let url = action.url else {
            Logger.debug("Blocked popup with no URL", category: Logger.navigation)
            return .cancel
        }

        // Block javascript: URLs in new windows (security risk)
        if url.scheme?.lowercased() == "javascript" {
            Logger.debug("Blocked javascript: popup", category: Logger.navigation)
            return .cancel
        }

        // User-initiated navigations always bypass popup blocking policy.
        // This matches browser convention: clicking a link that opens a new window
        // is fundamentally different from script-initiated window.open() calls.
        if action.isUserInitiated || action.isLinkActivated || action.isFormSubmission {
            // Probe the URL to determine if it's a download (only for download-like URLs)
            let probeResult = await contentProbe.probe(url)

            switch probeResult {
            case let .download(finalURL, suggestedFilename):
                Logger.info(
                    "Popup probe detected download: \(suggestedFilename ?? finalURL.lastPathComponent)",
                    category: Logger.navigation,
                )
                return .download(finalURL)

            case let .webpage(finalURL):
                Logger.info("Opening popup in new tab: \(finalURL.absoluteString)", category: Logger.navigation)
                return .openInNewTab(finalURL, activate: action.shouldActivateNewTab)

            case .skipProbe:
                // URL doesn't look like a download - open tab directly without probing
                Logger.info("Opening popup in new tab: \(url.absoluteString)", category: Logger.navigation)
                return .openInNewTab(url, activate: action.shouldActivateNewTab)

            case .unknown:
                // Probe failed or timed out - fall back to opening a tab
                // The DownloadResponseHandler will detect downloads via response headers
                Logger.info(
                    "Popup probe inconclusive, opening tab: \(url.absoluteString)",
                    category: Logger.navigation,
                )
                return .openInNewTab(url, activate: action.shouldActivateNewTab)
            }
        }

        // Script-initiated popup: check site policy
        let policy = policyProvider.popUpPolicy(for: url)
        switch policy {
        case .allow:
            Logger.info("Allowing script-initiated popup (site policy): \(url.absoluteString)", category: Logger.navigation)
            return .openInNewTab(url, activate: true)
        case .block, .blockAndNotify:
            Logger.info("Blocked script-initiated popup: \(url.absoluteString)", category: Logger.navigation)
            return .cancel
        }
    }
}

// MARK: - Pinned Tab Containment Handler

/// Implements Arc-style navigation containment for pinned tabs and live favorites.
///
/// When a pinned tab or live favorite navigates to a different domain, this handler
/// intercepts the navigation and shows a preview panel instead. This keeps the tab
/// focused on its designated site (e.g., GitHub, Slack, email) while still allowing
/// users to view and interact with cross-domain links.
///
/// ## Behavior
///
/// | Condition | Action |
/// |-----------|--------|
/// | Same domain | Allow navigation normally |
/// | Different domain | Show in preview panel |
/// | Download | Allow (handled by earlier handlers) |
/// | Non-HTTP(S) | Allow (mailto:, etc.) |
///
/// ## Order in Handler Chain
///
/// This handler runs after `ModifierClickHandler` to ensure that Cmd+click and
/// middle-click still open new tabs normally. It runs before `PopupHandler` so that
/// `target="_blank"` links on contained tabs show previews instead of opening tabs.
///
/// Downloads are handled by `DownloadActionHandler` which runs before this handler,
/// so download links proceed normally without triggering preview.
struct PinnedTabContainmentHandler: NavigationActionHandler {
    /// The tab associated with this navigation, if any.
    ///
    /// Used to check pinned/live favorite status and retrieve the home URL.
    let tab: Tab?

    func evaluate(_ action: some NavigationActionInput) async -> NavigationActionPolicy {
        // Handle main frame navigations and new window requests (target="_blank")
        guard action.isMainFrame || action.isNewWindowRequest else { return .next }

        // Only apply to pinned tabs or live favorites with a home URL
        guard let tab, let homeURL = tab.homeURL else { return .next }

        // Get the target URL
        guard let targetURL = action.url else { return .next }

        // Only apply to HTTP(S) URLs
        guard let scheme = targetURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else { return .next }

        // Extract registrable domains for comparison
        guard let homeDomain = homeURL.registrableDomain?.lowercased(),
              let targetDomain = targetURL.registrableDomain?.lowercased()
        else { return .next }

        // Same domain - allow navigation
        if homeDomain == targetDomain {
            return .next
        }

        // Different domain - show preview
        Logger.info(
            "Containment: \(homeDomain) → \(targetDomain), showing preview",
            category: Logger.navigation,
        )
        return .showPreview(targetURL)
    }
}

// MARK: - Link Protection Handler

/// Applies privacy-preserving URL transformations during navigation.
///
/// This handler integrates ``LinkProtection`` into the navigation pipeline,
/// cleaning URLs before they're loaded:
///
/// 1. Converts AMP cache URLs to canonical publisher URLs
/// 2. Removes tracking query parameters
///
/// ## When Applied
///
/// Link protection runs only for main frame navigations to avoid breaking
/// embedded content that may rely on tracking parameters for functionality.
///
/// ## Performance
///
/// URL cleaning is synchronous and fast (string operations only), so it
/// doesn't add noticeable latency to navigation.
///
/// ## Loop Prevention
///
/// To prevent redirect loops (e.g., if a cleaned URL somehow produces another
/// cleaned URL), we track recently redirected URLs and skip them on subsequent
/// navigations within a short time window.
struct LinkProtectionHandler: NavigationActionHandler {
    private static let loopPrevention = RedirectLoopPrevention()

    /// Whether link protection is enabled.
    let enabled: Bool

    /// Whether to remove tracking query parameters.
    let removeTracking: Bool

    /// Whether to convert AMP URLs to canonical form.
    let convertAMP: Bool

    /// Creates a handler with the specified settings.
    ///
    /// - Parameters:
    ///   - enabled: Master toggle for link protection.
    ///   - removeTracking: Whether to strip tracking parameters.
    ///   - convertAMP: Whether to convert AMP links.
    init(enabled: Bool = true, removeTracking: Bool = true, convertAMP: Bool = true) {
        self.enabled = enabled
        self.removeTracking = removeTracking
        self.convertAMP = convertAMP
    }

    /// Creates a handler from privacy protection settings.
    ///
    /// - Parameter settings: The privacy settings to read configuration from.
    init(privacySettings: PrivacyProtectionSettings) {
        self.enabled = privacySettings.enableLinkProtection
        self.removeTracking = privacySettings.removeTrackingParameters
        self.convertAMP = privacySettings.convertAMPLinks
    }

    func evaluate(_ action: some NavigationActionInput) async -> NavigationActionPolicy {
        // Skip if disabled or no active transformations
        guard enabled, removeTracking || convertAMP else {
            return .next
        }

        guard action.isMainFrame, let url = action.url else {
            return .next
        }

        if OAuthDomainRegistry.shouldBypassPrivacyProtection(url)
            || action.redirectChain?.containsOAuthURL == true {
            return .next
        }

        // Skip if we recently redirected to this URL (prevents loops)
        if await Self.loopPrevention.contains(url) {
            return .next
        }

        guard let cleanedURL = LinkProtection.cleanURL(
            from: url,
            removeTracking: removeTracking,
            convertAMP: convertAMP,
        ) else {
            return .next
        }

        await Self.loopPrevention.record(cleanedURL)

        Logger.info("Cleaned URL: \(url.absoluteString) → \(cleanedURL.absoluteString)", category: Logger.navigation)

        return .redirect(cleanedURL)
    }
}

/// Actor-isolated cache for tracking recent redirects to prevent loops.
///
/// Uses time-based expiration to automatically clear stale entries.
/// The cache is lightweight and designed for low-volume navigation events.
private actor RedirectLoopPrevention {
    private var recentRedirects: [URL: ContinuousClock.Instant] = [:]
    private let expiration: Duration = .seconds(2)
    private let maxEntries = 20

    /// Checks if a URL was recently used as a redirect target.
    func contains(_ url: URL) -> Bool {
        let now = ContinuousClock.now
        guard let timestamp = recentRedirects[url] else { return false }
        return now - timestamp < expiration
    }

    /// Records a redirect to prevent immediate re-processing.
    func record(_ url: URL) {
        let now = ContinuousClock.now

        // Clean up expired entries on every insert to prevent memory growth
        recentRedirects = recentRedirects.filter { now - $0.value < expiration }

        recentRedirects[url] = now

        // Additional cleanup if still over max entries (shouldn't happen often)
        if recentRedirects.count > maxEntries {
            recentRedirects = recentRedirects.filter { now - $0.value < expiration }
        }
    }
}

// MARK: - Deep Link Handler

/// Routes internal `refrax://` deep links to native in-tab views.
///
/// Recognized deep links:
/// - `refrax://ssl-error?type=...&url=...` — SSL certificate error interstitial
/// - `refrax://focus-blocked?url=...&focus=...` — Focus mode blocked page
///
/// Unrecognized `refrax://` URLs are cancelled to prevent loading external content.
struct DeepLinkHandler: NavigationActionHandler {
    func evaluate(_ action: some NavigationActionInput) async -> NavigationActionPolicy {
        guard let url = action.url,
              url.scheme == DeepLink.scheme
        else {
            return .next
        }

        // Validate the deep link is recognized
        guard DeepLink(url: url) != nil else {
            Logger.warning("Unknown deep link: \(url.absoluteString)", category: Logger.navigation)
            return .cancel
        }

        // All recognized deep links render in-tab via DeepLinkView
        return .allow
    }
}

// MARK: - Subframe Navigation Handler

/// Allows navigation in subframes (iframes) unconditionally.
///
/// Subframe navigations are essential for:
///
/// - Silent OAuth token refresh (hidden iframes)
/// - Embedded content (videos, maps, widgets)
/// - Advertising (if not blocked by content blocker)
/// - Analytics and tracking scripts
///
/// Per the [Same-Origin Policy](https://developer.mozilla.org/en-US/docs/Web/Security/Same-origin_policy),
/// cross-origin iframes are sandboxed by the browser. We allow the navigation
/// but rely on WebKit's security model for protection.
///
/// ## Order in Handler Chain
///
/// This handler should run early in the chain to avoid unnecessary processing
/// of subframe navigations by subsequent handlers.
struct SubframeNavigationHandler: NavigationActionHandler {
    func evaluate(_ action: some NavigationActionInput) async -> NavigationActionPolicy {
        // Main frame navigations are handled by other handlers
        // If target is nil (new window request) or target is main frame, pass to next handler
        guard let targetIsMainFrame = action.targetIsMainFrame,
              !targetIsMainFrame
        else {
            return .next
        }

        // Allow all subframe navigations
        return .allow
    }
}

// MARK: - Download Response Handler

/// Detects responses that should be downloaded rather than displayed.
///
/// A navigation response should become a download when:
///
/// 1. **Content-Disposition: attachment** — Server explicitly requests download
///    per [RFC 6266](https://datatracker.ietf.org/doc/html/rfc6266)
///
/// 2. **Non-displayable MIME type** — WebKit cannot render the content
///    (e.g., `application/zip`, `application/octet-stream`)
///
/// 3. **HTTP error status** — 4xx/5xx responses (handled separately)
///
/// ## Download Flow
///
/// When this handler returns `.download`, the browser should:
/// 1. Cancel the navigation response
/// 2. Re-request the URL as a download
/// 3. Present download UI to the user
struct DownloadResponseHandler: NavigationResponseHandler {
    /// MIME types that WebKit can definitely display, even if `canShowMIMEType` returns false.
    ///
    /// WebKit's `canShowMIMEType` can sometimes return `false` for media types that it
    /// actually CAN play (especially when loaded as the main frame). This causes
    /// intermittent issues where media files get treated as downloads.
    private static let alwaysDisplayableMIMETypes: Set<String> = [
        // Audio
        "audio/mpeg", "audio/mp3", "audio/mp4", "audio/aac", "audio/wav",
        "audio/ogg", "audio/webm", "audio/x-m4a", "audio/flac",
        // Video
        "video/mp4", "video/webm", "video/ogg", "video/quicktime",
        // Images
        "image/jpeg", "image/png", "image/gif", "image/webp", "image/svg+xml",
        // Documents WebKit can render
        "application/pdf",
    ]

    func evaluate(_ response: some NavigationResponseInput) async -> NavigationResponsePolicy {
        // Server requested download
        if response.hasDownloadDisposition {
            Logger.info("Download disposition: \(response.url?.absoluteString ?? "unknown")", category: Logger.navigation)
            return .download
        }

        // WebKit can't display this content type
        if !response.canShowMIMEType {
            // Check if it's a type we know WebKit CAN display (work around canShowMIMEType bugs)
            if let mimeType = response.mimeType?.lowercased(),
               Self.alwaysDisplayableMIMETypes.contains(mimeType) {
                Logger.info(
                    "canShowMIMEType=false but known displayable type: \(mimeType)",
                    category: Logger.navigation,
                )
                return .next
            }

            Logger.info("Non-displayable MIME type: \(response.mimeType ?? "unknown")", category: Logger.navigation)
            return .download
        }

        return .next
    }
}

// MARK: - HTTP Error Handler

/// Shows error pages for HTTP error responses.
///
/// HTTP status codes in the 4xx (client error) and 5xx (server error) ranges
/// indicate failed requests. Rather than displaying a blank page or the
/// server's error HTML, we show a consistent error page.
///
/// ## Status Code Ranges
///
/// Per [RFC 9110 § 15](https://datatracker.ietf.org/doc/html/rfc9110#section-15):
///
/// - **4xx Client Error**: Request was malformed or unauthorized
///   - 400 Bad Request, 401 Unauthorized, 403 Forbidden, 404 Not Found
///
/// - **5xx Server Error**: Server failed to fulfill valid request
///   - 500 Internal Server Error, 502 Bad Gateway, 503 Service Unavailable
///
/// ## Error Page
///
/// Errors return `.showError` which triggers `loadAlternateHTMLForError`
/// to show a native error view with retry functionality.
struct HTTPErrorHandler: NavigationResponseHandler {
    func evaluate(_ response: some NavigationResponseInput) async -> NavigationResponsePolicy {
        // Only handle main frame responses
        guard response.isMainFrame else {
            return .next
        }

        // Check for HTTP error status
        guard let statusCode = response.statusCode,
              statusCode >= 400,
              let failedURL = response.url
        else {
            return .next
        }

        Logger.warning("HTTP \(statusCode) for: \(failedURL.absoluteString)", category: Logger.navigation)

        return .showError(code: statusCode, failedURL: failedURL)
    }
}

// MARK: - Data URL Script Handler

/// Blocks data: URLs containing executable script content.
///
/// Data URLs ([RFC 2397](https://datatracker.ietf.org/doc/html/rfc2397)) can contain
/// arbitrary content, including malicious scripts. This handler detects and blocks
/// data URLs with potentially dangerous content.
///
/// ## Security Risks
///
/// - XSS attacks via `data:text/html,<script>...</script>`
/// - Phishing pages served entirely from data URLs
/// - Bypassing content security policies
///
/// ## Detection
///
/// Uses Swift Regex to identify:
/// - `<script>` tags (with any attributes)
/// - Event handlers (`onclick`, `onerror`, etc.)
/// - `javascript:` URLs embedded in data content
///
/// ## References
///
/// - [OWASP: XSS Prevention](https://cheatsheetseries.owasp.org/cheatsheets/Cross_Site_Scripting_Prevention_Cheat_Sheet.html)
/// - [Chromium: Data URL Navigation](https://www.chromium.org/Home/chromium-security/data-url-security/)
struct DataURLScriptHandler: NavigationActionHandler {
    /// Regex pattern for detecting script tags.
    /// Matches: <script>, <script src="...">, <script type="text/javascript">, etc.
    private static let scriptTagPattern = Regex {
        "<"
        Optionally {
            "/"
        }
        "script"
        ChoiceOf {
            ">"
            /\s/
        }
    }
    .ignoresCase()

    /// Regex pattern for dangerous event handlers.
    /// Matches: onclick="...", onerror='...', onload=`...`, etc.
    private static let eventHandlerPattern = Regex {
        /\bon/
        OneOrMore(.word)
        /\s*/
        "="
    }
    .ignoresCase()

    /// Regex pattern for javascript: protocol in attributes.
    /// Matches: href="javascript:...", src='javascript:...', etc.
    private static let javascriptProtocolPattern = Regex {
        /["']/
        /\s*/
        "javascript:"
    }
    .ignoresCase()

    func evaluate(_ action: some NavigationActionInput) async -> NavigationActionPolicy {
        guard let url = action.url,
              url.scheme?.lowercased() == "data"
        else {
            return .next
        }

        // Only check main frame data URLs - subframes are sandboxed
        guard action.isMainFrame else {
            return .next
        }

        // Extract the content after "data:"
        let urlString = url.absoluteString
        guard let dataContent = urlString.dropFirst(5).removingPercentEncoding else {
            return .next
        }

        // Check for dangerous patterns
        if containsDangerousContent(dataContent) {
            Logger.warning("Blocked data URL with script content", category: Logger.navigation)
            return .cancel
        }

        return .next
    }

    private func containsDangerousContent(_ content: String) -> Bool {
        // Check for script tags
        if content.contains(Self.scriptTagPattern) {
            return true
        }

        // Check for event handlers
        if content.contains(Self.eventHandlerPattern) {
            return true
        }

        // Check for javascript: protocol
        if content.contains(Self.javascriptProtocolPattern) {
            return true
        }

        return false
    }
}

// MARK: - Blob URL Handler

/// Restricts blob: URL navigation to user-initiated actions only.
///
/// Blob URLs (`blob:https://example.com/uuid`) are created by JavaScript using
/// `URL.createObjectURL()`. They're scoped to the creating origin but can be
/// used for various attacks if navigated to programmatically.
///
/// ## Security Concerns
///
/// - Blob URLs can contain any content type, including HTML with scripts
/// - They persist until explicitly revoked or page unload
/// - Cross-origin blob URLs shouldn't be accessible, but defense in depth applies
///
/// ## Policy
///
/// - User-initiated navigations (clicks, form submissions) are allowed
/// - Script-initiated main frame navigations are blocked
/// - Subframe blob URLs are allowed (sandboxed by WebKit)
///
/// ## References
///
/// - [MDN: URL.createObjectURL()](https://developer.mozilla.org/en-US/docs/Web/API/URL/createObjectURL_static)
/// - [HTML Living Standard: Blob URL Entry](https://html.spec.whatwg.org/multipage/urls-and-fetching.html#blob-url-entry)
struct BlobURLHandler: NavigationActionHandler {
    func evaluate(_ action: some NavigationActionInput) async -> NavigationActionPolicy {
        guard let url = action.url,
              url.scheme?.lowercased() == "blob"
        else {
            return .next
        }

        // Only restrict main frame blob navigations
        guard action.isMainFrame else {
            return .next
        }

        // Allow user-initiated navigations
        if action.isUserInitiated || action.isLinkActivated || action.isFormSubmission {
            Logger.debug("Allowing user-initiated blob URL navigation", category: Logger.navigation)
            return .next
        }

        // Block script-initiated blob navigations to main frame
        Logger.warning(
            "Blocked script-initiated blob URL navigation: \(url.absoluteString.prefix(100))",
            category: Logger.navigation,
        )
        return .cancel
    }
}

// MARK: - File Scheme Handler

/// Restricts file: URL access to user-initiated actions only.
///
/// The file: scheme provides direct filesystem access, which is a significant
/// security concern. Unrestricted file: URL navigation could allow:
///
/// ## Security Risks
///
/// - Reading sensitive local files (SSH keys, browser data, credentials)
/// - Directory traversal attacks
/// - Information disclosure via error messages
///
/// ## Policy
///
/// - User-initiated navigations (address bar entry, drag-drop, file->open) are allowed
/// - Script-initiated file: navigations from web content are blocked
/// - File-to-file navigations are allowed (local HTML linking to local resources)
///
/// ## Implementation Notes
///
/// WebKit already has same-origin restrictions on file URLs, but this provides
/// defense in depth against any bypass vulnerabilities.
///
/// ## References
///
/// - [WebKit File URL Security](https://webkit.org/blog/8124/link-click-analytics-and-privacy/)
/// - [Chromium File URL Policy](https://chromium.googlesource.com/chromium/src/+/main/docs/security/file-urls.md)
struct FileSchemeHandler: NavigationActionHandler {
    func evaluate(_ action: some NavigationActionInput) async -> NavigationActionPolicy {
        guard let url = action.url,
              url.scheme?.lowercased() == "file"
        else {
            return .next
        }

        // Allow if source is also a file: URL (local document linking to local resources)
        // Note: securityOrigin.protocol may be empty string for certain frames (e.g., about:blank)
        let sourceProtocol = action.sourceSecurityOriginProtocol
        if !sourceProtocol.isEmpty, sourceProtocol == "file" {
            return .next
        }

        // Allow user-initiated navigations (typing in address bar, clicking links)
        if action.isUserInitiated || action.isLinkActivated {
            Logger.debug("Allowing user-initiated file URL navigation", category: Logger.navigation)
            return .next
        }

        // Allow back/forward and reload (user controls these)
        if action.isBackForward || action.isReload {
            return .next
        }

        // Allow programmatic loads from empty/new tabs (e.g., Open File, app delegate file open)
        // These come from our own loadFileURL calls, not from web content scripts.
        if sourceProtocol.isEmpty || sourceProtocol == "about" {
            return .next
        }

        // Block script-initiated file: navigations from web content
        Logger.warning(
            "Blocked script-initiated file URL navigation from web content: \(url.path)",
            category: Logger.navigation,
        )
        return .cancel
    }
}

// MARK: - URL Shortener Handler

/// Expands shortened URLs to their final destinations.
///
/// URL shorteners like bit.ly and t.co obscure link destinations, making it
/// difficult for users to know where they're going. This handler intercepts
/// navigations to known shortener domains and expands them before loading.
///
/// ## Privacy Approach
///
/// Expansion is done via HEAD requests in an ephemeral session:
/// - No cookies are sent or stored
/// - No JavaScript is executed
/// - Only HTTP redirects are followed
///
/// ## Performance
///
/// To avoid blocking navigation, expansion has a configurable timeout (default 5s).
/// If expansion fails or times out, the original URL is used.
///
/// ## Settings Integration
///
/// This handler checks ``PrivacyProtectionSettings/expandURLShorteners`` before
/// attempting expansion. Users can disable this feature or configure the timeout.
struct URLShortenerHandler: NavigationActionHandler {
    let settings: BrowserSettings

    func evaluate(_ action: some NavigationActionInput) async -> NavigationActionPolicy {
        guard action.isMainFrame, let url = action.url else {
            return .next
        }

        if OAuthDomainRegistry.shouldBypassPrivacyProtection(url)
            || action.redirectChain?.containsOAuthURL == true {
            return .next
        }

        // Check if feature is enabled
        let privacySettings = settings.privacyProtection
        guard privacySettings.expandURLShorteners else {
            return .next
        }

        // Check if this is a shortener URL
        guard URLShortenerExpander.isShortenerURL(url) else {
            return .next
        }

        // Check exceptions
        if let host = url.host?.lowercased() {
            let lowercasedExceptions = privacySettings.linkProtectionExceptions.map { $0.lowercased() }
            if lowercasedExceptions.contains(where: { host.contains($0) }) {
                return .next
            }
        }

        // Expand the URL
        let timeout = privacySettings.shortenerExpansionTimeout
        if let expandedURL = await URLShortenerExpander.shared.expand(url, timeout: timeout) {
            Logger.info(
                "Expanded shortener: \(url.host ?? "") → \(expandedURL.host ?? "")",
                category: Logger.navigation,
            )
            return .redirect(expandedURL)
        }

        return .next
    }
}

// MARK: - Custom Redirect Handler

/// Applies user-defined URL transformation rules.
///
/// Users can create custom redirect rules to transform URLs before navigation.
/// Common use cases:
///
/// - Redirect Twitter/X links to Nitter
/// - Redirect YouTube to Invidious/Piped
/// - Redirect Reddit to Teddit/Libreddit
/// - Redirect Medium to Scribe
///
/// ## Pattern Syntax
///
/// Rules use simple wildcard patterns:
/// - `*` matches any sequence of characters
/// - Captured wildcards can be referenced in the destination as `$1`, `$2`, etc.
///
/// ## Example
///
/// ```
/// Source:      twitter.com/*
/// Destination: nitter.net/$1
///
/// Input:  https://twitter.com/user/status/123
/// Output: https://nitter.net/user/status/123
/// ```
struct CustomRedirectHandler: NavigationActionHandler {
    let settings: BrowserSettings

    func evaluate(_ action: some NavigationActionInput) async -> NavigationActionPolicy {
        guard action.isMainFrame, let url = action.url else {
            return .next
        }

        if OAuthDomainRegistry.shouldBypassPrivacyProtection(url)
            || action.redirectChain?.containsOAuthURL == true {
            return .next
        }

        // Get enabled redirects sorted by order
        let redirects = settings.privacyProtection.customRedirects
            .filter(\.isEnabled)
            .sorted { $0.order < $1.order }

        // Try each redirect rule
        for redirect in redirects {
            if let newURL = redirect.apply(to: url) {
                Logger.info(
                    "Custom redirect: \(redirect.name) → \(newURL.host ?? "")",
                    category: Logger.navigation,
                )
                return .redirect(newURL)
            }
        }

        return .next
    }
}

// MARK: - App Redirect Handler

/// Opens matching URLs in external applications.
///
/// Users can configure rules to open specific URLs in dedicated apps instead
/// of the browser. Use cases:
///
/// - Open YouTube in IINA or a dedicated player
/// - Open GitHub in a native client
/// - Open Zoom/Teams links in their apps
/// - Open Spotify in the desktop app
///
/// ## Pattern Matching
///
/// Rules match by domain (with optional path):
/// - `youtube.com` — exact domain match
/// - `*.youtube.com` — matches any subdomain
/// - `zoom.us/j/*` — matches join meeting URLs only
struct AppRedirectHandler: NavigationActionHandler {
    let settings: BrowserSettings

    func evaluate(_ action: some NavigationActionInput) async -> NavigationActionPolicy {
        guard action.isMainFrame, let url = action.url else {
            return .next
        }

        if OAuthDomainRegistry.shouldBypassPrivacyProtection(url)
            || action.redirectChain?.containsOAuthURL == true {
            return .next
        }

        // Get enabled rules sorted by order
        let rules = settings.privacyProtection.appRedirectRules
            .filter(\.isEnabled)
            .sorted { $0.order < $1.order }

        // Try each rule
        for rule in rules {
            if rule.matches(url) {
                Logger.info(
                    "App redirect: \(rule.name) → \(rule.targetAppBundleID)",
                    category: Logger.navigation,
                )

                // Open in target app
                if await rule.openInTargetApp(url) {
                    return .cancel
                } else {
                    return .next
                }
            }
        }

        return .next
    }
}

// MARK: - Focus Mode Restriction Handler

/// Blocks or redirects navigation based on Focus Mode restrictions.
///
/// When a Focus Mode is active with domain restrictions configured, this handler
/// intercepts main frame navigations to blocked domains and redirects them to
/// a Focus Mode interstitial page.
///
/// ## Behavior
///
/// - **Blocked domains**: Redirect to `refrax://focus-blocked` interstitial
/// - **Blurred domains**: Allowed to proceed (blur is applied after load)
/// - **Session bypassed domains**: Allowed to proceed
///
/// ## Order in Handler Chain
///
/// This handler should run after security handlers but before URL transformation
/// handlers. Blocked navigations take precedence over link cleaning.
struct FocusModeRestrictionHandler: NavigationActionHandler {
    func evaluate(_ action: some NavigationActionInput) async -> NavigationActionPolicy {
        // Only check main frame navigations
        guard action.isMainFrame, let url = action.url else {
            return .next
        }

        // Skip deep links and internal schemes
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return .next
        }

        guard let host = url.host?.lowercased() else {
            return .next
        }

        // Check restrictions on main actor
        let shouldBlock = await MainActor.run {
            RestrictionEnforcer.shared.shouldBlock(domain: host)
        }

        guard shouldBlock else {
            return .next
        }

        // Get Focus name for the interstitial
        let focusName = await MainActor.run {
            // Try to get the Focus name from FocusModeManager if available
            // Fall back to "Focus Mode" if not available
            "Focus Mode"
        }

        Logger.info("Focus Mode blocking: \(host)", category: Logger.navigation)

        // Redirect to the Focus blocked interstitial
        let deepLink = DeepLink.focusBlocked(blockedURL: url, focusName: focusName)
        return .redirect(deepLink.url)
    }
}

// MARK: - Handler Chain Helpers

/// A chain of navigation action handlers evaluated in order.
///
/// Handlers are evaluated sequentially until one returns a non-`.next` policy.
/// If all handlers return `.next`, the navigation is allowed.
///
/// ## Usage
///
/// ```swift
/// let chain = NavigationActionChain(handlers: [
///     ExternalSchemeHandler(),
///     PopupHandler(siteSettingsCoordinator: coordinator),
///     LinkProtectionHandler(),
/// ])
///
/// let policy = await chain.evaluate(action)
/// ```
struct NavigationActionChain: NavigationActionHandler {
    let handlers: [any NavigationActionHandler]

    func evaluate(_ action: some NavigationActionInput) async -> NavigationActionPolicy {
        for handler in handlers {
            let policy = await handler.evaluate(action)
            if case .next = policy {
                continue
            }
            return policy
        }
        return .allow
    }
}

/// A chain of navigation response handlers evaluated in order.
struct NavigationResponseChain: NavigationResponseHandler {
    let handlers: [any NavigationResponseHandler]

    func evaluate(_ response: some NavigationResponseInput) async -> NavigationResponsePolicy {
        for handler in handlers {
            let policy = await handler.evaluate(response)
            if case .next = policy {
                continue
            }
            return policy
        }
        return .allow
    }
}
