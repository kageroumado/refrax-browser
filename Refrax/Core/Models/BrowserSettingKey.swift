import Foundation

/// Single source of truth for settings metadata.
///
/// Every searchable/controllable browser setting has a case here.
/// Adding a new case forces handling in ``metadata``, ``currentValue(in:)``,
/// and ``setValue(_:in:)`` — the compiler enforces completeness.
enum BrowserSettingKey: String, CaseIterable, Sendable {
    // MARK: - General

    case showSidebarHints
    case spaceSwipeGestureEnabled
    case shiftClickLinkPreviewEnabled
    case showModifierKeyHints
    case autoPiPOnTabSwitch
    case forceNativeVideoControls
    case clipboardLinkMonitoring
    case showCalendarWidget
    case useAria2ForLargeFiles
    case enableBitTorrent
    case ytdlpEnabled
    case ytdlpUseCookies
    case ytdlpDeleteAfterPhotosImport

    // MARK: - Appearance

    case webpageDarkMode
    case pageFilter
    case backgroundRemovalMode
    case preserveMediaInFilter
    case enableSpaceWindowColoring
    case enableWebsiteWindowColoring
    case websiteColorUseSolidBlend

    // MARK: - Tabs

    case showTabPreviews
    case archiveEnabled
    case autoArchiveRulesEnabled
    case enableAutomaticSnapshots
    case badgeDetectionEnabled
    case showTimeSpentInTooltips
    case showUnsavedFormIndicator
    case elementFullscreenMode

    // MARK: - Privacy

    case blockThirdPartyCookies
    case doNotTrack
    case enableGlobalPrivacyControl
    case enableGPCTelemetry
    case enableAutoConsent
    case hideSignInPrompts
    case automaticHistoryCleanup
    case contentProtectionBypassEnabled
    case disableBeforeUnloadAlerts
    case disableScrollHijacking
    case autoFillMode
    case requireAuthForAutoFill

    // MARK: - Advanced

    case enableJavaScript
    case allowJavaScriptWhitelist
    case allowPopups
    case allowSSLCertificateBypass
    case enableAutoCrashRecovery
    case controlAccessMode
}

// MARK: - Metadata

