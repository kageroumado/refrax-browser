import Foundation
import SwiftData
import SwiftUI

/// User preferences and browser configuration.
///
/// Central storage for all user-configurable settings in Refrax, from search engines
/// to privacy controls. Settings are automatically persisted via SwiftData.
///
/// ## Categories
///
/// - **Search**: Default search engine and behavior
/// - **UI**: Theme, visual preferences
/// - **Privacy**: Cookie blocking, GPC/DNT signals, tracking protection, private mode
/// - **Advanced**: JavaScript, pop-ups, developer tools
///
/// ## Singleton Pattern
///
/// Only one `BrowserSettings` instance should exist in the database. Use
/// ``fetchOrCreate(in:)`` to retrieve or create the singleton instance.
///
/// ## Reset Capability
///
/// Users can restore factory defaults via ``resetToDefaults()``, which resets
/// all values to their initial defaults.
@Model
final class BrowserSettings {
    // MARK: - Identity

    /// Stable identifier for sync — BrowserSettings is a singleton per database.
    @Attribute(.preserveValueOnDeletion)
    var id: UUID = UUID()

    // MARK: - Search

    /// ID of the default search engine.
    ///
    /// Use ``defaultSearchEngine`` computed property for type-safe access.
    var searchEngineID: String?

    /// Injected reference to the custom search engine manager.
    ///
    /// Used by ``defaultSearchEngine`` to resolve custom engine IDs.
    /// Set once during app setup in ``RefraxAppDelegate``.
    @Transient var customSearchEngineManager: CustomSearchEngineManager?

    // MARK: - Appearance: Theme

    /// Raw value for appearance theme.
    ///
    /// Use ``theme`` computed property for type-safe access.
    var themeRawValue: String

    /// Hex string for custom accent color.
    ///
    /// Use ``customAccentColor`` computed property for type-safe access.
    var customAccentColorHex: String?

    // MARK: - Appearance: Window Background

    /// Hex string for custom window background color.
    ///
    /// Use ``customWindowBackgroundColor`` computed property for type-safe access.
    var customWindowBackgroundColorHex: String?

    /// How much to mix the window background color (0.0 to 1.0).
    var windowBackgroundMixAmount: Double

    /// Raw value for color mix mode.
    ///
    /// Use ``windowBackgroundMixMode`` computed property for type-safe access.
    var windowBackgroundMixModeRawValue: String

    /// Whether to tint window background based on active space color.
    var enableSpaceWindowColoring: Bool

    /// Whether websites can tint window background using their theme color.
    ///
    /// When enabled, websites with `<meta name="theme-color">` or a uniform top color
    /// can influence the window background. Per-site overrides take precedence.
    var enableWebsiteWindowColoring: Bool

    /// Opacity of the window background fill layer (0.0 to 1.0).
    ///
    /// Controls how much of the desktop is visible through the window:
    /// - `0.84`: macOS default (nearly opaque, subtle backdrop visibility)
    /// - `0.0`: Full Aero mode (desktop visible through tinted glass)
    var windowBackgroundFillOpacity: Double

    /// Whether website-provided colors use solid blend mode.
    ///
    /// When `true` (default), website colors render as a solid overlay without
    /// blending, providing consistent appearance for the site's chosen color.
    /// When `false`, website colors use the user's selected blend mode
    /// (same as custom and space colors).
    var websiteColorUseSolidBlend: Bool

    // MARK: - Appearance: Sidebar

    /// Raw value for default sidebar mode when collapsed.
    ///
    /// Use ``defaultSidebarMode`` computed property for type-safe access.
    var defaultSidebarModeRaw: String

    // MARK: - Appearance: Page

    /// Global dark mode preference for web pages.
    var webpageDarkModeRaw: String

    var webpageDarkMode: DarkModePreference {
        get { DarkModePreference(rawValue: webpageDarkModeRaw) ?? .off }
        set { webpageDarkModeRaw = newValue.rawValue }
    }

    /// Global page filter for accessibility.
    var pageFilterRaw: String

    var pageFilter: PageFilter {
        get { PageFilter(rawValue: pageFilterRaw) ?? .none }
        set { pageFilterRaw = newValue.rawValue }
    }

    /// Whether to preserve images and videos when using invert filter.
    ///
    /// When true, media elements are re-inverted to show original colors.
    var preserveMediaInFilter: Bool

    /// Global background removal mode.
    var backgroundRemovalModeRaw: String

    var backgroundRemovalMode: BackgroundRemovalMode {
        get { BackgroundRemovalMode(rawValue: backgroundRemovalModeRaw) ?? .none }
        set { backgroundRemovalModeRaw = newValue.rawValue }
    }

    // MARK: - Tabs: Previews

    /// Whether to show tab preview thumbnails on hover.
    var showTabPreviews: Bool

    // MARK: - Tabs: Archive

    /// Whether the tab archive feature is enabled.
    ///
    /// When enabled, closing a tab moves it to the Archive group instead of
    /// deleting it immediately, allowing recovery. When disabled, tabs are
    /// closed permanently.
    ///
    /// - Note: Disabling this setting deletes the archive group and all
    ///   archived tabs in every space.
    var archiveEnabled: Bool

    /// Hours after which archived tabs are automatically cleared, or `nil` for indefinite.
    ///
    /// Only tabs archived before the user's last app activation are subject
    /// to expiration, preventing silent disappearance during idle periods.
    ///
    /// Common values:
    /// - 1: One hour
    /// - 6: Six hours (default)
    /// - 24: One day
    /// - 168: One week
    /// - nil: Keep indefinitely
    var archiveClearHours: Int?

    /// Whether user-defined auto-archive rules are enabled.
    ///
    /// When enabled, tabs matching user rules (inactivity duration, tab count
    /// limits, domain patterns) are automatically archived on the hourly schedule.
    var autoArchiveRulesEnabled: Bool

    // MARK: - Tabs: Snapshots

    /// Whether automatic tab snapshots are enabled.
    ///
    /// When enabled, tabs are automatically snapshotted every 15 minutes.
    var enableAutomaticSnapshots: Bool

