import CloudKit
import SwiftData

extension BrowsingContext: Syncable {
    nonisolated static var ckRecordType: String { "BrowsingContext" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["name"] = name as NSString
        record["color"] = color as NSString
        record["isDefault"] = isDefault as NSNumber

        // Dates
        record["createdAt"] = createdAt as NSDate
        record["lastUsed"] = lastUsed as NSDate

        // Optionals
        record["iconName"] = iconName as NSString?
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> BrowsingContext {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else {
            throw SyncError.missingRequiredField("recordID")
        }

        // Fetch existing or create new
        var descriptor = FetchDescriptor<BrowsingContext>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let browsingContext: BrowsingContext
        if let existing {
            browsingContext = existing
        } else {
            let name = record["name"] as? String ?? "Context"
            browsingContext = BrowsingContext(name: name)
            browsingContext.id = uuid
            context.insert(browsingContext)
        }

        // Update all properties from record
        browsingContext.name = record["name"] as? String ?? browsingContext.name
        browsingContext.color = record["color"] as? String ?? GroupColor.steel.rawValue
        browsingContext.isDefault = (record["isDefault"] as? Bool) ?? false
        browsingContext.createdAt = record["createdAt"] as? Date ?? browsingContext.createdAt
        browsingContext.lastUsed = record["lastUsed"] as? Date ?? browsingContext.lastUsed

        // Optionals
        browsingContext.iconName = record["iconName"] as? String

        return browsingContext
    }
}