extension BrowserSettingKey {
    var metadata: SettingMetadata {
        switch self {
        // General
        case .showSidebarHints:
            SettingMetadata(
                displayName: "Sidebar Guide",
                description: "Show sidebar guide on empty tab",
                keywords: ["sidebar", "guide", "hints", "getting started", "onboarding"],
                icon: "lightbulb",
                category: .general,
                highlightID: "general.sidebarHints",
                valueKind: .toggle,
            )
        case .spaceSwipeGestureEnabled:
            SettingMetadata(
                displayName: "Space Swipe Gesture",
                description: "Two-finger swipe to switch spaces",
                keywords: ["swipe", "gesture", "spaces", "sidebar"],
                icon: "hand.draw.fill",
                category: .general,
                highlightID: "general.spaceSwipeGesture",
                valueKind: .toggle,
            )
        case .shiftClickLinkPreviewEnabled:
            SettingMetadata(
                displayName: "Shift+Click Link Preview",
                description: "Preview links with Shift+Click",
                keywords: ["shift", "click", "preview", "link", "quick look"],
                icon: "eye.fill",
                category: .general,
                highlightID: "general.shiftClickLinkPreview",
                valueKind: .toggle,
            )
        case .showModifierKeyHints:
            SettingMetadata(
                displayName: "Modifier Key Hints",
                description: "Show hints when holding Option or Shift",
                keywords: ["modifier", "key", "hints", "option", "shift", "overlay"],
                icon: "keyboard",
                category: .general,
                highlightID: "general.modifierKeyHints",
                valueKind: .toggle,
            )
        case .autoPiPOnTabSwitch:
            SettingMetadata(
                displayName: "Auto Picture-in-Picture",
                description: "Float video when switching tabs",
                keywords: ["auto", "pip", "picture in picture", "pip on switch", "floating video", "tab switch"],
                icon: "pip.fill",
                category: .general,
                highlightID: "general.autoPiP",
                valueKind: .toggle,
            )
        case .forceNativeVideoControls:
            SettingMetadata(
                displayName: "Force Native Video Controls",
                description: "Show native video controls on all videos",
                keywords: ["video", "controls", "native", "airplay", "pip"],
                icon: "play.rectangle.fill",
                category: .general,
                highlightID: "general.nativeVideoControls",
                valueKind: .toggle,
            )
        case .clipboardLinkMonitoring:
            SettingMetadata(
                displayName: "Clipboard Link Monitoring",
                description: "Detect links copied to clipboard",
                keywords: ["clipboard", "paste", "url", "toast", "quick open", "link detection", "monitor"],
                icon: "doc.on.clipboard",
                category: .general,
                highlightID: "general.clipboardMonitoring",
                valueKind: .toggle,
            )
        case .showCalendarWidget:
            SettingMetadata(
                displayName: "Calendar Widget",
                description: "Show calendar events in sidebar",
                keywords: ["calendar", "widget", "events", "sidebar", "show calendar", "calendar reminders"],
                icon: "calendar",
                category: .general,
                highlightID: "general.showCalendarWidget",
                valueKind: .toggle,
            )
        case .useAria2ForLargeFiles:
            SettingMetadata(
                displayName: "aria2 Large File Downloads",
                description: "Use aria2 for large file downloads",
                keywords: ["aria2", "download", "large", "multi-connection", "accelerated"],
                icon: "arrow.down.circle.fill",
                category: .general,
                highlightID: "general.aria2",
                valueKind: .toggle,
            )
        case .enableBitTorrent:
            SettingMetadata(
                displayName: "BitTorrent Downloads",
                description: "Handle magnet links and .torrent files",
                keywords: ["bittorrent", "torrent", "magnet", "p2p"],
                icon: "arrow.triangle.2.circlepath",
                category: .general,
                highlightID: "general.bittorrent",
                valueKind: .toggle,
            )
        case .ytdlpEnabled:
            SettingMetadata(
                displayName: "Video Downloads (yt-dlp)",
                description: "Download videos from supported sites",
                keywords: ["yt-dlp", "youtube", "video", "download", "vimeo", "tiktok"],
                icon: "arrow.down.to.line.circle.fill",
                category: .general,
                highlightID: "general.ytdlp",
                valueKind: .toggle,
            )
        case .ytdlpUseCookies:
            SettingMetadata(
                displayName: "Video Download Cookies",
                description: "Export cookies for authenticated downloads",
                keywords: ["yt-dlp", "cookies", "authenticated", "private", "age-restricted"],
                icon: "key.fill",
                category: .general,
                highlightID: "general.ytdlpCookies",
                valueKind: .toggle,
            )
        case .ytdlpDeleteAfterPhotosImport:
            SettingMetadata(
                displayName: "Delete After Photos Import",
                description: "Delete video files after importing to Photos",
                keywords: ["yt-dlp", "photos", "import", "delete", "cleanup"],
                icon: "trash",
                category: .general,
                highlightID: "general.ytdlpDeleteAfterImport",
                valueKind: .toggle,
            )
        // Appearance
        case .webpageDarkMode:
            SettingMetadata(
                displayName: "Dark Mode",
                description: "Force dark colors on webpages",
                keywords: ["night mode", "dark theme", "dark pages", "night theme", "force dark", "dark", "mode", "webpage"],
                icon: "moon.fill",
                category: .appearance,
                highlightID: "appearance.webpageDarkMode",
                valueKind: .picker(["Off", "Match System", "Always"]),
            )
        case .pageFilter:
            SettingMetadata(
                displayName: "Page Filter",
                description: "Apply color filters to pages",
                keywords: ["color filter", "sepia", "grayscale", "invert colors", "accessibility filter", "contrast"],
                icon: "camera.filters",
                category: .appearance,
                highlightID: "appearance.pageFilter",
                valueKind: .picker(["None", "Sepia", "Grayscale", "Invert Colors"]),
            )
        case .backgroundRemovalMode:
            SettingMetadata(
                displayName: "Background Removal",
                description: "Remove or simplify page backgrounds",
                keywords: ["background", "remove", "simplify", "transparent", "vibrancy"],
                icon: "rectangle.dashed",
                category: .appearance,
                highlightID: "appearance.backgroundRemoval",
                valueKind: .picker(["None", "Remove Images", "Simplify", "Transparent"]),
            )
        case .preserveMediaInFilter:
            SettingMetadata(
                displayName: "Preserve Media in Filters",
                description: "Keep original colors for images and videos when using filters",
                keywords: ["preserve", "media", "images", "videos", "filter"],
                icon: "photo",
                category: .appearance,
                highlightID: "appearance.preserveMedia",
                valueKind: .toggle,
            )
        case .enableSpaceWindowColoring:
            SettingMetadata(
                displayName: "Space Window Coloring",
                description: "Tint window based on space color",
                keywords: ["space", "spaces", "coloring", "background", "tint"],
                icon: "paintpalette.fill",
                category: .appearance,
                highlightID: "appearance.spaceColoring",
                valueKind: .toggle,
            )
        case .enableWebsiteWindowColoring:
            SettingMetadata(
                displayName: "Website Window Coloring",
                description: "Tint window based on website theme color",
                keywords: ["website", "theme", "color", "coloring", "background", "tint"],
                icon: "globe",
                category: .appearance,
                highlightID: "appearance.websiteColoring",
                valueKind: .toggle,
            )
        case .websiteColorUseSolidBlend:
            SettingMetadata(
                displayName: "Website Solid Blend",
                description: "Use solid blend for website colors",
                keywords: ["website", "solid", "blend", "color", "overlay"],
                icon: "square.filled.on.square",
                category: .appearance,
                highlightID: "appearance.websiteSolidBlend",
                valueKind: .toggle,
            )
        // Tabs
        case .showTabPreviews:
            SettingMetadata(
                displayName: "Tab Previews",
                description: "Show thumbnail previews on hover",
                keywords: ["tab thumbnails", "preview tabs", "tab preview", "hover preview", "tabs", "previews"],
                icon: "rectangle.split.3x1",
                category: .tabs,
                highlightID: "tabs.showPreviews",
                valueKind: .toggle,
            )
        case .archiveEnabled:
            SettingMetadata(
                displayName: "Tab Archive",
                description: "Move closed tabs to archive instead of deleting",
                keywords: ["archive", "trash", "close", "tabs", "recovery"],
                icon: "archivebox.fill",
                category: .tabs,
                highlightID: "tabs.archiveEnabled",
                valueKind: .toggle,
            )
        case .autoArchiveRulesEnabled:
            SettingMetadata(
                displayName: "Auto-Archive Rules",
                description: "Automatically archive tabs based on rules",
                keywords: ["auto", "archive", "rules", "automatic", "inactivity", "limit"],
                icon: "clock.arrow.circlepath",
                category: .tabs,
                highlightID: "tabs.autoArchiveRules",
                valueKind: .toggle,
            )
        case .enableAutomaticSnapshots:
            SettingMetadata(
                displayName: "Automatic Snapshots",
                description: "Periodically save tab snapshots",
                keywords: ["snapshot", "backup", "automatic", "restore"],
                icon: "camera.fill",
                category: .tabs,
                highlightID: "tabs.snapshots",
                valueKind: .toggle,
            )
        case .badgeDetectionEnabled:
            SettingMetadata(
                displayName: "Badge Detection",
                description: "Detect notification badges in page titles",
                keywords: ["badge", "notification", "unread", "count", "title"],
                icon: "bell.badge.fill",
                category: .tabs,
                highlightID: "tabs.badgeDetection",
                valueKind: .toggle,
            )
        case .showTimeSpentInTooltips:
            SettingMetadata(
                displayName: "Time Spent in Tooltips",
                description: "Show domain time in tab tooltips",
                keywords: ["time", "spent", "tooltip", "tracking", "domain"],
                icon: "clock.fill",
                category: .tabs,
                highlightID: "tabs.showTimeInTooltips",
                valueKind: .toggle,
            )
        case .showUnsavedFormIndicator:
            SettingMetadata(
                displayName: "Unsaved Form Indicator",
                description: "Show indicator for tabs with unsaved forms",
                keywords: ["unsaved", "form", "indicator", "pencil", "data"],
                icon: "pencil.circle.fill",
                category: .tabs,
                highlightID: "tabs.unsavedFormIndicator",
                valueKind: .toggle,
            )
        case .elementFullscreenMode:
            SettingMetadata(
                displayName: "Video Fullscreen Mode",
                description: "Where videos go when they enter fullscreen",
                keywords: ["fullscreen", "video", "in-window", "in-tab", "windowed", "floating", "pip"],
                icon: "rectangle.inset.filled",
                category: .tabs,
                highlightID: "tabs.inWindowFullscreen",
                valueKind: .picker(FullscreenPresentationMode.allCases.map(\.rawValue)),
            )
        // Privacy
        case .blockThirdPartyCookies:
            SettingMetadata(
                displayName: "Block Third-Party Cookies",
                description: "Prevent cross-site tracking",
                keywords: ["block cookies", "cookie blocking", "third party cookies", "tracking cookies", "cookies"],
                icon: "hand.raised.fill",
                category: .privacy,
                highlightID: "privacy.thirdPartyCookies",
                valueKind: .toggle,
            )
        case .doNotTrack:
            SettingMetadata(
                displayName: "Do Not Track",
                description: "Request sites not to track you",
                keywords: ["dnt", "tracking", "privacy", "no tracking", "header"],
                icon: "hand.raised.fill",
                category: .privacy,
                highlightID: "privacy.doNotTrack",
                valueKind: .toggle,
            )
        case .enableGlobalPrivacyControl:
            SettingMetadata(
                displayName: "Global Privacy Control",
                description: "Send GPC signals to websites",
                keywords: ["gpc", "global privacy control", "tracking", "header", "sec-gpc"],
                icon: "shield.lefthalf.filled",
                category: .privacy,
                highlightID: "privacy.gpc",
                valueKind: .toggle,
            )
        case .enableGPCTelemetry:
            SettingMetadata(
                displayName: "GPC Telemetry",
                description: "Log when sites read GPC signal",
                keywords: ["gpc", "telemetry", "logging", "privacy", "debug"],
                icon: "chart.bar.fill",
                category: .privacy,
                highlightID: "privacy.gpcTelemetry",
                valueKind: .toggle,
            )
        case .enableAutoConsent:
            SettingMetadata(
                displayName: "Auto-Consent Cookie Popups",
                description: "Automatically dismiss cookie banners",
                keywords: ["cookie consent", "gdpr", "cookie popup", "auto consent", "auto dismiss cookies", "banner"],
                icon: "checkmark.shield.fill",
                category: .privacy,
                highlightID: "privacy.autoConsent",
                valueKind: .toggle,
            )
        case .hideSignInPrompts:
            SettingMetadata(
                displayName: "Hide Sign-In Prompts",
                description: "Hide sign-in with Google and similar prompts",
                keywords: ["sign in", "google", "prompts", "banners", "hide"],
                icon: "eye.slash.fill",
                category: .privacy,
                highlightID: "privacy.hideSignInPrompts",
                valueKind: .toggle,
            )
        case .automaticHistoryCleanup:
            SettingMetadata(
                displayName: "Auto-Delete Old History",
                description: "Automatically delete history after retention period",
                keywords: ["history", "auto", "delete", "cleanup", "retention"],
                icon: "trash.fill",
                category: .privacy,
                highlightID: "privacy.autoDeleteHistory",
                valueKind: .toggle,
            )
        case .contentProtectionBypassEnabled:
            SettingMetadata(
                displayName: "Content Protection Bypass",
                description: "Allow text selection and copying on all sites",
                keywords: ["copy", "select", "text", "protection", "bypass", "right-click"],
                icon: "doc.on.doc.fill",
                category: .privacy,
                highlightID: "privacy.contentProtection",
                valueKind: .toggle,
            )
        case .disableBeforeUnloadAlerts:
            SettingMetadata(
                displayName: "Block Page Leave Alerts",
                description: "Block 'Are you sure you want to leave?' dialogs",
                keywords: ["leave", "alert", "beforeunload", "confirm", "dialog"],
                icon: "xmark.shield.fill",
                category: .privacy,
                highlightID: "privacy.beforeUnloadAlerts",
                valueKind: .toggle,
            )
        case .disableScrollHijacking:
            SettingMetadata(
                displayName: "Disable Scroll Hijacking",
                description: "Use native scrolling on all sites",
                keywords: ["scroll", "hijacking", "smooth", "native"],
                icon: "arrow.up.arrow.down",
                category: .privacy,
                highlightID: "privacy.scrollHijacking",
                valueKind: .toggle,
            )
        case .autoFillMode:
            SettingMetadata(
                displayName: "Passwords & AutoFill",
                description: "How passwords and form data are filled",
                keywords: ["passwords", "autofill", "credentials", "keychain", "login", "sign in", "fill"],
                icon: "key.fill",
                category: .privacy,
                highlightID: "privacy.autofill",
                valueKind: .picker(AutoFillMode.allCases.map(\.displayName)),
            )
        case .requireAuthForAutoFill:
            SettingMetadata(
                displayName: "Require Touch ID to AutoFill",
                description: "Authenticate before filling saved passwords",
                keywords: ["touch id", "touchid", "biometric", "authenticate", "passwords", "autofill", "security"],
                icon: "touchid",
                category: .privacy,
                highlightID: "privacy.requireAuthAutoFill",
                valueKind: .toggle,
            )
        // Advanced
        case .enableJavaScript:
            SettingMetadata(
                displayName: "JavaScript",
                description: "Enable JavaScript on pages",
                keywords: ["js", "javascript", "scripts", "enable javascript", "disable javascript", "web", "content"],
                icon: "curlybraces",
                category: .advanced,
                highlightID: "advanced.javascript",
                valueKind: .toggle,
            )
        case .allowJavaScriptWhitelist:
            SettingMetadata(
                displayName: "JavaScript Site Whitelist",
                description: "Allow per-site JavaScript overrides",
                keywords: ["javascript", "js", "whitelist", "exceptions", "per-site"],
                icon: "list.bullet",
                category: .advanced,
                highlightID: "advanced.javascriptWhitelist",
                valueKind: .toggle,
            )
        case .allowPopups:
            SettingMetadata(
                displayName: "Allow Pop-ups",
                description: "Allow sites to open popup windows",
                keywords: ["popups", "pop-ups", "windows", "block popups"],
                icon: "rectangle.on.rectangle",
                category: .advanced,
                highlightID: "advanced.popups",
                valueKind: .toggle,
            )
        case .allowSSLCertificateBypass:
            SettingMetadata(
                displayName: "SSL Certificate Bypass",
                description: "Allow bypassing invalid SSL certificates",
                keywords: ["ssl", "certificate", "bypass", "security", "https"],
                icon: "lock.open.fill",
                category: .advanced,
                highlightID: "advanced.sslBypass",
                valueKind: .toggle,
            )
        case .enableAutoCrashRecovery:
            SettingMetadata(
                displayName: "Auto Crash Recovery",
                description: "Automatically reload crashed tabs",
                keywords: ["crash", "recovery", "reload", "automatic"],
                icon: "arrow.clockwise",
                category: .advanced,
                highlightID: "advanced.crashRecovery",
                valueKind: .toggle,
            )
        case .controlAccessMode:
            SettingMetadata(
                displayName: "Control Server Access",
                description: "Who can control the browser via CLI",
                keywords: ["control", "server", "cli", "refrax-ctl", "socket", "access", "security", "automation"],
                icon: "lock.shield.fill",
                category: .advanced,
                highlightID: "advanced.controlAccess",
                valueKind: .picker(ControlAccessMode.allCases.map(\.displayName)),
            )
        }
    }
}

