import Foundation

/// Context information for evaluating routing rules.
///
/// Captures all the information available at navigation time that can be used
/// to match routing rule conditions.
///
/// ## Usage
///
/// ```swift
/// let context = NavigationContext(
///     url: navigatingURL,
///     referrer: sourcePage.url,
///     currentSpaceID: windowState.activeSpaceID,
///     sourceAppBundleID: nil, // Internal navigation
///     timestamp: Date()
/// )
///
/// for rule in rules {
///     if rule.matches(context) {
///         return rule.action
///     }
/// }
/// ```
struct NavigationContext: Sendable, Equatable {
    /// The URL being navigated to.
    let url: URL

    /// The URL of the page that initiated the navigation (if any).
    let referrer: URL?

    /// The ID of the space where the navigation originated.
    let currentSpaceID: UUID?

    /// The bundle ID of the external app that opened this URL (if any).
    ///
    /// Only set for URLs opened via the URL scheme from other applications.
    /// Examples: "com.apple.mail", "com.tinyspeck.slackmacgap"
    let sourceAppBundleID: String?

    /// When the navigation occurred.
    ///
    /// Used for time-based conditions.
    let timestamp: Date

    /// Creates a navigation context.
    ///
    /// - Parameters:
    ///   - url: The URL being navigated to.
    ///   - referrer: The URL of the referring page, if any.
    ///   - currentSpaceID: The ID of the current space.
    ///   - sourceAppBundleID: The bundle ID of the external app that opened this URL.
    ///   - timestamp: When the navigation occurred.
    init(
        url: URL,
        referrer: URL? = nil,
        currentSpaceID: UUID? = nil,
        sourceAppBundleID: String? = nil,
        timestamp: Date = Date(),
    ) {
        self.url = url
        self.referrer = referrer
        self.currentSpaceID = currentSpaceID
        self.sourceAppBundleID = sourceAppBundleID
        self.timestamp = timestamp
    }
}

// MARK: - Debug Description

extension NavigationContext: CustomDebugStringConvertible {
    var debugDescription: String {
        var parts = ["NavigationContext("]
        parts.append("  url: \(url.absoluteString)")
        if let referrer {
            parts.append("  referrer: \(referrer.absoluteString)")
        }
        if let spaceID = currentSpaceID {
            parts.append("  currentSpaceID: \(spaceID.uuidString.prefix(8))...")
        }
        if let appID = sourceAppBundleID {
            parts.append("  sourceApp: \(appID)")
        }
        parts.append("  timestamp: \(timestamp)")
        parts.append(")")
        return parts.joined(separator: "\n")
    }
}
