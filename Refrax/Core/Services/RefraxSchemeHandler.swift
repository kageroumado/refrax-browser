import Foundation
import WebKit

/// Handles `refrax://` URL scheme requests within WebKit.
///
/// When WebKit encounters a `refrax://` URL, it delegates to this handler
/// instead of attempting to load it as a web resource. The handler notifies
/// the associated ``WebPage`` to trigger a SwiftUI view update, then returns
/// a minimal response to satisfy WebKit.
///
/// ## How It Works
///
/// 1. User navigates to a `refrax://` deep link (e.g., `refrax://ssl-error`)
/// 2. WebKit sees the registered `refrax` scheme
/// 3. WebKit calls `reply(for:)` on this handler
/// 4. Handler sets `isShowingDeepLink = true` on the associated `WebPage`
/// 5. Handler returns a minimal valid response (empty HTML)
/// 6. SwiftUI observes the flag change and renders ``DeepLinkView``
///
/// ## Per-Page Registration
///
/// Each ``WebPage`` creates its own handler instance and registers it
/// with the ``WebPage.Configuration``. This allows the handler to directly
/// notify the correct page when a deep link is intercepted.
final class RefraxSchemeHandler: URLSchemeHandler {
    /// Callback to notify the page when a deep link is intercepted.
    /// Passes the intercepted URL so the page can store it for view rendering.
    private let onDeepLinkIntercepted: @MainActor (URL) -> Void

    /// Creates a scheme handler that notifies the given callback on interception.
    ///
    /// - Parameter onDeepLinkIntercepted: Called on the main actor when a
    ///   `refrax://` URL is intercepted. Receives the intercepted URL.
    init(onDeepLinkIntercepted: @escaping @MainActor (URL) -> Void) {
        self.onDeepLinkIntercepted = onDeepLinkIntercepted
    }

    /// Responds to requests for `refrax://` URLs.
    ///
    /// Notifies the page via the callback with the intercepted URL,
    /// then returns a minimal valid response that signals success to WebKit.
    ///
    /// - Parameter request: The URL request for the `refrax://` resource.
    /// - Returns: An async sequence yielding a response and empty data.
    func reply(
        for request: URLRequest,
    ) -> some AsyncSequence<URLSchemeTaskResult, any Error> {
        // Capture callback for use in the stream
        let callback = onDeepLinkIntercepted

        return AsyncThrowingStream { continuation in
            guard let url = request.url else {
                continuation.finish(throwing: URLError(.badURL))
                return
            }

            // Notify the page on the main actor with the intercepted URL
            DispatchQueue.main.async {
                callback(url)
            }

            // Return a minimal successful response.
            // The actual content is rendered by DeepLinkView in WebViewContainer.
            let response = URLResponse(
                url: url,
                mimeType: "text/html",
                expectedContentLength: 0,
                textEncodingName: "utf-8",
            )

            continuation.yield(.response(response))
            continuation.yield(.data(Data()))
            continuation.finish()
        }
    }
}
