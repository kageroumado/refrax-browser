import Foundation
import Security

/// Central manager for credential storage and retrieval.
///
/// `PasswordsManager` provides a unified interface for all password-related operations,
/// including storage in the macOS Keychain, credential lookup for auto-fill, and
/// import/export functionality.
///
/// ## Overview
///
/// This manager centralizes all Keychain interactions and provides:
/// - Credential lookup with subdomain matching for auto-fill
/// - Secure storage of new credentials
/// - Conflict detection and resolution during import
/// - Credential update and deletion
///
/// ## Keychain Storage
///
/// All credentials are stored in the macOS Keychain using `kSecClassInternetPassword`.
/// This provides:
/// - System-level encryption
/// - iCloud Keychain sync (if enabled by user)
/// - Touch ID / password protection
///
/// ## Usage
///
/// ```swift
/// // Lookup credentials for auto-fill
/// let credentials = passwordsManager.findCredentials(for: url)
///
/// // Save a new credential
/// try passwordsManager.saveCredential(credential)
///
/// // Import with conflict detection
/// if let conflict = passwordsManager.checkForConflict(imported) {
///     // Handle conflict
/// } else {
///     try passwordsManager.importCredential(imported)
/// }
/// ```
///
@Observable
final class PasswordsManager {
    // MARK: - Types

    /// A credential stored in or retrieved from the Keychain.
    struct StoredCredential: Identifiable, Sendable, Equatable, Hashable {
        let id: UUID
        let domain: String
        let username: String
        let password: String
        let dateCreated: Date?
        let dateModified: Date?

        nonisolated init(
            id: UUID = UUID(),
            domain: String,
            username: String,
            password: String,
            dateCreated: Date? = nil,
            dateModified: Date? = nil,
        ) {
            self.id = id
            self.domain = domain
            self.username = username
            self.password = password
            self.dateCreated = dateCreated
            self.dateModified = dateModified
        }
    }

    /// A conflict between an existing credential and one being imported.
    struct CredentialConflict: Identifiable, Sendable {
        let id: UUID
        let domain: String
        let username: String
        let existing: StoredCredential
        let incoming: ImportedCredential
        var resolution: ConflictResolution?

        init(existing: StoredCredential, incoming: ImportedCredential) {
            self.id = UUID()
            self.domain = existing.domain
            self.username = existing.username
            self.existing = existing
            self.incoming = incoming
            self.resolution = nil
        }
    }

    /// How to resolve a credential conflict during import.
    enum ConflictResolution: Sendable {
        case keepExisting
        case useImported
        case keepBoth
    }

    /// Errors that can occur during password operations.
    enum PasswordError: Error, LocalizedError, Sendable {
        case keychainError(OSStatus)
        case credentialNotFound
        case duplicateCredential
        case invalidData
        case accessDenied

        var errorDescription: String? {
            switch self {
            case let .keychainError(status):
                "Keychain error: \(status)"
            case .credentialNotFound:
                "Credential not found"
            case .duplicateCredential:
                "A credential with this username already exists for this domain"
            case .invalidData:
                "Invalid credential data"
            case .accessDenied:
                "Access to Keychain was denied"
            }
        }
    }

    // MARK: - Properties

    /// The service name used for Keychain entries created by Refrax.
    /// Debug and release builds use different labels so their keychain items
    /// are fully separate — prevents cross-build access prompts.
    #if DEBUG
    private let serviceName = "Refrax Browser (Debug)"
    #else
    private let serviceName = "Refrax Browser"
    #endif

    // MARK: - Credential Lookup

