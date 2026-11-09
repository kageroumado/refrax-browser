import Darwin
import Foundation
import RefraxProtocol
import Security

// MARK: - Process Signing

/// One running process, named by the audit token of a socket peer or by a PID.
///
/// The peer is always named by its audit token. Its ancestors can only be named by PID,
/// so a host found by walking up from the peer is checked against the PID it has at the
/// moment of the check.
nonisolated enum ProcessReference: @unchecked Sendable {
    case peer(SocketPeer)
    case pid(pid_t)

    var pid: pid_t {
        switch self {
        case let .peer(peer): peer.pid
        case let .pid(pid): pid
        }
    }
}

/// Code-signing facts about one process, read from its validated signature.
nonisolated struct ProcessSigning: Sendable, Equatable {
    /// Path of the process's main executable.
    let executablePath: String
    /// Signing identifier, when the signature is valid.
    let identifier: String?
    /// Team identifier, when the signature is valid and names a developer team.
    let teamID: String?
    /// The signing certificate's subject, such as "Developer ID Application: Name (TEAMID)".
    let signerName: String?
    /// Whether Apple itself signed the code (`anchor apple`).
    let isApple: Bool
    /// The code directory hash, in hex, of validly ad hoc signed code: it names this exact
    /// build, so the build can be recognized again where its signer cannot.
    var cdHash: String? = nil
}

/// Reads code-signing facts and process relationships. The real implementation is
/// ``SecurityProcessInspector``; tests supply their own.
nonisolated protocol ProcessInspector: Sendable {
    /// Signing facts for a process, or `nil` when the process is gone.
    func signing(of process: ProcessReference) -> ProcessSigning?
    /// Whether the process's code has a valid signature that satisfies `requirement`.
    func process(_ process: ProcessReference, satisfies requirement: String) -> Bool
    /// The parent of `pid`.
    func parentPID(of pid: pid_t) -> pid_t?
    /// The process macOS holds responsible for `pid`, the one TCC asks about.
    func responsiblePID(for pid: pid_t) -> pid_t?
}

// MARK: - Client Identity

/// What the control server authorizes: the app (or process) on whose behalf a client
/// connected.
nonisolated struct ControlHost: Sendable, Equatable {
    nonisolated enum Kind: String, Codable, Sendable {
        /// A process whose main executable is an app bundle's.
        case app
        /// A process outside any app bundle: a launchd job, a cron job, a shell tool.
        case process
    }

    let kind: Kind
    let pid: pid_t
    /// The app bundle's path for an app, the executable's path otherwise.
    let path: String
    let displayName: String
    let identifier: String?
    let teamID: String?
    /// The signing certificate's subject, shown in the prompt.
    let signerName: String?
    let isApple: Bool
    /// Requirement text this host's running code was verified against. Ad hoc signed code is
    /// named by its code directory hash, so remembering it covers that build only. `nil` when
    /// the host is unsigned or failed validation; such a host can be allowed once but never
    /// remembered.
    let requirement: String?

    /// The requirement names this exact build by its hash, because the code is ad hoc signed.
    var isPinnedToBuild: Bool {
        requirement.map(ClientIdentity.isBuildRequirement) ?? false
    }
}

/// A connected control client: the peer process, and the host it acts for.
nonisolated struct ClientIdentity: Sendable, Equatable {
    let host: ControlHost
    /// Whether the peer is Refrax's own validly signed `refrax-ctl`.
    let viaCLI: Bool
    let peerPID: pid_t
    let peerPath: String

    var pid: pid_t {
        host.pid
    }

    var path: String {
        host.path
    }

    var displayName: String {
        host.displayName
    }

    /// Key that identifies the host across connections: its requirement, or its path when
    /// it has none.
    var hostKey: String {
        host.requirement ?? "unverified:\(host.path)"
    }
}

// MARK: - Derivation

