import CloudKit
import Foundation
import SwiftData
import Testing
@testable import Refrax

private let example = EngineID(rawValue: "test.engine.example")

private func url(_ string: String) throws -> URL {
    try #require(URL(string: string))
}

// MARK: - Matching

@Suite("Site engine rule matching", .tags(.engines))
struct SiteEngineRuleMatchingTests {
    private let rules = SiteEngineRules([
        SiteEngineRule(host: "youtube.com", engine: .chromium),
        SiteEngineRule(host: "music.youtube.com", engine: .systemWebKit),
        SiteEngineRule(host: "xn--bcher-kva.example", engine: .chromium),
    ])

    @Test(arguments: [
        "https://youtube.com/watch?v=1",
        "https://www.youtube.com/",
        "https://m.youtube.com/feed",
        "http://a.b.youtube.com/",
    ])
    func `A rule covers its host and every subdomain`(address: String) throws {
        #expect(try rules.rule(for: url(address))?.host == "youtube.com")
    }

    @Test
    func `The most specific rule wins`() throws {
        #expect(try rules.rule(for: url("https://music.youtube.com/playlist"))?.engine == .systemWebKit)
        #expect(try rules.rule(for: url("https://www.music.youtube.com/"))?.host == "music.youtube.com")
    }

    @Test(arguments: [
        "https://notyoutube.com/",
        "https://youtube.com.evil.example/",
        "https://example.org/youtube.com",
    ])
    func `A host that merely contains a rule's host isn't covered`(address: String) throws {
        #expect(try rules.rule(for: url(address)) == nil)
    }

    @Test
    func `Case, ports, and a trailing dot don't matter`() throws {
        #expect(try rules.rule(for: url("https://WWW.YouTube.COM:8443/x"))?.host == "youtube.com")
        #expect(try rules.rule(for: url("https://youtube.com./"))?.host == "youtube.com")
    }

    @Test
    func `An internationalized host matches its encoded rule`() throws {
        #expect(try rules.rule(for: url("https://Bücher.example/"))?.host == "xn--bcher-kva.example")
        #expect(try rules.rule(for: url("https://shop.xn--bcher-kva.example/"))?.host == "xn--bcher-kva.example")
    }

    @Test(arguments: ["about:blank", "file:///Users/x/youtube.com", "refrax://settings", "data:text/html,youtube.com"])
    func `Only http and https URLs have rules`(address: String) throws {
        #expect(try rules.rule(for: url(address)) == nil)
    }

    @Test(arguments: [
        ("YouTube.com", "youtube.com"),
        ("  www.youtube.com  ", "youtube.com"),
        ("https://www.youtube.com/watch?v=1", "youtube.com"),
        ("youtube.com:443", "youtube.com"),
        ("bücher.example", "xn--bcher-kva.example"),
        ("www.com", "www.com"),
        ("music.youtube.com.", "music.youtube.com"),
    ])
    func `Typed hosts are stored in canonical form`(input: String, expected: String) {
        #expect(SiteEngineRules.canonicalHost(input) == expected)
    }

    @Test(arguments: ["", "   ", "two words.com", "a..b", ".com", "exa$mple.com"])
    func `Text that isn't a host name is refused`(input: String) {
        #expect(SiteEngineRules.canonicalHost(input) == nil)
    }
}

// MARK: - Editing

@Suite("Site engine rule editing", .tags(.engines))
struct SiteEngineRuleEditingTests {
    @Test
    func `Setting a host's engine replaces its rule in place`() {
        var rules = SiteEngineRules([
            SiteEngineRule(host: "a.example", engine: .chromium),
            SiteEngineRule(host: "b.example", engine: .chromium),
        ])
        #expect(rules.set(.systemWebKit, for: "WWW.A.example") == "a.example")
        #expect(rules.rules.map(\.host) == ["a.example", "b.example"])
        #expect(rules.rules.first?.engine == .systemWebKit)
    }

