import AppKit
import Foundation
import WebKit

/// Provides contextual user agent strings for web navigation.
///
/// `UserAgentProvider` implements Safari-compatible user agent spoofing to ensure
/// compatibility with sites that employ browser detection (particularly Google's
/// authentication systems).
///
/// ## Strategy
///
/// Major web services (Google, Microsoft, etc.) often serve degraded experiences
/// or block functionality for non-Safari browsers on macOS. By presenting a
/// Safari-compatible user agent, we ensure users get the full web experience.
///
/// ## User Agent Tiers
///
/// 1. **Safari** (default) — Full Safari UA for maximum compatibility
/// 2. **Branded** — Safari UA with Refrax identifier for sites that track browser usage
/// 3. **Minimal** — Plain WebKit UA for legacy compatibility
///
/// ## Domain Selection
///
/// User agents are selected per-domain using ``UserAgentPolicy``:
/// - OAuth providers (Google, Microsoft, etc.) → Safari UA
/// - General browsing → Safari UA (default)
/// - Explicitly branded domains → Branded UA
///
/// ## Usage
///
/// ```swift
/// let provider = UserAgentProvider()
/// let ua = provider.userAgent(for: url)
/// preferences.userAgent = ua
/// ```
///
/// ## References
///
/// - [Safari User Agent Strings](https://developer.apple.com/documentation/safari-release-notes)
/// - [User-Agent Client Hints](https://web.dev/user-agent-client-hints/)
struct UserAgentProvider: Sendable {
    // MARK: - Cached Version Detection

    /// Cached version info, computed once at startup.
    private static let versionInfo = VersionInfo()

    /// Frozen macOS version for user agent strings.
    ///
    /// Both Safari and Chrome freeze this at `10_15_7` regardless of actual
    /// macOS version to reduce fingerprinting surface. We match this behavior.
    private static let macOSVersion = "10_15_7"

    // MARK: - Fallback Versions

    /// Fallback Safari version if detection fails.
    private static let fallbackSafariVersion = "26.3.1"

    /// Fallback WebKit version if detection fails.
    private static let fallbackWebKitVersion = "605.1.15"

    /// Cached version information computed once at startup.
    private struct VersionInfo: Sendable {
        let safariVersion: String
        let webKitVersion: String

        init() {
            self.safariVersion = Self.detectSafariVersion() ?? UserAgentProvider.fallbackSafariVersion
            self.webKitVersion = Self.detectWebKitVersion() ?? UserAgentProvider.fallbackWebKitVersion
        }

        private static func detectSafariVersion() -> String? {
            let safariPath = "/Applications/Safari.app/Contents/Info.plist"
            guard let plist = NSDictionary(contentsOfFile: safariPath),
                  let version = plist["CFBundleShortVersionString"] as? String
            else {
                return nil
            }
            return version
        }

        private static func detectWebKitVersion() -> String? {
            // Use WebKit framework version instead of creating a WKWebView
            guard let webKitBundle = Bundle(identifier: "com.apple.WebKit"),
                  let version = webKitBundle.infoDictionary?["CFBundleVersion"] as? String
            else {
                return nil
            }
            return version
        }
    }

    // MARK: - User Agent Strings

    /// Application name suffix for WebKit's user agent.
    ///
    /// When set on `WebPage.Configuration.applicationNameForUserAgent`, WebKit appends
    /// this to its default user agent. We use Safari's format to ensure compatibility.
    ///
    /// The resulting user agent will look like:
    /// `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.1 Safari/605.1.15`
    static let applicationName: String = "Version/\(versionInfo.safariVersion) Safari/\(versionInfo.webKitVersion)"

