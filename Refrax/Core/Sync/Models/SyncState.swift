import SwiftData

/// Singleton tracking overall sync engine state.
///
/// Lives in the sync metadata store. Stores the SwiftData history token (for change detection),
/// the CKSyncEngine state serialization (for resume across launches), and the iCloud account hash
/// (for detecting account switches).
@Model final class SyncState {
    /// Encoded `DefaultHistoryToken` — tracks position in SwiftData's persistent history.
    var historyToken: Data?

    /// Encoded `CKSyncEngine.State.Serialization` — required for the engine to resume
    /// from where it left off instead of doing a full re-sync on every launch.
    var engineState: Data?

    /// When the last full sync cycle completed successfully.
    var lastFullSyncAt: Date?

    /// Hash of the current iCloud account identifier. Used to detect account switches.
    var accountID: String?

    init() {}

    /// Fetches the singleton SyncState, creating one if it doesn't exist.
    static func fetchOrCreate(in context: ModelContext) -> SyncState {
        var descriptor = FetchDescriptor<SyncState>()
        descriptor.fetchLimit = 1
        if let existing = try? context.fetch(descriptor).first {
            return existing
        }
        let state = SyncState()
        context.insert(state)
        try? context.save()
        return state
    }
}
