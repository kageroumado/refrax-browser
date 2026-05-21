import Foundation
import WebKit

// MARK: - Dialog Result Types

extension WebPage {
    /// The result of handling a JavaScript `confirm()` dialog.
    enum JavaScriptConfirmResult: Hashable, Sendable {
        /// The user pressed OK.
        case ok

        /// The user pressed Cancel.
        case cancel
    }

    /// The result of handling a JavaScript `prompt()` dialog.
    enum JavaScriptPromptResult: Hashable, Sendable {
        /// The user pressed OK with the specified text.
        case ok(String)

        /// The user pressed Cancel.
        case cancel
    }

    /// The result of handling a file input prompt.
    enum FileInputPromptResult: Hashable, Sendable {
        /// The user selected the specified files.
        case selected([URL])

        /// The user cancelled the selection.
        case cancel
    }
}

// MARK: - Dialog Presenting Protocol

extension WebPage {
    /// Allows providing custom behavior to handle JavaScript actions and provide a response.
    ///
    /// Typically when handling these, some UI should be presented to the user for them to provide a response,
    /// which will then be communicated back to JavaScript.
    ///
    /// When these methods are invoked, JavaScript is blocked until the async method returns.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct MyDialogPresenter: WebPage.DialogPresenting {
    ///     @MainActor
    ///     func handleJavaScriptAlert(
    ///         message: String,
    ///         initiatedBy frame: WebPage.FrameInfo
    ///     ) async {
    ///         // Show alert UI
    ///     }
    ///
    ///     @MainActor
    ///     func handleJavaScriptConfirm(
    ///         message: String,
    ///         initiatedBy frame: WebPage.FrameInfo
    ///     ) async -> WebPage.JavaScriptConfirmResult {
    ///         // Show confirm UI and return result
    ///         return .ok
    ///     }
    /// }
    /// ```
    protocol DialogPresenting {
        /// A JavaScript `alert()` function has been invoked.
        ///
        /// - Parameters:
        ///   - message: The message provided by JavaScript.
        ///   - frame: Information about the frame that initiated the call.
        @MainActor
        func handleJavaScriptAlert(
            message: String,
            initiatedBy frame: WebPage.FrameInfo,
        ) async

        /// A JavaScript `confirm()` function has been invoked.
        ///
        /// - Parameters:
        ///   - message: The message provided by JavaScript.
        ///   - frame: Information about the frame that initiated the call.
        /// - Returns: The result of handling the dialog.
        @MainActor
        func handleJavaScriptConfirm(
            message: String,
            initiatedBy frame: WebPage.FrameInfo,
        ) async -> WebPage.JavaScriptConfirmResult

        /// A JavaScript `prompt()` function has been invoked.
        ///
        /// - Parameters:
        ///   - message: The message provided by JavaScript.
        ///   - defaultText: The initial text for the input field.
        ///   - frame: Information about the frame that initiated the call.
        /// - Returns: The result of handling the dialog.
        @MainActor
        func handleJavaScriptPrompt(
            message: String,
            defaultText: String?,
            initiatedBy frame: WebPage.FrameInfo,
        ) async -> WebPage.JavaScriptPromptResult

        /// A file input element has been activated.
        ///
        /// - Parameters:
        ///   - parameters: Options for the file dialog.
        ///   - frame: Information about the frame that initiated the call.
        /// - Returns: The result of handling the file selection.
        @MainActor
        func handleFileInputPrompt(
            parameters: WKOpenPanelParameters,
            initiatedBy frame: WebPage.FrameInfo,
        ) async -> WebPage.FileInputPromptResult
    }
}

// MARK: - Default Implementation

extension WebPage.DialogPresenting {
    /// Default implementation: immediately returns.
    @MainActor
    func handleJavaScriptAlert(
        message _: String,
        initiatedBy _: WebPage.FrameInfo,
    ) async {
        // No-op by default
    }

    /// Default implementation: returns `.cancel`.
    @MainActor
    func handleJavaScriptConfirm(
        message _: String,
        initiatedBy _: WebPage.FrameInfo,
    ) async -> WebPage.JavaScriptConfirmResult {
        .cancel
    }

    /// Default implementation: returns `.cancel`.
    @MainActor
    func handleJavaScriptPrompt(
        message _: String,
        defaultText _: String?,
        initiatedBy _: WebPage.FrameInfo,
    ) async -> WebPage.JavaScriptPromptResult {
        .cancel
    }

    /// Default implementation: returns `.cancel`.
    @MainActor
    func handleFileInputPrompt(
        parameters _: WKOpenPanelParameters,
        initiatedBy _: WebPage.FrameInfo,
    ) async -> WebPage.FileInputPromptResult {
        .cancel
    }
}
