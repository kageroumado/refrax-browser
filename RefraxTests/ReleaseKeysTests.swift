import CryptoKit
import Foundation
@testable import Refrax
import Testing

@Suite("Release signing keys")
struct ReleaseKeysTests {
    private let first = Curve25519.Signing.PrivateKey()
    private let second = Curve25519.Signing.PrivateKey()

    private func entry(_ key: Curve25519.Signing.PrivateKey) -> String {
        key.publicKey.rawRepresentation.base64EncodedString()
    }

    @Test("A list of base64 keys parses, in order")
    func parsesList() throws {
        let keys = try #require(ReleaseKeys(infoValue: [entry(first), entry(second)]))
        #expect(keys.keys.map(\.rawRepresentation) == [first.publicKey.rawRepresentation, second.publicKey.rawRepresentation])
    }

    @Test("A missing, empty, single-string or malformed value pins nothing")
    func rejectsMalformed() {
        #expect(ReleaseKeys(infoValue: nil) == nil)
        #expect(ReleaseKeys(infoValue: [String]()) == nil)
        #expect(ReleaseKeys(infoValue: entry(first)) == nil)
        #expect(ReleaseKeys(infoValue: [entry(first), "not a key"]) == nil)
        #expect(ReleaseKeys(infoValue: [entry(first), Data(count: 31).base64EncodedString()]) == nil)
    }

    @Test("A signature by any pinned key verifies; one by another key doesn't")
    func verifiesAgainstAnyKey() throws {
        let message = Data("Refrax-0.36.0.dmg".utf8)
        let keys = ReleaseKeys([first.publicKey, second.publicKey])
        #expect(try keys.isValidSignature(first.signature(for: message), for: message))
        #expect(try keys.isValidSignature(second.signature(for: message), for: message))
        #expect(try !keys.isValidSignature(Curve25519.Signing.PrivateKey().signature(for: message), for: message))
        #expect(try !keys.isValidSignature(first.signature(for: message), for: Data("Refrax-0.36.1.dmg".utf8)))
    }

    /// Installs check every update with the keys they pin, so dropping a key before installs
    /// carry its successor strands them. The second key signs releases through 0.36.0.
    @Test("The app pins the 2026-10 key and the key earlier releases are signed with")
    func appPinsBothKeys() throws {
        let keys = try #require(ReleaseKeys.pinned())
        #expect(keys.keys.map { $0.rawRepresentation.base64EncodedString() } == [
            "TGknB8k6iJu+iFdB57Fj+2wmldlbCAMYyrUcq5IOHKg=",
            "PZpeAoItKlJVbxk8kQTIe0Q4WikXTOP1jKSaZEch9NI=",
        ])
    }
}
