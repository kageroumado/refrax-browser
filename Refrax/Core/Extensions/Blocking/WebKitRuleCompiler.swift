import Algorithms
import Foundation

/// Converts parsed filter rules to WebKit content rule list JSON format.
///
/// WebKit content rules use a JSON format with triggers and actions:
/// ```json
/// [{
///   "trigger": { "url-filter": ".*\\.ads\\..*" },
///   "action": { "type": "block" }
/// }]
/// ```
///
/// ## WebKit Limitations
///
/// WebKit content rules have strict limitations:
/// - At most 150,000 rules per compiled list (`maxRuleCount` in WebCore's
///   `ContentExtensionParser.cpp`); larger rule sets are split across several lists
/// - Limited regex: no `|` alternation, no `{n,m}`, no lookahead/lookbehind
/// - Only ASCII characters in patterns
/// - Cannot have both `if-domain` AND `unless-domain` in same trigger
/// - `ignore-previous-rules` only overrides rules earlier in the same list
///
/// Rules that can't be represented are silently skipped. The compiler emits
/// `block`, `css-display-none`, and `ignore-previous-rules` actions; WebKit's
/// `redirect` and `modify-headers` actions additionally need the list enabled per
/// navigation through `WKWebpagePreferences._activeContentRuleListActionPatterns`.
nonisolated struct WebKitRuleCompiler: Sendable {
    // MARK: - Constants

    /// Maximum number of rules per WebKit content rule list.
    ///
    /// Matches WebKit's `maxRuleCount`: a list whose top-level array holds more
    /// rules fails to compile with `JSONTooManyRules`. Every attached list is a
    /// separate bytecode set WebKit consults per request, and an exception only
    /// reaches rules in its own list, so full chunks are both faster and more exact.
    static let maxRulesPerList = 150_000

    /// Version of the compiled output. Bump it when compilation changes, so rule
    /// lists cached in WebKit's store are recompiled rather than reused.
    ///
    /// - 2: Rules without a party option match first-party requests; `#@#`
    ///   exceptions no longer compile to `ignore-previous-rules`.
    static let version = 2

    /// Default resource types for blocking rules that don't specify types.
    /// Excludes `document` to prevent blocking main frame navigations.
    private static let defaultBlockingResourceTypes = [
        "script", "image", "style-sheet", "font", "raw", "media", "popup",
    ]

    // MARK: - Compilation

    /// Compiles parsed rules to WebKit content rule JSON.
    func compile(_ parseResult: FilterParser.ParseResult) -> String {
        let webkitRules = compileRules(parseResult)

        do {
            let data = try JSONSerialization.data(withJSONObject: webkitRules, options: [])
            return String(data: data, encoding: .utf8) ?? "[]"
        } catch {
            Logger.error("Failed to serialize WebKit rules: \(error)", category: Logger.tabs)
            return "[]"
        }
    }

    /// Compiles rules into JSON chunks that each fit in one WebKit content rule list.
    ///
    /// Chunks fill in filter-list order, network rules before cosmetic rules, so
    /// only the last chunk is partial.
    ///
    /// - Parameters:
    ///   - parseResult: The parsed filter list.
    ///   - maxRulesPerChunk: The largest number of WebKit rules in one chunk.
    /// - Returns: One JSON array per chunk; empty when no rule compiled.
    func compileInChunks(
        _ parseResult: FilterParser.ParseResult,
        maxRulesPerChunk: Int = Self.maxRulesPerList,
    ) -> [String] {
        precondition(maxRulesPerChunk > 0, "maxRulesPerChunk must be positive")
        return compileRules(parseResult)
            .chunks(ofCount: maxRulesPerChunk)
            .compactMap { serializeChunk(Array($0)) }
    }

    /// Compiles every network rule, then every cosmetic rule, into WebKit rule objects.
    private func compileRules(_ parseResult: FilterParser.ParseResult) -> [[String: Any]] {
        var webkitRules: [[String: Any]] = []
        for rule in parseResult.networkRules {
            webkitRules.append(contentsOf: compileNetworkRule(rule))
        }
        webkitRules.append(contentsOf: compileCosmeticRules(parseResult.cosmeticRules))
        return webkitRules
    }

    // MARK: - Rule Compilation

    /// Compiles a single rule, potentially returning multiple WebKit rules.
    ///
    /// Multiple rules may be returned when:
    /// - Pattern ends with `^` (separator): creates both separator and end-anchor variants
    /// - Rule has both `if-domain` and `unless-domain`: splits into separate rules
    private func compileNetworkRule(_ rule: FilterParser.NetworkRule) -> [[String: Any]] {
        // Build URL filter first - if invalid, skip the rule
        guard let urlFilter = buildURLFilter(rule) else { return [] }

        // Validate the final pattern is WebKit-compatible
        guard isValidWebKitRegex(urlFilter) else { return [] }

        // Check if we need an end-anchor variant (pattern ends with ^ separator)
        // This ensures patterns like ||ads.com^ match both ads.com/foo AND ads.com
        let needsEndAnchorVariant = rule.pattern.hasSuffix("^") && !rule.isRegex
        var endAnchorFilter: String?
        if needsEndAnchorVariant {
            endAnchorFilter = buildEndAnchorURLFilter(rule)
            if let filter = endAnchorFilter, !isValidWebKitRegex(filter) {
                endAnchorFilter = nil
            }
        }

        // Resource types - NEVER block main document navigations for blocking rules
        var resourceTypes: [String]?
        if let ruleTypes = rule.resourceTypes, !ruleTypes.isEmpty {
            var webkitTypes = ruleTypes.compactMap { webkitResourceType($0) }
            // Remove "document" from blocking rules to prevent blocking page navigation
            if !rule.isException {
                webkitTypes.removeAll { $0 == "document" }
            }
            if webkitTypes.isEmpty {
                return [] // All types were document - skip
            }
            resourceTypes = webkitTypes
        } else if !rule.isException {
            // No types specified on blocking rule: use safe defaults (no document)
            resourceTypes = Self.defaultBlockingResourceTypes
        }

        // Third-party / first-party. Without `$third-party` or `$first-party` a rule
        // matches both, as in uBlock Origin and Adblock Plus: sites like YouTube serve
        // their ads and ad beacons from their own domain.
        let hasDomains = rule.domains?.isEmpty == false
        var loadType: [String]?
        if let thirdParty = rule.thirdParty {
            loadType = thirdParty ? ["third-party"] : ["first-party"]
        }

        let action: [String: String] = [
            "type": rule.isException ? "ignore-previous-rules" : "block",
        ]

        // Domain conditions - WebKit only allows ONE of if-domain or unless-domain
        let hasExcludeDomains = rule.excludeDomains?.isEmpty == false

        // If both domains and excludeDomains present, split into separate rules
        if hasDomains, hasExcludeDomains {
            return buildSplitDomainRules(
                urlFilter: urlFilter,
                endAnchorFilter: endAnchorFilter,
                rule: rule,
                resourceTypes: resourceTypes,
                loadType: loadType,
                action: action,
            )
        }

        // Single domain condition or none
        var rules: [[String: Any]] = []

        // Build main rule
        if let mainRule = buildSingleRule(
            urlFilter: urlFilter,
            rule: rule,
            resourceTypes: resourceTypes,
            loadType: loadType,
            action: action,
        ) {
            rules.append(mainRule)
        }

        // Build end-anchor variant if needed
        if let endFilter = endAnchorFilter {
            if let endRule = buildSingleRule(
                urlFilter: endFilter,
                rule: rule,
                resourceTypes: resourceTypes,
                loadType: loadType,
                action: action,
            ) {
                rules.append(endRule)
            }
        }

        return rules
    }

    /// Builds a single WebKit rule with the given parameters.
    private func buildSingleRule(
        urlFilter: String,
        rule: FilterParser.NetworkRule,
        resourceTypes: [String]?,
        loadType: [String]?,
        action: [String: String],
    ) -> [String: Any]? {
        var trigger: [String: Any] = [:]
        trigger["url-filter"] = urlFilter
        trigger["url-filter-is-case-sensitive"] = false

        if let domains = rule.domains, !domains.isEmpty {
            let validDomains = domains.compactMap { formatDomain($0) }
            if validDomains.isEmpty { return nil }
            trigger["if-domain"] = validDomains
        } else if let excludeDomains = rule.excludeDomains, !excludeDomains.isEmpty {
            let validDomains = excludeDomains.compactMap { formatDomain($0) }
            if validDomains.isEmpty { return nil }
            trigger["unless-domain"] = validDomains
        }

        if let types = resourceTypes {
            trigger["resource-type"] = types
        }
        if let load = loadType {
            trigger["load-type"] = load
        }

        return ["trigger": trigger, "action": action]
    }

    /// Builds split rules when both if-domain and unless-domain are present.
    private func buildSplitDomainRules(
        urlFilter: String,
        endAnchorFilter: String?,
        rule: FilterParser.NetworkRule,
        resourceTypes: [String]?,
        loadType: [String]?,
        action: [String: String],
    ) -> [[String: Any]] {
        var rules: [[String: Any]] = []

        guard let domains = rule.domains, !domains.isEmpty,
              let excludeDomains = rule.excludeDomains, !excludeDomains.isEmpty else {
            return []
        }

        let validIncludeDomains = domains.compactMap { formatDomain($0) }
        let validExcludeDomains = excludeDomains.compactMap { formatDomain($0) }

        guard !validIncludeDomains.isEmpty, !validExcludeDomains.isEmpty else { return [] }

        // Rule 1: Apply to included domains only
        var trigger1: [String: Any] = [
            "url-filter": urlFilter,
            "url-filter-is-case-sensitive": false,
            "if-domain": validIncludeDomains,
        ]
        if let types = resourceTypes { trigger1["resource-type"] = types }
        if let load = loadType { trigger1["load-type"] = load }
        rules.append(["trigger": trigger1, "action": action])

        // Rule 1b: End-anchor variant for included domains
        if let endFilter = endAnchorFilter {
            var trigger1b: [String: Any] = [
                "url-filter": endFilter,
                "url-filter-is-case-sensitive": false,
                "if-domain": validIncludeDomains,
            ]
            if let types = resourceTypes { trigger1b["resource-type"] = types }
            if let load = loadType { trigger1b["load-type"] = load }
            rules.append(["trigger": trigger1b, "action": action])
        }

        // Rule 2: Apply everywhere except excluded domains
        var trigger2: [String: Any] = [
            "url-filter": urlFilter,
            "url-filter-is-case-sensitive": false,
            "unless-domain": validExcludeDomains,
        ]
        if let types = resourceTypes { trigger2["resource-type"] = types }
        if let load = loadType { trigger2["load-type"] = load }
        rules.append(["trigger": trigger2, "action": action])

        // Rule 2b: End-anchor variant for excluded domains
        if let endFilter = endAnchorFilter {
            var trigger2b: [String: Any] = [
                "url-filter": endFilter,
                "url-filter-is-case-sensitive": false,
                "unless-domain": validExcludeDomains,
            ]
            if let types = resourceTypes { trigger2b["resource-type"] = types }
            if let load = loadType { trigger2b["load-type"] = load }
            rules.append(["trigger": trigger2b, "action": action])
        }

        return rules
    }

    // MARK: - URL Filter Building

    private func buildURLFilter(_ rule: FilterParser.NetworkRule) -> String? {
        var pattern = rule.pattern

        // Reject empty or overly broad patterns
        let trimmed = pattern.trimmingCharacters(in: CharacterSet.whitespaces)
        if trimmed.isEmpty || trimmed == "*" || trimmed == "^" || trimmed == "**" || trimmed == "***" {
            return nil
        }

        if rule.isRegex {
            return sanitizeRegex(pattern)
        }

        // Convert AdBlock pattern to WebKit regex
        pattern = convertToWebKitRegex(pattern)

        // Reject if pattern became empty or too broad
        if pattern.isEmpty || pattern == ".*" || pattern == ".+" || pattern == "." {
            return nil
        }

        // Handle anchors
        if rule.isDomainAnchor {
            // || means domain anchor: match domain or subdomain
            pattern = "^[^:]+://([^/]*\\.)?" + pattern
        } else if rule.anchorStart {
            pattern = "^" + pattern
        }

        if rule.anchorEnd {
            pattern += "$"
        }

        return pattern
    }

    /// Builds an end-anchor variant for patterns ending with ^ separator.
    ///
    /// When a pattern like `||ads.com^` is converted, it matches `ads.com/foo` (separator in middle),
    /// but NOT `ads.com` where the URL ends at the domain. This method creates a variant with `$`
    /// end anchor to match that case.
    private func buildEndAnchorURLFilter(_ rule: FilterParser.NetworkRule) -> String? {
        // Strip the trailing ^ from pattern
        var pattern = rule.pattern
        guard pattern.hasSuffix("^") else { return nil }
        pattern = String(pattern.dropLast())

        // Reject empty or overly broad patterns
        let trimmed = pattern.trimmingCharacters(in: CharacterSet.whitespaces)
        if trimmed.isEmpty || trimmed == "*" || trimmed == "**" {
            return nil
        }

        // Convert AdBlock pattern to WebKit regex (without the trailing ^)
        pattern = convertToWebKitRegex(pattern)

        // Reject if pattern became empty or too broad
        if pattern.isEmpty || pattern == ".*" || pattern == ".+" || pattern == "." {
            return nil
        }

        // Handle anchors
        if rule.isDomainAnchor {
            pattern = "^[^:]+://([^/]*\\.)?" + pattern
        } else if rule.anchorStart {
            pattern = "^" + pattern
        }

        // Add end anchor (this is the key difference)
        pattern += "$"

        return pattern
    }

    /// Converts AdBlock pattern syntax to WebKit-compatible regex.
    private func convertToWebKitRegex(_ pattern: String) -> String {
        var result = ""
        result.reserveCapacity(pattern.count * 2)

        for char in pattern {
            switch char {
            // AdBlock wildcards
            case "*":
                result += ".*"
            case "^":
                // Separator: matches non-alphanumeric except _ - . %
                result += "[^a-zA-Z0-9_.%-]"
            // Regex special chars that need escaping
            case ".":
                result += "\\."
            case "+":
                result += "\\+"
            case "?":
                result += "\\?"
            case "[":
                result += "\\["
            case "]":
                result += "\\]"
            case "(":
                result += "\\("
            case ")":
                result += "\\)"
            case "{":
                result += "\\{"
            case "}":
                result += "\\}"
            case "|":
                result += "\\|"
            case "\\":
                result += "\\\\"
            case "$":
                result += "\\$"
            // Pass through safe characters
            default:
                // Only allow ASCII characters
                if char.isASCII {
                    result.append(char)
                }
            }
        }

        return result
    }

    /// Sanitizes a regex pattern for WebKit's limited regex support.
    private func sanitizeRegex(_ regex: String) -> String? {
        // Reject non-ASCII patterns
        guard regex.allSatisfy(\.isASCII) else { return nil }

        var cleaned = regex

        // Remove lookahead (?=...) and (?!...)
        cleaned = cleaned.replacingOccurrences(
            of: "\\(\\?[=!][^)]*\\)",
            with: "",
            options: .regularExpression,
        )

        // Remove lookbehind (?<=...) and (?<!...)
        cleaned = cleaned.replacingOccurrences(
            of: "\\(\\?<[=!][^)]*\\)",
            with: "",
            options: .regularExpression,
        )

        // Convert character class shortcuts
        cleaned = cleaned.replacingOccurrences(of: "\\w", with: "[a-zA-Z0-9_]")
        cleaned = cleaned.replacingOccurrences(of: "\\W", with: "[^a-zA-Z0-9_]")
        cleaned = cleaned.replacingOccurrences(of: "\\d", with: "[0-9]")
        cleaned = cleaned.replacingOccurrences(of: "\\D", with: "[^0-9]")
        cleaned = cleaned.replacingOccurrences(of: "\\s", with: "[ \\t\\n\\r]")
        cleaned = cleaned.replacingOccurrences(of: "\\S", with: "[^ \\t\\n\\r]")

        // Convert open-ended quantifiers {n,} to + (approximate "n or more" as "one or more")
        // WebKit doesn't support numeric quantifiers, but {n,} can be approximated
        cleaned = cleaned.replacingOccurrences(
            of: "\\{[0-9]+,\\}",
            with: "+",
            options: .regularExpression,
        )

        // Check for unsupported features
        if containsUnsupportedRegex(cleaned) {
            return nil
        }

        // Reject overly broad patterns
        if cleaned.isEmpty || cleaned == ".*" || cleaned == ".+" || cleaned == "." {
            return nil
        }

        return cleaned
    }

    /// Checks for regex features not supported by WebKit.
    private func containsUnsupportedRegex(_ pattern: String) -> Bool {
        // Check for unescaped alternation (|) outside character classes
        if containsUnescapedAlternation(pattern) {
            return true
        }

        // Check for repetition ranges {n} {n,} {n,m}
        if pattern.contains("{") {
            return true
        }

        // Check for non-capturing groups (?:...)
        if pattern.contains("(?:") || pattern.contains("(?") {
            return true
        }

        // Check for backreferences \1, \2, etc.
        if pattern.range(of: "\\\\[0-9]", options: .regularExpression) != nil {
            return true
        }

        // Verify balanced brackets and parentheses
        if !hasBalancedBrackets(pattern) {
            return true
        }

        return false
    }

    /// Checks if pattern contains unescaped | outside character classes.
    private func containsUnescapedAlternation(_ pattern: String) -> Bool {
        var inCharClass = false
        var i = pattern.startIndex

        while i < pattern.endIndex {
            let char = pattern[i]
            let nextIndex = pattern.index(after: i)

            if char == "\\", nextIndex < pattern.endIndex {
                // Skip escaped character
                i = pattern.index(after: nextIndex)
                continue
            }

            if char == "[" {
                inCharClass = true
            } else if char == "]", inCharClass {
                inCharClass = false
            } else if char == "|", !inCharClass {
                return true
            }

            i = nextIndex
        }

        return false
    }

    /// Verifies brackets [] and parentheses () are balanced.
    private func hasBalancedBrackets(_ pattern: String) -> Bool {
        var bracketDepth = 0
        var parenDepth = 0
        var i = pattern.startIndex

        while i < pattern.endIndex {
            let char = pattern[i]
            let nextIndex = pattern.index(after: i)

            if char == "\\", nextIndex < pattern.endIndex {
                // Skip escaped character
                i = pattern.index(after: nextIndex)
                continue
            }

            switch char {
            case "[":
                bracketDepth += 1
            case "]":
                bracketDepth -= 1
                if bracketDepth < 0 { return false }
            case "(":
                parenDepth += 1
            case ")":
                parenDepth -= 1
                if parenDepth < 0 { return false }
            default:
                break
            }

            i = nextIndex
        }

        return bracketDepth == 0 && parenDepth == 0
    }

    /// Final validation that pattern is WebKit-compatible.
    private func isValidWebKitRegex(_ pattern: String) -> Bool {
        // Must be non-empty
        guard !pattern.isEmpty else { return false }

        // Must be ASCII only
        guard pattern.allSatisfy(\.isASCII) else { return false }

        // Check for balanced brackets
        guard hasBalancedBrackets(pattern) else { return false }

        // No unescaped alternation
        guard !containsUnescapedAlternation(pattern) else { return false }

        // No unsupported constructs
        if pattern.contains("{") || pattern.contains("(?") {
            return false
        }

        return true
    }

    // MARK: - Domain Formatting

    /// Formats a domain for WebKit's if-domain/unless-domain.
    private func formatDomain(_ domain: String) -> String? {
        var d = domain.lowercased()

        // Remove leading dot if present
        if d.hasPrefix(".") {
            d = String(d.dropFirst())
        }

        // Reject empty domains
        guard !d.isEmpty else { return nil }

        // Reject domains with wildcards (WebKit doesn't support regex in domains)
        if d.contains("*") || d.contains("?") {
            return nil
        }

        // Must be ASCII
        guard d.allSatisfy(\.isASCII) else { return nil }

        // WebKit expects domains prefixed with * for subdomain matching
        return "*\(d)"
    }

    // MARK: - Resource Type Mapping

    private func webkitResourceType(_ type: FilterParser.ResourceType) -> String? {
        switch type {
        case .document:
            "document"
        case .stylesheet:
            "style-sheet"
        case .script:
            "script"
        case .image:
            "image"
        case .font:
            "font"
        case .media:
            "media"
        case .popup:
            "popup"
        case .xmlhttprequest:
            "raw" // fetch/XHR maps to "raw"
        case .websocket:
            "raw" // WebKit doesn't have websocket type
        case .other:
            nil
        }
    }

    // MARK: - Cosmetic Rule Compilation

    /// Groups cosmetic rules by domain combination and compiles to WebKit `css-display-none` rules.
    ///
    /// Selectors with the same domain constraints are merged into a single rule with
    /// a comma-separated selector list, reducing the total rule count.
    ///
    /// Exceptions (`#@#`) unhide one selector, which WebKit can't express: its only
    /// exception action, `ignore-previous-rules`, cancels every earlier rule in the
    /// list, network blocks included. They're applied here instead, by dropping the
    /// selector from the hiding rules on the excepted domains.
    private func compileCosmeticRules(_ rules: [FilterParser.CosmeticRule]) -> [[String: Any]] {
        // Group by (domains, excludeDomains) to merge selectors
        struct DomainKey: Hashable {
            let domains: [String]?
            let excludeDomains: [String]?
        }

        let exceptions = cosmeticExceptions(in: rules)
        var groups: [DomainKey: [String]] = [:]
        var groupOrder: [DomainKey] = []

        for rule in rules where !rule.isException {
            // Validate selector is ASCII (WebKit requirement)
            guard rule.selector.allSatisfy(\.isASCII) else { continue }
            guard let key = applyingExceptions(exceptions[rule.selector], to: rule).map({
                DomainKey(domains: $0.domains, excludeDomains: $0.excludeDomains)
            }) else { continue }

            if groups[key] == nil {
                groupOrder.append(key)
            }
            groups[key, default: []].append(rule.selector)
        }

        var webkitRules: [[String: Any]] = []

        for key in groupOrder {
            guard let selectors = groups[key] else { continue }

            // WebKit css-display-none supports comma-separated selectors
            let combinedSelector = selectors.joined(separator: ", ")

            var trigger: [String: Any] = [
                "url-filter": ".*",
            ]

            // Domain constraints
            if let domains = key.domains, !domains.isEmpty {
                let validDomains = domains.compactMap { formatDomain($0) }
                guard !validDomains.isEmpty else { continue }
                trigger["if-domain"] = validDomains
            } else if let excludeDomains = key.excludeDomains, !excludeDomains.isEmpty {
                let validDomains = excludeDomains.compactMap { formatDomain($0) }
                guard !validDomains.isEmpty else { continue }
                trigger["unless-domain"] = validDomains
            }

            webkitRules.append([
                "trigger": trigger,
                "action": ["type": "css-display-none", "selector": combinedSelector],
            ])
        }

        return webkitRules
    }

    /// Where each selector is excepted from hiding.
    ///
    /// Maps a selector to the domains of its `#@#` exceptions, or to `nil` when an
    /// exception applies everywhere.
    private func cosmeticExceptions(in rules: [FilterParser.CosmeticRule]) -> [String: Set<String>?] {
        var exceptions: [String: Set<String>?] = [:]
        for rule in rules where rule.isException {
            guard let domains = rule.domains, !domains.isEmpty else {
                exceptions[rule.selector] = .some(nil)
                continue
            }
            if case .some(nil) = exceptions[rule.selector] {
                continue
            }
            let normalized = domains.map { normalizeCosmeticDomain($0) }
            exceptions[rule.selector] = .some((exceptions[rule.selector] ?? []).map { $0.union(normalized) })
        }
        return exceptions
    }

    /// The domain constraints left for a hiding rule once its selector's exceptions apply.
    ///
    /// - Parameters:
    ///   - exception: The selector's exception domains; `.some(nil)` for everywhere,
    ///     `nil` when the selector has no exception.
    ///   - rule: The hiding rule.
    /// - Returns: The rule's domains and excluded domains, or `nil` when the
    ///   exceptions leave nowhere to hide the selector.
    private func applyingExceptions(
        _ exception: Set<String>??,
        to rule: FilterParser.CosmeticRule,
    ) -> (domains: [String]?, excludeDomains: [String]?)? {
        guard let exception else { return (rule.domains, rule.excludeDomains) }
        guard let exceptedDomains = exception else { return nil }

        func isExcepted(_ domain: String) -> Bool {
            let domain = normalizeCosmeticDomain(domain)
            return exceptedDomains.contains { domain == $0 || domain.hasSuffix(".\($0)") }
        }

        if let domains = rule.domains, !domains.isEmpty {
            // Hidden only on listed domains: stop hiding on the excepted ones
            let remaining = domains.filter { !isExcepted($0) }
            return remaining.isEmpty ? nil : (remaining, rule.excludeDomains)
        }

        // Hidden everywhere: exclude the excepted domains as well
        let excluded = (rule.excludeDomains ?? []) + exceptedDomains.sorted().filter { excepted in
            !(rule.excludeDomains ?? []).contains { normalizeCosmeticDomain($0) == excepted }
        }
        return (nil, excluded)
    }

    /// Lowercases a filter-list domain and drops a leading dot.
    private func normalizeCosmeticDomain(_ domain: String) -> String {
        let lowered = domain.lowercased()
        return lowered.hasPrefix(".") ? String(lowered.dropFirst()) : lowered
    }

    // MARK: - Serialization

    private func serializeChunk(_ rules: [[String: Any]]) -> String? {
        do {
            let data = try JSONSerialization.data(withJSONObject: rules, options: [])
            return String(data: data, encoding: .utf8)
        } catch {
            Logger.error("Failed to serialize WebKit rule chunk: \(error)", category: Logger.tabs)
            return nil
        }
    }
}
