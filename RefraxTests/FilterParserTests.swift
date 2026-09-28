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

    /// The WebKit rules a filter list compiles to.
    private func compiledRules(_ content: String) throws -> [[String: Any]] {
        let json = compiler.compile(parser.parse(content))
        let data = try #require(json.data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
    }

    @Test("A network rule without a party option blocks first-party requests too")
    func networkRuleMatchesBothParties() throws {
        let rules = try compiledRules("""
        /pagead/*
        ||tracker.example^$third-party
        """)
        let triggers = rules.compactMap { $0["trigger"] as? [String: Any] }
        let pagead = try #require(triggers.first { ($0["url-filter"] as? String)?.contains("pagead") == true })
        #expect(pagead["load-type"] == nil)

        let tracker = try #require(triggers.first { ($0["url-filter"] as? String)?.contains("tracker") == true })
        #expect(tracker["load-type"] as? [String] == ["third-party"])
    }

    @Test("A global exception drops the selector and emits no rule-cancelling action")
    func globalExceptionDropsSelector() throws {
        let rules = try compiledRules("""
        ||ads.example.com^
        ##.cookie-banner
        ##.ad-unit
        #@#.cookie-banner
        """)

        let actions = rules.compactMap { $0["action"] as? [String: String] }
        #expect(!actions.contains { $0["type"] == "ignore-previous-rules" })
        #expect(actions.contains { $0["type"] == "block" })

        let selectors = actions.compactMap { $0["selector"] }
        #expect(selectors == [".ad-unit"])
    }

    @Test("A domain exception excludes its domains from a generic hiding rule")
    func domainExceptionExcludesDomains() throws {
        let rules = try compiledRules("""
        ##.sponsored
        example.com#@#.sponsored
        """)
        #expect(rules.count == 1)

        let trigger = try #require(rules[0]["trigger"] as? [String: Any])
        #expect(trigger["unless-domain"] as? [String] == ["*example.com"])
        let action = try #require(rules[0]["action"] as? [String: String])
        #expect(action["selector"] == ".sponsored")
    }

    @Test("A domain exception removes its domains, and their subdomains, from a scoped rule")
    func domainExceptionNarrowsScopedRule() throws {
        let rules = try compiledRules("""
        example.com,sub.other.org,news.site##.promo
        other.org#@#.promo
        """)
        #expect(rules.count == 1)

        let trigger = try #require(rules[0]["trigger"] as? [String: Any])
        #expect(trigger["if-domain"] as? [String] == ["*example.com", "*news.site"])
    }

    @Test("A domain exception covering every domain of a scoped rule drops it")
    func domainExceptionDropsScopedRule() throws {
        let rules = try compiledRules("""
        example.com##.promo
        example.com#@#.promo
        """)
        #expect(rules.isEmpty)
    }

    @Test("An exception leaves other selectors on the same domains hidden")
    func exceptionOnlyAffectsItsSelector() throws {
        let rules = try compiledRules("""
        example.com##.promo
        example.com##.banner
        example.com#@#.promo
        """)
        #expect(rules.count == 1)
        let action = try #require(rules[0]["action"] as? [String: String])
        #expect(action["selector"] == ".banner")
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
