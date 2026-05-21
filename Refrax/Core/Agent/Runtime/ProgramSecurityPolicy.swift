import Foundation
import RefraxProtocol

// MARK: - Security Violation

/// A security policy violation detected during static analysis of a program.
struct SecurityViolation: Sendable {
    /// The category of violation.
    let kind: Kind
    /// A human-readable description of the violation.
    let message: String
    /// The source line number where the violation was found, if applicable.
    let line: Int?

    /// Categories of security violations that the static analyzer can detect.
    enum Kind: Sendable {
        case navigationLimitExceeded
        case interactionLimitExceeded
        case pageReadLimitExceeded
        case javaScriptDisallowed
        case blockedDomain
        case domainNotAllowed
    }
}

// MARK: - Static Analyzer

/// Static analyzer that validates programs against security policies before execution.
nonisolated enum ProgramSecurityAnalyzer {
    /// Validates a program against a security policy.
    /// Returns an array of violations (empty = valid).
    static func validate(program: String, policy: ProgramSecurityPolicy) -> [SecurityViolation] {
        let lines = program.components(separatedBy: .newlines)
        var violations: [SecurityViolation] = []

        var navigationCount = 0
        var interactionCount = 0
        var pageReadCount = 0

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let lineNumber = index + 1

            if trimmed.hasPrefix("navigate ") || trimmed.hasPrefix("go_back") || trimmed.hasPrefix("go_forward") {
                navigationCount += 1
            }

            if trimmed.hasPrefix("click ") || trimmed.hasPrefix("type ")
                || trimmed.hasPrefix("fill ") || trimmed.hasPrefix("hover ")
                || trimmed.hasPrefix("select ") || trimmed.hasPrefix("fill_form")
                || trimmed.hasPrefix("press_key ") || trimmed.hasPrefix("request_human ")
                || trimmed.hasPrefix("dismiss_cookies") {
                interactionCount += 1
            }

            if trimmed.contains("read_page") || trimmed.hasPrefix("screenshot") {
                pageReadCount += 1
            }

            if !policy.allowJavaScript, trimmed.hasPrefix("page_exec ") {
                violations.append(SecurityViolation(
                    kind: .javaScriptDisallowed,
                    message: "JavaScript execution is not allowed by policy",
                    line: lineNumber,
                ))
            }

            if trimmed.hasPrefix("navigate ") {
                if let url = extractStaticURL(from: trimmed) {
                    checkDomainPolicy(url: url, policy: policy, line: lineNumber, violations: &violations)
                }
            }
        }

        if navigationCount > policy.maxNavigations {
            violations.append(SecurityViolation(
                kind: .navigationLimitExceeded,
                message: "Program has \(navigationCount) navigations, limit is \(policy.maxNavigations)",
                line: nil,
            ))
        }

        if interactionCount > policy.maxInteractions {
            violations.append(SecurityViolation(
                kind: .interactionLimitExceeded,
                message: "Program has \(interactionCount) interactions, limit is \(policy.maxInteractions)",
                line: nil,
            ))
        }

        if pageReadCount > policy.maxPageReads {
            violations.append(SecurityViolation(
                kind: .pageReadLimitExceeded,
                message: "Program has \(pageReadCount) page reads, limit is \(policy.maxPageReads)",
                line: nil,
            ))
        }

        return violations
    }

    // MARK: - Private Helpers

    /// Extracts a static URL from a `navigate` command line, skipping variable references.
    private static func extractStaticURL(from line: String) -> String? {
        let remainder = line.dropFirst("navigate ".count).trimmingCharacters(in: .whitespaces)

        if remainder.hasPrefix("\"") {
            let inner = remainder.dropFirst()
            if let endQuote = inner.firstIndex(of: "\"") {
                return String(inner[inner.startIndex ..< endQuote])
            }
        }

        let url = remainder.prefix(while: { !$0.isWhitespace })
        if url.hasPrefix("$") { return nil }

        return url.isEmpty ? nil : String(url)
    }

    /// Checks a URL against domain allow/block lists.
    private static func checkDomainPolicy(
        url urlString: String,
        policy: ProgramSecurityPolicy,
        line: Int,
        violations: inout [SecurityViolation],
    ) {
        guard let url = URL(string: urlString), let host = url.host else { return }

        if let blockedDomains = policy.blockedDomains {
            if blockedDomains.contains(where: { host.hasSuffix($0) }) {
                violations.append(SecurityViolation(
                    kind: .blockedDomain,
                    message: "Domain '\(host)' is blocked by policy",
                    line: line,
                ))
            }
        }

        if let allowedDomains = policy.allowedDomains {
            if !allowedDomains.contains(where: { host.hasSuffix($0) }) {
                violations.append(SecurityViolation(
                    kind: .domainNotAllowed,
                    message: "Domain '\(host)' is not in the allowed domain list",
                    line: line,
                ))
            }
        }
    }
}

// MARK: - Sensitive Field Detection

/// Detects whether a form field is sensitive (password, credit card, SSN, etc.).
nonisolated enum SensitiveFieldDetector {
    private nonisolated(unsafe) static let sensitivePatterns: [Regex<Substring>] = {
        let patterns = [
            "password", "passwd", "secret",
            "credit.?card", "cc.?num", "card.?number",
            "cvv", "cvc", "csc",
            "ssn", "social.?security",
            "routing.?number", "account.?number",
        ]
        return patterns.compactMap { try? Regex<Substring>($0) }
    }()

    /// Checks if an element handle represents a sensitive field.
    static func isSensitive(_ element: ElementHandle) -> Bool {
        if element.inputType?.lowercased() == "password" { return true }

        let fieldsToCheck = [
            element.text.lowercased(),
            element.role?.lowercased(),
            element.value?.lowercased(),
            element.ref.lowercased(),
        ].compactMap(\.self).joined(separator: " ")

        return sensitivePatterns.contains { fieldsToCheck.contains($0) }
    }
}