    /// Finds all credentials for a given URL with registrable domain matching.
    ///
    /// This method supports auto-fill by finding credentials that match the URL's host
    /// or its registrable domain (eTLD+1). For example, credentials for `example.com`
    /// will match `login.example.com`.
    ///
    /// - Parameter url: The URL to find credentials for.
    /// - Returns: Array of matching credentials, with exact matches first.
    ///
    /// - Note: Only HTTPS URLs are supported for security reasons.
    func findCredentials(for url: URL) -> [StoredCredential] {
        guard let host = url.host?.lowercased(), url.scheme == "https" else {
            Logger.debug("findCredentials: skipping non-HTTPS URL or missing host", category: Logger.autoFill)
            return []
        }

        var allCredentials: [StoredCredential] = []

        var domainsToCheck = [host]
        if let registrable = url.registrableDomain?.lowercased(),
           registrable != host {
            domainsToCheck.append(registrable)
        }

        Logger.debug("findCredentials: checking domains \(domainsToCheck) for URL \(url)", category: Logger.autoFill)

        for domain in domainsToCheck {
            if let matches = try? findInternetPasswords(for: domain) {
                let newMatches = matches.filter { credential in
                    !allCredentials.contains {
                        $0.username == credential.username && $0.domain == credential.domain
                    }
                }
                allCredentials.append(contentsOf: newMatches)
            }
        }

        Logger.debug("findCredentials: found \(allCredentials.count) credential(s)", category: Logger.autoFill)
        return allCredentials
    }

    /// Finds a specific credential by domain and username.
    ///
    /// - Parameters:
    ///   - domain: The domain to search.
    ///   - username: The username to match.
    /// - Returns: The matching credential, or `nil` if not found.
    func findCredential(domain: String, username: String) -> StoredCredential? {
        guard let credentials = try? findInternetPasswords(for: domain) else {
            return nil
        }
        return credentials.first { $0.username == username }
    }

    // MARK: - Credential Storage

    /// Saves a new credential to the Keychain.
    ///
    /// - Parameter credential: The credential to save.
    /// - Throws: `PasswordError` if the save fails or a duplicate exists.
    func saveCredential(_ credential: StoredCredential) throws {
        guard let passwordData = credential.password.data(using: .utf8) else {
            throw PasswordError.invalidData
        }

        // Note: kSecAttrCreationDate and kSecAttrModificationDate are read-only
        // attributes that the Keychain sets automatically. Attempting to set them
        // in SecItemAdd causes errSecParam (-50).
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: credential.domain,
            kSecAttrAccount as String: credential.username,
            kSecValueData as String: passwordData,
            kSecAttrLabel as String: serviceName,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        switch status {
        case errSecSuccess:
            Logger.info("Saved credential for '\(credential.username)' on domain '\(credential.domain)'", category: Logger.autoFill)
        case errSecDuplicateItem:
            Logger.warning("Duplicate credential for '\(credential.username)' on domain '\(credential.domain)'", category: Logger.autoFill)
            throw PasswordError.duplicateCredential
        default:
            Logger.error("Failed to save credential for domain '\(credential.domain)': status \(status)", category: Logger.autoFill)
            throw PasswordError.keychainError(status)
        }
    }

    /// Updates an existing credential in the Keychain.
    ///
    /// - Parameter credential: The credential with updated values.
    /// - Throws: `PasswordError` if the update fails.
    func updateCredential(_ credential: StoredCredential) throws {
        guard let passwordData = credential.password.data(using: .utf8) else {
            throw PasswordError.invalidData
        }

        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: credential.domain,
            kSecAttrAccount as String: credential.username,
        ]

