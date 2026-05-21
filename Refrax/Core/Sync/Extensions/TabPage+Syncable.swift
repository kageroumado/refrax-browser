import CloudKit
import SwiftData

extension TabPage: Syncable {
    nonisolated static var ckRecordType: String { "TabPage" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["url"] = url.absoluteString as NSString
        record["title"] = title as NSString

        // Dates
        record["createdAt"] = createdAt as NSDate

        // Optionals
        record["openerTabPageID"] = openerTabPageID?.uuidString as NSString?
        record["layoutPosition"] = layoutPosition as NSString?
        record["scrollPositionY"] = scrollPositionY as NSNumber?

        // EXCLUDED: faviconData, largeFaviconData (re-derivable from websites)

        // Relationships
        // TabPage → Tab: CASCADE (TabPage is deleted when Tab is deleted)
        if let tabID = tab?.id {
            record["tabRef"] = RecordMapper.reference(
                to: tabID, recordType: Tab.ckRecordType, action: .deleteSelf
            )
        } else {
            record["tabRef"] = nil
        }
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> TabPage {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else {
            throw SyncError.missingRequiredField("recordID")
        }

        // Fetch existing or create new
        var descriptor = FetchDescriptor<TabPage>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let page: TabPage
        if let existing {
            page = existing
        } else {
            let url = (record["url"] as? String).flatMap(URL.init(string:)) ?? .blank
            let title = record["title"] as? String ?? "New Page"
            let layoutPosition = (record["layoutPosition"] as? String)
                .flatMap(PanePosition.init(rawValue:))

            page = TabPage(url: url, title: title, layoutPosition: layoutPosition)
            page.id = uuid
            context.insert(page)
        }

        // Update all properties from record
        if let urlString = record["url"] as? String, let url = URL(string: urlString) {
            page.url = url
        }
        page.title = record["title"] as? String ?? page.title
        page.createdAt = record["createdAt"] as? Date ?? page.createdAt
        page.openerTabPageID = (record["openerTabPageID"] as? String)
            .flatMap(UUID.init(uuidString:))
        page.layoutPosition = record["layoutPosition"] as? String
        page.scrollPositionY = record["scrollPositionY"] as? Double

        // Resolve tab relationship
        if let tabRef = record["tabRef"] as? CKRecord.Reference,
           let tabUUID = RecordMapper.uuid(from: tabRef.recordID)
        {
            if page.tab?.id != tabUUID {
                var tabDescriptor = FetchDescriptor<Tab>(
                    predicate: #Predicate { $0.id == tabUUID }
                )
                tabDescriptor.fetchLimit = 1
                page.tab = try? context.fetch(tabDescriptor).first
            }
        } else {
            page.tab = nil
        }

        return page
    }
}
