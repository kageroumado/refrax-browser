import WebKit

final class BrowserDialogPresenter: WebPage.DialogPresenting {
    let dialogState: DialogState
    
    init(dialogState: DialogState) {
        self.dialogState = dialogState
    }
    
    // MARK: - File Input

    func handleFileInputPrompt(
        parameters: WKOpenPanelParameters,
        initiatedBy _: WebPage.FrameInfo,
    ) async -> WebPage.FileInputPromptResult {
        Logger.info("File input requested", category: Logger.navigation)

        return await withCheckedContinuation { continuation in
            dialogState.fileInput = DialogState.FileInputInfo(
                parameters: parameters,
                continuation: continuation,
            )
        }
    }

    // MARK: - Client Certificate (mTLS)

    /// Presents a client certificate picker for an `NSURLAuthenticationMethodClientCertificate` challenge.
    ///
    /// - Parameters:
    ///   - host: The challenge host, shown to the user.
    ///   - identities: Candidate identities (already filtered by issuer DNs).
    /// - Returns: The chosen identity, or `nil` if the user cancels.
    func handleClientCertificateChallenge(
        host: String,
        identities: [SecIdentity],
    ) async -> SecIdentity? {
        Logger.info(
            "Client certificate challenge for \(host) (\(identities.count) identities)",
            category: Logger.security,
        )

        return await withCheckedContinuation { continuation in
            dialogState.clientCertificate = DialogState.ClientCertificateInfo(
                host: host,
                identities: identities,
                continuation: continuation,
            )
        }
    }
}
