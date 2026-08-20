import Foundation
import WebKit

extension WebPage {
    /// Configuration for creating a `WebPage` instance.
    ///
    /// This structure mirrors WebKit's `WebPage.Configuration` API while providing
    /// Refrax-specific customization options.
    struct Configuration {
        // MARK: - Storage

        /// The website data store for cookies and cached data.
        var websiteDataStore: WKWebsiteDataStore = .default()

        /// The user content controller for scripts and message handlers.
        var userContentController: WKUserContentController = .init()

        /// The web extension controller.
        var webExtensionController: WKWebExtensionController?

        // MARK: - Navigation Preferences

        /// Default preferences for new navigations.
        var defaultNavigationPreferences: NavigationPreferences = .init()

        // MARK: - URL Scheme Handlers

        /// Custom URL scheme handlers.
        ///
        /// Register handlers for custom URL schemes (e.g., `refrax://`).
        ///
        /// ## Example
        ///
        /// ```swift
        /// var config = WebPage.Configuration()
        /// if let scheme = URLScheme("refrax") {
        ///     config.urlSchemeHandlers[scheme] = MySchemeHandler()
        /// }
        /// ```
        var urlSchemeHandlers: [URLScheme: any URLSchemeHandler] = [:]

        // MARK: - Device Sensor Authorization

        /// Specifies how web resources may access device sensors.
        ///
        /// The default implementation returns `WKPermissionDecision.prompt` for all requests.
        var deviceSensorAuthorization: WebPage.DeviceSensorAuthorization = .init(decision: .prompt)

        // MARK: - Content Settings

        /// The app name that appears in the user agent string.
        var applicationNameForUserAgent: String?

        /// Whether to limit navigation to app-bound domains.
        var limitsNavigationsToAppBoundDomains: Bool = false

        /// Whether to automatically upgrade HTTP to HTTPS for known hosts.
        var upgradeKnownHostsToHTTPS: Bool = true

        /// Whether to suppress incremental rendering.
        var suppressesIncrementalRendering: Bool = false

        /// Whether to allow AirPlay for media.
        var allowsAirPlayForMediaPlayback: Bool = true

        /// Media types that require user interaction before playback.
        ///
        /// Uses WebKit's built-in autoplay gate rather than JS shims.
        /// Default is `.audio` to allow muted autoplay while blocking sound.
        var mediaTypesRequiringUserActionForPlayback: WKAudiovisualMediaTypes = .audio

        /// Whether to allow inline text predictions.
        ///
        /// When enabled, the system may show predictive text suggestions inline
        /// in text fields and content-editable areas.
        ///
        /// Disabled due to a WebKit bug where text completions can be inserted
        /// at the wrong position (e.g., beginning of field instead of cursor)
        /// in contentEditable elements like Discord's chat input.
        var allowsInlinePredictions: Bool = false

        // MARK: - macOS Specific

        /// The directionality of user interface elements.
        var userInterfaceDirectionPolicy: WKUserInterfaceDirectionPolicy = .content

        // MARK: - WebKit Feature Flags

        /// Whether to enable in-window fullscreen for videos.
        var inWindowFullscreenEnabled: Bool = false

        /// Whether to disable cross-origin resource sharing checks.
        var disableCORS: Bool = false

        /// User overrides for WebKit and app feature flags.
        ///
        /// Keys are `_WKFeature` keys or `app.*` identifiers.
        /// Values override the hardcoded defaults in ``enableFeatures(on:)``.
        var featureFlagOverrides: [String: Bool] = [:]

        // MARK: - Initialization

        /// Creates a new configuration with default values.
        init() {}

        // MARK: - WKWebViewConfiguration Conversion

