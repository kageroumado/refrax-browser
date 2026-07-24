import CloudKit
import SwiftData

extension BrowserSettings: Syncable {
    nonisolated static var ckRecordType: String { "BrowserSettings" }

    /// Well-known record name for the singleton BrowserSettings record.
    ///
    /// Since BrowserSettings is a singleton (no UUID `id`), we use a fixed
    /// record name so all devices converge on the same CKRecord.
    static let singletonRecordName = "BrowserSettings-Singleton"

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // MARK: - Search

        record["searchEngineID"] = searchEngineID as NSString?

        // MARK: - Appearance: Theme

        record["themeRawValue"] = themeRawValue as NSString
        record["customAccentColorHex"] = customAccentColorHex as NSString?

        // MARK: - Appearance: Window Background

        record["customWindowBackgroundColorHex"] = customWindowBackgroundColorHex as NSString?
        record["windowBackgroundMixAmount"] = windowBackgroundMixAmount as NSNumber
        record["windowBackgroundMixModeRawValue"] = windowBackgroundMixModeRawValue as NSString
        record["enableSpaceWindowColoring"] = enableSpaceWindowColoring as NSNumber
        record["enableWebsiteWindowColoring"] = enableWebsiteWindowColoring as NSNumber
        record["windowBackgroundFillOpacity"] = windowBackgroundFillOpacity as NSNumber
        record["websiteColorUseSolidBlend"] = websiteColorUseSolidBlend as NSNumber

        // MARK: - Appearance: Sidebar

        record["defaultSidebarModeRaw"] = defaultSidebarModeRaw as NSString

        // MARK: - Appearance: Page

        record["webpageDarkModeRaw"] = webpageDarkModeRaw as NSString
        record["pageFilterRaw"] = pageFilterRaw as NSString
        record["preserveMediaInFilter"] = preserveMediaInFilter as NSNumber
        record["backgroundRemovalModeRaw"] = backgroundRemovalModeRaw as NSString

        // MARK: - Tabs: Previews

        record["showTabPreviews"] = showTabPreviews as NSNumber

        // MARK: - Tabs: Archive

        record["archiveEnabled"] = archiveEnabled as NSNumber
        record["archiveClearHours"] = archiveClearHours as NSNumber?
        record["autoArchiveRulesEnabled"] = autoArchiveRulesEnabled as NSNumber

        // MARK: - Tabs: Snapshots

        record["enableAutomaticSnapshots"] = enableAutomaticSnapshots as NSNumber
        record["snapshotRetentionDays"] = snapshotRetentionDays as NSNumber
        record["maxSnapshotCount"] = maxSnapshotCount as NSNumber

        // MARK: - Tabs: Video

        record["inWindowFullscreenEnabled"] = inWindowFullscreenEnabled as NSNumber?

        // MARK: - Tabs: Notifications

        record["badgeDetectionEnabled"] = badgeDetectionEnabled as NSNumber

        // MARK: - Tabs: Time Tracking

        record["showTimeSpentInTooltips"] = showTimeSpentInTooltips as NSNumber

        // MARK: - Tabs: Indicators

        record["showUnsavedFormIndicator"] = showUnsavedFormIndicator as NSNumber

        // MARK: - Favorites

        record["enabledAppShortcutsRaw"] = enabledAppShortcutsRaw as NSString
        record["appShortcutColorsJSON"] = appShortcutColorsJSON as NSString
        record["appShortcutNamesJSON"] = appShortcutNamesJSON as NSString

        // MARK: - Privacy: Tracking Protection

        record["blockThirdPartyCookies"] = blockThirdPartyCookies as NSNumber
        record["doNotTrack"] = doNotTrack as NSNumber
        record["enableGlobalPrivacyControl"] = enableGlobalPrivacyControl as NSNumber
        record["enableGPCTelemetry"] = enableGPCTelemetry as NSNumber
        record["enableAutoConsent"] = enableAutoConsent as NSNumber
        record["hideSignInPrompts"] = hideSignInPrompts as NSNumber

        // MARK: - Privacy: History

        record["automaticHistoryCleanup"] = automaticHistoryCleanup as NSNumber
        record["historyRetentionDays"] = historyRetentionDays as NSNumber

        // MARK: - Privacy: Space Locking

        record["defaultLockTimeout"] = defaultLockTimeout as NSNumber

        // MARK: - Getting Started

        record["showSidebarHints"] = showSidebarHints as NSNumber

        // MARK: - Browsing: Gestures

        record["spaceSwipeGestureEnabled"] = spaceSwipeGestureEnabled as NSNumber