    @Test
    func `Renaming keeps the place and refuses a duplicate`() {
        var rules = SiteEngineRules([
            SiteEngineRule(host: "a.example", engine: .chromium),
            SiteEngineRule(host: "b.example", engine: .systemWebKit),
        ])
        let duplicate = rules.rename("a.example", to: "b.example")
        let invalid = rules.rename("a.example", to: "not a host")
        let renamed = rules.rename("a.example", to: "c.example")
        #expect(!duplicate)
        #expect(!invalid)
        #expect(renamed)
        #expect(rules.rules == [
            SiteEngineRule(host: "c.example", engine: .chromium),
            SiteEngineRule(host: "b.example", engine: .systemWebKit),
        ])
    }

    @Test
    func `Removing takes the rule for exactly that host`() {
        var rules = SiteEngineRules.defaults
        #expect(rules.remove(host: "www.youtube.com")?.host == "youtube.com")
        #expect(rules.remove(host: "youtube.com") == nil)
        #expect(rules.rules.map(\.host) == ["youtu.be", "youtube-nocookie.com"])
    }

    @Test
    func `Duplicate hosts keep their first rule`() {
        let rules = SiteEngineRules([
            SiteEngineRule(host: "a.example", engine: .chromium),
            SiteEngineRule(host: "a.example", engine: .systemWebKit),
        ])
        #expect(rules.rules == [SiteEngineRule(host: "a.example", engine: .chromium)])
    }
}

// MARK: - Storage

@Suite("Site engine rule storage", .tags(.engines), .serialized)
@MainActor
struct SiteEngineRuleStorageTests {
    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    @Test
    func `New settings open YouTube in Chromium`() throws {
        let settings = BrowserSettings()
        #expect(settings.siteEngineRulesJSON == nil)
        #expect(settings.siteEngineRules == .defaults)
        for address in ["https://www.youtube.com/watch?v=1", "https://youtu.be/abc", "https://www.youtube-nocookie.com/embed/x"] {
            #expect(try settings.siteEngineRules.rule(for: url(address))?.engine == .chromium)
        }
    }

    @Test
    func `Rules round-trip through JSON, including an empty list`() throws {
        let settings = BrowserSettings()
        var rules = SiteEngineRules([SiteEngineRule(host: "example.com", engine: example)])
        rules.set(.chromium, for: "youtube.com")
        settings.siteEngineRules = rules
        #expect(settings.siteEngineRules == rules)

        settings.siteEngineRules = SiteEngineRules()
        #expect(settings.siteEngineRulesJSON != nil)
        #expect(settings.siteEngineRules.rules.isEmpty)

        let data = try JSONEncoder().encode(rules)
        #expect(try JSONDecoder().decode(SiteEngineRules.self, from: data) == rules)
        let json = try #require(String(data: data, encoding: .utf8))
        #expect(json.contains(#""engine":"test.engine.example""#))
    }

    @Test
    func `Reset returns the default rules`() {
        let settings = BrowserSettings()
        settings.siteEngineRules = SiteEngineRules()
        settings.resetToDefaults()
        #expect(settings.siteEngineRules == .defaults)
    }

    @Test
    func `Rules sync through the settings record`() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let settings = BrowserSettings()
        settings.siteEngineRules = SiteEngineRules([SiteEngineRule(host: "example.com", engine: .chromium)])
        context.insert(settings)
        try context.save()

        let record = CKRecord(
            recordType: BrowserSettings.ckRecordType,
            recordID: CKRecord.ID(recordName: BrowserSettings.singletonRecordName, zoneID: RecordMapper.zoneID),
        )
        settings.encodeToRecord(record)
        settings.siteEngineRulesJSON = nil

