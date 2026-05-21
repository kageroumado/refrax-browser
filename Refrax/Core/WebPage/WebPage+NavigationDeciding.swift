import AppKit
import Foundation
import SwiftUI
import WebKit

// MARK: - EventModifiers Conversion

extension SwiftUI.EventModifiers {
    /// Creates `EventModifiers` from `NSEvent.ModifierFlags`.
    init(_ wrapped: NSEvent.ModifierFlags) {
        var result: SwiftUI.EventModifiers = []
        if wrapped.contains(.capsLock) { result.insert(.capsLock) }
        if wrapped.contains(.command) { result.insert(.command) }
        if wrapped.contains(.control) { result.insert(.control) }
        if wrapped.contains(.numericPad) { result.insert(.numericPad) }
        if wrapped.contains(.option) { result.insert(.option) }
        if wrapped.contains(.shift) { result.insert(.shift) }
        self = result
    }
}

// MARK: - Navigation Action

extension WebPage {
    /// Information about an action that causes navigation to occur.
    ///
    /// Mirrors WebKit's `WebPage.NavigationAction` API while wrapping `WKNavigationAction`.
    struct NavigationAction {
        /// The underlying WebKit navigation action.
        let wrapped: WKNavigationAction

        /// Redirect chain context for this navigation.
        let redirectChain: RedirectChain?

        init(_ wrapped: WKNavigationAction, redirectChain: RedirectChain? = nil) {
            self.wrapped = wrapped
            self.redirectChain = redirectChain
        }

        /// The frame that requested the navigation.
        var source: FrameInfo {
            FrameInfo(wrapped.sourceFrame)
        }

        /// The frame in which to display the new content.
        ///
        /// `nil` if the navigation requests a new window/tab.
        var target: FrameInfo? {
            wrapped.targetFrame.map(FrameInfo.init)
        }

        /// The type of action that triggered the navigation.
        var navigationType: WKNavigationType {
            wrapped.navigationType
        }

        /// The URL request associated with the navigation.
        var request: URLRequest {
            wrapped.request
        }

        /// The requested URL.
        var url: URL? {
            wrapped.request.url
        }

        /// Whether the web content indicated this should be downloaded.
        var shouldPerformDownload: Bool {
            wrapped.shouldPerformDownload
        }

        /// The mouse button that caused the navigation.
        var buttonNumber: Int {
            wrapped.buttonNumber
        }

        /// The keyboard modifier flags active during navigation.
        var modifierFlags: SwiftUI.EventModifiers {
            SwiftUI.EventModifiers(wrapped.modifierFlags)
        }

        /// Whether this is a redirect from a content rule list.
        var isContentRuleListRedirect: Bool {
            wrapped.isContentRuleListRedirect
        }
    }
}

// MARK: - Navigation Action Conveniences

/// Convenience accessors derived from `WKNavigationAction`.
///
/// Design rationale:
/// - Keep a single `WebPage.NavigationAction` type to avoid wrapper churn.
/// - Provide derived behaviors (e.g., user-initiated detection) without
///   renaming core WebKit properties like `source` and `target`.

extension WebPage.NavigationAction {
    /// Whether this navigation targets the main frame.
    ///
    /// Uses the wrapped `target` frame directly to avoid duplicating
    /// WebKit's naming with new shim property names.
    var isMainFrame: Bool {
        target?.isMainFrame ?? false
    }

    /// Whether this navigation requests a new window/tab.
    ///
    /// `target == nil` indicates `target="_blank"` or `window.open()` calls.
    var isNewWindowRequest: Bool {
        target == nil
    }

    /// Whether this was a middle mouse button click or auxiliary button click.
    ///
    /// Middle-click on links conventionally opens in a new background tab.
    /// Per NSEvent.buttonNumber, button 2 is the standard middle button.
    /// However, some third-party mice (Logitech, Razer, etc.) may report
    /// scroll wheel clicks as button 4+ depending on driver configuration.
    ///
    /// We treat any button >= 2 as a "new tab" trigger since:
    /// - Button 2: Standard middle click (scroll wheel)
    /// - Buttons 3+: Side buttons (also commonly used for new tab/back/forward)
    ///
    /// See: [Mozilla Bug 1615213](https://bugzilla.mozilla.org/show_bug.cgi?id=1615213)
    /// for discussion of cross-platform mouse button detection issues.
    var isMiddleClick: Bool {
        buttonNumber >= 2
    }

    /// Whether the Command key was held during navigation.
    ///
    /// Cmd+click on links conventionally opens in a new tab.
    var isCommandClick: Bool {
        modifierFlags.contains(.command)
    }

    /// Whether Shift was held during navigation.
    ///
    /// Cmd+Shift+click conventionally opens in a new tab and switches to it.
    var isShiftHeld: Bool {
        modifierFlags.contains(.shift)
    }

    /// Whether this navigation was likely triggered by a user gesture.
    ///
    /// Combines navigation type analysis with modifier key detection.
    /// Link activations, form submissions, and modifier-key navigations
    /// are considered user-initiated.
    ///
    /// Per [User Activation](https://html.spec.whatwg.org/multipage/interaction.html#tracking-user-activation),
    /// user-initiated navigations have elevated trust for popup handling.
    var isUserInitiated: Bool {
        switch navigationType {
        case .linkActivated, .formSubmitted, .formResubmitted, .backForward, .reload:
            return true
        case .other:
            return false
        @unknown default:
            return false
        }
    }

    /// Whether this is a form submission.
    var isFormSubmission: Bool {
        navigationType == .formSubmitted || navigationType == .formResubmitted
    }

    /// Whether this is a link activation (click).
    var isLinkActivated: Bool {
        navigationType == .linkActivated
    }

