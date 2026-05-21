import CloudKit
import SwiftData

extension HistoryEntry: Syncable {
    nonisolated static var ckRecordType: String { "HistoryEntry" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["url"] = url.absoluteString as NSString
        record["domain"] = domain as NSString
        record["searchableText"] = searchableText as NSString
        record["timeSpent"] = timeSpent as NSNumber
        record["isImported"] = isImported as NSNumber
        record["failedToLoad"] = failedToLoad as NSNumber

        // Dates
        record["visitedAt"] = visitedAt as NSDate

        // Optionals
        record["title"] = title as NSString?
        record["closedAt"] = closedAt as NSDate?
        record["lastSeenAt"] = lastSeenAt as NSDate?
        record["spaceID"] = spaceID?.uuidString as NSString?
        record["tabID"] = tabID?.uuidString as NSString?
        record["httpStatusCode"] = httpStatusCode as NSNumber?
        record["faviconURL"] = faviconURL?.absoluteString as NSString?

        // Self-referential relationship: parent HistoryEntry
        // Uses .none action — deleting parent should not delete child history entries
        record["parentRef"] = RecordMapper.optionalReference(
            to: parent?.id, recordType: HistoryEntry.ckRecordType, action: .none
        )

        // To-many: children — NOT encoded here (inferred from child → parent references)
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> HistoryEntry {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else {
            throw SyncError.missingRequiredField("recordID")
        }

        // Fetch existing or create new
        var descriptor = FetchDescriptor<HistoryEntry>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let entry: HistoryEntry
        if let existing {
            entry = existing
        } else {
            guard let urlString = record["url"] as? String,
                  let url = URL(string: urlString)
            else {
                throw SyncError.missingRequiredField("url")
            }
            entry = HistoryEntry(url: url)
            entry.id = uuid
            context.insert(entry)
        }

        // Update all properties from record
        if let urlString = record["url"] as? String, let url = URL(string: urlString) {
            entry.url = url
        }
        entry.domain = record["domain"] as? String ?? entry.domain
        entry.searchableText = record["searchableText"] as? String ?? entry.searchableText
        entry.timeSpent = (record["timeSpent"] as? Double) ?? 0
        entry.isImported = (record["isImported"] as? Bool) ?? false
        entry.failedToLoad = (record["failedToLoad"] as? Bool) ?? false
        entry.visitedAt = record["visitedAt"] as? Date ?? entry.visitedAt

        // Optionals
        entry.title = record["title"] as? String
        entry.closedAt = record["closedAt"] as? Date
        entry.lastSeenAt = record["lastSeenAt"] as? Date
        entry.spaceID = (record["spaceID"] as? String).flatMap(UUID.init(uuidString:))
        entry.tabID = (record["tabID"] as? String).flatMap(UUID.init(uuidString:))
        entry.httpStatusCode = record["httpStatusCode"] as? Int
        entry.faviconURL = (record["faviconURL"] as? String).flatMap(URL.init(string:))

        // Resolve parent relationship (self-referential, deferred linking)
        if let parentRef = record["parentRef"] as? CKRecord.Reference,
           let parentUUID = RecordMapper.uuid(from: parentRef.recordID)
        {
            if entry.parent?.id != parentUUID {
                var parentDescriptor = FetchDescriptor<HistoryEntry>(
                    predicate: #Predicate { $0.id == parentUUID }
                )
                parentDescriptor.fetchLimit = 1
                entry.parent = try? context.fetch(parentDescriptor).first
                // parent may be nil if it hasn't synced yet — SyncCoordinator
                // handles deferred relationship linking in a later pass.
            }
        } else {
            entry.parent = nil
        }

        return entry
    }
}
