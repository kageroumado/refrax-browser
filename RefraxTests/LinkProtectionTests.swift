import Foundation
import Testing

@testable import Refrax

// MARK: - Link Protection Tests

@Suite("LinkProtection", .tags(.navigation))
@MainActor
struct LinkProtectionTests {
    // MARK: - Tracking Parameter Removal

    @Test("Removes UTM parameters")
    func removesUTMParameters() {
        let url = URL(string: "https://example.com/page?utm_source=twitter&utm_campaign=test&id=123")!
        let cleaned = LinkProtection.removeTrackingParameters(from: url)

        #expect(cleaned != nil)
        #expect(cleaned?.absoluteString == "https://example.com/page?id=123")
    }

    @Test("Removes fbclid parameter")
    func removesFbclid() {
        let url = URL(string: "https://example.com/article?fbclid=abc123def456&page=2")!
        let cleaned = LinkProtection.removeTrackingParameters(from: url)

        #expect(cleaned != nil)
        #expect(cleaned?.absoluteString == "https://example.com/article?page=2")
    }

    @Test("Removes gclid parameter")
    func removesGclid() {
        let url = URL(string: "https://example.com/product?gclid=tracking123&color=blue")!
        let cleaned = LinkProtection.removeTrackingParameters(from: url)

        #expect(cleaned != nil)
        #expect(cleaned?.absoluteString == "https://example.com/product?color=blue")
    }

    @Test("Preserves non-tracking parameters")
    func preservesNonTrackingParams() {
        let url = URL(string: "https://example.com/search?q=swift&page=2&sort=date")!
        let cleaned = LinkProtection.removeTrackingParameters(from: url)

        // No tracking params → returns nil (no changes)
        #expect(cleaned == nil)
    }

    @Test("Case-insensitive parameter matching")
    func caseInsensitiveMatching() {
        let url = URL(string: "https://example.com/page?UTM_SOURCE=test&UTM_CAMPAIGN=promo")!
        let cleaned = LinkProtection.removeTrackingParameters(from: url)

        #expect(cleaned != nil)
        // All params removed → query cleared
        #expect(cleaned?.query == nil)
    }

    @Test("All tracking parameters removed clears query")
    func allParamsRemovedClearsQuery() {
        let url = URL(string: "https://example.com/page?utm_source=test&fbclid=abc&gclid=def")!
        let cleaned = LinkProtection.removeTrackingParameters(from: url)

        #expect(cleaned != nil)
        #expect(cleaned?.query == nil)
        #expect(cleaned?.absoluteString == "https://example.com/page")
    }

    @Test("Returns nil if no changes needed")
    func returnsNilIfNoChanges() {
        let url = URL(string: "https://example.com/page?id=123&name=test")!
        let cleaned = LinkProtection.removeTrackingParameters(from: url)

        #expect(cleaned == nil)
    }

    @Test("Returns nil for URL without query string")
    func noQueryStringReturnsNil() {
        let url = URL(string: "https://example.com/page")!
        let cleaned = LinkProtection.removeTrackingParameters(from: url)

        #expect(cleaned == nil)
    }

    @Test("Handles multiple tracking parameter types")
    func multipleTrackingTypes() {
        let url = URL(string: "https://example.com/article?utm_source=newsletter&fbclid=fb123&msclkid=ms456&valid=keep")!
        let cleaned = LinkProtection.removeTrackingParameters(from: url)

        #expect(cleaned != nil)
        #expect(cleaned?.absoluteString == "https://example.com/article?valid=keep")
    }

    // MARK: - AMP Conversion

    @Test("Converts Google AMP cache URL")
    func googleAMPCacheConverted() {
        let url = URL(string: "https://www.google.com/amp/s/example.com/article/123")!
        let canonical = LinkProtection.extractCanonicalFromAMP(url)

        #expect(canonical != nil)
        #expect(canonical?.host == "example.com")
        #expect(canonical?.path == "/article/123")
    }

    @Test("Converts ampproject.org cache URL")
    func ampprojectCacheConverted() {
        let url = URL(string: "https://example-com.cdn.ampproject.org/v/s/example.com/news/story")!
        let canonical = LinkProtection.extractCanonicalFromAMP(url)

        #expect(canonical != nil)
        #expect(canonical?.host == "example.com")
        #expect(canonical?.path == "/news/story")
    }

    @Test("Converts Bing AMP URL")
    func bingAMPConverted() {
        let url = URL(string: "https://www.bing.com/amp/s/example.com/page")!
        let canonical = LinkProtection.extractCanonicalFromAMP(url)

        #expect(canonical != nil)
        #expect(canonical?.host == "example.com")
    }

    @Test("Converts publisher-hosted AMP path")
    func publisherAMPPathConverted() {
        let url = URL(string: "https://example.com/amp/article/123")!
        let canonical = LinkProtection.extractCanonicalFromAMP(url)

        #expect(canonical != nil)
        #expect(canonical?.path == "/article/123")
        #expect(canonical?.host == "example.com")
    }