        // MARK: - Browsing: Link Previews

        record["shiftClickLinkPreviewEnabled"] = shiftClickLinkPreviewEnabled as NSNumber
        record["showModifierKeyHints"] = showModifierKeyHints as NSNumber

        // MARK: - Browsing: Media

        record["autoPiPOnTabSwitch"] = autoPiPOnTabSwitch as NSNumber
        record["forceNativeVideoControls"] = forceNativeVideoControls as NSNumber
        record["defaultVideoSpeed"] = defaultVideoSpeed as NSNumber

        // MARK: - Browsing: Web Behavior

        record["disableBeforeUnloadAlerts"] = disableBeforeUnloadAlerts as NSNumber
        record["disableScrollHijacking"] = disableScrollHijacking as NSNumber
        record["contentProtectionBypassEnabled"] = contentProtectionBypassEnabled as NSNumber

        // MARK: - Browsing: Mail Handler

        record["preferredMailHandlerRaw"] = preferredMailHandlerRaw as NSString

        // MARK: - Browsing: AutoFill

        record["autoFillModeRaw"] = autoFillModeRaw as NSString
        record["requireAuthForAutoFill"] = requireAuthForAutoFill as NSNumber

        // MARK: - Browsing: Clipboard

        record["clipboardLinkMonitoring"] = clipboardLinkMonitoring as NSNumber

        // MARK: - Downloads

        record["customDownloadDirectory"] = customDownloadDirectory as NSString?

        // MARK: - Downloads: aria2

        record["useAria2ForLargeFiles"] = useAria2ForLargeFiles as NSNumber
        record["aria2ThresholdMB"] = aria2ThresholdMB as NSNumber
        record["enableBitTorrent"] = enableBitTorrent as NSNumber

        // MARK: - Downloads: yt-dlp

        record["ytdlpEnabled"] = ytdlpEnabled as NSNumber
        record["ytdlpUseCookies"] = ytdlpUseCookies as NSNumber
        record["ytdlpDeleteAfterPhotosImport"] = ytdlpDeleteAfterPhotosImport as NSNumber

        // MARK: - Agent Chat

        record["agentEnabled"] = agentEnabled as NSNumber
        record["agentSessionKey"] = agentSessionKey as NSString
        record["agentAutoIncludeContext"] = agentAutoIncludeContext as NSNumber
        record["agentProviderKindRaw"] = agentProviderKind.rawValue as NSString
        record["agentClaudeModel"] = agentClaudeModel as NSString
        record["agentClaudeMaxTokens"] = agentClaudeMaxTokens as NSNumber
        record["agentOpenAIModel"] = agentOpenAIModel as NSString
        record["agentOpenRouterModel"] = agentOpenRouterModel as NSString
        record["agentCustomModel"] = agentCustomModel as NSString
        record["agentCustomBaseURL"] = agentCustomBaseURL as NSString
        record["agentCustomRequiresAuth"] = agentCustomRequiresAuth as NSNumber
        record["agentOpenAIMaxTokens"] = agentOpenAIMaxTokens as NSNumber
        record["agentDisplayName"] = agentDisplayName as NSString
        record["agentAvatarData"] = agentAvatarData as NSData?

        // MARK: - Widgets: Calendar

        record["showCalendarWidget"] = showCalendarWidget as NSNumber
        record["calendarLookAheadHours"] = calendarLookAheadHours as NSNumber
        record["calendarAutoExpandOnImminent"] = calendarAutoExpandOnImminent as NSNumber
        record["enabledCalendarIDsJSON"] = enabledCalendarIDsJSON as NSString

        // MARK: - Widgets: Speed Reader

        record["speedReaderWPM"] = speedReaderWPM as NSNumber
        record["speedReaderResumePositionsJSON"] = speedReaderResumePositionsJSON as NSString

        // MARK: - Advanced: JavaScript

        record["enableJavaScript"] = enableJavaScript as NSNumber
        record["allowJavaScriptWhitelist"] = allowJavaScriptWhitelist as NSNumber

        // MARK: - Advanced: Windows

        record["allowPopups"] = allowPopups as NSNumber

        // MARK: - Advanced: Control Server

        record["controlAccessModeRaw"] = controlAccessModeRaw as NSString
        record["allowedControlClientsJSON"] = allowedControlClientsJSON as NSString

        // MARK: - Advanced: Security

        record["allowSSLCertificateBypass"] = allowSSLCertificateBypass as NSNumber

        // MARK: - Advanced: Crash Recovery