        // Note: kSecAttrModificationDate is read-only and set automatically by the Keychain.
        // Attempting to set it causes errSecParam (-50).
        let attributes: [String: Any] = [
            kSecValueData as String: passwordData,
        ]

        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)

        switch status {
        case errSecSuccess:
            Logger.info("Updated credential for \(credential.domain)", category: Logger.autoFill)
        case errSecItemNotFound:
            throw PasswordError.credentialNotFound
        default:
            throw PasswordError.keychainError(status)
        }
    }

    /// Deletes a credential from the Keychain.
    ///
    /// - Parameter credential: The credential to delete.
    /// - Throws: `PasswordError` if the deletion fails.
    func deleteCredential(_ credential: StoredCredential) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: credential.domain,
            kSecAttrAccount as String: credential.username,
        ]

        let status = SecItemDelete(query as CFDictionary)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            Logger.info("Deleted credential for \(credential.domain)", category: Logger.autoFill)
        default:
            throw PasswordError.keychainError(status)
        }
    }

    // MARK: - Import Support

    /// Checks if importing a credential would create a conflict.
    ///
    /// A conflict exists when a credential with the same domain and username
    /// already exists in the Keychain.
    ///
    /// - Parameter credential: The credential to check.
    /// - Returns: A `CredentialConflict` if one exists, otherwise `nil`.
    func checkForConflict(_ credential: ImportedCredential) -> CredentialConflict? {
        guard let existing = findCredential(domain: credential.domain, username: credential.username) else {
            return nil
        }

        if existing.password == credential.password {
            return nil
        }

        return CredentialConflict(existing: existing, incoming: credential)
    }

    /// Imports a credential with the specified conflict resolution.
    ///
    /// - Parameters:
    ///   - credential: The credential to import.
    ///   - resolution: How to handle conflicts. Defaults to `.useImported`.
    /// - Throws: `PasswordError` if the import fails.
    func importCredential(
        _ credential: ImportedCredential,
        conflictResolution resolution: ConflictResolution = .useImported,
    ) throws {
        let stored = StoredCredential(
            domain: credential.domain,
            username: credential.username,
            password: credential.password,
            dateCreated: credential.dateCreated,
            dateModified: credential.dateLastUsed,
        )

        if findCredential(domain: credential.domain, username: credential.username) != nil {
            switch resolution {
            case .keepExisting:
                return
            case .useImported:
                try updateCredential(stored)
            case .keepBoth:
                let modifiedCredential = StoredCredential(
                    domain: credential.domain,
                    username: "\(credential.username) (imported)",
                    password: credential.password,
                    dateCreated: credential.dateCreated,
                    dateModified: credential.dateLastUsed,
                )
                try saveCredential(modifiedCredential)
            }
        } else {
            try saveCredential(stored)
        }
    }

    // MARK: - All Credentials

    /// Returns all credentials stored by Refrax.
    ///
    /// This method retrieves all credentials with the Refrax service label.
    /// Used by the Password Manager window to display all stored passwords.
    ///
    /// Apple's Security framework prohibits combining `kSecReturnData` with `kSecMatchLimitAll`
    /// for password items. This method works around this by querying for references first,
    /// then getting data for each item individually.
    ///
    /// - Returns: Array of all stored credentials.
    /// - Throws: `PasswordError` if retrieval fails.
    nonisolated func allCredentials() throws -> [StoredCredential] {
        let metadata = try allCredentialMetadata()

        // For each item, query individually to get the password data
        return metadata.compactMap { credential in
            guard let password = try? fetchPassword(for: credential) else { return nil }
            return StoredCredential(
                domain: credential.domain,
                username: credential.username,
                password: password,
                dateCreated: credential.dateCreated,
                dateModified: credential.dateModified,
            )
        }
    }

    /// Fetches metadata for all credentials without decrypting passwords.
    ///
    /// This is fast (single keychain query) and suitable for populating lists
    /// where passwords aren't needed for display.
    nonisolated func allCredentialMetadata() throws -> [StoredCredential] {
        let refsQuery: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: serviceName,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnPersistentRef as String: true,
            kSecReturnAttributes as String: true,
        ]

        var refsItem: CFTypeRef?
        let refsStatus = SecItemCopyMatching(refsQuery as CFDictionary, &refsItem)

        guard refsStatus != errSecItemNotFound else {
            return []
        }

        guard refsStatus == errSecSuccess else {
            throw PasswordError.keychainError(refsStatus)
        }

        guard let foundItems = refsItem as? [[String: Any]] else {
            throw PasswordError.invalidData
        }

        var credentials: [StoredCredential] = []
        for itemDict in foundItems {
            guard let server = itemDict[kSecAttrServer as String] as? String,
                  let username = itemDict[kSecAttrAccount as String] as? String
            else {
                continue
            }

            let dateCreated = itemDict[kSecAttrCreationDate as String] as? Date
            let dateModified = itemDict[kSecAttrModificationDate as String] as? Date

            credentials.append(StoredCredential(
                domain: server,
                username: username,
                password: "",
                dateCreated: dateCreated,
                dateModified: dateModified,
            ))
        }

        return credentials.sorted { $0.domain.localizedCaseInsensitiveCompare($1.domain) == .orderedAscending }
    }

    /// Fetches the password for a single credential from the keychain.
    ///
    /// Used for on-demand password retrieval (copy, detail view, export)
    /// to avoid the cost of decrypting all passwords upfront.
    nonisolated func fetchPassword(for credential: StoredCredential) throws -> String {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: credential.domain,
            kSecAttrAccount as String: credential.username,
            kSecAttrLabel as String: serviceName,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        guard status == errSecSuccess,
              let passwordData = item as? Data,
              let password = String(data: passwordData, encoding: .utf8)
        else {
            throw PasswordError.keychainError(status)
        }

        return password
    }

    /// Deletes all credentials stored by Refrax.
    ///
    /// - Warning: This is a destructive operation that cannot be undone.
    /// - Throws: `PasswordError` if deletion fails.
    func deleteAllCredentials() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrLabel as String: serviceName,
        ]

        let status = SecItemDelete(query as CFDictionary)

        switch status {
        case errSecSuccess, errSecItemNotFound:
            Logger.info("Deleted all stored credentials", category: Logger.autoFill)
        default:
            throw PasswordError.keychainError(status)
        }
    }

    // MARK: - Browser Keychain Access (Stubs)

    /// Requests access to another browser's Keychain entries.
    ///
    /// - Parameter browser: The browser to request access for.
    /// - Returns: `true` if access was granted.
    ///
    /// - Note: This is a stub for future implementation. Direct Keychain access
    ///   to other browsers' credentials requires special entitlements and user authorization.
    func requestKeychainAccess(for browser: ThirdPartyBrowser) async throws -> Bool {
        Logger.warning(
            "Direct Keychain access for \(browser.displayName) not yet implemented",
            category: Logger.autoFill,
        )
        throw PasswordError.accessDenied
    }
}

