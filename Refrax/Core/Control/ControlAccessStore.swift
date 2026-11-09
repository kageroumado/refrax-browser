import Foundation
import OSLog
import Security

// MARK: - State

/// The control server's access mode and its remembered clients.
nonisolated struct ControlAccessState: Codable, Equatable, Sendable {
    var mode: ControlAccessMode = .prompt
    var clients: [AllowedClient] = []
}

/// A host the user chose to always allow, remembered by its code requirement.
nonisolated struct AllowedClient: Codable, Equatable, Sendable, Identifiable {
    /// Requirement text the host's running code must satisfy.
    let requirement: String
    let kind: ControlHost.Kind
    let displayName: String
    let identifier: String
    let teamID: String?
    let signerName: String?
    let isApple: Bool

    var id: String {
        requirement
    }

    /// The requirement names one build by its hash, because the code is ad hoc signed.
    var isPinnedToBuild: Bool {
        ClientIdentity.isBuildRequirement(requirement)
    }

    init?(host: ControlHost) {
        guard let requirement = host.requirement else { return nil }
        self.requirement = requirement
        self.kind = host.kind
        self.displayName = host.displayName
        self.identifier = host.identifier ?? host.displayName
        self.teamID = host.teamID
        self.signerName = host.signerName
        self.isApple = host.isApple
    }
}

// MARK: - Store

/// Where ``ControlAccessState`` persists.
nonisolated protocol ControlAccessStore: Sendable {
    /// The stored state, or `nil` when none is stored or it cannot be read.
    func load() -> ControlAccessState?
    func save(_ state: ControlAccessState)
}

/// Keeps ``ControlAccessState`` in the data protection keychain, in Refrax's default access
/// group (the one it shares with its credential provider extension).
///
/// Other processes running as the user can read and rewrite the SwiftData store, and the
/// store syncs to every Mac on the account; a data protection keychain item can be read and
/// written only by code signed into its access group, and this one never leaves this Mac.
nonisolated struct KeychainControlAccessStore: ControlAccessStore {
    private static let account = "state"
    private static let log = OSLog(subsystem: "website.refrax.browser", category: "control-access")

    /// One item per app identity, so the debug build keeps its own.
    private let service: String

    init(bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "website.refrax.browser") {
        self.service = "\(bundleIdentifier).control-access"
    }

    /// The mode stored for the running app, read straight from the keychain.
    static func storedMode() -> ControlAccessMode {
        KeychainControlAccessStore().load()?.mode ?? ControlAccessState().mode
    }

    func load() -> ControlAccessState? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound {
                os_log("Couldn't read control access state (status %d)", log: Self.log, type: .error, status)
            }
            return nil
        }
        return try? JSONDecoder().decode(ControlAccessState.self, from: data)
    }

    func save(_ state: ControlAccessState) {
        guard let data = try? JSONEncoder().encode(state) else { return }

        let updateStatus = SecItemUpdate(baseQuery as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }

        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(attributes as CFDictionary, nil)
        if addStatus != errSecSuccess {
            os_log(
                "Couldn't save control access state (update %d, add %d)",
                log: Self.log, type: .error, updateStatus, addStatus,
            )
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false,
            kSecAttrService as String: service,
            kSecAttrAccount as String: Self.account,
        ]
    }
}
