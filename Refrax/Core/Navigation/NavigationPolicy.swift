import Foundation
import WebKit

// MARK: - Navigation Policy

/// Navigation policies operate directly on `WebPage.NavigationAction`.
///
/// Design rationale:
/// - `WebPage.NavigationAction` already mirrors WebKit and now includes
///   derived properties (user gesture, new-window detection, etc.).
/// - Keeping a single action type avoids divergence between wrapper and
///   WebKit behavior as APIs evolve.

/// The result of evaluating a navigation request.
///
/// Navigation handlers return a policy to indicate how the navigation should proceed.
/// Policies are ordered by precedence—once a handler returns a non-`.next` policy,
/// processing stops and that policy is applied.
///
/// ## Policy Precedence
///
/// 1. `.cancel` - Immediately stops the navigation
/// 2. `.redirect` - Modifies the request and restarts navigation
/// 3. `.download` - Converts navigation to a download (response policies only)
/// 4. `.allow` - Permits navigation to proceed
/// 5. `.next` - Delegates to the next handler in the chain
///
/// ## Example
///
/// ```swift
/// func evaluate(_ action: WebPage.NavigationAction) -> NavigationActionPolicy {
///     guard action.url.scheme == "mailto" else {
///         return .next  // Not our concern
///     }
///     NSWorkspace.shared.open(action.url)
///     return .cancel  // Handled externally
/// }
/// ```
nonisolated enum NavigationActionPolicy: Sendable, Equatable {
    /// Allow the navigation to proceed unchanged.
    case allow

    /// Cancel the navigation entirely.
    ///
    /// Use when the navigation should not occur, either because it was
    /// handled externally (e.g., opened in another app) or blocked.
    case cancel

    /// Redirect to a modified URL.
    ///
    /// The navigation will restart with the new URL. Common uses include
    /// stripping tracking parameters or converting AMP links to canonical URLs.
    ///
    /// - Parameter url: The new destination URL.
    case redirect(URL)

    /// Open the URL in a new tab.
    ///
    /// Use for popup requests or target="_blank" links that should open
    /// in the browser rather than being blocked.
    ///
    /// - Parameters:
    ///   - url: The URL to open in the new tab.
    ///   - activate: Whether to switch focus to the new tab.
    case openInNewTab(URL, activate: Bool)

    /// Initiate a download for the URL.
    ///
    /// Use when a link has the HTML5 `download` attribute set.
    ///
    /// - Parameter url: The URL to download.
    case download(URL)

    /// Show the URL in a preview panel instead of navigating.
    ///
    /// Used for navigation containment on pinned tabs and live favorites.
    /// Cross-domain navigations are intercepted and shown in a preview panel,
    /// keeping the tab focused on its designated site (Arc-style behavior).
    ///
    /// - Parameter url: The URL to preview.
    case showPreview(URL)

    /// Pass to the next handler in the chain.
    ///
    /// Use when this handler doesn't apply to the current navigation.
    /// If all handlers return `.next`, the navigation is allowed.
    case next
}

/// The result of evaluating a navigation response.
///
/// Response policies are evaluated after the server responds but before
/// content is rendered. This allows inspection of HTTP status codes,
/// MIME types, and content disposition headers.
nonisolated enum NavigationResponsePolicy: Sendable, Equatable {
    /// Allow the response to be rendered.
    case allow

    /// Cancel and do not render the response.
    case cancel

    /// Convert to a download instead of rendering.
    ///
    /// Use when the content should be saved rather than displayed,
    /// such as for non-displayable MIME types or explicit download headers.
    case download

    /// Redirect to an error page.
    ///
    /// - Parameters:
    ///   - code: The HTTP status code or error code.
    ///   - failedURL: The URL that failed.
    case showError(code: Int, failedURL: URL)

    /// Pass to the next handler in the chain.
    case next
}

/// Contextual information about a navigation response.
///
/// Wraps `WebPage.NavigationResponse` with convenient accessors for
/// HTTP metadata and content type information.
struct NavigationResponse: Sendable {
    /// The underlying WebKit navigation response.
    let webKitResponse: WebPage.NavigationResponse

    /// Whether this response is for the main frame.
    ///
    /// Accesses the underlying `WKNavigationResponse.isForMainFrame` via reflection
    /// on `WebPage.NavigationResponse`.
    var isMainFrame: Bool { webKitResponse.isForMainFrame }

    /// The URL of the response.
    var url: URL? { webKitResponse.response.url }

    /// The HTTP response, if this is an HTTP(S) response.
    var httpResponse: HTTPURLResponse? {
        webKitResponse.response as? HTTPURLResponse
    }

    /// The HTTP status code, or `nil` for non-HTTP responses.
    var statusCode: Int? { httpResponse?.statusCode }

    /// The MIME type of the response content.
    var mimeType: String? { webKitResponse.response.mimeType }

