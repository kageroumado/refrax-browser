import Foundation
import SwiftData
import WebKit

// TODO: Wire remaining SiteSettings to WebPage/WebView configuration:
// - useReaderWhenAvailable: Trigger Reader mode after page load
// - enableContentBlockers: Configure content rule lists per-site

/// Per-domain settings for granular site control.
///
/// Stores user preferences for individual websites, including:
/// - Content settings (zoom, Reader, content blockers, JavaScript)
/// - Media settings (auto-play policy)
/// - Window settings (pop-up policy)
/// - Permissions (camera, microphone, screen sharing, location, sensors)
///
/// ## Domain Matching
///
/// The ``domain`` field stores the registrable domain (e.g., "example.com").
/// Settings apply to all subdomains unless a more specific setting exists.
///
/// Lookup order:
/// 1. Exact match: `sub.example.com`
/// 2. Parent domain: `example.com`
///
/// ## Default Values
///
/// When no site settings exist, the browser uses global defaults from
/// ``BrowserSettings``. Most permission defaults to `.ask` (prompt user).
///
/// - Note: Currently only some settings are wired to WebView. Reader mode and
///   per-site content blocker toggling still need to be applied during navigation.
@Model
final class SiteSettings {
    #Index<SiteSettings>([\.domain])

    // MARK: - Identity

    /// Stable identifier for sync.
    @Attribute(.preserveValueOnDeletion)
    var id: UUID = UUID()

    /// Domain this settings applies to.
    ///
    /// Should be a registrable domain (e.g., "example.com") or
    /// a specific subdomain (e.g., "app.example.com").
    @Attribute(.unique)
    var domain: String

    // MARK: - Content Settings

    /// Page zoom level as percentage (50-300).
    ///
    /// Default is 100 (no zoom).
    var pageZoom: Int = 100

    /// Automatically use Reader mode when available.
    var useReaderWhenAvailable: Bool = false

    /// Enable content blockers for this site.
    ///
    /// When false, ad blocking and tracking protection are disabled.
    var enableContentBlockers: Bool = true

    /// Allow JavaScript execution on this site.
    ///
    /// Disabling JavaScript improves privacy but breaks most sites.
    var allowJavaScript: Bool = true

    /// Badge detection policy for this site.
    ///
    /// Controls whether notification counts in page titles (e.g., "(3) Gmail")
    /// automatically mark the tab as unread.
    var badgeDetectionRaw: String = BadgeDetectionMode.automatic.rawValue

    var badgeDetection: BadgeDetectionMode {
        get { BadgeDetectionMode(rawValue: badgeDetectionRaw) ?? .automatic }
        set { badgeDetectionRaw = newValue.rawValue }
    }

    // MARK: - Media Settings

    /// Auto-play policy for media on this site.
    var autoPlayPolicyRaw: String = AutoPlayPolicy.stopMediaWithSound.rawValue

    var autoPlayPolicy: AutoPlayPolicy {
        get { AutoPlayPolicy(rawValue: autoPlayPolicyRaw) ?? .stopMediaWithSound }
        set { autoPlayPolicyRaw = newValue.rawValue }
    }

    // MARK: - Window Settings

    /// Pop-up window policy for this site.
    var popUpPolicyRaw: String = PopUpPolicy.blockAndNotify.rawValue

    var popUpPolicy: PopUpPolicy {
        get { PopUpPolicy(rawValue: popUpPolicyRaw) ?? .blockAndNotify }
        set { popUpPolicyRaw = newValue.rawValue }
    }

    /// Global Privacy Control (GPC) header override for this site.
    ///
    /// When set to `.allow` or `.block`, this controls whether the `Sec-GPC`
    /// header is sent for this site. `.useAllowlist` means no per-site override.
    var gpcHeaderOverrideRaw: String = GPCHeaderOverride.useAllowlist.rawValue

    var gpcHeaderOverride: GPCHeaderOverride {
        get { GPCHeaderOverride(rawValue: gpcHeaderOverrideRaw) ?? .useAllowlist }
        set { gpcHeaderOverrideRaw = newValue.rawValue }
    }

    /// Disable automatic cookie consent dismissal for this site.
    ///
    /// When true, AutoConsentManager will skip this site even if globally enabled.
    /// Use this for sites where the consent banner needs manual handling.
    var disableAutoConsent: Bool = false

    /// Per-site override for website window coloring.
    ///
    /// Controls whether this site's theme color can tint the window background.
    /// - `.useDefault`: Follow global `enableWebsiteWindowColoring` setting
    /// - `.allow`: Always allow this site to color (overrides space coloring)
    /// - `.deny`: Never allow this site to color
    var websiteColoringPolicyRaw: String = WebsiteColoringPolicy.useDefault.rawValue

