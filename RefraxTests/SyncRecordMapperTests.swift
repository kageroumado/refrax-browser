import CloudKit
@testable import Refrax
import Testing

@Suite("RecordMapper Utilities", .serialized)
@MainActor
struct SyncRecordMapperTests {
    // The production constant switches zone names between debug and release
    // builds, so tests must compare against it rather than a literal name
    static let zoneID = RecordMapper.zoneID

    @Test("Record ID from UUID")
    func recordIDFromUUID() {
        let uuid = UUID()
        let recordID = RecordMapper.recordID(for: uuid)
        #expect(recordID.recordName == uuid.uuidString)
        #expect(recordID.zoneID == Self.zoneID)
    }

    @Test("UUID from record ID")
    func uuidFromRecordID() {
        let uuid = UUID()
        let recordID = CKRecord.ID(recordName: uuid.uuidString, zoneID: Self.zoneID)
        let extracted = RecordMapper.uuid(from: recordID)
        #expect(extracted == uuid)
    }

    @Test("UUID from invalid record ID returns nil")
    func uuidFromInvalidRecordID() {
        let recordID = CKRecord.ID(recordName: "not-a-uuid", zoneID: Self.zoneID)
        let extracted = RecordMapper.uuid(from: recordID)
        #expect(extracted == nil)
    }

    @Test("Encode and decode CKRecord system fields")
    func systemFieldsRoundTrip() throws {
        let record = CKRecord(recordType: "Tab", recordID: CKRecord.ID(
            recordName: UUID().uuidString, zoneID: Self.zoneID
        ))
        let data = RecordMapper.encodeSystemFields(of: record)
        let decoded = try RecordMapper.decodeSystemFields(from: data)
        #expect(decoded.recordID == record.recordID)
        #expect(decoded.recordType == record.recordType)
    }

    @Test("CKRecord.Reference from UUID")
    func referenceFromUUID() {
        let uuid = UUID()
        let ref = RecordMapper.reference(to: uuid, recordType: "Space", action: .deleteSelf)
        #expect(ref.recordID.recordName == uuid.uuidString)
    }
}