    /// Full Safari user agent string.
    ///
    /// Matches the format used by Safari on macOS:
    /// `Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.1 Safari/605.1.15`
    static let safari: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X \(macOSVersion)) " +
        "AppleWebKit/\(versionInfo.webKitVersion) (KHTML, like Gecko) " +
        "Version/\(versionInfo.safariVersion) " +
        "Safari/\(versionInfo.webKitVersion)"

    /// Safari user agent with Refrax identifier appended.
    ///
    /// Some sites track browser usage; this allows identification while
    /// maintaining Safari compatibility.
    static let branded: String = {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        return "\(safari) Refrax/\(appVersion)"
    }()

    /// Minimal WebKit user agent without Safari identifier.
    ///
    /// Used for legacy sites that only check for WebKit.
    static let minimal: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X \(macOSVersion)) " +
        "AppleWebKit/\(versionInfo.webKitVersion) (KHTML, like Gecko)"

    /// Chrome user agent for sites that require Chromium-based browsers.
    ///
    /// Used for Chrome Web Store and Firefox Add-ons which gate functionality
    /// behind Chrome/Firefox UA detection. Uses a recent stable Chrome version.
    static let chrome: String = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) " +
        "Chrome/144.0.0.0 Safari/537.36"

    // MARK: - Policy Selection

    /// Gets the appropriate user agent for a URL.
    ///
    /// Selection is based on domain matching:
    /// 1. OAuth/auth domains → Safari (ensures login compatibility)
    /// 2. Domains requiring Safari → Safari
    /// 3. All other domains → Safari (default for best compatibility)
    ///
    /// - Parameter url: The URL to select a user agent for.
    /// - Returns: The appropriate user agent string.
    func userAgent(for url: URL?) -> String {
        guard let url, let host = url.host?.lowercased() else {
            return Self.safari
        }

        let policy = UserAgentPolicy.policy(for: host)
        return userAgent(for: policy)
    }

    /// Gets the user agent string for a specific policy.
    func userAgent(for policy: UserAgentPolicy) -> String {
        switch policy {
        case .safari:
            Self.safari
        case .branded:
            Self.branded
        case .minimal:
            Self.minimal
        case .chrome:
            Self.chrome
        }
    }
}

// MARK: - User Agent Policy

/// Policy determining which user agent to use for a domain.
enum UserAgentPolicy: Sendable {
    /// Use full Safari user agent (default, maximum compatibility).
    case safari

    /// Use Safari UA with Refrax identifier.
    case branded

    /// Use minimal WebKit UA.
    case minimal

    /// Use Chrome UA for sites that gate features behind Chrome detection.
    case chrome

    /// Determines the policy for a given host.
    ///
    /// - Parameter host: The domain host (e.g., "accounts.google.com").
    /// - Returns: The appropriate policy for this domain.
    static func policy(for host: String) -> UserAgentPolicy {
        // Extension stores require Chrome UA to render properly
        if chromeRequiredDomains.contains(where: { host.hasSuffix($0) }) {
            return .chrome
        }

        // OAuth and authentication domains always get Safari UA
        if OAuthDomainRegistry.isOAuthDomain(host) {
            return .safari
        }

        // Domains known to require Safari UA
        if safariRequiredDomains.contains(where: { host.hasSuffix($0) }) {
            return .safari
        }

        // Default to Safari for best compatibility
        return .safari
    }

    /// Domains that require Chrome UA.
    ///
    /// Extension web stores detect non-Chrome browsers and hide content or
    /// block installation. Spoofing Chrome UA ensures full page rendering.
    private static let chromeRequiredDomains: Set<String> = [
        "chromewebstore.google.com",
        "addons.mozilla.org",
    ]

    /// Domains that require Safari UA for proper functionality.
    ///
    /// These are domains known to serve degraded experiences to non-Safari browsers.
    private static let safariRequiredDomains: Set<String> = [
        // Google services
        "google.com",
        "googleapis.com",
        "gstatic.com",
        "youtube.com",
        "youtu.be",
        "googlevideo.com",

        // Microsoft services
        "microsoft.com",
        "live.com",
        "office.com",
        "office365.com",
        "microsoftonline.com",
        "azure.com",
        "bing.com",

        // Apple services
        "apple.com",
        "icloud.com",

        // Social platforms
        "facebook.com",
        "instagram.com",
        "twitter.com",
        "x.com",
        "linkedin.com",

        // Other major services
        "amazon.com",
        "netflix.com",
        "spotify.com",
        "discord.com",
        "slack.com",
        "notion.so",
        "figma.com",
    ]
}
