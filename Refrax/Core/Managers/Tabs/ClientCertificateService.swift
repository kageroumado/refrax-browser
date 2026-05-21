import Foundation
import Security

/// Stateless helper for looking up client certificate identities in the user's keychain.
///
/// Used by ``BrowserNavigationDecider`` to fulfill
/// `NSURLAuthenticationMethodClientCertificate` challenges (mTLS).
enum ClientCertificateService {
    /// Returns identities from the user's keychain whose certificate was issued
    /// by one of the given DER-encoded distinguished names.
    ///
    /// When the server's challenge advertises no issuers (`issuers` is `nil` or
    /// empty), this returns every available identity so the user can still pick
    /// one. The keychain enforces user consent for accessing the private key.
    ///
    /// - Parameter issuers: DER-encoded issuer distinguished names from
    ///   `URLProtectionSpace.distinguishedNames`.
    /// - Returns: Matching identities, possibly empty.
    static func identities(matchingIssuers issuers: [Data]?) -> [SecIdentity] {
        var query: [CFString: Any] = [
            kSecClass: kSecClassIdentity,
            kSecReturnRef: true,
            kSecMatchLimit: kSecMatchLimitAll,
        ]

        if let issuers, !issuers.isEmpty {
            query[kSecMatchIssuers] = issuers
        }

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            return result as? [SecIdentity] ?? []
        case errSecItemNotFound:
            return []
        default:
            Logger.warning(
                "Keychain identity lookup failed: OSStatus \(status)",
                category: Logger.security,
            )
            return []
        }
    }
}
