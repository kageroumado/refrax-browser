import AppKit

/// Shows an authorization prompt when an unknown binary tries to connect
/// to the control server in prompt mode.
///
/// Uses `NSAlert` to present the binary's identity and let the user choose
/// whether to allow the connection.
nonisolated enum ControlAccessPrompt {
    /// Shows an authorization alert for the given client identity.
    ///
    /// - Returns: The user's authorization decision.
    @MainActor
    static func prompt(for identity: ClientIdentity) -> AuthorizationDecision {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Control Server Access Request"

        var info = "\"\(identity.displayName)\" wants to control Refrax."
        info += "\n\nPath: \(identity.path)"
        if let sigId = identity.signingIdentifier {
            info += "\nSigning ID: \(sigId)"
        }
        if let teamID = identity.teamID {
            info += "\nTeam ID: \(teamID)"
        }
        if identity.signingIdentifier == nil {
            info += "\n\nThis application is not code-signed."
        }

        alert.informativeText = info

        // Try to get the app icon for the binary
        if let icon = NSWorkspace.shared.icon(forFile: identity.path) as NSImage? {
            alert.icon = icon
        }

        alert.addButton(withTitle: "Always Allow")
        alert.addButton(withTitle: "Allow Once")
        alert.addButton(withTitle: "Deny")

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn: return .alwaysAllow
        case .alertSecondButtonReturn: return .allow
        default: return .deny
        }
    }
}