// MARK: - Value Access

extension BrowserSettingKey {
    /// Reads the current value from ``BrowserSettings``.
    func currentValue(in settings: BrowserSettings) -> SettingValue {
        switch self {
        // General
        case .showSidebarHints: .bool(settings.showSidebarHints)
        case .spaceSwipeGestureEnabled: .bool(settings.spaceSwipeGestureEnabled)
        case .shiftClickLinkPreviewEnabled: .bool(settings.shiftClickLinkPreviewEnabled)
        case .showModifierKeyHints: .bool(settings.showModifierKeyHints)
        case .autoPiPOnTabSwitch: .bool(settings.autoPiPOnTabSwitch)
        case .forceNativeVideoControls: .bool(settings.forceNativeVideoControls)
        case .clipboardLinkMonitoring: .bool(settings.clipboardLinkMonitoring)
        case .showCalendarWidget: .bool(settings.showCalendarWidget)
        case .useAria2ForLargeFiles: .bool(settings.useAria2ForLargeFiles)
        case .enableBitTorrent: .bool(settings.enableBitTorrent)
        case .ytdlpEnabled: .bool(settings.ytdlpEnabled)
        case .ytdlpUseCookies: .bool(settings.ytdlpUseCookies)
        case .ytdlpDeleteAfterPhotosImport: .bool(settings.ytdlpDeleteAfterPhotosImport)
        // Appearance
        case .webpageDarkMode: .string(settings.webpageDarkMode.displayName)
        case .pageFilter: .string(settings.pageFilter.displayName)
        case .backgroundRemovalMode: .string(settings.backgroundRemovalMode.displayName)
        case .preserveMediaInFilter: .bool(settings.preserveMediaInFilter)
        case .enableSpaceWindowColoring: .bool(settings.enableSpaceWindowColoring)
        case .enableWebsiteWindowColoring: .bool(settings.enableWebsiteWindowColoring)
        case .websiteColorUseSolidBlend: .bool(settings.websiteColorUseSolidBlend)
        // Tabs
        case .showTabPreviews: .bool(settings.showTabPreviews)
        case .archiveEnabled: .bool(settings.archiveEnabled)
        case .autoArchiveRulesEnabled: .bool(settings.autoArchiveRulesEnabled)
        case .enableAutomaticSnapshots: .bool(settings.enableAutomaticSnapshots)
        case .badgeDetectionEnabled: .bool(settings.badgeDetectionEnabled)
        case .showTimeSpentInTooltips: .bool(settings.showTimeSpentInTooltips)
        case .showUnsavedFormIndicator: .bool(settings.showUnsavedFormIndicator)
        case .elementFullscreenMode: .string(settings.elementFullscreenMode.rawValue)
        // Privacy
        case .blockThirdPartyCookies: .bool(settings.blockThirdPartyCookies)
        case .doNotTrack: .bool(settings.doNotTrack)
        case .enableGlobalPrivacyControl: .bool(settings.enableGlobalPrivacyControl)
        case .enableGPCTelemetry: .bool(settings.enableGPCTelemetry)
        case .enableAutoConsent: .bool(settings.enableAutoConsent)
        case .hideSignInPrompts: .bool(settings.hideSignInPrompts)
        case .automaticHistoryCleanup: .bool(settings.automaticHistoryCleanup)
        case .contentProtectionBypassEnabled: .bool(settings.contentProtectionBypassEnabled)
        case .disableBeforeUnloadAlerts: .bool(settings.disableBeforeUnloadAlerts)
        case .disableScrollHijacking: .bool(settings.disableScrollHijacking)
        case .autoFillMode: .string(settings.autoFillMode.displayName)
        case .requireAuthForAutoFill: .bool(settings.requireAuthForAutoFill)
        // Advanced
        case .enableJavaScript: .bool(settings.enableJavaScript)
        case .allowJavaScriptWhitelist: .bool(settings.allowJavaScriptWhitelist)
        case .allowPopups: .bool(settings.allowPopups)
        case .allowSSLCertificateBypass: .bool(settings.allowSSLCertificateBypass)
        case .enableAutoCrashRecovery: .bool(settings.enableAutoCrashRecovery)
        case .controlAccessMode: .string(settings.controlAccessMode.displayName)
        }
    }

