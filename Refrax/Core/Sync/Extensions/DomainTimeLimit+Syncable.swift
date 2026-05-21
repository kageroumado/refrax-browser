import CloudKit
import SwiftData

extension DomainTimeLimit: Syncable {
    nonisolated static var ckRecordType: String { "DomainTimeLimit" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["domain"] = domain as NSString
        record["dailyLimitSeconds"] = dailyLimitSeconds as NSNumber
        record["isEnabled"] = isEnabled as NSNumber
        record["snoozesUsedToday"] = snoozesUsedToday as NSNumber

        // Optionals
        record["lastSnoozeReset"] = lastSnoozeReset as NSDate?
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> DomainTimeLimit {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else {
            throw SyncError.missingRequiredField("recordID")
        }

        // Fetch existing or create new
        var descriptor = FetchDescriptor<DomainTimeLimit>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let limit: DomainTimeLimit
        if let existing {
            limit = existing
        } else {
            guard let domain = record["domain"] as? String else {
                throw SyncError.missingRequiredField("domain")
            }
            let dailyLimitSeconds = (record["dailyLimitSeconds"] as? Int) ?? 1800
            limit = DomainTimeLimit(domain: domain, dailyLimitSeconds: dailyLimitSeconds)
            limit.id = uuid
            context.insert(limit)
        }

        // Update all properties from record
        limit.domain = record["domain"] as? String ?? limit.domain
        limit.dailyLimitSeconds = (record["dailyLimitSeconds"] as? Int) ?? limit.dailyLimitSeconds
        limit.isEnabled = (record["isEnabled"] as? Bool) ?? true
        limit.snoozesUsedToday = (record["snoozesUsedToday"] as? Int) ?? 0
        limit.lastSnoozeReset = record["lastSnoozeReset"] as? Date

        return limit
    }
}
