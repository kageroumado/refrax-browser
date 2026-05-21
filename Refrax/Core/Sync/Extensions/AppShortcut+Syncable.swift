import CloudKit
import SwiftData

extension AppShortcut: Syncable {
    nonisolated static var ckRecordType: String { "AppShortcut" }

    nonisolated func encodeToRecord(_ record: CKRecord) {
        // Scalars
        record["typeRawValue"] = shortcutType.rawValue as NSString
        record["positionValue"] = positionValue as NSNumber

        // Optionals
        record["customColor"] = customColor as NSString?
        record["customName"] = customName as NSString?
    }

    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> AppShortcut {
        guard let uuid = RecordMapper.uuid(from: record.recordID) else {
            throw SyncError.missingRequiredField("recordID")
        }

        // Fetch existing or create new
        var descriptor = FetchDescriptor<AppShortcut>(predicate: #Predicate { $0.id == uuid })
        descriptor.fetchLimit = 1
        let existing = try? context.fetch(descriptor).first

        let shortcut: AppShortcut
        if let existing {
            shortcut = existing
        } else {
            let typeRaw = record["typeRawValue"] as? String ?? AppShortcutType.settings.rawValue
            let type = AppShortcutType(rawValue: typeRaw) ?? .settings
            shortcut = AppShortcut(type: type)
            shortcut.id = uuid
            context.insert(shortcut)
        }

        // Update all properties from record
        if let typeRaw = record["typeRawValue"] as? String,
           let type = AppShortcutType(rawValue: typeRaw)
        {
            shortcut.shortcutType = type
        }
        shortcut.positionValue = (record["positionValue"] as? Int) ?? 0
        shortcut.customColor = record["customColor"] as? String
        shortcut.customName = record["customName"] as? String

        return shortcut
    }
}
