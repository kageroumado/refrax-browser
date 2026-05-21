import CloudKit
import SwiftData

extension AppRedirectRule: Syncable {
    nonisolated static var ckRecordType: String { "AppRedirectRule" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["name"] = name as NSString
        record["domainPattern"] = domainPattern as NSString
        record["targetAppBundleID"] = targetAppBundleID as NSString
        record["isEnabled"] = isEnabled as NSNumber
        record["order"] = order as NSNumber

        // Optionals
        record["pathPattern"] = pathPattern as NSString?

        // Excluded: cached regexes (@Transient)

        // Relationships
        // AppRedirectRule → PrivacyProtectionSettings: CASCADE (deleted with parent)
        // Parent is a singleton — no reference needed; resolved via singleton accessor.
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> AppRedirectRule {
        guard let name = record["name"] as? String, !name.isEmpty else {
            throw SyncError.missingRequiredField("name")
        }
        guard let domainPattern = record["domainPattern"] as? String else {
            throw SyncError.missingRequiredField("domainPattern")
        }

        // AppRedirectRule has no explicit UUID id. Use name + domainPattern as
        // composite key for upsert.
        var descriptor = FetchDescriptor<AppRedirectRule>(
            predicate: #Predicate { $0.name == name && $0.domainPattern == domainPattern }
        )
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let rule: AppRedirectRule
        if let existing {
            rule = existing
        } else {
            guard let targetAppBundleID = record["targetAppBundleID"] as? String else {
                throw SyncError.missingRequiredField("targetAppBundleID")
            }
            rule = AppRedirectRule(
                name: name,
                domainPattern: domainPattern,
                targetAppBundleID: targetAppBundleID
            )
            context.insert(rule)
        }

        // Update all properties from record
        rule.name = name
        rule.domainPattern = domainPattern
        rule.targetAppBundleID = record["targetAppBundleID"] as? String ?? rule.targetAppBundleID
        rule.isEnabled = (record["isEnabled"] as? Bool) ?? true
        rule.order = (record["order"] as? Int) ?? 0
        rule.pathPattern = record["pathPattern"] as? String

        // Re-attach to parent singleton if not already attached
        if rule.privacySettings == nil {
            let settingsDescriptor = FetchDescriptor<BrowserSettings>()
            if let browserSettings = try? context.fetch(settingsDescriptor).first {
                rule.privacySettings = browserSettings.privacyProtection
            }
        }

        return rule
    }
}
