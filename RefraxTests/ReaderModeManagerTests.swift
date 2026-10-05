import Foundation
import SwiftUI
import Testing
@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for Reader Mode functionality.
    @Tag static var readerMode: Self
}

// MARK: - ReaderPreferences Tests

@Suite("ReaderPreferences Model", .tags(.readerMode))
@MainActor
struct ReaderPreferencesTests {
    @Test
    func `Default values are set correctly`() {
        let prefs = ReaderPreferences()

        #expect(prefs.theme == .auto)
        #expect(prefs.fontSize == 18)
        #expect(prefs.fontFamily == .system)
        #expect(prefs.lineHeight == 1.6)
        #expect(prefs.maxWidth == 680)
    }

    @Test
    func `Preferences are equatable`() {
        let prefs1 = ReaderPreferences()
        let prefs2 = ReaderPreferences()

        #expect(prefs1 == prefs2)
    }

    @Test
    func `Modified preferences differ`() {
        var prefs1 = ReaderPreferences()
        var prefs2 = ReaderPreferences()
        prefs2.fontSize = 20

        #expect(prefs1 != prefs2)

        prefs1.theme = .dark
        #expect(prefs1 != prefs2)
    }

    @Test
    func `Preferences are codable`() throws {
        var original = ReaderPreferences()
        original.theme = .sepia
        original.fontSize = 22
        original.fontFamily = .serif
        original.lineHeight = 1.8
        original.maxWidth = 720

        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ReaderPreferences.self, from: encoded)

        #expect(decoded == original)
        #expect(decoded.theme == .sepia)
        #expect(decoded.fontSize == 22)
        #expect(decoded.fontFamily == .serif)
        #expect(decoded.lineHeight == 1.8)
        #expect(decoded.maxWidth == 720)
    }
}

// MARK: - ReaderTheme Tests

@Suite("ReaderTheme Enum", .tags(.readerMode))
@MainActor
struct ReaderThemeTests {
    @Test
    func `All cases exist`() {
        let allCases = ReaderTheme.allCases
        #expect(allCases.count == 4)
        #expect(allCases.contains(.auto))
        #expect(allCases.contains(.light))
        #expect(allCases.contains(.dark))
        #expect(allCases.contains(.sepia))
    }

    @Test
    func `Display names are correct`() {
        #expect(ReaderTheme.auto.displayName == "Auto")
        #expect(ReaderTheme.light.displayName == "Light")
        #expect(ReaderTheme.dark.displayName == "Dark")
        #expect(ReaderTheme.sepia.displayName == "Sepia")
    }

    @Test
    func `Icon names are correct`() {
        #expect(ReaderTheme.auto.iconName == "circle.lefthalf.filled")
        #expect(ReaderTheme.light.iconName == "sun.max")
        #expect(ReaderTheme.dark.iconName == "moon")
        #expect(ReaderTheme.sepia.iconName == "book")
    }

    @Test
    func `Theme is codable`() throws {
        for theme in ReaderTheme.allCases {
            let encoded = try JSONEncoder().encode(theme)
            let decoded = try JSONDecoder().decode(ReaderTheme.self, from: encoded)
            #expect(decoded == theme)
        }
    }

    @Test
    func `Light theme has light background`() {
        let bgColor = ReaderTheme.light.backgroundColor(for: .light)
        #expect(bgColor == .white)
    }

    @Test
    func `Dark theme has dark background`() {
        let bgColor = ReaderTheme.dark.backgroundColor(for: .dark)
        // Dark theme uses Color(white: 0.1)
        #expect(bgColor != .white)
    }

    @Test
    func `Auto theme adapts to color scheme`() {
        let lightBg = ReaderTheme.auto.backgroundColor(for: .light)
        let darkBg = ReaderTheme.auto.backgroundColor(for: .dark)
        #expect(lightBg != darkBg)
    }

    @Test
    func `Text colors are defined for all themes`() {
        for theme in ReaderTheme.allCases {
            // Just verify they don't crash
            _ = theme.textColor(for: .light)
            _ = theme.textColor(for: .dark)
        }
    }

    @Test
    func `Link colors are defined for all themes`() {
        for theme in ReaderTheme.allCases {
            // Just verify they don't crash
            _ = theme.linkColor(for: .light)
            _ = theme.linkColor(for: .dark)
        }
    }
}