    /// Number of days to retain tab snapshots.
    ///
    /// Snapshots older than this are automatically deleted.
    /// Default: 30 days
    var snapshotRetentionDays: Int

    /// Maximum number of snapshots to keep.
    ///
    /// When exceeded, oldest snapshots are deleted first.
    /// Default: 200
    var maxSnapshotCount: Int

    // MARK: - Tabs: Video

    /// Legacy toggle superseded by ``elementFullscreenMode``; kept as the
    /// migration source for databases written before the mode picker existed.
    var inWindowFullscreenEnabled: Bool?

    /// Raw storage for ``elementFullscreenMode``.
    var elementFullscreenModeRaw: String?

    /// How element (video) fullscreen is presented.
    ///
    /// Falls back to the legacy ``inWindowFullscreenEnabled`` toggle when the
    /// mode has never been set on this database.
    var elementFullscreenMode: FullscreenPresentationMode {
        get {
            if let raw = elementFullscreenModeRaw,
               let mode = FullscreenPresentationMode(rawValue: raw) {
                return mode
            }
            return (inWindowFullscreenEnabled ?? false) ? .inTab : .system
        }
        set { elementFullscreenModeRaw = newValue.rawValue }
    }

    // MARK: - Tabs: Notifications

    /// Whether to detect notification badges from page titles.
    ///
    /// When enabled, pages with notification patterns in their titles (e.g., "(3) Gmail")
    /// automatically mark their tabs as unread. Per-site overrides take precedence.
    var badgeDetectionEnabled: Bool

    // MARK: - Tabs: Time Tracking

    /// Whether to show time spent per domain in tab tooltips.
    ///
    /// When enabled, hovering over a tab shows how much time has been spent
    /// on that domain today (rolling 24-hour window).
    var showTimeSpentInTooltips: Bool

    // MARK: - Tabs: Indicators

    /// Whether to show an indicator for tabs with unsaved form data.
    ///
    /// When enabled, tabs containing forms with user-entered data display
    /// a pencil indicator. These tabs are also exempt from auto-archiving.
    var showUnsavedFormIndicator: Bool

    // MARK: - Favorites

    /// Comma-separated list of enabled app shortcut type raw values.
    ///
    /// Use ``enabledAppShortcuts`` computed property for type-safe access.
    var enabledAppShortcutsRaw: String

    /// JSON-encoded dictionary of custom colors per app shortcut type.
    ///
    /// Use ``appShortcutColor(for:)`` and ``setAppShortcutColor(_:for:)`` for access.
    var appShortcutColorsJSON: String

    /// JSON-encoded dictionary of custom names per app shortcut type.
    ///
    /// Use ``appShortcutName(for:)`` and ``setAppShortcutName(_:for:)`` for access.
    var appShortcutNamesJSON: String

    // MARK: - Privacy: Tracking Protection

    /// Whether to block third-party cookies.
    var blockThirdPartyCookies: Bool

    /// Whether to send Do Not Track header.
    var doNotTrack: Bool

    /// Whether to send Global Privacy Control signals.
    ///
    /// When enabled, Refrax:
    /// - Sends the `Sec-GPC: 1` request header on navigations.
    /// - Exposes `navigator.globalPrivacyControl = true` to web content.
    var enableGlobalPrivacyControl: Bool

    /// Whether to log lightweight GPC usage telemetry.
    ///
    /// When enabled, Refrax records a one-time log per host when a page
    /// reads the GPC DOM signal. This is local-only logging intended
    /// for debugging breakage reports.
    var enableGPCTelemetry: Bool

    /// Whether to automatically dismiss cookie consent banners.
    ///
    /// When enabled, Refrax detects cookie consent popups and automatically
    /// clicks "reject all" or "necessary only" buttons using community-maintained
    /// rules. Falls back to "accept" if no reject option exists.
    var enableAutoConsent: Bool

    /// Whether to hide "Sign in with Google" and similar prompts.
    ///
    /// Uses cosmetic filtering to hide intrusive sign-in prompts,
    /// browser recommendation banners, and notification permission dialogs.
    var hideSignInPrompts: Bool

    // MARK: - Privacy: History

    /// Whether automatic history cleanup is enabled.
    ///
    /// When enabled, history older than ``historyRetentionDays`` is automatically deleted.
    var automaticHistoryCleanup: Bool

    /// Number of days to retain history entries.
    ///
    /// Only used when ``automaticHistoryCleanup`` is enabled.
    /// Common values:
    /// - 7: One week
    /// - 30: One month
    /// - 90: Three months
    /// - 180: Six months
    /// - 365: One year
    var historyRetentionDays: Int

    // MARK: - Privacy: Space Locking

    /// Default auto-lock timeout for locked spaces (seconds).
    ///
    /// After this duration of inactivity, locked spaces automatically re-lock.
    /// Individual spaces can override with ``Space/lockTimeoutOverride``.
    var defaultLockTimeout: Int

    // MARK: - Privacy: Privacy Protection Relationship

    /// Privacy protection settings (link cleaning, tracking prevention, etc.).
    ///
    /// One-to-one relationship. Created lazily via ``privacyProtection``.
    @Relationship(deleteRule: .cascade)
    private var _privacyProtection: PrivacyProtectionSettings?

    /// Gets or creates privacy protection settings.
    var privacyProtection: PrivacyProtectionSettings {
        if let existing = _privacyProtection {
            return existing
        }
        let settings = PrivacyProtectionSettings()
        _privacyProtection = settings
        return settings
    }

    // MARK: - Getting Started

    /// Whether to show the sidebar guide in the main content area when no tab is open.
    ///
    /// Defaults to true on first launch. Users can dismiss via the "Don't show again"
    /// button in the guide, or re-enable it from Settings > General.
    var showSidebarHints: Bool = true

    // MARK: - Browsing: Gestures

    /// Whether two-finger swipe gesture is enabled for switching spaces.
    ///
    /// When enabled, swiping horizontally on the sidebar switches between spaces.
    var spaceSwipeGestureEnabled: Bool