        /// Creates a `WKWebViewConfiguration` from this configuration.
        func makeWKWebViewConfiguration() -> WKWebViewConfiguration {
            let config = WKWebViewConfiguration()

            config.websiteDataStore = websiteDataStore
            config.userContentController = userContentController

            if let webExtensionController {
                config.webExtensionController = webExtensionController
            }

            // Apply default preferences
            config.defaultWebpagePreferences = defaultNavigationPreferences.makeWKWebpagePreferences()

            // Register URL scheme handlers
            for (scheme, handler) in urlSchemeHandlers {
                let adapter = URLSchemeHandlerAdapter(handler)
                config.setURLSchemeHandler(adapter, forURLScheme: scheme.rawValue)
            }

            // Apply content settings
            if let appName = applicationNameForUserAgent {
                config.applicationNameForUserAgent = appName
            }

            config.limitsNavigationsToAppBoundDomains = limitsNavigationsToAppBoundDomains
            config.upgradeKnownHostsToHTTPS = upgradeKnownHostsToHTTPS
            config.suppressesIncrementalRendering = suppressesIncrementalRendering
            config.allowsAirPlayForMediaPlayback = allowsAirPlayForMediaPlayback
            config.mediaTypesRequiringUserActionForPlayback = mediaTypesRequiringUserActionForPlayback

            // macOS specific
            config.userInterfaceDirectionPolicy = userInterfaceDirectionPolicy

            // Inline predictions (public API since macOS 14.0)
            config.allowsInlinePredictions = allowsInlinePredictions

            // Preferences
            config.preferences.isTextInteractionEnabled = true
            config.preferences.isElementFullscreenEnabled = true

            // PiP is opt-in for modern-API WebKit embedders on macOS (Safari opts in);
            // without this, MediaElementSession.allowsPictureInPicture() is false and
            // every PiP entry point (_togglePictureInPicture, the WebKit context-menu
            // item, _canTogglePictureInPicture) silently no-ops.
            config.preferences._allowsPictureInPictureMediaPlayback = true

            // WebKit feature flags (via _WKFeature private API)
            enableFeatures(on: config.preferences)

            // CORS bypass (private API)
            if disableCORS {
                config._crossOriginAccessControlCheckEnabled = false
            }

            // Enable page top color sampling for website window coloring.
            // Both properties must be set for sampling to work.
            // Values match Safari's configuration for consistency.
            config._sampledPageTopColorMaxDifference = 30.0
            config._sampledPageTopColorMinHeight = 5.0

            return config
        }

        /// Applies Refrax configuration to an existing WKWebViewConfiguration.
        ///
        /// Used for popup pages where WebKit provides a base configuration that must
        /// be preserved for `window.opener` semantics, but Refrax settings should
        /// still be applied.
        ///
        /// This method intentionally does NOT modify:
        /// - `websiteDataStore`: Handled separately by `WebPagePool` for space isolation
        /// - URL scheme handlers: Already registered on the provided config if needed
        /// - `processPool`: Provided by WebKit for proper cross-page communication
        ///
        /// - Parameter config: The WKWebViewConfiguration to modify in-place.
        func applyTo(_ config: WKWebViewConfiguration) {
            // Apply default navigation preferences (JavaScript policy, content mode)
            config.defaultWebpagePreferences = defaultNavigationPreferences.makeWKWebpagePreferences()

            // NOTE: We intentionally do NOT merge user scripts here.
            // For popups, WebKit clones the opener's WKWebViewConfiguration including
            // its userContentController. Since the opener uses the shared controller
            // (state.webPageConfiguration.userContentController), the popup's cloned
            // controller already has all the scripts. Adding them again would duplicate
            // every script and flood WebKit's IPC queue with AddUserScripts messages.

            // Apply web extension controller if set
            if let webExtensionController {
                config.webExtensionController = webExtensionController
            }

            // Apply content settings
            if let appName = applicationNameForUserAgent {
                config.applicationNameForUserAgent = appName
            }

            config.limitsNavigationsToAppBoundDomains = limitsNavigationsToAppBoundDomains
            config.upgradeKnownHostsToHTTPS = upgradeKnownHostsToHTTPS
            config.suppressesIncrementalRendering = suppressesIncrementalRendering
            config.allowsAirPlayForMediaPlayback = allowsAirPlayForMediaPlayback
            config.mediaTypesRequiringUserActionForPlayback = mediaTypesRequiringUserActionForPlayback

            // macOS specific
            config.userInterfaceDirectionPolicy = userInterfaceDirectionPolicy

            // Inline predictions (public API since macOS 14.0)
            config.allowsInlinePredictions = allowsInlinePredictions

            // Preferences
            config.preferences.isTextInteractionEnabled = true
            config.preferences.isElementFullscreenEnabled = true
            config.preferences._allowsPictureInPictureMediaPlayback = true

            // WebKit feature flags (via _WKFeature private API)
            enableFeatures(on: config.preferences)

            // CORS bypass (private API)
            if disableCORS {
                config._crossOriginAccessControlCheckEnabled = false
            }

            // Enable page top color sampling for website window coloring.
            // Both properties must be set for sampling to work.
            config._sampledPageTopColorMaxDifference = 30.0
            config._sampledPageTopColorMinHeight = 5.0
        }