        let applied = try BrowserSettings.applyRecord(record, into: context)
        #expect(applied.siteEngineRules.rules == [SiteEngineRule(host: "example.com", engine: .chromium)])
    }

    @Test
    func `The pin migration clears only pins naming the default engine, once`() throws {
        let container = try Self.makeContainer()
        let context = ModelContext(container)
        let defaultPin = try TabPage(url: url("https://a.example"))
        defaultPin.engineID = EngineID.systemWebKit.rawValue
        let realPin = try TabPage(url: url("https://b.example"))
        realPin.engineID = EngineID.chromium.rawValue
        let unpinned = try TabPage(url: url("https://c.example"))
        for page in [defaultPin, realPin, unpinned] {
            context.insert(page)
        }
        try context.save()

        let defaults = try #require(UserDefaults(suiteName: "SiteEngineRuleStorageTests.\(UUID().uuidString)"))
        #expect(EnginePinMigration.runOnce(in: context, defaultEngine: .systemWebKit, defaults: defaults) == 1)
        #expect(defaultPin.engineID == nil)
        #expect(realPin.engineID == EngineID.chromium.rawValue)
        #expect(unpinned.engineID == nil)

        realPin.engineID = EngineID.systemWebKit.rawValue
        #expect(EnginePinMigration.runOnce(in: context, defaultEngine: .systemWebKit, defaults: defaults) == 0)
        #expect(realPin.engineID == EngineID.systemWebKit.rawValue)
    }
}

// MARK: - Precedence

@Suite("Engine choice precedence", .tags(.engines))
struct EngineChoicePrecedenceTests {
    private let rules = SiteEngineRules([
        SiteEngineRule(host: "youtube.com", engine: .chromium),
        SiteEngineRule(host: "example.com", engine: example),
    ])

    private func choice(default defaultEngine: EngineID = .systemWebKit, usable: Set<EngineID> = [.chromium]) -> EngineChoice {
        EngineChoice(rules: rules, defaultEngine: defaultEngine, usable: usable)
    }

    @Test
    func `A pin beats the site rule, which beats the default`() throws {
        let youtube = try url("https://www.youtube.com/")
        let other = try url("https://kagerou.glass/")
        #expect(choice().startingEngine(for: youtube, pinned: .systemWebKit) == .systemWebKit)
        #expect(choice().startingEngine(for: youtube, pinned: nil) == .chromium)
        #expect(choice().startingEngine(for: other, pinned: nil) == .systemWebKit)
        #expect(choice(default: .chromium).startingEngine(for: other, pinned: nil) == .chromium)
        #expect(choice().startingEngine(for: other, pinned: .chromium) == .chromium)
    }

    @Test
    func `A rule or pin naming an engine that isn't usable is inert`() throws {
        let page = try url("https://example.com/")
        #expect(choice().startingEngine(for: page, pinned: nil) == .systemWebKit)
        #expect(choice(default: .chromium).startingEngine(for: page, pinned: nil) == .chromium)
        #expect(try choice(usable: []).startingEngine(for: url("https://youtube.com/"), pinned: .chromium) == .systemWebKit)
        #expect(try choice(default: example, usable: []).automaticEngine(for: url("https://kagerou.glass/")) == .systemWebKit)
    }

    @Test
    func `Moving a page to the engine it gets anyway leaves it unpinned`() throws {
        let youtube = try url("https://youtube.com/")
        #expect(choice().pin(movingTo: .chromium, at: youtube) == nil)
        #expect(choice().pin(movingTo: .systemWebKit, at: youtube) == .systemWebKit)
        #expect(try choice().pin(movingTo: .chromium, at: url("https://kagerou.glass/")) == .chromium)
        #expect(try choice().pin(movingTo: .systemWebKit, at: url("https://kagerou.glass/")) == nil)
    }

    @Test
    func `The menus offer to remove the covering rule, else to add one per other engine`() throws {
        let installed: [EngineID] = [.systemWebKit, .chromium]
        #expect(try choice().ruleActions(for: url("https://m.youtube.com/"), installed: installed)
            == [.remove(SiteEngineRule(host: "youtube.com", engine: .chromium))])
        #expect(try choice().ruleActions(for: url("https://www.kagerou.glass/x"), installed: installed)
            == [.add(host: "kagerou.glass", engine: .chromium)])
        #expect(try choice(default: .chromium).ruleActions(for: url("https://kagerou.glass/"), installed: installed)
            == [.add(host: "kagerou.glass", engine: .systemWebKit)])
        #expect(try choice().ruleActions(for: url("about:blank"), installed: installed).isEmpty)
    }
}

