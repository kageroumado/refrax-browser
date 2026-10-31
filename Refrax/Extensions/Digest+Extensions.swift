import CryptoKit

nonisolated extension Digest {
    /// The digest as lowercase hex.
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
