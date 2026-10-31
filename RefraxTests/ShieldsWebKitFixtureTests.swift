import Foundation
import Testing
import WebKit
@testable import Refrax

/// One Shields build installed into a fresh `WKWebView`, serving pages from a loopback server
/// on `localhost` (first party) and `127.0.0.1` (third party).
@MainActor
private final class ShieldsFixture {
    let root: URL
    let server: LoopbackServer
    let port: UInt16
    let webKit: ShieldsWebKit
    let artifacts: ShieldsArtifacts
    let webView: WKWebView
    private let delegate: FixtureNavigationDelegate

    init(filters: String) async throws {
        self.root = try shieldsScratchDirectory()
        self.server = try LoopbackServer()
        self.port = try await server.start()
        let resources = try #require(ShieldsResources.bundled())
        let list = ShieldsList(id: "ublock-filters", text: Data(filters.utf8), isTrusted: true)
        self.artifacts = try await ShieldsCompiler().build(lists: [list], resources: resources, into: root).artifacts
        let configuration = WKWebViewConfiguration()
        let store = try #require(WKContentRuleListStore(url: root.appending(path: "store", directoryHint: .isDirectory)))
        self.webKit = ShieldsWebKit(userContentController: configuration.userContentController, scriptRegistry: ScriptRegistry(), store: store)
        try await webKit.install(artifacts)
        self.webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        self.delegate = FixtureNavigationDelegate(webKit: webKit)
        webView.navigationDelegate = delegate
    }

