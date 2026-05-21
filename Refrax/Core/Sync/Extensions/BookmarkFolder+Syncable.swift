import CloudKit
import SwiftData

extension BookmarkFolder: Syncable {
    nonisolated static var ckRecordType: String { "BookmarkFolder" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["name"] = name as NSString
        record["color"] = color as NSString
        record["position"] = position as NSNumber
        record["isFavorite"] = isFavorite as NSNumber
        record["favoritePositionValue"] = favoritePositionValue as NSNumber

        // Dates
        record["createdAt"] = createdAt as NSDate
        record["lastModified"] = lastModified as NSDate

        // Optionals
        record["customIconJSON"] = customIconJSON as NSString?

        // Relationships
        // BookmarkFolder → parent BookmarkFolder: DELETESELF (child cascade-deletes with parent)
        record["parentFolderRef"] = RecordMapper.optionalReference(
            to: parentFolder?.id, recordType: BookmarkFolder.ckRecordType, action: .deleteSelf
        )

        // To-many: bookmarks, childFolders — NOT encoded here
        // (inferred from Bookmark → folder and BookmarkFolder → parentFolder references)
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> BookmarkFolder {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else {
            throw SyncError.missingRequiredField("recordID")
        }

        // Fetch existing or create new
        var descriptor = FetchDescriptor<BookmarkFolder>(
            predicate: #Predicate { $0.id == uuid }
        )
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let folder: BookmarkFolder
        if let existing {
            folder = existing
        } else {
            let name = record["name"] as? String ?? "Folder"
            folder = BookmarkFolder(name: name)
            folder.id = uuid
            context.insert(folder)
        }

        // Update all properties from record
        folder.name = record["name"] as? String ?? folder.name
        folder.color = record["color"] as? String ?? "#808080"
        folder.position = (record["position"] as? Int) ?? 0
        folder.isFavorite = (record["isFavorite"] as? Bool) ?? false
        folder.favoritePositionValue = (record["favoritePositionValue"] as? Int) ?? 0
        folder.createdAt = record["createdAt"] as? Date ?? folder.createdAt
        folder.lastModified = record["lastModified"] as? Date ?? folder.lastModified

        // Optionals
        folder.customIconJSON = record["customIconJSON"] as? String

        // Resolve parent folder relationship
        if let parentRef = record["parentFolderRef"] as? CKRecord.Reference,
           let parentUUID = RecordMapper.uuid(from: parentRef.recordID)
        {
            folder.parentFolderID = parentUUID
            if folder.parentFolder?.id != parentUUID {
                var parentDescriptor = FetchDescriptor<BookmarkFolder>(
                    predicate: #Predicate { $0.id == parentUUID }
                )
                parentDescriptor.fetchLimit = 1
                folder.parentFolder = try? context.fetch(parentDescriptor).first
                // parentFolder may be nil if it hasn't synced yet — SyncCoordinator
                // handles deferred relationship linking in a later pass.
            }
        } else {
            folder.parentFolderID = nil
            folder.parentFolder = nil
        }

        return folder
    }
}
