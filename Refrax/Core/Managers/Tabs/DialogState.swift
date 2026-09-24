import Security
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// The window-level panels a page can open: the file picker and client certificate choice.
///
/// Each holds a continuation that resumes the page with the user's choice. JavaScript dialogs
/// and permission requests are per-page questions (`PagePrompts`).
@Observable
final class DialogState {
    /// Active file input panel, if any.
    var fileInput: FileInputInfo?

    /// Active client certificate (mTLS) picker, if any.
    var clientCertificate: ClientCertificateInfo?

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