    // MARK: - Browsing: Link Previews

    /// Whether Shift+Click triggers a Quick Look preview for links.
    ///
    /// When enabled, holding Shift and clicking a link shows a preview
    /// instead of navigating. This provides an alternative to Force Touch
    /// previews for users with mice or trackpads without Force Touch.
    var shiftClickLinkPreviewEnabled: Bool

    /// Whether to show modifier key hints overlay on web content.
    ///
    /// When enabled, holding Option or Shift shows a brief hint explaining
    /// what clicking a link will do (open in Glimpse, or show Link Preview).
    /// Power users who already know these shortcuts can disable this.
    var showModifierKeyHints: Bool

    // MARK: - Browsing: Media

    /// Whether to automatically enter Picture-in-Picture when switching tabs.
    ///
    /// When enabled and a tab has a playing video, switching to another tab
    /// will automatically enter PiP mode for the video. Only triggers for
    /// videos that are actively playing (not paused).
    var autoPiPOnTabSwitch: Bool

    /// Whether to force native video controls on all video elements.
    ///
    /// When enabled, browser-native video controls are shown on all videos,
    /// enabling AirPlay, Picture-in-Picture, and standard playback controls
    /// even on sites that hide them.
    /// Individual sites can override via ``SiteSettings/videoControlsOverride``.
    var forceNativeVideoControls: Bool

    /// Default video playback speed.
    ///
    /// Applied to videos when ``forceNativeVideoControls`` is enabled.
    /// Valid range: 0.25 to 4.0. Default: 1.0 (normal speed).
    var defaultVideoSpeed: Double

    // MARK: - Browsing: Web Behavior

    /// Whether to block beforeunload alerts from web pages.
    ///
    /// When enabled, websites cannot show "Are you sure you want to leave?" dialogs.
    /// The browser's native media playback checks (audio, camera, mic) still apply.
    /// Individual sites can override via ``SiteSettings/beforeUnloadAlertOverride``.
    var disableBeforeUnloadAlerts: Bool

    /// Whether to disable scroll hijacking on web pages.
    ///
    /// When enabled, custom scroll behaviors (smooth scrolling, scroll snapping,
    /// scroll animations) are disabled in favor of native scrolling.
    /// Individual sites can override via ``SiteSettings/scrollHijackingOverride``.
    var disableScrollHijacking: Bool

    /// Whether content protection bypass is enabled by default.
    ///
    /// When enabled, websites cannot prevent text selection, copying,
    /// or context menus. Individual sites can override via ``SiteSettings/contentProtectionBypass``.
    var contentProtectionBypassEnabled: Bool

    // MARK: - Browsing: Mail Handler

    /// Raw value for preferred mail handler.
    ///
    /// Use ``preferredMailHandler`` computed property for type-safe access.
    var preferredMailHandlerRaw: String

    // MARK: - Browsing: AutoFill

    /// Raw value for autofill mode setting.
    ///
    /// Use ``autoFillMode`` computed property for type-safe access.
    var autoFillModeRaw: String

    /// Autofill mode setting.
    ///
    /// Controls how Refrax interacts with form fields:
    /// - `.disabled`: No autofill UI, extensions can work freely
    /// - `.systemOnly`: Only "Passwords...", "Credit Cards...", "Contacts..." options
    /// - `.builtIn`: Full autofill with credential saving and generation
    ///
    /// The Passwords window remains accessible for manual management regardless of mode.
    var autoFillMode: AutoFillMode {
        get { AutoFillMode(rawValue: autoFillModeRaw) ?? .disabled }
        set { autoFillModeRaw = newValue.rawValue }
    }

    /// Whether to require Touch ID (or system password) before autofilling credentials.
    ///
    /// When enabled, clicking a credential in the autofill popover triggers biometric
    /// or password authentication before filling. The Touch ID icon is shown on
    /// credential rows as a visual indicator. Default: `false`.
    var requireAuthForAutoFill: Bool = false

    // MARK: - Browsing: Clipboard

    /// Whether to monitor clipboard for URLs and show quick-open toast.
    ///
    /// When enabled, Refrax periodically checks the clipboard for HTTP/HTTPS URLs
    /// and shows a toast allowing quick navigation. Off by default for privacy.
    var clipboardLinkMonitoring: Bool

    // MARK: - Downloads

    /// Custom download directory path.
    ///
    /// When `nil`, downloads go to the system Downloads folder (~/Downloads).
    /// Users can specify a custom path for all downloads.
    var customDownloadDirectory: String?

    // MARK: - Downloads: aria2

    /// Whether to use aria2 for large file downloads.
    ///
    /// When enabled, downloads larger than ``aria2ThresholdMB`` use aria2's
    /// multi-connection downloader for improved speed and reliability.
    var useAria2ForLargeFiles: Bool

    /// Size threshold in megabytes for using aria2.
    ///
    /// Downloads >= this size will use aria2 if ``useAria2ForLargeFiles`` is true.
    /// Common values: 10, 25, 50, 100, 250 MB. Default: 50.
    var aria2ThresholdMB: Int

    /// Whether BitTorrent downloads are enabled.
    ///
    /// When enabled, Refrax can handle magnet: links and .torrent files.
    /// Requires aria2 daemon with BitTorrent support. Downloads are not seeded
    /// by default to minimize bandwidth usage.
    var enableBitTorrent: Bool

    // MARK: - Downloads: yt-dlp

    /// Whether yt-dlp video downloads are enabled.
    ///
    /// When enabled, context menu shows download options on supported video sites
    /// (YouTube, Vimeo, TikTok, etc.). Requires yt-dlp binary to be installed.
    var ytdlpEnabled: Bool

    /// Whether to export browser cookies for yt-dlp downloads.
    ///
    /// When enabled, browser cookies are passed to yt-dlp for authenticated
    /// downloads (age-restricted content, private playlists, etc.).
    var ytdlpUseCookies: Bool