// MARK: - ReaderFont Tests

@Suite("ReaderFont Enum", .tags(.readerMode))
@MainActor
struct ReaderFontTests {
    @Test
    func `all cases exist`() {
        let allCases = ReaderFont.allCases
        #expect(allCases.count == 4)
        #expect(allCases.contains(.system))
        #expect(allCases.contains(.serif))
        #expect(allCases.contains(.sansSerif))
        #expect(allCases.contains(.mono))
    }

    @Test
    func `display names`() {
        #expect(ReaderFont.system.displayName == "System")
        #expect(ReaderFont.serif.displayName == "Serif")
        #expect(ReaderFont.sansSerif.displayName == "Sans Serif")
        #expect(ReaderFont.mono.displayName == "Monospace")
    }

    @Test
    func `CSS font families are valid strings`() {
        #expect(ReaderFont.system.cssFontFamily.contains("-apple-system"))
        #expect(ReaderFont.serif.cssFontFamily.contains("Georgia"))
        #expect(ReaderFont.sansSerif.cssFontFamily.contains("Helvetica"))
        #expect(ReaderFont.mono.cssFontFamily.contains("Menlo"))
    }

    @Test
    func `Font designs are correct`() {
        #expect(ReaderFont.system.fontDesign == .default)
        #expect(ReaderFont.serif.fontDesign == .serif)
        #expect(ReaderFont.sansSerif.fontDesign == .default)
        #expect(ReaderFont.mono.fontDesign == .monospaced)
    }

    @Test
    func `Font is codable`() throws {
        for font in ReaderFont.allCases {
            let encoded = try JSONEncoder().encode(font)
            let decoded = try JSONDecoder().decode(ReaderFont.self, from: encoded)
            #expect(decoded == font)
        }
    }
}

// MARK: - ExtractedArticle Tests

@Suite("ExtractedArticle Model", .tags(.readerMode))
@MainActor
struct ExtractedArticleTests {
    // MARK: - Helpers

    func makeArticle(
        title: String = "Test Article",
        byline: String? = "Author Name",
        content: String = "<p>Article content here.</p>",
        textContent: String = "Article content here.",
        excerpt: String? = "Short excerpt",
        siteName: String? = "Test Site",
        publishedTime: Date? = nil,
        sourceURL: URL = URL(string: "https://example.com/article")!,
    ) -> ExtractedArticle {
        ExtractedArticle(
            title: title,
            byline: byline,
            content: content,
            textContent: textContent,
            excerpt: excerpt,
            siteName: siteName,
            publishedTime: publishedTime,
            sourceURL: sourceURL,
        )
    }

    // MARK: - Tests

    @Test
    func `Word count calculates correctly`() {
        let article = makeArticle(textContent: "One two three four five")
        #expect(article.wordCount == 5)
    }

    @Test
    func `Word count handles empty content`() {
        let article = makeArticle(textContent: "")
        #expect(article.wordCount == 0)
    }

    @Test
    func `Word count handles single word`() {
        let article = makeArticle(textContent: "Hello")
        #expect(article.wordCount == 1)
    }

    @Test
    func `Word count handles multiple whitespace`() {
        let article = makeArticle(textContent: "One   two\t\tthree\n\nfour")
        #expect(article.wordCount == 4)
    }

    @Test
    func `Estimated read time for short article`() {
        // Less than 200 words should be 1 minute minimum
        let article = makeArticle(textContent: "Short article")
        #expect(article.estimatedReadTime == 1)
    }

    @Test
    func `Estimated read time for medium article`() {
        // 400 words at 200 wpm = 2 minutes
        let words = Array(repeating: "word", count: 400).joined(separator: " ")
        let article = makeArticle(textContent: words)
        #expect(article.estimatedReadTime == 2)
    }

    @Test
    func `Estimated read time for long article`() {
        // 1000 words at 200 wpm = 5 minutes
        let words = Array(repeating: "word", count: 1_000).joined(separator: " ")
        let article = makeArticle(textContent: words)
        #expect(article.estimatedReadTime == 5)
    }

    @Test
    func `Read time string format`() {
        let article = makeArticle(textContent: "Short")
        #expect(article.readTimeString == "1 min read")

        let words = Array(repeating: "word", count: 600).joined(separator: " ")
        let longerArticle = makeArticle(textContent: words)
        #expect(longerArticle.readTimeString == "3 min read")
    }

