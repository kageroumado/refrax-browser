import Foundation
import SwiftData
import Testing

@testable import Refrax

// MARK: - AppRedirectRule Tests

@Suite("AppRedirectRule", .tags(.navigation))
@MainActor
struct AppRedirectRuleTests {
    // MARK: - Test Helpers

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func makeRule(
        in context: ModelContext,
        name: String = "Test",
        domainPattern: String,
        pathPattern: String? = nil,
        targetAppBundleID: String = "com.test.app",
        isEnabled: Bool = true,
    ) -> AppRedirectRule {
        let rule = AppRedirectRule(
            name: name,
            domainPattern: domainPattern,
            pathPattern: pathPattern,
            targetAppBundleID: targetAppBundleID,
            isEnabled: isEnabled,
        )
        context.insert(rule)
        return rule
    }

    // MARK: - Domain Pattern Matching

    @Test("Exact domain matches")
    func exactDomainMatches() throws {
        let container = try Self.makeContainer()
        let rule = Self.makeRule(in: container.mainContext, domainPattern: "youtube.com")

        let matchingURL = URL(string: "https://youtube.com/watch?v=abc")!
        let nonMatchingURL = URL(string: "https://vimeo.com/123")!

        #expect(rule.matches(matchingURL) == true)
        #expect(rule.matches(nonMatchingURL) == false)
    }

    @Test("Subdomain wildcard matches any subdomain")
    func subdomainWildcardMatches() throws {
        let container = try Self.makeContainer()
        let rule = Self.makeRule(in: container.mainContext, domainPattern: "*.youtube.com")

        let wwwURL = URL(string: "https://www.youtube.com/watch")!
        let musicURL = URL(string: "https://music.youtube.com/playlist")!
        let bareURL = URL(string: "https://youtube.com/watch")!

        #expect(rule.matches(wwwURL) == true)
        #expect(rule.matches(musicURL) == true)
        // Bare domain doesn't match *.youtube.com
        #expect(rule.matches(bareURL) == false)
    }

    @Test("Wildcard anywhere in domain")
    func wildcardAnywhereInDomain() throws {
        let container = try Self.makeContainer()
        let rule = Self.makeRule(in: container.mainContext, domainPattern: "*youtube*")

        let youtubeURL = URL(string: "https://youtube.com/watch")!
        let wwwYoutubeURL = URL(string: "https://www.youtube.com/watch")!
        let musicYoutubeURL = URL(string: "https://music.youtube.com/")!
        let unrelatedURL = URL(string: "https://vimeo.com/")!

        #expect(rule.matches(youtubeURL) == true)
        #expect(rule.matches(wwwYoutubeURL) == true)
        #expect(rule.matches(musicYoutubeURL) == true)
        #expect(rule.matches(unrelatedURL) == false)
    }

    @Test("Case insensitive host matching")
    func caseInsensitiveHostMatch() throws {
        let container = try Self.makeContainer()
        let rule = Self.makeRule(in: container.mainContext, domainPattern: "YouTube.com")

        let lowercaseURL = URL(string: "https://youtube.com/watch")!
        let uppercaseURL = URL(string: "https://YOUTUBE.COM/watch")!
        let mixedURL = URL(string: "https://YouTube.COM/watch")!

        #expect(rule.matches(lowercaseURL) == true)
        #expect(rule.matches(uppercaseURL) == true)
        #expect(rule.matches(mixedURL) == true)
    }

    @Test("Whole match behavior prevents partial domain match")
    func wholeMatchBehavior() throws {
        let container = try Self.makeContainer()
        let rule = Self.makeRule(in: container.mainContext, domainPattern: "tube.com")

        // Should NOT match youtube.com (tube.com is not a whole match)
        let youtubeURL = URL(string: "https://youtube.com/watch")!
        // Should match tube.com exactly
        let tubeURL = URL(string: "https://tube.com/video")!

        #expect(rule.matches(youtubeURL) == false)
        #expect(rule.matches(tubeURL) == true)
    }

    // MARK: - Path Pattern Matching

