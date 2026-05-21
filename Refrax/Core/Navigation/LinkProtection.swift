import Foundation

// MARK: - Link Protection

/// Removes tracking parameters and converts AMP links to canonical URLs.
///
/// `LinkProtection` implements privacy-preserving URL transformations based on
/// community-maintained blocklists and standard URL patterns.
///
/// ## Tracking Parameter Removal
///
/// Many websites append tracking parameters to URLs for analytics and attribution.
/// These parameters don't affect page content but leak user behavior across sites.
/// Common examples include:
///
/// - `utm_*` — Google Analytics campaign tracking
/// - `fbclid` — Facebook click identifier
/// - `gclid` — Google Ads click identifier
/// - `mc_eid` — Mailchimp email campaign tracking
///
/// Reference: [EFF's Privacy Badger](https://privacybadger.org/) and
/// [AdGuard Tracking Parameters Filter](https://github.com/nickeltech/nickeltracker)
///
/// ## AMP Link Conversion
///
/// [AMP (Accelerated Mobile Pages)](https://amp.dev/) serves cached copies of
/// web pages through Google's CDN. While faster, this:
///
/// - Routes traffic through Google's servers
/// - Breaks the direct relationship between users and publishers
/// - Often provides a degraded experience on desktop
///
/// This handler detects AMP URLs and extracts the canonical destination.
///
/// ## Usage
///
/// ```swift
/// if let cleanURL = LinkProtection.cleanURL(from: trackedURL) {
///     // Use cleanURL instead of trackedURL
/// }
/// ```
enum LinkProtection {
    // MARK: - Tracking Parameters

    /// Known tracking query parameters to remove.
    ///
    /// Based on community blocklists. Parameters are matched case-insensitively.
    /// Wildcards like `utm_*` are expanded to specific known variants.
    static let trackingParameters: Set<String> = [
        // Google Analytics (utm_* family)
        "utm_source",
        "utm_medium",
        "utm_campaign",
        "utm_term",
        "utm_content",
        "utm_id",
        "utm_source_platform",
        "utm_creative_format",
        "utm_marketing_tactic",

        // Facebook
        "fbclid",
        "fb_action_ids",
        "fb_action_types",
        "fb_source",
        "fb_ref",

        // Google Ads
        "gclid",
        "gclsrc",
        "dclid",
        "gbraid",
        "wbraid",

        // Microsoft/Bing
        "msclkid",

        // Twitter/X
        "twclid",

        // TikTok
        "ttclid",

        // Mailchimp
        "mc_eid",
        "mc_cid",

        // HubSpot
        "hsa_acc",
        "hsa_cam",
        "hsa_grp",
        "hsa_ad",
        "hsa_src",
        "hsa_tgt",
        "hsa_kw",
        "hsa_mt",
        "hsa_net",
        "hsa_ver",

        // Adobe/Omniture
        "s_kwcid",
        "cid",
        "ef_id",

        // Yahoo
        "yclid",

        // Other common trackers
        "igshid", // Instagram
        "si", // Spotify
        "ref", // Generic referrer
        "ref_",
        "_ga", // Google Analytics client ID
        "_gl", // Google Linker
        "oly_enc_id", // Omeda
        "oly_anon_id",
        "vero_id", // Vero
        "vero_conv",
        "wickedid", // Wicked Reports
        "wickedsource",
        "sscid", // ShareASale
        "rb_clickid", // Rakuten
        "irclickid", // Impact Radius
        "trk_contact", // Listrak
        "trk_msg",
        "trk_module",
        "trk_sid",
        "mkt_tok", // Marketo
        "elqTrackId", // Eloqua
        "li_fat_id", // LinkedIn
        "li_oatml",
        "cvid", // Bing
        "ncid", // CNET
        "partner", // Generic
        "campaign",
        "feature", // YouTube (sometimes tracking)
    ]

    // MARK: - AMP Patterns

