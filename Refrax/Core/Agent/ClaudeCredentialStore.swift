import Foundation
import Security

/// Keychain-backed credential store for agent providers.
///
/// Stores one API key per provider under a distinct Keychain service name,
/// so credentials for different providers never collide. The `@Sendable`
/// APIs are all synchronous and thread-safe — ``SecItem`` is safe to call
/// from any queue.
///
/// ## Accounts
///
/// | Provider | Service | Account |
/// |---|---|---|
/// | `.claudeAPI` | `website.refrax.browser.claude-credentials` | `anthropic-api-key` |
/// | `.openAI` | `website.refrax.browser.openai-credentials` | `openai-api-key` |
/// | `.openRouter` | `website.refrax.browser.openrouter-credentials` | `openrouter-api-key` |
/// | `.custom` | `website.refrax.browser.custom-credentials` | `custom-api-key` |
///
/// The Claude service name is preserved from earlier releases; see
/// ``deleteLegacyOAuthCredentials()`` for one-time cleanup of removed
/// OAuth accounts.
nonisolated enum AgentCredentialStore {
    // MARK: - Provider-Specific Keychain Coordinates

    /// Returns the Keychain `kSecAttrService` for a provider.
    static func service(for provider: AgentProviderKind) -> String {
        switch provider {
        case .claudeAPI: "website.refrax.browser.claude-credentials"
        case .openAI: "website.refrax.browser.openai-credentials"
        case .openRouter: "website.refrax.browser.openrouter-credentials"
        case .custom: "website.refrax.browser.custom-credentials"
        }
    }

    /// Returns the Keychain `kSecAttrAccount` for a provider.
    static func account(for provider: AgentProviderKind) -> String {
        switch provider {
        case .claudeAPI: "anthropic-api-key"
        case .openAI: "openai-api-key"
        case .openRouter: "openrouter-api-key"
        case .custom: "custom-api-key"
        }
    }

    // MARK: - Generic API

    /// Stores an API key for the given provider in the Keychain.
    ///
    /// An empty key is treated as a deletion.
    static func storeAPIKey(_ key: String, for provider: AgentProviderKind) {
        guard !key.isEmpty else {
            deleteAPIKey(for: provider)
            return
        }
        setKeychainValue(key, service: service(for: provider), account: account(for: provider))
    }

    /// Loads the stored API key for the given provider, if any.
    static func loadAPIKey(for provider: AgentProviderKind) -> String? {
        getKeychainValue(service: service(for: provider), account: account(for: provider))
    }

    /// Deletes the stored API key for the given provider.
    static func deleteAPIKey(for provider: AgentProviderKind) {
        deleteKeychainValue(service: service(for: provider), account: account(for: provider))
    }

    /// Whether an API key is stored for the given provider.
    static func hasAPIKey(for provider: AgentProviderKind) -> Bool {
        loadAPIKey(for: provider) != nil
    }

    // MARK: - Keychain Helpers

    private static func setKeychainValue(_ value: String, service: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }

        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked,
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    private static func getKeychainValue(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteKeychainValue(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Keychain-backed credential store for the Anthropic Messages API.
///
/// Thin compatibility shim over ``AgentCredentialStore`` preserved so the
/// rest of the app keeps compiling without a sweeping rename. New code
/// should prefer ``AgentCredentialStore`` directly.
nonisolated enum ClaudeCredentialStore {
    /// Legacy OAuth keychain account names retained only for migration cleanup.
    private static let legacyOAuthService = "website.refrax.browser.claude-credentials"
    private static let legacyOAuthAccessAccount = "anthropic-oauth-access"
    private static let legacyOAuthRefreshAccount = "anthropic-oauth-refresh"
    private static let legacyOAuthExpiryAccount = "anthropic-oauth-expiry"

    // MARK: - API Key

    /// Stores an Anthropic API key in the Keychain.
    static func storeAPIKey(_ key: String) {
        AgentCredentialStore.storeAPIKey(key, for: .claudeAPI)
    }

    /// Loads the stored Anthropic API key from the Keychain, if any.
    static func loadAPIKey() -> String? {
        AgentCredentialStore.loadAPIKey(for: .claudeAPI)
    }

    /// Deletes the stored Anthropic API key from the Keychain.
    static func deleteAPIKey() {
        AgentCredentialStore.deleteAPIKey(for: .claudeAPI)
    }

    // MARK: - Unified Credential

    /// Returns the active Claude credential based on what's stored.
    static func activeCredential() -> ClaudeCredential? {
        loadAPIKey().map { .apiKey($0) }
    }

    /// Whether any Claude credential is stored.
    static var hasCredential: Bool {
        activeCredential() != nil
    }

    /// Deletes all stored Claude credentials.
    static func deleteAll() {
        deleteAPIKey()
        deleteLegacyOAuthCredentials()
    }

    // MARK: - Legacy OAuth Migration

    /// Removes the three OAuth keychain accounts from any previous release.
    ///
    /// Safe to call repeatedly; missing accounts are a no-op. Invoked once
    /// on first launch after upgrading past the OAuth removal.
    static func deleteLegacyOAuthCredentials() {
        deleteLegacyKeychainValue(account: legacyOAuthAccessAccount)
        deleteLegacyKeychainValue(account: legacyOAuthRefreshAccount)
        deleteLegacyKeychainValue(account: legacyOAuthExpiryAccount)
    }

    private static func deleteLegacyKeychainValue(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: legacyOAuthService,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Types

/// Unified credential type for the Claude client.
nonisolated enum ClaudeCredential: Sendable {
    case apiKey(String)

    /// The token string for API requests.
    var token: String {
        switch self {
        case let .apiKey(key): key
        }
    }
}
