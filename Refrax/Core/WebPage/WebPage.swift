import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - Deep Link Flag

/// Observable state for tracking deep link display.
///
/// This class allows ``RefraxSchemeHandler`` to notify ``WebPage`` when a
/// `refrax://` URL is intercepted, triggering SwiftUI view updates. Using a
/// separate observable class is necessary because:
///
/// 1. `WebPage.Configuration` must be set at init time (not modifiable after)
/// 2. The scheme handler callback needs to capture something to update state
/// 3. We can't capture `self` before all stored properties are initialized
///
/// By using a small holder class, we can capture it in the handler closure
/// before `self` is fully initialized, then observe it from the view layer.
@Observable
final class DeepLinkFlag {
    /// The intercepted deep link URL, or `nil` if not showing a deep link.
    ///
    /// When set, ``WebViewContainer`` renders a ``DeepLinkView`` for this URL
    /// instead of the WebKit ``WebView``.
    var deepLinkURL: URL?

    /// Whether the session is currently displaying a deep link.
    var isShowingDeepLink: Bool {
        deepLinkURL != nil
    }

    init() {}
}

// MARK: - Sticky Header Detection

/// Result of JavaScript-based sticky header detection.
///
/// Used as a fallback when WebKit's native `_sampledTopFixedPositionContentColor`
/// detection doesn't work (e.g., due to scroll position filtering in WebCore).
struct StickyHeaderDetectionResult: Codable, Sendable {
    /// Whether a sticky or fixed position header was detected at the top.
    let hasStickyHeader: Bool

    /// The background color of the header, if detected.
    /// Format is CSS color string (e.g., "rgb(255, 255, 255)").
    let headerColor: String?

    /// The height of the header in pixels, if detected.
    let headerHeight: Double?
}

// MARK: - WebPage

/// An observable object that controls and manages the behavior of interactive web content.
///
/// `WebPage` is Refrax's browser-optimized alternative to WebKit's `WebPage`, providing:
///
/// - **Direct `WKWebView` access**: Via `backingWebView` property (no reflection needed)
/// - **Private API integration**: Audio state, process state, inspector control via ObjC bridge headers
/// - **Browser-specific features**: History tracking, favicon loading, zoom control
/// - **SwiftUI compatibility**: Observable properties that trigger view updates
/// - **Persistence sync**: Automatic synchronization with persisted ``TabPage`` model
///
/// ## Architecture
///
/// ```
/// ┌─────────────────────────────────────────────────────────┐
/// │ TabPage (SwiftData - Persisted)                         │
/// │  - id, url, title, faviconData, layoutPosition          │
/// └────────────────────────┬────────────────────────────────┘
///                          │ runtime sync
/// ┌────────────────────────▼────────────────────────────────┐
/// │ WebPage (@Observable - Runtime)                         │
/// │  - backingWebView: WKWebView                            │
/// │  - all navigation state, security, audio, process...    │
/// │  - history tracking, favicon loading, zoom control      │
/// └─────────────────────────────────────────────────────────┘
/// ```
///
/// ## Usage
///
/// ```swift
/// let page = WebPage(
///     tabPage: tabPage,
///     configuration: configuration,
///     historyManager: historyManager,
///     autoFillManager: autoFillManager,
///     faviconCache: faviconCache,
///     navigationDecider: decider,
///     dialogPresenter: presenter
/// )
///
/// // Load content
/// page.load(url)
///
/// // Access properties
/// if page.isLoading {
///     ProgressView(value: page.estimatedProgress)
/// }
/// ```
///
/// ## Visibility Tracking
///
/// Call ``onBecameVisible()`` and ``onBecameHidden()`` from the view layer to enable
/// accurate time-spent tracking:
///
/// ```swift
/// WebView(page)
///     .onAppear { page.onBecameVisible() }
///     .onDisappear { page.onBecameHidden() }
/// ```
///
/// ## File layout
/// - `WebPage.swift`: core types, stored state, init/deinit, observation wiring.
/// - `WebPage+Navigation.swift`: loading/navigation, history, favicon, helpers.
/// - `WebPage+JavaScript.swift`: JS evaluation helpers.
/// - `WebPage+Media.swift`: media playback/capture/audio + PDF/image/in-window helpers.
/// - `WebPage+Zoom.swift`: zoom controls.
/// - `WebPage+FormData.swift`: form state queries.
/// - `WebPage+Inspector.swift`: Web Inspector actions.
/// - `WebPage+Windowing.swift`: multi-window ownership + mirror windows.
/// - `WebPage+LinkHover.swift`: link hover callbacks.
/// - `WebPage+Lifecycle.swift`: page pool hookup for process lifecycle.
@Observable
final class WebPage: Identifiable {
    // MARK: - Types

    /// A CSS media type as defined by the CSS specification.
    struct CSSMediaType: Hashable, RawRepresentable, Sendable {
        static let all = CSSMediaType(rawValue: "all")
        static let screen = CSSMediaType(rawValue: "screen")
        static let print = CSSMediaType(rawValue: "print")

        let rawValue: String
    }

    /// The set of possible fullscreen states.
    enum FullscreenState: Hashable, Sendable {
        case enteringFullscreen
        case exitingFullscreen
        case inFullscreen
        case notInFullscreen

        init(_ wrapped: WKWebView.FullscreenState) {
            self = switch wrapped {
            case .enteringFullscreen: .enteringFullscreen
            case .exitingFullscreen: .exitingFullscreen
            case .inFullscreen: .inFullscreen
            case .notInFullscreen: .notInFullscreen
            @unknown default: .notInFullscreen
            }
        }
    }

    /// Represents the overall security state of a page.
    enum SecurityState: Sendable {
        /// Secure: Valid HTTPS with no mixed content
        case secure

        /// Mixed content: Valid HTTPS but some resources loaded over HTTP
        case mixedContent

        /// Insecure: HTTP, invalid certificate, or unknown
        case insecure

        /// Local network: Special case for development/home servers
        case localNetwork
    }