    /// Regular expression patterns for detecting AMP URLs.
    ///
    /// AMP pages are served from various CDN domains and URL patterns:
    /// - `https://www.google.com/amp/s/example.com/article`
    /// - `https://example-com.cdn.ampproject.org/v/s/example.com/article`
    /// - `https://example.com/amp/article` (publisher-hosted)
    private static let ampPatterns: [(host: String, pathPrefix: String)] = [
        ("google.com", "/amp/s/"),
        ("google.com", "/amp/"),
        ("ampproject.org", "/v/s/"),
        ("ampproject.org", "/v/"),
        ("ampproject.org", "/c/s/"),
        ("ampproject.org", "/c/"),
        ("bing.com", "/amp/s/"),
    ]

    /// Path suffixes that indicate AMP versions of pages.
    private static let ampPathSuffixes: [String] = [
        "/amp",
        "/amp/",
        ".amp",
        ".amp.html",
    ]

    /// Query parameters that indicate AMP versions.
    private static let ampQueryParameters: Set<String> = [
        "amp",
        "amp_js_v",
        "usqp",
    ]

    // MARK: - Public API

    /// Cleans a URL by removing tracking parameters and converting AMP links.
    ///
    /// Applies all link protection transformations in order:
    /// 1. AMP to canonical conversion (if applicable)
    /// 2. Tracking parameter removal
    ///
    /// - Parameter url: The URL to clean.
    /// - Returns: The cleaned URL, or `nil` if the URL couldn't be processed
    ///   or no changes were needed.
    static func cleanURL(from url: URL) -> URL? {
        cleanURL(from: url, removeTracking: true, convertAMP: true)
    }

    /// Cleans a URL with configurable transformations.
    ///
    /// Applies selected link protection transformations:
    /// 1. AMP to canonical conversion (if `convertAMP` is true)
    /// 2. Tracking parameter removal (if `removeTracking` is true)
    ///
    /// - Parameters:
    ///   - url: The URL to clean.
    ///   - removeTracking: Whether to remove tracking query parameters.
    ///   - convertAMP: Whether to convert AMP URLs to canonical form.
    /// - Returns: The cleaned URL, or `nil` if the URL couldn't be processed
    ///   or no changes were needed.
    static func cleanURL(from url: URL, removeTracking: Bool, convertAMP: Bool) -> URL? {
        var workingURL = url

        // Step 1: Convert AMP to canonical
        if convertAMP, let canonicalURL = extractCanonicalFromAMP(url) {
            workingURL = canonicalURL
        }

        // Step 2: Remove tracking parameters
        if removeTracking, let cleanedURL = removeTrackingParameters(from: workingURL) {
            workingURL = cleanedURL
        }

        // Only return if we made changes
        return workingURL != url ? workingURL : nil
    }

    /// Removes known tracking query parameters from a URL.
    ///
    /// Parameters are matched case-insensitively. The URL structure is
    /// preserved except for the removed parameters.
    ///
    /// - Parameter url: The URL to clean.
    /// - Returns: The URL with tracking parameters removed, or `nil` if
    ///   no parameters were removed or the URL couldn't be processed.
    static func removeTrackingParameters(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let queryItems = components.queryItems,
              !queryItems.isEmpty
        else {
            return nil
        }

        let filteredItems = queryItems.filter { item in
            !trackingParameters.contains(item.name.lowercased())
        }

        // No parameters removed
        guard filteredItems.count != queryItems.count else {
            return nil
        }

        // If all parameters were tracking, remove the query entirely
        components.queryItems = filteredItems.isEmpty ? nil : filteredItems

        return components.url
    }

    /// Extracts the canonical URL from an AMP cache URL.
    ///
    /// Detects various AMP URL formats and extracts the original publisher URL:
    ///
    /// ```
    /// Input:  https://www.google.com/amp/s/example.com/article
    /// Output: https://example.com/article
    ///
    /// Input:  https://example-com.cdn.ampproject.org/v/s/example.com/article
    /// Output: https://example.com/article
    /// ```
    ///
    /// - Parameter url: The potential AMP URL to convert.
    /// - Returns: The canonical URL if this was an AMP URL, otherwise `nil`.
    static func extractCanonicalFromAMP(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }

