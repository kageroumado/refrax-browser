import Foundation

/// Content extracted from a web page using Readability.js.
///
/// Contains the article's main content, metadata, and computed properties
/// like estimated reading time. The extraction preserves HTML formatting
/// in ``content`` while providing plain text in ``textContent``.
struct ExtractedArticle: Sendable, Equatable {
    /// The article's title.
    let title: String

    /// The article's byline (author attribution).
    let byline: String?

    /// The article's main content as sanitized HTML.
    ///
    /// Contains the cleaned-up article body with images and formatting preserved.
    /// Safe to render in a WKWebView or convert to AttributedString.
    let content: String

    /// The article's main content as plain text.
    ///
    /// Useful for text-to-speech, search indexing, or simple display.
    let textContent: String

    /// A short excerpt from the article.
    let excerpt: String?

    /// The site name (e.g., "The New York Times").
    let siteName: String?

    /// The article's published date, if detected.
    let publishedTime: Date?

    /// The original URL of the article.
    let sourceURL: URL

    /// Word count of the plain text content.
    var wordCount: Int {
        textContent.split(whereSeparator: \.isWhitespace).count
    }

    /// Number of images in the article content.
    ///
    /// Counted by occurrences of `<img` tags in the HTML content.
    var imageCount: Int {
        // Count <img tags (case-insensitive)
        let pattern = "<img"
        var count = 0
        var searchRange = content.startIndex ..< content.endIndex
        while let range = content.range(of: pattern, options: .caseInsensitive, range: searchRange) {
            count += 1
            searchRange = range.upperBound ..< content.endIndex
        }
        return count
    }

    /// Estimated reading time in minutes.
    ///
    /// Uses an average reading speed of 200 words per minute,
    /// plus ~12 seconds per image for viewing time.
    var estimatedReadTime: Int {
        estimatedReadTime(wpm: 200)
    }

    /// Estimated reading time with custom words-per-minute speed.
    ///
    /// - Parameter wpm: Reading speed in words per minute.
    /// - Returns: Estimated minutes to read.
    func estimatedReadTime(wpm: Int) -> Int {
        let effectiveWPM = max(50, wpm) // Minimum 50 WPM to avoid division issues
        let readingSeconds = (wordCount * 60) / effectiveWPM
        let imageSeconds = imageCount * 12 // ~12 seconds per image
        let totalSeconds = readingSeconds + imageSeconds
        return max(1, Int(ceil(Double(totalSeconds) / 60.0)))
    }

    /// Formatted reading time string (e.g., "5 min read").
    var readTimeString: String {
        readTimeString(wpm: 200)
    }

    /// Formatted reading time string with custom WPM.
    func readTimeString(wpm: Int) -> String {
        let minutes = estimatedReadTime(wpm: wpm)
        if minutes >= 60 {
            let hours = minutes / 60
            let remainingMinutes = minutes % 60
            if remainingMinutes == 0 {
                return "\(hours) hr read"
            }
            return "\(hours) hr \(remainingMinutes) min read"
        }
        return "\(minutes) min read"
    }
}

// MARK: - JSON Decoding

extension ExtractedArticle {
    /// Creates an article from Readability.js JSON output.
    ///
    /// - Parameters:
    ///   - json: The parsed JSON dictionary from Readability.parse()
    ///   - sourceURL: The URL of the page that was extracted
    /// - Returns: An extracted article, or nil if required fields are missing
    static func from(json: [String: Any], sourceURL: URL) -> ExtractedArticle? {
        guard let title = json["title"] as? String,
              let content = json["content"] as? String,
              let textContent = json["textContent"] as? String
        else {
            return nil
        }

        // Parse published time if present
        var publishedTime: Date?
        if let timeString = json["publishedTime"] as? String {
            // Try with fractional seconds first, then without
            publishedTime = try? Date(timeString, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true))
            if publishedTime == nil {
                publishedTime = try? Date(timeString, strategy: .iso8601)
            }
        }

        return ExtractedArticle(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            byline: (json["byline"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content,
            textContent: textContent,
            excerpt: (json["excerpt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            siteName: (json["siteName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
            publishedTime: publishedTime,
            sourceURL: sourceURL,
        )
    }
}
