import AppKit

// MARK: - Form Data State

extension WebPage {
    /// Checks and updates the form data state.
    func checkFormDataState() async {
        let contentScriptManager = NSApplication.shared.typedDelegate.contentScriptManager
        hasUnsavedFormData = await contentScriptManager.queryFormDataState(for: self)
    }

    /// Resets the cached form data state.
    func resetFormDataState() {
        hasUnsavedFormData = false
    }
}
