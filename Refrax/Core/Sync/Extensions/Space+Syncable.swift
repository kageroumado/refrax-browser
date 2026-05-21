import CloudKit
import SwiftData

extension Space: Syncable {
    nonisolated static var ckRecordType: String { "Space" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["name"] = name as NSString
        record["iconName"] = iconName as NSString
        record["colorHex"] = colorHex as NSString
        record["position"] = position as NSNumber
        record["dataStoreMode"] = dataStoreMode.rawValue as NSString
        record["isLockEnabled"] = isLockEnabled as NSNumber

        // Dates
        record["createdAt"] = createdAt as NSDate

        // Optionals
        record["spaceDescription"] = spaceDescription as NSString?
        record["customDownloadPath"] = customDownloadPath as NSString?
        record["downloadColorTag"] = downloadColorTag as NSNumber?
        record["lockTimeoutOverride"] = lockTimeoutOverride as NSNumber?

        // To-many relationships (tabs, groups) are NOT encoded here.
        // They are inferred from child references (Tab/TabGroup → Space).
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> Space {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else {
            throw SyncError.missingRequiredField("recordID")
        }

        // Fetch existing or create new
        var descriptor = FetchDescriptor<Space>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let space: Space
        if let existing {
            space = existing
        } else {
            guard let name = record["name"] as? String else {
                throw SyncError.missingRequiredField("name")
            }
            guard let iconName = record["iconName"] as? String else {
                throw SyncError.missingRequiredField("iconName")
            }
            space = Space(id: uuid, name: name, iconName: iconName)
            context.insert(space)
        }

        // Update all properties from record
        space.name = record["name"] as? String ?? space.name
        space.iconName = record["iconName"] as? String ?? space.iconName
        space.colorHex = record["colorHex"] as? String ?? GroupColor.steel.rawValue
        space.position = (record["position"] as? Int) ?? 0
        space.createdAt = record["createdAt"] as? Date ?? space.createdAt
        space.dataStoreMode = (record["dataStoreMode"] as? String)
            .flatMap(DataStoreMode.init(rawValue:)) ?? .global
        space.isLockEnabled = (record["isLockEnabled"] as? Bool) ?? false

        // Optionals
        space.spaceDescription = record["spaceDescription"] as? String
        space.customDownloadPath = record["customDownloadPath"] as? String
        space.downloadColorTag = record["downloadColorTag"] as? Int
        space.lockTimeoutOverride = record["lockTimeoutOverride"] as? Int

        return space
    }
}