        // Check CDN-hosted AMP patterns
        for pattern in ampPatterns {
            if host.contains(pattern.host) {
                return extractFromCDNPattern(url, pathPrefix: pattern.pathPrefix)
            }
        }

        // Check publisher-hosted AMP patterns (path-based)
        return extractFromPublisherAMP(url)
    }

    // MARK: - Private Helpers

    /// Extracts canonical URL from CDN-hosted AMP (Google AMP Cache, ampproject.org).
    private static func extractFromCDNPattern(_ url: URL, pathPrefix: String) -> URL? {
        let path = url.path

        guard path.hasPrefix(pathPrefix) else { return nil }

        // Extract the embedded URL from the path
        let embeddedPath = String(path.dropFirst(pathPrefix.count))

        // The embedded URL might be URL-encoded
        let decodedPath = embeddedPath.removingPercentEncoding ?? embeddedPath

        // Reconstruct the canonical URL
        // Path format: example.com/article or s/example.com/article
        var canonicalPath = decodedPath
        if canonicalPath.hasPrefix("s/") {
            canonicalPath = String(canonicalPath.dropFirst(2))
        }

        // Preserve query string from original if present
        var canonicalURLString = "https://\(canonicalPath)"
        if let query = url.query {
            canonicalURLString += "?\(query)"
        }

        guard let canonicalURL = URL(string: canonicalURLString) else {
            return nil
        }

        // Clean tracking params from the extracted URL
        return removeTrackingParameters(from: canonicalURL) ?? canonicalURL
    }

    /// Extracts canonical URL from publisher-hosted AMP pages.
    private static func extractFromPublisherAMP(_ url: URL) -> URL? {
        var path = url.path

        // Check for AMP path suffixes
        for suffix in ampPathSuffixes {
            if path.hasSuffix(suffix) {
                path = String(path.dropLast(suffix.count))
                if path.isEmpty { path = "/" }

                var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
                components?.path = path

                // Remove AMP-specific query parameters
                if var items = components?.queryItems {
                    items.removeAll { ampQueryParameters.contains($0.name.lowercased()) }
                    components?.queryItems = items.isEmpty ? nil : items
                }

                return components?.url
            }
        }

        // Check for /amp/ in path (e.g., example.com/amp/article)
        if let ampRange = path.range(of: "/amp/", options: .caseInsensitive) {
            let cleanPath = path.replacingCharacters(in: ampRange, with: "/")

            var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
            components?.path = cleanPath

            return components?.url
        }

        return nil
    }
}

// MARK: - URL Extensions

extension URL {
    /// Returns a copy of this URL with tracking parameters removed.
    ///
    /// Convenience method that applies ``LinkProtection/removeTrackingParameters(from:)``.
    ///
    /// - Returns: The cleaned URL, or `self` if no changes were needed.
    func removingTrackingParameters() -> URL {
        LinkProtection.removeTrackingParameters(from: self) ?? self
    }

    /// Whether this URL appears to be an AMP cache URL.
    ///
    /// Checks for known AMP CDN hosts and URL patterns.
    var isAMPURL: Bool {
        guard let host = host?.lowercased() else { return false }

        // CDN patterns
        if host.contains("ampproject.org") { return true }
        if host.contains("google.com"), path.hasPrefix("/amp") { return true }
        if host.contains("bing.com"), path.hasPrefix("/amp") { return true }

        // Publisher patterns
        let ampSuffixes = ["/amp", "/amp/", ".amp", ".amp.html"]
        return ampSuffixes.contains { path.hasSuffix($0) } || path.contains("/amp/")
    }

    /// The canonical URL if this is an AMP URL, otherwise `self`.
    var canonicalURL: URL {
        LinkProtection.extractCanonicalFromAMP(self) ?? self
    }
}
