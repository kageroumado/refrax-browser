import Foundation

/// Content extracted from a web page using Readability.js.
///
/// Contains the article's main content, metadata, and its reading statistics. The
/// extraction preserves HTML formatting in ``content`` while providing plain text in
/// ``textContent``. The statistics are computed once, when the article is created,
/// because a long page's text runs to megabytes and views read them on every update.
nonisolated struct ExtractedArticle: Sendable, Equatable {
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

    /// Number of whitespace-separated words in ``textContent``.
    let wordCount: Int

    /// Number of `<img` tags in ``content``, matched case-insensitively.
    let imageCount: Int

    /// Creates an article and computes its statistics. Linear in the text length; create
    /// long articles off the main actor (``ReaderExtraction/decode(_:sourceURL:)``).
    init(
        title: String,
        byline: String?,
        content: String,
        textContent: String,
        excerpt: String?,
        siteName: String?,
        publishedTime: Date?,
        sourceURL: URL,
    ) {
        self.title = title
        self.byline = byline
        self.content = content
        self.textContent = textContent
        self.excerpt = excerpt
        self.siteName = siteName
        self.publishedTime = publishedTime
        self.sourceURL = sourceURL
        self.wordCount = Self.wordCount(of: textContent)
        self.imageCount = Self.imageCount(in: content)
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

// MARK: - Statistics

nonisolated extension ExtractedArticle {
    /// Counts runs of non-whitespace scalars.
    static func wordCount(of text: String) -> Int {
        var count = 0
        var isInWord = false
        for scalar in text.unicodeScalars {
            let isWhitespace = scalar.isASCII
                ? scalar == " " || (0x09 ... 0x0D).contains(scalar.value)
                : scalar.properties.isWhitespace
            if isWhitespace {
                isInWord = false
            } else if !isInWord {
                isInWord = true
                count += 1
            }
        }
        return count
    }

    /// Counts `<img` tag openings, case-insensitively, in one pass over the UTF-8 bytes.
    static func imageCount(in html: String) -> Int {
        let pattern = Array("<img".utf8)
        var count = 0
        var matched = 0
        for byte in html.utf8 {
            // ASCII letters fold to lowercase with 0x20; "<" has no case.
            let folded = (0x41 ... 0x5A).contains(byte) ? byte | 0x20 : byte
            if folded == pattern[matched] {
                matched += 1
                if matched == pattern.count {
                    count += 1
                    matched = 0
                }
            } else {
                matched = folded == pattern[0] ? 1 : 0
            }
        }
        return count
    }
}

// MARK: - Readability Output

nonisolated extension ExtractedArticle {
    /// Creates an article from Readability.js output.
    init(payload: ReaderArticlePayload, sourceURL: URL) {
        self.init(
            title: payload.title.trimmingCharacters(in: .whitespacesAndNewlines),
            byline: payload.byline?.trimmingCharacters(in: .whitespacesAndNewlines),
            content: payload.content,
            textContent: payload.textContent,
            excerpt: payload.excerpt?.trimmingCharacters(in: .whitespacesAndNewlines),
            siteName: payload.siteName?.trimmingCharacters(in: .whitespacesAndNewlines),
            publishedTime: payload.publishedTime.flatMap(Self.parseDate),
            sourceURL: sourceURL,
        )
    }

    /// Parses an ISO 8601 date, with or without fractional seconds.
    private static func parseDate(_ string: String) -> Date? {
        (try? Date(string, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
            ?? (try? Date(string, strategy: .iso8601))
    }
}

/// The fields Readability.js returns for an article, as the extraction script reports them.
nonisolated struct ReaderArticlePayload: Sendable, Equatable, Decodable {
    let title: String
    let byline: String?
    let content: String
    let textContent: String
    let excerpt: String?
    let siteName: String?
    let publishedTime: String?
}

// MARK: - Extraction Result

/// The outcome of running Readability.js on a page.
nonisolated enum ReaderExtraction: Sendable, Equatable {
    /// Readability found an article.
    case article(ExtractedArticle)
    /// The page is above ``ReaderModeManager/Limits``, or extraction ran past its timeout.
    case tooLong
    /// Readability found no article, or the script failed.
    case failed

    /// The script's JSON report: `status` is `"extracted"`, `"tooLong"`, or `"failed"`, and
    /// `article` is present with `"extracted"`.
    private struct Report: Decodable {
        let status: String
        let article: ReaderArticlePayload?
    }

    /// Decodes the extraction script's JSON report and computes the article's statistics,
    /// off the main actor: a long page's report runs to megabytes.
    @concurrent
    static func decode(_ json: String, sourceURL: URL) async -> ReaderExtraction {
        parse(json, sourceURL: sourceURL)
    }

    /// Decodes the extraction script's JSON report on the calling actor.
    static func parse(_ json: String, sourceURL: URL) -> ReaderExtraction {
        guard let report = try? JSONDecoder().decode(Report.self, from: Data(json.utf8)) else { return .failed }
        switch report.status {
        case "extracted":
            guard let payload = report.article else { return .failed }
            return .article(ExtractedArticle(payload: payload, sourceURL: sourceURL))
        case "tooLong":
            return .tooLong
        default:
            return .failed
        }
    }
}
