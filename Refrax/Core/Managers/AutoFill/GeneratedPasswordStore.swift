import Foundation
import os

/// Stores recently generated passwords in RAM only.
///
/// ## Security Design
///
/// Generated passwords are stored **only in memory** with aggressive expiration:
/// - **No disk persistence**: Passwords never touch the filesystem
/// - **Short TTL**: 5-minute expiration (covers typical signup flow)
/// - **Automatic pruning**: Expired entries removed on every access
/// - **Single entry per domain**: New generation replaces old
/// - **Cleared on app termination**: Memory is released when app exits
/// - **Entry limit**: Maximum 5 passwords stored at once
///
/// ## Attack Vectors Mitigated
///
/// - **Filesystem access**: No disk storage means no file to steal
/// - **Memory dumps**: Short TTL limits exposure window
/// - **Cross-session attacks**: Passwords don't survive app restart
/// - **Memory exhaustion**: Entry limit prevents unbounded growth
///
/// ## Usage
/// ```swift
/// let store = GeneratedPasswordStore.shared
/// let password = store.generatePassword(for: "github.com")
/// let recent = store.recentlyGeneratedPassword(for: "github.com")
/// ```
final class GeneratedPasswordStore {
    // MARK: - Singleton

    /// Shared instance for app-wide access.
    static let shared = GeneratedPasswordStore()

    // MARK: - Configuration

    /// How long generated passwords are kept before expiring (in seconds).
    ///
    /// Short TTL (5 minutes) balances usability with security:
    /// - Long enough to complete a typical signup flow
    /// - Short enough to limit exposure if memory is compromised
    private nonisolated static let expirationInterval: TimeInterval = 5 * 60

    /// Maximum number of passwords to store at once.
    ///
    /// Limits memory footprint and attack surface.
    private nonisolated static let maxStoredPasswords = 5

    // MARK: - Storage

    private struct GeneratedPassword: Sendable {
        let password: String
        let domain: String
        let generatedAt: Date

        nonisolated func isExpired(interval: TimeInterval) -> Bool {
            Date().timeIntervalSince(generatedAt) > interval
        }
    }

    private nonisolated let passwords = OSAllocatedUnfairLock(initialState: [String: GeneratedPassword]())

    // MARK: - Initialization

    private init() {
        // RAM-only storage - no disk loading
    }

    // MARK: - Public API

    /// Generates a new password for the given domain and stores it in RAM.
    ///
    /// - Parameters:
    ///   - domain: The domain (e.g., "github.com") to generate a password for.
    ///   - rules: Optional password rules from the website's quirks database.
    /// - Returns: The newly generated password.
    func generatePassword(for domain: String, rules: PasswordRules? = nil) -> String {
        let password = PasswordGenerator.generateStrongPassword(rules: rules)
        let normalizedDomain = normalizeDomain(domain)

        passwords.withLock { passwords in
            Self.pruneExpired(&passwords)
            Self.enforceMaxEntries(&passwords)

            passwords[normalizedDomain] = GeneratedPassword(
                password: password,
                domain: normalizedDomain,
                generatedAt: Date(),
            )
        }

        Logger.debug("Generated new password for \(normalizedDomain)", category: Logger.autoFill)

        return password
    }

    /// Gets the most recently generated password for a domain, if not expired.
    ///
    /// - Parameter domain: The domain to look up.
    /// - Returns: The recently generated password, or `nil` if none exists or it's expired.
    func recentlyGeneratedPassword(for domain: String) -> String? {
        let normalizedDomain = normalizeDomain(domain)

        return passwords.withLock { passwords in
            Self.pruneExpired(&passwords)

            guard let entry = passwords[normalizedDomain],
                  !entry.isExpired(interval: Self.expirationInterval)
            else {
                passwords.removeValue(forKey: normalizedDomain)
                return nil
            }

            return entry.password
        }
    }

    /// Clears the generated password for a domain.
    ///
    /// Call this when a credential is successfully saved.
    ///
    /// - Parameter domain: The domain to clear.
    func clearPassword(for domain: String) {
        let normalizedDomain = normalizeDomain(domain)
        _ = passwords.withLock { $0.removeValue(forKey: normalizedDomain) }
    }

    /// Clears all stored passwords immediately.
    ///
    /// Call this on app backgrounding or when security-sensitive events occur.
    func clearAll() {
        passwords.withLock { $0.removeAll() }
    }

    // MARK: - Private Helpers

    private func normalizeDomain(_ domain: String) -> String {
        let normalized = domain.lowercased()
        if let registrable = PublicSuffixList.shared.registrableDomain(for: normalized) {
            return registrable
        }

        if normalized.hasPrefix("www.") {
            return String(normalized.dropFirst(4))
        }

        return normalized
    }

    /// Removes expired entries. Must be called within `passwords.withLock`.
    private nonisolated static func pruneExpired(_ passwords: inout [String: GeneratedPassword]) {
        let interval = expirationInterval
        passwords = passwords.filter { !$0.value.isExpired(interval: interval) }
    }

    /// Enforces maximum entry count by removing oldest. Must be called within `passwords.withLock`.
    private nonisolated static func enforceMaxEntries(_ passwords: inout [String: GeneratedPassword]) {
        guard passwords.count >= maxStoredPasswords else { return }

        if let oldest = passwords.min(by: { $0.value.generatedAt < $1.value.generatedAt }) {
            passwords.removeValue(forKey: oldest.key)
        }
    }
}
