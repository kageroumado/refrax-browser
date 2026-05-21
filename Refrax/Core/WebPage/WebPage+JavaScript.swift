import Foundation
import WebKit

// MARK: - JavaScript

extension WebPage {
    /// Executes the specified string as an async JavaScript function.
    ///
    /// Don't format the string in the functionBody parameter as a function-like callable object, as you would in pure
    /// JavaScript. Instead, put only the body of the function in the string. For example, the following string shows a valid function body that takes x, y, and z
    /// arguments and returns a result.
    ///
    /// ```javascript
    /// return x ? y : z;
    /// ```
    ///
    /// If your JavaScript code returns an object with a callable then property, WebKit calls that property on
    /// the resulting object and waits for its resolution. If resolution succeeds, WebKit returns the resulting
    /// object. If resolution fails, WebKit throws a `WKErrorJavaScriptAsyncFunctionResultRejected` error. If the
    /// garbage collector reclaims the object before resolution finishes, WebKit throws a `WKErrorJavaScriptAsyncFunctionResultUnreachable` error.
    ///
    /// - Parameters:
    ///   - functionBody: The JavaScript string to use as the function body.
    ///   - arguments: A dictionary of the arguments to pass to the function call.
    ///   - frame: The frame in which to evaluate the JavaScript code. Specify `nil` to target the main frame.
    ///   - contentWorld: The namespace in which to evaluate the JavaScript code.
    /// - Returns: The result of the script evaluation.
    /// - Throws: An error if a problem occurred while evaluating the JavaScript.
    @discardableResult
    func callJavaScript(
        _ functionBody: String,
        arguments: [String: Any] = [:],
        in frame: FrameInfo? = nil,
        contentWorld: WKContentWorld? = nil,
    ) async throws -> Any? {
        try await backingWebView.callAsyncJavaScript(
            functionBody,
            arguments: arguments,
            in: frame?.wrapped,
            contentWorld: contentWorld ?? .page,
        )
    }

    /// Evaluates JavaScript in the page.
    ///
    /// - Note: This is a Refrax extension. The WebKit reference uses `callJavaScript` only.
    @discardableResult
    func evaluateJavaScript(
        _ script: String,
        in frame: FrameInfo? = nil,
        contentWorld: WKContentWorld = .page,
    ) async throws -> Any? {
        try await backingWebView.evaluateJavaScript(script, in: frame?.wrapped, contentWorld: contentWorld)
    }
}