        record["crashThreshold"] = crashThreshold as NSNumber
        record["crashTimeWindowSeconds"] = crashTimeWindowSeconds as NSNumber
        record["enableAutoCrashRecovery"] = enableAutoCrashRecovery as NSNumber

        // MARK: - Feedback

        record["feedbackName"] = feedbackName as NSString
        record["feedbackEmail"] = feedbackEmail as NSString
        record["verboseLoggingEnabled"] = verboseLoggingEnabled as NSNumber

        // MARK: - Updates

        record["checkForUpdatesAutomatically"] = checkForUpdatesAutomatically as NSNumber

        // MARK: - Activation & Telemetry

        record["isActivated"] = isActivated as NSNumber
        record["activationCode"] = activationCode as NSString?
        record["hasCompletedOnboarding"] = hasCompletedOnboarding as NSNumber
        record["hasRunOnboardingMigration"] = hasRunOnboardingMigration as NSNumber
        record["telemetryEnabled"] = telemetryEnabled as NSNumber
        record["lastHeartbeatDate"] = lastHeartbeatDate as NSDate?

        // PrivacyProtectionSettings is synced independently — not followed here.
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> BrowserSettings {
        // Singleton: always update the existing instance rather than creating a new one.
        // Inlined from fetchOrCreate to avoid @MainActor requirement.
        let descriptor = FetchDescriptor<BrowserSettings>()
        let settings: BrowserSettings
        if let existing = try? context.fetch(descriptor).first {
            settings = existing
        } else {
            let newSettings = BrowserSettings()
            context.insert(newSettings)
            settings = newSettings
        }

        // MARK: - Search

        settings.searchEngineID = record["searchEngineID"] as? String

        // MARK: - Appearance: Theme

        settings.themeRawValue = record["themeRawValue"] as? String
            ?? AppearanceTheme.system.rawValue
        settings.customAccentColorHex = record["customAccentColorHex"] as? String

        // MARK: - Appearance: Window Background

        settings.customWindowBackgroundColorHex = record["customWindowBackgroundColorHex"] as? String
        settings.windowBackgroundMixAmount = (record["windowBackgroundMixAmount"] as? Double)
            ?? Defaults.windowBackgroundMixAmount
        settings.windowBackgroundMixModeRawValue = record["windowBackgroundMixModeRawValue"] as? String
            ?? Defaults.windowBackgroundMixMode.rawValue
        settings.enableSpaceWindowColoring = (record["enableSpaceWindowColoring"] as? Bool) ?? false
        settings.enableWebsiteWindowColoring = (record["enableWebsiteWindowColoring"] as? Bool) ?? false
        settings.windowBackgroundFillOpacity = (record["windowBackgroundFillOpacity"] as? Double)
            ?? Defaults.windowBackgroundFillOpacity
        settings.websiteColorUseSolidBlend = (record["websiteColorUseSolidBlend"] as? Bool) ?? true

        // MARK: - Appearance: Sidebar

        settings.defaultSidebarModeRaw = record["defaultSidebarModeRaw"] as? String
            ?? SidebarMode.compact.rawValue

        // MARK: - Appearance: Page

        settings.webpageDarkModeRaw = record["webpageDarkModeRaw"] as? String
            ?? DarkModePreference.off.rawValue
        settings.pageFilterRaw = record["pageFilterRaw"] as? String
            ?? PageFilter.none.rawValue
        settings.preserveMediaInFilter = (record["preserveMediaInFilter"] as? Bool) ?? true
        settings.backgroundRemovalModeRaw = record["backgroundRemovalModeRaw"] as? String
            ?? BackgroundRemovalMode.none.rawValue

        // MARK: - Tabs: Previews

        settings.showTabPreviews = (record["showTabPreviews"] as? Bool) ?? false

        // MARK: - Tabs: Archive

        settings.archiveEnabled = (record["archiveEnabled"] as? Bool) ?? false
        settings.archiveClearHours = record["archiveClearHours"] as? Int
        settings.autoArchiveRulesEnabled = (record["autoArchiveRulesEnabled"] as? Bool) ?? false

        // MARK: - Tabs: Snapshots

        settings.enableAutomaticSnapshots = (record["enableAutomaticSnapshots"] as? Bool) ?? true
        settings.snapshotRetentionDays = (record["snapshotRetentionDays"] as? Int) ?? 30
        settings.maxSnapshotCount = (record["maxSnapshotCount"] as? Int) ?? 200

        // MARK: - Tabs: Video

        settings.inWindowFullscreenEnabled = record["inWindowFullscreenEnabled"] as? Bool

        // MARK: - Tabs: Notifications

        settings.badgeDetectionEnabled = (record["badgeDetectionEnabled"] as? Bool) ?? true

        // MARK: - Tabs: Time Tracking

        settings.showTimeSpentInTooltips = (record["showTimeSpentInTooltips"] as? Bool) ?? true

        // MARK: - Tabs: Indicators

        settings.showUnsavedFormIndicator = (record["showUnsavedFormIndicator"] as? Bool) ?? false

        // MARK: - Favorites

        settings.enabledAppShortcutsRaw = record["enabledAppShortcutsRaw"] as? String ?? ""
        settings.appShortcutColorsJSON = record["appShortcutColorsJSON"] as? String ?? "{}"
        settings.appShortcutNamesJSON = record["appShortcutNamesJSON"] as? String ?? "{}"

        // MARK: - Privacy: Tracking Protection

        settings.blockThirdPartyCookies = (record["blockThirdPartyCookies"] as? Bool) ?? true
        settings.doNotTrack = (record["doNotTrack"] as? Bool) ?? true
        settings.enableGlobalPrivacyControl = (record["enableGlobalPrivacyControl"] as? Bool) ?? true
        settings.enableGPCTelemetry = (record["enableGPCTelemetry"] as? Bool) ?? false
        settings.enableAutoConsent = (record["enableAutoConsent"] as? Bool) ?? false
        settings.hideSignInPrompts = (record["hideSignInPrompts"] as? Bool) ?? true

        // MARK: - Privacy: History

        settings.automaticHistoryCleanup = (record["automaticHistoryCleanup"] as? Bool) ?? false
        settings.historyRetentionDays = (record["historyRetentionDays"] as? Int) ?? 365

        // MARK: - Privacy: Space Locking

        settings.defaultLockTimeout = (record["defaultLockTimeout"] as? Int) ?? 300

        // MARK: - Getting Started

        settings.showSidebarHints = (record["showSidebarHints"] as? Bool) ?? true

        // MARK: - Browsing: Gestures

        settings.spaceSwipeGestureEnabled = (record["spaceSwipeGestureEnabled"] as? Bool) ?? true

        // MARK: - Browsing: Link Previews

        settings.shiftClickLinkPreviewEnabled = (record["shiftClickLinkPreviewEnabled"] as? Bool) ?? true
        settings.showModifierKeyHints = (record["showModifierKeyHints"] as? Bool) ?? true

        // MARK: - Browsing: Media

        settings.autoPiPOnTabSwitch = (record["autoPiPOnTabSwitch"] as? Bool) ?? true
        settings.forceNativeVideoControls = (record["forceNativeVideoControls"] as? Bool) ?? false
        settings.defaultVideoSpeed = (record["defaultVideoSpeed"] as? Double) ?? 1.0

        // MARK: - Browsing: Web Behavior

        settings.disableBeforeUnloadAlerts = (record["disableBeforeUnloadAlerts"] as? Bool) ?? false
        settings.disableScrollHijacking = (record["disableScrollHijacking"] as? Bool) ?? false
        settings.contentProtectionBypassEnabled = (record["contentProtectionBypassEnabled"] as? Bool) ?? true

        // MARK: - Browsing: Mail Handler

        settings.preferredMailHandlerRaw = record["preferredMailHandlerRaw"] as? String
            ?? MailHandler.system.rawValue

        // MARK: - Browsing: AutoFill

        settings.autoFillModeRaw = record["autoFillModeRaw"] as? String
            ?? AutoFillMode.builtIn.rawValue
        settings.requireAuthForAutoFill = (record["requireAuthForAutoFill"] as? Bool) ?? false

        // MARK: - Browsing: Clipboard

        settings.clipboardLinkMonitoring = (record["clipboardLinkMonitoring"] as? Bool) ?? false

        // MARK: - Downloads

        settings.customDownloadDirectory = record["customDownloadDirectory"] as? String

        // MARK: - Downloads: aria2

        settings.useAria2ForLargeFiles = (record["useAria2ForLargeFiles"] as? Bool) ?? false
        settings.aria2ThresholdMB = (record["aria2ThresholdMB"] as? Int) ?? 50
        settings.enableBitTorrent = (record["enableBitTorrent"] as? Bool) ?? false

        // MARK: - Downloads: yt-dlp

        settings.ytdlpEnabled = (record["ytdlpEnabled"] as? Bool) ?? true
        settings.ytdlpUseCookies = (record["ytdlpUseCookies"] as? Bool) ?? true
        settings.ytdlpDeleteAfterPhotosImport = (record["ytdlpDeleteAfterPhotosImport"] as? Bool) ?? false

        // MARK: - Agent Chat

        settings.agentEnabled = (record["agentEnabled"] as? Bool) ?? true
        settings.agentSessionKey = record["agentSessionKey"] as? String ?? "agent:main:main"
        settings.agentAutoIncludeContext = (record["agentAutoIncludeContext"] as? Bool) ?? true
        settings.agentProviderKind = (record["agentProviderKindRaw"] as? String)
            .flatMap(AgentProviderKind.init(rawValue:)) ?? .claudeAPI
        settings.agentClaudeModel = record["agentClaudeModel"] as? String
            ?? ClaudeModel.sonnet.rawValue
        settings.agentClaudeMaxTokens = (record["agentClaudeMaxTokens"] as? Int) ?? 8_192
        settings.agentOpenAIModel = record["agentOpenAIModel"] as? String ?? "gpt-5"
        settings.agentOpenRouterModel = record["agentOpenRouterModel"] as? String
            ?? "anthropic/claude-opus-4.6"
        settings.agentCustomModel = record["agentCustomModel"] as? String ?? ""
        settings.agentCustomBaseURL = record["agentCustomBaseURL"] as? String
            ?? "http://localhost:11434/v1"
        settings.agentCustomRequiresAuth = (record["agentCustomRequiresAuth"] as? Bool) ?? false
        settings.agentOpenAIMaxTokens = (record["agentOpenAIMaxTokens"] as? Int) ?? 4_096
        settings.agentDisplayName = record["agentDisplayName"] as? String ?? "Agent"
        settings.agentAvatarData = record["agentAvatarData"] as? Data

        // MARK: - Widgets: Calendar

        settings.showCalendarWidget = (record["showCalendarWidget"] as? Bool) ?? false
        settings.calendarLookAheadHours = (record["calendarLookAheadHours"] as? Int) ?? 24
        settings.calendarAutoExpandOnImminent = (record["calendarAutoExpandOnImminent"] as? Bool) ?? true
        settings.enabledCalendarIDsJSON = record["enabledCalendarIDsJSON"] as? String ?? "[]"

        // MARK: - Widgets: Speed Reader

        settings.speedReaderWPM = (record["speedReaderWPM"] as? Int) ?? 250
        settings.speedReaderResumePositionsJSON = record["speedReaderResumePositionsJSON"] as? String ?? "{}"

        // MARK: - Advanced: JavaScript

        settings.enableJavaScript = (record["enableJavaScript"] as? Bool) ?? true
        settings.allowJavaScriptWhitelist = (record["allowJavaScriptWhitelist"] as? Bool) ?? true

        // MARK: - Advanced: Windows

        settings.allowPopups = (record["allowPopups"] as? Bool) ?? false

        // MARK: - Advanced: Control Server

        settings.controlAccessModeRaw = record["controlAccessModeRaw"] as? String
            ?? ControlAccessMode.prompt.rawValue
        settings.allowedControlClientsJSON = record["allowedControlClientsJSON"] as? String ?? "[]"

        // MARK: - Advanced: Security

        settings.allowSSLCertificateBypass = (record["allowSSLCertificateBypass"] as? Bool) ?? false

        // MARK: - Advanced: Crash Recovery

        settings.crashThreshold = (record["crashThreshold"] as? Int) ?? 3
        settings.crashTimeWindowSeconds = (record["crashTimeWindowSeconds"] as? Int) ?? 60
        settings.enableAutoCrashRecovery = (record["enableAutoCrashRecovery"] as? Bool) ?? true

        // MARK: - Feedback

        settings.feedbackName = record["feedbackName"] as? String ?? ""
        settings.feedbackEmail = record["feedbackEmail"] as? String ?? ""
        settings.verboseLoggingEnabled = (record["verboseLoggingEnabled"] as? Bool) ?? false

        // MARK: - Updates

        settings.checkForUpdatesAutomatically = (record["checkForUpdatesAutomatically"] as? Bool) ?? true

        // MARK: - Activation & Telemetry

        settings.isActivated = (record["isActivated"] as? Bool) ?? false
        settings.activationCode = record["activationCode"] as? String
        settings.hasCompletedOnboarding = (record["hasCompletedOnboarding"] as? Bool) ?? false
        settings.hasRunOnboardingMigration = (record["hasRunOnboardingMigration"] as? Bool) ?? false
        settings.telemetryEnabled = (record["telemetryEnabled"] as? Bool) ?? false
        settings.lastHeartbeatDate = record["lastHeartbeatDate"] as? Date

        return settings
    }
}