    var websiteColoringPolicy: WebsiteColoringPolicy {
        get { WebsiteColoringPolicy(rawValue: websiteColoringPolicyRaw) ?? .useDefault }
        set { websiteColoringPolicyRaw = newValue.rawValue }
    }

    // MARK: - Permissions

    /// Camera access permission.
    var cameraPermissionRaw: String = PermissionPolicy.ask.rawValue

    var cameraPermission: PermissionPolicy {
        get { PermissionPolicy(rawValue: cameraPermissionRaw) ?? .ask }
        set { cameraPermissionRaw = newValue.rawValue }
    }

    /// Microphone access permission.
    var microphonePermissionRaw: String = PermissionPolicy.ask.rawValue

    var microphonePermission: PermissionPolicy {
        get { PermissionPolicy(rawValue: microphonePermissionRaw) ?? .ask }
        set { microphonePermissionRaw = newValue.rawValue }
    }

    /// Screen sharing permission.
    var screenSharingPermissionRaw: String = PermissionPolicy.ask.rawValue

    var screenSharingPermission: PermissionPolicy {
        get { PermissionPolicy(rawValue: screenSharingPermissionRaw) ?? .ask }
        set { screenSharingPermissionRaw = newValue.rawValue }
    }

    /// Location access permission.
    var locationPermissionRaw: String = PermissionPolicy.ask.rawValue

    var locationPermission: PermissionPolicy {
        get { PermissionPolicy(rawValue: locationPermissionRaw) ?? .ask }
        set { locationPermissionRaw = newValue.rawValue }
    }

    /// Device sensor (motion/orientation) permission.
    var deviceSensorPermissionRaw: String = PermissionPolicy.ask.rawValue

    var deviceSensorPermission: PermissionPolicy {
        get { PermissionPolicy(rawValue: deviceSensorPermissionRaw) ?? .ask }
        set { deviceSensorPermissionRaw = newValue.rawValue }
    }

    // MARK: - Content Protection

    /// Override for content protection bypass (text selection, copy, context menu).
    ///
    /// - `nil`: Use global `contentProtectionBypassEnabled` setting
    /// - `true`: Force enable bypass for this site
    /// - `false`: Force disable bypass for this site (use site's restrictions)
    var contentProtectionBypass: Bool?

    // MARK: - Energy

    /// Freezes CSS/SVG animation on this site to save energy ("Calm This Page").
    ///
    /// Infinite decorative animations keep the compositor rendering every frame
    /// while the page is visible. When enabled, `CalmPageScript` pauses them in
    /// place on every navigation; toggling applies live without a reload.
    var calmPage: Bool = false

    // MARK: - Web Behavior Overrides

    /// Override for beforeunload alert blocking.
    ///
    /// Controls whether this site can show "Are you sure you want to leave?" alerts.
    var beforeUnloadAlertOverrideRaw: String = BeforeUnloadAlertOverride.useDefault.rawValue

    var beforeUnloadAlertOverride: BeforeUnloadAlertOverride {
        get { BeforeUnloadAlertOverride(rawValue: beforeUnloadAlertOverrideRaw) ?? .useDefault }
        set { beforeUnloadAlertOverrideRaw = newValue.rawValue }
    }

    /// Override for scroll hijacking prevention.
    ///
    /// Controls whether custom scroll behaviors are allowed on this site.
    var scrollHijackingOverrideRaw: String = ScrollHijackingOverride.useDefault.rawValue

    var scrollHijackingOverride: ScrollHijackingOverride {
        get { ScrollHijackingOverride(rawValue: scrollHijackingOverrideRaw) ?? .useDefault }
        set { scrollHijackingOverrideRaw = newValue.rawValue }
    }

    /// Override for native video controls.
    ///
    /// Controls whether native video controls are forced on this site.
    var videoControlsOverrideRaw: String = VideoControlsOverride.useDefault.rawValue

    var videoControlsOverride: VideoControlsOverride {
        get { VideoControlsOverride(rawValue: videoControlsOverrideRaw) ?? .useDefault }
        set { videoControlsOverrideRaw = newValue.rawValue }
    }

    /// Override video playback speed for this site.
    ///
    /// - `nil`: Use global `defaultVideoSpeed` setting
    /// - Other: Use this speed for videos on this site
    var videoSpeedOverride: Double?

    // MARK: - Passwords

    /// When true, never prompt to save passwords for this domain.
    ///
    /// User can set this by choosing "Never for This Site" when the
    /// save password prompt appears after form submission.
    var neverSavePasswords: Bool = false

