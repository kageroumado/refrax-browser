import Security
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Manages the presentation of JavaScript dialogs and file input panels.
///
/// `DialogState` holds the current dialog to present (if any) and its associated
/// continuation for async/await integration. Only one dialog can be active at a time.
///
/// ## Supported Dialogs
///
/// - **Alert**: Simple message with OK button (`window.alert()`)
/// - **Confirm**: Yes/No choice (`window.confirm()`)
/// - **Prompt**: Text input with optional default (`window.prompt()`)
/// - **File Input**: Native file picker (`<input type="file">`)
///
/// ## Usage
///
/// Dialog state is observed by the main browser window and presented as sheets:
///
/// ```swift
/// .sheet(item: $dialogState.alert) { info in
///     AlertDialog(message: info.message) {
///         info.continuation.resume()
///     }
/// }
/// ```
///
/// The continuation resumes the JavaScript execution with the user's response.
@Observable
final class DialogState {
    /// Active JavaScript alert dialog, if any.
    var alert: AlertInfo?

    /// Active JavaScript confirm dialog, if any.
    var confirm: ConfirmInfo?

    /// Active JavaScript prompt dialog, if any.
    var prompt: PromptInfo?

    /// Active file input panel, if any.
    var fileInput: FileInputInfo?

    /// Active client certificate (mTLS) picker, if any.
    var clientCertificate: ClientCertificateInfo?

    /// Information for presenting a JavaScript `alert()` dialog.
    struct AlertInfo: Identifiable {
        let id = UUID()
        /// The message to display.
        let message: String
        /// Continuation to resume when the user dismisses the alert.
        let continuation: CheckedContinuation<Void, Never>
    }

    /// Information for presenting a JavaScript `confirm()` dialog.
    struct ConfirmInfo: Identifiable {
        let id = UUID()
        /// The question to display.
        let message: String
        /// Continuation to resume with the user's choice.
        let continuation: CheckedContinuation<WebPage.JavaScriptConfirmResult, Never>
    }

    /// Information for presenting a JavaScript `prompt()` dialog.
    struct PromptInfo: Identifiable {
        let id = UUID()
        /// The prompt message to display.
        let message: String
        /// Default text for the input field.
        let defaultText: String?
        /// Continuation to resume with the user's input.
        let continuation: CheckedContinuation<WebPage.JavaScriptPromptResult, Never>
    }

    /// Information for presenting a file input panel.
    struct FileInputInfo: Identifiable {
        let id = UUID()
        /// WebKit parameters specifying allowed file types and selection mode.
        let parameters: WKOpenPanelParameters
        /// Continuation to resume with selected files.
        let continuation: CheckedContinuation<WebPage.FileInputPromptResult, Never>
    }

    /// Information for presenting a client certificate (mTLS) picker.
    ///
    /// The picker lets the user choose one of their keychain identities to
    /// present to the server when it issues an
    /// `NSURLAuthenticationMethodClientCertificate` challenge.
    struct ClientCertificateInfo: Identifiable {
        let id = UUID()
        /// Challenge host, shown in the picker message.
        let host: String
        /// Candidate identities to present (already filtered by issuer DNs).
        let identities: [SecIdentity]
        /// Continuation resumed with the chosen identity, or `nil` for cancel.
        let continuation: CheckedContinuation<SecIdentity?, Never>
    }
}

extension WKOpenPanelParameters {
    /// Content types allowed by the file input, derived from the `accept` attribute.
    ///
    /// Attempts to parse types in this order:
    /// 1. `_allowedFileExtensions` (macOS 11+, most reliable)
    /// 2. `_acceptedMIMETypes` (fallback for MIME-only accept attributes)
    ///
    /// Returns `[.item]` (any file) if no restrictions are specified.
    var allowedContentTypes: [UTType] {
        var types: [UTType] = []

        // Try file extensions first (most reliable on macOS 11+)
        if let extensions = _allowedFileExtensions {
            types = extensions.compactMap { UTType(filenameExtension: $0) }
        }

        // If no extensions, try MIME types (handles "image/*", "application/pdf", etc.)
        if types.isEmpty, let mimeTypes = _acceptedMIMETypes {
            types = mimeTypes.compactMap { UTType(mimeType: $0) }
        }

        return types.isEmpty ? [.item] : types
    }
}
