// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import Foundation

/// What a `contentBlocking` engine does in pages (CONTRACT.md §4.5, §4.7): every kind of network
/// decision, $document and $csp, cosmetic filtering in the main
/// frame and in a cross-site frame, the request log, and agreement with adblock-rust's own
/// decisions for the same requests (shields-architecture §9, the Chromium leg).
enum ShieldsTests {
    @MainActor
    static func network(_ context: Context, mode: String = "standard") async throws -> (page: TestPage, results: [String: String]) {
        try await context.contentBlockingApplied(mode: mode)
        let page = try await context.page("/html/shields-net")
        let value = try await page.evaluate("window.done", timeout: 30)
        guard let results = value as? [String: String] else {
            throw Failure("shields-net returned \(JSON.canonical(value))")
        }
        return (page, results)
    }

    static let all: [ConformanceTest] = [
        ConformanceTest(name: "shields.network-decisions", timeout: 90) { context in
            let blockedBefore = context.server.hits("/asset/blocked.png")
            let (page, results) = try await network(context)
            defer { page.close() }
            try expectEqual(results["firstParty"], "blocked", "listed image")
            try expectEqual(results["thirdParty"], "blocked", "listed image on another site")
            try expectEqual(results["allowed"], "loaded", "unlisted image")
            try expectEqual(results["excepted"], "loaded", "image an exception rule lifts")
            try expectEqual(results["secondList"], "blocked", "image the second list names")
            try expectEqual(results["script"], "blocked", "listed script")
            try expectEqual(results["redirected"], "loaded", "$redirect script")
            try expectEqual(results["redirectedTo"], "stub", "$redirect served the resource")
            try expectEqual(results["fetch"], "blocked", "fetch() ($xhr)")
            let echo = results["echo"] ?? ""
            try expect(echo.contains("keep=2") && !echo.contains("tracking"), "$removeparam: the server saw \(echo.prefix(200))")
            try expect(!context.server.requests.contains { $0.contains("tracking=1") }, "the parameter never reached the server")
            try expect(context.server.hits("/asset/socket-allowed") > 0, "an allowed WebSocket reaches the server")
            try expectEqual(context.server.hits("/asset/socket-blocked"), 0, "requests for a blocked WebSocket")
            try expectEqual(context.server.hits("/asset/blocked.png") - blockedBefore, 0, "requests for blocked images")
        },

        ConformanceTest(name: "shields.standard-mode-blocks-first-party", timeout: 90) { context in
            let (page, results) = try await network(context, mode: "standard")
            defer { page.close() }
            try expectEqual(results["firstParty"], "blocked", "a site's own listed image in standard mode")
            try expectEqual(results["thirdParty"], "blocked", "another site's listed image in standard mode")
            try expectEqual(results["script"], "blocked", "a site's own listed script in standard mode")
            try expectEqual(results["fetch"], "blocked", "a site's own listed fetch() in standard mode")
            try expectEqual(results["redirectedTo"], "stub", "a site's own $redirect script in standard mode")
            let echo = results["echo"] ?? ""
            try expect(echo.contains("keep=2") && !echo.contains("tracking"), "$removeparam on the site's own request in standard mode")
        },

        ConformanceTest(name: "shields.document-blocked", timeout: 60) { context in
            try await context.contentBlockingApplied()
            let page = try context.engine.makePage(context.url("/html/basic", host: "blocked-page.localhost"))
            defer { page.close() }
            let failure = try await page.waitForEvent("navigationFailed", timeout: 20)
            let kind = (failure["failure"] as? [String: Any])?["kind"] as? String
            try expectEqual(kind, "blockedByPolicy", "a $document rule's page")
            let log = try await page.requestLog()
            let recorded = log.entries.contains { $0["type"] as? String == "main_frame" && $0["decision"] as? String == "blocked" }
            try expect(recorded, "the log records the blocked page: \(JSON.canonical(log.entries))")
        },

        ConformanceTest(name: "shields.redirects-are-decided", timeout: 60) { context in
            try await context.contentBlockingApplied()
            let page = try await context.page("/html/basic")
            defer { page.close() }
            // A subresource redirected to a listed URL is blocked at the redirect.
            let image = try await page.evaluate("""
            new Promise(done => {
              const img = new Image();
              img.onload = () => done('loaded');
              img.onerror = () => done('blocked');
              img.src = '/redirect?to=/asset/blocked.png';
            })
            """) as? String
            try expectEqual(image, "blocked", "an image redirected to a listed URL")
            // A page redirected to a $document site gets Shields' page, not a network error.
            let target = context.url("/html/basic", host: "blocked-page.localhost")
            let redirected = try context.engine.makePage(context.url("/redirect?to=\(target)"))
            defer { redirected.close() }
            let failure = try await redirected.waitForEvent("navigationFailed", timeout: 20)
            try expectEqual((failure["failure"] as? [String: Any])?["kind"] as? String, "blockedByPolicy", "a page redirected to a $document site")
            let log = try await redirected.requestLog()
            let blocked = log.entries.first { $0["type"] as? String == "main_frame" && $0["decision"] as? String == "blocked" }
            try expect((blocked?["url"] as? String)?.contains("blocked-page.localhost") == true, "the log names the redirect's target: \(JSON.canonical(log.entries))")
        },

        ConformanceTest(name: "shields.first-engine-is-waited-for", timeout: 60) { context in
            try context.engine.require("contentBlocking")
            // Off clears the engine; on again loads it afresh, and a page loaded right away
            // waits for it.
            try context.contentBlocking(enabled: false)
            try await pause(0.3)
            try context.contentBlocking()
            let results = try await BlockingTests.results(context)
            try expectEqual(results["image"], "blocked", "a listed image on a page loaded as the engine loads")
        },

        ConformanceTest(name: "shields.failed-update-keeps-the-engine", timeout: 60) { context in
            try await context.contentBlockingApplied()
            guard let shields = context.shields else { throw Skip("no Shields engine files") }
            var policy = shields.policy(enabled: true, mode: "standard", allowlistedHosts: [], format: nil)
            policy["engine"] = ["path": shields.engine.absoluteString, "sha256": String(repeating: "0", count: 64), "format": ShieldsFixture.format]
            let mark = context.engine.events.count
            context.apply("contentBlocking", ["policy": policy])
            let status = try await context.engine.waitForEvent("contentBlockingStatus", after: mark, timeout: 30)
            try expectEqual(status["status"] as? String, "applied", "status after a file that fails its hash")
            try expectEqual(status["sha256"] as? String, shields.engineSHA256, "the engine still in use")
            try expect(status["reason"] is String, "the status says the update failed")
            try expectEqual(try await BlockingTests.results(context)["image"], "blocked", "blocking after the failed update")
        },

        ConformanceTest(name: "shields.csp-header", timeout: 60) { context in
            try await context.contentBlockingApplied()
            let page = try await context.page("/html/csp-page")
            defer { page.close() }
            try expectEqual(try await page.evaluate("typeof window.__inline") as? String, "undefined", "inline script under the $csp policy")
            let control = try await context.page("/html/scripted")
            defer { control.close() }
            try expect(context.server.hits("/asset/js-ran-127.0.0.1") > 0, "inline scripts run on a page no $csp rule names")
            let log = try await page.requestLog()
            try expect(log.entries.contains { $0["decision"] as? String == "csp" }, "the log records the added policy")
        },

        ConformanceTest(name: "shields.cosmetics-main-frame-and-iframe", timeout: 60) { context in
            try await context.contentBlockingApplied()
            let page = try await context.page("/html/shields-cosmetic")
            defer { page.close() }
            var last: Any = NSNull()
            let state = try await eventuallyAsync("the cosmetic filters to settle (last: \(JSON.canonical(last)))", timeout: 10) { () -> [String: Any]? in
                let value = try await page.evaluate("""
                ({hidden: getComputedStyle(document.getElementById('hidden')).display,
                  procedural: !!document.getElementById('procedural'),
                  kept: !!document.getElementById('kept'),
                  styled: getComputedStyle(document.getElementById('styled')).color,
                  generic: getComputedStyle(document.getElementById('generic')).display,
                  visible: getComputedStyle(document.getElementById('visible')).display,
                  marker: window.__seenAtStart,
                  frame: window.frameReport || null})
                """) as? [String: Any]
                last = value ?? NSNull()
                guard let value, value["frame"] is [String: Any], value["procedural"] as? Bool == false,
                      value["generic"] as? String == "none" else { return nil }
                return value
            }
            try expectEqual(state["hidden"] as? String, "none", "## hide in the main frame")
            try expectEqual(state["visible"] as? String, "block", "an element no rule names")
            try expectEqual(state["kept"] as? Bool, true, "a procedural filter's non-match")
            try expectEqual(state["styled"] as? String, "rgb(255, 0, 0)", ":style()")
            try expectEqual(JSON.canonical(state["marker"]), JSON.canonical(["main:/html/shields-cosmetic"]), "scriptlet ran before the page's first script")
            let frame = state["frame"] as? [String: Any] ?? [:]
            try expectEqual(frame["display"] as? String, "none", "## hide in a cross-site iframe")
            try expectEqual(JSON.canonical(frame["marker"]), JSON.canonical(["frame:/html/shields-frame"]), "scriptlet in a cross-site iframe")
        },

        ConformanceTest(name: "shields.frames-a-page-makes-inherit-its-rules", timeout: 60) { context in
            try await context.contentBlockingApplied()
            let page = try await context.page("/html/shields-cosmetic")
            defer { page.close() }
            // A fresh iframe's initial empty document: a page reaching for globals no scriptlet
            // touched gets the scriptlet's.
            let blank = try await page.evaluate("""
            (() => {
              const frame = document.createElement('iframe');
              document.body.append(frame);
              return frame.contentWindow.__shieldsMarker || null;
            })()
            """)
            try expectEqual(JSON.canonical(blank), JSON.canonical(["main:blank"]), "scriptlets in a new iframe's initial document")
            // A srcdoc frame gets the page's hiding and scriptlets.
            let srcdoc = try await page.evaluate("""
            new Promise(done => {
              const frame = document.createElement('iframe');
              frame.srcdoc = '<div class=cosmetic-hidden id=hidden>x</div>';
              frame.onload = () => done({
                display: frame.contentWindow.getComputedStyle(frame.contentDocument.getElementById('hidden')).display,
                marker: frame.contentWindow.__shieldsMarker || null,
              });
              document.body.append(frame);
            })
            """) as? [String: Any] ?? [:]
            try expectEqual(srcdoc["display"] as? String, "none", "## hide in a srcdoc frame")
            try expectEqual(JSON.canonical(srcdoc["marker"]), JSON.canonical(["main:srcdoc"]), "scriptlet in a srcdoc frame")
        },

        ConformanceTest(name: "shields.no-cosmetics-when-allowlisted", timeout: 60) { context in
            try await context.contentBlockingApplied(allowlistedHosts: ["127.0.0.1"])
            let page = try await context.page("/html/shields-cosmetic")
            defer { page.close() }
            try await pause(0.5)
            let hidden = try await page.evaluate("getComputedStyle(document.getElementById('hidden')).display") as? String
            try expectEqual(hidden, "block", "## hide on an allowlisted site")
            try expectEqual(try await page.evaluate("window.__seenAtStart.length") as? Int, 0, "scriptlets on an allowlisted site")
        },

        ConformanceTest(name: "shields.request-log", timeout: 90) { context in
            try context.engine.require("requestLog")
            let (page, _) = try await network(context)
            defer { page.close() }
            let log = try await page.requestLog()
            func entry(_ suffix: String) -> [String: Any]? {
                log.entries.first { ($0["url"] as? String)?.hasSuffix(suffix) == true }
            }
            let blocked = try entry("/asset/blocked.js").orFail("blocked.js in the log")
            try expectEqual(blocked["decision"] as? String, "blocked", "blocked.js decision")
            try expectEqual(blocked["list"] as? String, "list0", "blocked.js list")
            try expectEqual(blocked["rule"] as? String, "/asset/blocked.js$script", "blocked.js rule")
            try expectEqual(blocked["type"] as? String, "script", "blocked.js type")
            try expect(blocked["line"] is Int, "blocked.js line")
            try expectEqual(try entry("/asset/second-list.png").orFail("second-list.png")["list"] as? String, "list1", "second list's id")
            try expectEqual(try entry("/asset/redirected.js").orFail("redirected.js")["decision"] as? String, "redirected", "$redirect decision")
            try expectEqual(try entry("/asset/excepted.png").orFail("excepted.png")["decision"] as? String, "excepted", "exception decision")
            try expectEqual(try entry("/asset/allowed.png").orFail("allowed.png")["decision"] as? String, "allowed", "unlisted decision")
            let rewritten = try entry("/echo?tracking=1&keep=2").orFail("the $removeparam request")
            try expectEqual(rewritten["decision"] as? String, "rewritten", "$removeparam decision")
            try expectEqual(try entry("/asset/socket-blocked").orFail("socket-blocked")["type"] as? String, "websocket", "WebSocket type")
            // Sequence numbers: nothing follows the last entry, and nextSequence is its seq.
            let later = try await page.requestLog(since: Int64(log.nextSequence))
            try expect(later.entries.isEmpty, "entries after nextSequence: \(later.entries.count)")
            try expectEqual(log.entries.last?["seq"] as? Int, log.nextSequence, "nextSequence")
            let seqs = log.entries.compactMap { $0["seq"] as? Int }
            try expectEqual(seqs, seqs.sorted(), "entries oldest first")
            // A very long URL is logged cut short, without taking the log with it.
            _ = try await page.evaluate("void (new Image().src = '/asset/allowed.png?' + 'q'.repeat(70000))")
            let long = try await eventuallyAsync("the long URL in the log") { () -> [String: Any]? in
                try await page.requestLog(since: Int64(log.nextSequence)).entries.first { $0["truncated"] as? Bool == true }
            }
            try expect(((long["url"] as? String)?.utf8.count ?? .max) <= 2048, "a logged URL is at most 2 KB")
        },

        ConformanceTest(name: "shields.parity-with-adblock-rust", timeout: 120) { context in
            try context.engine.require("requestLog")
            guard let shields = context.shields else { throw Skip("no Shields engine files") }
            let (page, _) = try await network(context)
            defer { page.close() }
            let log = try await page.requestLog()
            let decided = log.entries.filter { ["blocked", "redirected", "rewritten", "excepted", "allowed"].contains($0["decision"] as? String ?? "") }
            let requests = decided.compactMap { entry -> [String: String]? in
                guard let url = entry["url"] as? String, let type = entry["type"] as? String else { return nil }
                return ["url": url, "type": type, "source": entry["frameURL"] as? String ?? url, "method": entry["method"] as? String ?? "GET"]
            }
            let predicted = try shields.predict(requests)
            var disagreements: [String] = []
            for entry in decided {
                guard let url = entry["url"] as? String, let type = entry["type"] as? String,
                      let decision = entry["decision"] as? String else { continue }
                let expected = predicted["\(type) \(url)"]
                if expected != decision {
                    disagreements.append("\(type) \(url): engine \(decision), adblock-rust \(expected ?? "?")")
                }
            }
            context.note("\(decided.count) decisions compared")
            try expect(decided.count >= 10, "too few decisions logged: \(decided.count)")
            try expect(disagreements.isEmpty, "disagreements: \(disagreements.joined(separator: "; "))")
        },
    ]
}

extension Optional {
    func orFail(_ what: String) throws -> Wrapped {
        guard let self else { throw Failure("missing: \(what)") }
        return self
    }
}
