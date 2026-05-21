import Foundation

/// Matches URLs against user script @match, @include, and @exclude patterns.
///
/// Supports three pattern types:
///
/// ## Chrome @match Patterns
/// Format: `scheme://host/path`
/// - `*://*.example.com/*` - any protocol, any subdomain
/// - `https://example.com/*` - exact host with https
/// - `<all_urls>` - matches all http/https URLs
///
/// ## Greasemonkey @include Wildcards
/// Format: glob-style patterns
/// - `*example.com*` - contains example.com anywhere
/// - `http://example.*/*` - any TLD
///
/// ## Regex Patterns
/// Prefix with `/` and end with `/` (optional flags)
/// - `/^https:\/\/example\.com\/api\/.*/`
/// - `/pattern/i` - case insensitive
///
/// ## Usage
///
/// ```swift
/// let matcher = ScriptURLPatternMatcher()
/// let url = URL(string: "https://github.com/user/repo")!
///
/// matcher.matches(url: url, pattern: "*://*.github.com/*") // true
/// matcher.matches(url: url, include: ["*github.com*"], exclude: []) // true
/// ```
struct ScriptURLPatternMatcher {
    // MARK: - Public API

    /// Checks if a URL matches inclusion patterns and doesn't match exclusion patterns.
    ///
    /// - Parameters:
    ///   - url: URL to check.
    ///   - include: Patterns that should match (any match = included).
    ///   - exclude: Patterns that should not match (any match = excluded).
    /// - Returns: True if URL matches at least one include and no excludes.
    func matches(url: URL, include: [String], exclude: [String]) -> Bool {
        // Must match at least one include pattern
        guard include.contains(where: { matches(url: url, pattern: $0) }) else {
            return false
        }

        // Must not match any exclude pattern
        return !exclude.contains { matches(url: url, pattern: $0) }
    }

    /// Checks if a URL matches a single pattern.
    ///
    /// Automatically detects pattern type (match, include, or regex).
    func matches(url: URL, pattern: String) -> Bool {
        // Empty pattern matches nothing
        guard !pattern.isEmpty else { return false }

        // Special <all_urls> pattern
        if pattern == "<all_urls>" {
            return matchesScheme(url: url, allowedSchemes: ["http", "https"])
        }

        // Regex pattern (starts and ends with /)
        if pattern.hasPrefix("/"), let endIndex = pattern.dropFirst().lastIndex(of: "/") {
            return matchesRegex(url: url, pattern: pattern, flagsStart: endIndex)
        }

        // Chrome @match pattern (contains ://)
        if pattern.contains("://") {
            return matchesChromePattern(url: url, pattern: pattern)
        }

        // Greasemonkey @include wildcard pattern
        return matchesGreasemonkeyPattern(url: url, pattern: pattern)
    }

    /// Checks if a script matches a URL based on its patterns.
    func matches(url: URL, script: UserScript) -> Bool {
        // Combine both @match and @include patterns
        let includePatterns = script.matchPatterns + script.includePatterns
        return matches(url: url, include: includePatterns, exclude: script.excludePatterns)
    }

    /// Filters scripts that match a given URL.
    func matchingScripts(_ scripts: [UserScript], for url: URL, enabledOnly: Bool = true) -> [UserScript] {
        scripts.filter { script in
            if enabledOnly, !script.isEnabled { return false }
            return matches(url: url, script: script)
        }
    }

    // MARK: - Chrome @match Patterns

    /// Matches Chrome extension-style @match patterns.
    ///
    /// Format: `scheme://host[:port]/path`
    /// - Scheme: `*` (http/https), `http`, `https`, `file`, etc.
    /// - Host: `*` (any), `*.domain.com` (subdomains), `domain.com` (exact)
    /// - Port: Optional, e.g., `localhost:8080`
    /// - Path: `/*` (any), `/path/*` (prefix), `/exact/path` (exact)
    private func matchesChromePattern(url: URL, pattern: String) -> Bool {
        // Parse pattern components
        guard let patternURL = parseChromePattern(pattern) else {
            return false
        }

        // Match scheme
        guard matchesScheme(url: url, patternScheme: patternURL.scheme) else {
            return false
        }

        // Match host (with optional port)
        guard matchesHostWithPort(url: url, patternHost: patternURL.host) else {
            return false
        }

        // Match path
        return matchesPath(url: url, patternPath: patternURL.path)
    }

    private func parseChromePattern(_ pattern: String) -> (scheme: String, host: String, path: String)? {
        // Split by ://
        let parts = pattern.split(separator: "://", maxSplits: 1)
        guard parts.count == 2 else { return nil }

        let scheme = String(parts[0])
        let rest = String(parts[1])

        // Split host from path (first /)
        if let slashIndex = rest.firstIndex(of: "/") {
            let host = String(rest[..<slashIndex])
            let path = String(rest[slashIndex...])
            return (scheme, host, path)
        } else {
            // No path specified, assume /*
            return (scheme, rest, "/*")
        }
    }

