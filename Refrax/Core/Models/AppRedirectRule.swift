import AppKit
import Foundation
import SwiftData

/// A rule for opening specific URLs in external applications.
///
/// App redirect rules intercept navigation and open matching URLs
/// in a different application instead.
///
/// ## Example Uses
///
/// - Open YouTube in a dedicated player app
/// - Open GitHub in a native client
/// - Open Zoom/Teams links in their respective apps
///
/// ## Pattern Matching
///
/// Domain patterns support wildcards:
/// - `youtube.com` — matches exactly
/// - `*.youtube.com` — matches any subdomain
/// - `*youtube*` — matches any domain containing "youtube"
///
/// Path patterns are optional and use the same wildcard syntax.
@Model
final class AppRedirectRule {
    /// Stable identifier for sync.
    @Attribute(.preserveValueOnDeletion)
    var id: UUID = UUID()

    /// Display name for this rule.
    var name: String

    /// Domain pattern to match.
    ///
    /// Supports `*` wildcards. Examples:
    /// - `youtube.com`
    /// - `*.github.com`
    var domainPattern: String

    /// Optional path pattern to match.
    ///
    /// If nil, matches all paths on the domain.
    /// Supports `*` wildcards. Example: `/watch*`
    var pathPattern: String?

    /// Bundle identifier of the target application.
    ///
    /// Example: `com.apple.Safari`, `com.brave.Browser`
    var targetAppBundleID: String

    /// Whether this rule is active.
    var isEnabled: Bool = true

    /// Sort order within the rule list.
    var order: Int = 0

    /// Parent settings (inverse relationship).
    var privacySettings: PrivacyProtectionSettings?

    // MARK: - Cached Regex

    /// Cached compiled regex for domain pattern.
    @Transient
    private var _cachedDomainRegex: Regex<AnyRegexOutput>?

    /// Pattern that was used to compile the cached regex.
    @Transient
    private var _cachedDomainPattern: String?

    /// Cached compiled regex for path pattern.
    @Transient
    private var _cachedPathRegex: Regex<AnyRegexOutput>?

    /// Pattern that was used to compile the cached path regex.
    @Transient
    private var _cachedPathPattern: String?

    // MARK: - Initialization

    init(
        name: String,
        domainPattern: String,
        pathPattern: String? = nil,
        targetAppBundleID: String,
        isEnabled: Bool = true,
        order: Int = 0,
    ) {
        self.name = name
        self.domainPattern = domainPattern
        self.pathPattern = pathPattern
        self.targetAppBundleID = targetAppBundleID
        self.isEnabled = isEnabled
        self.order = order
    }

    // MARK: - Matching

    /// Checks if this rule matches a URL.
    ///
    /// - Parameter url: The URL to check.
    /// - Returns: True if domain (and optionally path) match.
    func matches(_ url: URL) -> Bool {
        guard isEnabled,
              let host = url.host?.lowercased()
        else { return false }

        // Check domain pattern using cached regex (wholeMatch for anchored pattern)
        guard let domainRegex = domainRegex(for: domainPattern.lowercased()),
              host.wholeMatch(of: domainRegex) != nil
        else { return false }

        // Check path pattern if specified (wholeMatch for anchored pattern)
        if let pathPattern {
            guard let pathRegex = pathRegex(for: pathPattern),
                  url.path.wholeMatch(of: pathRegex) != nil
            else { return false }
        }

        return true
    }

    /// Opens the URL in the target application.
    ///
    /// - Parameter url: The URL to open.
    /// - Returns: True if the app was launched successfully.
    func openInTargetApp(_ url: URL) async -> Bool {
        guard let appURL = NSWorkspace.shared.urlForApplication(
            withBundleIdentifier: targetAppBundleID,
        ) else {
            Logger.warning(
                "App not found for bundle ID: \(targetAppBundleID)",
                category: Logger.navigation,
            )
            return false
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        do {
            try await NSWorkspace.shared.open(
                [url],
                withApplicationAt: appURL,
                configuration: configuration,
            )
            Logger.info(
                "Opened \(url.host ?? "URL") in \(targetAppBundleID)",
                category: Logger.navigation,
            )
            return true
        } catch {
            Logger.warning(
                "Failed to open in target app with error \(error)",
                category: Logger.navigation,
            )
            return false
        }
    }

    // MARK: - Private

    /// Gets or compiles the domain regex, caching the result.
    private func domainRegex(for pattern: String) -> Regex<AnyRegexOutput>? {
        // Return cached if pattern unchanged
        if pattern == _cachedDomainPattern, let cached = _cachedDomainRegex {
            return cached
        }

        // Compile and cache
        guard let regex = compileWildcardPattern(pattern) else {
            return nil
        }

        _cachedDomainPattern = pattern
        _cachedDomainRegex = regex
        return regex
    }

    /// Gets or compiles the path regex, caching the result.
    private func pathRegex(for pattern: String) -> Regex<AnyRegexOutput>? {
        // Return cached if pattern unchanged
        if pattern == _cachedPathPattern, let cached = _cachedPathRegex {
            return cached
        }

        // Compile and cache
        guard let regex = compileWildcardPattern(pattern) else {
            return nil
        }

        _cachedPathPattern = pattern
        _cachedPathRegex = regex
        return regex
    }

    /// Compiles a wildcard pattern to regex.
    ///
    /// The pattern is designed for use with `wholeMatch`, so no anchors are needed.
    private func compileWildcardPattern(_ pattern: String) -> Regex<AnyRegexOutput>? {
        var regexPattern = ""
        for char in pattern {
            if char == "*" {
                regexPattern += ".*"
            } else if "\\^$.|?+()[]{}".contains(char) {
                regexPattern += "\\\(char)"
            } else {
                regexPattern += String(char)
            }
        }

        return try? Regex(regexPattern).ignoresCase()
    }
}

// MARK: - Common App Bundle IDs

extension AppRedirectRule {
    /// Common application bundle identifiers.
    enum CommonApps {
        static let safari = "com.apple.Safari"
        static let chrome = "com.google.Chrome"
        static let firefox = "org.mozilla.firefox"
        static let brave = "com.brave.Browser"
        static let edge = "com.microsoft.edgemac"
        static let arc = "company.thebrowser.Browser"
        static let zoom = "us.zoom.xos"
        static let slack = "com.tinyspeck.slackmacgap"
        static let discord = "com.hnc.Discord"
        static let spotify = "com.spotify.client"
        static let iina = "com.colliderli.iina"
    }
}
