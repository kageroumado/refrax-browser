import WebKit

final class BrowserDialogPresenter: WebPage.DialogPresenting {
    let dialogState: DialogState
    
    init(dialogState: DialogState) {
        self.dialogState = dialogState
    }
    
    // MARK: - JavaScript Alert
    
    func handleJavaScriptAlert(
        message: String,
        initiatedBy _: WebPage.FrameInfo,
    ) async {
        Logger.info("JS Alert: \(message)", category: Logger.navigation)
        
        await withCheckedContinuation { continuation in
            dialogState.alert = DialogState.AlertInfo(
                message: message,
                continuation: continuation,
            )
        }
    }
    
    // MARK: - JavaScript Confirm
    
    func handleJavaScriptConfirm(
        message: String,
        initiatedBy _: WebPage.FrameInfo,
    ) async -> WebPage.JavaScriptConfirmResult {
        Logger.info("JS Confirm: \(message)", category: Logger.navigation)
        
        return await withCheckedContinuation { continuation in
            dialogState.confirm = DialogState.ConfirmInfo(
                message: message,
                continuation: continuation,
            )
        }
    }
    
    // MARK: - JavaScript Prompt
    
    func handleJavaScriptPrompt(
        message: String,
        defaultText: String?,
        initiatedBy _: WebPage.FrameInfo,
    ) async -> WebPage.JavaScriptPromptResult {
        Logger.info("JS Prompt: \(message)", category: Logger.navigation)
        
        return await withCheckedContinuation { continuation in
            dialogState.prompt = DialogState.PromptInfo(
                message: message,
                defaultText: defaultText,
                continuation: continuation,
            )
        }
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