    /// Whether this is a back/forward navigation.
    var isBackForward: Bool {
        navigationType == .backForward
    }

    /// Whether this is a reload.
    var isReload: Bool {
        navigationType == .reload
    }

    /// Whether this navigation should open in a new tab based on user input.
    ///
    /// Returns `true` for:
    /// - Middle mouse button clicks
    /// - Command+click (macOS convention)
    /// - Links with `target="_blank"` (new window requests)
    ///
    /// This does NOT include `shouldPerformDownload` since downloads
    /// are handled differently.
    var shouldOpenInNewTab: Bool {
        isMiddleClick || isCommandClick || isNewWindowRequest
    }

    /// Whether the new tab should be activated (switched to).
    ///
    /// Activation logic:
    /// - **Cmd+Shift+click** → activate new tab
    /// - **Middle-click or Cmd+click** (without Shift) → background tab
    /// - **New window requests** (popup links like `target="_blank"`) → activate new tab
    ///
    /// The rationale is that when a user explicitly clicks a link that opens in
    /// a new window (popup), they expect to be taken to that content. In contrast,
    /// middle-click and Cmd+click are explicit "open in background" gestures.
    var shouldActivateNewTab: Bool {
        if isCommandClick && isShiftHeld {
            return true
        }

        if isMiddleClick || isCommandClick {
            return false
        }

        if isNewWindowRequest {
            return true
        }

        return false
    }
}

// MARK: - Navigation Response

extension WebPage {
    /// Information about the response to a navigation request.
    ///
    /// Mirrors WebKit's `WebPage.NavigationResponse` API while wrapping `WKNavigationResponse`.
    struct NavigationResponse {
        /// The underlying WebKit navigation response.
        let wrapped: WKNavigationResponse

        init(_ wrapped: WKNavigationResponse) {
            self.wrapped = wrapped
        }

        /// Whether this response is for the main frame.
        var isForMainFrame: Bool {
            wrapped.isForMainFrame
        }

        /// The URL response.
        var response: URLResponse {
            wrapped.response
        }

        /// Whether WebKit can render this MIME type natively.
        var canShowMimeType: Bool {
            wrapped.canShowMIMEType
        }
    }
}

// MARK: - Frame Info

extension WebPage {
    /// Information about a frame on a webpage.
    ///
    /// Mirrors WebKit's `WebPage.FrameInfo` API while wrapping `WKFrameInfo`.
    struct FrameInfo {
        /// The underlying WebKit frame info.
        let wrapped: WKFrameInfo

        init(_ wrapped: WKFrameInfo) {
            self.wrapped = wrapped
        }

        /// Whether this is the main frame.
        var isMainFrame: Bool {
            wrapped.isMainFrame
        }

        /// The frame's current request.
        var request: URLRequest {
            wrapped.request
        }

        /// The frame's security origin.
        var securityOrigin: WKSecurityOrigin {
            wrapped.securityOrigin
        }
    }
}

// MARK: - Navigation Deciding Protocol

extension WebPage {
    /// Allows providing custom behavior to handle navigation changes and to coordinate these changes for the web page's main page.
    ///
    /// For example, you might use these methods to restrict navigation from specific links within your content.
    ///
    /// ## Example
    ///
    /// ```swift
    /// struct MyNavigationDecider: WebPage.NavigationDeciding {
    ///     mutating func decidePolicy(
    ///         for action: WebPage.NavigationAction,
    ///         preferences: inout WebPage.NavigationPreferences
    ///     ) async -> WKNavigationActionPolicy {
    ///         // Block certain schemes
    ///         if action.request.url?.scheme == "javascript" {
    ///             return .cancel
    ///         }
    ///         return .allow
    ///     }
    /// }
    /// ```
    protocol NavigationDeciding {
        /// Determines permission to navigate to new content based on the specified preferences and action information.
        ///
        /// The web page calls this method after the interaction occurs but before it attempts to load any content.
        ///
        /// - Parameters:
        ///   - action: Details about the action that triggered the navigation request.
        ///   - preferences: The preferences to use when displaying the new webpage.
        /// - Returns: The navigation policy for the action.
        mutating func decidePolicy(
            for action: WebPage.NavigationAction,
            preferences: inout WebPage.NavigationPreferences,
        ) async -> WKNavigationActionPolicy

        /// Determines permission to navigate to new content after the response to the navigation request is known.
        ///
        /// - Parameter response: Descriptive information about the navigation response.
        /// - Returns: The navigation policy for the response.
        mutating func decidePolicy(
            for response: WebPage.NavigationResponse,
        ) async -> WKNavigationResponsePolicy

        /// Determines the response to an authentication challenge.
        ///
        /// - Parameter challenge: The authentication challenge.
        /// - Returns: The option to use to handle the challenge, and the credential to use for authentication when the disposition is ``URLSession/AuthChallengeDisposition/useCredential``.
        mutating func decideAuthenticationChallengeDisposition(
            for challenge: URLAuthenticationChallenge,
        ) async -> (URLSession.AuthChallengeDisposition, URLCredential?)
    }
}

// MARK: - Default Implementation

extension WebPage.NavigationDeciding {
    /// Default implementation: allows all navigation actions.
    func decidePolicy(
        for _: WebPage.NavigationAction,
        preferences _: inout WebPage.NavigationPreferences,
    ) async -> WKNavigationActionPolicy {
        .allow
    }

    /// Default implementation: allows all navigation responses.
    func decidePolicy(
        for _: WebPage.NavigationResponse,
    ) async -> WKNavigationResponsePolicy {
        .allow
    }

    /// Default implementation: performs default handling.
    func decideAuthenticationChallengeDisposition(
        for _: URLAuthenticationChallenge,
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        (.performDefaultHandling, nil)
    }
}
