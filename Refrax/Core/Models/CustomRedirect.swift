import Foundation
import SwiftData

/// A user-defined URL redirect rule with wildcard pattern matching.
///
/// Custom redirects transform URLs during navigation. Common uses:
/// - Replace Twitter with Nitter: `twitter.com/*` → `nitter.net/$1`
/// - Replace Medium with Scribe: `*.medium.com/*` → `scribe.rip/$1`
/// - Remove mobile subdomains: `m.example.com/*` → `example.com/$1`
///
/// ## Pattern Syntax
///
/// The ``sourcePattern`` uses simple wildcard matching:
/// - `*` matches any sequence of characters (captured as `$1`, `$2`, etc.)
/// - All other characters are matched literally
/// - Matching is case-insensitive for the domain portion
///
/// ## Examples
///
/// | Source Pattern | Destination | Input URL | Output URL |
/// |----------------|-------------|-----------|------------|
/// | `twitter.com/*` | `nitter.net/$1` | `twitter.com/user/status/123` | `nitter.net/user/status/123` |
/// | `*.reddit.com/*` | `teddit.net/$2` | `old.reddit.com/r/swift` | `teddit.net/r/swift` |
/// | `youtube.com/watch*` | `yewtu.be/watch$1` | `youtube.com/watch?v=abc` | `yewtu.be/watch?v=abc` |
@Model
final class CustomRedirect {
    /// Stable identifier for sync.
    @Attribute(.preserveValueOnDeletion)
    var id: UUID = UUID()

    /// Display name for this rule.
    var name: String

    /// Source URL pattern with wildcards.
    ///
    /// Use `*` for wildcards that capture groups. The domain portion
    /// is matched case-insensitively.
    var sourcePattern: String

    /// Destination URL template.
    ///
    /// Use `$1`, `$2`, etc. to insert captured wildcard groups.
    /// The template should include the scheme if different from source.
    var destinationTemplate: String

    /// Whether this rule is active.
    var isEnabled: Bool = true

    /// Sort order within the rule list.
    ///
    /// Lower values are evaluated first.
    var order: Int = 0

    /// Parent settings (inverse relationship).
    var privacySettings: PrivacyProtectionSettings?

    /// Cached compiled regex to avoid recompilation on every URL check.
    @Transient
    private var cachedRegex: (regex: Regex<AnyRegexOutput>, captureCount: Int)?

    /// The pattern that was used to create the cached regex.
    @Transient
    private var cachedPatternSource: String?

    // MARK: - Initialization

    init(
        name: String,
        sourcePattern: String,
        destinationTemplate: String,
        isEnabled: Bool = true,
        order: Int = 0,
    ) {
        self.name = name
        self.sourcePattern = sourcePattern
        self.destinationTemplate = destinationTemplate
        self.isEnabled = isEnabled
        self.order = order
    }

    // MARK: - Pattern Matching

    /// Applies this rule to a URL.
    ///
    /// - Parameter url: The URL to transform.
    /// - Returns: The transformed URL if the pattern matches and all required capture groups
    ///   are present in the destination template, `nil` otherwise.
    func apply(to url: URL) -> URL? {
        guard isEnabled else { return nil }

        let urlString = url.absoluteString

        // Get or compile regex
        guard let (regex, captureCount) = compiledPattern() else { return nil }

        guard let match = try? regex.firstMatch(in: urlString) else {
            return nil
        }

        // Build destination with captured groups
        // match[0] is the full match, match[1...] are capture groups
        var result = destinationTemplate
        for i in 1 ..< captureCount + 1 {
            let placeholder = "$\(i)"
            guard result.contains(placeholder) else { continue }

            // AnyRegexOutput indices: 0 = full match, 1+ = captures
            // If a required placeholder exists but capture group didn't match, fail the redirect
            guard let output = match.output[safe: i],
                  let range = output.range else {
                Logger.warning(
                    "Custom redirect '\(name)' failed: capture group $\(i) not matched",
                    category: Logger.navigation,
                )
                return nil
            }
            let captured = String(urlString[range])
            result = result.replacingOccurrences(of: placeholder, with: captured)
        }

        // Ensure result has a scheme
        if !result.contains("://") {
            // Handle relative paths by preserving the original URL's host
            if result.hasPrefix("/") {
                if let scheme = url.scheme, let host = url.host {
                    result = "\(scheme)://\(host)\(result)"
                } else {
                    return nil
                }
            } else {
                result = "https://\(result)"
            }
        }

        return URL(string: result)
    }

    // MARK: - Private Methods

    /// Returns the cached compiled pattern, or compiles it if needed.
    ///
    /// - Returns: Tuple of (compiled regex, number of capture groups), or nil on error.
    private func compiledPattern() -> (Regex<AnyRegexOutput>, Int)? {
        // Return cached regex if pattern hasn't changed
        if let cached = cachedRegex, cachedPatternSource == sourcePattern {
            return cached
        }

        // Compile and cache the pattern
        guard let compiled = compilePattern() else { return nil }
        cachedRegex = compiled
        cachedPatternSource = sourcePattern
        return compiled
    }

    /// Compiles the source pattern to a regex.
    ///
    /// - Returns: Tuple of (compiled regex, number of capture groups), or nil on error.
    private func compilePattern() -> (Regex<AnyRegexOutput>, Int)? {
        var regexPattern = "^"
        var captureCount = 0

        // Add scheme matching (optional https:// or http://)
        if !sourcePattern.contains("://") {
            regexPattern += "https?://"
        }

        // Process pattern character by character
        var i = sourcePattern.startIndex
        while i < sourcePattern.endIndex {
            let char = sourcePattern[i]

            if char == "*" {
                // Wildcard becomes a capturing group
                captureCount += 1
                regexPattern += "(.*?)"
            } else if "\\^$.|?+()[]{}".contains(char) {
                // Escape regex special characters
                regexPattern += "\\\(char)"
            } else {
                regexPattern += String(char)
            }

            i = sourcePattern.index(after: i)
        }

        regexPattern += "$"

        do {
            let regex = try Regex(regexPattern).ignoresCase()
            return (regex, captureCount)
        } catch {
            Logger.error("Invalid redirect pattern: \(sourcePattern)", category: Logger.navigation)
            return nil
        }
    }
}