    /// Writes a value to ``BrowserSettings``.
    func setValue(_ value: SettingValue, in settings: BrowserSettings) {
        switch self {
        // General
        case .showSidebarHints:
            if case let .bool(v) = value { settings.showSidebarHints = v }
        case .spaceSwipeGestureEnabled:
            if case let .bool(v) = value { settings.spaceSwipeGestureEnabled = v }
        case .shiftClickLinkPreviewEnabled:
            if case let .bool(v) = value { settings.shiftClickLinkPreviewEnabled = v }
        case .showModifierKeyHints:
            if case let .bool(v) = value { settings.showModifierKeyHints = v }
        case .autoPiPOnTabSwitch:
            if case let .bool(v) = value { settings.autoPiPOnTabSwitch = v }
        case .forceNativeVideoControls:
            if case let .bool(v) = value { settings.forceNativeVideoControls = v }
        case .clipboardLinkMonitoring:
            if case let .bool(v) = value { settings.clipboardLinkMonitoring = v }
        case .showCalendarWidget:
            if case let .bool(v) = value { settings.showCalendarWidget = v }
        case .useAria2ForLargeFiles:
            if case let .bool(v) = value { settings.useAria2ForLargeFiles = v }
        case .enableBitTorrent:
            if case let .bool(v) = value { settings.enableBitTorrent = v }
        case .ytdlpEnabled:
            if case let .bool(v) = value { settings.ytdlpEnabled = v }
        case .ytdlpUseCookies:
            if case let .bool(v) = value { settings.ytdlpUseCookies = v }
        case .ytdlpDeleteAfterPhotosImport:
            if case let .bool(v) = value { settings.ytdlpDeleteAfterPhotosImport = v }
        // Appearance
        case .webpageDarkMode:
            if case let .string(v) = value {
                if let pref = DarkModePreference.allCases.first(where: { $0.displayName == v || $0.rawValue == v }) {
                    settings.webpageDarkMode = pref
                }
            }
        case .pageFilter:
            if case let .string(v) = value {
                if let filter = PageFilter.allCases.first(where: { $0.displayName == v || $0.rawValue == v }) {
                    settings.pageFilter = filter
                }
            }
        case .backgroundRemovalMode:
            if case let .string(v) = value {
                if let mode = BackgroundRemovalMode.allCases.first(where: { $0.displayName == v || $0.rawValue == v }) {
                    settings.backgroundRemovalMode = mode
                }
            }
        case .preserveMediaInFilter:
            if case let .bool(v) = value { settings.preserveMediaInFilter = v }
        case .enableSpaceWindowColoring:
            if case let .bool(v) = value { settings.enableSpaceWindowColoring = v }
        case .enableWebsiteWindowColoring:
            if case let .bool(v) = value { settings.enableWebsiteWindowColoring = v }
        case .websiteColorUseSolidBlend:
            if case let .bool(v) = value { settings.websiteColorUseSolidBlend = v }
        // Tabs
        case .showTabPreviews:
            if case let .bool(v) = value { settings.showTabPreviews = v }
        case .archiveEnabled:
            if case let .bool(v) = value { settings.archiveEnabled = v }
        case .autoArchiveRulesEnabled:
            if case let .bool(v) = value { settings.autoArchiveRulesEnabled = v }
        case .enableAutomaticSnapshots:
            if case let .bool(v) = value { settings.enableAutomaticSnapshots = v }
        case .badgeDetectionEnabled:
            if case let .bool(v) = value { settings.badgeDetectionEnabled = v }
        case .showTimeSpentInTooltips:
            if case let .bool(v) = value { settings.showTimeSpentInTooltips = v }
        case .showUnsavedFormIndicator:
            if case let .bool(v) = value { settings.showUnsavedFormIndicator = v }
        case .elementFullscreenMode:
            if case let .string(v) = value, let mode = FullscreenPresentationMode(rawValue: v) {
                settings.elementFullscreenMode = mode
            }
        // Privacy
        case .blockThirdPartyCookies:
            if case let .bool(v) = value { settings.blockThirdPartyCookies = v }
        case .doNotTrack:
            if case let .bool(v) = value { settings.doNotTrack = v }
        case .enableGlobalPrivacyControl:
            if case let .bool(v) = value { settings.enableGlobalPrivacyControl = v }
        case .enableGPCTelemetry:
            if case let .bool(v) = value { settings.enableGPCTelemetry = v }
        case .enableAutoConsent:
            if case let .bool(v) = value { settings.enableAutoConsent = v }
        case .hideSignInPrompts:
            if case let .bool(v) = value { settings.hideSignInPrompts = v }
        case .automaticHistoryCleanup:
            if case let .bool(v) = value { settings.automaticHistoryCleanup = v }
        case .contentProtectionBypassEnabled:
            if case let .bool(v) = value { settings.contentProtectionBypassEnabled = v }
        case .disableBeforeUnloadAlerts:
            if case let .bool(v) = value { settings.disableBeforeUnloadAlerts = v }
        case .disableScrollHijacking:
            if case let .bool(v) = value { settings.disableScrollHijacking = v }
        case .autoFillMode:
            if case let .string(v) = value {
                if let mode = AutoFillMode.allCases.first(where: { $0.displayName == v || $0.rawValue == v }) {
                    settings.autoFillMode = mode
                }
            }
        case .requireAuthForAutoFill:
            if case let .bool(v) = value { settings.requireAuthForAutoFill = v }
        // Advanced
        case .enableJavaScript:
            if case let .bool(v) = value { settings.enableJavaScript = v }
        case .allowJavaScriptWhitelist:
            if case let .bool(v) = value { settings.allowJavaScriptWhitelist = v }
        case .allowPopups:
            if case let .bool(v) = value { settings.allowPopups = v }
        case .allowSSLCertificateBypass:
            if case let .bool(v) = value { settings.allowSSLCertificateBypass = v }
        case .enableAutoCrashRecovery:
            if case let .bool(v) = value { settings.enableAutoCrashRecovery = v }
        case .controlAccessMode:
            if case let .string(v) = value {
                if let mode = ControlAccessMode.allCases.first(where: { $0.displayName == v || $0.rawValue == v }) {
                    settings.controlAccessMode = mode
                }
            }
        }
    }

