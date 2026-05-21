import Foundation

/// Describes a single toggleable feature flag.
///
/// Each definition specifies the flag's key (matching the WebKit `_WKFeature` key
/// or an app-level identifier), display metadata, and default state.
/// User overrides are stored in ``BrowserSettings/featureFlagOverridesJSON``.
struct FeatureFlagDefinition: Identifiable, Sendable {
    /// Unique key matching the WebKit feature key or app-level identifier.
    let key: String

    /// Human-readable name shown in settings.
    let name: String

    /// Brief description of what the flag controls.
    let description: String

    /// Grouping category for the settings UI.
    let category: Category

    /// Whether the flag is enabled when no user override exists.
    let defaultValue: Bool

    var id: String { key }

    /// Feature flag categories for the settings UI.
    enum Category: String, CaseIterable, Sendable {
        case webPlatform = "Web Platform"
        case privacy = "Privacy"
        case media = "Media"
        case security = "Security"
        case browser = "Browser"
    }
}

// MARK: - Registry

extension FeatureFlagDefinition {
    /// All known feature flags, grouped by category.
    ///
    /// WebKit flags use their `_WKFeature` key verbatim so ``enableFeatures(on:)``
    /// can look up overrides directly. App-level flags use `app.` prefixed keys.
    static let all: [FeatureFlagDefinition] = webPlatform + privacy + media + security + browser

    // MARK: Web Platform

    static let webPlatform: [FeatureFlagDefinition] = [
        FeatureFlagDefinition(
            key: "RequestIdleCallbackEnabled",
            name: "Request Idle Callback",
            description: "Run background tasks during browser idle periods.",
            category: .webPlatform,
            defaultValue: true
        ),
        FeatureFlagDefinition(
            key: "CloseWatcherEnabled",
            name: "Close Watcher",
            description: "Let web apps intercept close gestures (Escape key, back navigation) for dialogs and popovers.",
            category: .webPlatform,
            defaultValue: true
        ),
        FeatureFlagDefinition(
            key: "ObservableEnabled",
            name: "Observable",
            description: "TC39 Observable API for reactive event streams.",
            category: .webPlatform,
            defaultValue: true
        ),
        FeatureFlagDefinition(
            key: "WebTransportEnabled",
            name: "WebTransport",
            description: "Low-latency client-server communication over HTTP/3.",
            category: .webPlatform,
            defaultValue: true
        ),
        FeatureFlagDefinition(
            key: "CSSScrollAnchoringEnabled",
            name: "CSS Scroll Anchoring",
            description: "Prevent content jumps when elements load above the viewport.",
            category: .webPlatform,
            defaultValue: true
        ),
        FeatureFlagDefinition(
            key: "LinkPrefetchEnabled",
            name: "Link Prefetch",
            description: "Preload resources hinted by <link rel=\"prefetch\"> for faster navigation.",
            category: .webPlatform,
            defaultValue: true
        ),
        FeatureFlagDefinition(
            key: "SpeculationRulesPrefetchEnabled",
            name: "Speculation Rules",
            description: "Preload pages based on Speculation Rules for near-instant navigation.",
            category: .webPlatform,
            defaultValue: true
        ),
        FeatureFlagDefinition(
            key: "ShapeDetection",
            name: "Shape Detection",
            description: "Detect barcodes, faces, and text in images using native APIs.",
            category: .webPlatform,
            defaultValue: true
        ),
    ]

    // MARK: Privacy

    static let privacy: [FeatureFlagDefinition] = [
        FeatureFlagDefinition(
            key: "HTTPSByDefaultEnabled",
            name: "HTTPS by Default",
            description: "Automatically upgrade navigations to HTTPS when available.",
            category: .privacy,
            defaultValue: true
        ),
        FeatureFlagDefinition(
            key: "LinkSanitizerEnabled",
            name: "Link Sanitizer",
            description: "Strip known tracking parameters from URLs at the WebKit level.",
            category: .privacy,
            defaultValue: true
        ),
        FeatureFlagDefinition(
            key: "FilterLinkDecorationByDefaultEnabled",
            name: "Filter Link Decoration",
            description: "Remove tracking decorations appended to links by ad networks.",
            category: .privacy,
            defaultValue: true
        ),
    ]

    // MARK: Media

    static let media: [FeatureFlagDefinition] = [
        FeatureFlagDefinition(
            key: "WebCodecsAV1Enabled",
            name: "WebCodecs AV1",
            description: "Hardware-accelerated AV1 video decoding via the WebCodecs API.",
            category: .media,
            defaultValue: true
        ),
        FeatureFlagDefinition(
            key: "WebRTCAV1CodecEnabled",
            name: "WebRTC AV1",
            description: "AV1 codec support for WebRTC video calls.",
            category: .media,
            defaultValue: true
        ),
    ]

    // MARK: Security

    static let security: [FeatureFlagDefinition] = [
        FeatureFlagDefinition(
            key: "app.disableCORS",
            name: "Disable CORS",
            description: "Skip cross-origin resource sharing checks. Allows any page to fetch resources from any origin without preflight.",
            category: .security,
            defaultValue: false
        ),
    ]

    // MARK: Browser

    static let browser: [FeatureFlagDefinition] = [
        FeatureFlagDefinition(
            key: "app.realPopupWebViews",
            name: "Real Popup Web Views",
            description: "Use real WKWebView instances for popups to preserve window.opener semantics. Disabling returns nil for window.open() calls.",
            category: .browser,
            defaultValue: true
        ),
        FeatureFlagDefinition(
            key: "app.processAudioTap",
            name: "Audio Tap During Screen Sharing",
            description: "Capture WebKit audio and re-route it through the app process so screen sharing tools can include browser audio.",
            category: .browser,
            defaultValue: false
        ),
        FeatureFlagDefinition(
            key: "app.widgetsEnabled",
            name: "Widget Data Sharing",
            description: "Share tab and space data with widgets via App Group container. May trigger a privacy prompt on first use.",
            category: .browser,
            defaultValue: false
        ),
    ]

    /// Looks up a definition by key, or nil if not registered.
    static func definition(for key: String) -> FeatureFlagDefinition? {
        all.first { $0.key == key }
    }

    /// All definitions for a given category.
    static func definitions(for category: Category) -> [FeatureFlagDefinition] {
        all.filter { $0.category == category }
    }
}
