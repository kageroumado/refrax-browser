import CloudKit
import SwiftData

extension ArchiveRule: Syncable {
    nonisolated static var ckRecordType: String { "ArchiveRule" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["name"] = name as NSString
        record["ruleTypeRaw"] = ruleTypeRaw as NSString
        record["isEnabled"] = isEnabled as NSNumber
        record["priority"] = priority as NSNumber

        // Optionals
        record["domainPattern"] = domainPattern as NSString?
        record["spaceID"] = spaceID?.uuidString as NSString?
        record["inactivityDays"] = inactivityDays as NSNumber?
        record["maxTabCount"] = maxTabCount as NSNumber?
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> ArchiveRule {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else {
            throw SyncError.missingRequiredField("recordID")
        }

        // Fetch existing or create new
        var descriptor = FetchDescriptor<ArchiveRule>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let rule: ArchiveRule
        if let existing {
            rule = existing
        } else {
            guard let name = record["name"] as? String else {
                throw SyncError.missingRequiredField("name")
            }
            let ruleType = (record["ruleTypeRaw"] as? String)
                .flatMap(ArchiveRuleType.init(rawValue:)) ?? .inactivity
            rule = ArchiveRule(name: name, ruleType: ruleType)
            rule.id = uuid
            context.insert(rule)
        }

        // Update all properties from record
        rule.name = record["name"] as? String ?? rule.name
        rule.ruleTypeRaw = record["ruleTypeRaw"] as? String
            ?? ArchiveRuleType.inactivity.rawValue
        rule.isEnabled = (record["isEnabled"] as? Bool) ?? true
        rule.priority = (record["priority"] as? Int) ?? 0
        rule.domainPattern = record["domainPattern"] as? String
        rule.spaceID = (record["spaceID"] as? String).flatMap(UUID.init(uuidString:))
        rule.inactivityDays = record["inactivityDays"] as? Int
        rule.maxTabCount = record["maxTabCount"] as? Int

        return rule
    }
}
