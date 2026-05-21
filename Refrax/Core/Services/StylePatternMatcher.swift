import Foundation
import SwiftData

/// Matches URLs against user style domain and URL patterns.
///
/// Handles the various pattern types:
/// - Exact domains: "github.com" matches github.com and subdomains
/// - Wildcard domains: "*.github.com" matches any subdomain
/// - URL patterns: Glob-style path matching
///
/// ## Usage
///
/// ```swift
/// let matcher = StylePatternMatcher()
/// let style = UserStyle(...)
/// style.domainPatterns = ["github.com", "*.gitlab.com"]
///
/// matcher.matches(url: URL(string: "https://github.com/")!, style: style) // true
/// matcher.matches(url: URL(string: "https://example.com/")!, style: style) // false
/// ```
struct StylePatternMatcher {
    /// Checks if a URL matches a user style's patterns.
    ///
    /// Matching logic:
    /// 1. Global styles match any URL with a host
    /// 2. Domain patterns match the URL's host
    /// 3. URL patterns match the full URL string
    ///
    /// - Parameters:
    ///   - url: The URL to check.
    ///   - style: The user style with patterns to match against.
    /// - Returns: Whether the URL matches the style.
    func matches(url: URL, style: UserStyle) -> Bool {
        if style.isGlobal {
            return url.host != nil
        }

        let matchesDomainPattern = style.domainPatterns.contains { matchesDomain(url: url, pattern: $0) }
        let matchesURLPattern = style.urlPatterns.contains { matchesURL(url: url, pattern: $0) }

        return matchesDomainPattern || matchesURLPattern
    }

    /// Checks if a URL matches any of the given domain patterns.
    ///
    /// - Parameters:
    ///   - url: The URL to check.
    ///   - patterns: Domain patterns to match against.
    /// - Returns: Whether the URL matches any pattern.
    func matchesDomainPatterns(url: URL, patterns: [String]) -> Bool {
        patterns.contains { matchesDomain(url: url, pattern: $0) }
    }

    // MARK: - Domain Matching

    /// Matches a URL against a domain pattern.
    ///
    /// Pattern formats:
    /// - "example.com" - matches example.com and all subdomains
    /// - "*.example.com" - matches subdomains only (but also example.com for convenience)
    ///
    /// Matching is case-insensitive.
    private func matchesDomain(url: URL, pattern: String) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        let pattern = pattern.lowercased()

        if pattern.hasPrefix("*.") {
            // Wildcard: *.example.com matches sub.example.com
            let suffix = String(pattern.dropFirst(2))

            // Match the suffix domain itself
            if host == suffix {
                return true
            }

            // Match subdomains (host ends with .suffix)
            return host.hasSuffix(".\(suffix)")
        } else {
            // Exact or subdomain match
            // "github.com" matches both "github.com" and "sub.github.com"
            if host == pattern {
                return true
            }

            // Check if host is a subdomain of pattern
            // Important: "github.com" should NOT match "fakegithub.com"
            return host.hasSuffix(".\(pattern)")
        }
    }

    // MARK: - URL Pattern Matching

    /// Matches a URL against a URL pattern.
    ///
    /// Supports glob-style wildcards:
    /// - `*` matches any sequence of characters except `/`
    /// - `**` matches any sequence including `/`
    ///
    /// Examples:
    /// - "https://github.com/*/issues" matches issues pages
    /// - "https://example.com/path/**" matches all under /path/
    private func matchesURL(url: URL, pattern: String) -> Bool {
        let urlString = url.absoluteString

        // Convert glob pattern to regex
        var regexPattern = NSRegularExpression.escapedPattern(for: pattern)

        // Replace ** with placeholder, then * with [^/]*, then placeholder with .*
        regexPattern = regexPattern
            .replacingOccurrences(of: "\\*\\*", with: "<<<DOUBLESTAR>>>")
            .replacingOccurrences(of: "\\*", with: "[^/]*")
            .replacingOccurrences(of: "<<<DOUBLESTAR>>>", with: ".*")

        // Anchor the pattern
        regexPattern = "^" + regexPattern

        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: .caseInsensitive)
            let range = NSRange(urlString.startIndex..., in: urlString)
            return regex.firstMatch(in: urlString, range: range) != nil
        } catch {
            return false
        }
    }
}

// MARK: - Batch Matching

extension StylePatternMatcher {
    /// Filters styles that match a given URL.
    ///
    /// - Parameters:
    ///   - styles: Array of styles to filter.
    ///   - url: URL to match against.
    ///   - enabledOnly: If true, only returns enabled styles.
    /// - Returns: Array of matching styles.
    func matchingStyles(_ styles: [UserStyle], for url: URL, enabledOnly: Bool = true) -> [UserStyle] {
        styles.filter { style in
            if enabledOnly, !style.isEnabled { return false }
            return matches(url: url, style: style)
        }
    }
}
