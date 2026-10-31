import CryptoKit
import Foundation

/// Who an extension is, as native messaging hosts decide whom to serve.
///
/// Chrome-format host manifests list `chrome-extension://<id>/` origins and Firefox-format ones
/// list add-on IDs. Only a Chrome ID proven by a CRX signature at install is trusted; an ID the
/// manifest merely states (its `key`, its `browser_specific_settings.gecko.id`) can be copied
/// by any sideloaded extension, so a host reached through one needs the user's consent. Hosts
/// in Refrax's own folder name the extension by the origin Refrax serves it from.
nonisolated struct ExtensionIdentity: Equatable, Sendable {
    /// The Chrome ID of the developer key that signed the extension's CRX.
    let verifiedChromeID: String?
    /// The Chrome ID the manifest's `key` hashes to; unverified.
    let claimedChromeID: String?
    /// The Firefox add-on ID the manifest declares; unverified.
    let claimedGeckoID: String?
    /// `webkit-extension://<context identifier>/`, stable for an installation.
    let refraxOrigin: String

    init(verifiedChromeID: String?, claimedChromeID: String?, claimedGeckoID: String?, refraxOrigin: String) {
        self.verifiedChromeID = verifiedChromeID
        self.claimedChromeID = claimedChromeID
        self.claimedGeckoID = claimedGeckoID
        self.refraxOrigin = refraxOrigin
    }

    /// The identity of an extension with `manifest`, served from `refraxOrigin`, whose CRX
    /// proved `verifiedChromeID` at install.
    init(manifest: [String: Any], verifiedChromeID: String?, refraxOrigin: String) {
        let key = (manifest["key"] as? String).flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
        let settings = manifest["browser_specific_settings"] as? [String: Any] ?? manifest["applications"] as? [String: Any]
        self.init(
            verifiedChromeID: verifiedChromeID,
            claimedChromeID: key.map(Self.chromeID(forPublicKey:)),
            claimedGeckoID: (settings?["gecko"] as? [String: Any])?["id"] as? String,
            refraxOrigin: refraxOrigin,
        )
    }

    static func chromeOrigin(_ chromeID: String) -> String {
        "chrome-extension://\(chromeID)/"
    }

    /// Chrome's extension ID for a DER public key: the first 16 bytes of its SHA-256, each
    /// hex digit written as the letter that many places after `a`.
    static func chromeID(forPublicKey key: Data) -> String {
        let letters = Array("abcdefghijklmnop")
        return String(SHA256.hash(data: key).prefix(16).flatMap { byte in
            [letters[Int(byte >> 4)], letters[Int(byte & 0xF)]]
        })
    }
}
