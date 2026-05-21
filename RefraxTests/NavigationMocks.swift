import Foundation
import os
import Testing

@testable import Refrax

// MARK: - Mock Navigation Action

/// Mock implementation of `NavigationActionInput` for testing navigation handlers.
///
/// Provides full control over all navigation properties without requiring
/// WebKit objects. Default values are sensible for most tests.
///
/// ## Usage
///
/// ```swift
/// let action = MockNavigationAction(
///     url: URL(string: "https://example.com")!,
///     isMainFrame: true,
///     isUserInitiated: true
/// )
/// let policy = await handler.evaluate(action)
/// #expect(policy == .allow)
/// ```
struct MockNavigationAction: NavigationActionInput, Sendable {
    // MARK: - Properties

    var url: URL?
    var redirectChain: RedirectChain?
    var isMainFrame: Bool
    var isNewWindowRequest: Bool
    var isMiddleClick: Bool
    var isCommandClick: Bool
    var isShiftHeld: Bool
    var isUserInitiated: Bool
    var isLinkActivated: Bool
    var isFormSubmission: Bool
    var isBackForward: Bool
    var isReload: Bool
    var shouldPerformDownload: Bool
    var shouldActivateNewTab: Bool
    var sourceSecurityOriginProtocol: String
    var targetIsMainFrame: Bool?

    // MARK: - Initialization

    /// Creates a mock navigation action with the specified properties.
    ///
    /// - Parameters:
    ///   - url: The navigation URL. Defaults to `nil`.
    ///   - isMainFrame: Whether targeting main frame. Defaults to `true`.
    ///   - isNewWindowRequest: Whether requesting new window. Defaults to `false`.
    ///   - isMiddleClick: Whether middle-click triggered. Defaults to `false`.
    ///   - isCommandClick: Whether Cmd key held. Defaults to `false`.
    ///   - isShiftHeld: Whether Shift key held. Defaults to `false`.
    ///   - isUserInitiated: Whether user-initiated. Defaults to `false`.
    ///   - isLinkActivated: Whether link click. Defaults to `false`.
    ///   - isFormSubmission: Whether form submission. Defaults to `false`.
    ///   - isBackForward: Whether back/forward. Defaults to `false`.
    ///   - isReload: Whether reload. Defaults to `false`.
    ///   - shouldPerformDownload: Whether download attribute set. Defaults to `false`.
    ///   - shouldActivateNewTab: Whether new tab should activate. Defaults to `false`.
    ///   - sourceSecurityOriginProtocol: Source frame protocol. Defaults to `"https"`.
    ///   - targetIsMainFrame: Target frame main frame status. Defaults to `true`.
    init(
        url: URL? = nil,
        redirectChain: RedirectChain? = nil,
        isMainFrame: Bool = true,
        isNewWindowRequest: Bool = false,
        isMiddleClick: Bool = false,
        isCommandClick: Bool = false,
        isShiftHeld: Bool = false,
        isUserInitiated: Bool = false,
        isLinkActivated: Bool = false,
        isFormSubmission: Bool = false,
        isBackForward: Bool = false,
        isReload: Bool = false,
        shouldPerformDownload: Bool = false,
        shouldActivateNewTab: Bool = false,
        sourceSecurityOriginProtocol: String = "https",
        targetIsMainFrame: Bool? = true,
    ) {
        self.url = url
        self.redirectChain = redirectChain
        self.isMainFrame = isMainFrame
        self.isNewWindowRequest = isNewWindowRequest
        self.isMiddleClick = isMiddleClick
        self.isCommandClick = isCommandClick
        self.isShiftHeld = isShiftHeld
        self.isUserInitiated = isUserInitiated
        self.isLinkActivated = isLinkActivated
        self.isFormSubmission = isFormSubmission
        self.isBackForward = isBackForward
        self.isReload = isReload
        self.shouldPerformDownload = shouldPerformDownload
        self.shouldActivateNewTab = shouldActivateNewTab
        self.sourceSecurityOriginProtocol = sourceSecurityOriginProtocol
        self.targetIsMainFrame = targetIsMainFrame
    }
}

// MARK: - Mock Navigation Action Builders

extension MockNavigationAction {
    /// Creates a standard main frame navigation to the given URL.
    static func mainFrame(url: URL, userInitiated: Bool = false) -> MockNavigationAction {
        MockNavigationAction(
            url: url,
            isMainFrame: true,
            isUserInitiated: userInitiated,
        )
    }

