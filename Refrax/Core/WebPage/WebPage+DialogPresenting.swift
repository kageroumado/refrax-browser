import Foundation
import WebKit

// MARK: - Dialog Result Types

extension WebPage {
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
    /// Presents the window-level panels a page can open: the file picker.
    ///
    /// JavaScript dialogs are page questions (`PagePrompts`), shown in the page's own pane.
    protocol DialogPresenting {
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
    /// Default implementation: returns `.cancel`.
    @MainActor
    func handleFileInputPrompt(
        parameters _: WKOpenPanelParameters,
        initiatedBy _: WebPage.FrameInfo,
    ) async -> WebPage.FileInputPromptResult {
        .cancel
    }
}
