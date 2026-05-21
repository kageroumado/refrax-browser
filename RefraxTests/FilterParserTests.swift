import Foundation
import Testing
@testable import Refrax

// MARK: - Test Tags

extension Tag {
    @Tag static var filterParser: Self
}

// MARK: - Cosmetic Rule Parsing Tests

@Suite("FilterParser Cosmetic Rules", .tags(.filterParser))
struct FilterParserCosmeticTests {
    let parser = FilterParser()

    // MARK: - Global Rules

    @Test("Parses global cosmetic rule")
    func globalRule() {
        let result = parser.parse("##.cookie-banner")
        #expect(result.cosmeticRules.count == 1)
        let rule = result.cosmeticRules[0]
        #expect(rule.selector == ".cookie-banner")
        #expect(rule.domains == nil)
        #expect(rule.excludeDomains == nil)
        #expect(rule.isException == false)
    }

    @Test("Parses global rule with complex selector")
    func globalComplexSelector() {
        let result = parser.parse("##div[class*='consent-banner'] > .overlay")
        #expect(result.cosmeticRules.count == 1)
        #expect(result.cosmeticRules[0].selector == "div[class*='consent-banner'] > .overlay")
    }

    // MARK: - Domain-Scoped Rules

    @Test("Parses single-domain cosmetic rule")
    func singleDomainRule() {
        let result = parser.parse("example.com##.ad-banner")
        #expect(result.cosmeticRules.count == 1)
        let rule = result.cosmeticRules[0]
        #expect(rule.selector == ".ad-banner")
        #expect(rule.domains == ["example.com"])
        #expect(rule.excludeDomains == nil)
        #expect(rule.isException == false)
    }

    @Test("Parses multi-domain cosmetic rule")
    func multiDomainRule() {
        let result = parser.parse("example.com,other.org##.cookie-popup")
        #expect(result.cosmeticRules.count == 1)
        let rule = result.cosmeticRules[0]
        #expect(rule.selector == ".cookie-popup")
        #expect(rule.domains == ["example.com", "other.org"])
    }

    @Test("Parses exclude-domain cosmetic rule")
    func excludeDomainRule() {
        let result = parser.parse("~example.com##.tracking-pixel")
        #expect(result.cosmeticRules.count == 1)
        let rule = result.cosmeticRules[0]
        #expect(rule.selector == ".tracking-pixel")
        #expect(rule.domains == nil)
        #expect(rule.excludeDomains == ["example.com"])
    }

    @Test("Parses mixed include and exclude domains")
    func mixedDomains() {
        let result = parser.parse("site.com,~sub.site.com##.banner")
        #expect(result.cosmeticRules.count == 1)
        let rule = result.cosmeticRules[0]
        #expect(rule.selector == ".banner")
        #expect(rule.domains == ["site.com"])
        #expect(rule.excludeDomains == ["sub.site.com"])
    }

    // MARK: - Exception Rules

    @Test("Parses global exception rule")
    func globalException() {
        let result = parser.parse("#@#.cookie-banner")
        #expect(result.cosmeticRules.count == 1)
        let rule = result.cosmeticRules[0]
        #expect(rule.selector == ".cookie-banner")
        #expect(rule.isException == true)
        #expect(rule.domains == nil)
    }

    @Test("Parses domain-scoped exception rule")
    func domainScopedException() {
        let result = parser.parse("example.com#@#.ad-unit")
        #expect(result.cosmeticRules.count == 1)
        let rule = result.cosmeticRules[0]
        #expect(rule.selector == ".ad-unit")
        #expect(rule.isException == true)
        #expect(rule.domains == ["example.com"])
    }

    // MARK: - Skipped Syntax

    @Test("Skips procedural cosmetic rules")
    func skipsProcedural() {
        let result = parser.parse("example.com#?#.ad:has(> .sponsored)")
        #expect(result.cosmeticRules.isEmpty)
    }

    @Test("Skips scriptlet injection rules")
    func skipsScriptlet() {
        let result = parser.parse("example.com##+js(set-cookie, consent, 1)")
        #expect(result.cosmeticRules.isEmpty)
    }

    @Test("Skips CSS injection rules")
    func skipsCSSInjection() {
        let result = parser.parse("example.com#$#body { overflow: auto !important; }")
        #expect(result.cosmeticRules.isEmpty)
    }

