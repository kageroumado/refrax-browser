import Foundation

/// Parsed metadata from a UserCSS file.
///
/// UserCSS is the standard format used by Userstyles.world and other style hosting sites.
/// It embeds metadata in a comment block at the start of the CSS file.
///
/// Example UserCSS format:
/// ```css
/// /* ==UserStyle==
/// @name         GitHub Dark
/// @namespace    userstyles.world
/// @version      1.0.0
/// @description  Dark theme for GitHub
/// @author       username
/// @updateURL    https://userstyles.world/api/style/123.user.css
/// ==/UserStyle== */
///
/// @-moz-document domain("github.com") {
///     body { background: #1a1a1a; }
/// }
/// ```
struct UserStyleMetadata {
    var name: String
    var namespace: String?
    var version: String?
    var description: String?
    var author: String?
    var homepageURL: URL?
    var updateURL: URL?
    var license: String?

    /// Domain rules extracted from @-moz-document directives.
    var domainRules: [DomainRule]

    /// The CSS content with @-moz-document wrappers stripped.
    var strippedCSS: String

    /// Domain/URL matching rules from @-moz-document directives.
    enum DomainRule: Equatable {
        /// Matches exact domain and subdomains: `domain("example.com")`
        case domain(String)

        /// Matches URLs starting with prefix: `url-prefix("https://example.com/path")`
        case urlPrefix(String)

        /// Matches exact URL: `url("https://example.com/specific")`
        case url(String)

        /// Matches URLs against regex: `regexp("...")`
        case regexp(String)
    }
}

// MARK: - Parser

extension UserStyleMetadata {
    /// Parses UserCSS source into metadata.
    ///
    /// Handles:
    /// - UserStyle metadata block extraction
    /// - @-moz-document directive parsing
    /// - CSS content stripping
    ///
    /// - Parameter source: Raw UserCSS file content.
    /// - Returns: Parsed metadata, or nil if not a valid UserCSS file.
    static func parse(source: String) -> UserStyleMetadata? {
        let fields = parseMetadataBlock(from: source)
        let domainRules = parseMozDocumentRules(source)
        let strippedCSS = stripMozDocumentWrappers(source)

        return UserStyleMetadata(
            name: fields["name"] ?? "Imported Style",
            namespace: fields["namespace"],
            version: fields["version"],
            description: fields["description"],
            author: fields["author"],
            homepageURL: fields["homepageurl"].flatMap(URL.init(string:)),
            updateURL: fields["updateurl"].flatMap(URL.init(string:)),
            license: fields["license"],
            domainRules: domainRules,
            strippedCSS: strippedCSS,
        )
    }

    // MARK: - Private Helpers

    private static func parseMetadataBlock(from source: String) -> [String: String] {
        let metadataPattern = #"/\*\s*==UserStyle==\s*([\s\S]*?)\s*==/UserStyle==\s*\*/"#
        guard let match = source.range(of: metadataPattern, options: .regularExpression) else {
            return [:]
        }

        var fields: [String: String] = [:]
        let block = String(source[match])

        for line in block.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let (key, value) = parseMetadataLine(trimmed) {
                fields[key.lowercased()] = value
            }
        }

