import CryptoKit
import Foundation

/// The unique identifier, and with it the `webkit-extension://` base URL, an installed
/// extension's context gets in each controller.
///
/// WebKit gives a new context a random identifier, and keys the extension's storage
/// (`storage.local`, granted permissions, dynamic rules, registered scripts) and its pages'
/// origin by it. A random identifier per launch would leave every extension with empty
/// storage after a relaunch, so Refrax derives it from the installation: the installed
/// extension's identifier in the default controller, and a name-based UUID of the space and
/// the extension in a space's own controller, so each context keeps a base URL of its own.
nonisolated enum ExtensionContextIdentifier {
    /// The identifier for `installedID`'s context in the controller of `spaceID`, or in the
    /// default controller when `spaceID` is `nil`. Always a lowercase UUID, which is valid as
    /// a URL host.
    static func identifier(installedID: String, spaceID: UUID?) -> String {
        if spaceID == nil, let uuid = UUID(uuidString: installedID) {
            return uuid.uuidString.lowercased()
        }
        let name = "\(spaceID?.uuidString ?? "default")/\(installedID)"
        var bytes = Array(SHA256.hash(data: Data(name.utf8)).prefix(16))
        // RFC 9562 name-based layout: version 8, variant 10.
        bytes[6] = bytes[6] & 0x0F | 0x80
        bytes[8] = bytes[8] & 0x3F | 0x80
        let uuid = UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15],
        ))
        return uuid.uuidString.lowercased()
    }

    /// The base URL WebKit serves a context with `identifier` from.
    static func baseURL(for identifier: String) -> URL {
        URL(string: "webkit-extension://\(identifier)/")!
    }
}
