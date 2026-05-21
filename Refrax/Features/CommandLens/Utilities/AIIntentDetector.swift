import Foundation

/// Detects whether user input appears to be an AI query.
///
/// Uses heuristics to identify natural language questions that should
/// be routed to the AI assistant rather than treated as search/URL.
enum AIIntentDetector {
    // MARK: - Detection

    /// Checks if the input appears to be an AI query.
    ///
    /// Returns `true` for:
    /// - Explicit AI triggers ("@ai", "ai:", "ask:")
    /// - Question words at start ("what", "why", "how", "explain", etc.)
    /// - Modal verb phrases ("can you", "would you", "should I", etc.)
    /// - Natural language questions (4+ words without URL-like patterns)
    /// - Questions ending with "?" (10+ characters)
    ///
    /// - Parameter input: The user's input text.
    /// - Returns: `true` if the input looks like an AI query.
    static func isAIIntent(_ input: String) -> Bool {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        guard !trimmed.isEmpty else { return false }

        // Explicit AI triggers
        if hasExplicitTrigger(trimmed) {
            return true
        }

        // Question patterns and modal verbs
        if hasQuestionPattern(trimmed) {
            return true
        }

        // Natural language heuristic: 4+ words that don't look like a URL/search
        if looksLikeNaturalLanguage(trimmed) {
            return true
        }

        return false
    }

    /// Extracts the actual query from an AI-intent input.
    ///
    /// Removes explicit triggers like "@ai" or "ai:" prefix.
    ///
    /// - Parameter input: The user's input text.
    /// - Returns: The cleaned query text.
    static func extractQuery(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()

        // Remove explicit triggers
        for trigger in explicitTriggers {
            if lowercased.hasPrefix(trigger) {
                let startIndex = trimmed.index(trimmed.startIndex, offsetBy: trigger.count)
                return String(trimmed[startIndex...]).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return trimmed
    }

    // MARK: - Private

    /// Explicit AI trigger prefixes.
    private static let explicitTriggers = [
        "@ai ",
        "ai: ",
        "ai:",
        "ask ",
        "ask: ",
    ]

    /// Question word patterns that indicate AI intent.
    private static let questionPatterns = [
        // Interrogative words
        "what ",
        "what's ",
        "what is ",
        "what are ",
        "why ",
        "why is ",
        "why does ",
        "how ",
        "how do ",
        "how does ",
        "how can ",
        "how to ",
        "where ",
        "where is ",
        "where can ",
        "when ",
        "when did ",
        "when does ",
        "which ",
        "who ",
        "who is ",

        // Modal verb phrases
        "can you ",
        "could you ",
        "would you ",
        "will you ",
        "should i ",
        "should we ",
        "do you ",
        "is there ",
        "is it ",
        "are there ",

        // Imperative requests
        "explain ",
        "summarize ",
        "summarise ",
        "tell me ",
        "help me ",
        "show me ",
        "find me ",
        "give me ",
        "list ",
        "describe ",
        "compare ",
        "analyze ",
        "analyse ",
        "translate ",
        "define ",
    ]

    private static func hasExplicitTrigger(_ input: String) -> Bool {
        for trigger in explicitTriggers {
            if input.hasPrefix(trigger) || input == trigger.trimmingCharacters(in: .whitespaces) {
                return true
            }
        }
        return false
    }

    private static func hasQuestionPattern(_ input: String) -> Bool {
        for pattern in questionPatterns {
            if input.hasPrefix(pattern) {
                return true
            }
        }

        // Ends with a question mark and is long enough
        if input.hasSuffix("?"), input.count > 10 {
            return true
        }

        return false
    }

    /// Detects natural language input that's likely a question or request
    /// even without a recognized prefix pattern.
    ///
    /// Triggers when: 4+ words, no URL-like patterns (dots, slashes, colons).
    /// This catches inputs like "make the background blue" or
    /// "I need help with something" that don't start with question words.
    private static func looksLikeNaturalLanguage(_ input: String) -> Bool {
        let words = input.split(separator: " ", omittingEmptySubsequences: true)
        guard words.count >= 4 else { return false }

        // Exclude URL-like patterns: contains dots between non-space chars,
        // protocol prefixes, or path separators
        if input.contains("://") || input.contains("www.") {
            return false
        }

        // Exclude inputs that look like domain names (word.word pattern)
        // but allow normal sentences with periods at the end
        let withoutTrailingPunct = input.trimmingCharacters(in: CharacterSet(charactersIn: ".!?"))
        if withoutTrailingPunct.contains(".") {
            // Could be a URL like "github.com something something something"
            let firstWord = String(words[0])
            if firstWord.contains(".") {
                return false
            }
        }

        return true
    }
}