nonisolated extension ClientIdentity {
    /// Most ancestors walked looking for the app that ran `refrax-ctl`.
    private static let maxAncestorDepth = 64

    /// Why a peer was refused before anyone was asked about it.
    nonisolated enum Refusal: Error, Equatable {
        /// The peer's process is gone, or its executable cannot be found.
        case unidentified
        /// The peer is `refrax-ctl`, but Refrax has no developer team to check it against.
        case appUnsigned(cliPath: String)
        /// The peer is `refrax-ctl` with a signature from another team, or none.
        case foreignCLI(cliPath: String, expectedTeam: String)

        var message: String {
            switch self {
            case .unidentified:
                "Refrax could not identify the connecting process."
            case let .appUnsigned(path):
                "This build of Refrax is not signed by a developer team, so it cannot verify refrax-ctl at \(path). "
                    + "Sign Refrax and refrax-ctl with your team."
            case let .foreignCLI(path, team):
                "refrax-ctl at \(path) is not signed by the team that signed Refrax (\(team)). "
                    + "Use the refrax-ctl built with this copy of Refrax."
            }
        }
    }

    /// Identifies the host behind a connected peer.
    ///
    /// When the peer is `refrax-ctl` signed by `ownTeamID`, the team that signed Refrax, the
    /// host is the app that ran it: the responsible process when it is an app, else the
    /// nearest app among the peer's ancestors, else the process that ran the CLI (the
    /// responsible one, or the parent). A peer that calls itself `refrax-ctl` by its signing
    /// identifier or file name is refused unless it passes that check. Any other peer is its
    /// own host.
    static func derive(
        peer: ProcessReference,
        ownTeamID: String?,
        inspector: some ProcessInspector,
    ) throws(Refusal) -> ClientIdentity {
        guard let peerSigning = inspector.signing(of: peer) else { throw .unidentified }
        let peerPID = peer.pid
        let peerPath = peerSigning.executablePath

        let claimsCLI = peerSigning.identifier == RefraxCodeSigning.cliIdentifier
            || (peerPath as NSString).lastPathComponent == RefraxCodeSigning.cliIdentifier
        let host: ControlHost?
        if claimsCLI {
            guard let ownTeamID else { throw .appUnsigned(cliPath: peerPath) }
            guard let requirement = RefraxCodeSigning.cliRequirement(teamID: ownTeamID),
                  inspector.process(peer, satisfies: requirement)
            else { throw .foreignCLI(cliPath: peerPath, expectedTeam: ownTeamID) }
            host = cliHost(peerPID: peerPID, inspector: inspector)
        } else {
            host = makeHost(peer, signing: peerSigning, inspector: inspector)
        }
        guard let host else { throw .unidentified }
        return ClientIdentity(host: host, viaCLI: claimsCLI, peerPID: peerPID, peerPath: peerPath)
    }

    private static func cliHost(peerPID: pid_t, inspector: some ProcessInspector) -> ControlHost? {
        let responsible = inspector.responsiblePID(for: peerPID).flatMap { $0 > 1 && $0 != peerPID ? $0 : nil }

        if let responsible, let host = appHost(pid: responsible, inspector: inspector) {
            return host
        }

        var visited: Set<pid_t> = [peerPID]
        var current = inspector.parentPID(of: peerPID)
        while let pid = current, pid > 1, visited.count < maxAncestorDepth, visited.insert(pid).inserted {
            if let host = appHost(pid: pid, inspector: inspector) {
                return host
            }
            current = inspector.parentPID(of: pid)
        }

        let runner = responsible ?? inspector.parentPID(of: peerPID).flatMap { $0 > 1 ? $0 : nil }
        guard let runner, let signing = inspector.signing(of: .pid(runner)) else { return nil }
        return makeHost(.pid(runner), signing: signing, inspector: inspector)
    }

    private static func appHost(pid: pid_t, inspector: some ProcessInspector) -> ControlHost? {
        guard let signing = inspector.signing(of: .pid(pid)),
              appBundlePath(forExecutable: signing.executablePath) != nil
        else { return nil }
        return makeHost(.pid(pid), signing: signing, inspector: inspector)
    }

    private static func makeHost(
        _ process: ProcessReference,
        signing: ProcessSigning,
        inspector: some ProcessInspector,
    ) -> ControlHost {
        let bundlePath = appBundlePath(forExecutable: signing.executablePath)
        let path = bundlePath ?? signing.executablePath
        let fileName = (path as NSString).lastPathComponent
        let displayName = bundlePath != nil ? (fileName as NSString).deletingPathExtension : fileName

        let requirement = requirementText(for: signing).flatMap { text in
            inspector.process(process, satisfies: text) ? text : nil
        }

        return ControlHost(
            kind: bundlePath != nil ? .app : .process,
            pid: process.pid,
            path: path,
            displayName: displayName,
            identifier: signing.identifier,
            teamID: signing.teamID,
            signerName: signing.signerName,
            isApple: signing.isApple,
            requirement: requirement,
        )
    }

    /// The requirement that names code with these signing facts: Apple's own code by
    /// identifier, a developer's by identifier and team, ad hoc signed code by its hash.
    static func requirementText(for signing: ProcessSigning) -> String? {
        if let cdHash = signing.cdHash {
            return buildRequirement(cdHash: cdHash)
        }
        guard let identifier = signing.identifier else { return nil }
        if signing.isApple {
            return RefraxCodeSigning.appleRequirement(identifier: identifier)
        }
        guard let teamID = signing.teamID else { return nil }
        return RefraxCodeSigning.teamRequirement(identifier: identifier, teamID: teamID)
    }

    /// Requirement text that only the code with the code directory hash `cdHash` satisfies.
    ///
    /// - Returns: `nil` unless `cdHash` is 40 hex digits, the 20 bytes macOS names code by.
    static func buildRequirement(cdHash: String) -> String? {
        guard cdHash.count == 40, cdHash.allSatisfy(\.isHexDigit) else { return nil }
        return "cdhash H\"\(cdHash.lowercased())\""
    }

    /// Whether `requirement` names one build by its hash, as ``buildRequirement(cdHash:)`` makes.
    static func isBuildRequirement(_ requirement: String) -> Bool {
        requirement.hasPrefix("cdhash ")
    }

    /// The `.app` bundle whose main executable is at `path`, as in
    /// `/Applications/Name.app/Contents/MacOS/Name`.
    static func appBundlePath(forExecutable path: String) -> String? {
        let components = (path as NSString).pathComponents
        guard components.count >= 4 else { return nil }
        let bundleIndex = components.count - 4
        guard components[bundleIndex].lowercased().hasSuffix(".app"),
              components[bundleIndex + 1] == "Contents",
              components[bundleIndex + 2] == "MacOS"
        else { return nil }
        return NSString.path(withComponents: Array(components[...bundleIndex]))
    }
}