    /// Whether to delete video files after importing to Photos.
    ///
    /// When enabled and using "Save to Photos" mode, the downloaded video
    /// file is deleted after successful import to the Photos library.
    var ytdlpDeleteAfterPhotosImport: Bool

    // MARK: - Agent Chat

    /// Whether the agent chat feature is enabled.
    var agentEnabled: Bool

    /// Session key for agent chat conversations.
    ///
    /// Use "agent:main:main" for continuity with Discord DMs.
    var agentSessionKey: String

    /// Whether to automatically include browser context in messages.
    ///
    /// When enabled and a message references "this page" or similar,
    /// the current URL, title, and selection are included.
    var agentAutoIncludeContext: Bool

    /// Which provider backend to use for agent chat.
    var agentProviderKind: AgentProviderKind

    /// Claude model identifier for direct API mode.
    var agentClaudeModel: String

    /// Maximum output tokens for Claude API responses.
    var agentClaudeMaxTokens: Int

    /// Model identifier used when ``agentProviderKind`` is `.openAI`.
    var agentOpenAIModel: String = "gpt-5"

    /// Model identifier used when ``agentProviderKind`` is `.openRouter`.
    ///
    /// OpenRouter routes by `provider/model-slug`; defaults to a
    /// tool-calling-capable Claude.
    var agentOpenRouterModel: String = "anthropic/claude-opus-4.6"

    /// Model identifier used when ``agentProviderKind`` is `.custom`.
    ///
    /// Typically the identifier returned by the custom endpoint's
    /// `GET /v1/models` response (e.g., `llama3.1:latest` for Ollama).
    var agentCustomModel: String = ""

    /// Base URL for the custom OpenAI-compatible endpoint.
    ///
    /// Must include the API prefix — e.g., `http://localhost:11434/v1` for
    /// Ollama, `http://localhost:1234/v1` for LM Studio.
    var agentCustomBaseURL: String = "http://localhost:11434/v1"

    /// Whether the custom endpoint requires an API key. When `false`, no
    /// `Authorization` header is sent (typical for fully local servers).
    var agentCustomRequiresAuth: Bool = false

    /// Maximum output tokens for OpenAI-compatible providers.
    var agentOpenAIMaxTokens: Int = 4_096

    /// Display name for the agent in chat header.
    var agentDisplayName: String

    /// Custom avatar image data for the agent (PNG).
    /// If nil, shows default person icon.
    var agentAvatarData: Data?

    // MARK: - Widgets: Calendar

    /// Whether to show the calendar widget in the sidebar.
    var showCalendarWidget: Bool

    /// Number of hours to look ahead for upcoming events.
    var calendarLookAheadHours: Int

    /// Whether to auto-expand when an event starts within 15 minutes.
    var calendarAutoExpandOnImminent: Bool

    /// JSON-encoded array of enabled calendar identifiers.
    ///
    /// Use ``enabledCalendarIDs`` computed property for type-safe access.
    var enabledCalendarIDsJSON: String

    // MARK: - Widgets: Speed Reader

    /// Default words per minute for Speed Reader.
    ///
    /// Valid range: 50-800 WPM. Default: 250.
    var speedReaderWPM: Int

    /// JSON-encoded dictionary mapping article URLs to resume word indices.
    ///
    /// Use ``speedReaderResumePositions`` computed property for type-safe access.
    /// Entries older than 7 days are automatically cleaned up.
    var speedReaderResumePositionsJSON: String

    // MARK: - Advanced: JavaScript

    /// Whether JavaScript is enabled globally.
    ///
    /// Changes apply to new pages only. Existing pages retain their JavaScript
    /// setting until reloaded or recreated.
    var enableJavaScript: Bool

    /// Whether to allow site-specific JavaScript overrides.
    ///
    /// When true and global JavaScript is disabled, sites can be whitelisted
    /// to enable JavaScript. When false, JavaScript is disabled for all sites
    /// regardless of per-site settings.
    var allowJavaScriptWhitelist: Bool

    // MARK: - Advanced: Windows

    /// Whether pop-up windows are allowed.
    var allowPopups: Bool

    // MARK: - Advanced: Control Server

    /// Raw value for control server access mode.
    ///
    /// Use ``controlAccessMode`` computed property for type-safe access.
    var controlAccessModeRaw: String

    /// JSON-encoded array of allowed control server clients.
    ///
    /// Use ``ControlAccessManager`` for programmatic access.
    var allowedControlClientsJSON: String

    /// Control server access mode.
    ///
    /// Controls how the control server handles incoming connections:
    /// - `.off`: Socket not running, no CLI access
    /// - `.prompt`: Unknown binaries trigger an allow/deny alert
    /// - `.open`: Any same-UID process accepted
    var controlAccessMode: ControlAccessMode {
        get { ControlAccessMode(rawValue: controlAccessModeRaw) ?? .prompt }
        set { controlAccessModeRaw = newValue.rawValue }
    }

    // MARK: - Advanced: Security

    /// Whether users can bypass SSL certificate errors.
    ///
    /// When enabled, users can proceed to websites with invalid certificates
    /// after viewing a warning. Disabled by default for security.
    ///
    /// - Warning: Enabling this setting reduces security. Users should only
    ///   bypass certificate errors for trusted development/testing servers.
    var allowSSLCertificateBypass: Bool

    // MARK: - Advanced: Crash Recovery

    /// Number of crashes within the time window before stopping auto-reload.
    ///
    /// When a page crashes this many times within ``crashTimeWindowSeconds``,
    /// auto-recovery is suppressed and the user must manually reload.
    ///
    /// Default: 3 crashes
    var crashThreshold: Int

    /// Time window for tracking crash frequency (seconds).
    ///
    /// Crashes are counted within this rolling window to determine if a page
    /// is "problematic".
    ///
    /// Default: 60 seconds
    var crashTimeWindowSeconds: Int

    /// Whether to automatically reload tabs after crashes.
    ///
    /// When disabled, crashed tabs show an error page and require manual reload.
    var enableAutoCrashRecovery: Bool

    // MARK: - Feedback

