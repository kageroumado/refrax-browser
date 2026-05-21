import Foundation

/// Represents a credential stored in the Keychain
struct KeychainCredential: Identifiable, Equatable {
    let id = UUID()
    let username: String
    let password: String
    let domain: String

    static func == (lhs: KeychainCredential, rhs: KeychainCredential) -> Bool {
        lhs.username == rhs.username && lhs.password == rhs.password && lhs.domain == rhs.domain
    }

    init?(username: String, passwordData: Data, domain: String) {
        guard let password = String(data: passwordData, encoding: .utf8) else {
            return nil
        }
        self.username = username
        self.password = password
        self.domain = domain
    }
}