    @Test
    func `All properties are accessible`() throws {
        let date = Date()
        let url = try #require(URL(string: "https://example.com/test"))

        let article = makeArticle(
            title: "My Title",
            byline: "John Doe",
            content: "<p>HTML content</p>",
            textContent: "Plain text",
            excerpt: "An excerpt",
            siteName: "My Site",
            publishedTime: date,
            sourceURL: url,
        )

        #expect(article.title == "My Title")
        #expect(article.byline == "John Doe")
        #expect(article.content == "<p>HTML content</p>")
        #expect(article.textContent == "Plain text")
        #expect(article.excerpt == "An excerpt")
        #expect(article.siteName == "My Site")
        #expect(article.publishedTime == date)
        #expect(article.sourceURL == url)
    }

    @Test
    func `Optional fields can be nil`() {
        let article = makeArticle(
            byline: nil,
            excerpt: nil,
            siteName: nil,
            publishedTime: nil,
        )

        #expect(article.byline == nil)
        #expect(article.excerpt == nil)
        #expect(article.siteName == nil)
        #expect(article.publishedTime == nil)
    }
}

// MARK: - ExtractedArticle JSON Parsing Tests

@Suite("Reader Extraction Report", .tags(.readerMode))
struct ReaderExtractionReportTests {
    let url = URL(string: "https://example.com/article")!

    /// An `"extracted"` report wrapping the given article fields.
    func extractedReport(_ article: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: ["status": "extracted", "article": article])
        return String(decoding: data, as: UTF8.self)
    }

    func article(from report: String) -> ExtractedArticle? {
        guard case let .article(article) = ReaderExtraction.parse(report, sourceURL: url) else { return nil }
        return article
    }

    @Test
    func `Extracted report with all fields`() throws {
        let article = try #require(article(from: extractedReport([
            "title": "Test Article",
            "byline": "John Doe",
            "content": "<p>Content</p>",
            "textContent": "Content",
            "excerpt": "An excerpt",
            "siteName": "Test Site",
            "publishedTime": "2024-01-15T10:30:00Z",
        ])))

        #expect(article.title == "Test Article")
        #expect(article.byline == "John Doe")
        #expect(article.content == "<p>Content</p>")
        #expect(article.textContent == "Content")
        #expect(article.excerpt == "An excerpt")
        #expect(article.siteName == "Test Site")
        #expect(article.publishedTime != nil)
        #expect(article.sourceURL == url)
    }

    @Test
    func `Extracted report with null optional fields`() throws {
        let article = try #require(article(from: extractedReport([
            "title": "Minimal Article",
            "byline": NSNull(),
            "content": "<p>Content</p>",
            "textContent": "Content",
        ])))

        #expect(article.title == "Minimal Article")
        #expect(article.byline == nil)
        #expect(article.excerpt == nil)
        #expect(article.siteName == nil)
        #expect(article.publishedTime == nil)
    }

    @Test(arguments: ["title", "content", "textContent"])
    func `Extracted report missing a required field fails`(field: String) throws {
        var fields: [String: Any] = ["title": "Title", "content": "<p>C</p>", "textContent": "C"]
        fields.removeValue(forKey: field)
        #expect(try ReaderExtraction.parse(extractedReport(fields), sourceURL: url) == .failed)
    }

    @Test
    func `Extracted report without an article fails`() {
        #expect(ReaderExtraction.parse(#"{"status":"extracted"}"#, sourceURL: url) == .failed)
    }

    @Test
    func `Too-long report`() {
        #expect(ReaderExtraction.parse(#"{"status":"tooLong"}"#, sourceURL: url) == .tooLong)
    }

    @Test(arguments: [
        #"{"status":"failed"}"#,
        #"{"status":"somethingElse"}"#,
        "not json",
        "",
    ])
    func `Failed, unknown, and malformed reports fail`(report: String) {
        #expect(ReaderExtraction.parse(report, sourceURL: url) == .failed)
    }

    @Test
    func `Decoding off the main actor matches parsing`() async throws {
        let report = try extractedReport(["title": "T", "content": "<img src=a>", "textContent": "one two"])
        let decoded = await ReaderExtraction.decode(report, sourceURL: url)
        #expect(decoded == ReaderExtraction.parse(report, sourceURL: url))
    }

    @Test(arguments: [
        "2024-06-15T14:30:45.123Z",
        "2024-06-15T14:30:45Z",
    ])
    func `ISO 8601 dates with and without fractional seconds`(date: String) throws {
        let article = try #require(article(from: extractedReport([
            "title": "Test", "content": "<p>C</p>", "textContent": "C", "publishedTime": date,
        ])))
        #expect(article.publishedTime != nil)
    }

    @Test
    func `Invalid date string leaves the published time empty`() throws {
        let article = try #require(article(from: extractedReport([
            "title": "Test", "content": "<p>C</p>", "textContent": "C", "publishedTime": "not-a-date",
        ])))
        #expect(article.publishedTime == nil)
    }

    @Test
    func `Strings are trimmed`() throws {
        let article = try #require(article(from: extractedReport([
            "title": "  Spaced Title  ",
            "content": "<p>C</p>",
            "textContent": "C",
            "byline": "  Spaced Author  ",
            "excerpt": "  Spaced Excerpt  ",
            "siteName": "  Spaced Site  ",
        ])))

        #expect(article.title == "Spaced Title")
        #expect(article.byline == "Spaced Author")
        #expect(article.excerpt == "Spaced Excerpt")
        #expect(article.siteName == "Spaced Site")
    }
}