    /// Serves `html` at `/page.html` on localhost and loads it.
    func open(_ html: String) async throws {
        server.route("/page.html", body: html)
        try webView.load(URLRequest(url: #require(URL(string: "http://localhost:\(port)/page.html"))))
        try await delegate.waitForLoad()
    }

    func value(_ expression: String) async throws -> Any? {
        try await webView.evaluateJavaScript(expression)
    }

    /// `expression` once it is true, polling for up to two seconds.
    func eventually(_ expression: String) async throws -> Bool {
        for _ in 0 ..< 20 {
            if try await value(expression) as? Bool == true {
                return true
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    func tearDown() {
        server.stop()
        try? FileManager.default.removeItem(at: root)
    }
}

@Suite("Shields in WebKit: page scope and hostless frames", .tags(.shields), .serialized)
@MainActor
struct ShieldsWebKitFixtureTests {
    @Test
    func `A removeparam filter for a blocked URL leaves the block in force`() async throws {
        let fixture = try await ShieldsFixture(filters: """
        /ads/track.js$script
        $removeparam=utm_source
        """)
        defer { fixture.tearDown() }
        fixture.server.route("/ads/track.js", type: "text/javascript", body: "window.trackRan = true;")
        fixture.server.route("/ads/track.js?utm_source=x", type: "text/javascript", body: "window.trackRan = true;")
        fixture.server.route("/ok.js", type: "text/javascript", body: "window.okRan = true;")
        try await fixture.open("""
        <!doctype html><html><head>
        <script src="http://127.0.0.1:\(fixture.port)/ads/track.js?utm_source=x"></script>
        <script src="http://127.0.0.1:\(fixture.port)/ok.js?utm_source=x"></script>
        </head><body></body></html>
        """)
        #expect(!fixture.server.requested.contains { $0.hasPrefix("/ads/track.js") }, "requested: \(fixture.server.requested)")
        #expect(try await fixture.value("window.trackRan === true") as? Bool == false)
        #expect(
            fixture.server.requested.contains { $0.hasPrefix("/ok.js") && !$0.contains("utm_source") },
            "the parameter is still removed elsewhere",
        )
    }

    @Test
    func `A generichide page keeps generic hides off for every load; a document exception lifts its third-party blocks`() async throws {
        let fixture = try await ShieldsFixture(filters: """
        ##.generic-ad
        /ads/blocked.js$script
        @@||localhost^$generichide
        """)
        defer { fixture.tearDown() }
        fixture.server.route("/ads/blocked.js", type: "text/javascript", body: "window.blockedRan = true;")
        fixture.server.route("/style.css", type: "text/css", body: "body { margin: 0 }")
        try await fixture.open("""
        <!doctype html><html><head>
        <link rel="stylesheet" href="http://127.0.0.1:\(fixture.port)/style.css">
        <script src="http://127.0.0.1:\(fixture.port)/ads/blocked.js"></script>
        </head><body><div class="generic-ad" id="generic">ad</div></body></html>
        """)
        #expect(
            try await fixture.value("getComputedStyle(document.getElementById('generic')).display") as? String != "none",
            "a third-party subresource load does not bring the generic hides back",
        )
        #expect(!fixture.server.requested.contains("/ads/blocked.js"), "generichide leaves network blocks alone")

        let exempt = try await ShieldsFixture(filters: """
        /ads/blocked.js$script
        @@||localhost^$document
        """)
        defer { exempt.tearDown() }
        exempt.server.route("/ads/blocked.js", type: "text/javascript", body: "window.blockedRan = true;")
        try await exempt.open("""
        <!doctype html><html><head>
        <script src="http://127.0.0.1:\(exempt.port)/ads/blocked.js"></script>
        </head><body></body></html>
        """)
        #expect(exempt.server.requested.contains("/ads/blocked.js"), "the page's own third-party loads are lifted")
        #expect(try await exempt.value("window.blockedRan === true") as? Bool == true)
    }

    @Test
    func `Scriptlets and procedural filters reach about-blank frames: pristine globals and friendly-iframe ads`() async throws {
        let fixture = try await ShieldsFixture(filters: """
        localhost##+js(no-setTimeout-if, adblockProbe)
        localhost##.promo:has-text(Sponsored)
        ##.generic-ad
        """)
        defer { fixture.tearDown() }
        try await fixture.open("""
        <!doctype html><html><head></head><body>
        <script>
        setTimeout(function adblockProbe() { window.mainProbeRan = true; }, 0);
        
        // A fresh frame's pristine setTimeout, taken the moment the frame exists.
        const probe = document.createElement('iframe');
        document.body.appendChild(probe);
        probe.contentWindow.setTimeout(function adblockProbe() { window.frameProbeRan = true; }, 0);
        setTimeout(function control() { window.controlRan = true; }, 0);
        
        // An ad written into a hostless frame.
        const ad = document.createElement('iframe');
        ad.id = 'ad';
        document.body.appendChild(ad);
        ad.contentDocument.body.innerHTML =
            '<div class="generic-ad" id="generic">ad</div>' +
            '<div class="promo" id="sponsored">Sponsored</div>' +
            '<div class="promo" id="news">News</div>';
        </script>
        </body></html>
        """)
        #expect(try await fixture.eventually("window.controlRan === true"))
        #expect(try await fixture.value("window.mainProbeRan === true") as? Bool == false)
        #expect(
            try await fixture.value("window.frameProbeRan === true") as? Bool == false,
            "the frame's setTimeout carries the page's scriptlet",
        )

        let style = "(id) => getComputedStyle(document.getElementById('ad').contentDocument.getElementById(id)).display"
        #expect(try await fixture.eventually("(\(style))('sponsored') === 'none'"), "the procedural filter runs in the frame")
        #expect(try await fixture.value("(\(style))('news')") as? String != "none")
        #expect(try await fixture.value("(\(style))('generic')") as? String == "none", "the generic hide sheet reaches the frame")
    }

    @Test
    func `Of two installs the newer wins whichever finishes first; an uninstall or refusal attaches nothing`() async throws {
        let fixture = try await ShieldsFixture(filters: "/ads/first.js$script\n")
        defer { fixture.tearDown() }
        let resources = Data("[]".utf8)
        let compiler = ShieldsCompiler()
        let second = try await compiler.build(
            lists: [ShieldsList(id: "easylist", text: Data("/ads/second.js$script\n".utf8))], resources: resources, into: fixture.root,
        ).artifacts
        let third = try await compiler.build(
            lists: [ShieldsList(id: "easylist", text: Data("/ads/third.js$script\n".utf8))], resources: resources, into: fixture.root,
        ).artifacts
        let webKit = fixture.webKit

        // The task starts once the install below suspends, so it is the newer install, and
        // the older one is still compiling when it starts.
        let newer = Task { try await webKit.install(second) }
        let olderResult = try await webKit.install(third)
        let newerResult = try await newer.value
        #expect(newerResult)
        #expect(!olderResult, "the superseded install stops")
        #expect(webKit.artifacts?.key == second.key)
        #expect(webKit.ruleListIdentifiers == Set([second.ruleListIdentifier(forPath: ShieldsArtifacts.networkRulesPath(0))].compactMap(\.self)))

        // Its lists already compiled, the older build attached afterwards replaces the newer.
        #expect(try await webKit.install(third))
        #expect(webKit.artifacts?.key == third.key)

        // An uninstall while an install is in flight leaves nothing attached.
        let pending = Task { try await webKit.install(second) }
        await Task.yield()
        webKit.uninstall()
        let pendingResult = try await pending.value
        #expect(!pendingResult)
        #expect(webKit.artifacts == nil)
        #expect(webKit.ruleListIdentifiers.isEmpty)

        // Shields turned off before the attach: refused at the last moment.
        let refused = try await webKit.install(second) { false }
        #expect(!refused)
        #expect(webKit.artifacts == nil)
    }

    @Test
    func `A rules file that no longer matches its manifest is refused, and a cached build with a short file is rebuilt`() async throws {
        let fixture = try await ShieldsFixture(filters: "/ads/first.js$script\n")
        defer { fixture.tearDown() }
        let lists = [ShieldsList(id: "easylist", text: Data("/ads/tampered.js$script\n".utf8))]
        let compiler = ShieldsCompiler()
        let built = try await compiler.build(lists: lists, resources: Data("[]".utf8), into: fixture.root).artifacts

        // Same size, other bytes: found by hash when read.
        let rules = built.networkRulesURL(0)
        var bytes = try Data(contentsOf: rules)
        let index = try #require(bytes.firstIndex(of: UInt8(ascii: "t")))
        bytes[index] = UInt8(ascii: "T")
        try bytes.write(to: rules)
        await #expect(throws: ShieldsError.self) { try await fixture.webKit.install(built) }
        #expect(fixture.webKit.artifacts?.key == fixture.artifacts.key, "the previous build stays attached")

        // A short file: the cache entry is not whole, so the build runs again.
        try bytes.prefix(bytes.count / 2).write(to: rules)
        #expect(ShieldsArtifacts(key: built.key, directory: built.directory) == nil)
        let (rebuilt, engine) = try await compiler.build(lists: lists, resources: Data("[]".utf8), into: fixture.root)
        #expect(engine != nil)
        #expect(rebuilt.key == built.key)
        try #expect(rebuilt.verifiedContents(ofPath: ShieldsArtifacts.networkRulesPath(0)).count > bytes.count / 2)
    }
}
