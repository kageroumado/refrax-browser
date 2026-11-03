import Darwin
import Foundation
import RefraxProtocol
import Security
import Testing
@testable import Refrax

// MARK: - Fakes

/// A process tree with chosen signing facts. Requirements are matched against the facts the
/// way ``ClientIdentity/requirementText(for:)`` builds them.
private struct FakeProcessInspector: ProcessInspector {
    var signings: [pid_t: ProcessSigning] = [:]
    var parents: [pid_t: pid_t] = [:]
    var responsible: [pid_t: pid_t] = [:]
    /// PIDs whose signature fails validation against any requirement.
    var invalid: Set<pid_t> = []

    func signing(of process: ProcessReference) -> ProcessSigning? {
        signings[process.pid]
    }

    func process(_ process: ProcessReference, satisfies requirement: String) -> Bool {
        guard !invalid.contains(process.pid), let signing = signings[process.pid] else { return false }
        return ClientIdentity.requirementText(for: signing) == requirement
    }

    func parentPID(of pid: pid_t) -> pid_t? {
        parents[pid]
    }

    func responsiblePID(for pid: pid_t) -> pid_t? {
        responsible[pid]
    }
}

private extension ProcessSigning {
    static func team(_ path: String, _ identifier: String, team: String = "TEAM123456") -> ProcessSigning {
        ProcessSigning(
            executablePath: path,
            identifier: identifier,
            teamID: team,
            signerName: "Developer ID Application: Someone (\(team))",
            isApple: false,
        )
    }

    static func apple(_ path: String, _ identifier: String) -> ProcessSigning {
        ProcessSigning(executablePath: path, identifier: identifier, teamID: nil, signerName: "Software Signing", isApple: true)
    }

    static func unsigned(_ path: String) -> ProcessSigning {
        ProcessSigning(executablePath: path, identifier: nil, teamID: nil, signerName: nil, isApple: false)
    }

    static let refraxCTL = ProcessSigning.team(
        "/usr/local/bin/refrax-ctl",
        RefraxCodeSigning.cliIdentifier,
        team: refraxTeam,
    )
}

/// The team the tests' Refrax is signed by.
private let refraxTeam = "REFRAXTEAM"

private func derive(
    _ pid: pid_t,
    _ inspector: FakeProcessInspector,
    ownTeamID: String? = refraxTeam,
) throws(ClientIdentity.Refusal) -> ClientIdentity {
    try ClientIdentity.derive(peer: .pid(pid), ownTeamID: ownTeamID, inspector: inspector)
}

/// Holds control access state in memory.
private final class InMemoryControlAccessStore: ControlAccessStore, @unchecked Sendable {
    private let lock = NSLock()
    private var state: ControlAccessState?

    init(_ state: ControlAccessState? = nil) {
        self.state = state
    }

    func load() -> ControlAccessState? {
        lock.withLock { state }
    }

    func save(_ state: ControlAccessState) {
        lock.withLock { self.state = state }
    }
}

/// Counts prompts, and holds one open until the test answers it.
@MainActor
private final class PromptRecorder {
    var prompts = 0
    private(set) var waiting: CheckedContinuation<AuthorizationDecision, Never>?

    func hold() async -> AuthorizationDecision {
        prompts += 1
        return await withCheckedContinuation { waiting = $0 }
    }

    func answer(_ decision: AuthorizationDecision) {
        waiting?.resume(returning: decision)
        waiting = nil
    }
}

/// A clock the test advances by hand.
private final class ManualClock: @unchecked Sendable {
    private let lock = NSLock()
    private var instant = ContinuousClock.now

    var now: ContinuousClock.Instant {
        lock.withLock { instant }
    }

    func advance(by duration: Duration) {
        lock.withLock { instant += duration }
    }
}

private func identity(
    host: ProcessSigning,
    pid: pid_t = 500,
    viaCLI: Bool = true,
) -> ClientIdentity {
    let inspector = FakeProcessInspector(
        signings: [pid: host, 900: .refraxCTL],
        parents: [900: pid],
        responsible: [900: pid],
    )
    let peer: pid_t = viaCLI ? 900 : pid
    do {
        return try derive(peer, inspector)
    } catch {
        preconditionFailure("A fixture identity failed to derive: \(error)")
    }
}