    // MARK: - Mixed Content

    @Test("Parses both network and cosmetic rules from same content")
    func mixedRules() {
        let content = """
        ! EasyList Cookie
        [Adblock Plus 2.0]
        ||tracker.example.com^
        ##.cookie-consent
        example.com##.newsletter-popup
        @@||allowed.example.com^
        #@#.safe-banner
        example.com##+js(set-cookie)
        """
        let result = parser.parse(content)
        #expect(result.networkRules.count == 2) // tracker block + exception
        #expect(result.cosmeticRules.count == 3) // global hide + domain hide + exception
    }

    @Test("Handles empty selector gracefully")
    func emptySelector() {
        let result = parser.parse("example.com##")
        #expect(result.cosmeticRules.isEmpty)
    }
}

// MARK: - WebKit Cosmetic Compilation Tests

@Suite("WebKitRuleCompiler Cosmetic Rules", .tags(.filterParser))
struct WebKitRuleCompilerCosmeticTests {
    let compiler = WebKitRuleCompiler()
    let parser = FilterParser()

    @Test("Compiles global cosmetic rule to css-display-none")
    func globalCosmeticRule() throws {
        let result = parser.parse("##.cookie-banner")
        let json = compiler.compile(result)

        let data = try #require(json.data(using: .utf8))
        let rules = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(rules.count == 1)

        let rule = rules[0]
        let action = try #require(rule["action"] as? [String: String])
        #expect(action["type"] == "css-display-none")
        #expect(action["selector"] == ".cookie-banner")

        let trigger = try #require(rule["trigger"] as? [String: Any])
        #expect(trigger["url-filter"] as? String == ".*")
        #expect(trigger["if-domain"] == nil)
    }

    @Test("Compiles domain-scoped cosmetic rule with if-domain")
    func domainScopedCosmeticRule() throws {
        let result = parser.parse("example.com##.ad-unit")
        let json = compiler.compile(result)

        let data = try #require(json.data(using: .utf8))
        let rules = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(rules.count == 1)

        let trigger = try #require(rules[0]["trigger"] as? [String: Any])
        let ifDomain = try #require(trigger["if-domain"] as? [String])
        #expect(ifDomain.contains("*example.com"))
    }

    @Test("Compiles exception cosmetic rule to ignore-previous-rules")
    func exceptionCosmeticRule() throws {
        let result = parser.parse("#@#.cookie-banner")
        let json = compiler.compile(result)

        let data = try #require(json.data(using: .utf8))
        let rules = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(rules.count == 1)

        let action = try #require(rules[0]["action"] as? [String: String])
        #expect(action["type"] == "ignore-previous-rules")
    }

    @Test("Groups cosmetic rules with same domain into single rule")
    func groupsSameDomain() throws {
        let content = """
        example.com##.ad-one
        example.com##.ad-two
        """
        let result = parser.parse(content)
        let json = compiler.compile(result)

        let data = try #require(json.data(using: .utf8))
        let rules = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        // Both selectors should be merged into one rule
        #expect(rules.count == 1)
        let action = try #require(rules[0]["action"] as? [String: String])
        let selector = try #require(action["selector"])
        #expect(selector.contains(".ad-one"))
        #expect(selector.contains(".ad-two"))
    }

    @Test("Compiles mixed network and cosmetic rules together")
    func mixedCompilation() throws {
        let content = """
        ||ads.example.com^
        ##.cookie-banner
        """
        let result = parser.parse(content)
        let json = compiler.compile(result)

        let data = try #require(json.data(using: .utf8))
        let rules = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        // Should have both a block rule and a css-display-none rule
        let types = rules.compactMap { ($0["action"] as? [String: String])?["type"] }
        #expect(types.contains("block"))
        #expect(types.contains("css-display-none"))
    }

    @Test("Compiles exclude-domain cosmetic rule with unless-domain")
    func excludeDomainCosmeticRule() throws {
        let result = parser.parse("~example.com##.widget")
        let json = compiler.compile(result)

        let data = try #require(json.data(using: .utf8))
        let rules = try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(rules.count == 1)

        let trigger = try #require(rules[0]["trigger"] as? [String: Any])
        let unlessDomain = try #require(trigger["unless-domain"] as? [String])
        #expect(unlessDomain.contains("*example.com"))
    }
}
