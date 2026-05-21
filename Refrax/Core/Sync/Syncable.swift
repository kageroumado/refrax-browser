import CloudKit
import SwiftData

/// A model that can be synced to CloudKit via CKSyncEngine.
///
/// Conforming types provide their CloudKit record type name and
/// encode/decode logic for converting between SwiftData models and CKRecords.
protocol Syncable: PersistentModel {
    /// The CKRecord type name in CloudKit (e.g., "Tab", "Space").
    /// By convention, matches the Swift type name.
    nonisolated static var ckRecordType: String { get }

    /// Encodes this model's properties into a CKRecord for upload.
    ///
    /// Should NOT encode:
    /// - Favicon data (re-derived from websites on target device)
    /// - Transient/computed properties
    /// - The `id` property (already encoded as the CKRecord.ID)
    ///
    /// Marked `nonisolated` so it can be called from the sync actor's context.
    nonisolated func encodeToRecord(_ record: CKRecord)

    /// Creates or updates a model from a CKRecord received from CloudKit.
    ///
    /// If a model with the same UUID exists in `context`, updates it in place.
    /// Otherwise, creates a new instance. Throws on malformed records.
    ///
    /// Marked `nonisolated` so it can be called from the sync actor's context.
    ///
    /// - Returns: The created or updated model instance.
    @discardableResult
    nonisolated static func applyRecord(_ record: CKRecord, into context: ModelContext) throws -> Self
}

// MARK: - Default Implementations

extension Syncable {
    /// Default: uses the Swift type name as the CKRecord type.
    nonisolated static var ckRecordType: String {
        String(describing: Self.self)
    }
}

// MARK: - Syncable Type Registry

/// Registry of all syncable model type names, used to filter SwiftData history changes.
///
/// When processing history transactions, only changes whose `entityName` appears in this
/// set are forwarded to the sync engine. All other changes (CachedFavicon, Download, etc.)
/// are silently skipped.
nonisolated enum SyncableTypeRegistry {
    /// Entity names of all 25 syncable model types.
    static let syncableEntityNames: Set<String> = [
        "Tab", "TabPage", "Space", "TabGroup",
        "Bookmark", "BookmarkFolder",
        "HistoryEntry", "BrowsingContext",
        "BrowserSettings", "SiteSettings", "PrivacyProtectionSettings",
        "CustomSearchEngine", "CustomRedirect", "AppRedirectRule",
        "ExternalURLRule", "ExternalURLSettings", "SourceAppRule",
        "RoutingRule", "ArchiveRule",
        "UserScript", "UserStyle",
        "FocusModeMapping", "AppShortcut", "SavedFilter", "DomainTimeLimit",
    ]

    /// Maps entity names to their CKRecord type. For now, all 1:1 with the entity name.
    static let entityToCKRecordType: [String: String] = {
        Dictionary(uniqueKeysWithValues: syncableEntityNames.map { ($0, $0) })
    }()

    /// Checks whether a history change's entity is syncable.
    static func isSyncable(entityName: String) -> Bool {
        syncableEntityNames.contains(entityName)
    }
}