// MARK: - Identity Derivation

@Suite("Control client identity")
struct ControlClientIdentityTests {
    private static let terminal = ProcessSigning.apple(
        "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal",
        "com.apple.Terminal",
    )

    @Test
    func `refrax-ctl run from an app is attributed to the responsible app`() throws {
        let inspector = FakeProcessInspector(
            signings: [100: Self.terminal, 200: .apple("/bin/zsh", "com.apple.zsh"), 300: .refraxCTL],
            parents: [300: 200, 200: 100],
            responsible: [300: 100],
        )

        let identity = try derive(300, inspector)

        #expect(identity.viaCLI)
        #expect(identity.host.kind == .app)
        #expect(identity.host.pid == 100)
        #expect(identity.host.displayName == "Terminal")
        #expect(identity.host.path == "/System/Applications/Utilities/Terminal.app")
        #expect(identity.host.requirement == #"anchor apple and identifier "com.apple.Terminal""#)
        #expect(identity.peerPath == "/usr/local/bin/refrax-ctl")
    }

    @Test
    func `Without a responsible app, the nearest app ancestor is the host`() throws {
        let editor = ProcessSigning.team("/Applications/Editor.app/Contents/MacOS/Editor", "com.example.editor")
        let inspector = FakeProcessInspector(
            signings: [100: editor, 200: .apple("/bin/zsh", "com.apple.zsh"), 300: .refraxCTL],
            parents: [300: 200, 200: 100, 100: 1],
        )

        let identity = try derive(300, inspector)

        #expect(identity.host.pid == 100)
        #expect(identity.host.kind == .app)
        #expect(identity.host.requirement == RefraxCodeSigning.teamRequirement(identifier: "com.example.editor", teamID: "TEAM123456"))
    }

    @Test
    func `With no app among the ancestors, the process that ran refrax-ctl is a background host`() throws {
        let inspector = FakeProcessInspector(
            signings: [200: .apple("/usr/sbin/cron", "com.apple.cron"), 300: .refraxCTL],
            parents: [300: 200, 200: 1],
        )

        let identity = try derive(300, inspector)

        #expect(identity.host.kind == .process)
        #expect(identity.host.pid == 200)
        #expect(identity.host.path == "/usr/sbin/cron")
        #expect(identity.host.displayName == "cron")
        #expect(identity.host.requirement == #"anchor apple and identifier "com.apple.cron""#)
    }

    @Test
    func `A peer that is not refrax-ctl is its own host`() throws {
        let tool = ProcessSigning.team("/Applications/Agent.app/Contents/MacOS/Agent", "com.example.agent")
        let inspector = FakeProcessInspector(
            signings: [100: Self.terminal, 300: tool],
            parents: [300: 100],
            responsible: [300: 100],
        )

        let identity = try derive(300, inspector)

        #expect(!identity.viaCLI)
        #expect(identity.host.pid == 300)
        #expect(identity.host.displayName == "Agent")
    }

