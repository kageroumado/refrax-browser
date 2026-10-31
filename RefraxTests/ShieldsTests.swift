import Foundation
import os
import Testing
@testable import Refrax

extension Tag {
    /// Shields: the adblock-rust library, builds, the request logger.
    @Tag static var shields: Self
}

/// A fresh directory under the temporary directory, removed by the caller.
func shieldsScratchDirectory() throws -> URL {
    let directory = FileManager.default.temporaryDirectory.appending(path: "shields-tests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    return directory
}

@Suite("Shields library", .tags(.shields))
struct ShieldsLibraryTests {
    @Test
    func `The linked library speaks the C interface Refrax was built against`() {
        #expect(ShieldsEngine.abiVersion == 1)
        #expect(ShieldsEngine.format.hasPrefix("adblock-0.13.3;"))
        #expect(ShieldsEngine.webKitPassVersion >= 1)
    }

    @Test
    func `The bundled resources hold uBlock Origin's scriptlets and redirect resources`() throws {
        let resources = try #require(ShieldsResources.bundled())
        let summary = try #require(ShieldsResources.check(resources))
        #expect(summary.scriptlets >= 100)
        #expect(summary.redirects >= 40)
    }

    @Test
    func `A resources file with a missing dependency is rejected`() {
        let broken = Data(#"[{"name":"a.js","kind":{"mime":"application/javascript"},"content":"","dependencies":["gone.fn"]}]"#.utf8)
        #expect(ShieldsResources.check(broken) == nil)
        #expect(ShieldsResources.check(Data("not json".utf8)) == nil)
    }

    @Test
    func `A corrupt DAT is refused`() {
        #expect(throws: ShieldsError.unreadableEngine) {
            try ShieldsEngine(dat: Data(repeating: 0, count: 64), resources: Data("[]".utf8))
        }
    }
}

@Suite("Shields cache key", .tags(.shields))
struct ShieldsKeyTests {
    private let easyList = ShieldsList(id: "easylist", text: Data("||ads.example^\n".utf8))
    private let unbreak = ShieldsList(id: "ublock-unbreak", text: Data("@@||ads.example/ok^\n".utf8), isTrusted: true)
    private let resources = Data("[]".utf8)

    @Test
    func `The same inputs give the same key`() {
        #expect(ShieldsKey(lists: [easyList, unbreak], resources: resources) == ShieldsKey(lists: [easyList, unbreak], resources: resources))
    }

    @Test
    func `Text, trust, order, resources and the library format each change the key`() {
        let base = ShieldsKey(lists: [easyList, unbreak], resources: resources)
        let edited = ShieldsList(id: "easylist", text: Data("||ads.example^\n||more.example^\n".utf8))
        var untrusted = unbreak
        untrusted.isTrusted = false
        #expect(ShieldsKey(lists: [edited, unbreak], resources: resources) != base)
        #expect(ShieldsKey(lists: [easyList, untrusted], resources: resources) != base)
        #expect(ShieldsKey(lists: [unbreak, easyList], resources: resources) != base)
        #expect(ShieldsKey(lists: [easyList, unbreak], resources: Data("[ ]".utf8)) != base)
        #expect(ShieldsKey(lists: [easyList, unbreak], resources: resources, format: "adblock-0.14.0;shields-1") != base)
        #expect(base.hex.count == 64)
        #expect(base.shortForm.count == 12)
    }
}

@Suite("Shields compiler", .tags(.shields))
struct ShieldsCompilerTests {
    private static let lists = [
        ShieldsList(id: "easylist", text: Data("||ads.example^\n##.generic-ad\nexample.com##.banner\n".utf8)),
        ShieldsList(
            id: "ublock-filters",
            text: Data("@@||ads.example/allowed.js^\nexample.com##+js(set-constant, adsEnabled, false)\n".utf8),
            isTrusted: true,
        ),
    ]

    @Test
    func `A build writes both DATs, the WebKit artifacts and a manifest; a second build reuses it`() async throws {
        let root = try shieldsScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = try #require(ShieldsResources.bundled())
        let compiler = ShieldsCompiler()

        let (built, engine) = try await compiler.build(lists: Self.lists, resources: resources, into: root)
        #expect(engine != nil)
        #expect(built.manifest.lists.map(\.id) == ["easylist", "ublock-filters"])
        #expect(built.manifest.lists.map(\.sourceIndex) == [0, 1])
        #expect(built.manifest.lists[0].stats.network == 1)
        #expect(built.manifest.webKit.networkLists == 1)
        #expect(built.manifest.webKit.cosmeticLists == 1)
        #expect(built.manifest.webKit.scripts >= 1)
        for file in [built.engineURL, built.debugEngineURL, built.resourcesURL, built.networkRulesURL(0), built.cosmeticRulesURL(0), built.scriptsURL] {
            #expect(FileManager.default.fileExists(atPath: file.path), "\(file.lastPathComponent)")
        }

        let (cached, cachedEngine) = try await compiler.build(lists: Self.lists, resources: resources, into: root)
        #expect(cachedEngine == nil, "a warm build compiles nothing")
        #expect(cached == built)
    }

    @Test
    func `The debug engine explains a block, and an exception from another list lifts it`() async throws {
        let root = try shieldsScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = try #require(ShieldsResources.bundled())
        let (_, built) = try await ShieldsCompiler().build(lists: Self.lists, resources: resources, into: root)
        let engine = try #require(built)

        let blocked = try #require(engine.explain(url: "https://ads.example/x.js", source: "https://example.com/", type: "script"))
        #expect(blocked.shouldBlock)
        #expect(blocked.rule?.text == "||ads.example^")
        #expect(blocked.rule?.sourceIndex == 0)

        let allowed = try #require(engine.explain(url: "https://ads.example/allowed.js", source: "https://example.com/", type: "script"))
        #expect(!allowed.shouldBlock)
        #expect(allowed.exception?.text == "@@||ads.example/allowed.js^")
        #expect(allowed.exception?.sourceIndex == 1)

        let page = try #require(URL(string: "https://example.com/"))
        let cosmetics = try #require(engine.cosmeticResources(for: page))
        #expect(cosmetics.hideSelectors.contains(".banner"))
        #expect(cosmetics.injectedScript.contains("setConstant("))
    }

    @Test
    func `The host's DAT loads and decides like the app's engine`() async throws {
        let root = try shieldsScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let resources = try #require(ShieldsResources.bundled())
        let (built, _) = try await ShieldsCompiler().build(lists: Self.lists, resources: resources, into: root)
        let host = try ShieldsEngine(dat: Data(contentsOf: built.engineURL), resources: Data(contentsOf: built.resourcesURL))
        let explanation = try #require(host.explain(url: "https://ads.example/x.js", source: "https://example.com/", type: "script"))
        #expect(explanation.shouldBlock)
        #expect(explanation.rule?.text == nil, "the host's DAT carries no rule text")
    }
}

@Suite("Filter list sources", .tags(.shields))
struct FilterListSourceTests {
    @Test
    func `A saved built-in list takes its current default URL and keeps its state`() throws {
        var saved = try #require(FilterListSource.defaultLists.first { $0.id == "easylist-cookie" })
        saved.url = URL.staticRequired("https://easylist.to/easylist/easylist-cookie.txt")
        saved.isEnabled = false
        saved.ruleCount = 42

        let updated = try #require(FilterListSource.reconciled([saved]).first)

        #expect(updated.url.absoluteString == "https://ublockorigin.github.io/uAssets/thirdparties/easylist-cookies.txt")
        #expect(updated.isEnabled == false)
        #expect(updated.ruleCount == 42)
    }

    @Test
    func `Built-in lists missing from a saved set are added as shipped, and custom lists stay`() {
        let custom = FilterListSource(
            id: "custom-1234abcd",
            name: "Mine",
            url: URL.staticRequired("https://example.com/list.txt"),
            category: .custom,
            isEnabled: true,
            updateFrequency: FilterListSource.dailyUpdates,
        )
        let reconciled = FilterListSource.reconciled([custom])
        #expect(reconciled.first == custom)
        #expect(reconciled.contains { $0.id == "ublock-unbreak" && $0.isEnabled })
        #expect(reconciled.contains { $0.id == "liste-fr" && !$0.isEnabled })
        #expect(Set(reconciled.map(\.id)).count == reconciled.count)
    }

    @Test
    func `Only uBlock Origin's lists are trusted with trusted scriptlets`() throws {
        #expect(try #require(FilterListSource.defaultLists.first { $0.id == "ublock-filters" }).isTrusted)
        #expect(try !(#require(FilterListSource.defaultLists.first { $0.id == "easylist" }).isTrusted))
    }
}

@Suite("Request log", .tags(.shields))
struct RequestLogTests {
    @Test
    func `An engine's log decodes with absent optional keys, and bad URLs are rejected`() throws {
        let json = Data(#"""
        {"entries":[
          {"seq":1,"time":1700000000.5,"frameURL":null,"url":"https://ads.test/a.js","type":"script","method":"GET","decision":"blocked","exactness":"exact"},
          {"seq":2,"time":1700000001,"frameURL":"https://site.test/","url":"https://site.test/?utm_source=x","type":"main_frame","method":"GET","decision":"rewritten","rewrittenURL":"https://site.test/","exactness":"exact"}
        ],"nextSequence":2}
        """#.utf8)
        let log = try EngineWire.decodeRequestLog(json)
        #expect(log.entries.count == 2)
        #expect(log.entries[0].rule == nil)
        #expect(log.entries[0].frameURL == nil)
        #expect(log.entries[1].rewrittenURL?.absoluteString == "https://site.test/")
        #expect(log.nextSequence == 2)

        let hostile = Data(#"""
        {"entries":[{"seq":1,"time":1,"url":"javascript:alert(1)","type":"script","method":"GET",
        "decision":"blocked","exactness":"exact"}],"nextSequence":1}
        """#.utf8)
        #expect(throws: EngineError.self) { try EngineWire.decodeRequestLog(hostile) }
    }

    @Test
    func `Attribution names the rule and its list for entries an engine left bare`() async throws {
        let root = try shieldsScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let lists = [ShieldsList(id: "easyprivacy", text: Data("||tracker.test^$third-party\n".utf8))]
        let (_, built) = try await ShieldsCompiler().build(lists: lists, resources: Data("[]".utf8), into: root)
        let engine = try #require(built)
        let bare = try RequestLog(
            entries: [RequestLogEntry(
                seq: 1, time: .now, frameURL: URL(string: "https://site.test/"), url: #require(URL(string: "https://tracker.test/p.gif")),
                type: "image", method: "GET", decision: .blocked, exactness: .exact,
            )],
            nextSequence: 1,
        )
        let named = bare.attributed(using: engine, lists: [0: "easyprivacy"])
        #expect(named.entries[0].rule == "||tracker.test^$third-party")
        #expect(named.entries[0].list == "easyprivacy")
        #expect(named.entries[0].line == 0)
        #expect(named.entries[0].exactness == .exact)
    }

    @Test
    @MainActor
    func `The WebKit log keeps the newest 2,000 entries and counts blocks per document`() throws {
        let log = ShieldsRequestLog()
        for index in 0 ..< 2_050 {
            try log.record(url: #require(URL(string: "https://ads.test/\(index).js")), frameURL: nil, decision: .blocked)
        }
        #expect(log.entries.count == 2_000)
        #expect(log.entries.first?.seq == 51)
        #expect(log.blockedCount == 2_050)
        #expect(log.log(since: 2_040).entries.count == 10)
        log.documentCommitted()
        #expect(log.blockedCount == 0)
        #expect(log.entries.first?.type == "script")
    }
}

@Suite("Custom filter lists", .tags(.shields))
struct CustomFilterListTests {
    private func custom(_ url: String, allowsScriptlets: Bool? = nil) throws -> FilterListSource {
        var source = try FilterListSource(
            id: "custom-abcd1234",
            name: "Mine",
            url: #require(URL(string: url)),
            category: .custom,
            isEnabled: true,
            updateFrequency: FilterListSource.dailyUpdates,
        )
        source.allowsScriptlets = allowsScriptlets
        return source
    }

    @Test
    func `A custom list URL is HTTPS: http moves to https, other schemes are refused`() {
        #expect(FilterListSource.customListURL(from: "https://lists.example/a.txt")?.absoluteString == "https://lists.example/a.txt")
        #expect(FilterListSource.customListURL(from: " http://lists.example/a.txt ")?.absoluteString == "https://lists.example/a.txt")
        #expect(FilterListSource.customListURL(from: "http://lists.example:80/a.txt")?.absoluteString == "https://lists.example/a.txt")
        #expect(FilterListSource.customListURL(from: "ftp://lists.example/a.txt") == nil)
        #expect(FilterListSource.customListURL(from: "javascript:alert(1)") == nil)
        #expect(FilterListSource.customListURL(from: "https:///a.txt") == nil)
    }

    @Test
    func `A stored http list is neither fetched nor built`() throws {
        let insecure = try custom("http://lists.example/a.txt", allowsScriptlets: true)
        #expect(!insecure.isFetchable)
        #expect(ContentBlockingManager.shieldsList(for: insecure, text: Data("||ads.example^\n".utf8)) == nil)
        let builtInListsAreHTTPS = FilterListSource.allAvailableLists.allSatisfy(\.isFetchable)
        #expect(builtInListsAreHTTPS)
    }

    @Test
    func `Adding an http list is refused`() async throws {
        let directory = try shieldsScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let manager = ContentBlockingManager(storageDirectory: directory)
        let added = try await manager.addCustomFilterList(name: "Mine", url: #require(URL(string: "http://lists.example/a.txt")))
        #expect(added == nil)
        #expect(await manager.filterLists.isEmpty)
    }

    @Test(arguments: ["\n", "\r\n", "\r", "mixed"])
    func `A custom list runs scriptlets only when the user trusted it, whatever its line endings`(ending: String) async throws {
        let lines = ["example.com##.banner", "example.com##+js(set-constant, adsEnabled, false)", "example.com#@#+js(nowebrtc)"]
        let text = if ending == "mixed" {
            lines[0] + "\r\n" + lines[1] + "\r" + lines[1] + "\n" + lines[2] + "\r\n"
        } else {
            lines.joined(separator: ending) + ending
        }
        let untrusted = try #require(ContentBlockingManager.shieldsList(for: custom("https://lists.example/a.txt"), text: Data(text.utf8)))
        let trusted = try #require(ContentBlockingManager.shieldsList(
            for: custom("https://lists.example/a.txt", allowsScriptlets: true),
            text: Data(text.utf8),
        ))
        #expect(!untrusted.allowsScriptlets && trusted.allowsScriptlets)
        #expect(!untrusted.isTrusted && !trusted.isTrusted, "custom lists never get uBO's trusted scriptlets")

        let resources = try #require(ShieldsResources.bundled())
        let page = try #require(URL(string: "https://example.com/"))
        let root = try shieldsScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let untrustedEngine = try #require(try await ShieldsCompiler().build(lists: [untrusted], resources: resources, into: root).engine)
        let untrustedCosmetics = try #require(untrustedEngine.cosmeticResources(for: page))
        #expect(untrustedCosmetics.injectedScript.isEmpty, "\(ending.debugDescription): \(untrustedCosmetics.injectedScript.prefix(80))")
        if ending != "\r" {
            // A lone-CR file is one line to adblock-rust, so it has no filters to compare.
            #expect(untrustedCosmetics.hideSelectors.contains(".banner"))
            let trustedEngine = try #require(try await ShieldsCompiler().build(lists: [trusted], resources: resources, into: root).engine)
            let trustedCosmetics = try #require(trustedEngine.cosmeticResources(for: page))
            #expect(trustedCosmetics.injectedScript.contains("setConstant("))
        }
    }

    @Test
    func `A list fetch refuses a redirect through http and keeps no text`() async throws {
        let directory = try shieldsScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [RedirectingListProtocol.self]
        let manager = ContentBlockingManager(storageDirectory: directory, configuration: configuration)

        let hop = try #require(URL(string: "https://lists.example/hop.txt"))
        let safe = try #require(URL(string: "https://lists.example/safe.txt"))
        let refused = try #require(await manager.addCustomFilterList(name: "Hop", url: hop))
        let refusedState = try #require(await manager.filterLists.first { $0.id == refused.id })
        #expect(refusedState.lastError == ShieldsListError.insecureURL.errorDescription)
        #expect(!FileManager.default.fileExists(atPath: directory.appending(path: "\(refused.id).txt").path))
        let requested = RedirectingListProtocol.requested.withLock { $0 }
        #expect(!requested.contains { $0.contains("mitm.example") || $0.contains("attacker.example") })

        let allowed = try #require(await manager.addCustomFilterList(name: "Safe", url: safe))
        let allowedState = try #require(await manager.filterLists.first { $0.id == allowed.id })
        #expect(allowedState.lastError == nil, "an https-to-https redirect is fine")
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "\(allowed.id).txt").path))
    }
}

/// Serves filter lists behind redirects: `hop.txt` goes https → http → https, `safe.txt`
/// https → https; everything else answers with a list.
private final nonisolated class RedirectingListProtocol: URLProtocol, @unchecked Sendable {
    static let requested = OSAllocatedUnfairLock<[String]>(initialState: [])

    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.requested.withLock { $0.append(url.absoluteString) }
        switch url.absoluteString {
        case "https://lists.example/hop.txt": redirect(to: "http://mitm.example/hop.txt")
        case "http://mitm.example/hop.txt": redirect(to: "https://attacker.example/list.txt")
        case "https://lists.example/safe.txt": redirect(to: "https://cdn.example/list.txt")
        default:
            let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)
            if let response {
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            }
            client?.urlProtocol(self, didLoad: Data("example.com##+js(set-constant, adsEnabled, false)\n".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}

    private func redirect(to target: String) {
        guard let url = request.url, let targetURL = URL(string: target),
              let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target])
        else { return }
        client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: targetURL), redirectResponse: response)
    }
}
