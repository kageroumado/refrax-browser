import CloudKit
import SwiftData

extension ExternalURLRule: Syncable {
    nonisolated static var ckRecordType: String { "ExternalURLRule" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["name"] = name as NSString
        record["domainPattern"] = domainPattern as NSString
        record["actionRaw"] = actionRaw as NSString
        record["isEnabled"] = isEnabled as NSNumber
        record["order"] = order as NSNumber

        // Optionals
        record["pathPattern"] = pathPattern as NSString?
        record["targetSpaceID"] = targetSpaceID?.uuidString as NSString?
        record["targetGroupID"] = targetGroupID?.uuidString as NSString?

        // Excluded: cached regexes (@Transient)

        // Relationships
        // ExternalURLRule → ExternalURLSettings: CASCADE (deleted with parent)
        // Parent is a singleton — no reference needed; resolved via singleton accessor.
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> ExternalURLRule {
        guard let name = record["name"] as? String, !name.isEmpty else {
            throw SyncError.missingRequiredField("name")
        }
        guard let domainPattern = record["domainPattern"] as? String else {
            throw SyncError.missingRequiredField("domainPattern")
        }

        // ExternalURLRule has no explicit UUID id. Use name + domainPattern as
        // composite key for upsert.
        var descriptor = FetchDescriptor<ExternalURLRule>(
            predicate: #Predicate { $0.name == name && $0.domainPattern == domainPattern }
        )
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let rule: ExternalURLRule
        if let existing {
            rule = existing
        } else {
            rule = ExternalURLRule(name: name, domainPattern: domainPattern)
            context.insert(rule)
        }

        // Update all properties from record
        rule.name = name
        rule.domainPattern = domainPattern
        rule.actionRaw = record["actionRaw"] as? String ?? ""
        rule.isEnabled = (record["isEnabled"] as? Bool) ?? true
        rule.order = (record["order"] as? Int) ?? 0
        rule.pathPattern = record["pathPattern"] as? String
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
