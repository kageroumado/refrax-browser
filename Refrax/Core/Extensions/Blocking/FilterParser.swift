import Foundation

/// Parses AdBlock Plus and uBlock Origin filter list syntax.
///
/// This parser extracts both network rules and cosmetic rules that can be
/// converted to WebKit content rules.
///
/// ## Supported Syntax
///
/// ### Network Rules
///
/// | Syntax | Meaning | Example |
/// |--------|---------|---------|
/// | `\|\|domain.com^` | Block requests to domain | `\|\|ads.example.com^` |
/// | `@@\|\|domain.com^` | Exception (allow) | `@@\|\|allowed.com^` |
/// | `/regex/` | Regex URL pattern | `/ad[0-9]+\\.js/` |
/// | `$option` | Filter options | `\|\|example.com^$script,third-party` |
/// | `\|https://` | Starts with | `\|https://ads.` |
/// | `^` | Separator (non-alphanumeric except `_-.%`) | `\|\|example.com^` |
///
/// ### Cosmetic Rules (Element Hiding)
///
/// | Syntax | Meaning | Example |
/// |--------|---------|---------|
/// | `##selector` | Hide element globally | `##.cookie-banner` |
/// | `domain##selector` | Hide on specific domain | `example.com##.ad` |
/// | `~domain##selector` | Hide except on domain | `~example.com##.ad` |
/// | `#@#selector` | Exception (unhide) | `#@#.cookie-banner` |
///
/// ## Skipped Syntax (handled by uBlock extension)
///
/// - `#?#selector` (procedural cosmetic filters)
/// - `##+js()` (scriptlet injection)
/// - `#$#` (CSS injection, AdGuard)
/// - `!` (comments)
/// - `[Adblock Plus ...]` (header)
nonisolated struct FilterParser: Sendable {
    // MARK: - Parsed Rule Types

    /// A parsed network filter rule.
    struct NetworkRule: Sendable, Equatable {
        /// The URL pattern to match.
        let pattern: String

        /// Whether this is a regex pattern.
        let isRegex: Bool

        /// Whether this is an exception (allow) rule.
        let isException: Bool

        /// Whether the pattern anchors to start of URL.
        let anchorStart: Bool

        /// Whether the pattern anchors to end of URL.
        let anchorEnd: Bool

        /// Whether pattern starts with `||` (domain anchor).
        let isDomainAnchor: Bool

        /// Domains to apply the rule to (if-domain).
        let domains: [String]?

        /// Domains to exclude from the rule (unless-domain).
        let excludeDomains: [String]?

        /// Resource types to block.
        let resourceTypes: Set<ResourceType>?

        /// Whether to match only third-party requests.
        let thirdParty: Bool?
    }

    /// Resource types that can be filtered.
    enum ResourceType: String, CaseIterable, Sendable {
        case document
        case stylesheet = "style-sheet"
        case script
        case image
        case font
        case media
        case popup
        case xmlhttprequest = "raw"
        case websocket
        case other

        /// Maps AdBlock Plus option names to WebKit resource types.
        static func from(adblockOption: String) -> ResourceType? {
            switch adblockOption.lowercased() {
            case "document", "doc":
                .document
            case "stylesheet", "css":
                .stylesheet
            case "script":
                .script
            case "image", "img":
                .image
            case "font":
                .font
            case "media":
                .media
            case "popup":
                .popup
            case "xmlhttprequest", "xhr":
                .xmlhttprequest
            case "websocket":
                .websocket
            case "subdocument", "frame":
                .document // Treat as document for WebKit
            case "other":
                .other
            default:
                nil
            }
        }
    }

    /// A parsed cosmetic (element hiding) rule.
    struct CosmeticRule: Sendable, Equatable {
        /// CSS selector to hide.
        let selector: String

        /// Domains to apply the rule on. `nil` means all domains (global).
        let domains: [String]?

        /// Domains to exclude from the rule.
        let excludeDomains: [String]?

        /// Whether this is an exception (unhide) rule (`#@#`).
        let isException: Bool
    }

    /// Result of parsing a filter list, containing both network and cosmetic rules.
    struct ParseResult: Sendable {
        let networkRules: [NetworkRule]
        let cosmeticRules: [CosmeticRule]
    }

    // MARK: - Parsing

    /// Parses a filter list and returns both network and cosmetic rules.
    ///
    /// - Parameter content: The raw filter list text content.
    /// - Returns: Parsed network and cosmetic rules.
    func parse(_ content: String) -> ParseResult {
        var networkRules: [NetworkRule] = []
        var cosmeticRules: [CosmeticRule] = []

        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Skip empty lines
            guard !trimmed.isEmpty else { continue }

            // Skip comments
            guard !trimmed.hasPrefix("!") else { continue }

            // Skip header
            guard !trimmed.hasPrefix("[") else { continue }

            // Skip scriptlet rules (+js, etc.)
            guard !isScriptletRule(trimmed) else { continue }

            // Try cosmetic rule first
            if let cosmeticRule = parseCosmeticRule(trimmed) {
                cosmeticRules.append(cosmeticRule)
                continue
            }

            // Skip unsupported cosmetic syntax (procedural, CSS injection)
            guard !isUnsupportedCosmeticRule(trimmed) else { continue }

            // Parse network rule
            if let rule = parseNetworkRule(trimmed) {
                networkRules.append(rule)
            }
        }

        return ParseResult(networkRules: networkRules, cosmeticRules: cosmeticRules)
    }

    // MARK: - Rule Type Detection

    /// Checks for cosmetic syntax we don't parse (procedural, CSS injection).
    private func isUnsupportedCosmeticRule(_ line: String) -> Bool {
        line.contains("#?#") || line.contains("#$#") || line.contains("#@?#") || line.contains("#$?#")
    }

    private func isScriptletRule(_ line: String) -> Bool {
        line.contains("+js(") || line.contains("#%#")
    }

    // MARK: - Cosmetic Rule Parsing

    /// Parses a cosmetic (element hiding) rule.
    ///
    /// Handles:
    /// - `##.selector` — global
    /// - `domain.com##.selector` — domain-scoped
    /// - `domain.com,other.com##.selector` — multi-domain
    /// - `~domain.com##.selector` — all except domain
    /// - `#@#.selector` — exception (global unhide)
    /// - `domain.com#@#.selector` — domain-scoped exception
    private func parseCosmeticRule(_ line: String) -> CosmeticRule? {
        // Find the cosmetic separator: ## or #@#
        // Must distinguish from #?#, #$#, ##+js() which we skip
        let isException: Bool
        let separatorRange: Range<String.Index>
        let selector: String

        if let range = findCosmeticSeparator(line, separator: "#@#") {
            isException = true
            separatorRange = range
            selector = String(line[range.upperBound...])
        } else if let range = findCosmeticSeparator(line, separator: "##") {
            isException = false
            separatorRange = range
            selector = String(line[range.upperBound...])
        } else {
            return nil
        }

        // Reject if selector is empty or starts with special syntax
        let trimmedSelector = selector.trimmingCharacters(in: .whitespaces)
        guard !trimmedSelector.isEmpty else { return nil }

        // Skip procedural/extended selectors that start with +js(, :has(), :style()
        if trimmedSelector.hasPrefix("+js(") || trimmedSelector.hasPrefix("^") {
            return nil
        }

        // Parse domain part (everything before the separator)
        let domainPart = String(line[..<separatorRange.lowerBound])

        var includeDomains: [String]?
        var excludeDomains: [String]?

        if !domainPart.isEmpty {
            var incl: [String] = []
            var excl: [String] = []

            let domains = domainPart.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespaces) }
            for domain in domains {
                guard !domain.isEmpty else { continue }
                if domain.hasPrefix("~") {
                    let d = String(domain.dropFirst())
                    if !d.isEmpty { excl.append(d) }
                } else {
                    incl.append(domain)
                }
            }

            includeDomains = incl.isEmpty ? nil : incl
            excludeDomains = excl.isEmpty ? nil : excl
        }

        return CosmeticRule(
            selector: trimmedSelector,
            domains: includeDomains,
            excludeDomains: excludeDomains,
            isException: isException,
        )
    }

    /// Finds the first occurrence of a cosmetic separator (`##` or `#@#`) that
    /// isn't part of a longer special sequence like `#?#`, `#$#`, or `##+js(`.
    private func findCosmeticSeparator(_ line: String, separator: String) -> Range<String.Index>? {
        var searchStart = line.startIndex

        while let range = line.range(of: separator, range: searchStart ..< line.endIndex) {
            if separator == "##" {
                // Skip ##+js() scriptlet injection
                let afterIndex = range.upperBound
                if afterIndex < line.endIndex, line[afterIndex] == "+" {
                    searchStart = range.upperBound
                    continue
                }

                // Skip if this ## is actually inside #@#, #?#, or #$#
                if range.lowerBound > line.startIndex {
                    let charBefore = line[line.index(before: range.lowerBound)]
                    if charBefore == "@" || charBefore == "?" || charBefore == "$" {
                        searchStart = range.upperBound
                        continue
                    }
                }
            }

            return range
        }

        return nil
    }

    // MARK: - Network Rule Parsing

    private func parseNetworkRule(_ line: String) -> NetworkRule? {
        var pattern = line
        var isException = false
        var anchorStart = false
        var anchorEnd = false
        var isDomainAnchor = false
        var isRegex = false
        var domains: [String]?
        var excludeDomains: [String]?
        var resourceTypes: Set<ResourceType>?
        var thirdParty: Bool?

        // Check for exception rule
        if pattern.hasPrefix("@@") {
            isException = true
            pattern = String(pattern.dropFirst(2))
        }

        // Parse options (after $)
        if let dollarIndex = pattern.lastIndex(of: "$") {
            let optionsString = String(pattern[pattern.index(after: dollarIndex)...])
            pattern = String(pattern[..<dollarIndex])

            let parsed = parseOptions(optionsString)
            domains = parsed.domains
            excludeDomains = parsed.excludeDomains
            resourceTypes = parsed.resourceTypes
            thirdParty = parsed.thirdParty

            // Skip rules with unsupported options
            if parsed.hasUnsupportedOptions {
                return nil
            }
        }

        // Check for regex pattern
        if pattern.hasPrefix("/"), pattern.hasSuffix("/"), pattern.count > 2 {
            isRegex = true
            pattern = String(pattern.dropFirst().dropLast())
        } else {
            // Check for anchors
            if pattern.hasPrefix("||") {
                isDomainAnchor = true
                pattern = String(pattern.dropFirst(2))
            } else if pattern.hasPrefix("|") {
                anchorStart = true
                pattern = String(pattern.dropFirst())
            }

            if pattern.hasSuffix("|") {
                anchorEnd = true
                pattern = String(pattern.dropLast())
            }
        }

        // Skip empty patterns
        guard !pattern.isEmpty else { return nil }

        return NetworkRule(
            pattern: pattern,
            isRegex: isRegex,
            isException: isException,
            anchorStart: anchorStart,
            anchorEnd: anchorEnd,
            isDomainAnchor: isDomainAnchor,
            domains: domains,
            excludeDomains: excludeDomains,
            resourceTypes: resourceTypes,
            thirdParty: thirdParty,
        )
    }

    // MARK: - Option Parsing

    private struct ParsedOptions {
        var domains: [String]?
        var excludeDomains: [String]?
        var resourceTypes: Set<ResourceType>?
        var thirdParty: Bool?
        var hasUnsupportedOptions = false
    }

    private func parseOptions(_ optionsString: String) -> ParsedOptions {
        var result = ParsedOptions()
        var positiveTypes: Set<ResourceType> = []
        var negativeTypes: Set<ResourceType> = []

        let options = optionsString.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

        for option in options {
            let isNegated = option.hasPrefix("~")
            let name = isNegated ? String(option.dropFirst()) : option

            // Domain option
            if name.hasPrefix("domain=") {
                let domainList = String(name.dropFirst(7))
                let (incl, excl) = parseDomainList(domainList)
                result.domains = incl.isEmpty ? nil : incl
                result.excludeDomains = excl.isEmpty ? nil : excl
                continue
            }

            // Third-party option
            if name == "third-party" || name == "3p" {
                result.thirdParty = !isNegated
                continue
            }

            if name == "first-party" || name == "1p" {
                result.thirdParty = isNegated // first-party = not third-party
                continue
            }

            // Resource type options
            if let resourceType = ResourceType.from(adblockOption: name) {
                if isNegated {
                    negativeTypes.insert(resourceType)
                } else {
                    positiveTypes.insert(resourceType)
                }
                continue
            }

            // Skip rules with options we can't handle
            // These options may appear as "option" or "option=value"
            let unsupportedOptions = [
                "csp", "redirect", "redirect-rule", "removeparam", "replace",
                "header", "method", "permissions", "important",
                "badfilter", "match-case", "denyallow", "to", "from",
                "uritransform",
            ]
            let nameLower = name.lowercased()
            let isUnsupported = unsupportedOptions.contains { unsupported in
                nameLower == unsupported || nameLower.hasPrefix(unsupported + "=")
            }
            if isUnsupported {
                result.hasUnsupportedOptions = true
            }
        }

        // Determine final resource types
        if !positiveTypes.isEmpty {
            result.resourceTypes = positiveTypes
        } else if !negativeTypes.isEmpty {
            // All types except the negated ones
            result.resourceTypes = Set(ResourceType.allCases).subtracting(negativeTypes)
        }

        return result
    }

    private func parseDomainList(_ domainList: String) -> (include: [String], exclude: [String]) {
        var include: [String] = []
        var exclude: [String] = []

        let domains = domainList.split(separator: "|").map { String($0) }
        for domain in domains {
            if domain.hasPrefix("~") {
                exclude.append(String(domain.dropFirst()))
            } else {
                include.append(domain)
            }
        }

        return (include, exclude)
    }
}
