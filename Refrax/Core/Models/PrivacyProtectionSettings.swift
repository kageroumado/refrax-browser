import Foundation
import SwiftData

/// Global privacy protection settings.
///
/// Controls URL cleaning, tracking prevention, and custom redirect rules.
/// Stored as a one-to-one relationship with ``BrowserSettings``.
///
/// ## URL Cleaning
///
/// When ``enableLinkProtection`` is true, URLs are cleaned during navigation:
/// - Tracking parameters are removed (utm_*, fbclid, etc.)
/// - AMP cache URLs are converted to canonical publisher URLs
/// - Shortened URLs are expanded to their final destination
///
/// ## Custom Rules
///
/// Users can define custom redirect rules via ``customRedirects`` and
/// app-based redirects via ``appRedirectRules``.
///
/// ## Exceptions
///
/// Domains in ``linkProtectionExceptions`` bypass all URL cleaning.
///
@Model
final class PrivacyProtectionSettings {
    // MARK: - Identity

    /// Stable identifier for sync.
    @Attribute(.preserveValueOnDeletion)
    var id: UUID = UUID()

    // MARK: - URL Cleaning

    /// Master toggle for link protection features.
    ///
    /// When disabled, all URL cleaning is skipped. Individual feature
    /// toggles are ignored.
    var enableLinkProtection: Bool = true

    /// Remove known tracking query parameters from URLs.
    ///
    /// Parameters like `utm_source`, `fbclid`, `gclid` are stripped.
    /// See ``LinkProtection/trackingParameters`` for the full list.
    var removeTrackingParameters: Bool = true

    /// Expand shortened URLs to their final destination.
    ///
    /// Supports common shorteners: bit.ly, t.co, tinyurl.com, etc.
    /// Expansion happens in an isolated session without cookies.
    var expandURLShorteners: Bool = true

    /// Timeout in seconds for URL shortener expansion.
    ///
    /// If expansion takes longer, the original URL is used.
    var shortenerExpansionTimeout: Double = 5.0

    /// Convert AMP cache URLs to canonical publisher URLs.
    ///
    /// Routes traffic directly to publishers instead of through
    /// Google's AMP cache.
    var convertAMPLinks: Bool = true

    /// User-defined tracking parameters to remove.
    ///
    /// Added to the built-in list in ``LinkProtection/trackingParameters``.
    /// Parameters are matched case-insensitively.
    var customTrackingParameters: [String] = []

    /// Domains exempt from link protection.
    ///
    /// URLs with hosts matching these domains bypass all URL cleaning.
    /// Supports exact matches only (no wildcards).
    var linkProtectionExceptions: [String] = []

    // MARK: - Custom Rules

    /// User-defined URL redirect rules.
    ///
    /// Applied in order during navigation. First matching rule wins.
    @Relationship(deleteRule: .cascade, inverse: \CustomRedirect.privacySettings)
    var customRedirects: [CustomRedirect] = []

    /// Rules for opening URLs in external applications.
    ///
    /// Applied in order. First matching rule opens the URL in the
    /// specified app and cancels navigation in Refrax.
    @Relationship(deleteRule: .cascade, inverse: \AppRedirectRule.privacySettings)
    var appRedirectRules: [AppRedirectRule] = []

    // MARK: - External URL Settings

    /// Settings for handling URLs opened from external applications.
    ///
    /// One-to-one relationship. Created lazily via ``externalURLSettings``.
    @Relationship(deleteRule: .cascade)
    private var _externalURLSettings: ExternalURLSettings?

    /// Gets or creates external URL settings.
    var externalURLSettings: ExternalURLSettings {
        if let existing = _externalURLSettings {
            return existing
        }
        let settings = ExternalURLSettings()
        _externalURLSettings = settings
        return settings
    }

    // MARK: - Initialization

    init() {}

    // MARK: - Convenience

    /// Whether any link protection feature is enabled.
    var hasActiveLinkProtection: Bool {
        enableLinkProtection && (
            removeTrackingParameters ||
                expandURLShorteners ||
                convertAMPLinks
        )
    }

    /// Checks if a domain is exempt from link protection.
    func isExempt(domain: String) -> Bool {
        let lowercased = domain.lowercased()
        return linkProtectionExceptions.contains { exception in
            lowercased == exception.lowercased() ||
                lowercased.hasSuffix(".\(exception.lowercased())")
        }
    }
}