// MARK: - Statistics Tests

@Suite("ExtractedArticle Statistics", .tags(.readerMode))
struct ExtractedArticleStatisticsTests {
    @Test(arguments: [
        ("", 0),
        ("   ", 0),
        ("one", 1),
        ("one two", 2),
        ("  leading and trailing  ", 3),
        ("tabs\tand\r\nnewlines\u{0B}vt\u{0C}ff", 5),
        ("no\u{00A0}break\u{2003}em\u{3000}ideographic", 4),
        ("日本語 テキスト", 2),
        ("emoji 👨‍👩‍👧 family", 3),
    ])
    func `Word count splits on Unicode whitespace`(text: String, expected: Int) {
        #expect(ExtractedArticle.wordCount(of: text) == expected)
    }

    @Test
    func `Word count agrees with splitting on whitespace characters`() {
        let text = String(repeating: "Lorem ipsum\u{2028}dolor\n\tsit amet,  consectetur ", count: 200)
        #expect(ExtractedArticle.wordCount(of: text) == text.split(whereSeparator: \.isWhitespace).count)
    }

    @Test(arguments: [
        ("", 0),
        ("<p>no images</p>", 0),
        ("<img src=a>", 1),
        ("<IMG src=a><Img src=b><iMg src=c>", 3),
        ("<<img src=a>", 1),
        ("<i<img src=a>", 1),
        ("<image>", 0),
        ("<im g>", 0),
        ("<p>é</p><img src=ü>", 1),
    ])
    func `Image count matches <img case-insensitively`(html: String, expected: Int) {
        #expect(ExtractedArticle.imageCount(in: html) == expected)
    }

    @Test
    func `Statistics are computed when the article is created`() throws {
        let article = try ExtractedArticle(
            title: "T",
            byline: nil,
            content: "<p>a</p><img src=x><img src=y>",
            textContent: "three little words",
            excerpt: nil,
            siteName: nil,
            publishedTime: nil,
            sourceURL: #require(URL(string: "https://example.com")),
        )
        #expect(article.wordCount == 3)
        #expect(article.imageCount == 2)
    }
}

// MARK: - ReaderModeEvent Tests

@Suite("ReaderModeEvent Parsing", .tags(.readerMode))
@MainActor
struct ReaderModeEventTests {
    @Test
    func `Availability message parses`() {
        let event = ReaderModeEvent(.object([
            "type": .string("availability"),
            "url": .string("https://example.com"),
            "available": .bool(true),
        ]))

        guard case let .availability(url, available) = event else {
            Issue.record("Expected availability event")
            return
        }
        #expect(url == "https://example.com")
        #expect(available)
    }

    @Test
    func `Unknown message types are ignored`() {
        let event = ReaderModeEvent(.object([
            "type": .string("extracted"),
            "url": .string("https://example.com"),
        ]))
        #expect(event == nil)
    }
}
