import AuthenticationServices
import Foundation

/// Builds a Credential Exchange (CXF) payload from Refrax's stored credentials
/// so the system can hand them to another password manager — Apple Passwords,
/// 1Password, Bitwarden — that the user picks in the export sheet.
///
/// The inverse of ``CredentialExchangeImporter``. Only password logins are
/// exported; Refrax does not yet store passkeys, TOTP, or cards.
enum CredentialExchangeExporter {
    static let relyingPartyIdentifier = "website.refrax.browser"
    static let displayName = "Refrax"

    /// Packages `credentials` into a single account whose items each carry one
    /// basic-authentication login, in the format version the destination asked
    /// for via `ASCredentialExportManager.requestExport()`.
    static func exportData(
        from credentials: [PasswordsManager.StoredCredential],
        formatVersion: ASExportedCredentialData.FormatVersion,
        timestamp: Date = Date(),
    ) -> ASExportedCredentialData {
        let items = credentials.map(item(for:))

        let account = ASImportableAccount(
            id: Data(displayName.utf8),
            userName: "",
            email: "",
            collections: [],
            items: items,
        )

        return ASExportedCredentialData(
            accounts: [account],
            formatVersion: formatVersion,
            exporterRelyingPartyIdentifier: relyingPartyIdentifier,
            exporterDisplayName: displayName,
            timestamp: timestamp,
        )
    }

    private static func item(for credential: PasswordsManager.StoredCredential) -> ASImportableItem {
        let basic = ASImportableCredential.BasicAuthentication(
            userName: ASImportableEditableField(id: nil, fieldType: .string, value: credential.username),
            password: ASImportableEditableField(id: nil, fieldType: .concealedString, value: credential.password),
        )

        let id = Data(credential.id.uuidString.utf8)
        let scope = scope(for: credential.domain)

        // The 26.1 SDK exposes a dated initializer only for non-optional dates.
        // Carry the timestamps when the store has both; otherwise omit them.
        if let created = credential.dateCreated, let modified = credential.dateModified {
            return ASImportableItem(
                id: id,
                created: created,
                lastModified: modified,
                title: credential.domain,
                scope: scope,
                credentials: [.basicAuthentication(basic)],
            )
        }

        return ASImportableItem(
            id: id,
            title: credential.domain,
            scope: scope,
            credentials: [.basicAuthentication(basic)],
        )
    }

    private static func scope(for domain: String) -> ASImportableCredentialScope? {
        let trimmed = domain.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let string = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: string), url.host() != nil else { return nil }

        return ASImportableCredentialScope(urls: [url])
    }
}
