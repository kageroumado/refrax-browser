import Foundation
import os

/// Utility for matching URL patterns with wildcard support.
///
/// Used by routing rules to match domain and path patterns.
///
/// ## Wildcard Syntax
///
/// - `*` matches any sequence of characters (including empty)
/// - Matching is case-insensitive
///
/// ## Examples
///
/// ```swift
/// // Domain matching
/// PatternMatcher.matchesWildcard("github.com", pattern: "github.com") // true
/// PatternMatcher.matchesWildcard("api.github.com", pattern: "*.github.com") // true
/// PatternMatcher.matchesWildcard("github.com", pattern: "*.github.com") // false
///
/// // Path matching
/// PatternMatcher.matchesWildcard("/user/repo/issues", pattern: "*/issues") // true
/// PatternMatcher.matchesWildcard("/settings", pattern: "*/issues") // false
/// ```
/// Wrapper to make Regex Sendable since we manage thread-safety via OSAllocatedUnfairLock.
private nonisolated struct SendableRegex: @unchecked Sendable {
    let regex: Regex<AnyRegexOutput>
}

nonisolated enum PatternMatcher: Sendable {
    /// Thread-safe cache for compiled regex patterns using OSAllocatedUnfairLock.
    private static let cache = OSAllocatedUnfairLock(
        initialState: [String: SendableRegex](),
    )

    /// Matches a string against a wildcard pattern.
    ///
    /// - Parameters:
    ///   - string: The string to test.
    ///   - pattern: The pattern with optional wildcards (`*`).
    /// - Returns: `true` if the string matches the pattern.
    static func matchesWildcard(_ string: String, pattern: String) -> Bool {
        let regex = getOrCreateRegex(for: pattern)
        return (try? regex.wholeMatch(in: string.lowercased())) != nil
    }

    /// Gets or creates a compiled regex for the given wildcard pattern.
    private static func getOrCreateRegex(for pattern: String) -> Regex<AnyRegexOutput> {
        let lowercasePattern = pattern.lowercased()

        let wrapper: SendableRegex = cache.withLock { regexCache in
            if let cached = regexCache[lowercasePattern] {
                return cached
            }

            let regex = compileWildcardPattern(lowercasePattern)
            let wrapper = SendableRegex(regex: regex)
            regexCache[lowercasePattern] = wrapper
            return wrapper
        }
        return wrapper.regex
    }

    /// Characters that need escaping in regex patterns.
    private static let regexSpecialChars: Set<Character> = [
        ".", "?", "+", "[", "]", "(", ")", "{", "}", "^", "$", "|", "\\",
    ]

    /// Compiles a wildcard pattern to a regex.
    ///
    /// Escapes all regex special characters except `*`, which becomes `.*`.
    private static func compileWildcardPattern(_ pattern: String) -> Regex<AnyRegexOutput> {
        var regexPattern = ""
        regexPattern.reserveCapacity(pattern.count * 2)

        for char in pattern {
            if char == "*" {
                regexPattern += ".*"
            } else if regexSpecialChars.contains(char) {
                regexPattern += "\\\(char)"
            } else {
                regexPattern.append(char)
            }
        }

        // Use force try since we control the pattern construction
        // swiftlint:disable:next force_try
        return try! Regex(regexPattern)
    }

    /// Clears the regex cache.
    ///
    /// Call this when memory pressure is detected or patterns are updated.
    static func clearCache() {
        cache.withLock { regexCache in
            regexCache.removeAll()
        }
    }
}