    /// Remembered name for feedback submissions.
    var feedbackName: String = ""

    /// Remembered email for feedback submissions.
    var feedbackEmail: String = ""

    /// Whether to persist all log levels to disk (not just warning+).
    var verboseLoggingEnabled: Bool = false

    // MARK: - Updates

    /// Whether to automatically check for updates on the hourly schedule.
    var checkForUpdatesAutomatically: Bool = true

    // MARK: - Activation & Telemetry

    /// Whether the app has been activated with a valid invite code.
    var isActivated: Bool = false

    /// The invite code used to activate this device.
    var activationCode: String?

    /// Whether the user has completed the onboarding flow.
    ///
    /// When `false`, the app shows the onboarding window instead of the main browser.
    var hasCompletedOnboarding: Bool = false

    /// Whether the one-time onboarding migration has run.
    ///
    /// The migration auto-completes onboarding for pre-onboarding installs
    /// that already have browsing data. This flag prevents it from
    /// re-triggering after a debug reset.
    var hasRunOnboardingMigration: Bool = false

    /// Whether anonymous telemetry is enabled (opt-out).
    var telemetryEnabled: Bool = true

    /// Timestamp of the last heartbeat ping sent to the server.
    ///
    /// Used to throttle heartbeats to once per 24 hours.
    var lastHeartbeatDate: Date?

    // MARK: - Feature Flags

    /// JSON-encoded dictionary of user feature flag overrides.
    ///
    /// Maps feature flag keys (e.g., `"LinkSanitizerEnabled"`) to boolean values.
    /// Flags not present in this dictionary use their default value from
    /// ``FeatureFlagDefinition/defaultValue``.
    ///
    /// Use ``isFeatureFlagEnabled(_:default:)``, ``setFeatureFlag(_:enabled:)``,
    /// and ``resetFeatureFlags()`` for type-safe access.
    var featureFlagOverridesJSON: String = "{}"

    // MARK: - Sync

    /// Whether iCloud sync is enabled.
    ///
    /// Opt-in for the first release. When enabled and an iCloud account is available,
    /// the app creates a ``SyncCoordinator`` to push/pull data via CKSyncEngine.
    var iCloudSyncEnabled: Bool = false

    // MARK: - Defaults

    enum Defaults {
        static let accentColorHex = "p3:0.7840,0.6900,0.9930"
        static let windowBackgroundColorHex = "p3:0.7840,0.6900,0.9930"
        static let windowBackgroundMixAmount = 0.6
        static let windowBackgroundMixMode: ColorMixMode = .multiply
        static let windowBackgroundFillOpacity = 0.84
    }

    // MARK: - Initialization

    /// Creates settings with default values.
    init() {
        self.searchEngineID = nil
        self.showTabPreviews = false
        self.themeRawValue = AppearanceTheme.system.rawValue
        self.customAccentColorHex = Defaults.accentColorHex
        self.customWindowBackgroundColorHex = Defaults.windowBackgroundColorHex
        self.windowBackgroundMixAmount = Defaults.windowBackgroundMixAmount
        self.windowBackgroundMixModeRawValue = Defaults.windowBackgroundMixMode.rawValue
        self.windowBackgroundFillOpacity = Defaults.windowBackgroundFillOpacity
        self.enableSpaceWindowColoring = false
        self.enableWebsiteWindowColoring = false
        self.websiteColorUseSolidBlend = true
        self.spaceSwipeGestureEnabled = true
        self.defaultSidebarModeRaw = SidebarMode.compact.rawValue
        self.blockThirdPartyCookies = true
        self.doNotTrack = true
        self.enableGlobalPrivacyControl = true
        self.enableGPCTelemetry = false
        self.enableAutoConsent = false
        self.automaticHistoryCleanup = false
        self.historyRetentionDays = 365
        self.archiveEnabled = false
        self.archiveClearHours = 6
        self.autoArchiveRulesEnabled = false
        self.enableAutomaticSnapshots = true
        self.snapshotRetentionDays = 30
        self.maxSnapshotCount = 200
        self.enableJavaScript = true
        self.allowJavaScriptWhitelist = true
        self.allowPopups = false
        self.shiftClickLinkPreviewEnabled = true
        self.showModifierKeyHints = true
        self.inWindowFullscreenEnabled = false
        self.badgeDetectionEnabled = true
        self.showTimeSpentInTooltips = true
        self.showUnsavedFormIndicator = false
        self.autoPiPOnTabSwitch = true
        self.controlAccessModeRaw = ControlAccessMode.prompt.rawValue
        self.allowedControlClientsJSON = "[]"
        self.allowSSLCertificateBypass = false
        self.defaultLockTimeout = 300
        self.contentProtectionBypassEnabled = true
        self.disableBeforeUnloadAlerts = false
        self.disableScrollHijacking = false
        self.forceNativeVideoControls = false
        self.defaultVideoSpeed = 1.0
        self.hideSignInPrompts = true
        self.webpageDarkModeRaw = DarkModePreference.off.rawValue
        self.pageFilterRaw = PageFilter.none.rawValue
        self.preserveMediaInFilter = true
        self.backgroundRemovalModeRaw = BackgroundRemovalMode.none.rawValue
        self.crashThreshold = 3
        self.crashTimeWindowSeconds = 60
        self.enableAutoCrashRecovery = true
        self.enabledAppShortcutsRaw = ""
        self.appShortcutColorsJSON = "{}"
        self.appShortcutNamesJSON = "{}"
        self.showCalendarWidget = false
        self.calendarLookAheadHours = 24
        self.calendarAutoExpandOnImminent = true
        self.enabledCalendarIDsJSON = "[]"
        self.speedReaderWPM = 250
        self.speedReaderResumePositionsJSON = "{}"
        self.autoFillModeRaw = AutoFillMode.builtIn.rawValue
        self.requireAuthForAutoFill = false
        self.clipboardLinkMonitoring = false
        self.customDownloadDirectory = nil
        self.useAria2ForLargeFiles = false
        self.aria2ThresholdMB = 50
        self.enableBitTorrent = false
        self.ytdlpEnabled = true
        self.ytdlpUseCookies = true
        self.ytdlpDeleteAfterPhotosImport = false
        self.agentEnabled = true
        self.agentSessionKey = "agent:main:main"
        self.agentAutoIncludeContext = true
        self.agentProviderKind = .claudeAPI
        self.agentClaudeModel = ClaudeModel.sonnet.rawValue
        self.agentClaudeMaxTokens = 8_192
        self.agentOpenAIModel = "gpt-5"
        self.agentOpenRouterModel = "anthropic/claude-opus-4.6"
        self.agentCustomModel = ""
        self.agentCustomBaseURL = "http://localhost:11434/v1"
        self.agentCustomRequiresAuth = false
        self.agentOpenAIMaxTokens = 4_096
        self.agentDisplayName = "Agent"
        self.agentAvatarData = nil
        self.preferredMailHandlerRaw = MailHandler.system.rawValue
        self.feedbackName = ""
        self.feedbackEmail = ""
        self.verboseLoggingEnabled = false
        self.checkForUpdatesAutomatically = true
        self.isActivated = false
        self.activationCode = nil
        self.hasCompletedOnboarding = false
        self.hasRunOnboardingMigration = false
        self.telemetryEnabled = false
        self.lastHeartbeatDate = nil
        self.featureFlagOverridesJSON = "{}"
        self.iCloudSyncEnabled = false
    }

