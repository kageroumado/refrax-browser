import Darwin
import Foundation
import OSLog
import Security

// MARK: - Control Access Mode

/// Controls how the control server handles incoming connections.
enum ControlAccessMode: String, Codable, CaseIterable, Sendable {
    /// Socket not running, no CLI access.
    case off

    /// Unknown binaries trigger an allow/deny alert.
    case prompt

    /// Any same-UID process accepted without verification.
    case open

    var displayName: String {
        switch self {
        case .off: "Off"
        case .prompt: "Ask for Permission"
        case .open: "Allow All"
        }
    }

    var description: String {
        switch self {
        case .off: "Control server is disabled. No external tools can control the browser."
        case .prompt: "Unknown apps must be approved before they can control the browser."
        case .open: "Any app running as your user can control the browser without approval."
        }
    }
}

// MARK: - Authorization Decision

/// User's response to a control server authorization prompt.
enum AuthorizationDecision: Sendable {
    case allow
    case alwaysAllow
    case deny
}

// MARK: - Client Identity

/// Identity of a process connecting to the control server.
///
/// Resolved from a PID via `proc_pidpath` for the executable path and
/// Security framework APIs for code signing information.
struct ClientIdentity: Sendable, Equatable {
    let pid: pid_t
    let path: String
    let signingIdentifier: String?
    let teamID: String?
    let displayName: String
}

// MARK: - Allowed Client

/// A client that has been granted persistent access to the control server.
struct AllowedClient: Codable, Sendable, Equatable {
    let path: String
    let signingIdentifier: String?
    let displayName: String

    /// Whether this allowed client matches the given identity.
    ///
    /// Prefers signing identifier match (stable across updates).
    /// Falls back to path match for unsigned binaries.
    func matches(_ identity: ClientIdentity) -> Bool {
        if let sigId = signingIdentifier, let identitySigId = identity.signingIdentifier {
            return sigId == identitySigId
        }
        return path == identity.path
    }
}

// MARK: - Client Identity Resolution

/// Resolves process identity from a PID.
///
/// Thread-safe: uses only POSIX and CoreFoundation APIs.
nonisolated enum ClientIdentityResolver {
    static func resolve(pid: pid_t) -> ClientIdentity {
        let path = resolvePath(pid: pid)
        let signing = resolveSigningInfo(pid: pid)
        return ClientIdentity(
            pid: pid,
            path: path,
            signingIdentifier: signing.identifier,
            teamID: signing.teamID,
            displayName: (path as NSString).lastPathComponent,
        )
    }

    private static func resolvePath(pid: pid_t) -> String {
        let bufferSize = 4_096
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        let length = proc_pidpath(pid, buffer, UInt32(bufferSize))
        guard length > 0 else { return "<unknown>" }
        return String(cString: buffer)
    }

    private static func resolveSigningInfo(pid: pid_t) -> (identifier: String?, teamID: String?) {
        let attrs = [kSecGuestAttributePid: pid] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attrs, SecCSFlags(), &code) == errSecSuccess,
              let code
        else { return (nil, nil) }

        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let staticCode
        else { return (nil, nil) }

        var info: CFDictionary?
        let signingFlags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, signingFlags, &info) == errSecSuccess,
              let dict = info as? [String: Any]
        else { return (nil, nil) }

        let identifier = dict[kSecCodeInfoIdentifier as String] as? String
        let teamID = dict[kSecCodeInfoTeamIdentifier as String] as? String
        return (identifier, teamID)
    }
}

// MARK: - Control Access Manager

/// Manages authorization for control server connections.
///
/// Maintains a list of allowed clients and handles the authorization flow
/// for incoming connections. In prompt mode, unknown clients trigger a
/// user-facing alert.
@Observable
final class ControlAccessManager {
    private static let logger = OSLog(subsystem: "website.refrax.browser", category: "control-access")

    private(set) var allowedClients: [AllowedClient] = []
    private unowned let settings: BrowserSettings

    /// Callback invoked when an unknown client needs authorization in prompt mode.
    @ObservationIgnored
    var onAuthorizationPrompt: (@MainActor @Sendable (ClientIdentity) async -> AuthorizationDecision)?

