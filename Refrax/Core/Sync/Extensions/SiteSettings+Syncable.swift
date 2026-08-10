import CloudKit
import SwiftData

extension SiteSettings: Syncable {
    nonisolated static var ckRecordType: String { "SiteSettings" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Primary key
        record["domain"] = domain as NSString

        // MARK: - Content Settings

        record["pageZoom"] = pageZoom as NSNumber
        record["useReaderWhenAvailable"] = useReaderWhenAvailable as NSNumber
        record["enableContentBlockers"] = enableContentBlockers as NSNumber
        record["allowJavaScript"] = allowJavaScript as NSNumber
        record["badgeDetectionRaw"] = badgeDetectionRaw as NSString

        // MARK: - Media Settings

        record["autoPlayPolicyRaw"] = autoPlayPolicyRaw as NSString

        // MARK: - Window Settings

        record["popUpPolicyRaw"] = popUpPolicyRaw as NSString
        record["gpcHeaderOverrideRaw"] = gpcHeaderOverrideRaw as NSString
        record["disableAutoConsent"] = disableAutoConsent as NSNumber
        record["websiteColoringPolicyRaw"] = websiteColoringPolicyRaw as NSString

        // MARK: - Permissions

        record["cameraPermissionRaw"] = cameraPermissionRaw as NSString
        record["microphonePermissionRaw"] = microphonePermissionRaw as NSString
        record["screenSharingPermissionRaw"] = screenSharingPermissionRaw as NSString
        record["locationPermissionRaw"] = locationPermissionRaw as NSString
        record["deviceSensorPermissionRaw"] = deviceSensorPermissionRaw as NSString

        // MARK: - Content Protection

        record["contentProtectionBypass"] = contentProtectionBypass as NSNumber?

        // MARK: - Energy

        record["calmPage"] = calmPage as NSNumber

        // MARK: - Web Behavior Overrides

        record["beforeUnloadAlertOverrideRaw"] = beforeUnloadAlertOverrideRaw as NSString
        record["scrollHijackingOverrideRaw"] = scrollHijackingOverrideRaw as NSString
        record["videoControlsOverrideRaw"] = videoControlsOverrideRaw as NSString
        record["videoSpeedOverride"] = videoSpeedOverride as NSNumber?

        // MARK: - Passwords

        record["neverSavePasswords"] = neverSavePasswords as NSNumber

        // MARK: - Page Appearance

        record["darkModeOverrideRaw"] = darkModeOverrideRaw as NSString
        record["pageFilterOverrideRaw"] = pageFilterOverrideRaw as NSString
        record["backgroundRemovalOverrideRaw"] = backgroundRemovalOverrideRaw as NSString

        // MARK: - Media Settings (PiP)

        record["pipPreferenceRaw"] = pipPreferenceRaw as NSString

        // MARK: - Translation

        record["translationPreferenceRaw"] = translationPreferenceRaw as NSString
        record["alwaysTranslateLanguages"] = alwaysTranslateLanguages as NSArray

        // MARK: - Timestamps

        record["createdAt"] = createdAt as NSDate
        record["modifiedAt"] = modifiedAt as NSDate
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> SiteSettings {
        guard let domain = record["domain"] as? String, !domain.isEmpty else {
            throw SyncError.missingRequiredField("domain")
        }

        // SiteSettings uses domain as unique key, not UUID.
        // Fetch by domain for upsert.
        let lowercasedDomain = domain.lowercased()
        var descriptor = FetchDescriptor<SiteSettings>(
            predicate: #Predicate { $0.domain == lowercasedDomain }
        )
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let siteSettings: SiteSettings
        if let existing {
            siteSettings = existing
        } else {
            siteSettings = SiteSettings(domain: domain)
            context.insert(siteSettings)
        }

        // MARK: - Content Settings

        siteSettings.pageZoom = (record["pageZoom"] as? Int) ?? 100
        siteSettings.useReaderWhenAvailable = (record["useReaderWhenAvailable"] as? Bool) ?? false
        siteSettings.enableContentBlockers = (record["enableContentBlockers"] as? Bool) ?? true
        siteSettings.allowJavaScript = (record["allowJavaScript"] as? Bool) ?? true
        siteSettings.badgeDetectionRaw = record["badgeDetectionRaw"] as? String
            ?? BadgeDetectionMode.automatic.rawValue

        // MARK: - Media Settings

        siteSettings.autoPlayPolicyRaw = record["autoPlayPolicyRaw"] as? String
            ?? AutoPlayPolicy.stopMediaWithSound.rawValue

        // MARK: - Window Settings

        siteSettings.popUpPolicyRaw = record["popUpPolicyRaw"] as? String
            ?? PopUpPolicy.blockAndNotify.rawValue
        siteSettings.gpcHeaderOverrideRaw = record["gpcHeaderOverrideRaw"] as? String
            ?? GPCHeaderOverride.useAllowlist.rawValue
        siteSettings.disableAutoConsent = (record["disableAutoConsent"] as? Bool) ?? false
        siteSettings.websiteColoringPolicyRaw = record["websiteColoringPolicyRaw"] as? String
            ?? WebsiteColoringPolicy.useDefault.rawValue

        // MARK: - Permissions

        siteSettings.cameraPermissionRaw = record["cameraPermissionRaw"] as? String
            ?? PermissionPolicy.ask.rawValue
        siteSettings.microphonePermissionRaw = record["microphonePermissionRaw"] as? String
            ?? PermissionPolicy.ask.rawValue
        siteSettings.screenSharingPermissionRaw = record["screenSharingPermissionRaw"] as? String
            ?? PermissionPolicy.ask.rawValue
        siteSettings.locationPermissionRaw = record["locationPermissionRaw"] as? String
            ?? PermissionPolicy.ask.rawValue
        siteSettings.deviceSensorPermissionRaw = record["deviceSensorPermissionRaw"] as? String
            ?? PermissionPolicy.ask.rawValue

        // MARK: - Content Protection

        siteSettings.contentProtectionBypass = record["contentProtectionBypass"] as? Bool

        // MARK: - Energy

        siteSettings.calmPage = record["calmPage"] as? Bool ?? false

        // MARK: - Web Behavior Overrides

        siteSettings.beforeUnloadAlertOverrideRaw = record["beforeUnloadAlertOverrideRaw"] as? String
            ?? BeforeUnloadAlertOverride.useDefault.rawValue
        siteSettings.scrollHijackingOverrideRaw = record["scrollHijackingOverrideRaw"] as? String
            ?? ScrollHijackingOverride.useDefault.rawValue
        siteSettings.videoControlsOverrideRaw = record["videoControlsOverrideRaw"] as? String
            ?? VideoControlsOverride.useDefault.rawValue
        siteSettings.videoSpeedOverride = record["videoSpeedOverride"] as? Double

        // MARK: - Passwords

        siteSettings.neverSavePasswords = (record["neverSavePasswords"] as? Bool) ?? false

        // MARK: - Page Appearance

        siteSettings.darkModeOverrideRaw = record["darkModeOverrideRaw"] as? String
            ?? DarkModeOverride.auto.rawValue
        siteSettings.pageFilterOverrideRaw = record["pageFilterOverrideRaw"] as? String
            ?? PageFilterOverride.auto.rawValue
        siteSettings.backgroundRemovalOverrideRaw = record["backgroundRemovalOverrideRaw"] as? String
            ?? BackgroundRemovalOverride.auto.rawValue

        // MARK: - Media Settings (PiP)

        siteSettings.pipPreferenceRaw = record["pipPreferenceRaw"] as? String
            ?? PiPPreference.system.rawValue

        // MARK: - Translation

        siteSettings.translationPreferenceRaw = record["translationPreferenceRaw"] as? String
            ?? TranslationPreference.ask.rawValue
        siteSettings.alwaysTranslateLanguages = (record["alwaysTranslateLanguages"] as? [String]) ?? []

        // MARK: - Timestamps

        siteSettings.createdAt = record["createdAt"] as? Date ?? siteSettings.createdAt
        siteSettings.modifiedAt = record["modifiedAt"] as? Date ?? siteSettings.modifiedAt

        return siteSettings
    }
}
