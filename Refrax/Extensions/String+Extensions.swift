import Foundation

extension String {
    /// Escapes a string for safe use in JavaScript string literals.
    ///
    /// Handles both single and double quoted strings by escaping:
    /// - Backslashes
    /// - Single quotes
    /// - Double quotes
    /// - Newlines, carriage returns, and tabs
    ///
    /// - Parameter quoteStyle: The quote style to optimize for (single or double).
    ///   When nil, escapes both quote types for maximum compatibility.
    /// - Returns: The escaped string safe for JavaScript interpolation.
    func escapedForJS(quoteStyle: JSQuoteStyle? = nil) -> String {
        var result = replacingOccurrences(of: "\\", with: "\\\\")

        switch quoteStyle {
        case .single:
            result = result.replacingOccurrences(of: "'", with: "\\'")
        case .double:
            result = result.replacingOccurrences(of: "\"", with: "\\\"")
        case nil:
            result = result.replacingOccurrences(of: "'", with: "\\'")
            result = result.replacingOccurrences(of: "\"", with: "\\\"")
        }

        result = result.replacingOccurrences(of: "\n", with: "\\n")
        result = result.replacingOccurrences(of: "\r", with: "\\r")
        result = result.replacingOccurrences(of: "\t", with: "\\t")

        return result
    }
}

/// Quote style for JavaScript string escaping.
enum JSQuoteStyle {
    /// Single quotes: 'string'
    case single
    /// Double quotes: "string"
    case double
}
