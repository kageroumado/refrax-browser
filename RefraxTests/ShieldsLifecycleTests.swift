import CryptoKit
import Foundation
import Testing
import WebKit
@testable import Refrax

/// The test bundle, which ships no list snapshots.
private final class TestBundleAnchor {}

/// Fails every request, so a manager's background update changes nothing.
private final nonisolated class OfflineProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with _: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
    }

    override func stopLoading() {}
}

@MainActor
private final class Recorder<Value> {
    var values: [Value] = []
}

/// Launch, readiness and failure handling across the manager, the store and WebKit.
@Suite("Shields lifecycle", .tags(.shields), .serialized)
@MainActor
struct ShieldsLifecycleTests {
    private static func manager(in directory: URL) -> ContentBlockingManager {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [OfflineProtocol.self]
        return ContentBlockingManager(storageDirectory: directory, configuration: configuration, bundle: Bundle(for: TestBundleAnchor.self))
    }

    private static func writeEasyList(_ text: String, in directory: URL) throws {
        try Data(text.utf8).write(to: directory.appending(path: "easylist.txt"))
    }

    @Test
    func `A launch whose lists changed attaches the last attached build before building the new one`() async throws {
        let directory = try shieldsScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.writeEasyList("/ads/a.js$script\n", in: directory)

        func launch() async -> [String] {
            let builds = Recorder<String>()
            await Self.manager(in: directory).start(onChange: { _ in }, onBuild: { artifacts in
                builds.values.append(artifacts.key.hex)
                return .attached
            })
            return builds.values
        }

        let first = await launch()
        let firstKey = try #require(first.first)
        #expect(first.count == 1)
        #expect(await launch() == [firstKey], "an unchanged launch attaches the same build once")

        try Self.writeEasyList("/ads/b.js$script\n", in: directory)
        let changed = await launch()
        #expect(changed.count == 2)
        #expect(changed.first == firstKey, "the previous build first, while the new one compiles")
        #expect(changed.last != firstKey)
    }

