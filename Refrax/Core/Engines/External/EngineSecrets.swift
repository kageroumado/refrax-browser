import Foundation
import Security

/// Key material engines ask Refrax for (`Engines/CONTRACT.md` §4.6), such as the key an engine
/// encrypts its cookies with.
///
/// One keychain item per engine and secret name, created on the first request: 32 random bytes,
/// the same on every later request. Items live in the data protection keychain, where access
/// follows Refrax's entitlements rather than an access list, so reading one never prompts. An
/// engine keeping its own item would prompt after any update signed differently, from a
/// process with no window to show the prompt in.
nonisolated enum EngineSecrets {
    /// Length of every secret, in bytes.
    static let secretSize = 32

    /// Per app, like the engines' data directories: debug and release Refrax share a keychain
    /// access group but not their engines' data.
    static let service = "\(Bundle.main.bundleIdentifier ?? "website.refrax.browser").engine-secrets"

    /// The secret `name` for `engine`, created if it doesn't exist yet, or nil when the keychain
    /// can't be read (it is locked). Blocks on the keychain: call it off the main actor.
    static func secret(named name: String, for engine: EngineID) -> Data? {
        let account = account(name, engine)
        if let existing = read(account) {
            return existing
        }
        var bytes = Data(count: secretSize)
        let generated = bytes.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, secretSize, $0.baseAddress!) }
        guard generated == errSecSuccess else { return nil }

        var add = baseQuery(account)
        add[kSecValueData as String] = bytes
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        switch SecItemAdd(add as CFDictionary, nil) {
        case errSecSuccess:
            return bytes
        case errSecDuplicateItem:
            // Another request created it first; every caller must get the same secret.
            return read(account)
        case let status:
            Logger.warning("Could not store engine secret \(account): \(status)", category: Logger.engines)
            return nil
        }
    }

    /// Deletes every secret stored for `engine`.
    static func removeSecrets(for engine: EngineID) {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return }
        let prefix = "\(engine.rawValue)/"
        query = baseQuery("")
        for account in items.compactMap({ $0[kSecAttrAccount as String] as? String }) where account.hasPrefix(prefix) {
            query[kSecAttrAccount as String] = account
            SecItemDelete(query as CFDictionary)
        }
    }

    private static func account(_ name: String, _ engine: EngineID) -> String {
        "\(engine.rawValue)/\(name)"
    }

    private static func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private static func read(_ account: String) -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data, data.count == secretSize else { return nil }
        return data
    }
}
