import WebKit

extension WKWebView {
    /// Evaluates JavaScript without synthesizing a user gesture.
    ///
    /// `evaluateJavaScript`/`callAsyncJavaScript` run scripts inside a forced
    /// user gesture and strip the window's transient activation afterward —
    /// erasing the activation a real user click just granted and breaking
    /// activation-gated APIs the page calls next (fullscreen, popups, PiP).
    /// Use this for any evaluation triggered by user-input-adjacent events
    /// (focus, editor state, selection, context menu) or that merely observes
    /// the page. Main frame, page content world only.
    @discardableResult
    func evaluateJavaScriptWithoutUserGesture(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            _evaluateJavaScriptWithoutUserGesture(script) { result, error in
                // WebKit invokes the completion on the main thread with immutable
                // property-list values; transferring them out is safe.
                nonisolated(unsafe) let result = result
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result)
                }
            }
        }
    }
}