    /// All external dependencies required to create and operate a WebPage.
    ///
    /// This struct bundles all manager and service dependencies that a WebPage needs.
    /// Passing dependencies as a single struct at init ensures nothing is forgotten
    /// and makes the dependency graph explicit.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// let dependencies = WebPage.Dependencies(
    ///     historyManager: historyManager,
    ///     autoFillManager: autoFillManager,
    ///     faviconCache: faviconCache,
    ///     settingsApplier: settingsApplier,
    ///     siteSettingsCoordinator: siteSettingsCoordinator,
    ///     domainTimeTracker: domainTimeTracker,
    ///     downloadManager: downloadManager,
    ///     webInspectorManager: webInspectorManager,
    ///     pagePool: pagePool,
    ///     navigationDecider: decider,
    ///     dialogPresenter: presenter
    /// )
    ///
    /// let page = WebPage(
    ///     tabPage: tabPage,
    ///     configuration: config,
    ///     dependencies: dependencies
    /// )
    /// ```
    struct Dependencies {
        /// Manager for recording browsing history.
        let historyManager: HistoryManager

        /// Manager for credential auto-fill.
        let autoFillManager: AutoFillManager

        /// Cache for domain-level favicon storage.
        let faviconCache: FaviconCache

        /// Applies user settings to the web page (user agent, content blockers, etc.).
        let settingsApplier: WebPageSettingsApplier

        /// Coordinator for per-site settings (permissions, autoplay policy).
        let siteSettingsCoordinator: SiteSettingsCoordinator

        /// Tracker for time spent on domains.
        let domainTimeTracker: DomainTimeTracker

        /// Manager for handling WKDownload completions.
        let downloadManager: DownloadManager

        /// Manager for Web Inspector developer tools.
        let webInspectorManager: WebInspectorManager

        /// Pool managing WebPage lifecycle and process termination handling.
        ///
        /// The page pool reference is passed to the navigation and UI delegates
        /// for handling process terminations and forced page closes.
        let pagePool: WebPagePool

        /// Policy object for handling navigation decisions.
        let navigationDecider: BrowserNavigationDecider

        /// Handler for JavaScript dialogs.
        let dialogPresenter: BrowserDialogPresenter
    }

    // MARK: - Identity & Persistence

    /// Unique identifier for this web page instance.
    ///
    /// This is synced from the associated ``TabPage`` for consistency.
    var id: UUID {
        tabPage.id
    }

    /// The persisted tab page model this session manages.
    ///
    /// Changes to URL, title, and favicon are synchronized back to this model
    /// during navigation events.
    ///
    /// This can be reassigned during tab transfers via ``transferTo(_:)``.
    var tabPage: TabPage

    /// The ID of the page that opened this one via window.open().
    var openerPageID: TabPage.ID?

    // MARK: - Configuration

    /// The configuration used to create this web page.
    let configuration: Configuration

    /// A preconfigured WKWebViewConfiguration supplied by WebKit for popups.
    @ObservationIgnored
    private let providedWebViewConfiguration: WKWebViewConfiguration?

    // MARK: - Backing Web View

    /// The underlying `WebPageWebView` instance.
    ///
    /// Use this for direct access to WebKit APIs not exposed through `WebPage`.
    /// Named to match WebKit's internal naming convention.
    @ObservationIgnored
    private(set) var backingWebView: WebPageWebView

    /// The website data store backing this page.
    ///
    /// Used to route cookie-dependent features (downloads, auth) through
    /// the same storage context as the page.
    var websiteDataStore: WKWebsiteDataStore {
        backingWebView.configuration.websiteDataStore
    }

    // MARK: - Delegates

    /// The navigation delegate adapter.
    @ObservationIgnored
    let backingNavigationDelegate: WKNavigationDelegateAdapter

    /// The UI delegate adapter.
    @ObservationIgnored
    let backingUIDelegate: WKUIDelegateAdapter

    // MARK: - Dependencies

    let historyManager: HistoryManager
    let autoFillManager: AutoFillManager
    let faviconCache: FaviconCache
    @ObservationIgnored
    let settingsApplier: WebPageSettingsApplier
    @ObservationIgnored
    weak var siteSettingsCoordinator: SiteSettingsCoordinator?
    @ObservationIgnored
    let domainTimeTracker: DomainTimeTracker

    /// Adapter for WebKit's private history delegate protocol.
    @ObservationIgnored
    var historyDelegateAdapter: HistoryDelegateAdapter?

    /// Adapter for WebKit's private icon loading delegate (favicon detection).
    @ObservationIgnored
    let iconLoadingDelegateAdapter: IconLoadingDelegateAdapter

    // MARK: - Download Manager

    /// The download manager for handling WKDownload completions.
    var downloadManager: DownloadManager? {
        get { backingNavigationDelegate.downloadManager }
        set { backingNavigationDelegate.downloadManager = newValue }
    }

    // MARK: - Observable Properties (Core WebKit)

    // These properties use the WebKit backingProperty pattern: lazy KVO observation
    // created on first access, reading values directly from backingWebView.

    /// The URL for the current webpage.
    var url: URL? {
        backingProperty(\.url, backedBy: \.url)
    }

    /// The page title.
    var title: String {
        backingProperty(\.title, backedBy: \.title) { $0 ?? "" }
    }

    /// An estimate of completion percentage of the current navigation (0.0 to 1.0).
    ///
    /// Throttled to only notify observers when progress changes by at least 1% (0.01)
    /// to reduce high-frequency updates during page loads (50-100 KVO events).
    /// Always updates when progress reaches 1.0 (complete).
    var estimatedProgress: Double {
        access(keyPath: \.estimatedProgress)
        return _estimatedProgress
    }

    @ObservationIgnored
    private var _estimatedProgress: Double = 0

    /// Whether the webpage is currently loading content.
    var isLoading: Bool {
        backingProperty(\.isLoading, backedBy: \.isLoading)
    }

    /// The trust management object for evaluating server certificates.
    var serverTrust: SecTrust? {
        backingProperty(\.serverTrust, backedBy: \.serverTrust)
    }

    /// Whether the webpage loaded all resources through secure connections.
    var hasOnlySecureContent: Bool {
        backingProperty(\.hasOnlySecureContent, backedBy: \.hasOnlySecureContent)
    }

    /// The fullscreen state of the page.
    var fullscreenState: FullscreenState {
        backingProperty(\.fullscreenState, backedBy: \.fullscreenState) { FullscreenState($0) }
    }

