import CloudKit
import SwiftData

/// Tracks CloudKit system fields for a synced model instance.
///
/// Lives in a separate sync metadata store (`sync.store`), not the main app store.
/// Each SyncRecord maps a domain model (by type + UUID) to its CloudKit record state.
@Model final class SyncRecord {
    /// The entity name of the synced model (e.g., "Tab", "Space").
    var modelType: String

    /// The UUID string of the domain model's `id` property.
    var modelID: String

    /// Opaque CKRecord system fields, required to update existing records without conflicts.
    /// Encoded via `CKRecord.encodeSystemFields(with:)`.
    var ckSystemFields: Data

    /// When this record was last successfully pushed to or pulled from CloudKit.
    var lastSyncedAt: Date

    init(modelType: String, modelID: String, ckSystemFields: Data, lastSyncedAt: Date = .now) {
        self.modelType = modelType
        self.modelID = modelID
        self.ckSystemFields = ckSystemFields
        self.lastSyncedAt = lastSyncedAt
    }
}
