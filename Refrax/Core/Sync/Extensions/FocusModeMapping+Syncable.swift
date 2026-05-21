import CloudKit
import SwiftData

extension FocusModeMapping: Syncable {
    nonisolated static var ckRecordType: String { "FocusModeMapping" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Identity
        record["focusIdentifier"] = focusIdentifier as NSString
        record["focusDisplayName"] = focusDisplayName as NSString

        // Scalars
        record["suppressNotifications"] = suppressNotifications as NSNumber
        record["isEnabled"] = isEnabled as NSNumber

        // Matching arrays
        record["restrictedDomains"] = restrictedDomains as NSArray
        record["blurredDomains"] = blurredDomains as NSArray

        // Dates
        record["createdAt"] = createdAt as NSDate

        // Optionals
        record["targetSpaceID"] = targetSpaceID?.uuidString as NSString?
        record["lastTriggeredAt"] = lastTriggeredAt as NSDate?
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> FocusModeMapping {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else {
            throw SyncError.missingRequiredField("recordID")
        }

        // Fetch existing or create new
        var descriptor = FetchDescriptor<FocusModeMapping>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let mapping: FocusModeMapping
        if let existing {
            mapping = existing
        } else {
            guard let focusIdentifier = record["focusIdentifier"] as? String else {
                throw SyncError.missingRequiredField("focusIdentifier")
            }
            guard let focusDisplayName = record["focusDisplayName"] as? String else {
                throw SyncError.missingRequiredField("focusDisplayName")
            }
            mapping = FocusModeMapping(
                focusIdentifier: focusIdentifier,
                focusDisplayName: focusDisplayName
            )
            mapping.id = uuid
            context.insert(mapping)
        }

        // Update all properties from record
        mapping.focusIdentifier = record["focusIdentifier"] as? String ?? mapping.focusIdentifier
        mapping.focusDisplayName = record["focusDisplayName"] as? String ?? mapping.focusDisplayName
        mapping.suppressNotifications = (record["suppressNotifications"] as? Bool) ?? false
        mapping.isEnabled = (record["isEnabled"] as? Bool) ?? true
        mapping.restrictedDomains = (record["restrictedDomains"] as? [String]) ?? []
        mapping.blurredDomains = (record["blurredDomains"] as? [String]) ?? []
        mapping.createdAt = record["createdAt"] as? Date ?? mapping.createdAt
        mapping.targetSpaceID = (record["targetSpaceID"] as? String).flatMap(UUID.init(uuidString:))
        mapping.lastTriggeredAt = record["lastTriggeredAt"] as? Date

        return mapping
    }
}