    @Test
    func `refrax-ctl signed by another team is refused`() {
        let fake = ProcessSigning.team("/usr/local/bin/refrax-ctl", RefraxCodeSigning.cliIdentifier, team: "EVILTEAM01")
        let inspector = FakeProcessInspector(signings: [100: Self.terminal, 300: fake], parents: [300: 100])

        #expect(throws: ClientIdentity.Refusal.foreignCLI(cliPath: "/usr/local/bin/refrax-ctl", expectedTeam: refraxTeam)) {
            try derive(300, inspector)
        }
    }

    @Test
    func `An unsigned binary named refrax-ctl is refused`() {
        let inspector = FakeProcessInspector(signings: [100: Self.terminal, 300: .unsigned("/tmp/x/refrax-ctl")], parents: [300: 100])

        #expect(throws: ClientIdentity.Refusal.foreignCLI(cliPath: "/tmp/x/refrax-ctl", expectedTeam: refraxTeam)) {
            try derive(300, inspector)
        }
    }

    @Test
    func `A Refrax with no developer team refuses refrax-ctl rather than trusting it`() {
        let inspector = FakeProcessInspector(signings: [100: Self.terminal, 300: .refraxCTL], parents: [300: 100])

        #expect(throws: ClientIdentity.Refusal.appUnsigned(cliPath: "/usr/local/bin/refrax-ctl")) {
            try derive(300, inspector, ownTeamID: nil)
        }
    }

    @Test
    func `Unsigned and ad hoc code gets no requirement`() throws {
        let inspector = FakeProcessInspector(signings: [300: .unsigned("/tmp/tool")])

        let identity = try derive(300, inspector)

        #expect(identity.host.requirement == nil)
        #expect(identity.hostKey == "unverified:/tmp/tool")
    }

    @Test
    func `A host whose signature fails validation gets no requirement`() throws {
        let editor = ProcessSigning.team("/Applications/Editor.app/Contents/MacOS/Editor", "com.example.editor")
        let inspector = FakeProcessInspector(
            signings: [100: editor, 300: .refraxCTL],
            parents: [300: 100],
            responsible: [300: 100],
            invalid: [100],
        )

        let identity = try derive(300, inspector)

        #expect(identity.host.pid == 100)
        #expect(identity.host.requirement == nil)
    }

    @Test(arguments: [
        ("/Applications/A.app/Contents/MacOS/A", "/Applications/A.app"),
        ("/Applications/A.app/Contents/Frameworks/H.app/Contents/MacOS/H", "/Applications/A.app/Contents/Frameworks/H.app"),
        ("/Applications/A.app/Contents/Helpers/tool", nil),
        ("/usr/bin/python3", nil),
    ])
    func `App bundle paths are recognized only for a bundle's main executable`(executable: String, expected: String?) {
        #expect(ClientIdentity.appBundlePath(forExecutable: executable) == expected)
    }

    @Test
    func `Requirement text refuses identifiers it would have to escape`() {
        #expect(RefraxCodeSigning.teamRequirement(identifier: #"a" or anchor apple generic or "b"#, teamID: "T") == nil)
        #expect(RefraxCodeSigning.appleRequirement(identifier: "a\\b") == nil)
        #expect(RefraxCodeSigning.teamRequirement(identifier: "com.example.app", teamID: "TEAM123456") != nil)
    }

    @Test
    func `The prompt names the host, its signer, and the CLI path`() {
        let editor = ProcessSigning.team("/Applications/Editor.app/Contents/MacOS/Editor", "com.example.editor")
        let text = ControlAccessPrompt.informativeText(for: identity(host: editor))

        #expect(text.contains("Location: /Applications/Editor.app"))
        #expect(text.contains("Signed by Someone (team TEAM123456)."))
        #expect(text.contains("It runs refrax-ctl at /usr/local/bin/refrax-ctl."))
    }

    @Test
    func `The prompt calls a host outside any app a background process`() {
        let text = ControlAccessPrompt.informativeText(for: identity(host: .unsigned("/opt/jobs/sync")))

        #expect(text.contains("background process outside any app: /opt/jobs/sync"))
        #expect(text.contains("allow it only once"))
    }
}

// MARK: - Prompt Gate

@Suite("Control prompt gate")
struct ControlPromptGateTests {
    @Test
    func `The first connection prompts; a second one joins it`() {
        var gate = ControlPromptGate()
        let now = ContinuousClock.now

        #expect(gate.admit(key: "app", pid: 1, now: now) == .prompt)
        #expect(gate.admit(key: "app", pid: 1, now: now) == .joinPending)
        #expect(gate.admit(key: "other", pid: 2, now: now) == .prompt)
    }

