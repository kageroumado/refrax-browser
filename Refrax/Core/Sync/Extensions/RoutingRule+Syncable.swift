import CloudKit
import SwiftData

extension RoutingRule: Syncable {
    nonisolated static var ckRecordType: String { "RoutingRule" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["name"] = name as NSString
        record["priority"] = priority as NSNumber
        record["isEnabled"] = isEnabled as NSNumber

        // Codable arrays/structs encoded as JSON
        if let conditionsData = try? JSONEncoder().encode(conditions) {
            record["conditionsJSON"] = String(data: conditionsData, encoding: .utf8) as NSString?
        }
        if let actionData = try? JSONEncoder().encode(action) {
            record["actionJSON"] = String(data: actionData, encoding: .utf8) as NSString?
        }

        // Dates
        record["createdAt"] = createdAt as NSDate
        record["modifiedAt"] = modifiedAt as NSDate
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> RoutingRule {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else {
            throw SyncError.missingRequiredField("recordID")
        }

        // Fetch existing or create new
        var descriptor = FetchDescriptor<RoutingRule>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let rule: RoutingRule
        if let existing {
            rule = existing
        } else {
            guard let name = record["name"] as? String else {
                throw SyncError.missingRequiredField("name")
            }
            // Decode conditions and action from JSON
            let conditions: [RoutingCondition]
            if let json = record["conditionsJSON"] as? String,
               let data = json.data(using: .utf8)
            {
                conditions = (try? JSONDecoder().decode([RoutingCondition].self, from: data)) ?? []
            } else {
                conditions = []
            }

            let action: RoutingAction
            if let json = record["actionJSON"] as? String,
               let data = json.data(using: .utf8)
            {
                action = (try? JSONDecoder().decode(RoutingAction.self, from: data))
                    ?? .openInBackground
            } else {
                action = .openInBackground
            }

            rule = RoutingRule(name: name, conditions: conditions, action: action)
            rule.id = uuid
            context.insert(rule)
        }

        // Update all properties from record
        rule.name = record["name"] as? String ?? rule.name
        rule.priority = (record["priority"] as? Int) ?? 0
        rule.isEnabled = (record["isEnabled"] as? Bool) ?? true
        rule.createdAt = record["createdAt"] as? Date ?? rule.createdAt
        rule.modifiedAt = record["modifiedAt"] as? Date ?? rule.modifiedAt

        // Decode conditions
        if let json = record["conditionsJSON"] as? String,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode([RoutingCondition].self, from: data)
        {
            rule.conditions = decoded
        }

        // Decode action
        if let json = record["actionJSON"] as? String,
           let data = json.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(RoutingAction.self, from: data)
        {
            rule.action = decoded
        }

        return rule
    }
}
