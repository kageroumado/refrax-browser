import Foundation

/// Provides fuzzy string matching for natural language command recognition.
///
/// Uses multiple matching strategies in order of preference:
/// 1. Exact match (score 1.0)
/// 2. Prefix match (score 0.9)
/// 3. Contains match (score 0.7)
/// 4. Levenshtein distance (score 0.5 for close matches)
/// 5. No match (score 0.0)
enum FuzzyMatcher {
    /// Minimum score threshold for a match to be considered valid.
    static let minimumMatchScore: Double = 0.4

    /// Maximum Levenshtein distance for short words (< 8 chars).
    static let maxDistanceShort = 2

    /// Maximum Levenshtein distance for longer words.
    static let maxDistanceLong = 3

    /// Matches a query against an array of candidate terms.
    ///
    /// Returns the highest score found across all candidates.
    ///
    /// - Parameters:
    ///   - query: The user's input text.
    ///   - terms: Array of terms to match against (e.g., setting name + synonyms).
    /// - Returns: The best match score (0.0 to 1.0).
    static func match(query: String, against terms: [String]) -> Double {
        guard !query.isEmpty else { return 0.0 }

        let normalizedQuery = query.lowercased().trimmingCharacters(in: .whitespaces)

        var bestScore = 0.0

        for term in terms {
            let normalizedTerm = term.lowercased().trimmingCharacters(in: .whitespaces)
            let score = matchSingle(query: normalizedQuery, term: normalizedTerm)
            bestScore = max(bestScore, score)
        }

        return bestScore
    }

    /// Matches a single query against a single term.
    private static func matchSingle(query: String, term: String) -> Double {
        // 1. Exact match
        if query == term {
            return 1.0
        }

        // 2. Prefix match (query is prefix of term, or term is prefix of query)
        if term.hasPrefix(query) || query.hasPrefix(term) {
            // Score based on how much of the term is matched
            let matchRatio = Double(min(query.count, term.count)) / Double(max(query.count, term.count))
            return 0.8 + (0.1 * matchRatio)
        }

        // 3. Contains match
        if term.contains(query) {
            // Score based on position and length ratio
            let lengthRatio = Double(query.count) / Double(term.count)
            return 0.6 + (0.1 * lengthRatio)
        }

        // 4. Word-by-word prefix matching
        let queryWords = query.split(separator: " ")
        let termWords = term.split(separator: " ")

        if queryWords.count > 1 || termWords.count > 1 {
            var matchedWords = 0
            for queryWord in queryWords {
                for termWord in termWords {
                    if termWord.hasPrefix(queryWord) || queryWord.hasPrefix(termWord) {
                        matchedWords += 1
                        break
                    }
                }
            }

            if matchedWords == queryWords.count {
                let ratio = Double(matchedWords) / Double(max(queryWords.count, termWords.count))
                return 0.5 + (0.3 * ratio)
            }
        }

        // 5. Levenshtein distance for typo tolerance
        let distance = levenshteinDistance(query, term)
        let maxDistance = query.count < 8 ? maxDistanceShort : maxDistanceLong

        if distance <= maxDistance {
            // Score inversely proportional to distance
            let normalizedDistance = Double(distance) / Double(maxDistance + 1)
            return 0.5 * (1.0 - normalizedDistance)
        }

        return 0.0
    }

    /// Computes the Levenshtein edit distance between two strings.
    ///
    /// - Parameters:
    ///   - s1: First string.
    ///   - s2: Second string.
    /// - Returns: The minimum number of single-character edits needed.
    static func levenshteinDistance(_ s1: String, _ s2: String) -> Int {
        let s1Array = Array(s1)
        let s2Array = Array(s2)

        let m = s1Array.count
        let n = s2Array.count

        // Early termination for empty strings
        if m == 0 { return n }
        if n == 0 { return m }

        // Early termination if strings are too different in length
        if abs(m - n) > max(maxDistanceShort, maxDistanceLong) {
            return max(m, n)
        }

        // Use two rows instead of full matrix for space efficiency
        var previousRow = [Int](0 ... n)
        var currentRow = [Int](repeating: 0, count: n + 1)

        for i in 1 ... m {
            currentRow[0] = i

            for j in 1 ... n {
                let cost = s1Array[i - 1] == s2Array[j - 1] ? 0 : 1
                currentRow[j] = min(
                    currentRow[j - 1] + 1, // Insertion
                    previousRow[j] + 1, // Deletion
                    previousRow[j - 1] + cost, // Substitution
                )
            }

            swap(&previousRow, &currentRow)
        }

        return previousRow[n]
    }
}
