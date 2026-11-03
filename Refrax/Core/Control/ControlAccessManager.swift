import Foundation
import OSLog

// MARK: - Control Access Mode

/// How the control server treats incoming connections.
nonisolated enum ControlAccessMode: String, Codable, CaseIterable, Sendable {
    /// The socket is closed.
    case off

    /// Each app is asked about once; apps the user always allows are remembered.
    case prompt

    /// Any validly signed app running as the user is accepted without asking.
    case open

    var displayName: String {
        switch self {
        case .off: "Off"
        case .prompt: "Ask for Permission"
        case .open: "Allow All Signed Apps"
        }
    }

    var description: String {
        switch self {
        case .off:
            "The control server is off. No app can control Refrax."
        case .prompt:
            "Refrax asks once per app before it can control the browser, naming the app that runs refrax-ctl. Apps you always allow are listed here."
        case .open:
            "Any app running as you can control Refrax without asking, as long as its code carries a valid signature from Apple or an identified developer. Unsigned and ad hoc signed code is refused."
        }
    }
}

// MARK: - Authorization Decision

/// The user's answer to a control access prompt.
nonisolated enum AuthorizationDecision: Sendable {
    /// Allows the host until it or Refrax quits.
    case allowOnce
    case alwaysAllow
    case deny
}

// MARK: - Prompt Gate

/// Decides, per host, whether a connection is answered from memory, joins a prompt already
/// on screen, or needs a new prompt.
nonisolated struct ControlPromptGate: Sendable {
    enum Admission: Equatable, Sendable {
        case allowed
        case denied
        case joinPending
        case prompt
    }

    /// How long a denied host is refused without asking again.
    static let denialCooldown: Duration = .seconds(60)

    private var deniedUntil: [String: ContinuousClock.Instant] = [:]
    /// Processes allowed once, by host key.
    private var allowedSessions: [String: Set<pid_t>] = [:]
    private var pending: Set<String> = []

    /// Admits a connection from the host `key`, running as process `pid`.
    ///
    /// A `.prompt` result marks the host pending until ``record(_:key:pid:now:)``.
    mutating func admit(key: String, pid: pid_t, now: ContinuousClock.Instant) -> Admission {
        if allowedSessions[key]?.contains(pid) == true {
            return .allowed
        }
        if let until = deniedUntil[key] {
            if now < until {
                return .denied
            }
            deniedUntil[key] = nil
        }
        if pending.contains(key) {
            return .joinPending
        }
        pending.insert(key)
        return .prompt
    }

    /// Records the answer to the prompt for `key`.
    ///
    /// Always Allow leaves no session behind: the allow list alone admits that host, so
    /// removing it from the list takes effect on its next connection.
    mutating func record(_ decision: AuthorizationDecision, key: String, pid: pid_t, now: ContinuousClock.Instant) {
        pending.remove(key)
        switch decision {
        case .allowOnce:
            allowedSessions[key, default: []].insert(pid)
        case .alwaysAllow:
            break
        case .deny:
            deniedUntil[key] = now + Self.denialCooldown
        }
    }

    /// Forgets every process of the host `key` that was allowed once.
    mutating func revoke(key: String) {
        allowedSessions[key] = nil
    }

    /// Forgets every host allowed once and every recent denial, as when the mode changes.
    mutating func reset() {
        self = ControlPromptGate()
    }
}

// MARK: - Control Access Manager

/// Decides which clients may use the control server, and owns the access mode and the
/// list of always-allowed apps.
@Observable
final class ControlAccessManager {
    private static let logger = OSLog(subsystem: "website.refrax.browser", category: "control-access")

    private(set) var mode: ControlAccessMode
    private(set) var allowedClients: [AllowedClient]

    /// Asks the user about a client. Unset, every prompt-mode client is denied.
    @ObservationIgnored
    var onAuthorizationPrompt: (@MainActor @Sendable (ClientIdentity) async -> AuthorizationDecision)?

    @ObservationIgnored private let store: any ControlAccessStore
    @ObservationIgnored private let clock: @Sendable () -> ContinuousClock.Instant
    @ObservationIgnored private var gate = ControlPromptGate()
    @ObservationIgnored private var pendingPrompts: [String: Task<AuthorizationDecision, Never>] = [:]