// MARK: - Private Helpers

private extension PasswordsManager {
    /// Finds all internet passwords for a given domain.
    ///
    /// Apple's Security framework prohibits combining `kSecReturnData` with `kSecMatchLimitAll`
    /// for password items because retrieving each password may require additional authentication.
    /// This method works around this by:
    /// 1. Querying for persistent references (not data) with `kSecMatchLimitAll`
    /// 2. For each matching reference, querying individually with `kSecReturnData`
    func findInternetPasswords(for domain: String) throws -> [StoredCredential] {
        // Step 1: Query for persistent references only (kSecReturnData + kSecMatchLimitAll is prohibited)
        let refsQuery: [String: Any] = [
            kSecClass as String: kSecClassInternetPassword,
            kSecAttrServer as String: domain,
            kSecAttrLabel as String: serviceName,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnPersistentRef as String: true,
            kSecReturnAttributes as String: true,
        ]

        var refsItem: CFTypeRef?
        let refsStatus = SecItemCopyMatching(refsQuery as CFDictionary, &refsItem)

        guard refsStatus != errSecItemNotFound else {
            Logger.debug("No credentials for domain '\(domain)'", category: Logger.autoFill)
            return []
        }

        guard refsStatus == errSecSuccess else {
            Logger.error("Keychain refs query failed: \(refsStatus)", category: Logger.autoFill)
            throw PasswordError.keychainError(refsStatus)
        }

        guard let foundItems = refsItem as? [[String: Any]] else {
            throw PasswordError.invalidData
        }

        // Step 2: For each item, query individually to get the password data
        var credentials: [StoredCredential] = []
        for itemDict in foundItems {
            guard let persistentRef = itemDict[kSecValuePersistentRef as String] as? Data,
                  let username = itemDict[kSecAttrAccount as String] as? String
            else {
                continue
            }

            // Query for this specific item's data using the persistent reference
            let dataQuery: [String: Any] = [
                kSecClass as String: kSecClassInternetPassword,
                kSecMatchItemList as String: [persistentRef],

                kSecMatchLimit as String: kSecMatchLimitOne,
                kSecReturnData as String: true,
            ]

            var dataItem: CFTypeRef?
            let dataStatus = SecItemCopyMatching(dataQuery as CFDictionary, &dataItem)

            guard dataStatus == errSecSuccess,
                  let passwordData = dataItem as? Data,
                  let password = String(data: passwordData, encoding: .utf8)
            else {
                continue
            }

            let dateCreated = itemDict[kSecAttrCreationDate as String] as? Date
            let dateModified = itemDict[kSecAttrModificationDate as String] as? Date

            credentials.append(StoredCredential(
                domain: domain,
                username: username,
                password: password,
                dateCreated: dateCreated,
                dateModified: dateModified,
            ))
        }

        Logger.debug("Found \(credentials.count) credential(s) for domain '\(domain)'", category: Logger.autoFill)
        return credentials
    }
}