    @Test
    func `A denied host is refused without a prompt for the cooldown, then asked again`() {
        var gate = ControlPromptGate()
        let now = ContinuousClock.now

        _ = gate.admit(key: "app", pid: 1, now: now)
        gate.record(.deny, key: "app", pid: 1, now: now)

        #expect(gate.admit(key: "app", pid: 1, now: now + .seconds(59)) == .denied)
        #expect(gate.admit(key: "app", pid: 1, now: now + ControlPromptGate.denialCooldown) == .prompt)
    }

    @Test
    func `Allow Once lasts for that process of the host only`() {
        var gate = ControlPromptGate()
        let now = ContinuousClock.now

        _ = gate.admit(key: "app", pid: 1, now: now)
        gate.record(.allowOnce, key: "app", pid: 1, now: now)

        #expect(gate.admit(key: "app", pid: 1, now: now) == .allowed)
        #expect(gate.admit(key: "app", pid: 2, now: now) == .prompt)
    }
}

// MARK: - Access Manager

@Suite("ControlAccessManager authorization", .serialized)
@MainActor
struct ControlAccessManagerTests {
    private static let editor = ProcessSigning.team("/Applications/Editor.app/Contents/MacOS/Editor", "com.example.editor")

    @Test
    func `Prompt mode asks once for concurrent connections from one host`() async {
        let manager = ControlAccessManager(store: InMemoryControlAccessStore())
        let recorder = PromptRecorder()
        manager.onAuthorizationPrompt = { _ in
            await recorder.hold()
        }
        let client = identity(host: Self.editor)

        async let first = manager.authorize(client)
        async let second = manager.authorize(client)
        while recorder.waiting == nil {
            await Task.yield()
        }
        for _ in 0 ..< 10 {
            await Task.yield()
        }
        recorder.answer(.allowOnce)

        let results = await [first, second]
        #expect(results == [true, true])
        #expect(recorder.prompts == 1)
    }

    @Test
    func `Always Allow remembers the requirement, never a path`() async {
        let store = InMemoryControlAccessStore()
        let manager = ControlAccessManager(store: store)
        manager.onAuthorizationPrompt = { _ in .alwaysAllow }
        let client = identity(host: Self.editor)

        #expect(await manager.authorize(client))

        let saved = store.load()?.clients
        #expect(saved?.count == 1)
        #expect(saved?.first?.requirement == client.host.requirement)
        let reloaded = ControlAccessManager(store: store)
        #expect(reloaded.isAllowed(client))
    }

    @Test
    func `Always Allow for an unverified host allows it once and remembers nothing`() async {
        let store = InMemoryControlAccessStore()
        let manager = ControlAccessManager(store: store)
        manager.onAuthorizationPrompt = { _ in .alwaysAllow }

        #expect(await manager.authorize(identity(host: .unsigned("/tmp/tool"))))
        #expect(store.load()?.clients.isEmpty ?? true)
    }

    @Test
    func `A Deny is not asked again for a minute`() async {
        let clock = ManualClock()
        let manager = ControlAccessManager(store: InMemoryControlAccessStore(), clock: { clock.now })
        let recorder = PromptRecorder()
        manager.onAuthorizationPrompt = { _ in
            recorder.prompts += 1
            return .deny
        }
        let client = identity(host: Self.editor)

        #expect(await !(manager.authorize(client)))
        #expect(await !(manager.authorize(client)))
        #expect(recorder.prompts == 1)

        clock.advance(by: .seconds(61))
        #expect(await !(manager.authorize(client)))
        #expect(recorder.prompts == 2)
    }

    @Test
    func `Open mode accepts signed hosts and refuses unsigned ones without asking`() async {
        let manager = ControlAccessManager(store: InMemoryControlAccessStore(ControlAccessState(mode: .open)))
        manager.onAuthorizationPrompt = { _ in
            Issue.record("Open mode prompted")
            return .allowOnce
        }

        #expect(await manager.authorize(identity(host: Self.editor)))
        #expect(await !(manager.authorize(identity(host: .unsigned("/tmp/tool")))))
    }

    @Test
    func `Off refuses everyone`() async {
        let manager = ControlAccessManager(store: InMemoryControlAccessStore(ControlAccessState(mode: .off)))
        #expect(await !(manager.authorize(identity(host: Self.editor))))
    }