    /// Whether the webpage is using the camera.
    var cameraCaptureState: WKMediaCaptureState {
        backingProperty(\.cameraCaptureState, backedBy: \.cameraCaptureState)
    }

    /// Whether the webpage is using the microphone.
    var microphoneCaptureState: WKMediaCaptureState {
        backingProperty(\.microphoneCaptureState, backedBy: \.microphoneCaptureState)
    }

    /// The theme color extracted from the page's meta tags.
    var themeColor: Color? {
        backingProperty(\.themeColor, backedBy: \.themeColor) { $0.map { Color($0) } }
    }

    /// The sampled color from the top of the page.
    ///
    /// WebKit samples the actual rendered pixels at the top of the viewport.
    /// Use this as a fallback when `themeColor` is unavailable.
    ///
    /// Returns `nil` if:
    /// - The top pixels are not sufficiently uniform
    /// - Sampling is disabled in configuration
    /// - The page hasn't rendered yet
    var sampledPageTopColor: Color? {
        backingProperty(\.sampledPageTopColor, backedBy: \._sampledPageTopColor) { $0.map { Color($0) } }
    }

    /// The effective color for window tinting.
    ///
    /// Returns `sampledPageTopColor` which samples the actual rendered pixels
    /// at the top of the viewport, providing color information even for sites
    /// without explicit theme meta tags.
    var effectiveWindowColor: Color? {
        sampledPageTopColor
    }

    /// The height of sticky/fixed content at the top of the page.
    ///
    /// When greater than 0, indicates the page has a sticky header that
    /// should influence scroll edge effects.
    ///
    /// - Note: This property is not reliable for detecting sticky headers.
    ///   Use `prefersSolidColorHardScrollPocket` instead.
    var overflowHeightForTopScrollEdgeEffect: CGFloat {
        backingProperty(\.overflowHeightForTopScrollEdgeEffect, backedBy: \._overflowHeightForTopScrollEdgeEffect)
    }

    /// Whether WebKit prefers solid color (hard) blur over gradient (soft) blur.
    ///
    /// **Note:** This property only reflects client-explicit requests.
    /// Use `hasStickyHeader` instead for actual sticky header detection.
    var prefersSolidColorHardScrollPocket: Bool {
        backingProperty(\.prefersSolidColorHardScrollPocket, backedBy: \._prefersSolidColorHardScrollPocket)
    }

    /// The sampled color from fixed-position content at the top of the page.
    ///
    /// Returns the predominant color of any fixed/sticky position elements that
    /// intersect the top edge of the viewport. Non-nil indicates a sticky header.
    ///
    /// This property is KVO-observed and will trigger SwiftUI updates when
    /// WebKit detects or removes sticky headers.
    var sampledTopFixedPositionContentColor: NSColor? {
        backingProperty(\.sampledTopFixedPositionContentColor, backedBy: \._sampledTopFixedPositionContentColor)
    }

    /// Cached result of JavaScript sticky header detection.
    ///
    /// Updated after page load via `updateStickyHeaderDetection()`.
    /// This is observable to trigger SwiftUI updates when detection completes.
    private var _detectedStickyHeaderViaJS: Bool = false

    /// Whether the page has a sticky header (fixed-position content at the top).
    ///
    /// Uses a combination of:
    /// 1. WebKit's internal detection via `_sampledTopFixedPositionContentColor` (macOS 26+)
    /// 2. JavaScript fallback detection (cached after page load)
    ///
    /// When `true`, prefer uniform blur over gradient blur for the toolbar.
    var hasStickyHeader: Bool {
        // Try WebKit native detection first
        if sampledTopFixedPositionContentColor != nil {
            return true
        }
        // Fall back to cached JS detection
        return _detectedStickyHeaderViaJS
    }

    /// Detects sticky headers via JavaScript and updates the cached result.
    ///
    /// Waits for the page to finish loading before running detection. Uses
    /// `isLoading` observation with a timeout to avoid indefinite waits.
    ///
    /// - Note: This is async to allow callers to await completion and use
    ///   proper cancellation via `.task(id:)` modifiers.
    func detectStickyHeader() async {
        // Wait for page to finish loading (with timeout)
        let timeout = Duration.seconds(10)
        let startTime = ContinuousClock.now

        while isLoading {
            // Check for timeout
            if ContinuousClock.now - startTime > timeout {
                break
            }
            // Check for cancellation
            if Task.isCancelled { return }
            // Brief sleep to avoid busy-waiting
            try? await Task.sleep(for: .milliseconds(300))
        }

        // Additional wait for rendering to complete after load finishes
        await backingWebView.waitForPresentationUpdate()

        // Run JS detection
        let result = await hasStickyHeaderViaJS()
        _detectedStickyHeaderViaJS = result
    }

    /// Resets the cached sticky header detection.
    ///
    /// Call when starting a new navigation to avoid stale values from previous pages.
    func resetStickyHeaderDetection() {
        _detectedStickyHeaderViaJS = false
    }

    /// Detects sticky/fixed headers via JavaScript.
    ///
    /// This is a fallback detection method when WebKit's native `_sampledTopFixedPositionContentColor`
    /// doesn't work. It scans the DOM for elements with `position: sticky` or `position: fixed`
    /// that are positioned at the top of the viewport.
    ///
    /// - Returns: Detection result with header presence, sampled color, and height.
    ///
    /// ## Usage
    /// ```swift
    /// let result = await webPage.detectStickyHeaderViaJS()
    /// if result.hasStickyHeader {
    ///     // Use solid/uniform blur
    /// } else {
    ///     // Use gradient blur
    /// }
    /// ```
    func detectStickyHeaderViaJS() async -> StickyHeaderDetectionResult {
        do {
            let resultJSON = try await evaluateJavaScriptWithoutUserGesture(JavaScriptSnippets.detectStickyHeader) as? String
            guard let resultJSON, let data = resultJSON.data(using: .utf8) else {
                return StickyHeaderDetectionResult(hasStickyHeader: false, headerColor: nil, headerHeight: nil)
            }

            return try JSONDecoder().decode(StickyHeaderDetectionResult.self, from: data)
        } catch {
            return StickyHeaderDetectionResult(hasStickyHeader: false, headerColor: nil, headerHeight: nil)
        }
    }

