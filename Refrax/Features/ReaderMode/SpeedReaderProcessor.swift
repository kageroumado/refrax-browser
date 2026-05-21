import Foundation

/// A single word in the Speed Reader stream with its associated pause multiplier.
struct SpeedReaderWord: Sendable {
    let text: String

    /// Pause multiplier applied after displaying this word.
    ///
    /// - 1.0: Normal pace
    /// - 1.3: Long words (12+ characters)
    /// - 1.5: After comma, semicolon, colon
    /// - 2.0: After period, question mark, exclamation
    /// - 3.0: After paragraph break
    let pauseMultiplier: Double

    /// The Optimal Recognition Point index (approximately 30% into the word).
    ///
    /// This is where the eye should focus for fastest recognition.
    var orpIndex: Int {
        let letters = text.filter(\.isLetter)
        guard !letters.isEmpty else { return 0 }
        // ORP is typically at ~30% into the word, with a minimum of 1st character
        return max(0, Int(Double(letters.count) * 0.3) - 1)
    }
}

/// Processes text content into a sequence of words optimized for RSVP display.
///
/// Handles tokenization, punctuation detection, and pause timing. The processor
/// normalizes whitespace, preserves hyphenated words, and assigns appropriate
/// pause multipliers based on punctuation and word length.
enum SpeedReaderProcessor {
    // MARK: - Pause Multipliers

    private enum Pause {
        static let normal: Double = 1.0
        static let longWord: Double = 1.3 // 12+ characters
        static let comma: Double = 1.5 // , ; :
        static let sentence: Double = 2.0 // . ? !
        static let paragraph: Double = 3.0 // Double newline
    }

    private static let longWordThreshold = 12

    // MARK: - Processing

    /// Processes plain text content into Speed Reader words.
    ///
    /// - Parameter content: Plain text content (typically from ExtractedArticle.textContent)
    /// - Returns: Array of words with pause multipliers for RSVP display
    static func process(_ content: String) -> [SpeedReaderWord] {
        // Split by paragraph breaks (2+ newlines)
        let paragraphs = content.components(separatedBy: .newlines)
            .split(whereSeparator: \.isEmpty)
            .map { $0.joined(separator: " ") }

        var words: [SpeedReaderWord] = []

        for (paragraphIndex, paragraph) in paragraphs.enumerated() {
            let isLastParagraph = paragraphIndex == paragraphs.count - 1
            let paragraphWords = processParagraph(paragraph, isLast: isLastParagraph)
            words.append(contentsOf: paragraphWords)
        }

        return words
    }

    private static func processParagraph(_ paragraph: String, isLast: Bool) -> [SpeedReaderWord] {
        let tokens = paragraph.split(whereSeparator: \.isWhitespace).map(String.init)

        return tokens.enumerated().map { index, token in
            processToken(token, isLastInParagraph: index == tokens.count - 1, isLastParagraph: isLast)
        }
    }

    private static func processToken(_ token: String, isLastInParagraph: Bool, isLastParagraph: Bool) -> SpeedReaderWord {
        let displayText = token.trimmingCharacters(in: .punctuationCharacters)
        let cleanDisplayText = displayText.isEmpty ? token : displayText

        var multiplier: Double = switch token.last {
        case ".", "!", "?": Pause.sentence
        case ",", ";", ":": Pause.comma
        default: Pause.normal
        }

        if isLastInParagraph, !isLastParagraph {
            multiplier = max(multiplier, Pause.paragraph)
        }

        if cleanDisplayText.count >= longWordThreshold {
            multiplier = max(multiplier, Pause.longWord)
        }

        return SpeedReaderWord(text: cleanDisplayText, pauseMultiplier: multiplier)
    }

    // MARK: - Utility

    /// Calculates the total estimated reading time for processed words at a given WPM.
    ///
    /// - Parameters:
    ///   - words: Processed Speed Reader words
    ///   - wpm: Words per minute
    /// - Returns: Estimated duration in seconds, accounting for pause multipliers
    static func estimatedDuration(for words: [SpeedReaderWord], at wpm: Int) -> TimeInterval {
        guard wpm > 0 else { return 0 }

        let baseInterval = 60.0 / Double(wpm)
        let totalMultiplier = words.reduce(0.0) { $0 + $1.pauseMultiplier }

        return baseInterval * totalMultiplier
    }
}