    /// Creates a subframe navigation to the given URL.
    static func subframe(url: URL) -> MockNavigationAction {
        MockNavigationAction(
            url: url,
            isMainFrame: false,
            targetIsMainFrame: false,
        )
    }

    /// Creates a link click navigation.
    static func linkClick(url: URL, userInitiated: Bool = true) -> MockNavigationAction {
        MockNavigationAction(
            url: url,
            isMainFrame: true,
            isUserInitiated: userInitiated,
            isLinkActivated: true,
        )
    }

    /// Creates a middle-click navigation (opens in new tab).
    static func middleClick(url: URL) -> MockNavigationAction {
        MockNavigationAction(
            url: url,
            isMainFrame: true,
            isMiddleClick: true,
            isUserInitiated: true,
            isLinkActivated: true,
        )
    }

    /// Creates a Cmd+click navigation (opens in new tab).
    static func commandClick(url: URL, withShift: Bool = false) -> MockNavigationAction {
        MockNavigationAction(
            url: url,
            isMainFrame: true,
            isCommandClick: true,
            isShiftHeld: withShift,
            isUserInitiated: true,
            isLinkActivated: true,
            shouldActivateNewTab: withShift,
        )
    }

    /// Creates a new window/popup request.
    static func popup(url: URL?, userInitiated: Bool = true) -> MockNavigationAction {
        MockNavigationAction(
            url: url,
            isMainFrame: false,
            isNewWindowRequest: true,
            isUserInitiated: userInitiated,
            isLinkActivated: userInitiated,
            shouldActivateNewTab: true,
            targetIsMainFrame: nil,
        )
    }

    /// Creates a download action (download attribute present).
    static func download(url: URL) -> MockNavigationAction {
        MockNavigationAction(
            url: url,
            isMainFrame: true,
            isUserInitiated: true,
            isLinkActivated: true,
            shouldPerformDownload: true,
        )
    }

    /// Creates a form submission navigation.
    static func formSubmission(url: URL) -> MockNavigationAction {
        MockNavigationAction(
            url: url,
            isMainFrame: true,
            isUserInitiated: true,
            isFormSubmission: true,
        )
    }

    /// Creates a back/forward navigation.
    static func backForward(url: URL) -> MockNavigationAction {
        MockNavigationAction(
            url: url,
            isMainFrame: true,
            isUserInitiated: true,
            isBackForward: true,
        )
    }

    /// Creates a reload navigation.
    static func reload(url: URL) -> MockNavigationAction {
        MockNavigationAction(
            url: url,
            isMainFrame: true,
            isUserInitiated: true,
            isReload: true,
        )
    }

    /// Creates a file: URL navigation from a file: source.
    static func fileToFile(url: URL) -> MockNavigationAction {
        MockNavigationAction(
            url: url,
            isMainFrame: true,
            sourceSecurityOriginProtocol: "file",
        )
    }

    /// Creates a script-initiated navigation (not user-initiated).
    static func scriptInitiated(url: URL) -> MockNavigationAction {
        MockNavigationAction(
            url: url,
            isMainFrame: true,
            isUserInitiated: false,
            isLinkActivated: false,
        )
    }
}

// MARK: - Mock Navigation Response

/// Mock implementation of `NavigationResponseInput` for testing response handlers.
///
/// Provides full control over response properties without requiring
/// real HTTP responses or WebKit objects.
struct MockNavigationResponse: NavigationResponseInput, Sendable {
    var isMainFrame: Bool
    var url: URL?
    var statusCode: Int?
    var mimeType: String?
    var canShowMIMEType: Bool
    var hasDownloadDisposition: Bool
    var suggestedFilename: String?

    /// Creates a mock navigation response with the specified properties.
    init(
        isMainFrame: Bool = true,
        url: URL? = nil,
        statusCode: Int? = 200,
        mimeType: String? = "text/html",
        canShowMIMEType: Bool = true,
        hasDownloadDisposition: Bool = false,
        suggestedFilename: String? = nil,
    ) {
        self.isMainFrame = isMainFrame
        self.url = url
        self.statusCode = statusCode
        self.mimeType = mimeType
        self.canShowMIMEType = canShowMIMEType
        self.hasDownloadDisposition = hasDownloadDisposition
        self.suggestedFilename = suggestedFilename
    }
}

// MARK: - Mock Navigation Response Builders

