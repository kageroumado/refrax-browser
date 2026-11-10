import AppKit

/// Asks the user whether a client may control Refrax.
///
/// Deny is the default button. "Always Allow" appears only for a host with a verified code
/// requirement, since only such a host can be recognized again: by its signer, or, for ad hoc
/// signed code, by the hash of that one build.
nonisolated enum ControlAccessPrompt {
    @MainActor
    static func prompt(for identity: ClientIdentity) -> AuthorizationDecision {
        let host = identity.host
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = identity.viaCLI
            ? "Allow “\(host.displayName)” to control Refrax via refrax-ctl?"
            : "Allow “\(host.displayName)” to control Refrax?"
        alert.informativeText = informativeText(for: identity)

        if host.kind == .app {
            alert.icon = NSWorkspace.shared.icon(forFile: host.path)
        }

        alert.addButton(withTitle: "Deny")
        alert.addButton(withTitle: "Allow Once")
        if host.requirement != nil {
            alert.addButton(withTitle: "Always Allow")
        }

        switch alert.runModal() {
        case .alertSecondButtonReturn: return .allowOnce
        case .alertThirdButtonReturn: return .alwaysAllow
        default: return .deny
        }
    }

    /// The body of the prompt: who signed the host, where it is, and what allowing it grants.
    static func informativeText(for identity: ClientIdentity) -> String {
        let host = identity.host
        var lines: [String] = []

        switch host.kind {
        case .app:
            lines.append("Location: \(host.path)")
        case .process:
            lines.append("“\(host.displayName)” is a background process outside any app: \(host.path)")
        }

        if host.requirement == nil {
            lines.append("Its code has no valid signature, so Refrax can allow it only once.")
        } else if host.isPinnedToBuild {
            lines.append(
                "Its code is ad hoc signed, with no signature from Apple or an identified developer. "
                    + "Always Allow remembers this exact build, but any program you run can use it to control Refrax. "
                    + "Refrax asks again after it is updated or rebuilt.",
            )
        } else if host.isApple {
            lines.append("Signed by Apple.")
        } else if let teamID = host.teamID {
            lines.append("Signed by \(signerDisplayName(host.signerName, teamID: teamID)) (team \(teamID)).")
        }

        if identity.viaCLI {
            lines.append("It runs refrax-ctl at \(identity.peerPath).")
        }

        lines.append("Allowed, it can open and read pages, run scripts in them, and use their signed-in sessions.")
        return lines.joined(separator: "\n\n")
    }

    /// The developer name in a certificate subject such as
    /// "Developer ID Application: Name (TEAMID)".
    static func signerDisplayName(_ subject: String?, teamID: String) -> String {
        guard var name = subject else { return "an identified developer" }
        if let colon = name.firstIndex(of: ":") {
            name = String(name[name.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        }
        let suffix = " (\(teamID))"
        if name.hasSuffix(suffix) {
            name.removeLast(suffix.count)
        }
        return name.isEmpty ? "an identified developer" : name
    }
}
