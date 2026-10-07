import Foundation
import Security

/// Writes cookie values to the login keychain as generic passwords.
///
/// Values go straight from memory into the Security framework. Shelling out to
/// `security add-generic-password -w <value>` would put the value in the process list.
///
/// New items trust `refrax-ctl` and `/usr/bin/security`, so shell consumers read them
/// with `security find-generic-password -s <service> -w` without a prompt. The access
/// list API exists only for the file-based keychain, which is why it uses the
/// deprecated `SecAccess` calls.
enum CookieKeychainWriter {
    enum WriteError: LocalizedError {
        case trustedApplication(path: String, status: OSStatus)
        case accessList(OSStatus)
        case add(service: String, status: OSStatus)
        case update(service: String, status: OSStatus)

        var errorDescription: String? {
            switch self {
            case let .trustedApplication(path, status):
                "Couldn't add \(path) to the item's access list: \(message(for: status))"
            case let .accessList(status):
                "Couldn't create the item's access list: \(message(for: status))"
            case let .add(service, status):
                "Couldn't add keychain item \(service): \(message(for: status))"
            case let .update(service, status):
                "Couldn't update keychain item \(service): \(message(for: status))"
            }
        }

        private func message(for status: OSStatus) -> String {
            (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
        }
    }

    private static let securityToolPath = "/usr/bin/security"

    /// Stores `value` under `service`/`account`, updating the item in place when it exists.
    static func store(_ value: String, service: String, account: String) throws {
        let match: [CFString: Any] = [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
        let valueData = Data(value.utf8)

        let updateStatus = SecItemUpdate(match as CFDictionary, [kSecValueData: valueData] as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw WriteError.update(service: service, status: updateStatus)
        }

        var attributes = match
        attributes[kSecAttrLabel] = service
        attributes[kSecValueData] = valueData
        attributes[kSecAttrAccess] = try makeAccess(label: service)

        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw WriteError.add(service: service, status: addStatus)
        }
    }

    /// An access list trusting this executable and `/usr/bin/security`.
    private static func makeAccess(label: String) throws -> SecAccess {
        let applications = try [nil, securityToolPath].map(trustedApplication(at:))
        var access: SecAccess?
        let status = SecAccessCreate(label as CFString, applications as CFArray, &access)
        guard status == errSecSuccess, let access else {
            throw WriteError.accessList(status)
        }
        return access
    }

    /// A trusted application for `path`, or for this executable when `path` is `nil`.
    private static func trustedApplication(at path: String?) throws -> SecTrustedApplication {
        var application: SecTrustedApplication?
        let status = SecTrustedApplicationCreateFromPath(path, &application)
        guard status == errSecSuccess, let application else {
            throw WriteError.trustedApplication(path: path ?? "refrax-ctl", status: status)
        }
        return application
    }
}