    /// Quick check for sticky headers via JavaScript.
    ///
    /// More efficient than `detectStickyHeaderViaJS()` when you only need a boolean.
    func hasStickyHeaderViaJS() async -> Bool {
        do {
            let result = try await evaluateJavaScriptWithoutUserGesture(JavaScriptSnippets.hasStickyHeader)
            return result as? Bool ?? false
        } catch {
            return false
        }
    }

    // MARK: - Settable Properties

    /// The custom user agent string.
    var customUserAgent: String? {
        get { backingWebView.customUserAgent }
        set { backingWebView.customUserAgent = newValue }
    }

    /// The media type for the webpage's content.
    var mediaType: CSSMediaType? {
        get { backingWebView.mediaType.map(CSSMediaType.init(rawValue:)) }
        set { backingWebView.mediaType = newValue?.rawValue }
    }

    /// Whether Safari Web Inspector can inspect this page.
    var isInspectable: Bool {
        get { backingWebView.isInspectable }
        set { backingWebView.isInspectable = newValue }
    }

    // MARK: - Back-Forward List

    /// The webpage's back-forward navigation list.
    var backForwardList: BackForwardList = .init()

    /// Whether there is a back item in the history.
    var canGoBack: Bool {
        !backForwardList.backList.isEmpty
    }

    /// Whether there is a forward item in the history.
    var canGoForward: Bool {
        !backForwardList.forwardList.isEmpty
    }

    /// The array of items that precede the current item.
    var backList: [BackForwardList.Item] {
        backForwardList.backList
    }

    /// The array of items that follow the current item.
    var forwardList: [BackForwardList.Item] {
        backForwardList.forwardList
    }

    // MARK: - Media Capture State (Derived)

    /// Whether the page is actively using the camera.
    var isCameraActive: Bool {
        cameraCaptureState == .active
    }

    /// Whether the camera is muted (was active but user muted it).
    var isCameraMuted: Bool {
        cameraCaptureState == .muted
    }

    /// Whether the page is actively using the microphone.
    var isMicrophoneActive: Bool {
        microphoneCaptureState == .active
    }

    /// Whether the microphone is muted (was active but user muted it).
    var isMicrophoneMuted: Bool {
        microphoneCaptureState == .muted
    }

    /// Whether the page has any active media capture (camera or microphone).
    var hasActiveMediaCapture: Bool {
        isCameraActive || isMicrophoneActive
    }

    /// Whether the page has any muted media capture.
    var hasMutedMediaCapture: Bool {
        isCameraMuted || isMicrophoneMuted
    }

    // MARK: - Media Playback State

    /// Whether the page is in fullscreen mode.
    var isInFullscreen: Bool {
        fullscreenState == .inFullscreen || fullscreenState == .enteringFullscreen
    }

    /// Whether media playback is currently suspended.
    var isMediaSuspended: Bool = false

    // MARK: - Translation State

    /// Whether a translation is currently in progress.
    var isTranslating: Bool = false

    /// Whether the page is currently showing translated content.
    var isTranslated: Bool = false

    /// The detected source language of the page content.
    var detectedLanguage: Locale.Language?

    /// The original language before translation was applied.
    var originalLanguage: Locale.Language?

    /// The language the page was translated to.
    var translatedToLanguage: Locale.Language?

    /// Resets translation state when navigation begins.
    ///
    /// Called from navigation delegate when a new navigation starts,
    /// ensuring in-progress translations are cancelled.
    func resetTranslationState() {
        isTranslating = false
        isTranslated = false
        detectedLanguage = nil
        originalLanguage = nil
        translatedToLanguage = nil
    }

    // MARK: - Deep Link State

    /// Observable state holder for deep link display.
    @ObservationIgnored
    var deepLinkFlag: DeepLinkFlag = .init()

    /// Whether the session is currently displaying a deep link (internal browser view).
    var isShowingDeepLink: Bool {
        deepLinkFlag.isShowingDeepLink
    }

    /// The URL of the deep link being displayed, or `nil` if not showing a deep link.
    var deepLinkURL: URL? {
        deepLinkFlag.deepLinkURL
    }

    // MARK: - HTTP Error State

    /// The HTTP status code of an error for the current page, if any.
    ///
    /// When set alongside `httpErrorURL`, the view layer shows an error page
    /// instead of web content.
    var httpErrorCode: Int?

    /// The URL that failed to load, causing an error page to be displayed.
    ///
    /// Stored directly when `loadAlternateHTMLForError` is called, ensuring
    /// the error page can display immediately without waiting for WebKit's
    /// internal `_unreachableURL` property to be set asynchronously.
    var httpErrorURL: URL?

    // MARK: - Crash Error State

    /// Information about a crash that exceeded auto-recovery threshold.
    ///
    /// When set, the view layer shows a crash error page instead of web content.
    /// Cleared when the user manually triggers a reload via ``startNewNavigation()``.
    var crashError: CrashError?


    // MARK: - Security State

    /// Cached certificate info to avoid repeated certificate chain parsing.
    ///
    /// The cache is keyed by the SecTrust object reference - when serverTrust changes
    /// (e.g., after navigation), the cache automatically becomes invalid.
    ///
    /// Not marked `@ObservationIgnored` so views are notified when async evaluation completes.
    private var cachedCertificateInfo: (trust: SecTrust, info: CertificateInfo)?

    /// Tracks in-flight certificate evaluation to prevent duplicate async work.
    @ObservationIgnored
    private var pendingTrustEvaluation: SecTrust?