    @Test
    func `Without a stored state the mode is Ask and the list is empty`() {
        let manager = ControlAccessManager(store: InMemoryControlAccessStore())
        #expect(manager.mode == .prompt)
        #expect(manager.allowedClients.isEmpty)
    }

    @Test
    func `Changing the mode persists it`() {
        let store = InMemoryControlAccessStore()
        let manager = ControlAccessManager(store: store)
        manager.setMode(.off)
        #expect(store.load()?.mode == .off)
    }
}

// MARK: - Request Policy

@Suite("Control request policy")
struct ControlRequestPolicyTests {
    @Test(arguments: [
        "https://example.com/a", "http://localhost:8080/", "about:blank", "example.com",
    ])
    func `http, https and about URLs open`(string: String) throws {
        let url = try ControlURLPolicy.navigableURL(from: string)
        #expect(["http", "https", "about"].contains(url.scheme))
    }

    @Test(arguments: [
        "file:///etc/passwd", "javascript:alert(1)", "data:text/html,hi", "refrax://settings", "ftp://example.com",
    ])
    func `Other schemes are refused`(string: String) {
        #expect(throws: ControlURLPolicy.Refusal.self) {
            try ControlURLPolicy.navigableURL(from: string)
        }
    }

    @Test(arguments: [
        ("example.com", "example.com", true),
        ("www.example.com", "example.com", true),
        ("WWW.Example.COM", "example.com", true),
        ("notexample.com", "example.com", false),
        ("example.com.evil.net", "example.com", false),
        ("a.example.com", ".example.com", true),
        ("example.com", "", false),
    ])
    func `A domain matches itself and its subdomains only`(host: String, domain: String, expected: Bool) {
        #expect(host.isHost(inDomain: domain) == expected)
    }

    @Test(arguments: [
        ("example.com", true),
        (".example.com", true),
        ("sub.example.co.uk", true),
        ("127.0.0.1", true),
        ("com", false),
        ("co.uk", false),
        ("", false),
        (".", false),
        ("localhost", false),
    ])
    func `A cookie domain filter must name a registrable domain`(filter: String, accepted: Bool) {
        let suffixes: Set = ["com", "uk", "co.uk", "net"]
        #expect(ControlCookieAccess.isSpecificDomainFilter(filter, isPublicSuffix: suffixes.contains) == accepted)
    }

    @Test
    @MainActor
    func `A program without a policy runs under the restrictive default`() {
        let policy = ProgramInterpreter.effectivePolicy(nil)
        #expect(!policy.allowJavaScript)
        #expect(policy.sensitiveFieldPolicy == .requireConfirmation)
    }

    @Test
    @MainActor
    func `A domain policy checks subdomains on label boundaries`() {
        let policy = ProgramSecurityPolicy(allowedDomains: ["example.com"])
        let allowed = ProgramSecurityAnalyzer.validate(program: "navigate \"https://www.example.com/\"", policy: policy)
        let lookalike = ProgramSecurityAnalyzer.validate(program: "navigate \"https://notexample.com/\"", policy: policy)

        #expect(allowed.isEmpty)
        #expect(lookalike.contains { $0.kind == .domainNotAllowed })
    }
}

// MARK: - Settings

@Suite("Control-settable settings")
@MainActor
struct ControlSettableSettingsTests {
    @Test(arguments: [
        BrowserSettingKey.allowSSLCertificateBypass,
        .requireAuthForAutoFill,
        .autoFillMode,
        .enableContentBlocking,
        .blockThirdPartyCookies,
        .enableFingerprintingProtection,
    ])
    func `Protections cannot be changed over the control socket`(key: BrowserSettingKey) {
        #expect(!key.isSettableOverControlSocket)
    }

    @Test
    func `The access mode is not a setting a client can reach`() {
        #expect(BrowserSettingKey(rawValue: "controlAccessMode") == nil)
        #expect(BrowserSettingKey.doNotTrack.isSettableOverControlSocket)
    }
}

// MARK: - CLI Flags