        /// Enables WebKit features using the `_WKFeature` private API.
        ///
        /// Features are enabled by default per the hardcoded set below, then
        /// ``featureFlagOverrides`` are applied on top. User overrides can
        /// disable a default-on feature or enable a default-off one.
        ///
        /// Safer than KVC (`setValue:forKey:`) because unknown keys throw
        /// uncatchable `NSException` in Swift. Features not present in the
        /// running WebKit version are silently skipped.
        private func enableFeatures(on preferences: WKPreferences) {
            // Base set: features Refrax always enables (not user-toggleable).
            var featureStates: [String: Bool] = [
                "DeveloperExtrasEnabled": true,                 // Web Inspector
                "TextExtractionEnabled": true,                  // Agent perception
            ]

            // User-toggleable features: start with defaults from the registry,
            // then apply user overrides.
            for flag in FeatureFlagDefinition.all where !flag.key.hasPrefix("app.") {
                featureStates[flag.key] = featureFlagOverrides[flag.key] ?? flag.defaultValue
            }

            // LocalNetworkAccessEnabled — disabled, crashes web processes on macOS 26.3.
            // The feature (status: "unstable" in WebKit) adds IPAddressSpace to FetchRequest
            // IPC messages. The network process rejects these as invalid IPC, terminating the
            // web process with reason=8 (RequestedByNetworkProcess). WebKit bug, not ours.

            if inWindowFullscreenEnabled {
                featureStates["InWindowFullscreenEnabled"] = true
            }

            for feature in WKPreferences._features() {
                if let enabled = featureStates[feature.key] {
                    preferences._setEnabled(enabled, for: feature)
                }
            }
        }
    }
}

// MARK: - Navigation Preferences

extension WebPage {
    /// Preferences for navigation behavior.
    ///
    /// Mirrors WebKit's `WebPage.NavigationPreferences` API.
    struct NavigationPreferences: Sendable {
        /// Content rendering mode.
        enum ContentMode: Sendable {
            case recommended
            case mobile
            case desktop

            var wkContentMode: WKWebpagePreferences.ContentMode {
                switch self {
                case .recommended: .recommended
                case .mobile: .mobile
                case .desktop: .desktop
                }
            }
        }

        /// HTTPS upgrade policy.
        enum UpgradeToHTTPSPolicy: Sendable {
            case keepAsRequested
            case automaticFallbackToHTTP
            case userMediatedFallbackToHTTP
            case errorOnFailure

            var wkPolicy: WKWebpagePreferences.UpgradeToHTTPSPolicy {
                switch self {
                case .keepAsRequested: .keepAsRequested
                case .automaticFallbackToHTTP: .automaticFallbackToHTTP
                case .userMediatedFallbackToHTTP: .userMediatedFallbackToHTTP
                case .errorOnFailure: .errorOnFailure
                }
            }
        }

        /// The content mode for rendering.
        var preferredContentMode: ContentMode = .recommended

        /// Whether to allow JavaScript execution.
        var allowsContentJavaScript: Bool = true

        /// The HTTPS upgrade policy.
        var preferredHTTPSNavigationPolicy: UpgradeToHTTPSPolicy = .keepAsRequested

        /// Whether lockdown mode is enabled.
        var isLockdownModeEnabled: Bool = false

        /// Creates default navigation preferences.
        init() {}

        /// Creates a `WKWebpagePreferences` from this configuration.
        func makeWKWebpagePreferences() -> WKWebpagePreferences {
            let prefs = WKWebpagePreferences()
            prefs.preferredContentMode = preferredContentMode.wkContentMode
            prefs.allowsContentJavaScript = allowsContentJavaScript
            prefs.preferredHTTPSNavigationPolicy = preferredHTTPSNavigationPolicy.wkPolicy
            prefs.isLockdownModeEnabled = isLockdownModeEnabled
            return prefs
        }
    }
}

// MARK: - Device Sensor Authorization

extension WebPage {
    /// A type that describes the authorization permissions policy for device sensors.
    struct DeviceSensorAuthorization {
        /// The kind of sensor permission a web resource may request to access.
        enum Permission: Hashable, Sendable {
            /// The orientation and motion of the device.
            case deviceOrientationAndMotion

            /// A media capture device, like a microphone or camera.
            case mediaCapture(WKMediaCaptureType)
        }

        /// The decision handler for authorization requests.
        let decisionHandler: (Permission, WebPage.FrameInfo, WKSecurityOrigin) async -> WKPermissionDecision

        /// Creates a new `DeviceSensorAuthorization` using the specified policy.
        ///
        /// - Parameter decisionHandler: A closure which decides the permission decision for an authorization request,
        ///   which may be based on the kind of permission, the webpage frame information, or the security origin.
        init(
            decisionHandler: @escaping (Permission, WebPage.FrameInfo, WKSecurityOrigin) async -> WKPermissionDecision,
        ) {
            self.decisionHandler = decisionHandler
        }

        /// A convenience initializer to create a DeviceSensorAuthorization that always uses the same permission decision.
        init(decision: WKPermissionDecision) {
            self.init { _, _, _ in decision }
        }
    }
}
