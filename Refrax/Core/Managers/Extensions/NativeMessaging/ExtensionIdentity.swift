import CryptoKit
import Foundation

/// The identifiers other browsers know an extension by, read from its manifest: the Chrome
/// extension ID that its `key` hashes to, and the Firefox add-on ID it declares.
///
/// Native messaging hosts name the extensions they serve by these: Chrome-format host
/// manifests list `chrome-extension://<id>/` origins, Firefox-format ones list add-on IDs.
nonisolated struct ExtensionIdentity: Equatable, Sendable {
    /// The 32-letter Chrome extension ID, when the manifest carries a `key`.
    let chromeID: String?
    /// The Firefox add-on ID from `browser_specific_settings.gecko.id` or `applications.gecko.id`.
    let geckoID: String?

    init(chromeID: String?, geckoID: String?) {
        self.chromeID = chromeID
        self.geckoID = geckoID
    }

    /// Reads the identity from a parsed `manifest.json`.
    init(manifest: [String: Any]) {
        let key = (manifest["key"] as? String).flatMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
        self.chromeID = key.map(Self.chromeID(forPublicKey:))
        let settings = manifest["browser_specific_settings"] as? [String: Any] ?? manifest["applications"] as? [String: Any]
        self.geckoID = (settings?["gecko"] as? [String: Any])?["id"] as? String
    }

    /// The origin Chrome gives the extension and lists in `allowed_origins`.
    var chromeOrigin: String? {
        chromeID.map { "chrome-extension://\($0)/" }
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