@Suite("refrax-ctl global flags")
struct CLIGlobalFlagsTests {
    @Test
    func `Flags before the subcommand are read`() {
        let flags = CLIGlobalFlags.parse(["-q", "--timeout", "5", "--retry", "2", "--retry-delay", "0.5", "tab", "list"])

        #expect(flags.quiet)
        #expect(flags.timeout == 5)
        #expect(flags.retry == 2)
        #expect(flags.retryDelay == 0.5)
        #expect(flags.remainingArguments == ["tab", "list"])
    }

    @Test
    func `Flag-shaped arguments after the subcommand are left to it`() {
        let flags = CLIGlobalFlags.parse(["type", "e1", "-v", "--timeout", "9", "--version"])

        #expect(!flags.verbose)
        #expect(flags.timeout == 30)
        #expect(!flags.printVersion)
        #expect(flags.remainingArguments == ["type", "e1", "-v", "--timeout", "9", "--version"])
    }

    @Test
    func `A flag missing its value stops parsing and is left in place`() {
        let flags = CLIGlobalFlags.parse(["--timeout"])
        #expect(flags.remainingArguments == ["--timeout"])
    }

    @Test
    func `--version before the subcommand is read`() {
        #expect(CLIGlobalFlags.parse(["--version"]).printVersion)
    }
}

// MARK: - Keychain Store

@Suite("Keychain control access store", .enabled(if: RefraxCodeSigning.ownTeamID != nil, "The test host has no keychain access group"))
struct KeychainControlAccessStoreTests {
    @Test
    func `State saved to the keychain reads back, and a later save replaces it`() {
        let identifier = "website.refrax.tests.\(UUID().uuidString)"
        let store = KeychainControlAccessStore(bundleIdentifier: identifier)
        defer {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecUseDataProtectionKeychain as String: true,
                kSecAttrService as String: "\(identifier).control-access",
            ]
            SecItemDelete(query as CFDictionary)
        }

        #expect(store.load() == nil)
        store.save(ControlAccessState(mode: .off))
        #expect(store.load()?.mode == .off)
        store.save(ControlAccessState(mode: .open))
        #expect(store.load()?.mode == .open)
    }
}

// MARK: - Real Signatures

@Suite("Socket peer signatures", .enabled(if: RefraxCodeSigning.ownTeamID != nil, "The test host has no developer team"))
struct SocketPeerSignatureTests {
    /// Connects to a socket this process listens on, and returns both ends.
    private static func connectedPair() throws -> (listener: Int32, client: Int32, path: String) {
        let path = NSTemporaryDirectory() + "rx-\(UUID().uuidString.prefix(8)).sock"
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: address.sun_path)
        _ = withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { strlcpy($0, path, capacity) }
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)

        let listener = socket(AF_UNIX, SOCK_STREAM, 0)
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(listener, $0, length) }
        }
        try #require(bound == 0 && listen(listener, 1) == 0)

        let client = socket(AF_UNIX, SOCK_STREAM, 0)
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(client, $0, length) }
        }
        try #require(connected == 0)
        return (listener, client, path)
    }

    @Test
    func `The server end satisfies its own team's requirement and no other`() throws {
        let team = try #require(RefraxCodeSigning.ownTeamID)
        let identifier = try #require(Bundle.main.bundleIdentifier)
        let (listener, client, path) = try Self.connectedPair()
        defer {
            close(client)
            close(listener)
            unlink(path)
        }

        let peer = try #require(SocketPeer(fileDescriptor: client))
        let ownRequirement = try #require(RefraxCodeSigning.appRequirement(bundleIdentifier: identifier, teamID: team))
        let otherTeam = try #require(RefraxCodeSigning.appRequirement(bundleIdentifier: identifier, teamID: "ZZZZZZZZZZ"))
        let cliRequirement = try #require(RefraxCodeSigning.cliRequirement(teamID: team))

        #expect(peer.pid == getpid())
        #expect(peer.satisfies(ownRequirement))
        #expect(!peer.satisfies(otherTeam))
        #expect(!peer.satisfies(cliRequirement))
    }
}
