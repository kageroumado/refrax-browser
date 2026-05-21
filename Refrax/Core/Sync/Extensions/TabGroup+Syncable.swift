import CloudKit
import SwiftData

extension TabGroup: Syncable {
    nonisolated static var ckRecordType: String { "TabGroup" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["name"] = name as NSString
        record["colorString"] = colorString as NSString
        record["position"] = position as NSNumber
        record["isPinned"] = isPinned as NSNumber
        record["isCollapsed"] = isCollapsed as NSNumber
        record["isArchive"] = isArchive as NSNumber

        // Dates
        record["createdAt"] = createdAt as NSDate

        // Optionals
        record["iconName"] = iconName as NSString?
        record["parentGroupID"] = parentGroupID?.uuidString as NSString?

        // Relationships
        // TabGroup → Space: CASCADE (TabGroup is deleted when Space is deleted)
        if let spaceID = space?.id {
            record["spaceRef"] = RecordMapper.reference(
                to: spaceID, recordType: Space.ckRecordType, action: .deleteSelf
            )
        } else {
            record["spaceRef"] = nil
        }

        // To-many: tabs — NOT encoded here (inferred from Tab → TabGroup reference)
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> TabGroup {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else {
            throw SyncError.missingRequiredField("recordID")
        }

        // Fetch existing or create new
        var descriptor = FetchDescriptor<TabGroup>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let group: TabGroup
        if let existing {
            group = existing
        } else {
            // TabGroup init requires a Space — resolve the space reference
            guard let spaceRef = record["spaceRef"] as? CKRecord.Reference,
                  let spaceUUID = RecordMapper.uuid(from: spaceRef.recordID)
            else {
                throw SyncError.missingRequiredField("spaceRef")
            }

            var spaceDescriptor = FetchDescriptor<Space>(
                predicate: #Predicate { $0.id == spaceUUID }
            )
            spaceDescriptor.fetchLimit = 1
            guard let space = try? context.fetch(spaceDescriptor).first else {
                throw SyncError.modelNotFound(spaceUUID)
            }

            let name = record["name"] as? String ?? "Group"
            group = TabGroup(space: space, name: name)
            group.id = uuid
            context.insert(group)
        }

        // Update all properties from record
        group.name = record["name"] as? String ?? group.name
        group.colorString = record["colorString"] as? String ?? GroupColor.steel.rawValue
        group.position = (record["position"] as? Int) ?? 0
        group.isPinned = (record["isPinned"] as? Bool) ?? false
        group.isCollapsed = (record["isCollapsed"] as? Bool) ?? false
        group.isArchive = (record["isArchive"] as? Bool) ?? false
        group.createdAt = record["createdAt"] as? Date ?? group.createdAt
        group.iconName = record["iconName"] as? String
        group.parentGroupID = (record["parentGroupID"] as? String)
            .flatMap(UUID.init(uuidString:))

        // Resolve space relationship
        if let spaceRef = record["spaceRef"] as? CKRecord.Reference,
           let spaceUUID = RecordMapper.uuid(from: spaceRef.recordID)
        {
            if group.space?.id != spaceUUID {
                var spaceDescriptor = FetchDescriptor<Space>(
                    predicate: #Predicate { $0.id == spaceUUID }
                )
                spaceDescriptor.fetchLimit = 1
                group.space = try? context.fetch(spaceDescriptor).first
            }
        }

        return group
    }
}
