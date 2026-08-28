import AuthenticationServices

/// Serves Refrax's saved logins to the system Password AutoFill flow and hosts
/// the Credential Exchange import/export handshake.
///
/// Credential serving reads the shared-keychain store
/// (`website.refrax.browser.shared`); that wiring lands in a later pass. For now
/// the extension exists to declare the AutoFill + Credential Exchange
/// capabilities so Refrax appears as an AutoFill provider and as an
/// import/export target.
class CredentialProviderViewController: ASCredentialProviderViewController {

    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
    }

    @IBAction func cancel(_ sender: AnyObject?) {
        extensionContext.cancelRequest(
            withError: NSError(
                domain: ASExtensionErrorDomain,
                code: ASExtensionError.userCanceled.rawValue,
            ),
        )
    }

    /// Wired to the list UI's fill button. Until credential serving reads the
    /// shared-keychain store there is nothing to provide, so a selection
    /// cancels rather than returning a credential.
    @IBAction func passwordSelected(_ sender: AnyObject?) {
        cancel(sender)
    }
}