    private func matchesScheme(url: URL, patternScheme: String) -> Bool {
        guard let urlScheme = url.scheme?.lowercased() else { return false }
        let scheme = patternScheme.lowercased()

        if scheme == "*" {
            // Wildcard only matches http/https, not file/data/etc
            return urlScheme == "http" || urlScheme == "https"
        }

        return urlScheme == scheme
    }

    private func matchesScheme(url: URL, allowedSchemes: [String]) -> Bool {
        guard let urlScheme = url.scheme?.lowercased() else { return false }
        return allowedSchemes.contains(urlScheme)
    }

    /// Matches host with optional port support.
    ///
    /// Patterns can include ports: `localhost:8080`, `*.example.com:3000`
    private func matchesHostWithPort(url: URL, patternHost: String) -> Bool {
        // Check if pattern has a port
        if let colonIndex = patternHost.lastIndex(of: ":") {
            let hostPart = String(patternHost[..<colonIndex])
            let portPart = String(patternHost[patternHost.index(after: colonIndex)...])

            // Match host
            guard matchesHostOnly(url: url, patternHost: hostPart) else {
                return false
            }

            // Match port
            if let patternPort = Int(portPart) {
                return url.port == patternPort
            }

            return false
        }

        // No port in pattern, match host only
        return matchesHostOnly(url: url, patternHost: patternHost)
    }

    private func matchesHostOnly(url: URL, patternHost: String) -> Bool {
        guard let urlHost = url.host?.lowercased() else { return false }
        let pattern = patternHost.lowercased()

        // Wildcard * matches any host
        if pattern == "*" {
            return true
        }

        // Subdomain wildcard: *.example.com
        if pattern.hasPrefix("*.") {
            let baseDomain = String(pattern.dropFirst(2))

            // *.example.com does NOT match example.com itself (per Chrome spec)
            // but matches sub.example.com, a.b.example.com, etc.
            if urlHost == baseDomain {
                return false
            }

            return urlHost.hasSuffix(".\(baseDomain)")
        }

        // Exact match
        return urlHost == pattern
    }

    private func matchesPath(url: URL, patternPath: String) -> Bool {
        // Get URL path including query and fragment
        var urlPath = url.path
        if let query = url.query {
            urlPath += "?\(query)"
        }
        if let fragment = url.fragment {
            urlPath += "#\(fragment)"
        }

        // Empty path matches /
        if urlPath.isEmpty {
            urlPath = "/"
        }

        // Pattern /* matches everything
        if patternPath == "/*" || patternPath == "/*/" {
            return true
        }

        // Convert pattern to regex
        return matchesGlobPath(urlPath: urlPath, pattern: patternPath)
    }

    private func matchesGlobPath(urlPath: String, pattern: String) -> Bool {
        var regexPattern = NSRegularExpression.escapedPattern(for: pattern)

        // * matches anything except /
        regexPattern = regexPattern.replacingOccurrences(of: "\\*", with: "[^/]*")

        // Anchor
        regexPattern = "^" + regexPattern

        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: .caseInsensitive)
            let range = NSRange(urlPath.startIndex..., in: urlPath)
            return regex.firstMatch(in: urlPath, range: range) != nil
        } catch {
            return false
        }
    }

    // MARK: - Greasemonkey @include Wildcards

    /// Matches Greasemonkey-style @include wildcard patterns.
    ///
    /// - `*` matches any string
    /// - Patterns are matched against the full URL string
    private func matchesGreasemonkeyPattern(url: URL, pattern: String) -> Bool {
        let urlString = url.absoluteString

        // Convert GM wildcards to regex
        var regexPattern = NSRegularExpression.escapedPattern(for: pattern)

        // * matches anything
        regexPattern = regexPattern.replacingOccurrences(of: "\\*", with: ".*")

        // Anchor the pattern (implicit anchors in GM)
        regexPattern = "^" + regexPattern + "$"

        do {
            let regex = try NSRegularExpression(pattern: regexPattern, options: .caseInsensitive)
            let range = NSRange(urlString.startIndex..., in: urlString)
            return regex.firstMatch(in: urlString, range: range) != nil
        } catch {
            return false
        }
    }

    // MARK: - Regex Patterns

    /// Matches regex patterns (prefixed with /).
    ///
    /// Format: `/pattern/flags`
    /// - Pattern is the regex
    /// - Flags: `i` for case insensitive
    private func matchesRegex(url: URL, pattern: String, flagsStart: String.Index) -> Bool {
        let urlString = url.absoluteString

        // Extract regex and flags
        let regexStartIndex = pattern.index(after: pattern.startIndex)
        let regexContent = String(pattern[regexStartIndex ..< flagsStart])
        let flags = String(pattern[pattern.index(after: flagsStart)...])

        // Parse flags
        var options: NSRegularExpression.Options = []
        if flags.contains("i") {
            options.insert(.caseInsensitive)
        }

        do {
            let regex = try NSRegularExpression(pattern: regexContent, options: options)
            let range = NSRange(urlString.startIndex..., in: urlString)
            return regex.firstMatch(in: urlString, range: range) != nil
        } catch {
            // Invalid regex doesn't match
            return false
        }
    }
}