    @Test("Removes .amp.html suffix")
    func ampDotHtmlSuffixRemoved() {
        let url = URL(string: "https://example.com/article/123.amp.html")!
        let canonical = LinkProtection.extractCanonicalFromAMP(url)

        #expect(canonical != nil)
        #expect(canonical?.path == "/article/123")
    }

    @Test("Removes /amp suffix")
    func ampSuffixRemoved() {
        let url = URL(string: "https://example.com/article/123/amp")!
        let canonical = LinkProtection.extractCanonicalFromAMP(url)

        #expect(canonical != nil)
        #expect(canonical?.path == "/article/123")
    }

    @Test("Removes AMP query parameters")
    func ampQueryParamsRemoved() {
        let url = URL(string: "https://example.com/article/amp?amp=1&usqp=mq331AQ")!
        let canonical = LinkProtection.extractCanonicalFromAMP(url)

        #expect(canonical != nil)
        // AMP params should be removed
        #expect(canonical?.query == nil || !canonical!.query!.contains("amp="))
    }

    @Test("Non-AMP URL returns nil")
    func nonAMPReturnsNil() {
        let url = URL(string: "https://example.com/regular/article")!
        let canonical = LinkProtection.extractCanonicalFromAMP(url)

        #expect(canonical == nil)
    }

    @Test("Preserves non-AMP query parameters from CDN")
    func preservesNonAMPQueryParams() {
        let url = URL(string: "https://www.google.com/amp/s/example.com/article?id=123&category=tech")!
        let canonical = LinkProtection.extractCanonicalFromAMP(url)

        #expect(canonical != nil)
        #expect(canonical?.query?.contains("id=123") == true)
    }

    // MARK: - Combined Cleanup

    @Test("cleanURL applies both AMP and tracking cleanup")
    func cleanURLAppliesBothTransforms() {
        let url = URL(string: "https://www.google.com/amp/s/example.com/article?utm_source=twitter&id=123")!
        let cleaned = LinkProtection.cleanURL(from: url)

        #expect(cleaned != nil)
        #expect(cleaned?.host == "example.com")
        #expect(cleaned?.query?.contains("utm_source") == false)
        #expect(cleaned?.query?.contains("id=123") == true)
    }

    @Test("cleanURL returns nil if no changes needed")
    func cleanURLReturnsNilIfNoChanges() {
        let url = URL(string: "https://example.com/article?id=123")!
        let cleaned = LinkProtection.cleanURL(from: url)

        #expect(cleaned == nil)
    }

    @Test("cleanURL only removes tracking when not AMP")
    func cleanURLOnlyTracking() {
        let url = URL(string: "https://example.com/article?utm_source=test&id=123")!
        let cleaned = LinkProtection.cleanURL(from: url)

        #expect(cleaned != nil)
        #expect(cleaned?.host == "example.com")
        #expect(cleaned?.absoluteString == "https://example.com/article?id=123")
    }

    @Test("cleanURL only converts AMP when no tracking")
    func cleanURLOnlyAMP() {
        let url = URL(string: "https://example.com/article/amp")!
        let cleaned = LinkProtection.cleanURL(from: url)

        #expect(cleaned != nil)
        #expect(cleaned?.path == "/article")
    }

    // MARK: - URL Extension Tests

    @Test("removingTrackingParameters returns self if no changes")
    func removingTrackingParametersNoChanges() {
        let url = URL(string: "https://example.com/page?id=123")!
        let result = url.removingTrackingParameters()

        #expect(result == url)
    }

    @Test("removingTrackingParameters returns cleaned URL")
    func removingTrackingParametersWithChanges() {
        let url = URL(string: "https://example.com/page?utm_source=test&id=123")!
        let result = url.removingTrackingParameters()

        #expect(result != url)
        #expect(result.absoluteString == "https://example.com/page?id=123")
    }

    @Test("isAMPURL detects Google AMP")
    func isAMPURLGoogleAMP() {
        let url = URL(string: "https://www.google.com/amp/s/example.com/article")!
        #expect(url.isAMPURL == true)
    }

    @Test("isAMPURL detects ampproject.org")
    func isAMPURLAmpProject() {
        let url = URL(string: "https://cdn.ampproject.org/v/s/example.com/article")!
        #expect(url.isAMPURL == true)
    }

    @Test("isAMPURL detects publisher AMP path")
    func isAMPURLPublisherPath() {
        let url = URL(string: "https://example.com/article/amp")!
        #expect(url.isAMPURL == true)
    }

    @Test("isAMPURL returns false for regular URLs")
    func isAMPURLRegular() {
        let url = URL(string: "https://example.com/article")!
        #expect(url.isAMPURL == false)
    }

    @Test("canonicalURL returns self for non-AMP")
    func canonicalURLNonAMP() {
        let url = URL(string: "https://example.com/article")!
        #expect(url.canonicalURL == url)
    }

    @Test("canonicalURL extracts canonical from AMP")
    func canonicalURLFromAMP() {
        let url = URL(string: "https://www.google.com/amp/s/example.com/article")!
        let canonical = url.canonicalURL

        #expect(canonical.host == "example.com")
        #expect(canonical.path == "/article")
    }
}

// MARK: - Test Tags

extension Tag {
    @Tag static var navigation: Self
}
