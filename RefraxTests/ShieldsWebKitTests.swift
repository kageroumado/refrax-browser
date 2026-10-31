import Foundation
import Network
import os
import Testing
import WebKit
@testable import Refrax

/// A loopback HTTP/1.1 server that serves fixed bodies and records every path requested, the
/// ground truth of what a page loaded.
private final class LoopbackServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "shields.loopback")
    private let lock = NSLock()
    private var routes: [String: (type: String, body: String)] = [:]
    private var requestedPaths: [String] = []

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        self.listener = try NWListener(using: parameters)
    }

    var requested: [String] {
        lock.withLock { requestedPaths }
    }

    func route(_ path: String, type: String = "text/html", body: String) {
        lock.withLock { routes[path] = (type, body) }
    }

    /// Starts listening and returns the port.
    func start() async throws -> UInt16 {
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        return try await withCheckedThrowingContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            listener.stateUpdateHandler = { [listener] state in
                let shouldResume = resumed.withLock { done in
                    defer { done = true }
                    return !done
                }
                switch state {
                case .ready where shouldResume:
                    continuation.resume(returning: listener.port?.rawValue ?? 0)
                case let .failed(error) where shouldResume:
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
    }

    private func serve(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1_024) { [weak self] data, _, _, _ in
            guard let self, let data, let request = String(data: data, encoding: .utf8) else {
                connection.cancel()
                return
            }
            let path = request.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
            let route = lock.withLock {
                self.requestedPaths.append(path)
                return self.routes[path]
            }
            let status = route == nil ? "404 Not Found" : "200 OK"
            let body = Data((route?.body ?? "").utf8)
            let head = "HTTP/1.1 \(status)\r\nContent-Type: \(route?.type ?? "text/plain"); charset=utf-8\r\n"
                + "Content-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n"
            connection.send(content: Data(head.utf8) + body, completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}

/// Finishes a navigation and lets Shields' network lists take their redirect actions, as
/// `WKNavigationDelegateAdapter` does in the browser.
@MainActor
private final class FixtureNavigationDelegate: NSObject, WKNavigationDelegate {
    var actionPatterns: [String: Set<String>] = [:]
    private var finished: CheckedContinuation<Void, any Error>?

    func waitForLoad() async throws {
        try await withCheckedThrowingContinuation { finished = $0 }
    }

    func webView(
        _: WKWebView,
        decidePolicyFor _: WKNavigationAction,
        preferences: WKWebpagePreferences,
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        preferences._activeContentRuleListActionPatterns = actionPatterns
        return (.allow, preferences)
    }

    /// What the rule lists did, as "<path> blocked|redirected".
    private(set) var performedActions: [String] = []

    @objc(_webView:contentRuleListWithIdentifier:performedAction:forURL:)
    func _webView(
        _: WKWebView,
        contentRuleListWithIdentifier _: String,
        performedAction action: _WKContentRuleListAction,
        for url: URL,
    ) {
        performedActions.append("\(url.path()) \(action.blockedLoad ? "blocked" : action.redirected ? "redirected" : "other")")
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        finished?.resume()
        finished = nil
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: any Error) {
        finished?.resume(throwing: error)
        finished = nil
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: any Error) {
        finished?.resume(throwing: error)
        finished = nil
    }
}

/// Shields end to end in a real `WKWebView`: a build from Rust, its rule lists and user scripts
/// installed through ``ShieldsWebKit``, and a fixture page on a loopback server with a
/// cross-origin iframe.
@Suite("Shields in WebKit", .tags(.shields), .serialized)
@MainActor
struct ShieldsWebKitTests {
    private static let filters = """
    /ads/blocked.js$script,domain=localhost
    /ads/allowed.js$script,domain=localhost
    /ads/redirect.js$script,redirect=noop.js,domain=localhost
    ##.generic-ad
    localhost##.ad-banner
    localhost##.promo:has-text(Sponsored)
    localhost##+js(set-constant, shieldsMarker, true)
    127.0.0.1##+js(set-constant, shieldsFrameMarker, true)
    """

    /// In a second list: the union build lets it lift the first list's block.
    private static let unbreak = "@@/ads/allowed.js$script\n"

    private static func page(port: UInt16) -> String {
        """
        <!doctype html><html><head>
        <script>window.addEventListener('message', (event) => { window.frameReport = event.data; });</script>
        <script src="http://127.0.0.1:\(port)/ads/blocked.js"></script>
        <script src="http://127.0.0.1:\(port)/ads/allowed.js"></script>
        <script src="http://127.0.0.1:\(port)/ads/redirect.js"
                onload="window.redirectLoaded = true" onerror="window.redirectFailed = true"></script>
        </head><body>
        <div class="generic-ad" id="generic">ad</div>
        <div class="ad-banner" id="specific">ad</div>
        <div class="promo" id="sponsored">Sponsored</div>
        <div class="promo" id="news">News</div>
        <iframe src="http://127.0.0.1:\(port)/frame.html"></iframe>
        </body></html>
        """
    }

    private static let frame = """
    <!doctype html><html><body>
    <div class="generic-ad" id="generic">ad</div>
    <script>
    parent.postMessage({
        marker: window.shieldsFrameMarker === true,
        genericHidden: getComputedStyle(document.getElementById('generic')).display === 'none',
    }, '*');
    </script>
    </body></html>
    """

    @Test
    func `Blocks, lifts across lists, redirects, hides and runs scriptlets in the page and its iframe`() async throws {
        let root = try shieldsScratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let server = try LoopbackServer()
        defer { server.stop() }
        let port = try await server.start()
        server.route("/page.html", body: Self.page(port: port))
        server.route("/frame.html", body: Self.frame)
        for script in ["blocked", "allowed", "redirect"] {
            server.route("/ads/\(script).js", type: "text/javascript", body: "window.\(script)Ran = true;")
        }

        let resources = try #require(ShieldsResources.bundled())
        let lists = [
            ShieldsList(id: "easylist", text: Data(Self.filters.utf8)),
            ShieldsList(id: "ublock-unbreak", text: Data(Self.unbreak.utf8), isTrusted: true),
        ]
        let (artifacts, _) = try await ShieldsCompiler().build(lists: lists, resources: resources, into: root)

        let configuration = WKWebViewConfiguration()
        let store = try #require(WKContentRuleListStore(url: root.appending(path: "store", directoryHint: .isDirectory)))
        let webKit = ShieldsWebKit(
            userContentController: configuration.userContentController,
            scriptRegistry: ScriptRegistry(),
            store: store,
        )
        try await webKit.install(artifacts)
        #expect(!webKit.actionPatterns.isEmpty)

        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 800, height: 600), configuration: configuration)
        let delegate = FixtureNavigationDelegate()
        delegate.actionPatterns = webKit.actionPatterns
        webView.navigationDelegate = delegate
        try webView.load(URLRequest(url: #require(URL(string: "http://localhost:\(port)/page.html"))))
        try await delegate.waitForLoad()

        func value(_ expression: String) async throws -> Any? {
            try await webView.evaluateJavaScript(expression)
        }
        func isHidden(_ id: String) async throws -> Bool {
            try await value("getComputedStyle(document.getElementById('\(id)')).display === 'none'") as? Bool ?? false
        }

        // Network: the blocked script never reached the server; the excepted one did.
        #expect(!server.requested.contains("/ads/blocked.js"))
        #expect(try await value("window.blockedRan === true") as? Bool == false)
        #expect(server.requested.contains("/ads/allowed.js"), "an exception in another list lifts the block")
        #expect(try await value("window.allowedRan === true") as? Bool == true)

        // $redirect: WebKit serves the data: URL resource in place of the load.
        let redirectRules = try String(contentsOf: artifacts.networkRulesURL(0), encoding: .utf8)
            .components(separatedBy: "},{").filter { $0.contains("redirect") }.map { String($0.prefix(300)) }
        #expect(!server.requested.contains("/ads/redirect.js"), "actions: \(delegate.performedActions) rules: \(redirectRules)")
        #expect(try await value("window.redirectLoaded === true") as? Bool == true, "the redirect resource loads (R11)")
        #expect(try await value("window.redirectRan === true") as? Bool == false)

        // Cosmetics in the main frame: generic and host rule lists, the procedural runner.
        #expect(try await isHidden("generic"))
        #expect(try await isHidden("specific"))
        #expect(try await isHidden("sponsored"))
        #expect(try await !isHidden("news"))

        // The scriptlet ran in the page's main world at document start.
        #expect(try await value("window.shieldsMarker === true") as? Bool == true)

        // The cross-origin iframe: generic hiding and its host's scriptlet.
        var report: [String: Any]?
        for _ in 0 ..< 50 where report == nil {
            report = try await value("window.frameReport") as? [String: Any]
            if report == nil {
                try await Task.sleep(for: .milliseconds(100))
            }
        }
        let frame = try #require(report, "the iframe reported")
        #expect(frame["genericHidden"] as? Bool == true)
        #expect(frame["marker"] as? Bool == true, "the iframe's host gets its own scriptlet")
    }
}
