import CloudKit

/// Shared utilities for converting between SwiftData models and CKRecords.
///
/// Per-model encoding/decoding lives in the `+Syncable` extensions.
/// This type provides the common infrastructure they all use.
nonisolated enum RecordMapper {
    /// The CloudKit zone for all Refrax sync data.
    ///
    /// Debug and release builds use separate zones to prevent data cross-contamination,
    /// since they have separate local databases (different bundle IDs).
    static let zoneID: CKRecordZone.ID = {
        #if DEBUG
        let zoneName = "RefraxSync-Debug"
        #else
        let zoneName = "RefraxSync"
        #endif
        return CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)
    }()

    // MARK: - Record ID Conversion

    /// Creates a deterministic CKRecord.ID from a model's UUID.
    static func recordID(for uuid: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: uuid.uuidString, zoneID: zoneID)
    }

    /// Extracts the UUID from a CKRecord.ID's record name.
    static func uuid(from recordID: CKRecord.ID) -> UUID? {
        UUID(uuidString: recordID.recordName)
    }

    // MARK: - System Fields

    /// Encodes a CKRecord's system fields to opaque Data for storage in SyncRecord.
    static func encodeSystemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    /// Decodes a CKRecord from previously stored system fields.
    ///
    /// The returned record contains only system fields (record ID, change tag, etc.).
    /// Set your custom fields on this record before pushing to CloudKit.
    static func decodeSystemFields(from data: Data) throws -> CKRecord {
        let coder = try NSKeyedUnarchiver(forReadingFrom: data)
        coder.requiresSecureCoding = true
        guard let record = CKRecord(coder: coder) else {
            throw SyncError.corruptSystemFields
        }
        coder.finishDecoding()
        return record
    }

    // MARK: - References

    /// Creates a CKRecord.Reference pointing to a model by UUID.
    static func reference(
        to uuid: UUID,
        recordType: String,
        action: CKRecord.ReferenceAction
    ) -> CKRecord.Reference {
        CKRecord.Reference(
            recordID: recordID(for: uuid),
            action: action
        )
    }

    /// Creates a CKRecord.Reference from an optional UUID. Returns nil if UUID is nil.
    static func optionalReference(
        to uuid: UUID?,
        recordType: String,
        action: CKRecord.ReferenceAction
    ) -> CKRecord.Reference? {
        guard let uuid else { return nil }
        return reference(to: uuid, recordType: recordType, action: action)
    }

    // MARK: - New Record

    /// Creates a fresh CKRecord for a model, or restores one from stored system fields.
    ///
    /// If `systemFieldsData` is provided (from a previous sync), the record is decoded
    /// from it to preserve the change tag. Otherwise, a new record is created.
    static func record(
        for uuid: UUID,
        recordType: String,
        systemFieldsData: Data?
    ) throws -> CKRecord {
        if let data = systemFieldsData {
            return try decodeSystemFields(from: data)
        }
        return CKRecord(
            recordType: recordType,
            recordID: recordID(for: uuid)
        )
    }
}

// MARK: - Errors

nonisolated enum SyncError: Error, LocalizedError {
    case corruptSystemFields
    case missingRequiredField(String)
    case unknownRecordType(String)
    case modelNotFound(UUID)

    var errorDescription: String? {
        switch self {
        case .corruptSystemFields:
            "Failed to decode CloudKit system fields"
        case .missingRequiredField(let field):
            "CKRecord missing required field: \(field)"
        case .unknownRecordType(let type):
            "Unknown CKRecord type: \(type)"
        case .modelNotFound(let uuid):
            "Model not found for UUID: \(uuid)"
        }
    }
}
