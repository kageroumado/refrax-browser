import CloudKit
import SwiftData

extension ExternalURLSettings: Syncable {
    nonisolated static var ckRecordType: String { "ExternalURLSettings" }

    /// Well-known record name for the singleton ExternalURLSettings record.
    ///
    /// Since ExternalURLSettings is a singleton child of PrivacyProtectionSettings
    /// (no UUID `id`), we use a fixed record name so all devices converge on the
    /// same CKRecord.
    static let singletonRecordName = "ExternalURLSettings-Singleton"

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["enableCustomHandling"] = enableCustomHandling as NSNumber
        record["defaultBehaviorRaw"] = defaultBehaviorRaw as NSString
        record["activateOnExternalURL"] = activateOnExternalURL as NSNumber
        record["notifyOnBackgroundOpen"] = notifyOnBackgroundOpen as NSNumber

        // Optionals
        record["defaultTargetSpaceID"] = defaultTargetSpaceID?.uuidString as NSString?

        // Relationships: rules, sourceAppRules are synced independently.
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> ExternalURLSettings {
        // Singleton child of PrivacyProtectionSettings. Access via the lazy
        // accessor chain: BrowserSettings → PrivacyProtectionSettings → ExternalURLSettings.
        let descriptor = FetchDescriptor<BrowserSettings>()
        let browserSettings: BrowserSettings
        if let existing = try? context.fetch(descriptor).first {
            browserSettings = existing
        } else {
            let newSettings = BrowserSettings()
            context.insert(newSettings)
            browserSettings = newSettings
        }
        let settings = browserSettings.privacyProtection.externalURLSettings

        // Update all properties from record
        settings.enableCustomHandling = (record["enableCustomHandling"] as? Bool) ?? false
        settings.defaultBehaviorRaw = record["defaultBehaviorRaw"] as? String
            ?? ExternalURLBehavior.openInCurrentSpace.rawValue
        settings.activateOnExternalURL = (record["activateOnExternalURL"] as? Bool) ?? true
        settings.notifyOnBackgroundOpen = (record["notifyOnBackgroundOpen"] as? Bool) ?? true
        settings.defaultTargetSpaceID = (record["defaultTargetSpaceID"] as? String)
            .flatMap(UUID.init(uuidString:))

        return settings
    }
}