    /// Information about the current page's SSL certificate.
    ///
    /// Returns `.insecure` if:
    /// - No server trust is available
    /// - The URL is not HTTPS
    /// - Certificate evaluation is in progress
    ///
    /// Performance: Certificate evaluation runs off the main thread to avoid
    /// blocking UI. Results are cached per SecTrust object.
    var certificateInfo: CertificateInfo {
        // Read both values directly from backingWebView to ensure consistency
        let trust = backingWebView.serverTrust
        let webViewURL = backingWebView.url

        guard let trust,
              let webViewURL,
              webViewURL.scheme?.lowercased() == "https"
        else {
            return .insecure
        }

        // Return cached result if trust object hasn't changed
        if let cached = cachedCertificateInfo, cached.trust === trust {
            return cached.info
        }

        // Already evaluating this trust object - return placeholder
        if pendingTrustEvaluation === trust {
            return .insecure
        }

        // Start async evaluation off the main thread.
        // SecTrust is thread-safe but not marked Sendable, so wrap in unchecked sendable.
        pendingTrustEvaluation = trust
        let host = webViewURL.host
        let sendableTrust = UncheckedSendable(trust)
        Task.detached { [weak self] in
            let info = CertificateEvaluator.evaluate(sendableTrust.value, for: host)
            let trustValue = sendableTrust.value
            await MainActor.run { [weak self] in
                guard let self else { return }
                pendingTrustEvaluation = nil
                // Only cache if trust object hasn't changed during evaluation
                if backingWebView.serverTrust === trustValue {
                    cachedCertificateInfo = (trustValue, info)
                }
            }
        }

        return .insecure
    }

    /// Whether the current page has a secure (HTTPS) connection with a valid certificate.
    var isSecure: Bool {
        certificateInfo.isSecure
    }

    /// The overall security state of the page.
    var securityState: SecurityState {
        guard let url else {
            return .insecure
        }

        if url.isLocalNetworkAddress {
            return .localNetwork
        }

        if url.scheme?.lowercased() == "http" {
            return .insecure
        }

        let cert = certificateInfo
        switch cert.trustState {
        case .valid:
            return hasOnlySecureContent ? .secure : .mixedContent
        case .invalid, .unknown:
            return .insecure
        }
    }

    // MARK: - Web Process State

    /// Observer for web process state with `@Observable` KVO integration.
    var processStateObserver: ProcessStateObserver?

    // MARK: - In-Window Fullscreen

    /// Routes element fullscreen into the tab instead of a macOS Space.
    ///
    /// Created at web view creation when the in-window fullscreen setting is
    /// enabled; must live as long as the web view (its pointer is registered
    /// as the page's fullscreen client info).
    private(set) var inWindowFullscreenController: InWindowFullscreenController?

    /// The current state of the web process backing this session.
    var webProcessState: _WKWebProcessState {
        processStateObserver?.processState ?? backingWebView._webProcessState
    }

    /// Whether the web process is currently running.
    var isWebProcessRunning: Bool {
        processStateObserver?.isAlive ?? (backingWebView._webProcessState != .notRunning)
    }

    /// Whether the tab content needs to be reloaded to display.
    var needsReload: Bool {
        processStateObserver?.needsReload ?? false
    }

    /// Whether the web process is currently unresponsive (frozen/hung).
    var isUnresponsive: Bool {
        processStateObserver?.isUnresponsive ?? false
    }

    /// Whether the tab recently crashed and was automatically recovered.
    var recentlyCrashed: Bool {
        processStateObserver?.recentlyCrashed ?? false
    }

    // MARK: - Audio Playback State (Private API)

    /// Whether audio is currently playing.
    ///
    /// Observed via KVO on the private `_isPlayingAudio` property.
    var isPlayingAudio: Bool {
        backingProperty(\.isPlayingAudio, backedBy: \.isPlayingAudio)
    }

    /// Whether the tab's audio is muted.
    ///
    /// Observed via KVO on the private `_mediaMutedState` property.
    /// Note: After calling `setAudioMuted(_:)`, call `refreshAudioMuteState()`
    /// since `_setPageMuted:` doesn't trigger KVO notifications.
    var isAudioMuted: Bool {
        access(keyPath: \.isAudioMuted)
        return _isAudioMuted
    }

    @ObservationIgnored
    private var _isAudioMuted: Bool = false

    /// Cached playback state from `requestMediaPlaybackState()`.
    ///
    /// Updated via `refreshPlaybackState()`. Used by `isMediaPlaying` to determine
    /// if media is actually playing (even when muted from webpage's own controls).
    var cachedPlaybackState: WKMediaPlaybackState {
        access(keyPath: \.cachedPlaybackState)
        return _cachedPlaybackState
    }

    @ObservationIgnored
    private var _cachedPlaybackState: WKMediaPlaybackState = .none

    /// Updates the cached playback state with observation notification.
    func updateCachedPlaybackState(_ state: WKMediaPlaybackState) {
        guard _cachedPlaybackState != state else { return }
        withMutation(keyPath: \.cachedPlaybackState) {
            _cachedPlaybackState = state
        }
    }

    /// Current audio state combining playback and mute status.
    var audioState: WKWebView.AudioState {
        guard isPlayingAudio else { return .idle }
        return isAudioMuted ? .muted : .playing
    }

    /// Manually refreshes the mute state after programmatic changes.
    ///
    /// Call this after `setAudioMuted(_:)` or `toggleAudioMute()` since
    /// `_setPageMuted:` doesn't trigger KVO notifications.
    func refreshAudioMuteState() {
        let newValue = backingWebView.isAudioMuted
        if _isAudioMuted != newValue {
            withMutation(keyPath: \.isAudioMuted) {
                _isAudioMuted = newValue
            }
        }
    }

    // MARK: - Media Controls Panel State

    /// Per-tab volume multiplier (0.0–1.0). Runtime only, not persisted.
    ///
    /// Applied via JavaScript to HTMLMediaElement.volume or WebKit SPI fallback.
    /// When the page is evicted from the pool or the app restarts, this resets to 1.0.
    var volume: Double = 1.0

    /// Last time media was actively playing on this page.
    ///
    /// Used by ``MediaControlsManager`` to keep recently-active tabs visible
    /// in the panel for quick resume (5-minute timeout).
    var lastMediaActivity: Date?

    /// Whether the user manually marked this tab as a call.
    ///
    /// Overrides automatic domain-based call detection. Useful for unrecognized
    /// video conferencing services or web apps with WebRTC.
    var userMarkedAsCall: Bool = false

    /// Cached Media Session metadata from the page.
    ///
    /// Contains title, artist, album, and artwork URL from the Media Session API.
    /// Fetched on-demand and cached. Call `refreshMediaSessionMetadata()` to update.
    var mediaSessionMetadata: MediaSessionMetadata?

