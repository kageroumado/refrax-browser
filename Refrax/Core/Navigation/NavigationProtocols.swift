import Foundation
import WebKit

// MARK: - Navigation Action Protocol

/// Protocol for navigation action data that handlers can evaluate.
///
/// This abstraction allows navigation handlers to be tested with mock data
/// without requiring real WebKit objects. Production code uses
/// `WebPage.NavigationAction`, while tests use `MockNavigationAction`.
///
/// ## Design Rationale
///
/// WebKit's `WKNavigationAction` has no public initializers, making it
/// impossible to construct for unit tests. By extracting the interface
/// handlers actually use into a protocol, we enable:
///
/// 1. Fast unit tests without WebKit overhead
/// 2. Precise control over navigation scenarios
/// 3. Edge case testing that would be difficult with real navigations
///
/// ## Frame Information
///
/// Rather than exposing complex nested frame types, this protocol provides
/// flattened properties for the frame information handlers actually use:
/// - `sourceSecurityOriginProtocol` for the source frame's URL scheme
/// - `targetIsMainFrame` for checking if target is main frame
protocol NavigationActionInput: Sendable {
    /// The requested URL, if any.
    var url: URL? { get }

    /// Redirect chain for the current navigation, if available.
    var redirectChain: RedirectChain? { get }

    /// Whether this navigation targets the main frame.
    var isMainFrame: Bool { get }

    /// Whether this navigation requests a new window/tab.
    ///
    /// `true` for `target="_blank"` links and `window.open()` calls.
    var isNewWindowRequest: Bool { get }

    /// Whether this was a middle mouse button click.
    var isMiddleClick: Bool { get }

    /// Whether the Command key was held during navigation.
    var isCommandClick: Bool { get }

    /// Whether the Shift key was held during navigation.
    var isShiftHeld: Bool { get }

    /// Whether this navigation was triggered by a user gesture.
    var isUserInitiated: Bool { get }

    /// Whether this is a link activation (click).
    var isLinkActivated: Bool { get }

    /// Whether this is a form submission.
    var isFormSubmission: Bool { get }

    /// Whether this is a back/forward navigation.
    var isBackForward: Bool { get }

    /// Whether this is a reload.
    var isReload: Bool { get }

    /// Whether the web content indicated this should be downloaded.
    var shouldPerformDownload: Bool { get }

    /// Whether the new tab should be activated (switched to).
    var shouldActivateNewTab: Bool { get }

    /// The security origin protocol of the source frame (e.g., "https", "file").
    ///
    /// Used by `FileSchemeHandler` to detect file-to-file navigations.
    var sourceSecurityOriginProtocol: String { get }

    /// Whether the target frame is the main frame, if a target frame exists.
    ///
    /// Returns `nil` if `target` is nil (new window request).
    /// Used by `SubframeNavigationHandler` to detect subframe navigations.
    var targetIsMainFrame: Bool? { get }
}

// MARK: - Navigation Response Protocol

/// Protocol for navigation response data that handlers can evaluate.
///
/// Abstracts response information for testability without requiring
/// real HTTP responses.
protocol NavigationResponseInput: Sendable {
    /// Whether this response is for the main frame.
    var isMainFrame: Bool { get }

    /// The URL of the response.
    var url: URL? { get }

    /// The HTTP status code, if applicable.
    var statusCode: Int? { get }

    /// The MIME type of the response content.
    var mimeType: String? { get }

    /// Whether WebKit can render this content type.
    var canShowMIMEType: Bool { get }

    /// Whether the server indicated this should be downloaded.
    var hasDownloadDisposition: Bool { get }

    /// Suggested filename from the response headers.
    var suggestedFilename: String? { get }
}

// MARK: - WebPage.NavigationAction Conformance

extension WebPage.NavigationAction: NavigationActionInput {
    var sourceSecurityOriginProtocol: String {
        source.securityOrigin.protocol
    }

    var targetIsMainFrame: Bool? {
        target?.isMainFrame
    }
}

// MARK: - NavigationResponse Conformance

extension NavigationResponse: NavigationResponseInput {}

// MARK: - Popup Policy Protocol

/// Protocol for popup policy resolution.
///
/// Extracted from `SiteSettingsCoordinator` for testability.
/// Handlers can accept `any PopUpPolicyProviding` to enable mock injection.
@MainActor
protocol PopUpPolicyProviding: Sendable {
    /// Resolves the popup policy for a URL.
    ///
    /// - Parameter url: The URL requesting a popup.
    /// - Returns: The popup policy to apply.
    func popUpPolicy(for url: URL) -> PopUpPolicy
}

// MARK: - SiteSettingsCoordinator Conformance

extension SiteSettingsCoordinator: PopUpPolicyProviding {}

// MARK: - Popup Content Probing Protocol

/// Protocol for probing popup URLs to determine content type.
///
/// Extracted from `PopupContentProbe` for testability.
/// Tests can inject a mock that returns predetermined results.
protocol PopupContentProbing: Sendable {
    /// Probes a URL to determine if it leads to a download or webpage.
    ///
    /// - Parameters:
    ///   - url: The URL to probe.
    ///   - timeout: Maximum time to wait.
    /// - Returns: Probe result indicating content type.
    func probe(_ url: URL, timeout: TimeInterval) async -> PopupContentProbe.ProbeResult
}

extension PopupContentProbing {
    /// Probes a URL with default timeout.
    func probe(_ url: URL) async -> PopupContentProbe.ProbeResult {
        await probe(url, timeout: 3.0)
    }
}

// MARK: - PopupContentProbe Conformance

extension PopupContentProbe: PopupContentProbing {}