extension MockNavigationResponse {
    /// Creates a successful HTML response.
    static func html(url: URL) -> MockNavigationResponse {
        MockNavigationResponse(
            url: url,
            statusCode: 200,
            mimeType: "text/html",
        )
    }

    /// Creates a download response (Content-Disposition: attachment).
    static func download(url: URL, filename: String? = nil, mimeType: String = "application/octet-stream") -> MockNavigationResponse {
        MockNavigationResponse(
            url: url,
            statusCode: 200,
            mimeType: mimeType,
            canShowMIMEType: false,
            hasDownloadDisposition: true,
            suggestedFilename: filename,
        )
    }

    /// Creates a non-displayable response (WebKit can't render).
    static func nonDisplayable(url: URL, mimeType: String) -> MockNavigationResponse {
        MockNavigationResponse(
            url: url,
            statusCode: 200,
            mimeType: mimeType,
            canShowMIMEType: false,
        )
    }

    /// Creates an HTTP error response.
    static func httpError(url: URL, statusCode: Int) -> MockNavigationResponse {
        MockNavigationResponse(
            url: url,
            statusCode: statusCode,
            mimeType: "text/html",
        )
    }

    /// Creates a subframe response.
    static func subframe(url: URL) -> MockNavigationResponse {
        MockNavigationResponse(
            isMainFrame: false,
            url: url,
            statusCode: 200,
            mimeType: "text/html",
        )
    }
}

// MARK: - Test URL Helpers

/// Common test URLs for navigation handler tests.
enum TestURLs {
    static let https = URL(string: "https://example.com")!
    static let http = URL(string: "http://example.com")!
    static let file = URL(string: "file:///Users/test/document.html")!
    static let data = URL(string: "data:text/html,<h1>Hello</h1>")!
    static let dataWithScript = URL(string: "data:text/html,<script>alert(1)</script>")!
    static let blob = URL(string: "blob:https://example.com/uuid-here")!
    static let javascript = URL(string: "javascript:alert(1)")!
    static let mailto = URL(string: "mailto:test@example.com")!
    static let tel = URL(string: "tel:+1234567890")!
    static let slack = URL(string: "slack://open")!
    static let refrax = URL(string: "refrax://ssl-error?type=expired&url=https://example.com")!
    static let refraxFocusBlocked = URL(string: "refrax://focus-blocked?url=https://example.com&focus=Work")!

    // Tracking URLs
    static let withTracking = URL(string: "https://example.com/page?utm_source=test&id=123")!
    static let amp = URL(string: "https://www.google.com/amp/s/example.com/article")!

    // Downloads
    static let pdf = URL(string: "https://example.com/document.pdf")!
    static let zip = URL(string: "https://example.com/archive.zip")!

    // OAuth / payment
    static let oauth = URL(string: "https://accounts.google.com/o/oauth2/auth?response_type=code&client_id=abc&state=xyz")!
    static let payment = URL(string: "https://checkout.stripe.com/pay/cs_test_123")!
}

// MARK: - Mock Popup Policy Provider

/// Mock popup policy provider for testing `PopupHandler`.
///
/// Returns a configurable popup policy for all URLs.
@MainActor
final class MockPopUpPolicyProvider: PopUpPolicyProviding {
    /// The policy to return for all URLs. Defaults to `.allow`.
    var policy: PopUpPolicy = .allow

    /// URLs that have been queried.
    private(set) var queriedURLs: [URL] = []

    func popUpPolicy(for url: URL) -> PopUpPolicy {
        queriedURLs.append(url)
        return policy
    }
}

// MARK: - Mock Popup Content Probe

/// Mock content probe for testing `PopupHandler`.
///
/// Returns configurable probe results without making network requests.
final class MockPopupContentProbe: PopupContentProbing, @unchecked Sendable {
    private struct State {
        var result: PopupContentProbe.ProbeResult = .skipProbe
        var probedURLs: [URL] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// The result to return for all probes. Defaults to `.skipProbe`.
    var result: PopupContentProbe.ProbeResult {
        get { state.withLock { $0.result } }
        set { state.withLock { $0.result = newValue } }
    }

    /// URLs that have been probed.
    var probedURLs: [URL] {
        state.withLock { $0.probedURLs }
    }

    func probe(_ url: URL, timeout _: TimeInterval) async -> PopupContentProbe.ProbeResult {
        state.withLock { $0.probedURLs.append(url) }
        return result
    }
}