    // MARK: - Form Data State

    /// Cached form data state (updated via `checkFormDataState()`).
    var hasUnsavedFormData: Bool = false

    // MARK: - Content Blocker Bypass

    @ObservationIgnored
    var lastContentBlockerBypassHost: String?

    // MARK: - Zoom Control

    /// Current zoom level (percentage, e.g., 100 = 100%).
    var currentZoom: Int = 100

    // MARK: - Scroll Position

    /// Current vertical scroll offset of the page.
    ///
    /// Updated by the UI delegate when scroll geometry changes. Used for
    /// features like edge color sampling that need to respond to scroll events.
    var scrollOffsetY: CGFloat = 0

    // MARK: - Multi-Window Ownership

    /// The identifier of the window that currently owns the interactive WebView.
    ///
    /// When multiple windows display the same page, only the owner window gets
    /// the real interactive WebView. Other windows receive a read-only portal mirror
    /// via `CAPortalLayer`. Ownership is claimed when a window becomes key while
    /// displaying this page.
    ///
    /// - Note: Use `claimOwnership(for:)` and `isOwner(_:)` to manage ownership.
    var ownerWindowID: ObjectIdentifier?

    // MARK: - Reflected Windows

    /// Active reflected windows displaying this page's content.
    ///
    /// Reflected windows use the owner/portal mechanism for displaying web content.
    /// When a reflected window becomes key, it claims ownership of the interactive
    /// WebView, and other windows automatically switch to portal mode.
    @ObservationIgnored
    var _reflectedWindows: [ReflectedViewController] = []

    /// Tracked count of reflected windows for SwiftUI observation.
    /// This is separate from `_reflectedWindows` to allow observation of changes.
    var reflectedWindowCount: Int = 0

    /// Whether any reflected windows are currently active.
    var hasReflectedWindows: Bool {
        reflectedWindowCount > 0
    }

    // MARK: - Web Inspector

    /// Reference to the Web Inspector manager for developer tools.
    weak var webInspectorManager: WebInspectorManager?

    // MARK: - Link Hover Callback

    /// Callback invoked when the mouse moves over a link element.
    ///
    /// Set by ``WebViewContainer`` to update the local hover state for displaying
    /// a link URL preview overlay. Called with `nil` when the mouse moves off a link.
    @ObservationIgnored
    var onHoveredLinkChanged: ((URL?) -> Void)?

    // MARK: - KVO Observation Storage

    /// Lazy KVO observations created on first property access.
    ///
    /// Uses the WebKit pattern: observations are created when properties are first
    /// accessed, not eagerly at init. The `~Copyable` struct ensures single ownership
    /// and automatic invalidation on deinit.
    @ObservationIgnored
    private var observations = KeyValueObservations()

    // MARK: - Navigation Tracking

    @ObservationIgnored
    var redirectChain = RedirectChain()

    @ObservationIgnored
    var scopedNavigations: [ObjectIdentifier: AsyncThrowingStream<NavigationEvent, any Error>.Continuation] = [:]

    @ObservationIgnored
    var scopedStreams: [ObjectIdentifier: AsyncThrowingStream<NavigationEvent, any Error>] = [:]

    @ObservationIgnored
    var indefiniteNavigations: [UUID: AsyncThrowingStream<NavigationEvent, any Error>.Continuation] = [:]

    /// Cached navigation stream for the primary consumer (navigationObservationTask).
    ///
    /// This prevents stream accumulation when `navigations` is accessed multiple times.
    /// The stream is created lazily on first access and reused thereafter.
    @ObservationIgnored
    private var _cachedNavigationStream: AsyncThrowingStream<NavigationEvent, any Error>?

    /// UUID of the cached navigation stream for cleanup tracking.
    @ObservationIgnored
    private var _cachedNavigationStreamID: UUID?

    /// A sequence of all navigation events throughout the webpage's lifetime.
    ///
    /// - Important: This property returns a cached stream. Multiple accesses return
    ///   the same stream instance. For additional independent consumers, use
    ///   ``createIndefiniteNavigationSequence()`` directly.
    var navigations: AsyncThrowingStream<NavigationEvent, any Error> {
        if let cached = _cachedNavigationStream {
            return cached
        }
        let stream = createIndefiniteNavigationSequence()
        _cachedNavigationStream = stream
        return stream
    }

    // MARK: - Task Management

    @ObservationIgnored
    var loadTask: Task<Void, Never>?

    @ObservationIgnored
    var navigationObservationTask: Task<Void, Never>?

    @ObservationIgnored
    var faviconTask: Task<Void, Never>?

    @ObservationIgnored
    var historyDebounceTask: Task<Void, Never>?

    // MARK: - Navigation Generation

    /// Whether the initial load from init is still pending.
    ///
    /// Set to `true` when WebPage is created with a URL to load. Cleared once
    /// `load()` is actually called. Used by `ensureInitialLoadStarted()` to
    /// recover if the deferred init load was dropped (e.g. WebView not yet
    /// in a window when the async dispatch fired).
    @ObservationIgnored
    var initialLoadPending = false

    /// Generation counter for navigation operations.
    ///
    /// Incremented on each new navigation to detect stale events from cancelled loads.
    /// When a load is cancelled and a new one starts, events from the old navigation
    /// (which may still arrive due to cooperative cancellation) are ignored by comparing
    /// the captured generation against the current value.
    @ObservationIgnored
    var navigationGeneration: UInt64 = 0

    // MARK: - History Tracking State

    @ObservationIgnored
    var currentHistoryEntry: HistoryEntry?

    @ObservationIgnored
    var parentHistoryEntry: HistoryEntry?

    @ObservationIgnored
    var visibilityStartTime: Date?

    @ObservationIgnored
    var lastCommittedURL: URL?

    @ObservationIgnored
    var pendingHistoryURL: URL?

    @ObservationIgnored
    var isBackForwardNavigation: Bool = false

    // MARK: - Scroll Position Restoration