    // MARK: - Page Appearance

    /// Per-site dark mode override.
    var darkModeOverrideRaw: String = DarkModeOverride.auto.rawValue

    var darkModeOverride: DarkModeOverride {
        get { DarkModeOverride(rawValue: darkModeOverrideRaw) ?? .auto }
        set { darkModeOverrideRaw = newValue.rawValue }
    }

    /// Per-site page filter override.
    var pageFilterOverrideRaw: String = PageFilterOverride.auto.rawValue

    var pageFilterOverride: PageFilterOverride {
        get { PageFilterOverride(rawValue: pageFilterOverrideRaw) ?? .auto }
        set { pageFilterOverrideRaw = newValue.rawValue }
    }

    /// Per-site background removal override.
    var backgroundRemovalOverrideRaw: String = BackgroundRemovalOverride.auto.rawValue

    var backgroundRemovalOverride: BackgroundRemovalOverride {
        get { BackgroundRemovalOverride(rawValue: backgroundRemovalOverrideRaw) ?? .auto }
        set { backgroundRemovalOverrideRaw = newValue.rawValue }
    }

    // MARK: - Media Settings

    /// Per-site Picture-in-Picture preference.
    var pipPreferenceRaw: String = PiPPreference.system.rawValue

    var pipPreference: PiPPreference {
        get { PiPPreference(rawValue: pipPreferenceRaw) ?? .system }
        set { pipPreferenceRaw = newValue.rawValue }
    }

    // MARK: - Translation

    /// Translation preference for this site.
    ///
    /// Controls whether to offer, auto-translate, or never translate this site.
    var translationPreferenceRaw: String = TranslationPreference.ask.rawValue

    var translationPreference: TranslationPreference {
        get { TranslationPreference(rawValue: translationPreferenceRaw) ?? .ask }
        set { translationPreferenceRaw = newValue.rawValue }
    }

    /// Languages to always translate from on this site.
    ///
    /// When the page is detected as one of these languages, it will be
    /// auto-translated without prompting.
    var alwaysTranslateLanguages: [String] = []

    // MARK: - Timestamps

    /// When these settings were created.
    var createdAt: Date = Date()

    /// When these settings were last modified.
    var modifiedAt: Date = Date()

    // MARK: - Initialization

    init(domain: String) {
        self.domain = domain.lowercased()
    }

    // MARK: - Modification

    /// Marks the settings as modified and updates timestamp.
    func markModified() {
        modifiedAt = Date()
    }
}

// MARK: - Policy Enums

/// Auto-play policy for media elements.
enum AutoPlayPolicy: String, Codable, CaseIterable, Sendable {
    case allowAll
    case stopMediaWithSound
    case neverAutoPlay

    var displayName: String {
        switch self {
        case .allowAll: "Allow All Auto-Play"
        case .stopMediaWithSound: "Stop Media with Sound"
        case .neverAutoPlay: "Never Auto-Play"
        }
    }
}

// MARK: - WebKit Mapping

extension AutoPlayPolicy {
    /// Maps autoplay policy to WebKit's user-action requirements.
    ///
    /// Design rationale:
    /// - Use WebKit's built-in autoplay gating rather than manual JS playback control.
    /// - `stopMediaWithSound` maps to `.audio` to allow muted autoplay while
    ///   requiring gestures for audible playback, matching Safari behavior.
    var requiredUserActionMediaTypes: WKAudiovisualMediaTypes {
        switch self {
        case .allowAll:
            []
        case .stopMediaWithSound:
            .audio
        case .neverAutoPlay:
            .all
        }
    }

    /// Maps to WebKit's per-navigation autoplay policy.
    ///
    /// Set on `WKWebpagePreferences._autoplayPolicy` during navigation decisions
    /// so WebKit enforces the policy natively without manual media suspension.
    var websiteAutoplayPolicy: _WKWebsiteAutoplayPolicy {
        switch self {
        case .allowAll:
            .allow
        case .stopMediaWithSound:
            .allowWithoutSound
        case .neverAutoPlay:
            .deny
        }
    }
}

/// Pop-up window policy.
enum PopUpPolicy: String, Codable, CaseIterable, Sendable {
    case blockAndNotify
    case block
    case allow

    var displayName: String {
        switch self {
        case .blockAndNotify: "Block and Notify"
        case .block: "Block"
        case .allow: "Allow"
        }
    }
}

/// Per-site override for `Sec-GPC` header gating.
enum GPCHeaderOverride: String, Codable, CaseIterable, Sendable {
    case useAllowlist
    case allow
    case block