    // MARK: - Computed Properties

    /// The default search engine.
    ///
    /// Looks up the stored engine ID in built-in engines first, then custom engines.
    /// Falls back to DuckDuckGo if no engine ID is stored or not found.
    @MainActor
    var defaultSearchEngine: SearchEngine {
        get {
            guard let id = searchEngineID else { return .duckDuckGo }
            if let engine = SearchEngine.builtIns.first(where: { $0.id == id }) {
                return engine
            }
            if let engine = customSearchEngineManager?.cachedEngines.first(where: { $0.id == id }) {
                return engine
            }
            return .duckDuckGo
        }
        set {
            searchEngineID = newValue.id
        }
    }

    /// The appearance theme setting.
    var theme: AppearanceTheme {
        get {
            AppearanceTheme(rawValue: themeRawValue) ?? .system
        }
        set {
            themeRawValue = newValue.rawValue
        }
    }

    /// Custom accent color components.
    var customAccentColor: Color.Components? {
        get {
            guard let hex = customAccentColorHex else { return nil }
            return Color.Components(encoded: hex)
        }
        set {
            customAccentColorHex = newValue?.taggedString
        }
    }

    /// Custom window background color components.
    var customWindowBackgroundColor: Color.Components? {
        get {
            guard let hex = customWindowBackgroundColorHex else { return nil }
            return Color.Components(encoded: hex)
        }
        set {
            customWindowBackgroundColorHex = newValue?.taggedString
        }
    }

    /// The color mix mode for window background.
    var windowBackgroundMixMode: ColorMixMode {
        get {
            ColorMixMode(rawValue: windowBackgroundMixModeRawValue) ?? .softLight
        }
        set {
            windowBackgroundMixModeRawValue = newValue.rawValue
        }
    }

    /// The default sidebar mode when collapsed.
    var defaultSidebarMode: SidebarMode {
        get {
            SidebarMode(rawValue: defaultSidebarModeRaw) ?? .compact
        }
        set {
            defaultSidebarModeRaw = newValue.rawValue
        }
    }

    /// The preferred handler for mailto: links.
    var preferredMailHandler: MailHandler {
        get {
            MailHandler(rawValue: preferredMailHandlerRaw) ?? .system
        }
        set {
            preferredMailHandlerRaw = newValue.rawValue
        }
    }

    // MARK: - App Shortcuts

    /// Set of enabled app shortcut types.
    var enabledAppShortcuts: Set<AppShortcutType> {
        get {
            guard !enabledAppShortcutsRaw.isEmpty else { return [] }
            let rawValues = enabledAppShortcutsRaw.split(separator: ",")
            return Set(rawValues.compactMap { AppShortcutType(rawValue: String($0)) })
        }
        set {
            enabledAppShortcutsRaw = newValue.map(\.rawValue).joined(separator: ",")
        }
    }

    /// Check if an app shortcut type is enabled.
    func isAppShortcutEnabled(_ type: AppShortcutType) -> Bool {
        enabledAppShortcuts.contains(type)
    }

    /// Set of enabled calendar identifiers for the calendar widget.
    var enabledCalendarIDs: Set<String> {
        get {
            guard let data = enabledCalendarIDsJSON.data(using: .utf8),
                  let ids = try? JSONDecoder().decode([String].self, from: data) else {
                return []
            }
            return Set(ids)
        }
        set {
            if let data = try? JSONEncoder().encode(Array(newValue)),
               let json = String(data: data, encoding: .utf8) {
                enabledCalendarIDsJSON = json
            }
        }
    }

    /// Check if a calendar is enabled for the widget.
    func isCalendarEnabled(_ calendarID: String) -> Bool {
        enabledCalendarIDs.contains(calendarID)
    }

    // MARK: - Speed Reader Resume Positions

    /// Resume position entry with timestamp for cleanup.
    private struct ResumePosition: Codable {
        let index: Int
        let timestamp: Date
    }

    /// Gets the saved resume position for an article URL.
    ///
    /// Returns nil if no position is saved or if the saved position is older than 7 days.
    func speedReaderResumePosition(for url: URL) -> Int? {
        guard let data = speedReaderResumePositionsJSON.data(using: .utf8),
              let positions = try? JSONDecoder().decode([String: ResumePosition].self, from: data),
              let position = positions[url.absoluteString] else {
            return nil
        }

        // Expire positions older than 7 days
        let maxAge: TimeInterval = 7 * 24 * 60 * 60
        guard Date().timeIntervalSince(position.timestamp) < maxAge else {
            return nil
        }

        return position.index
    }