    init(
        store: any ControlAccessStore = KeychainControlAccessStore(),
        clock: @escaping @Sendable () -> ContinuousClock.Instant = { .now },
    ) {
        self.store = store
        self.clock = clock
        let state = store.load() ?? ControlAccessState()
        self.mode = state.mode
        self.allowedClients = state.clients
    }

    // MARK: Authorization

    /// Authorizes a client under the current mode.
    func authorize(_ identity: ClientIdentity) async -> Bool {
        switch mode {
        case .off:
            return false
        case .open:
            guard identity.host.requirement != nil else {
                os_log("Open mode refused unsigned client %{public}@", log: Self.logger, type: .info, identity.host.path)
                return false
            }
            return true
        case .prompt:
            return await authorizeByPrompt(identity)
        }
    }

    private func authorizeByPrompt(_ identity: ClientIdentity) async -> Bool {
        if isAllowed(identity) {
            return true
        }

        let key = identity.hostKey
        switch gate.admit(key: key, pid: identity.host.pid, now: clock()) {
        case .allowed:
            return true
        case .denied:
            return false
        case .joinPending:
            guard let pending = pendingPrompts[key] else { return false }
            return await pending.value != .deny
        case .prompt:
            break
        }

        guard let handler = onAuthorizationPrompt else {
            gate.record(.deny, key: key, pid: identity.host.pid, now: clock())
            return false
        }

        let prompt = Task { @MainActor in await handler(identity) }
        pendingPrompts[key] = prompt
        var decision = await prompt.value
        pendingPrompts[key] = nil

        if decision == .alwaysAllow, let client = AllowedClient(host: identity.host) {
            add(client)
        } else if decision == .alwaysAllow {
            decision = .allowOnce
        }
        gate.record(decision, key: key, pid: identity.host.pid, now: clock())

        os_log(
            "Control access %{public}@ for %{public}@ (%{public}@)",
            log: Self.logger, type: .info, "\(decision)", identity.displayName, identity.host.path,
        )
        return decision != .deny
    }

    /// Whether the client's host is on the always-allow list.
    func isAllowed(_ identity: ClientIdentity) -> Bool {
        guard let requirement = identity.host.requirement else { return false }
        return allowedClients.contains { $0.requirement == requirement }
    }

    // MARK: Settings

    /// Changes the mode. Every change, Off included, forgets the hosts allowed once.
    func setMode(_ newMode: ControlAccessMode) {
        guard newMode != mode else { return }
        mode = newMode
        gate.reset()
        save()
    }

    /// Adds the signed app or tool at `url` to the always-allow list.
    ///
    /// - Returns: `false` when the code at `url` carries no valid signature from Apple or an
    ///   identified developer.
    @discardableResult
    func addClient(at url: URL) -> Bool {
        guard let (signing, requirement) = SecurityProcessInspector.signing(ofFileAt: url),
              let identifier = signing.identifier
        else { return false }

        let bundlePath = url.pathExtension == "app" ? url.path : nil
        let host = ControlHost(
            kind: bundlePath != nil ? .app : .process,
            pid: 0,
            path: url.path,
            displayName: url.deletingPathExtension().lastPathComponent,
            identifier: identifier,
            teamID: signing.teamID,
            signerName: signing.signerName,
            isApple: signing.isApple,
            requirement: requirement,
        )
        guard let client = AllowedClient(host: host) else { return false }
        add(client)
        return true
    }

    /// Removes an app from the always-allow list, along with any Allow Once it holds, so its
    /// next connection is asked about again.
    func removeClient(_ client: AllowedClient) {
        allowedClients.removeAll { $0 == client }
        gate.revoke(key: client.requirement)
        save()
    }

    private func add(_ client: AllowedClient) {
        guard !allowedClients.contains(where: { $0.requirement == client.requirement }) else { return }
        allowedClients.append(client)
        save()
    }

    private func save() {
        store.save(ControlAccessState(mode: mode, clients: allowedClients))
    }
}
