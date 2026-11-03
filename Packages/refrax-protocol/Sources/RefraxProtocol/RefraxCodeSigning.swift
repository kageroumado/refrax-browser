import Darwin
import Foundation
import Security

/// The code-signing identities on both ends of the control socket, and the checks each end
/// runs on the other.
///
/// Both ends identify the peer by the audit token of the connected socket, which names one
/// process image; a PID can be reused, and a path can be swapped.
///
/// Neither end names a team: each trusts the other only when it is signed by the team that
/// signed itself, read from its own signature at runtime. A contributor's build trusts only
/// that contributor's other half, and a build with no team (ad hoc or unsigned) trusts no one.
public enum RefraxCodeSigning {
    /// The signing identifier of `refrax-ctl`. Debug and release builds share it: the tool
    /// embeds no Info.plist, so `codesign` names it after the product.
    public static let cliIdentifier = "refrax-ctl"

    /// The bundle identifier of the release app.
    public static let releaseAppIdentifier = "website.refrax.browser"

    /// The bundle identifier of the debug app.
    public static let debugAppIdentifier = "website.refrax.browser.debug"

    /// The developer team that signed the running process, or `nil` when its code is unsigned,
    /// ad hoc signed, or fails validation.
    public static let ownTeamID: String? = {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCheckValidity(code, [], nil) == errSecSuccess
        else { return nil }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return nil }
        return teamID(of: staticCode)
    }()

    /// The developer team named by a valid, non-ad-hoc signature on `staticCode`.
    public static func teamID(of staticCode: SecStaticCode) -> String? {
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let info = info as? [String: Any]
        else { return nil }
        let flags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
        guard flags & SecCodeSignatureFlags.adhoc.rawValue == 0 else { return nil }
        guard let team = info[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty else { return nil }
        return team
    }

    /// Requirement text for `refrax-ctl` signed by `teamID`.
    public static func cliRequirement(teamID: String) -> String? {
        teamRequirement(identifier: cliIdentifier, teamID: teamID)
    }

    /// Requirement text for the Refrax app with `bundleIdentifier`, signed by `teamID`.
    public static func appRequirement(bundleIdentifier: String, teamID: String) -> String? {
        teamRequirement(identifier: bundleIdentifier, teamID: teamID)
    }

    /// Requirement text for code signed by a developer team under `identifier`.
    ///
    /// - Returns: `nil` when either value holds a character that requirement text would
    ///   have to escape (a quote, a backslash, or a control character).
    public static func teamRequirement(identifier: String, teamID: String) -> String? {
        guard isLiteralSafe(identifier), isLiteralSafe(teamID) else { return nil }
        return "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamID)\""
    }

    /// Requirement text for code Apple itself signed under `identifier`.
    public static func appleRequirement(identifier: String) -> String? {
        guard isLiteralSafe(identifier) else { return nil }
        return "anchor apple and identifier \"\(identifier)\""
    }

    private static func isLiteralSafe(_ value: String) -> Bool {
        !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
            scalar != "\"" && scalar != "\\" && !CharacterSet.controlCharacters.contains(scalar)
        }
    }
}

// MARK: - Socket Peer

/// The process on the other end of a connected Unix domain socket.
public struct SocketPeer: @unchecked Sendable {
    /// The peer's audit token, captured by the kernel at `connect(2)`.
    public let auditToken: audit_token_t

    /// Reads the audit token of the peer connected to `fileDescriptor`.
    public init?(fileDescriptor: Int32) {
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout<audit_token_t>.size)
        guard getsockopt(fileDescriptor, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &length) == 0,
              Int(length) == MemoryLayout<audit_token_t>.size
        else { return nil }
        self.auditToken = token
    }

    /// The peer's process ID. Word 5 of an audit token is the PID (`audit_token_to_pid`).
    public var pid: pid_t {
        pid_t(bitPattern: auditToken.val.5)
    }

    /// The running code behind the audit token.
    public var code: SecCode? {
        let tokenData = withUnsafeBytes(of: auditToken) { Data($0) }
        let attributes = [kSecGuestAttributeAudit as String: tokenData] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess else { return nil }
        return code
    }

    /// Whether the peer's code has a valid signature that satisfies `requirementText`.
    public func satisfies(_ requirementText: String) -> Bool {
        guard let code else { return false }
        return Self.code(code, satisfies: requirementText)
    }

    /// Whether `code` has a valid signature that satisfies `requirementText`.
    public static func code(_ code: SecCode, satisfies requirementText: String) -> Bool {
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(requirementText as CFString, [], &requirement) == errSecSuccess,
              let requirement
        else { return false }
        return SecCodeCheckValidity(code, [], requirement) == errSecSuccess
    }
}
