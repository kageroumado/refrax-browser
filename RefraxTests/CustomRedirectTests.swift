import Foundation
import SwiftData
import Testing

@testable import Refrax

// MARK: - CustomRedirect Tests

@Suite("CustomRedirect", .tags(.navigation))
@MainActor
struct CustomRedirectTests {
    // MARK: - Test Helpers

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func makeRedirect(
        in context: ModelContext,
        name: String = "Test",
        sourcePattern: String,
        destinationTemplate: String,
        isEnabled: Bool = true,
    ) -> CustomRedirect {
        let redirect = CustomRedirect(
            name: name,
            sourcePattern: sourcePattern,
            destinationTemplate: destinationTemplate,
            isEnabled: isEnabled,
        )
        context.insert(redirect)
        return redirect
    }

    // MARK: - Basic Pattern Matching

    @Test("Wildcard captures and replaces path")
    func wildcardCaptureReplacement() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            sourcePattern: "twitter.com/*",
            destinationTemplate: "nitter.net/$1",
        )

        let url = URL(string: "https://twitter.com/user/status/123")!
        let result = redirect.apply(to: url)

        #expect(result != nil)
        #expect(result?.host == "nitter.net")
        #expect(result?.path == "/user/status/123")
    }

    @Test("Multiple wildcard captures")
    func multipleWildcardCaptures() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            sourcePattern: "*.reddit.com/*",
            destinationTemplate: "teddit.net/$2",
        )

        let url = URL(string: "https://old.reddit.com/r/swift/comments/abc")!
        let result = redirect.apply(to: url)

        #expect(result != nil)
        #expect(result?.host == "teddit.net")
        #expect(result?.path == "/r/swift/comments/abc")
    }

    @Test("Preserves query string in capture")
    func preservesQueryStringInCapture() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            sourcePattern: "youtube.com/watch*",
            destinationTemplate: "yewtu.be/watch$1",
        )

        let url = URL(string: "https://youtube.com/watch?v=abc123&t=120")!
        let result = redirect.apply(to: url)

        #expect(result != nil)
        #expect(result?.absoluteString.contains("v=abc123") == true)
    }

    @Test("Pattern without wildcard matches exactly")
    func exactMatch() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            sourcePattern: "example.com/old",
            destinationTemplate: "example.com/new",
        )

        let urlMatch = URL(string: "https://example.com/old")!
        let urlNoMatch = URL(string: "https://example.com/old/extra")!

        #expect(redirect.apply(to: urlMatch) != nil)
        #expect(redirect.apply(to: urlNoMatch) == nil)
    }

    @Test("Case insensitive domain matching")
    func caseInsensitiveMatching() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            sourcePattern: "Twitter.com/*",
            destinationTemplate: "nitter.net/$1",
        )

        let url = URL(string: "https://TWITTER.COM/user")!
        let result = redirect.apply(to: url)

        #expect(result != nil)
    }

    // MARK: - Edge Cases

    @Test("Template placeholder without matching capture left as literal")
    func templatePlaceholderLeftAsLiteral() throws {
        let container = try Self.makeContainer()
        // Pattern has 1 wildcard but template expects $2 (which doesn't exist)
        // Current behavior: unreferenced $N placeholders are left as literals
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            sourcePattern: "example.com/*",
            destinationTemplate: "new.com/$2",
        )

        let url = URL(string: "https://example.com/path")!
        let result = redirect.apply(to: url)

        // $2 is left as a literal since there's no capture group 2
        #expect(result?.absoluteString == "https://new.com/$2")
    }

    @Test("Scheme inserted when missing in destination")
    func schemeInsertedWhenMissing() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            sourcePattern: "twitter.com/*",
            destinationTemplate: "nitter.net/$1",
        )

        let url = URL(string: "https://twitter.com/user")!
        let result = redirect.apply(to: url)

        #expect(result != nil)
        #expect(result?.scheme == "https")
    }

    @Test("Relative path preserves original host")
    func relativePathPreservesHost() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            sourcePattern: "example.com/old/*",
            destinationTemplate: "/new/$1",
        )

        let url = URL(string: "https://example.com/old/page")!
        let result = redirect.apply(to: url)

        #expect(result != nil)
        #expect(result?.host == "example.com")
        #expect(result?.path == "/new/page")
    }

    @Test("Disabled rule returns nil")
    func disabledRuleReturnsNil() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            sourcePattern: "twitter.com/*",
            destinationTemplate: "nitter.net/$1",
            isEnabled: false,
        )

        let url = URL(string: "https://twitter.com/user")!
        let result = redirect.apply(to: url)

        #expect(result == nil)
    }

    @Test("Empty capture group handled")
    func emptyCaptureGroupHandled() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            sourcePattern: "example.com/*",
            destinationTemplate: "new.com/$1",
        )

        // URL with nothing after the pattern
        let url = URL(string: "https://example.com/")!
        let result = redirect.apply(to: url)

        #expect(result != nil)
        // Empty capture produces empty replacement
        #expect(result?.absoluteString == "https://new.com/")
    }

    @Test("Special regex characters escaped")
    func specialRegexCharactersEscaped() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            sourcePattern: "example.com/path?query=*",
            destinationTemplate: "new.com/$1",
        )

        let url = URL(string: "https://example.com/path?query=value")!
        let result = redirect.apply(to: url)

        #expect(result != nil)
    }

    @Test("URL without matching pattern returns nil")
    func nonMatchingURLReturnsNil() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            sourcePattern: "twitter.com/*",
            destinationTemplate: "nitter.net/$1",
        )

        let url = URL(string: "https://facebook.com/user")!
        let result = redirect.apply(to: url)

        #expect(result == nil)
    }

    // MARK: - Cache Behavior

    @Test("Cached regex reused on same pattern")
    func cacheReusedSamePattern() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            sourcePattern: "twitter.com/*",
            destinationTemplate: "nitter.net/$1",
        )

        let url1 = URL(string: "https://twitter.com/user1")!
        let url2 = URL(string: "https://twitter.com/user2")!

        // Both should work, demonstrating cache reuse
        let result1 = redirect.apply(to: url1)
        let result2 = redirect.apply(to: url2)

        #expect(result1 != nil)
        #expect(result2 != nil)
        #expect(result1?.path == "/user1")
        #expect(result2?.path == "/user2")
    }

    @Test("Cache invalidated on pattern change")
    func cacheInvalidatedOnPatternChange() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            sourcePattern: "twitter.com/*",
            destinationTemplate: "nitter.net/$1",
        )

        let twitterURL = URL(string: "https://twitter.com/user")!
        let facebookURL = URL(string: "https://facebook.com/user")!

        // First pattern should match twitter
        #expect(redirect.apply(to: twitterURL) != nil)
        #expect(redirect.apply(to: facebookURL) == nil)

        // Change pattern
        redirect.sourcePattern = "facebook.com/*"

        // New pattern should match facebook, not twitter
        #expect(redirect.apply(to: twitterURL) == nil)
        #expect(redirect.apply(to: facebookURL) != nil)
    }

    // MARK: - Real-World Examples

    @Test("Twitter to Nitter")
    func twitterToNitter() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            name: "Twitter → Nitter",
            sourcePattern: "twitter.com/*",
            destinationTemplate: "nitter.net/$1",
        )

        let url = URL(string: "https://twitter.com/elikiiii/status/1234567890")!
        let result = redirect.apply(to: url)

        #expect(result?.absoluteString == "https://nitter.net/elikiiii/status/1234567890")
    }

    @Test("YouTube to Invidious (exact domain)")
    func youtubeToInvidious() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            name: "YouTube → Invidious",
            sourcePattern: "youtube.com/*",
            destinationTemplate: "yewtu.be/$1",
        )

        let url = URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!
        // Note: www.youtube.com won't match youtube.com without www handling
        let result = redirect.apply(to: url)

        // With www prefix, exact youtube.com won't match
        #expect(result == nil)
    }

    @Test("YouTube with www subdomain")
    func youtubeWithWWW() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            name: "YouTube → Invidious",
            sourcePattern: "*.youtube.com/*",
            destinationTemplate: "yewtu.be/$2",
        )

        let url = URL(string: "https://www.youtube.com/watch?v=abc123")!
        let result = redirect.apply(to: url)

        #expect(result != nil)
        #expect(result?.host == "yewtu.be")
        #expect(result?.absoluteString.contains("v=abc123") == true)
    }

    @Test("Medium to Scribe")
    func mediumToScribe() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            name: "Medium → Scribe",
            sourcePattern: "*.medium.com/*",
            destinationTemplate: "scribe.rip/$2",
        )

        let url = URL(string: "https://user.medium.com/article-title-abc123")!
        let result = redirect.apply(to: url)

        #expect(result?.host == "scribe.rip")
        #expect(result?.path == "/article-title-abc123")
    }

    @Test("Remove mobile subdomain")
    func removeMobileSubdomain() throws {
        let container = try Self.makeContainer()
        let redirect = Self.makeRedirect(
            in: container.mainContext,
            name: "Remove mobile",
            sourcePattern: "m.example.com/*",
            destinationTemplate: "example.com/$1",
        )

        let url = URL(string: "https://m.example.com/article/123")!
        let result = redirect.apply(to: url)

        #expect(result?.host == "example.com")
        #expect(result?.path == "/article/123")
    }
}
