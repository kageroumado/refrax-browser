import CloudKit
import SwiftData

extension Tab: Syncable {
    nonisolated static var ckRecordType: String { "Tab" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["status"] = status.rawValue as NSString
        record["isReferenceTab"] = isReferenceTab as NSNumber
        record["isUnread"] = isUnread as NSNumber
        record["unreadFromBadge"] = unreadFromBadge as NSNumber
        record["position"] = position as NSNumber

        // Dates
        record["createdAt"] = createdAt as NSDate
        record["lastAccessed"] = lastAccessed as NSDate?
        record["archivedAt"] = archivedAt as NSDate?

        // Optionals
        record["customName"] = customName as NSString?
        record["lastBadgeCount"] = lastBadgeCount as NSNumber?
        record["groupID"] = groupID?.uuidString as NSString?
        record["originURL"] = originURL?.absoluteString as NSString?
        record["layoutConfigurationData"] = layoutConfigurationData as NSData?

        // Relationships
        // Tab → Space: CASCADE (Tab is deleted when Space is deleted)
        if let spaceID = space?.id {
            record["spaceRef"] = RecordMapper.reference(
                to: spaceID, recordType: Space.ckRecordType, action: .deleteSelf
            )
        } else {
            record["spaceRef"] = nil
        }

        // Tab → TabGroup: NULLIFY (Tab survives group deletion)
        record["groupRef"] = RecordMapper.optionalReference(
            to: group?.id, recordType: TabGroup.ckRecordType, action: .none
        )

        // Tab → Bookmark (linkedBookmark): NULLIFY — don't encode from Tab side,
        // the relationship is managed by Bookmark's sync.

        // To-many: pages — NOT encoded here (inferred from TabPage → Tab reference)
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> Tab {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else {
            throw SyncError.missingRequiredField("recordID")
        }

        // Fetch existing or create new
        var descriptor = FetchDescriptor<Tab>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let tab: Tab
        if let existing {
            tab = existing
        } else {
            // Tab init requires space — resolve the space reference
            var space: Space?
            if let spaceRef = record["spaceRef"] as? CKRecord.Reference,
               let spaceUUID = RecordMapper.uuid(from: spaceRef.recordID)
            {
                var spaceDescriptor = FetchDescriptor<Space>(
                    predicate: #Predicate { $0.id == spaceUUID }
                )
                spaceDescriptor.fetchLimit = 1
                space = try? context.fetch(spaceDescriptor).first
            }

            tab = Tab(space: space)
            tab.id = uuid
            context.insert(tab)
        }

        // Update all properties from record
        tab.status = (record["status"] as? String)
            .flatMap(TabStatus.init(rawValue:)) ?? .regular
        tab.isReferenceTab = (record["isReferenceTab"] as? Bool) ?? false
        tab.isUnread = (record["isUnread"] as? Bool) ?? false
        tab.unreadFromBadge = (record["unreadFromBadge"] as? Bool) ?? false
        tab.position = (record["position"] as? Int) ?? 0
        tab.createdAt = record["createdAt"] as? Date ?? tab.createdAt
        tab.lastAccessed = record["lastAccessed"] as? Date
        tab.archivedAt = record["archivedAt"] as? Date
        tab.customName = record["customName"] as? String
        tab.lastBadgeCount = record["lastBadgeCount"] as? Int
        tab.groupID = (record["groupID"] as? String).flatMap(UUID.init(uuidString:))
        tab.originURL = (record["originURL"] as? String).flatMap(URL.init(string:))
        tab.layoutConfigurationData = record["layoutConfigurationData"] as? Data

        // Resolve space relationship
        if let spaceRef = record["spaceRef"] as? CKRecord.Reference,
           let spaceUUID = RecordMapper.uuid(from: spaceRef.recordID)
        {
            if tab.space?.id != spaceUUID {
                var spaceDescriptor = FetchDescriptor<Space>(
                    predicate: #Predicate { $0.id == spaceUUID }
                )
                spaceDescriptor.fetchLimit = 1
                tab.space = try? context.fetch(spaceDescriptor).first
            }
        } else {
            tab.space = nil
        }

        // Resolve group relationship
        if let groupRef = record["groupRef"] as? CKRecord.Reference,
           let groupUUID = RecordMapper.uuid(from: groupRef.recordID)
        {
            if tab.group?.id != groupUUID {
                var groupDescriptor = FetchDescriptor<TabGroup>(
                    predicate: #Predicate { $0.id == groupUUID }
                )
                groupDescriptor.fetchLimit = 1
                tab.group = try? context.fetch(groupDescriptor).first
            }
        } else {
            tab.group = nil
        }

        return tab
    }
}
