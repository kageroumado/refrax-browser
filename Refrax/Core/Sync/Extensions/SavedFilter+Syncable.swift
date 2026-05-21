import CloudKit
import SwiftData

extension SavedFilter: Syncable {
    nonisolated static var ckRecordType: String { "SavedFilter" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["name"] = name as NSString
        record["searchText"] = searchText as NSString
        record["searchInTitle"] = searchInTitle as NSNumber
        record["searchInURL"] = searchInURL as NSNumber

        // Dates
        record["createdAt"] = createdAt as NSDate
        record["lastUsed"] = lastUsed as NSDate

        // Optionals
        record["searchUnread"] = searchUnread as NSNumber?
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> SavedFilter {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else {
            throw SyncError.missingRequiredField("recordID")
        }

        // Fetch existing or create new
        var descriptor = FetchDescriptor<SavedFilter>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let filter: SavedFilter
        if let existing {
            filter = existing
        } else {
            guard let name = record["name"] as? String else {
                throw SyncError.missingRequiredField("name")
            }
            let searchText = record["searchText"] as? String ?? ""
            filter = SavedFilter(id: uuid, name: name, searchText: searchText)
            context.insert(filter)
        }

        // Update all properties from record
        filter.name = record["name"] as? String ?? filter.name
        filter.searchText = record["searchText"] as? String ?? filter.searchText
        filter.searchInTitle = (record["searchInTitle"] as? Bool) ?? true
        filter.searchInURL = (record["searchInURL"] as? Bool) ?? true
        filter.createdAt = record["createdAt"] as? Date ?? filter.createdAt
        filter.lastUsed = record["lastUsed"] as? Date ?? filter.lastUsed
        filter.searchUnread = record["searchUnread"] as? Bool

        return filter
    }
}
