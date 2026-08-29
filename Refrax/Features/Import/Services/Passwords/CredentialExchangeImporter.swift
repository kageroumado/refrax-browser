import AuthenticationServices
import Foundation

/// Maps Credential Exchange (CXF) data received from another password manager —
/// Apple Passwords, 1Password, Bitwarden — into Refrax's `ImportedCredential`
/// model.
///
/// Only password logins (`BasicAuthentication`) are mapped. Passkeys, TOTP,
/// notes, and card credentials are carried in the same payload but are ignored
/// until Refrax stores those types.
enum CredentialExchangeImporter {
    /// Flattens the account → item → credential hierarchy into the flat list of
    /// password logins Refrax knows how to store.
    static func credentials(from data: ASExportedCredentialData) -> [ImportedCredential] {
        var results: [ImportedCredential] = []

        for account in data.accounts {
            for item in account.items {
                let domain = item.scope?.urls.lazy.compactMap { $0.host() }.first

                for credential in item.credentials {
                    guard case let .basicAuthentication(basic) = credential else { continue }

                    let username = basic.userName?.value ?? account.userName
                    guard let password = basic.password?.value, !password.isEmpty else { continue }

                    // Prefer the credential's scope URL; fall back to the item's
                    // title so a login without a URL still round-trips.
                    let resolvedDomain = domain ?? item.title
                    guard !resolvedDomain.isEmpty else { continue }

                    results.append(ImportedCredential(
                        domain: resolvedDomain,
                        username: username,
                        password: password,
                        dateCreated: item.created,
                        dateLastUsed: item.lastModified,
                        notes: item.subtitle,
                    ))
                }
            }
        }

        return results
    }
}
