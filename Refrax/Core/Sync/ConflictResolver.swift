import CloudKit

/// Resolves sync conflicts using last-write-wins (LWW) with delete-wins semantics.
///
/// When a push fails with `serverRecordChanged`, CKSyncEngine provides the client record
/// (what we tried to push) and the server record (current CloudKit state). We compare the
/// custom `modifiedAt` field (set from SwiftData history transaction timestamps) to determine
/// which version wins.
///
/// Tie-breaking: server wins. This is safe because the server record is already persisted
/// in CloudKit, so choosing it avoids an unnecessary re-push.
nonisolated enum ConflictResolver {
    /// Resolves a conflict between client and server records.
    ///
    /// - Returns: The winning record. The caller should apply the winner's data locally
    ///   and push it using the server record's system fields to avoid a second conflict.
    static func resolve(client: CKRecord, server: CKRecord) -> CKRecord {
        let clientDate = client["modifiedAt"] as? Date ?? .distantPast
        let serverDate = server["modifiedAt"] as? Date ?? .distantPast

        if clientDate > serverDate {
            return client
        }
        return server
    }
}