    var displayName: String {
        switch self {
        case .useAllowlist: "Use Default"
        case .allow: "Always Send"
        case .block: "Never Send"
        }
    }
}

/// Permission policy for site capabilities.
enum PermissionPolicy: String, Codable, CaseIterable, Sendable {
    case ask
    case deny
    case allow

    var displayName: String {
        switch self {
        case .ask: "Ask"
        case .deny: "Deny"
        case .allow: "Allow"
        }
    }

    /// Converts to WebKit permission decision.
    var webKitDecision: WKPermissionDecision {
        switch self {
        case .ask: .prompt
        case .deny: .deny
        case .allow: .grant
        }
    }
}

/// Per-site policy for website window coloring.
///
/// Controls whether a site's theme color can influence the window background.
/// This allows users to override the global setting for specific sites.
enum WebsiteColoringPolicy: String, Codable, CaseIterable, Sendable {
    /// Follow the global `enableWebsiteWindowColoring` setting.
    case useDefault

    /// Always allow this site to color the window.
    ///
    /// Takes precedence over space coloring, allowing specific sites
    /// (like design tools) to use their own theming.
    case allow

    /// Never allow this site to color the window.
    ///
    /// Useful for sites with distracting or inappropriate theme colors.
    case deny

    var displayName: String {
        switch self {
        case .useDefault: "Use Default"
        case .allow: "Allow"
        case .deny: "Block"
        }
    }
}

// MARK: - Dark Mode Override

/// Per-site dark mode override.
///
/// Controls whether forced dark mode is applied to this site.
enum DarkModeOverride: String, Codable, CaseIterable, Sendable {
    /// Follow the global `webpageDarkMode` setting.
    case auto

    /// Always apply dark mode to this site.
    case always

    /// Never apply dark mode to this site.
    case never

    var displayName: String {
        switch self {
        case .auto: "Use Default"
        case .always: "Always Dark"
        case .never: "Never Dark"
        }
    }
}

// MARK: - Page Filter

/// Visual filter to apply to web pages.
///
/// Accessibility-focused filters for improved readability.
enum PageFilter: String, Codable, CaseIterable, Sendable {
    case none
    case grayscale
    case highContrast
    case invertColors
    case reduceBrightness
    case sepia
    case protanopia
    case deuteranopia
    case tritanopia

    var displayName: String {
        switch self {
        case .none: "None"
        case .grayscale: "Grayscale"
        case .highContrast: "High Contrast"
        case .invertColors: "Invert Colors"
        case .reduceBrightness: "Reduce Brightness"
        case .sepia: "Sepia"
        case .protanopia: "Protanopia (Red-Blind)"
        case .deuteranopia: "Deuteranopia (Green-Blind)"
        case .tritanopia: "Tritanopia (Blue-Blind)"
        }
    }

    /// SF Symbol name for the filter.
    var iconName: String {
        switch self {
        case .none: "circle"
        case .grayscale: "circle.lefthalf.filled"
        case .highContrast: "circle.righthalf.filled"
        case .invertColors: "circle.fill"
        case .reduceBrightness: "sun.min"
        case .sepia: "sun.max"
        case .protanopia, .deuteranopia, .tritanopia: "eye"
        }
    }

    /// Whether this filter requires SVG color matrix injection.
    var requiresSVGFilters: Bool {
        switch self {
        case .protanopia, .deuteranopia, .tritanopia:
            true
        default:
            false
        }
    }
}

/// Per-site page filter override.
///
/// Allows overriding the global filter for specific sites.
enum PageFilterOverride: String, Codable, CaseIterable, Sendable {
    /// Use the global `pageFilter` setting.
    case auto
    case none
    case grayscale
    case highContrast
    case invertColors
    case reduceBrightness
    case sepia
    case protanopia
    case deuteranopia
    case tritanopia

    var displayName: String {
        if case .auto = self { return "Use Default" }
        guard let filter = effectiveFilter else { return "Use Default" }
        return filter.displayName
    }

    /// Returns the effective filter, or `nil` if using global default.
    var effectiveFilter: PageFilter? {
        switch self {
        case .auto: nil
        case .none: PageFilter.none
        case .grayscale: .grayscale
        case .highContrast: .highContrast
        case .invertColors: .invertColors
        case .reduceBrightness: .reduceBrightness
        case .sepia: .sepia
        case .protanopia: .protanopia
        case .deuteranopia: .deuteranopia
        case .tritanopia: .tritanopia
        }
    }
}

// MARK: - Background Removal