        return fields
    }

    private static func parseMetadataLine(_ line: String) -> (key: String, value: String)? {
        // Match @key value pattern
        let pattern = #"^@(\w+)\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
        else {
            return nil
        }

        guard let keyRange = Range(match.range(at: 1), in: line),
              let valueRange = Range(match.range(at: 2), in: line)
        else {
            return nil
        }

        let key = String(line[keyRange])
        let value = String(line[valueRange]).trimmingCharacters(in: .whitespaces)
        return (key, value)
    }

    private static func parseMozDocumentRules(_ source: String) -> [DomainRule] {
        var rules: [DomainRule] = []

        // Pattern to match @-moz-document with its function list
        // e.g., @-moz-document domain("github.com"), url-prefix("https://gitlab.com/")
        let mozDocPattern = #"@-moz-document\s+([^{]+)"#
        guard let regex = try? NSRegularExpression(pattern: mozDocPattern) else {
            return rules
        }

        let nsRange = NSRange(source.startIndex..., in: source)
        let matches = regex.matches(in: source, range: nsRange)

        for match in matches {
            guard let range = Range(match.range(at: 1), in: source) else { continue }
            let functionList = String(source[range])
            rules.append(contentsOf: parseFunctionList(functionList))
        }

        return rules
    }

    private static func parseFunctionList(_ functionList: String) -> [DomainRule] {
        splitFunctions(functionList).compactMap { function in
            parseSingleFunction(function.trimmingCharacters(in: .whitespaces))
        }
    }

    private static func splitFunctions(_ input: String) -> [String] {
        // Split by comma, but respect parentheses
        var functions: [String] = []
        var current = ""
        var parenDepth = 0

        for char in input {
            if char == "(" {
                parenDepth += 1
                current.append(char)
            } else if char == ")" {
                parenDepth -= 1
                current.append(char)
            } else if char == ",", parenDepth == 0 {
                functions.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }

        if !current.isEmpty {
            functions.append(current)
        }

        return functions
    }

    private static func parseSingleFunction(_ function: String) -> DomainRule? {
        // Match function(argument) pattern
        let pattern = #"^(\w+(?:-\w+)?)\s*\(\s*["\']?([^"\')\s]+)["\']?\s*\)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: function, range: NSRange(function.startIndex..., in: function))
        else {
            return nil
        }

        guard let nameRange = Range(match.range(at: 1), in: function),
              let valueRange = Range(match.range(at: 2), in: function)
        else {
            return nil
        }

        let name = String(function[nameRange]).lowercased()
        let value = String(function[valueRange])

        switch name {
        case "domain":
            return .domain(value)
        case "url-prefix":
            return .urlPrefix(value)
        case "url":
            return .url(value)
        case "regexp":
            return .regexp(value)
        default:
            return nil
        }
    }

    private static func stripMozDocumentWrappers(_ source: String) -> String {
        var result = source

        // Remove UserStyle metadata block
        let metadataPattern = #"/\*\s*==UserStyle==[\s\S]*?==/UserStyle==\s*\*/"#
        result = result.replacingOccurrences(of: metadataPattern, with: "", options: .regularExpression)

        // Remove @-moz-document wrappers while keeping the CSS inside
        // Match @-moz-document ... { and closing }
        let mozDocStartPattern = #"@-moz-document\s+[^{]+\{"#
        result = result.replacingOccurrences(of: mozDocStartPattern, with: "", options: .regularExpression)

        // Remove the final closing brace that was part of @-moz-document
        // This is tricky - we need to find matched braces
        result = removeUnmatchedClosingBraces(result)

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func removeUnmatchedClosingBraces(_ css: String) -> String {
        // Count braces to find unmatched ones at the end
        var braceDepth = 0
        let chars = Array(css)
        var inString = false
        var stringChar: Character = "\""

        for (index, char) in chars.enumerated() {
            if char == "\"" || char == "'" {
                if !inString {
                    inString = true
                    stringChar = char
                } else if char == stringChar, index > 0, chars[index - 1] != "\\" {
                    inString = false
                }
            } else if !inString {
                if char == "{" {
                    braceDepth += 1
                } else if char == "}" {
                    braceDepth -= 1
                }
            }
        }

        // Remove excess closing braces from the end
        var result = css
        while braceDepth < 0 {
            if let lastBrace = result.lastIndex(of: "}") {
                result.remove(at: lastBrace)
                braceDepth += 1
            } else {
                break
            }
        }

        return result
    }
}

// MARK: - Domain Rule Conversion

extension UserStyleMetadata {
    /// Converts parsed domain rules to pattern arrays for UserStyle model.
    ///
    /// - Returns: Tuple of (domainPatterns, urlPatterns) for UserStyle.
    func convertToPatterns() -> (domains: [String], urls: [String]) {
        var domains: [String] = []
        var urls: [String] = []

        for rule in domainRules {
            switch rule {
            case let .domain(domain):
                domains.append(domain)
            case let .urlPrefix(prefix):
                urls.append(prefix + "*")
            case let .url(exactURL):
                urls.append(exactURL)
            case .regexp:
                // Regex patterns are not directly supported in our matching
                // Skip for now - could be added with NSRegularExpression support
                break
            }
        }

        return (domains, urls)
    }
}