    /// Whether WebKit can render this content type.
    var canShowMIMEType: Bool { webKitResponse.canShowMimeType }

    /// Whether the server indicated this should be downloaded.
    ///
    /// Checks the `Content-Disposition` header for `attachment` directive
    /// per [RFC 6266](https://datatracker.ietf.org/doc/html/rfc6266).
    ///
    /// The header format can be:
    /// - `attachment`
    /// - `attachment; filename="file.pdf"`
    /// - `  attachment  ` (with leading/trailing whitespace)
    var hasDownloadDisposition: Bool {
        guard let disposition = httpResponse?.value(forHTTPHeaderField: "Content-Disposition") else {
            return false
        }

        // Extract disposition type (the part before any semicolon)
        // Per RFC 6266, the disposition-type is the first token
        let lowercased = disposition.lowercased().trimmingCharacters(in: .whitespaces)
        let dispositionType = lowercased.split(separator: ";", maxSplits: 1).first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? lowercased

        return dispositionType == "attachment"
    }

    /// Suggested filename from the response headers.
    ///
    /// Extracts the filename from `Content-Disposition` header if present,
    /// falls back to the URL's last path component.
    ///
    /// Per [RFC 6266 § 4.3](https://datatracker.ietf.org/doc/html/rfc6266#section-4.3),
    /// the filename parameter format can be:
    /// - `filename="report.pdf"`
    /// - `filename*=UTF-8''%E2%82%AC%20report.pdf` (RFC 5987 encoding)
    var suggestedFilename: String? {
        guard let disposition = httpResponse?.value(forHTTPHeaderField: "Content-Disposition") else {
            return nil
        }

        // Parse filename from Content-Disposition
        // Format: attachment; filename="report.pdf" or filename=report.pdf
        let components = disposition.split(separator: ";")
        for component in components {
            let trimmed = component.trimmingCharacters(in: .whitespaces)

            // Handle filename="value" or filename=value
            if trimmed.lowercased().hasPrefix("filename=") {
                var value = String(trimmed.dropFirst(9)) // Remove "filename="

                // Remove quotes if present
                if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                    value = String(value.dropFirst().dropLast())
                }

                // Decode percent encoding if present
                return value.removingPercentEncoding ?? value
            }

            // Handle filename*=UTF-8''value (RFC 5987)
            if trimmed.lowercased().hasPrefix("filename*=") {
                let value = String(trimmed.dropFirst(10)) // Remove "filename*="

                // RFC 5987 format: charset'language'encoded-value
                let parts = value.split(separator: "'", maxSplits: 2)
                if parts.count >= 3 {
                    let encoded = String(parts[2])
                    return encoded.removingPercentEncoding ?? encoded
                }
            }
        }

        return nil
    }
}

// MARK: - Handler Protocols

/// A handler that evaluates navigation action requests.
///
/// Implement this protocol to create modular navigation policies. Handlers
/// are composed into a chain and evaluated in order until one returns a
/// non-`.next` policy.
///
/// ## Implementation Guidelines
///
/// - Return `.next` when the handler doesn't apply
/// - Be stateless when possible for thread safety
/// - Avoid side effects in the `evaluate` method
/// - Document what navigation types the handler processes
///
/// ## Testability
///
/// Handlers accept `any NavigationActionInput` rather than the concrete
/// `WebPage.NavigationAction` type. This allows unit tests to provide
/// `MockNavigationAction` instances without requiring real WebKit objects.
///
/// ## Example
///
/// ```swift
/// struct ExternalSchemeHandler: NavigationActionHandler {
///     func evaluate(_ action: some NavigationActionInput) -> NavigationActionPolicy {
///         guard let url = action.url,
///               let scheme = url.scheme?.lowercased(),
///               !["http", "https", "file", "about", "data", "blob"].contains(scheme)
///         else {
///             return .next
///         }
///         NSWorkspace.shared.open(url)
///         return .cancel
///     }
/// }
/// ```
protocol NavigationActionHandler: Sendable {
    /// Evaluates a navigation action and returns a policy decision.
    ///
    /// - Parameter action: The navigation action to evaluate.
    /// - Returns: A policy indicating how to handle the navigation.
    func evaluate(_ action: some NavigationActionInput) async -> NavigationActionPolicy
}

/// A handler that evaluates navigation responses.
///
/// Response handlers run after the server responds but before content renders.
/// Use for HTTP status code handling, MIME type decisions, and download detection.
///
/// Handlers accept `any NavigationResponseInput` for testability with mocks.
protocol NavigationResponseHandler: Sendable {
    /// Evaluates a navigation response and returns a policy decision.
    ///
    /// - Parameter response: The navigation response to evaluate.
    /// - Returns: A policy indicating how to handle the response.
    func evaluate(_ response: some NavigationResponseInput) async -> NavigationResponsePolicy
}