    init(settings: BrowserSettings) {
        self.settings = settings
        loadFromSettings()
    }

    /// Authorizes a client identity based on the current access mode.
    func authorize(_ identity: ClientIdentity) async -> Bool {
        let mode = settings.controlAccessMode

        switch mode {
        case .off:
            return false
        case .open:
            return true
        case .prompt:
            if isAllowed(identity) {
                os_log(
                    "Authorized known client: %{public}@",
                    log: Self.logger, type: .info, identity.displayName,
                )
                return true
            }
            guard let handler = onAuthorizationPrompt else {
                os_log(
                    "No authorization prompt handler, denying: %{public}@",
                    log: Self.logger, type: .error, identity.displayName,
                )
                return false
            }
            let decision = await handler(identity)
            switch decision {
            case .allow:
                os_log("User allowed client once: %{public}@", log: Self.logger, type: .info, identity.displayName)
                return true
            case .alwaysAllow:
                addToAllowList(identity)
                os_log("User always-allowed client: %{public}@", log: Self.logger, type: .info, identity.displayName)
                return true
            case .deny:
                os_log("User denied client: %{public}@", log: Self.logger, type: .info, identity.displayName)
                return false
            }
        }
    }

    /// Checks if a client identity matches any allowed client.
    func isAllowed(_ identity: ClientIdentity) -> Bool {
        allowedClients.contains { $0.matches(identity) }
    }

    /// Adds a client identity to the persistent allow list.
    func addToAllowList(_ identity: ClientIdentity) {
        let client = AllowedClient(
            path: identity.path,
            signingIdentifier: identity.signingIdentifier,
            displayName: identity.displayName,
        )
        guard !allowedClients.contains(client) else { return }
        allowedClients.append(client)
        saveToSettings()
    }

    /// Adds a client directly to the allow list.
    func addClient(_ client: AllowedClient) {
        guard !allowedClients.contains(client) else { return }
        allowedClients.append(client)
        saveToSettings()
    }

    /// Removes a client from the allow list by index.
    func removeFromAllowList(at index: Int) {
        guard allowedClients.indices.contains(index) else { return }
        allowedClients.remove(at: index)
        saveToSettings()
    }

    /// Reloads the allow list from settings.
    func reload() {
        loadFromSettings()
    }

    /// Adds the built-in `refrax-ctl` binary to the allow list if not already present.
    func autoAllowRefraxCTL() {
        let bundlePath = Bundle.main.bundlePath
        let helpersPath = (bundlePath as NSString).appendingPathComponent("Contents/Helpers/refrax-ctl")

        let appSupport = Directories.appStorage.path
        let appSupportBinPath = (appSupport as NSString).appendingPathComponent("bin/refrax-ctl")

        let knownPaths = [
            helpersPath,
            "/usr/local/bin/refrax-ctl",
            appSupportBinPath,
            "\(NSHomeDirectory())/Developer/Refrax/refrax-ctl/.build/release/refrax-ctl",
            "\(NSHomeDirectory())/Developer/Refrax/refrax-ctl/.build/debug/refrax-ctl",
        ]

        var changed = false
        for path in knownPaths {
            guard !allowedClients.contains(where: { $0.path == path }) else { continue }
            let displayName = (path as NSString).lastPathComponent
            allowedClients.append(AllowedClient(path: path, signingIdentifier: nil, displayName: displayName))
            changed = true
        }

        if changed {
            saveToSettings()
        }
    }

    // MARK: - Persistence

    private func loadFromSettings() {
        guard let data = settings.allowedControlClientsJSON.data(using: .utf8),
              let clients = try? JSONDecoder().decode([AllowedClient].self, from: data)
        else {
            allowedClients = []
            return
        }
        allowedClients = clients
    }

    private func saveToSettings() {
        if let data = try? JSONEncoder().encode(allowedClients),
           let json = String(data: data, encoding: .utf8) {
            settings.allowedControlClientsJSON = json
        }
    }
}
