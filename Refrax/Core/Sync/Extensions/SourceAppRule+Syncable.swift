import CloudKit
import SwiftData

extension SourceAppRule: Syncable {
    nonisolated static var ckRecordType: String { "SourceAppRule" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["name"] = name as NSString
        record["bundleIDPattern"] = bundleIDPattern as NSString
        record["actionRaw"] = actionRaw as NSString
        record["isEnabled"] = isEnabled as NSNumber
        record["order"] = order as NSNumber

        // Optionals
        record["targetSpaceID"] = targetSpaceID?.uuidString as NSString?
        record["targetGroupID"] = targetGroupID?.uuidString as NSString?

        // Excluded: cached regex (@Transient)

        // Relationships
        // SourceAppRule → ExternalURLSettings: CASCADE (deleted with parent)
        // Parent is a singleton — no reference needed; resolved via singleton accessor.
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> SourceAppRule {
        guard let name = record["name"] as? String, !name.isEmpty else {
            throw SyncError.missingRequiredField("name")
        }
        guard let bundleIDPattern = record["bundleIDPattern"] as? String else {
            throw SyncError.missingRequiredField("bundleIDPattern")
        }

        // SourceAppRule has no explicit UUID id. Use name + bundleIDPattern as
        // composite key for upsert.
        var descriptor = FetchDescriptor<SourceAppRule>(
            predicate: #Predicate { $0.name == name && $0.bundleIDPattern == bundleIDPattern }
        )
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let rule: SourceAppRule
        if let existing {
            rule = existing
        } else {
            rule = SourceAppRule(name: name, bundleIDPattern: bundleIDPattern)
            context.insert(rule)
        }

        // Update all properties from record
        rule.name = name
        rule.bundleIDPattern = bundleIDPattern
        rule.actionRaw = record["actionRaw"] as? String ?? ""
        rule.isEnabled = (record["isEnabled"] as? Bool) ?? true
        rule.order = (record["order"] as? Int) ?? 0
        rule.targetSpaceID = (record["targetSpaceID"] as? String).flatMap(UUID.init(uuidString:))
        rule.targetGroupID = (record["targetGroupID"] as? String).flatMap(UUID.init(uuidString:))

        // Re-attach to parent singleton if not already attached
        if rule.settings == nil {
            let settingsDescriptor = FetchDescriptor<BrowserSettings>()
            if let browserSettings = try? context.fetch(settingsDescriptor).first {
                rule.settings = browserSettings.privacyProtection.externalURLSettings
            }
        }

        return rule
    }
}
