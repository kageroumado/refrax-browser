import CloudKit
import SwiftData

extension Bookmark: Syncable {
    nonisolated static var ckRecordType: String { "Bookmark" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["url"] = url.absoluteString as NSString
        record["title"] = title as NSString
        record["isFavorite"] = isFavorite as NSNumber
        record["favoriteMode"] = favoriteMode.rawValue as NSString
        record["favoritePositionValue"] = favoritePositionValue as NSNumber
        record["visitCount"] = visitCount as NSNumber
        record["offlineStatus"] = offlineStatus.rawValue as NSString
        record["tags"] = tags as NSArray

        // Dates
        record["createdAt"] = createdAt as NSDate
        record["lastModified"] = lastModified as NSDate

        // Optionals
        record["customIconJSON"] = customIconJSON as NSString?
        record["favoriteColor"] = favoriteColor as NSString?
        record["lastVisited"] = lastVisited as NSDate?
        record["offlineDataPath"] = offlineDataPath as NSString?
        record["offlineSavedAt"] = offlineSavedAt as NSDate?
        record["offlineFileSize"] = offlineFileSize as NSNumber?
        record["spaceID"] = spaceID?.uuidString as NSString?

        // Excluded: faviconData, largeFaviconData (re-derived from websites)
        // Excluded: searchableText (re-derived from title, url, tags)

        // Relationships
        // Bookmark → BookmarkFolder: DELETESELF (bookmark cascade-deletes with folder)
        record["folderRef"] = RecordMapper.optionalReference(
            to: folder?.id, recordType: BookmarkFolder.ckRecordType, action: .deleteSelf
        )

        // linkedTab — managed from Tab side (Tab.linkedBookmark), not encoded here
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> Bookmark {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else {
            throw SyncError.missingRequiredField("recordID")
        }

        // Fetch existing or create new
        var descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let bookmark: Bookmark
        if let existing {
            bookmark = existing
        } else {
            guard let urlString = record["url"] as? String,
                  let url = URL(string: urlString)
            else {
                throw SyncError.missingRequiredField("url")
            }
            let title = record["title"] as? String
            bookmark = Bookmark(url: url, title: title)
            bookmark.id = uuid
            context.insert(bookmark)
        }

        // Update all properties from record
        if let urlString = record["url"] as? String, let url = URL(string: urlString) {
            bookmark.url = url
        }
        bookmark.title = record["title"] as? String ?? bookmark.title
        bookmark.isFavorite = (record["isFavorite"] as? Bool) ?? false
        bookmark.favoriteMode = (record["favoriteMode"] as? String)
            .flatMap(FavoriteMode.init(rawValue:)) ?? .liveFavorite
        bookmark.favoritePositionValue = (record["favoritePositionValue"] as? Int) ?? 0
        bookmark.visitCount = (record["visitCount"] as? Int) ?? 0
        bookmark.offlineStatus = (record["offlineStatus"] as? String)
            .flatMap(OfflineStatus.init(rawValue:)) ?? .notSaved
        bookmark.tags = (record["tags"] as? [String]) ?? []
        bookmark.createdAt = record["createdAt"] as? Date ?? bookmark.createdAt
        bookmark.lastModified = record["lastModified"] as? Date ?? bookmark.lastModified

        // Optionals
        bookmark.customIconJSON = record["customIconJSON"] as? String
        bookmark.favoriteColor = record["favoriteColor"] as? String
        bookmark.lastVisited = record["lastVisited"] as? Date
        bookmark.offlineDataPath = record["offlineDataPath"] as? String
        bookmark.offlineSavedAt = record["offlineSavedAt"] as? Date
        bookmark.offlineFileSize = record["offlineFileSize"] as? Int64
        bookmark.spaceID = (record["spaceID"] as? String).flatMap(UUID.init(uuidString:))

        // Resolve folder relationship
        if let folderRef = record["folderRef"] as? CKRecord.Reference,
           let folderUUID = RecordMapper.uuid(from: folderRef.recordID)
        {
            bookmark.folderID = folderUUID
            if bookmark.folder?.id != folderUUID {
                var folderDescriptor = FetchDescriptor<BookmarkFolder>(
                    predicate: #Predicate { $0.id == folderUUID }
                )
                folderDescriptor.fetchLimit = 1
                bookmark.folder = try? context.fetch(folderDescriptor).first
            }
        } else {
            bookmark.folderID = nil
            bookmark.folder = nil
        }

        return bookmark
    }
}