    @Test("Path pattern nil matches all paths")
    func pathPatternNilMatchesAll() throws {
        let container = try Self.makeContainer()
        let rule = Self.makeRule(
            in: container.mainContext,
            domainPattern: "youtube.com",
            pathPattern: nil,
        )

        let watchURL = URL(string: "https://youtube.com/watch?v=abc")!
        let playlistURL = URL(string: "https://youtube.com/playlist")!
        let rootURL = URL(string: "https://youtube.com/")!

        #expect(rule.matches(watchURL) == true)
        #expect(rule.matches(playlistURL) == true)
        #expect(rule.matches(rootURL) == true)
    }

    @Test("Path pattern with wildcard")
    func pathPatternWithWildcard() throws {
        let container = try Self.makeContainer()
        let rule = Self.makeRule(
            in: container.mainContext,
            domainPattern: "youtube.com",
            pathPattern: "/watch*",
        )

        let watchURL = URL(string: "https://youtube.com/watch?v=abc")!
        let playlistURL = URL(string: "https://youtube.com/playlist")!
        let channelURL = URL(string: "https://youtube.com/channel/xyz")!

        #expect(rule.matches(watchURL) == true)
        #expect(rule.matches(playlistURL) == false)
        #expect(rule.matches(channelURL) == false)
    }

    @Test("Exact path pattern")
    func exactPathPattern() throws {
        let container = try Self.makeContainer()
        let rule = Self.makeRule(
            in: container.mainContext,
            domainPattern: "zoom.us",
            pathPattern: "/j/*",
        )

        let joinURL = URL(string: "https://zoom.us/j/123456789")!
        let homeURL = URL(string: "https://zoom.us/")!
        let settingsURL = URL(string: "https://zoom.us/settings")!

        #expect(rule.matches(joinURL) == true)
        #expect(rule.matches(homeURL) == false)
        #expect(rule.matches(settingsURL) == false)
    }

    @Test("Path pattern whole match")
    func pathPatternWholeMatch() throws {
        let container = try Self.makeContainer()
        let rule = Self.makeRule(
            in: container.mainContext,
            domainPattern: "example.com",
            pathPattern: "/api",
        )

        let exactURL = URL(string: "https://example.com/api")!
        let extendedURL = URL(string: "https://example.com/api/v1")!

        #expect(rule.matches(exactURL) == true)
        #expect(rule.matches(extendedURL) == false)
    }

    // MARK: - Rule State

    @Test("Disabled rule does not match")
    func disabledRuleDoesNotMatch() throws {
        let container = try Self.makeContainer()
        let rule = Self.makeRule(
            in: container.mainContext,
            domainPattern: "youtube.com",
            isEnabled: false,
        )

        let url = URL(string: "https://youtube.com/watch")!
        #expect(rule.matches(url) == false)
    }

    @Test("Rule with no host in URL returns false")
    func noHostReturnsFalse() throws {
        let container = try Self.makeContainer()
        let rule = Self.makeRule(in: container.mainContext, domainPattern: "youtube.com")

        // file:// URL has no host
        let fileURL = URL(string: "file:///path/to/file")!
        #expect(rule.matches(fileURL) == false)
    }

    // MARK: - Cache Behavior

    @Test("Cache invalidated on domain pattern change")
    func cacheInvalidatedOnDomainChange() throws {
        let container = try Self.makeContainer()
        let rule = Self.makeRule(in: container.mainContext, domainPattern: "youtube.com")

        let youtubeURL = URL(string: "https://youtube.com/watch")!
        let vimeoURL = URL(string: "https://vimeo.com/123")!

        // First pattern matches youtube
        #expect(rule.matches(youtubeURL) == true)
        #expect(rule.matches(vimeoURL) == false)

        // Change pattern
        rule.domainPattern = "vimeo.com"

        // New pattern should match vimeo, not youtube
        #expect(rule.matches(youtubeURL) == false)
        #expect(rule.matches(vimeoURL) == true)
    }