    /// Toggles or cycles the setting value.
    ///
    /// For `.toggle` settings, flips the boolean.
    /// For `.picker` settings, cycles to the next value.
    func toggle(in settings: BrowserSettings) {
        switch self {
        // Picker settings — cycle through values
        case .webpageDarkMode:
            switch settings.webpageDarkMode {
            case .off: settings.webpageDarkMode = .followSystem
            case .followSystem: settings.webpageDarkMode = .always
            case .always: settings.webpageDarkMode = .off
            }
        case .pageFilter:
            switch settings.pageFilter {
            case .none: settings.pageFilter = .sepia
            case .sepia: settings.pageFilter = .grayscale
            case .grayscale: settings.pageFilter = .invertColors
            case .invertColors: settings.pageFilter = .none
            default: settings.pageFilter = .none
            }
        case .backgroundRemovalMode:
            switch settings.backgroundRemovalMode {
            case .none: settings.backgroundRemovalMode = .removeImages
            case .removeImages: settings.backgroundRemovalMode = .simplify
            case .simplify: settings.backgroundRemovalMode = .transparent
            case .transparent: settings.backgroundRemovalMode = .none
            }
        case .controlAccessMode:
            switch settings.controlAccessMode {
            case .off: settings.controlAccessMode = .prompt
            case .prompt: settings.controlAccessMode = .open
            case .open: settings.controlAccessMode = .off
            }
        case .autoFillMode:
            switch settings.autoFillMode {
            case .disabled: settings.autoFillMode = .systemOnly
            case .systemOnly: settings.autoFillMode = .builtIn
            case .builtIn: settings.autoFillMode = .disabled
            }
        // All toggle settings — flip the bool
        default:
            if case let .bool(current) = currentValue(in: settings) {
                setValue(.bool(!current), in: settings)
            }
        }
    }

    /// Returns the current value as a human-readable display string.
    func displayValue(in settings: BrowserSettings) -> String {
        switch currentValue(in: settings) {
        case let .bool(v): v ? "On" : "Off"
        case let .string(v): v
        case let .int(v): "\(v)"
        case let .double(v): "\(v)"
        }
    }
}

// MARK: - Supporting Types

/// Metadata for a registrable browser setting.
struct SettingMetadata: Sendable {
    let displayName: String
    let description: String
    let keywords: [String]
    let icon: String
    let category: SettingsCategory
    let highlightID: String
    let valueKind: SettingValueKind
}

/// How a setting's value is controlled.
enum SettingValueKind: Sendable {
    /// Boolean — can toggle inline.
    case toggle
    /// Enum with fixed options — cycles through values.
    case picker([String])
    /// Complex setting — navigate to settings view only.
    case navigateOnly
}

/// A typed setting value for read/write.
enum SettingValue: Sendable {
    case bool(Bool)
    case string(String)
    case int(Int)
    case double(Double)
}
