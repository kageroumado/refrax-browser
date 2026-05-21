import CloudKit
import SwiftData

extension UserStyle: Syncable {
    nonisolated static var ckRecordType: String { "UserStyle" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Identity
        record["name"] = name as NSString
        record["sourceHash"] = sourceHash as NSString

        // Source
        record["css"] = css as NSString

        // Matching
        record["domainPatterns"] = domainPatterns as NSArray
        record["urlPatterns"] = urlPatterns as NSArray
        record["isGlobal"] = isGlobal as NSNumber

        // State
        record["isEnabled"] = isEnabled as NSNumber

        // Dates
        record["installedAt"] = installedAt as NSDate

        // Optionals
        record["styleDescription"] = styleDescription as NSString?
        record["author"] = author as NSString?
        record["version"] = version as NSString?
        record["sourceURL"] = sourceURL?.absoluteString as NSString?
        record["updateURL"] = updateURL?.absoluteString as NSString?
        record["lastUpdatedAt"] = lastUpdatedAt as NSDate?
        record["lastUpdateCheckAt"] = lastUpdateCheckAt as NSDate?
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> UserStyle {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else {
            throw SyncError.missingRequiredField("recordID")
        }

        // Fetch existing or create new
        var descriptor = FetchDescriptor<UserStyle>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let style: UserStyle
        if let existing {
            style = existing
        } else {
            guard let name = record["name"] as? String else {
                throw SyncError.missingRequiredField("name")
            }
            guard let css = record["css"] as? String else {
                throw SyncError.missingRequiredField("css")
            }
            style = UserStyle(name: name, css: css)
            style.id = uuid
            context.insert(style)
        }

        // Update all properties from record
        style.name = record["name"] as? String ?? style.name

        if let css = record["css"] as? String {
            style.css = css
        }
        style.sourceHash = record["sourceHash"] as? String ?? style.sourceHash

        // Matching
        style.domainPatterns = (record["domainPatterns"] as? [String]) ?? []
        style.urlPatterns = (record["urlPatterns"] as? [String]) ?? []
        style.isGlobal = (record["isGlobal"] as? Bool) ?? false

        // State
        style.isEnabled = (record["isEnabled"] as? Bool) ?? true

        // Dates
        style.installedAt = record["installedAt"] as? Date ?? style.installedAt

        // Optionals
        style.styleDescription = record["styleDescription"] as? String
        style.author = record["author"] as? String
        style.version = record["version"] as? String
        style.sourceURL = (record["sourceURL"] as? String).flatMap(URL.init(string:))
        style.updateURL = (record["updateURL"] as? String).flatMap(URL.init(string:))
        style.lastUpdatedAt = record["lastUpdatedAt"] as? Date
        style.lastUpdateCheckAt = record["lastUpdateCheckAt"] as? Date

        return style
    }
}
