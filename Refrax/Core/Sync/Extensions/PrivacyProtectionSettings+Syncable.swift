import CloudKit
import SwiftData

extension PrivacyProtectionSettings: Syncable {
    nonisolated static var ckRecordType: String { "PrivacyProtectionSettings" }

    /// Well-known record name for the singleton PrivacyProtectionSettings record.
    ///
    /// Since PrivacyProtectionSettings is a singleton child of BrowserSettings (no UUID `id`),
    /// we use a fixed record name so all devices converge on the same CKRecord.
    static let singletonRecordName = "PrivacyProtectionSettings-Singleton"

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // MARK: - URL Cleaning

        record["enableLinkProtection"] = enableLinkProtection as NSNumber
        record["removeTrackingParameters"] = removeTrackingParameters as NSNumber
        record["expandURLShorteners"] = expandURLShorteners as NSNumber
        record["shortenerExpansionTimeout"] = shortenerExpansionTimeout as NSNumber
        record["convertAMPLinks"] = convertAMPLinks as NSNumber
        record["customTrackingParameters"] = customTrackingParameters as NSArray
        record["linkProtectionExceptions"] = linkProtectionExceptions as NSArray

        // Relationships: customRedirects, appRedirectRules, _externalURLSettings
        // are synced independently — not followed here.
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> PrivacyProtectionSettings {
        // Singleton child of BrowserSettings. Fetch the parent first (inlined from
        // fetchOrCreate to avoid @MainActor requirement), then access the lazy accessor.
        let descriptor = FetchDescriptor<BrowserSettings>()
        let browserSettings: BrowserSettings
        if let existing = try? context.fetch(descriptor).first {
            browserSettings = existing
        } else {
            let newSettings = BrowserSettings()
            context.insert(newSettings)
            browserSettings = newSettings
        }
        let settings = browserSettings.privacyProtection

        // MARK: - URL Cleaning

        settings.enableLinkProtection = (record["enableLinkProtection"] as? Bool) ?? true
        settings.removeTrackingParameters = (record["removeTrackingParameters"] as? Bool) ?? true
        settings.expandURLShorteners = (record["expandURLShorteners"] as? Bool) ?? true
        settings.shortenerExpansionTimeout = (record["shortenerExpansionTimeout"] as? Double) ?? 5.0
        settings.convertAMPLinks = (record["convertAMPLinks"] as? Bool) ?? true
        settings.customTrackingParameters = (record["customTrackingParameters"] as? [String]) ?? []
        settings.linkProtectionExceptions = (record["linkProtectionExceptions"] as? [String]) ?? []

        return settings
    }
}
