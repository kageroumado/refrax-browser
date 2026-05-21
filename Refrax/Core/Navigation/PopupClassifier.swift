import WebKit

/// Classifies popup window requests to determine their relationship to the opener.
///
/// Popups are classified as either **linked** (tightly coupled to opener, like OAuth/payment flows)
/// or **independent** (general new windows). This classification determines how the popup
/// is displayed in the tab UI.
///
/// ## Classification Heuristics
///
/// A popup is considered **linked** if any of these conditions are met:
/// - The popup URL is `about:blank` (dynamically populated by opener)
/// - Same origin as opener (same host)
/// - URL path contains authentication/payment patterns (`/auth`, `/oauth`, `/3ds`, etc.)
/// - Target domain is a known OAuth or payment provider
///
/// ## Usage
///
/// ```swift
/// let request = PopupRequest(
///     openerURL: currentPage.url,
///     popupURL: navigationAction.request.url,
///     windowFeatures: windowFeatures
/// )
/// let relationship = PopupClassifier.classify(request)
/// ```
enum PopupClassifier {
    /// Classifies a popup request to determine its relationship to the opener.
    ///
    /// - Parameter request: The popup request containing opener and popup details.
    /// - Returns: The classified relationship type.
    static func classify(_ request: PopupRequest) -> PopupRelationship {
        // about:blank popups are always linked - they're dynamically populated
        if request.popupURL == .blank {
            return .linked
        }

        guard let openerHost = request.openerURL.host?.lowercased(),
              let popupHost = request.popupURL.host?.lowercased() else {
            return .independent
        }

        // Same origin is linked
        if openerHost == popupHost {
            return .linked
        }

        // Check for OAuth/payment URL patterns
        if isAuthenticationFlow(request.popupURL) {
            return .linked
        }

        // Check known OAuth/payment provider domains
        if OAuthDomainRegistry.isOAuthDomain(popupHost) ||
            OAuthDomainRegistry.isPaymentDomain(popupHost) {
            return .linked
        }

        return .independent
    }

    /// Checks if a URL appears to be part of an authentication or payment flow.
    private static func isAuthenticationFlow(_ url: URL) -> Bool {
        let path = url.path.lowercased()
        let authPatterns = [
            "/auth",
            "/oauth",
            "/login",
            "/signin",
            "/sign-in",
            "/sso",
            "/3ds",
            "/3d-secure",
            "/checkout",
            "/verify",
            "/authorize",
            "/connect/authorize",
            "/callback",
        ]

        return authPatterns.contains { path.contains($0) }
    }
}

// MARK: - Supporting Types

/// Describes the relationship between a popup and its opener window.
enum PopupRelationship {
    /// Tightly coupled popup (OAuth, 3D Secure, payment flows).
    ///
    /// Linked popups are created in the same tab group as their opener
    /// and maintain a visual relationship in the UI.
    case linked

    /// General popup with no special relationship to opener.
    ///
    /// Independent popups are created as regular new tabs.
    case independent
}

/// Encapsulates information about a popup window request.
struct PopupRequest {
    /// URL of the page that initiated the popup.
    let openerURL: URL

    /// Target URL for the popup window.
    let popupURL: URL

    /// Window features specified in the `window.open()` call.
    let windowFeatures: WKWindowFeatures

    /// The ID of the opener's TabPage, used for tracking the relationship.
    let openerTabPageID: UUID?

    /// Creates a popup request.
    ///
    /// - Parameters:
    ///   - openerURL: URL of the opener page.
    ///   - popupURL: Target URL for the popup.
    ///   - windowFeatures: WebKit window features from the navigation action.
    ///   - openerTabPageID: Optional ID of the opener's TabPage.
    init(
        openerURL: URL,
        popupURL: URL,
        windowFeatures: WKWindowFeatures,
        openerTabPageID: UUID? = nil,
    ) {
        self.openerURL = openerURL
        self.popupURL = popupURL
        self.windowFeatures = windowFeatures
        self.openerTabPageID = openerTabPageID
    }
}
