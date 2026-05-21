import CloudKit
import Testing

@testable import Refrax

@Suite("ConflictResolver", .serialized)
@MainActor
struct SyncConflictResolverTests {
    static let zoneID = RecordMapper.zoneID

    @Test("Later modification wins")
    func laterModificationWins() {
        let earlier = Date.now.addingTimeInterval(-60)
        let later = Date.now

        let clientRecord = CKRecord(recordType: "Tab", recordID: CKRecord.ID(
            recordName: UUID().uuidString, zoneID: Self.zoneID
        ))
        clientRecord["modifiedAt"] = later as NSDate

        let serverRecord = CKRecord(recordType: "Tab", recordID: clientRecord.recordID)
        serverRecord["modifiedAt"] = earlier as NSDate

        let winner = ConflictResolver.resolve(client: clientRecord, server: serverRecord)
        #expect(winner === clientRecord)
    }

    @Test("Server wins when timestamps equal")
    func serverWinsOnTie() {
        let same = Date.now

        let clientRecord = CKRecord(recordType: "Tab", recordID: CKRecord.ID(
            recordName: UUID().uuidString, zoneID: Self.zoneID
        ))
        clientRecord["modifiedAt"] = same as NSDate

        let serverRecord = CKRecord(recordType: "Tab", recordID: clientRecord.recordID)
        serverRecord["modifiedAt"] = same as NSDate

        let winner = ConflictResolver.resolve(client: clientRecord, server: serverRecord)
        #expect(winner === serverRecord)
    }

    @Test("Server wins when client has no timestamp")
    func serverWinsWithoutClientTimestamp() {
        let clientRecord = CKRecord(recordType: "Tab", recordID: CKRecord.ID(
            recordName: UUID().uuidString, zoneID: Self.zoneID
        ))

        let serverRecord = CKRecord(recordType: "Tab", recordID: clientRecord.recordID)
        serverRecord["modifiedAt"] = Date.now as NSDate

        let winner = ConflictResolver.resolve(client: clientRecord, server: serverRecord)
        #expect(winner === serverRecord)
    }
}