    /// Saves the resume position for an article URL.
    ///
    /// Also cleans up entries older than 7 days.
    func setSpeedReaderResumePosition(_ index: Int, for url: URL) {
        var positions: [String: ResumePosition] = [:]

        // Decode existing positions
        if let data = speedReaderResumePositionsJSON.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([String: ResumePosition].self, from: data) {
            positions = decoded
        }

        // Clean up old entries and add new one
        let maxAge: TimeInterval = 7 * 24 * 60 * 60
        let now = Date()
        positions = positions.filter { now.timeIntervalSince($0.value.timestamp) < maxAge }
        positions[url.absoluteString] = ResumePosition(index: index, timestamp: now)

        // Encode and save
        if let data = try? JSONEncoder().encode(positions),
           let json = String(data: data, encoding: .utf8) {
            speedReaderResumePositionsJSON = json
        }
    }

    /// Clears the resume position for an article URL.
    func clearSpeedReaderResumePosition(for url: URL) {
        guard var positions = try? JSONDecoder().decode(
            [String: ResumePosition].self,
            from: speedReaderResumePositionsJSON.data(using: .utf8) ?? Data(),
        ) else { return }

        positions.removeValue(forKey: url.absoluteString)

        if let data = try? JSONEncoder().encode(positions),
           let json = String(data: data, encoding: .utf8) {
            speedReaderResumePositionsJSON = json
        }
    }

    /// Enable or disable an app shortcut type.
    func setAppShortcutEnabled(_ type: AppShortcutType, enabled: Bool) {
        var shortcuts = enabledAppShortcuts
        if enabled {
            shortcuts.insert(type)
        } else {
            shortcuts.remove(type)
        }
        enabledAppShortcuts = shortcuts
    }

    /// Get custom color for an app shortcut type.
    func appShortcutColor(for type: AppShortcutType) -> String? {
        guard let data = appShortcutColorsJSON.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return dict[type.rawValue]
    }

    /// Set custom color for an app shortcut type.
    func setAppShortcutColor(_ color: String?, for type: AppShortcutType) {
        var dict: [String: String] = [:]
        if let data = appShortcutColorsJSON.data(using: .utf8),
           let existing = try? JSONDecoder().decode([String: String].self, from: data) {
            dict = existing
        }

        if let color {
            dict[type.rawValue] = color
        } else {
            dict.removeValue(forKey: type.rawValue)
        }

        if let encoded = try? JSONEncoder().encode(dict),
           let json = String(data: encoded, encoding: .utf8) {
            appShortcutColorsJSON = json
        }
    }

    /// Get custom name for an app shortcut type.
    func appShortcutName(for type: AppShortcutType) -> String? {
        guard let data = appShortcutNamesJSON.data(using: .utf8),
              let dict = try? JSONDecoder().decode([String: String].self, from: data) else {
            return nil
        }
        return dict[type.rawValue]
    }

    /// Set custom name for an app shortcut type.
    func setAppShortcutName(_ name: String?, for type: AppShortcutType) {
        var dict: [String: String] = [:]
        if let data = appShortcutNamesJSON.data(using: .utf8),
           let existing = try? JSONDecoder().decode([String: String].self, from: data) {
            dict = existing
        }

        if let name {
            dict[type.rawValue] = name
        } else {
            dict.removeValue(forKey: type.rawValue)
        }

        if let encoded = try? JSONEncoder().encode(dict),
           let json = String(data: encoded, encoding: .utf8) {
            appShortcutNamesJSON = json
        }
    }

    // MARK: - Feature Flags

    /// Decoded feature flag overrides dictionary.
    var featureFlagOverrides: [String: Bool] {
        get {
            guard let data = featureFlagOverridesJSON.data(using: .utf8),
                  let dict = try? JSONDecoder().decode([String: Bool].self, from: data)
            else {
                return [:]
            }
            return dict
        }
        set {
            if let data = try? JSONEncoder().encode(newValue),
               let json = String(data: data, encoding: .utf8)
            {
                featureFlagOverridesJSON = json
            }
        }
    }

    /// Returns whether a feature flag is enabled, falling back to the default.
    func isFeatureFlagEnabled(_ key: String, default defaultValue: Bool) -> Bool {
        featureFlagOverrides[key] ?? defaultValue
    }

    /// Sets or clears a feature flag override.
    ///
    /// Pass `nil` to remove the override and revert to the default value.
    func setFeatureFlag(_ key: String, enabled: Bool?) {
        var overrides = featureFlagOverrides
        overrides[key] = enabled
        featureFlagOverrides = overrides
    }

    /// Clears all feature flag overrides, reverting to defaults.
    func resetFeatureFlags() {
        featureFlagOverridesJSON = "{}"
    }

    /// Whether any feature flags have been overridden from their defaults.
    var hasFeatureFlagOverrides: Bool {
        !featureFlagOverrides.isEmpty
    }

    // MARK: - Reset