    @Test("Cache invalidated on path pattern change")
    func cacheInvalidatedOnPathChange() throws {
        let container = try Self.makeContainer()
        let rule = Self.makeRule(
            in: container.mainContext,
            domainPattern: "youtube.com",
            pathPattern: "/watch*",
        )

        let watchURL = URL(string: "https://youtube.com/watch?v=abc")!
        let playlistURL = URL(string: "https://youtube.com/playlist")!

        // First pattern matches /watch
        #expect(rule.matches(watchURL) == true)
        #expect(rule.matches(playlistURL) == false)

        // Change path pattern
        rule.pathPattern = "/playlist*"

        // New pattern should match /playlist, not /watch
        #expect(rule.matches(watchURL) == false)
        #expect(rule.matches(playlistURL) == true)
    }

    // MARK: - Real-World Examples

    @Test("YouTube to IINA")
    func youtubeToIINA() throws {
        let container = try Self.makeContainer()
        let rule = Self.makeRule(
            in: container.mainContext,
            name: "YouTube → IINA",
            domainPattern: "*.youtube.com",
            pathPattern: "/watch*",
            targetAppBundleID: AppRedirectRule.CommonApps.iina,
        )

        let watchURL = URL(string: "https://www.youtube.com/watch?v=abc123")!
        let channelURL = URL(string: "https://www.youtube.com/channel/xyz")!
        let musicURL = URL(string: "https://music.youtube.com/watch?v=def")!

        #expect(rule.matches(watchURL) == true)
        #expect(rule.matches(channelURL) == false)
        #expect(rule.matches(musicURL) == true)
    }

    @Test("Zoom meeting links")
    func zoomMeetingLinks() throws {
        let container = try Self.makeContainer()
        let rule = Self.makeRule(
            in: container.mainContext,
            name: "Zoom Meetings",
            domainPattern: "*.zoom.us",
            pathPattern: "/j/*",
            targetAppBundleID: AppRedirectRule.CommonApps.zoom,
        )

        let meetingURL = URL(string: "https://us02web.zoom.us/j/123456789?pwd=abc")!
        let homeURL = URL(string: "https://zoom.us/")!
        let webinarURL = URL(string: "https://zoom.us/webinar/register")!

        #expect(rule.matches(meetingURL) == true)
        #expect(rule.matches(homeURL) == false)
        #expect(rule.matches(webinarURL) == false)
    }

    @Test("Spotify links")
    func spotifyLinks() throws {
        let container = try Self.makeContainer()
        let rule = Self.makeRule(
            in: container.mainContext,
            name: "Spotify",
            domainPattern: "open.spotify.com",
            targetAppBundleID: AppRedirectRule.CommonApps.spotify,
        )

        let trackURL = URL(string: "https://open.spotify.com/track/abc123")!
        let playlistURL = URL(string: "https://open.spotify.com/playlist/xyz")!
        let mainURL = URL(string: "https://spotify.com/")!

        #expect(rule.matches(trackURL) == true)
        #expect(rule.matches(playlistURL) == true)
        #expect(rule.matches(mainURL) == false)
    }

    @Test("Slack links")
    func slackLinks() throws {
        let container = try Self.makeContainer()
        let rule = Self.makeRule(
            in: container.mainContext,
            name: "Slack",
            domainPattern: "*.slack.com",
            targetAppBundleID: AppRedirectRule.CommonApps.slack,
        )

        let channelURL = URL(string: "https://workspace.slack.com/archives/C123")!
        let appURL = URL(string: "https://app.slack.com/client/T123/C456")!
        let marketingURL = URL(string: "https://slack.com/pricing")!

        #expect(rule.matches(channelURL) == true)
        #expect(rule.matches(appURL) == true)
        #expect(rule.matches(marketingURL) == false)
    }

    // MARK: - Common Apps

    @Test("Common app bundle IDs are valid format")
    func commonAppBundleIDsValid() {
        // Just verify the format is correct (reverse domain notation)
        #expect(AppRedirectRule.CommonApps.safari.contains("."))
        #expect(AppRedirectRule.CommonApps.chrome.contains("."))
        #expect(AppRedirectRule.CommonApps.firefox.contains("."))
        #expect(AppRedirectRule.CommonApps.zoom.contains("."))
        #expect(AppRedirectRule.CommonApps.slack.contains("."))
        #expect(AppRedirectRule.CommonApps.spotify.contains("."))
        #expect(AppRedirectRule.CommonApps.iina.contains("."))
    }
}
