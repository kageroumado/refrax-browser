// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import Foundation

/// What a `contentBlocking` engine does in pages (CONTRACT.md §4.5, §4.7): every kind of network
/// decision, standard and aggressive mode, $document and $csp, cosmetic filtering in the main
/// frame and in a cross-site frame, the request log, and agreement with adblock-rust's own
/// decisions for the same requests (shields-architecture §9, the Chromium leg).
enum ShieldsTests {
    @MainActor
    static func network(_ context: Context, mode: String = "aggressive") async throws -> (page: TestPage, results: [String: String]) {
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

        ConformanceTest(name: "shields.standard-mode-spares-first-party", timeout: 90) { context in
            let (page, results) = try await network(context, mode: "standard")
            defer { page.close() }
            try expectEqual(results["firstParty"], "loaded", "a site's own listed image in standard mode")
            try expectEqual(results["thirdParty"], "blocked", "another site's listed image in standard mode")
            let log = try await page.requestLog()
            let spared = log.entries.first { ($0["url"] as? String)?.hasSuffix("127.0.0.1:\(context.server.port)/asset/blocked.png") == true }
            try expectEqual(spared?["sparedFirstParty"] as? Bool, true, "the log marks the spared request")
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
            // Sequence numbers: everything after the last entry is nothing.
            let later = try await page.requestLog(since: Int64(log.nextSequence - 1))
            try expect(later.entries.isEmpty, "entries after nextSequence - 1: \(later.entries.count)")
            let seqs = log.entries.compactMap { $0["seq"] as? Int }
            try expectEqual(seqs, seqs.sorted(), "entries oldest first")
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
