import Foundation
import SwiftData

/// A rule for handling external URLs matching specific patterns.
///
/// External URL rules allow users to customize how URLs from external sources
/// are handled based on domain, path, or URL patterns.
///
/// ## Pattern Matching
///
/// Domain and path patterns support wildcards:
/// - `*` matches any sequence of characters
/// - `*.example.com` matches any subdomain of example.com
/// - `/docs/*` matches any path starting with /docs/
///
/// ## Example Rules
///
/// - GitHub URLs → Open in "Development" space
/// - YouTube URLs → Open in Glimpse window
/// - Work domain → Open in "Work" space
@Model
final class ExternalURLRule {
    /// Stable identifier for sync.
    @Attribute(.preserveValueOnDeletion)
    var id: UUID = UUID()

    /// Display name for this rule.
    var name: String

    /// Domain pattern to match.
    ///
    /// Supports `*` wildcards. Examples:
    /// - `github.com` — exact match
    /// - `*.github.com` — any subdomain
    /// - `*` — matches all domains
    var domainPattern: String

    /// Optional path pattern to match.
    ///
    /// If nil, matches all paths on the domain.
    /// Supports `*` wildcards. Example: `/watch*`
    var pathPattern: String?

    /// The action to take when this rule matches.
    var actionRaw: String = ""

    /// Target space ID for space-specific actions.
    var targetSpaceID: UUID?

    /// Target group ID for group-specific actions.
    var targetGroupID: UUID?

    /// Whether this rule is active.
    var isEnabled: Bool = true

    /// Sort order within the rule list.
    var order: Int = 0

    /// Parent settings (inverse relationship).
    var settings: ExternalURLSettings?

    // MARK: - Cached Regex

    /// Cached compiled regex for domain pattern.
    @Transient
    private var _cachedDomainRegex: Regex<AnyRegexOutput>?

    /// Pattern used to compile the cached domain regex.
    @Transient
    private var _cachedDomainPattern: String?

    /// Cached compiled regex for path pattern.
    @Transient
    private var _cachedPathRegex: Regex<AnyRegexOutput>?

    /// Pattern used to compile the cached path regex.
    @Transient
    private var _cachedPathPattern: String?

    // MARK: - Initialization

    init(
        name: String,
        domainPattern: String,
        pathPattern: String? = nil,
        action: ExternalURLAction = .openInCurrentSpace,
        targetSpaceID: UUID? = nil,
        targetGroupID: UUID? = nil,
        isEnabled: Bool = true,
        order: Int = 0,
    ) {
        self.name = name
        self.domainPattern = domainPattern
        self.pathPattern = pathPattern
        self.targetSpaceID = targetSpaceID
        self.targetGroupID = targetGroupID
        self.isEnabled = isEnabled
        self.order = order
        self.action = action
    }

    // MARK: - Action Property

    /// The action to take when this rule matches.
    var action: ExternalURLAction {
        get {
            ExternalURLAction.decode(
                from: actionRaw,
                targetSpaceID: targetSpaceID,
                targetGroupID: targetGroupID,
            )
        }
        set {
            let encoded = newValue.encode()
            actionRaw = encoded.rawValue
            targetSpaceID = encoded.targetSpaceID
            targetGroupID = encoded.targetGroupID
        }
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

        // Match-all rule
        if domainPattern == "*" {
            return matchesPath(url)
        }

        // Check domain pattern
        guard let domainRegex = domainRegex(for: domainPattern.lowercased()),
              host.wholeMatch(of: domainRegex) != nil
        else { return false }

        return matchesPath(url)
    }

    private func matchesPath(_ url: URL) -> Bool {
        guard let pathPattern else { return true }

        guard let pathRegex = pathRegex(for: pathPattern),
              url.path.wholeMatch(of: pathRegex) != nil
        else { return false }

        return true
    }

    // MARK: - Regex Caching

    private func domainRegex(for pattern: String) -> Regex<AnyRegexOutput>? {
        if pattern == _cachedDomainPattern, let cached = _cachedDomainRegex {
            return cached
        }

        guard let regex = compileWildcardPattern(pattern) else {
            return nil
        }

        _cachedDomainPattern = pattern
        _cachedDomainRegex = regex
        return regex
    }

    private func pathRegex(for pattern: String) -> Regex<AnyRegexOutput>? {
        if pattern == _cachedPathPattern, let cached = _cachedPathRegex {
            return cached
        }

        guard let regex = compileWildcardPattern(pattern) else {
            return nil
        }

        _cachedPathPattern = pattern
        _cachedPathRegex = regex
        return regex
    }

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

// MARK: - Display Helpers

extension ExternalURLRule {
    /// A human-readable description of this rule's pattern.
    var patternDescription: String {
        if let pathPattern {
            "\(domainPattern)\(pathPattern)"
        } else {
            domainPattern
        }
    }

    /// A human-readable description of this rule's action.
    var actionDescription: String {
        action.description
    }
}