/// Mode for removing background images from web pages.
enum BackgroundRemovalMode: String, Codable, CaseIterable, Sendable {
    /// No background removal.
    case none

    /// Remove background-image CSS, keep background colors.
    case removeImages

    /// Remove images and simplify to solid background colors.
    case simplify

    /// Make backgrounds transparent (for vibrancy effect).
    case transparent

    var displayName: String {
        switch self {
        case .none: "None"
        case .removeImages: "Remove Background Images"
        case .simplify: "Simplify Backgrounds"
        case .transparent: "Transparent (Vibrancy)"
        }
    }
}

/// Per-site background removal override.
enum BackgroundRemovalOverride: String, Codable, CaseIterable, Sendable {
    /// Use the global `backgroundRemovalMode` setting.
    case auto
    case none
    case removeImages
    case simplify
    case transparent

    var displayName: String {
        if case .auto = self { return "Use Default" }
        guard let mode = effectiveMode else { return "Use Default" }
        return mode.displayName
    }

    /// Returns the effective mode, or `nil` if using global default.
    var effectiveMode: BackgroundRemovalMode? {
        switch self {
        case .auto: nil
        case .none: BackgroundRemovalMode.none
        case .removeImages: .removeImages
        case .simplify: .simplify
        case .transparent: .transparent
        }
    }
}

// MARK: - Picture-in-Picture

/// Per-site Picture-in-Picture preference.
///
/// Controls auto-PiP behavior when switching away from a tab with video.
enum PiPPreference: String, Codable, CaseIterable, Sendable {
    /// Follow the global `autoPiPOnTabSwitch` setting.
    case system

    /// Always auto-PiP when switching away from this site (even if global is off).
    case always

    /// Never auto-PiP for this site.
    case never

    var displayName: String {
        switch self {
        case .system: "Use Default"
        case .always: "Always Auto-PiP"
        case .never: "Never Auto-PiP"
        }
    }
}

// MARK: - Badge Detection

/// Badge detection mode for notification counts in page titles.
///
/// Many sites show notification counts in their titles (e.g., "(3) Gmail").
/// This setting controls whether those patterns mark the tab as unread.
enum BadgeDetectionMode: String, Codable, CaseIterable, Sendable {
    /// Automatically detect badges from title patterns.
    case automatic

    /// Never detect badges for this site.
    case disabled

    var displayName: String {
        switch self {
        case .automatic: "Automatic"
        case .disabled: "Disabled"
        }
    }
}

// MARK: - Translation Preference

/// Translation preference for a website.
///
/// Controls how translation is offered for pages on a specific domain.
enum TranslationPreference: String, Codable, CaseIterable, Sendable {
    /// Prompt for translation when a foreign language is detected.
    case ask

    /// Automatically translate pages on this site.
    case always

    /// Never offer translation for this site.
    case never

    var displayName: String {
        switch self {
        case .ask: "Ask"
        case .always: "Always Translate"
        case .never: "Never Translate"
        }
    }
}

// MARK: - Web Behavior Overrides

/// Override for beforeunload alert blocking.
///
/// Controls whether a site can show "Are you sure you want to leave?" alerts.
enum BeforeUnloadAlertOverride: String, Codable, CaseIterable, Sendable {
    /// Use global `disableBeforeUnloadAlerts` setting.
    case useDefault

    /// Allow this site to show beforeunload alerts.
    case allow

    /// Block beforeunload alerts on this site.
    case block

    var displayName: String {
        switch self {
        case .useDefault: "Use Default"
        case .allow: "Allow"
        case .block: "Block"
        }
    }
}

/// Override for scroll hijacking prevention.
///
/// Controls whether custom scroll behaviors are allowed on a site.
enum ScrollHijackingOverride: String, Codable, CaseIterable, Sendable {
    /// Use global `disableScrollHijacking` setting.
    case useDefault

    /// Allow this site to use custom scroll behaviors.
    case allow

    /// Force native scrolling on this site.
    case block

    var displayName: String {
        switch self {
        case .useDefault: "Use Default"
        case .allow: "Allow Site Control"
        case .block: "Force Native Scrolling"
        }
    }
}

/// Override for native video controls.
///
/// Controls whether native video controls are forced on a site.
enum VideoControlsOverride: String, Codable, CaseIterable, Sendable {
    /// Use global `forceNativeVideoControls` setting.
    case useDefault

    /// Force native video controls on this site.
    case forceNative

    /// Allow this site to use custom video controls.
    case allowSite

    var displayName: String {
        switch self {
        case .useDefault: "Use Default"
        case .forceNative: "Force Native"
        case .allowSite: "Allow Site"
        }
    }
}