    /// Whether to restore scroll position on the next navigation finish.
    ///
    /// Set to `true` during initialization when `tabPage.scrollPositionY` has a saved value.
    /// After restoration (or when the user navigates to a new URL), this is set to `false`
    /// to prevent restoring stale scroll positions.
    @ObservationIgnored
    var shouldRestoreScrollPosition: Bool = false

    // MARK: - Constants

    static let historyDebounceInterval: Duration = .milliseconds(800)
    static let faviconLoadDelay: Duration = .milliseconds(200)

    // MARK: - Initialization

    /// Creates a new WebPage and immediately begins loading content.
    ///
    /// - Warning: This initializer starts loading web resources immediately.
    ///   Only create a `WebPage` when you intend to display or preload the content.
    ///
    /// - Parameters:
    ///   - tabPage: The persisted tab page model to manage.
    ///   - configuration: WebKit configuration for the page. Pass `nil` for defaults.
    ///   - webViewConfiguration: A preconfigured WKWebViewConfiguration supplied by WebKit for popups.
    ///   - dependencies: All external manager and service dependencies.
    init(
        tabPage: TabPage,
        configuration: Configuration?,
        webViewConfiguration: WKWebViewConfiguration? = nil,
        expectedFrame: CGRect = CGRect(x: 0, y: 0, width: 1_024, height: 768),
        dependencies: Dependencies,
    ) {
        self.tabPage = tabPage
        self.historyManager = dependencies.historyManager
        self.autoFillManager = dependencies.autoFillManager
        self.faviconCache = dependencies.faviconCache
        self.providedWebViewConfiguration = webViewConfiguration

        // Create the deep link flag first so we can capture it in the handler
        let flag = DeepLinkFlag()
        self.deepLinkFlag = flag

        // Create configuration with refrax:// scheme handler
        var config = configuration ?? Configuration()
        if let scheme = URLScheme(DeepLink.scheme) {
            let handler = RefraxSchemeHandler { [flag] url in
                // All deep links render in-tab via DeepLinkView
                flag.deepLinkURL = url
            }
            config.urlSchemeHandlers[scheme] = handler

            if let webViewConfiguration {
                // Check if scheme is already registered (happens for popup configurations
                // which are cloned from the opener's configuration)
                if webViewConfiguration.urlSchemeHandler(forURLScheme: scheme.rawValue) == nil {
                    let adapter = URLSchemeHandlerAdapter(handler)
                    webViewConfiguration.setURLSchemeHandler(adapter, forURLScheme: scheme.rawValue)
                }
            }
        }
        self.configuration = config

        // Initialize all stored dependencies before using self
        self.settingsApplier = dependencies.settingsApplier
        self.domainTimeTracker = dependencies.domainTimeTracker

        self.backingNavigationDelegate = WKNavigationDelegateAdapter(navigationDecider: dependencies.navigationDecider)
        self.backingUIDelegate = WKUIDelegateAdapter(dialogPresenter: dependencies.dialogPresenter)
        self.iconLoadingDelegateAdapter = IconLoadingDelegateAdapter()

        // Create the backing WKWebView with the expected frame size.
        // Using the expected frame avoids a reflow when the webView is first
        // added to the adapter — content renders at approximately the right size
        // immediately instead of starting at an arbitrary 1024x768 default.
        let webViewConfig: WKWebViewConfiguration
        if let provided = webViewConfiguration {
            config.applyTo(provided)
            webViewConfig = provided
        } else {
            webViewConfig = config.makeWKWebViewConfiguration()
        }
        self.backingWebView = WebPageWebView(frame: expectedFrame, configuration: webViewConfig)
        backingWebView.navigationDelegate = backingNavigationDelegate
        backingWebView.uiDelegate = backingUIDelegate

        // Contain element fullscreen inside the tab (no macOS fullscreen Space)
        if config.inWindowFullscreenEnabled {
            self.inWindowFullscreenController = InWindowFullscreenController(webView: backingWebView)
        }

        // Set owner references (requires self to be fully initialized)
        backingNavigationDelegate.owner = self
        backingUIDelegate.owner = self
        iconLoadingDelegateAdapter.owner = self

        // Wire up remaining dependencies (weak/delegate references)
        self.siteSettingsCoordinator = dependencies.siteSettingsCoordinator
        self.webInspectorManager = dependencies.webInspectorManager
        backingNavigationDelegate.downloadManager = dependencies.downloadManager
        backingNavigationDelegate.pagePool = dependencies.pagePool
        backingUIDelegate.pagePool = dependencies.pagePool

        // Set Safari-compatible user agent for OAuth and site compatibility
        self.customUserAgent = UserAgentProvider.safari

        // Initialize audio mute state (not KVO-observable after _setPageMuted:)
        self._isAudioMuted = backingWebView.isAudioMuted

        // Start process state observation for crash detection
        self.processStateObserver = ProcessStateObserver(wkWebView: backingWebView)

        // Set up throttled progress observation (1% threshold to reduce notification overhead)
        setupThrottledProgressObservation()

        // Attach autofill manager
        dependencies.autoFillManager.attach(to: backingWebView, url: tabPage.url)

        // Attach history delegate for title change notifications
        let historyAdapter = HistoryDelegateAdapter(historyManager: dependencies.historyManager)
        historyAdapter.attach(to: backingWebView, tabID: tabPage.id)
        // Sync JavaScript title changes to TabPage model and check for badge patterns
        historyAdapter.onTitleChange = { [weak self] title in
            guard let self else { return }
            self.tabPage.title = title

            // Check for notification badge patterns (e.g., "(3) Gmail")
            if let tab = self.tabPage.tab, let url {
                siteSettingsCoordinator?.checkBadgeAndMarkUnread(
                    title: title,
                    tab: tab,
                    url: url,
                    isPageVisible: visibilityStartTime != nil,
                )
            }
        }
        // Sync client-side URL changes (History API) to TabPage model and record history.
        // SPAs like Twitter, GitHub, and YouTube use history.pushState() instead of
        // real navigation — treat these as navigations for history tracking.
        historyAdapter.onURLChange = { [weak self] newURL in
            guard let self else { return }
            // Skip replaceState calls that don't actually change the URL
            guard newURL != self.tabPage.url else { return }
            self.tabPage.url = newURL
            self.lastCommittedURL = newURL
            handleURLChangeForHistory(to: newURL)
        }
        self.historyDelegateAdapter = historyAdapter

        // Attach native favicon loader
        iconLoadingDelegateAdapter.attach(to: backingWebView)

        startNavigationObservation()

        // For popups, WebKit handles the navigation - we just return the webView
        // and WebKit will load the content. Calling load() ourselves would interfere.
        if webViewConfiguration == nil {
            // Check if we should restore scroll position after initial load
            self.shouldRestoreScrollPosition = tabPage.scrollPositionY != nil
            // Mark that we need to perform the initial load.
            // The load is deferred to avoid blocking SwiftUI view body evaluation
            // (WKWebView.load takes ~170ms synchronously).
            self.initialLoadPending = true
            DispatchQueue.main.async { [weak self] in
                self?.performInitialLoadIfNeeded()
            }
        }
    }

