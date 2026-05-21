import Foundation
import Testing

@testable import Refrax

// MARK: - URLShortenerExpander Tests

@Suite("URLShortenerExpander", .tags(.navigation))
@MainActor
struct URLShortenerExpanderTests {
    // MARK: - Shortener Detection

    @Test("Detects bit.ly as shortener")
    func detectsBitly() {
        let url = URL(string: "https://bit.ly/abc123")!
        #expect(URLShortenerExpander.isShortenerURL(url) == true)
    }

    @Test("Detects t.co as shortener")
    func detectsTco() {
        let url = URL(string: "https://t.co/xyz789")!
        #expect(URLShortenerExpander.isShortenerURL(url) == true)
    }

    @Test("Detects tinyurl.com as shortener")
    func detectsTinyURL() {
        let url = URL(string: "https://tinyurl.com/abc123")!
        #expect(URLShortenerExpander.isShortenerURL(url) == true)
    }

    @Test("Detects goo.gl as shortener")
    func detectsGooGl() {
        let url = URL(string: "https://goo.gl/maps/abc")!
        #expect(URLShortenerExpander.isShortenerURL(url) == true)
    }

    @Test("Detects amzn.to as shortener")
    func detectsAmzn() {
        let url = URL(string: "https://amzn.to/product123")!
        #expect(URLShortenerExpander.isShortenerURL(url) == true)
    }

    @Test("Detects nyti.ms as shortener")
    func detectsNYTimes() {
        let url = URL(string: "https://nyti.ms/article")!
        #expect(URLShortenerExpander.isShortenerURL(url) == true)
    }

    @Test("Detects shortener with www prefix")
    func detectsWithWWW() {
        let url = URL(string: "https://www.bit.ly/abc123")!
        #expect(URLShortenerExpander.isShortenerURL(url) == true)
    }

    @Test("Regular domain not detected as shortener")
    func regularDomainNotShortener() {
        let url = URL(string: "https://example.com/page")!
        #expect(URLShortenerExpander.isShortenerURL(url) == false)
    }

    @Test("Apple.com not detected as shortener")
    func appleDotComNotShortener() {
        let url = URL(string: "https://apple.com/iphone")!
        #expect(URLShortenerExpander.isShortenerURL(url) == false)
    }

    @Test("Google.com not detected as shortener")
    func googleDotComNotShortener() {
        let url = URL(string: "https://www.google.com/search")!
        #expect(URLShortenerExpander.isShortenerURL(url) == false)
    }

    @Test("URL without host returns false")
    func noHostReturnsFalse() {
        let url = URL(string: "file:///path/to/file")!
        #expect(URLShortenerExpander.isShortenerURL(url) == false)
    }

    // MARK: - URL Extension

    @Test("URL extension isShortenerURL works")
    func urlExtensionWorks() {
        let shortURL = URL(string: "https://bit.ly/abc")!
        let normalURL = URL(string: "https://example.com/page")!

        #expect(shortURL.isShortenerURL == true)
        #expect(normalURL.isShortenerURL == false)
    }

    // MARK: - Known Shorteners Coverage

    @Test("Social media shorteners detected")
    func socialMediaShorteners() {
        let urls = [
            URL(string: "https://fb.me/abc")!,
            URL(string: "https://lnkd.in/abc")!,
            URL(string: "https://redd.it/abc")!,
        ]

        for url in urls {
            #expect(URLShortenerExpander.isShortenerURL(url) == true, "Expected \(url.host ?? "") to be shortener")
        }
    }

    @Test("News media shorteners detected")
    func newsMediaShorteners() {
        let urls = [
            URL(string: "https://nyti.ms/abc")!,
            URL(string: "https://wapo.st/abc")!,
            URL(string: "https://cnn.it/abc")!,
            URL(string: "https://bbc.in/abc")!,
        ]

        for url in urls {
            #expect(URLShortenerExpander.isShortenerURL(url) == true, "Expected \(url.host ?? "") to be shortener")
        }
    }

    @Test("Tech shorteners detected")
    func techShorteners() {
        let urls = [
            URL(string: "https://g.co/abc")!,
            URL(string: "https://apple.co/abc")!,
            URL(string: "https://aka.ms/abc")!,
        ]

        for url in urls {
            #expect(URLShortenerExpander.isShortenerURL(url) == true, "Expected \(url.host ?? "") to be shortener")
        }
    }

    // MARK: - Cache Behavior (Behavioral Tests)

    @Test("Non-shortener URL returns nil from expand")
    func nonShortenerReturnsNil() async {
        let url = URL(string: "https://example.com/page")!
        let result = await URLShortenerExpander.shared.expand(url)

        #expect(result == nil)
    }

    @Test("Clear cache doesn't crash")
    func clearCacheDoesntCrash() async {
        await URLShortenerExpander.shared.clearCache()
        // If we get here without crashing, test passes
    }
}