// MARK: - Navigation Switches

@Suite("Engine switches for navigations", .tags(.engines, .navigation))
struct EngineNavigationSwitchTests {
    private let choice = EngineChoice(
        rules: SiteEngineRules([SiteEngineRule(host: "youtube.com", engine: .chromium)]),
        defaultEngine: .systemWebKit,
        usable: [.chromium],
    )

    private func navigation(
        to target: String,
        from page: String?,
        in engine: EngineID,
        isPinned: Bool = false,
        isExtensionPage: Bool = false,
        hasSwitched: Bool = false,
    ) throws -> EngineNavigation {
        try EngineNavigation(
            url: url(target),
            pageURL: page.map(url),
            activeEngine: engine,
            isPinned: isPinned,
            isExtensionPage: isExtensionPage,
            hasSwitched: hasSwitched,
        )
    }

    @Test
    func `Entering a ruled site switches to its engine`() throws {
        #expect(try choice.engineSwitch(for: navigation(to: "https://www.youtube.com/", from: "https://kagerou.glass/", in: .systemWebKit)) == .chromium)
        #expect(try choice.engineSwitch(for: navigation(to: "https://youtube.com/", from: nil, in: .systemWebKit)) == .chromium)
        #expect(try choice.engineSwitch(for: navigation(to: "https://youtube.com/", from: "about:blank", in: .systemWebKit)) == .chromium)
    }

    @Test
    func `Leaving a ruled site returns to the default engine`() throws {
        #expect(try choice.engineSwitch(for: navigation(to: "https://kagerou.glass/", from: "https://www.youtube.com/", in: .chromium)) == .systemWebKit)
    }

    @Test
    func `Moving between hosts of the same rule stays put`() throws {
        #expect(try choice.engineSwitch(for: navigation(to: "https://m.youtube.com/", from: "https://www.youtube.com/", in: .chromium)) == nil)
    }

    @Test
    func `Same-host navigations never switch`() throws {
        #expect(try choice.engineSwitch(for: navigation(to: "https://www.youtube.com/b", from: "https://www.youtube.com/a", in: .systemWebKit)) == nil)
        #expect(try choice.engineSwitch(for: navigation(to: "https://kagerou.glass/b", from: "https://kagerou.glass/a", in: .chromium)) == nil)
    }

    @Test
    func `Pinned and extension pages stay in their engine`() throws {
        #expect(try choice.engineSwitch(for: navigation(to: "https://youtube.com/", from: "https://kagerou.glass/", in: .systemWebKit, isPinned: true)) == nil)
        #expect(try choice.engineSwitch(for: navigation(to: "https://youtube.com/", from: "https://kagerou.glass/", in: .systemWebKit, isExtensionPage: true)) == nil)
    }

    @Test
    func `A navigation switches at most once`() throws {
        #expect(try choice.engineSwitch(for: navigation(to: "https://accounts.example/", from: "https://youtube.com/", in: .chromium, hasSwitched: true)) == nil)
        #expect(try choice.engineSwitch(for: navigation(to: "https://youtube.com/", from: "https://accounts.example/", in: .systemWebKit, hasSwitched: true)) == nil)
    }

    @Test
    func `A rule for an engine that isn't installed never switches`() throws {
        let uninstalled = EngineChoice(rules: .defaults, defaultEngine: .systemWebKit, usable: [])
        #expect(try uninstalled.engineSwitch(for: navigation(to: "https://youtube.com/", from: "https://kagerou.glass/", in: .systemWebKit)) == nil)
    }

    @Test(arguments: ["about:blank", "file:///tmp/a.html", "refrax://settings"])
    func `Only http and https destinations switch`(target: String) throws {
        #expect(try choice.engineSwitch(for: navigation(to: target, from: "https://youtube.com/", in: .chromium)) == nil)
    }
}