    @Test
    func `A page opened during launch is held until WebKit has the lists; a page a filter blocks is kept from opening`() async throws {
        let directory = try shieldsScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try Self.writeEasyList("||blocked.test^$document\n/ads/blocked.js$script\n", in: directory)
        let server = try LoopbackServer()
        defer { server.stop() }
        let port = try await server.start()
        server.route("/page.html", body: "<script src=\"http://127.0.0.1:\(port)/ads/blocked.js\"></script>")
        server.route("/ads/blocked.js", type: "text/javascript", body: "window.blockedRan = true;")

        let configuration = WKWebViewConfiguration()
        let ruleStore = try #require(WKContentRuleListStore(url: directory.appending(path: "store", directoryHint: .isDirectory)))
        let webKit = ShieldsWebKit(userContentController: configuration.userContentController, scriptRegistry: ScriptRegistry(), store: ruleStore)
        let store = ShieldsStore(webKit: webKit, manager: Self.manager(in: directory))
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let delegate = FixtureNavigationDelegate(webKit: webKit)
        webView.navigationDelegate = delegate
        #expect(!store.isReady)

        let starting = Task { await store.start() }
        await store.waitUntilReady(timeout: .seconds(60))
        #expect(webKit.artifacts != nil, "the wait ends once WebKit has the build")
        try webView.load(URLRequest(url: #require(URL(string: "http://localhost:\(port)/page.html"))))
        try await delegate.waitForLoad()
        #expect(!server.requested.contains("/ads/blocked.js"), "the page created before launch finished is filtered")
        await starting.value

        let blocked = try #require(URL(string: "https://blocked.test/landing"))
        let fine = try #require(URL(string: "https://fine.test/"))
        let sameSite = try #require(URL(string: "https://blocked.test/other"))
        #expect(await store.blocksPage(blocked, siteIsExempt: false))
        #expect(await !store.blocksPage(blocked, siteIsExempt: true))
        #expect(await !store.blocksPage(fine, siteIsExempt: false))
        store.openAnyway(blocked)
        #expect(await !store.blocksPage(sameSite, siteIsExempt: false))
    }

    @Test
    func `A build WebKit refuses still reaches the other engines, and launch is not held for it`() async throws {
        let directory = try shieldsScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = "/ads/a.js$script\n"
        try Self.writeEasyList(text, in: directory)
        let manager = Self.manager(in: directory)

        // The build the manager will find on disk, one rules file damaged at its size.
        let source = try #require(FilterListSource.defaultLists.first { $0.id == "easylist" })
        let list = try #require(ContentBlockingManager.shieldsList(for: source, text: Data(text.utf8)))
        let resources = ShieldsResources.current(in: directory.appending(path: "resources", directoryHint: .isDirectory))
        let built = try await ShieldsCompiler().build(lists: [list], resources: resources, into: manager.buildsDirectory).artifacts
        var bytes = try Data(contentsOf: built.networkRulesURL(0))
        let index = try #require(bytes.firstIndex(of: UInt8(ascii: "a")))
        bytes[index] = UInt8(ascii: "b")
        try bytes.write(to: built.networkRulesURL(0))

        let configuration = WKWebViewConfiguration()
        let ruleStore = try #require(WKContentRuleListStore(url: directory.appending(path: "store", directoryHint: .isDirectory)))
        let webKit = ShieldsWebKit(userContentController: configuration.userContentController, scriptRegistry: ScriptRegistry(), store: ruleStore)
        let store = ShieldsStore(webKit: webKit, manager: manager)
        let policies = Recorder<ContentBlockingPolicy>()
        store.onPolicy = { policies.values.append($0) }
        await store.start()

        #expect(webKit.artifacts == nil)
        #expect(store.lastError != nil)
        #expect(policies.values.last?.isEnabled == true)
        #expect(policies.values.last?.engine?.sha256 == built.manifest.engineSHA256)
        #expect(store.isReady)
    }

    @Test
    func `The shipped list snapshots decode to filter lists`() throws {
        for id in FilterListSource.bundledListIDs {
            let text = try #require(ContentBlockingManager.bundledSnapshot(of: id), "\(id)")
            let head = String(decoding: text.prefix(64), as: UTF8.self)
            #expect(head.hasPrefix("[Adblock") || head.hasPrefix("!"), "\(id): \(head)")
            #expect(text.count > 10_000)
        }
        #expect(ContentBlockingManager.bundledSnapshot(of: "fanboy-social") == nil)
    }

    @Test
    func `Rule lists Refrax compiled per list before Shields are recognized exactly`() {
        #expect(ShieldsWebKit.isLegacyPerListIdentifier("easylist-0"))
        #expect(ShieldsWebKit.isLegacyPerListIdentifier("ublock-quick-fixes-12"))
        #expect(ShieldsWebKit.isLegacyPerListIdentifier("custom-1A2B3C4D-3"))
        #expect(!ShieldsWebKit.isLegacyPerListIdentifier("custom-rules-1"))
        #expect(!ShieldsWebKit.isLegacyPerListIdentifier("easylist"))
        #expect(!ShieldsWebKit.isLegacyPerListIdentifier("shields.network.0123456789abcdef01234567"))
        #expect(!ShieldsWebKit.isLegacyPerListIdentifier("extension.dnr-1"))
    }
}

@Suite("Shields resources releases", .tags(.shields))
struct ShieldsResourcesReleaseTests {
    private let key = Curve25519.Signing.PrivateKey()

    private var keys: ReleaseKeys {
        ReleaseKeys([key.publicKey])
    }

    private func release(domain: String = "refrax-shields-resources", version: Int) throws -> Data {
        let resources = try JSONSerialization.jsonObject(with: #require(ShieldsResources.bundled()))
        return try JSONSerialization.data(withJSONObject: ["domain": domain, "version": version, "resources": resources])
    }

    private func signature(_ data: Data) throws -> Data {
        try Data(key.signature(for: data).base64EncodedString().utf8)
    }

    private func keep(_ envelope: Data, in directory: URL) throws {
        let url = directory.appending(path: "shields-resources.release.json")
        try envelope.write(to: url)
        try signature(envelope).write(to: EngineSignature.signatureURL(for: url))
    }

    @Test
    func `A release opens only with its domain and a pinned key's signature`() throws {
        let envelope = try release(version: 2)
        let opened = try ShieldsResources.open(envelope, signatureFile: signature(envelope), keys: keys)
        #expect(opened.version == 2)
        #expect(ShieldsResources.check(opened.resources) != nil)

        let other = try release(domain: "refrax-engines", version: 2)
        #expect(throws: ShieldsResources.ReleaseError.malformed) {
            try ShieldsResources.open(other, signatureFile: signature(other), keys: keys)
        }
        let stranger = ReleaseKeys([Curve25519.Signing.PrivateKey().publicKey])
        #expect(throws: EngineDistributionError.self) {
            try ShieldsResources.open(envelope, signatureFile: signature(envelope), keys: stranger)
        }
    }

    @Test
    func `A kept release is verified on every read and used only above the bundled version`() throws {
        let directory = try shieldsScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let bundled = try #require(ShieldsResources.bundled())
        #expect(ShieldsResources.bundledVersion() == 1)

        let newer = try release(version: 2)
        try keep(newer, in: directory)
        let current = ShieldsResources.current(in: directory, keys: keys)
        #expect(current != bundled)
        #expect(ShieldsResources.check(current) != nil)

        var tampered = newer
        tampered[tampered.index(before: tampered.endIndex)] = UInt8(ascii: " ")
        try tampered.write(to: directory.appending(path: "shields-resources.release.json"))
        #expect(ShieldsResources.current(in: directory, keys: keys) == bundled, "a file changed on disk no longer verifies")

        try keep(release(version: 1), in: directory)
        #expect(ShieldsResources.current(in: directory, keys: keys) == bundled, "not above the bundled version")
    }
}
