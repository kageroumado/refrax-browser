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
    @Test("Default values are set correctly")
    func defaultValues() {
        let prefs = ReaderPreferences()

        #expect(prefs.theme == .auto)
        #expect(prefs.fontSize == 18)
        #expect(prefs.fontFamily == .system)
        #expect(prefs.lineHeight == 1.6)
        #expect(prefs.maxWidth == 680)
    }

    @Test("Preferences are equatable")
    func equatable() {
        let prefs1 = ReaderPreferences()
        let prefs2 = ReaderPreferences()

        #expect(prefs1 == prefs2)
    }

    @Test("Modified preferences differ")
    func modifiedDiffer() {
        var prefs1 = ReaderPreferences()
        var prefs2 = ReaderPreferences()
        prefs2.fontSize = 20

        #expect(prefs1 != prefs2)

        prefs1.theme = .dark
        #expect(prefs1 != prefs2)
    }

    @Test("Preferences are codable")
    func codable() throws {
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
    @Test("All cases exist")
    func allCasesExist() {
        let allCases = ReaderTheme.allCases
        #expect(allCases.count == 4)
        #expect(allCases.contains(.auto))
        #expect(allCases.contains(.light))
        #expect(allCases.contains(.dark))
        #expect(allCases.contains(.sepia))
    }

    @Test("Display names are correct")
    func displayNames() {
        #expect(ReaderTheme.auto.displayName == "Auto")
        #expect(ReaderTheme.light.displayName == "Light")
        #expect(ReaderTheme.dark.displayName == "Dark")
        #expect(ReaderTheme.sepia.displayName == "Sepia")
    }

    @Test("Icon names are correct")
    func iconNames() {
        #expect(ReaderTheme.auto.iconName == "circle.lefthalf.filled")
        #expect(ReaderTheme.light.iconName == "sun.max")
        #expect(ReaderTheme.dark.iconName == "moon")
        #expect(ReaderTheme.sepia.iconName == "book")
    }

    @Test("Theme is codable")
    func codable() throws {
        for theme in ReaderTheme.allCases {
            let encoded = try JSONEncoder().encode(theme)
            let decoded = try JSONDecoder().decode(ReaderTheme.self, from: encoded)
            #expect(decoded == theme)
        }
    }

    @Test("Light theme has light background")
    func lightThemeBackground() {
        let bgColor = ReaderTheme.light.backgroundColor(for: .light)
        #expect(bgColor == .white)
    }

    @Test("Dark theme has dark background")
    func darkThemeBackground() {
        let bgColor = ReaderTheme.dark.backgroundColor(for: .dark)
        // Dark theme uses Color(white: 0.1)
        #expect(bgColor != .white)
    }

    @Test("Auto theme adapts to color scheme")
    func autoThemeAdapts() {
        let lightBg = ReaderTheme.auto.backgroundColor(for: .light)
        let darkBg = ReaderTheme.auto.backgroundColor(for: .dark)
        #expect(lightBg != darkBg)
    }

    @Test("Text colors are defined for all themes")
    func textColors() {
        for theme in ReaderTheme.allCases {
            // Just verify they don't crash
            _ = theme.textColor(for: .light)
            _ = theme.textColor(for: .dark)
        }
    }

    @Test("Link colors are defined for all themes")
    func linkColors() {
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
    @Test("All cases exist")
    func allCasesExist() {
        let allCases = ReaderFont.allCases
        #expect(allCases.count == 4)
        #expect(allCases.contains(.system))
        #expect(allCases.contains(.serif))
        #expect(allCases.contains(.sansSerif))
        #expect(allCases.contains(.mono))
    }

    @Test("Display names are correct")
    func displayNames() {
        #expect(ReaderFont.system.displayName == "System")
        #expect(ReaderFont.serif.displayName == "Serif")
        #expect(ReaderFont.sansSerif.displayName == "Sans Serif")
        #expect(ReaderFont.mono.displayName == "Monospace")
    }

    @Test("CSS font families are valid strings")
    func cssFontFamilies() {
        #expect(ReaderFont.system.cssFontFamily.contains("-apple-system"))
        #expect(ReaderFont.serif.cssFontFamily.contains("Georgia"))
        #expect(ReaderFont.sansSerif.cssFontFamily.contains("Helvetica"))
        #expect(ReaderFont.mono.cssFontFamily.contains("Menlo"))
    }

    @Test("Font designs are correct")
    func fontDesigns() {
        #expect(ReaderFont.system.fontDesign == .default)
        #expect(ReaderFont.serif.fontDesign == .serif)
        #expect(ReaderFont.sansSerif.fontDesign == .default)
        #expect(ReaderFont.mono.fontDesign == .monospaced)
    }

    @Test("Font is codable")
    func codable() throws {
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

    @Test("Word count calculates correctly")
    func wordCount() {
        let article = makeArticle(textContent: "One two three four five")
        #expect(article.wordCount == 5)
    }

    @Test("Word count handles empty content")
    func wordCountEmpty() {
        let article = makeArticle(textContent: "")
        #expect(article.wordCount == 0)
    }

    @Test("Word count handles single word")
    func wordCountSingleWord() {
        let article = makeArticle(textContent: "Hello")
        #expect(article.wordCount == 1)
    }

    @Test("Word count handles multiple whitespace")
    func wordCountMultipleWhitespace() {
        let article = makeArticle(textContent: "One   two\t\tthree\n\nfour")
        #expect(article.wordCount == 4)
    }

    @Test("Estimated read time for short article")
    func estimatedReadTimeShort() {
        // Less than 200 words should be 1 minute minimum
        let article = makeArticle(textContent: "Short article")
        #expect(article.estimatedReadTime == 1)
    }

    @Test("Estimated read time for medium article")
    func estimatedReadTimeMedium() {
        // 400 words at 200 wpm = 2 minutes
        let words = Array(repeating: "word", count: 400).joined(separator: " ")
        let article = makeArticle(textContent: words)
        #expect(article.estimatedReadTime == 2)
    }

    @Test("Estimated read time for long article")
    func estimatedReadTimeLong() {
        // 1000 words at 200 wpm = 5 minutes
        let words = Array(repeating: "word", count: 1_000).joined(separator: " ")
        let article = makeArticle(textContent: words)
        #expect(article.estimatedReadTime == 5)
    }

    @Test("Read time string format")
    func readTimeString() {
        let article = makeArticle(textContent: "Short")
        #expect(article.readTimeString == "1 min read")

        let words = Array(repeating: "word", count: 600).joined(separator: " ")
        let longerArticle = makeArticle(textContent: words)
        #expect(longerArticle.readTimeString == "3 min read")
    }

    @Test("All properties are accessible")
    func allPropertiesAccessible() {
        let date = Date()
        let url = URL(string: "https://example.com/test")!

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

    @Test("Optional fields can be nil")
    func optionalFieldsNil() {
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

@Suite("ExtractedArticle JSON Parsing", .tags(.readerMode))
@MainActor
struct ExtractedArticleJSONTests {
    @Test("Parse valid JSON with all fields")
    func parseValidJSONAllFields() {
        let json: [String: Any] = [
            "title": "Test Article",
            "byline": "John Doe",
            "content": "<p>Content</p>",
            "textContent": "Content",
            "excerpt": "An excerpt",
            "siteName": "Test Site",
            "publishedTime": "2024-01-15T10:30:00Z",
        ]

        let url = URL(string: "https://example.com")!
        let article = ExtractedArticle.from(json: json, sourceURL: url)

        #expect(article != nil)
        #expect(article?.title == "Test Article")
        #expect(article?.byline == "John Doe")
        #expect(article?.content == "<p>Content</p>")
        #expect(article?.textContent == "Content")
        #expect(article?.excerpt == "An excerpt")
        #expect(article?.siteName == "Test Site")
        #expect(article?.publishedTime != nil)
        #expect(article?.sourceURL == url)
    }

    @Test("Parse valid JSON with required fields only")
    func parseValidJSONRequiredOnly() {
        let json: [String: Any] = [
            "title": "Minimal Article",
            "content": "<p>Content</p>",
            "textContent": "Content",
        ]

        let url = URL(string: "https://example.com")!
        let article = ExtractedArticle.from(json: json, sourceURL: url)

        #expect(article != nil)
        #expect(article?.title == "Minimal Article")
        #expect(article?.byline == nil)
        #expect(article?.excerpt == nil)
        #expect(article?.siteName == nil)
        #expect(article?.publishedTime == nil)
    }

    @Test("Parse returns nil for missing title")
    func parseMissingTitle() {
        let json: [String: Any] = [
            "content": "<p>Content</p>",
            "textContent": "Content",
        ]

        let article = ExtractedArticle.from(json: json, sourceURL: URL(string: "https://example.com")!)
        #expect(article == nil)
    }

    @Test("Parse returns nil for missing content")
    func parseMissingContent() {
        let json: [String: Any] = [
            "title": "Title",
            "textContent": "Content",
        ]

        let article = ExtractedArticle.from(json: json, sourceURL: URL(string: "https://example.com")!)
        #expect(article == nil)
    }

    @Test("Parse returns nil for missing textContent")
    func parseMissingTextContent() {
        let json: [String: Any] = [
            "title": "Title",
            "content": "<p>Content</p>",
        ]

        let article = ExtractedArticle.from(json: json, sourceURL: URL(string: "https://example.com")!)
        #expect(article == nil)
    }

    @Test("Parse handles ISO8601 date with fractional seconds")
    func parseISO8601WithFractional() {
        let json: [String: Any] = [
            "title": "Test",
            "content": "<p>C</p>",
            "textContent": "C",
            "publishedTime": "2024-06-15T14:30:45.123Z",
        ]

        let article = ExtractedArticle.from(json: json, sourceURL: URL(string: "https://example.com")!)

        #expect(article != nil)
        #expect(article?.publishedTime != nil)
    }

    @Test("Parse handles ISO8601 date without fractional seconds")
    func parseISO8601WithoutFractional() {
        let json: [String: Any] = [
            "title": "Test",
            "content": "<p>C</p>",
            "textContent": "C",
            "publishedTime": "2024-06-15T14:30:45Z",
        ]

        let article = ExtractedArticle.from(json: json, sourceURL: URL(string: "https://example.com")!)

        #expect(article != nil)
        #expect(article?.publishedTime != nil)
    }

    @Test("Parse handles invalid date string")
    func parseInvalidDate() {
        let json: [String: Any] = [
            "title": "Test",
            "content": "<p>C</p>",
            "textContent": "C",
            "publishedTime": "not-a-date",
        ]

        let article = ExtractedArticle.from(json: json, sourceURL: URL(string: "https://example.com")!)

        #expect(article != nil)
        #expect(article?.publishedTime == nil)
    }

    @Test("Parse trims whitespace from strings")
    func parseTrimsWhitespace() {
        let json: [String: Any] = [
            "title": "  Spaced Title  ",
            "content": "<p>C</p>",
            "textContent": "C",
            "byline": "  Spaced Author  ",
            "excerpt": "  Spaced Excerpt  ",
            "siteName": "  Spaced Site  ",
        ]

        let article = ExtractedArticle.from(json: json, sourceURL: URL(string: "https://example.com")!)

        #expect(article?.title == "Spaced Title")
        #expect(article?.byline == "Spaced Author")
        #expect(article?.excerpt == "Spaced Excerpt")
        #expect(article?.siteName == "Spaced Site")
    }
}

// MARK: - ReaderModeEvent Tests

@Suite("ReaderModeEvent Enum", .tags(.readerMode))
@MainActor
struct ReaderModeEventTests {
    @Test("Availability event stores data")
    func availabilityEvent() {
        let event = ReaderModeEvent.availability(url: "https://example.com", available: true)

        if case let .availability(url, available) = event {
            #expect(url == "https://example.com")
            #expect(available == true)
        } else {
            Issue.record("Expected availability event")
        }
    }

    @Test("Extracted event stores data")
    func extractedEvent() {
        let articleData: [String: Any] = ["title": "Test"]
        let event = ReaderModeEvent.extracted(url: "https://example.com", article: articleData)

        if case let .extracted(url, article) = event {
            #expect(url == "https://example.com")
            #expect(article != nil)
            #expect(article?["title"] as? String == "Test")
        } else {
            Issue.record("Expected extracted event")
        }
    }

    @Test("Error event stores message")
    func errorEvent() {
        let event = ReaderModeEvent.error(url: "https://example.com", message: "Failed to extract")

        if case let .error(url, message) = event {
            #expect(url == "https://example.com")
            #expect(message == "Failed to extract")
        } else {
            Issue.record("Expected error event")
        }
    }
}
