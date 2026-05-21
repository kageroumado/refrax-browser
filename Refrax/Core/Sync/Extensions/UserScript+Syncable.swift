import CloudKit
import SwiftData

extension UserScript: Syncable {
    nonisolated static var ckRecordType: String { "UserScript" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Identity
        record["name"] = name as NSString
        record["namespace"] = namespace as NSString
        record["sourceHash"] = sourceHash as NSString

        // Source — stored as String for now; CKAsset optimization is a future improvement
        record["source"] = source as NSString

        // Matching
        record["includePatterns"] = includePatterns as NSArray
        record["excludePatterns"] = excludePatterns as NSArray
        record["matchPatterns"] = matchPatterns as NSArray
        record["runAtFrames"] = runAtFrames as NSNumber

        // Execution
        record["runAt"] = runAt.rawValue as NSString
        record["isEnabled"] = isEnabled as NSNumber

        // Permissions
        record["connectDomains"] = connectDomains as NSArray
        record["grantsRequested"] = grantsRequested as NSArray

        // Dates
        record["installedAt"] = installedAt as NSDate

        // Optionals
        record["version"] = version as NSString?
        record["scriptDescription"] = scriptDescription as NSString?
        record["author"] = author as NSString?
        record["sourceURL"] = sourceURL?.absoluteString as NSString?
        record["updateURL"] = updateURL?.absoluteString as NSString?
        record["lastUpdatedAt"] = lastUpdatedAt as NSDate?
        record["lastUpdateCheckAt"] = lastUpdateCheckAt as NSDate?
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> UserScript {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else {
            throw SyncError.missingRequiredField("recordID")
        }

        // Fetch existing or create new
        var descriptor = FetchDescriptor<UserScript>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let script: UserScript
        if let existing {
            script = existing
        } else {
            guard let name = record["name"] as? String else {
                throw SyncError.missingRequiredField("name")
            }
            guard let namespace = record["namespace"] as? String else {
                throw SyncError.missingRequiredField("namespace")
            }
            guard let source = record["source"] as? String else {
                throw SyncError.missingRequiredField("source")
            }
            script = UserScript(name: name, namespace: namespace, source: source)
            script.id = uuid
            context.insert(script)
        }

        // Update all properties from record
        script.name = record["name"] as? String ?? script.name
        script.namespace = record["namespace"] as? String ?? script.namespace

        if let source = record["source"] as? String {
            script.source = source
        }
        script.sourceHash = record["sourceHash"] as? String ?? script.sourceHash

        // Matching
        script.includePatterns = (record["includePatterns"] as? [String]) ?? []
        script.excludePatterns = (record["excludePatterns"] as? [String]) ?? []
        script.matchPatterns = (record["matchPatterns"] as? [String]) ?? []
        script.runAtFrames = (record["runAtFrames"] as? Bool) ?? true

        // Execution
        script.runAt = (record["runAt"] as? String)
            .flatMap(ScriptRunTime.init(rawValue:)) ?? .documentEnd
        script.isEnabled = (record["isEnabled"] as? Bool) ?? true

        // Permissions
        script.connectDomains = (record["connectDomains"] as? [String]) ?? []
        script.grantsRequested = (record["grantsRequested"] as? [String]) ?? []

        // Dates
        script.installedAt = record["installedAt"] as? Date ?? script.installedAt

        // Optionals
        script.version = record["version"] as? String
        script.scriptDescription = record["scriptDescription"] as? String
        script.author = record["author"] as? String
        script.sourceURL = (record["sourceURL"] as? String).flatMap(URL.init(string:))
        script.updateURL = (record["updateURL"] as? String).flatMap(URL.init(string:))
        script.lastUpdatedAt = record["lastUpdatedAt"] as? Date
        script.lastUpdateCheckAt = record["lastUpdateCheckAt"] as? Date

        return script
    }
}
