import Foundation

/// Injects `!important` into CSS declarations to ensure user styles override site CSS.
///
/// User styles should always win against site styles. Rather than requiring users
/// to manually add `!important` to every declaration, this processor adds it automatically.
///
/// ## Handling
///
/// - Adds `!important` to regular declarations
/// - Preserves existing `!important` (no duplication)
/// - Skips `@keyframes` (where !important is invalid)
/// - Preserves `@font-face`, `@media`, `@supports` structure
/// - Handles complex values (calc, gradients, var())
///
/// ## Usage
///
/// ```swift
/// let injector = CSSImportantInjector()
/// let processed = injector.process("body { color: red; }")
/// // Result: "body { color: red !important; }"
/// ```
struct CSSImportantInjector {
    /// Processes CSS to add `!important` to all declarations.
    ///
    /// - Parameter css: Raw CSS content.
    /// - Returns: CSS with `!important` added to declarations.
    func process(_ css: String) -> String {
        guard !css.isEmpty else { return css }

        var result = ""
        var index = css.startIndex
        var inKeyframes = false
        var keyframesBraceDepth = 0

        while index < css.endIndex {
            // Check for @keyframes start
            if isAtKeyframes(css, at: index) {
                inKeyframes = true
                keyframesBraceDepth = 0
            }

            // Track brace depth in keyframes
            if inKeyframes {
                if css[index] == "{" {
                    keyframesBraceDepth += 1
                } else if css[index] == "}" {
                    keyframesBraceDepth -= 1
                    if keyframesBraceDepth == 0 {
                        inKeyframes = false
                    }
                }
            }

            // Find the next declaration (property: value;)
            if let declarationRange = findDeclaration(css, from: index) {
                // Copy everything before the declaration
                result += String(css[index ..< declarationRange.lowerBound])

                // Process the declaration
                let declaration = String(css[declarationRange])
                if inKeyframes {
                    // Don't add !important inside @keyframes
                    result += declaration
                } else {
                    result += processDeclaration(declaration)
                }

                index = declarationRange.upperBound
            } else {
                // No more declarations, copy the rest
                result += String(css[index...])
                break
            }
        }

        return result
    }

    // MARK: - Private Helpers

    private func isAtKeyframes(_ css: String, at index: String.Index) -> Bool {
        let remaining = css[index...]
        return remaining.hasPrefix("@keyframes") || remaining.hasPrefix("@-webkit-keyframes")
    }

    /// Finds the next CSS declaration (property: value;) in the string.
    private func findDeclaration(_ css: String, from start: String.Index) -> Range<String.Index>? {
        var index = start
        var colonIndex: String.Index?
        var inString = false
        var stringChar: Character = "\""
        var parenDepth = 0
        var braceDepth = 0

        while index < css.endIndex {
            let char = css[index]

            // Handle strings
            if char == "\"" || char == "'" {
                if !inString {
                    inString = true
                    stringChar = char
                } else if char == stringChar {
                    // Check for escape
                    let prevIndex = css.index(before: index)
                    if prevIndex >= css.startIndex, css[prevIndex] != "\\" {
                        inString = false
                    }
                }
            } else if !inString {
                // Track nesting
                if char == "(" {
                    parenDepth += 1
                } else if char == ")" {
                    parenDepth = max(0, parenDepth - 1)
                } else if char == "{" {
                    braceDepth += 1
                    colonIndex = nil // Reset on entering new block
                } else if char == "}" {
                    braceDepth = max(0, braceDepth - 1)
                    colonIndex = nil
                } else if char == ":", parenDepth == 0, braceDepth > 0 {
                    // Found property: (only inside braces, not in selectors)
                    colonIndex = index
                } else if char == ";", colonIndex != nil {
                    // Found end of declaration
                    return colonIndex! ..< css.index(after: index)
                }
            }

            index = css.index(after: index)
        }

        return nil
    }

    /// Processes a single declaration to add !important.
    private func processDeclaration(_ declaration: String) -> String {
        if declaration.lowercased().contains("!important") {
            return declaration
        }

        guard let semicolonIndex = declaration.lastIndex(of: ";") else {
            return declaration
        }

        let value = declaration[..<semicolonIndex].trimmingCharacters(in: .whitespaces)
        return value + " !important;"
    }
}

// MARK: - CSS Escaping for JavaScript Injection

extension CSSImportantInjector {
    /// Escapes CSS for embedding in JavaScript template literals.
    ///
    /// Handles characters that would break template literal syntax:
    /// - Backslashes are doubled
    /// - Backticks are escaped
    /// - Dollar signs are escaped (prevent template substitution)
    ///
    /// - Parameter css: Processed CSS content.
    /// - Returns: CSS safe for JavaScript template literal injection.
    static func escapeForJavaScript(_ css: String) -> String {
        css
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "$", with: "\\$")
    }
}