    deinit {
        loadTask?.cancel()
        navigationObservationTask?.cancel()
        faviconTask?.cancel()
        historyDebounceTask?.cancel()

        // Clean up navigation streams to prevent memory leaks
        for continuation in scopedNavigations.values {
            continuation.finish()
        }
        scopedNavigations.removeAll()
        scopedStreams.removeAll()

        for continuation in indefiniteNavigations.values {
            continuation.finish()
        }
        indefiniteNavigations.removeAll()
    }

    // MARK: - KVO-to-Observation Bridge

    /// Creates a KVO observation that notifies the Observation framework.
    ///
    /// Uses the `.prior` option to call `willSet` before the change and `didSet` after,
    /// matching Swift's property observer semantics.
    private func createObservation(
        for keyPath: KeyPath<WebPage, some Any>,
        backedBy backingKeyPath: KeyPath<WebPageWebView, some Any>,
    ) -> NSKeyValueObservation {
        // Wrap key path in Sendable box for thread-safe capture in KVO closure
        let boxed = UncheckedSendableKeyPathBox(keyPath: keyPath)

        return backingWebView.observe(backingKeyPath, options: [.prior, .old, .new]) { [_$observationRegistrar, unowned self] _, change in
            if change.isPrior {
                _$observationRegistrar.willSet(self, keyPath: boxed.keyPath)
            } else {
                _$observationRegistrar.didSet(self, keyPath: boxed.keyPath)
            }
        }
    }

    /// Returns a property value backed by a WKWebView property with KVO observation.
    ///
    /// Observations are created lazily on first access. The value is read directly
    /// from `backingWebView` on each access (no caching).
    private func backingProperty<Value, BackingValue>(
        _ keyPath: KeyPath<WebPage, Value>,
        backedBy backingKeyPath: KeyPath<WebPageWebView, BackingValue>,
        _ transform: (BackingValue) -> Value,
    ) -> Value {
        // Lazily create KVO observation on first access
        if observations.contents[keyPath] == nil {
            observations.contents[keyPath] = createObservation(for: keyPath, backedBy: backingKeyPath)
        }

        // Notify Observation framework that this property is being accessed
        access(keyPath: keyPath)

        // Return the value from backing store, transformed if needed
        let backingValue = backingWebView[keyPath: backingKeyPath]
        return transform(backingValue)
    }

    /// Convenience overload for properties with matching types.
    private func backingProperty<Value>(
        _ keyPath: KeyPath<WebPage, Value>,
        backedBy backingKeyPath: KeyPath<WebPageWebView, Value>,
    ) -> Value {
        backingProperty(keyPath, backedBy: backingKeyPath) { $0 }
    }

    /// Sets up throttled KVO observation for estimatedProgress.
    ///
    /// Unlike other KVO-backed properties that use `backingProperty`, this observation
    /// includes a threshold check to only notify observers when progress changes by
    /// at least 1% (0.01). This reduces 50-100 KVO events during page load to ~100
    /// meaningful updates, significantly reducing @Observable notification overhead.
    private func setupThrottledProgressObservation() {
        // Wrap key path in Sendable box for thread-safe capture in KVO closure
        let boxedKeyPath = UncheckedSendableKeyPathBox(keyPath: \WebPage.estimatedProgress)

        observations.contents[\WebPage.estimatedProgress] = backingWebView.observe(
            \.estimatedProgress,
            options: [.new],
        ) { [_$observationRegistrar, unowned self] _, change in
            guard let newProgress = change.newValue else { return }

            // KVO callbacks for WKWebView run on main thread
            MainActor.assumeIsolated {
                // Always update when progress reaches 1.0 (complete)
                // Otherwise, only update if progress changed by at least 1%
                let threshold = 0.01
                guard newProgress >= 1.0 || abs(_estimatedProgress - newProgress) >= threshold else {
                    return
                }

                _$observationRegistrar.willSet(self, keyPath: boxedKeyPath.keyPath)
                _estimatedProgress = newProgress
                _$observationRegistrar.didSet(self, keyPath: boxedKeyPath.keyPath)
            }
        }
    }
}

// MARK: - KVO Observation Storage

extension WebPage {
    /// Storage for lazy KVO observations, keyed by WebPage property key path.
    ///
    /// Non-copyable to ensure single ownership. Observations are automatically
    /// invalidated when this struct is deallocated.
    struct KeyValueObservations: ~Copyable {
        var contents: [PartialKeyPath<WebPage>: NSKeyValueObservation] = [:]

        deinit {
            for (_, observation) in contents {
                observation.invalidate()
            }
        }
    }
}

// MARK: - Sendable KeyPath Box

/// Thread-safe wrapper for key paths used in KVO closures.
///
/// Key paths are not Sendable by default in Swift 6, but this wrapper marks them
/// as safe with `@unchecked Sendable`. This is valid because key paths are immutable
/// value types used only for tracking, not mutable access.
/// Wraps a non-Sendable value for transfer across isolation boundaries.
///
/// Use when you know the value is actually safe to send (e.g., immutable Core Foundation types
/// like SecTrust) but Swift's type system doesn't recognize it as Sendable.
private nonisolated struct UncheckedSendable<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) {
        self.value = value
    }
}

private nonisolated struct UncheckedSendableKeyPathBox<Root, Value>: @unchecked Sendable {
    let keyPath: KeyPath<Root, Value>
}