    /// Reset all settings to defaults.
    @MainActor
    func resetToDefaults() {
        defaultSearchEngine = .duckDuckGo
        showTabPreviews = false
        theme = .system
        customAccentColorHex = Defaults.accentColorHex
        customWindowBackgroundColor = Color.Components(encoded: Defaults.windowBackgroundColorHex)
        windowBackgroundMixAmount = Defaults.windowBackgroundMixAmount
        windowBackgroundMixMode = Defaults.windowBackgroundMixMode
        windowBackgroundFillOpacity = Defaults.windowBackgroundFillOpacity
        enableSpaceWindowColoring = false
        enableWebsiteWindowColoring = false
        websiteColorUseSolidBlend = true
        spaceSwipeGestureEnabled = true
        defaultSidebarMode = .compact
        blockThirdPartyCookies = true
        doNotTrack = true
        enableGlobalPrivacyControl = true
        enableGPCTelemetry = false
        enableAutoConsent = false
        automaticHistoryCleanup = false
        historyRetentionDays = 365
        archiveEnabled = false
        archiveClearHours = 6
        autoArchiveRulesEnabled = false
        enableAutomaticSnapshots = true
        snapshotRetentionDays = 30
        maxSnapshotCount = 200
        enableJavaScript = true
        allowJavaScriptWhitelist = true
        allowPopups = false
        shiftClickLinkPreviewEnabled = true
        showModifierKeyHints = true
        inWindowFullscreenEnabled = false
        elementFullscreenModeRaw = nil
        badgeDetectionEnabled = true
        showTimeSpentInTooltips = true
        showUnsavedFormIndicator = false
        autoPiPOnTabSwitch = true
        allowSSLCertificateBypass = false
        controlAccessMode = .prompt
        allowedControlClientsJSON = "[]"
        defaultLockTimeout = 300
        contentProtectionBypassEnabled = true
        disableBeforeUnloadAlerts = false
        disableScrollHijacking = false
        forceNativeVideoControls = false
        defaultVideoSpeed = 1.0
        hideSignInPrompts = true
        webpageDarkMode = .off
        pageFilter = .none
        preserveMediaInFilter = true
        backgroundRemovalMode = .none
        crashThreshold = 3
        crashTimeWindowSeconds = 60
        enableAutoCrashRecovery = true
        enabledAppShortcuts = []
        appShortcutColorsJSON = "{}"
        appShortcutNamesJSON = "{}"
        preferredMailHandler = .system
        autoFillMode = .systemOnly
        customDownloadDirectory = nil
        useAria2ForLargeFiles = false
        aria2ThresholdMB = 50
        enableBitTorrent = false
        ytdlpEnabled = true
        ytdlpUseCookies = true
        ytdlpDeleteAfterPhotosImport = false
        agentProviderKind = .claudeAPI
        agentClaudeModel = ClaudeModel.sonnet.rawValue
        agentClaudeMaxTokens = 8_192
        agentOpenAIModel = "gpt-5"
        agentOpenRouterModel = "anthropic/claude-opus-4.6"
        agentCustomModel = ""
        agentCustomBaseURL = "http://localhost:11434/v1"
        agentCustomRequiresAuth = false
        agentOpenAIMaxTokens = 4_096
        agentDisplayName = "Agent"
        agentAvatarData = nil
        feedbackName = ""
        feedbackEmail = ""
        verboseLoggingEnabled = false
        checkForUpdatesAutomatically = true
        telemetryEnabled = false
        lastHeartbeatDate = nil
        featureFlagOverridesJSON = "{}"
        iCloudSyncEnabled = false

        Logger.info("Browser settings reset to defaults", category: Logger.data)
    }

    // MARK: - Singleton Access

    /// Fetches the existing settings.
    ///
    /// - Parameter context: The model context to use.
    /// - Returns: The `BrowserSettings` instance, or a default instance if not found.
    @MainActor
    static func fetch(in context: ModelContext) -> BrowserSettings {
        let descriptor = FetchDescriptor<BrowserSettings>()
        return (try? context.fetch(descriptor).first) ?? BrowserSettings()
    }

    /// Fetches the existing settings or creates new default settings.
    ///
    /// - Parameter context: The model context to use.
    /// - Returns: The singleton `BrowserSettings` instance.
    @MainActor
    static func fetchOrCreate(in context: ModelContext) -> BrowserSettings {
        let descriptor = FetchDescriptor<BrowserSettings>()

        if let existing = try? context.fetch(descriptor).first {
            return existing
        }

        let settings = BrowserSettings()
        context.insert(settings)
        return settings
    }
}

// MARK: - Appearance Theme

enum AppearanceTheme: String, Codable, CaseIterable {
    case light
    case dark
    case system

    var displayName: String {
        switch self {
        case .light:
            "Light"
        case .dark:
            "Dark"
        case .system:
            "System"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .light:
            .light
        case .dark:
            .dark
        case .system:
            nil
        }
    }
}

// MARK: - Sidebar Mode

/// Display mode for the sidebar when collapsed.
///
/// Controls how the sidebar appears and behaves when not pinned open.
enum SidebarMode: String, Codable, CaseIterable, Sendable {
    /// Sidebar appears as a full overlay on hover.
    ///
    /// The default mode. Shows the complete sidebar with tabs, groups, and all
    /// navigation elements when the cursor enters the activation zone.
    case overlay

    /// Sidebar shows a compact strip with minimal tab information.
    ///
    /// A narrower (60px) always-visible strip showing tab favicons and basic
    /// state. Useful for users who want persistent tab visibility without
    /// the full sidebar taking space.
    case compact

    var displayName: String {
        switch self {
        case .overlay: "Overlay"
        case .compact: "Compact"
        }
    }

    var description: String {
        switch self {
        case .overlay: "Full sidebar appears on hover"
        case .compact: "Narrow strip always visible"
        }
    }
}

// MARK: - AutoFill Mode

/// Mode for the built-in autofill system.
///
/// Controls how Refrax interacts with form fields for credential filling.
enum AutoFillMode: String, Codable, CaseIterable, Sendable {
    /// Autofill is completely disabled.
    ///
    /// No autofill UI appears on any field. Password manager extensions
    /// can work without interference.
    case disabled

    /// Only system pickers are available.
    ///
    /// Shows "Passwords...", "Credit Cards...", and "Contacts..." options
    /// that open macOS system pickers. No credential saving or generation.
    case systemOnly

    /// Full built-in autofill with credential management.
    ///
    /// Shows saved credentials, offers to generate and save passwords,
    /// and includes system picker options.
    case builtIn

    var displayName: String {
        switch self {
        case .disabled: "Disabled"
        case .systemOnly: "System Pickers Only"
        case .builtIn: "Built-in AutoFill"
        }
    }
}

// MARK: - Dark Mode Preference

/// Global preference for forcing dark mode on web pages.
enum DarkModePreference: String, Codable, CaseIterable, Sendable {
    /// Never apply forced dark mode to web pages.
    case off

    /// Apply dark mode when system appearance is dark.
    case followSystem

    /// Always apply dark mode to all web pages.
    case always

    var displayName: String {
        switch self {
        case .off: "Off"
        case .followSystem: "Match System"
        case .always: "Always"
        }
    }
}
