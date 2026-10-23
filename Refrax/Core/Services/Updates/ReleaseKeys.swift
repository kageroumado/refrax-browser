import CryptoKit
import Foundation

/// The Ed25519 public keys that sign what Refrax downloads to run: app update DMGs and engine
/// releases, with the engine catalog.
///
/// Pinned in Info.plist as `RefraxEDPublicKeys`, each a base64 raw 32-byte key. A signature is
/// accepted when any pinned key verifies it, which is how the release key rotates without
/// stranding an install: a release ships the new key beside the old one and is itself signed
/// with the old key (installed copies check it with the keys *they* pin), later releases are
/// signed with the new key, and the old key leaves the list once installs carry the new one.
nonisolated struct ReleaseKeys: Sendable {
    /// The Info.plist key holding the pinned keys.
    static let infoKey = "RefraxEDPublicKeys"

    let keys: [Curve25519.Signing.PublicKey]

    init(_ keys: [Curve25519.Signing.PublicKey]) {
        self.keys = keys
    }

    /// Parses an Info.plist value: a non-empty array of base64 raw Ed25519 public keys. Nil
    /// for anything else, including one malformed entry, so a typo fails loudly in tests
    /// instead of silently narrowing what verifies.
    init?(infoValue: Any?) {
        guard let entries = infoValue as? [String], !entries.isEmpty else { return nil }
        var keys: [Curve25519.Signing.PublicKey] = []
        for entry in entries {
            guard let raw = Data(base64Encoded: entry),
                  let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw)
            else { return nil }
            keys.append(key)
        }
        self.keys = keys
    }

    /// The keys pinned in `bundle`; nil when it pins none.
    static func pinned(in bundle: Bundle = .main) -> ReleaseKeys? {
        ReleaseKeys(infoValue: bundle.object(forInfoDictionaryKey: infoKey))
    }

    /// Whether `signature` over `message` verifies against any of the keys.
    func isValidSignature(_ signature: Data, for message: some DataProtocol) -> Bool {
        keys.contains { $0.isValidSignature(signature, for: message) }
    }
}
