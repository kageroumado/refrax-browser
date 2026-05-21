import CloudKit
import SwiftData

extension CustomSearchEngine: Syncable {
    nonisolated static var ckRecordType: String { "CustomSearchEngine" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["name"] = name as NSString
        record["alias"] = alias as NSString
        record["searchURLTemplate"] = searchURLTemplate as NSString
        record["parserKindRaw"] = parserKindRaw as NSString
        record["iconName"] = iconName as NSString
        record["sortOrder"] = sortOrder as NSNumber
        record["isAutoDetected"] = isAutoDetected as NSNumber

        // Dates
        record["createdAt"] = createdAt as NSDate

        // Optionals
        record["suggestionURLTemplate"] = suggestionURLTemplate as NSString?
        record["sourceDomain"] = sourceDomain as NSString?
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> CustomSearchEngine {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else {
            throw SyncError.missingRequiredField("recordID")
        }

        // Fetch existing or create new
        var descriptor = FetchDescriptor<CustomSearchEngine>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let engine: CustomSearchEngine
        if let existing {
            engine = existing
        } else {
            guard let name = record["name"] as? String else {
                throw SyncError.missingRequiredField("name")
            }
            guard let alias = record["alias"] as? String else {
                throw SyncError.missingRequiredField("alias")
            }
            guard let searchURLTemplate = record["searchURLTemplate"] as? String else {
                throw SyncError.missingRequiredField("searchURLTemplate")
            }
            engine = CustomSearchEngine(
                id: uuid,
                name: name,
                alias: alias,
                searchURLTemplate: searchURLTemplate
            )
            context.insert(engine)
        }

        // Update all properties from record
        engine.name = record["name"] as? String ?? engine.name
        engine.alias = record["alias"] as? String ?? engine.alias
        engine.searchURLTemplate = record["searchURLTemplate"] as? String ?? engine.searchURLTemplate
        engine.parserKindRaw = record["parserKindRaw"] as? String
            ?? SuggestionParserKind.openSearch.rawValue
        engine.iconName = record["iconName"] as? String ?? "globe"
        engine.sortOrder = (record["sortOrder"] as? Int) ?? 0
        engine.isAutoDetected = (record["isAutoDetected"] as? Bool) ?? false
        engine.createdAt = record["createdAt"] as? Date ?? engine.createdAt

        // Optionals
        engine.suggestionURLTemplate = record["suggestionURLTemplate"] as? String
        engine.sourceDomain = record["sourceDomain"] as? String

        return engine
    }
}