// MARK: - Security Framework Inspector

/// Reads process signing through the Security framework, and process relationships through
/// `sysctl` and the responsibility SPI.
nonisolated struct SecurityProcessInspector: ProcessInspector {
    private typealias ResponsiblePIDFunction = @convention(c) (pid_t) -> pid_t

    /// `responsibility_get_pid_responsible_for_pid`, resolved at runtime because it is SPI.
    private static let responsiblePIDFunction: ResponsiblePIDFunction? = {
        guard let handle = dlopen(nil, RTLD_NOW),
              let symbol = dlsym(handle, "responsibility_get_pid_responsible_for_pid")
        else { return nil }
        return unsafeBitCast(symbol, to: ResponsiblePIDFunction.self)
    }()

    func signing(of process: ProcessReference) -> ProcessSigning? {
        guard let code = code(for: process) else { return nil }
        let path = Self.executablePath(of: code) ?? Self.executablePath(pid: process.pid)
        guard let path else { return nil }

        guard SecCodeCheckValidity(code, [], nil) == errSecSuccess,
              let info = Self.signingInformation(of: code)
        else {
            return ProcessSigning(executablePath: path, identifier: nil, teamID: nil, signerName: nil, isApple: false)
        }

        let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let isAdHoc = flags & SecCodeSignatureFlags.adhoc.rawValue != 0
        guard !isAdHoc else {
            // An ad hoc identifier is whatever the linker chose; only the hash names the code.
            return ProcessSigning(
                executablePath: path, identifier: nil, teamID: nil, signerName: nil, isApple: false,
                cdHash: Self.cdHash(in: info),
            )
        }

        let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate]
        let signerName = certificates?.first.flatMap { SecCertificateCopySubjectSummary($0) as String? }
        return ProcessSigning(
            executablePath: path,
            identifier: info[kSecCodeInfoIdentifier as String] as? String,
            teamID: info[kSecCodeInfoTeamIdentifier as String] as? String,
            signerName: signerName,
            isApple: Self.code(code, satisfies: "anchor apple"),
        )
    }

    func process(_ process: ProcessReference, satisfies requirement: String) -> Bool {
        guard let code = code(for: process) else { return false }
        return Self.code(code, satisfies: requirement)
    }

    func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }

    func responsiblePID(for pid: pid_t) -> pid_t? {
        guard let function = Self.responsiblePIDFunction else { return nil }
        let responsible = function(pid)
        return responsible > 0 ? responsible : nil
    }

    /// Signing facts for the code on disk at `url`, for adding an app to the allow list by
    /// hand. The facts are validated against the file's signature.
    static func signing(ofFileAt url: URL) -> (signing: ProcessSigning, requirement: String)? {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &staticCode) == errSecSuccess, let staticCode,
              SecStaticCodeCheckValidity(staticCode, SecCSFlags(rawValue: kSecCSCheckAllArchitectures), nil) == errSecSuccess
        else { return nil }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any]
        else { return nil }

        let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        let isAdHoc = flags & SecCodeSignatureFlags.adhoc.rawValue != 0
        let executablePath = (info[kSecCodeInfoMainExecutable as String] as? URL)?.path ?? url.path

        var appleRequirement: SecRequirement?
        SecRequirementCreateWithString("anchor apple" as CFString, [], &appleRequirement)
        let isApple = appleRequirement.map { SecStaticCodeCheckValidity(staticCode, [], $0) == errSecSuccess } ?? false

        let certificates = info[kSecCodeInfoCertificates as String] as? [SecCertificate]
        let signing = isAdHoc
            ? ProcessSigning(
                executablePath: executablePath, identifier: nil, teamID: nil, signerName: nil, isApple: false,
                cdHash: cdHash(in: info),
            )
            : ProcessSigning(
                executablePath: executablePath,
                identifier: info[kSecCodeInfoIdentifier as String] as? String,
                teamID: info[kSecCodeInfoTeamIdentifier as String] as? String,
                signerName: certificates?.first.flatMap { SecCertificateCopySubjectSummary($0) as String? },
                isApple: isApple,
            )
        guard let text = ClientIdentity.requirementText(for: signing) else { return nil }

        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess,
              let requirement,
              SecStaticCodeCheckValidity(staticCode, [], requirement) == errSecSuccess
        else { return nil }
        return (signing, text)
    }

    // MARK: Helpers

    private func code(for process: ProcessReference) -> SecCode? {
        switch process {
        case let .peer(peer):
            return peer.code
        case let .pid(pid):
            let attributes = [kSecGuestAttributePid as String: pid] as CFDictionary
            var code: SecCode?
            guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess else { return nil }
            return code
        }
    }

    private static func code(_ code: SecCode, satisfies requirement: String) -> Bool {
        SocketPeer.code(code, satisfies: requirement)
    }

    /// The code directory hash in signing information, in hex.
    private static func cdHash(in info: [String: Any]) -> String? {
        guard let unique = info[kSecCodeInfoUnique as String] as? Data, !unique.isEmpty else { return nil }
        return unique.map { String(format: "%02x", $0) }.joined()
    }

    private static func signingInformation(of code: SecCode) -> [String: Any]? {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        var info: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(staticCode, flags, &info) == errSecSuccess else { return nil }
        return info as? [String: Any]
    }

    private static func executablePath(of code: SecCode) -> String? {
        var staticCode: SecStaticCode?
        var url: CFURL?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyPath(staticCode, [], &url) == errSecSuccess, let url
        else { return nil }
        let path = (url as URL).path
        // For a bundle, SecCodeCopyPath names the bundle; the main executable is inside it.
        if path.hasSuffix(".app"), let executable = Bundle(path: path)?.executablePath {
            return executable
        }
        return path
    }

    private static func executablePath(pid: pid_t) -> String? {
        var buffer = [UInt8](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(decoding: buffer.prefix(Int(length)), as: UTF8.self)
    }
}
