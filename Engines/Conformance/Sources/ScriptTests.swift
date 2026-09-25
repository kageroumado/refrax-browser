// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import Foundation

/// The `scripts` policy (CONTRACT.md §4.4, §4.5): injection time, frames, match patterns, and
/// the message channels that are the only bridge from page content to Refrax.
enum ScriptTests {
    static func script(
        _ source: String,
        at time: String = "documentStart",
        world: String? = nil,
        mainFrameOnly: Bool = false,
        matches: [String] = [],
        excludes: [String] = [],
        channels: [String] = [],
    ) -> [String: Any] {
        [
            "id": "conformance.\(UUID().uuidString)",
            "source": source,
            "injectionTime": time,
            "world": world.map { ["isolated": ["name": $0]] } ?? ["page": [:]],
            "mainFrameOnly": mainFrameOnly,
            "matches": matches,
            "excludes": excludes,
            "channels": channels,
        ]
    }

    static let all: [ConformanceTest] = [
        ConformanceTest(name: "scripts.document-start-runs-before-the-page") { context in
            context.scripts([script("window.__early = document.readyState;")])
            let page = try await context.page("/html/early")
            let seen = try await page.evaluate("window.__seenEarly") as? String
            try expectEqual(seen, "string", "the page's first script saw the injected global")
            let state = try await page.evaluate("window.__early") as? String
            try expectEqual(state, "loading", "readyState at document start")
        },

        ConformanceTest(name: "scripts.document-end-sees-the-whole-document") { context in
            context.scripts([script("window.__endSawLate = !!document.getElementById('late');", at: "documentEnd")])
            let page = try await context.page("/html/early")
            let saw = try await page.evaluate("window.__endSawLate") as? Bool
            try expectEqual(saw, true, "document-end script found the last element")
        },

        ConformanceTest(name: "scripts.main-frame-only") { context in
            context.scripts([script("window.__ran = true;", mainFrameOnly: true)])
            let page = try await context.page("/html/frames")
            let childRan = try await childFrameResult(page)
            try expectEqual(childRan, false, "script ran in the child frame")
            let mainRan = try await page.evaluate("window.__ran === true") as? Bool
            try expectEqual(mainRan, true, "script ran in the main frame")
        },

        ConformanceTest(name: "scripts.every-frame-by-default") { context in
            context.scripts([script("window.__ran = true;")])
            let page = try await context.page("/html/frames")
            let childRan = try await childFrameResult(page)
            try expectEqual(childRan, true, "script ran in the child frame")
        },

        ConformanceTest(name: "scripts.matches-and-excludes") { context in
            context.scripts([script(
                "window.__matched = true;",
                matches: ["*://127.0.0.1/html/*"],
                excludes: ["*://*/html/excluded*"],
            )])
            let matched = try await context.page("/html/basic")
            let ran = try await matched.evaluate("window.__matched === true") as? Bool
            try expectEqual(ran, true, "ran on a matching URL")
            let otherHost = try await context.page("/html/basic", host: "localhost")
            let ranOnOther = try await otherHost.evaluate("window.__matched === true") as? Bool
            try expectEqual(ranOnOther, false, "ran on a host outside matches")
            let excluded = try await context.page("/html/excluded")
            let ranExcluded = try await excluded.evaluate("window.__matched === true") as? Bool
            try expectEqual(ranExcluded, false, "ran on an excluded URL")
        },

        ConformanceTest(name: "scripts.replacing-the-policy-removes-scripts") { context in
            context.scripts([script("window.__old = true;")])
            let before = try await context.page("/html/basic")
            try expectEqual(try await before.evaluate("window.__old === true") as? Bool, true, "installed script")
            context.scripts([])
            let after = try await context.page("/html/basic")
            try expectEqual(try await after.evaluate("window.__old === true") as? Bool, false, "script after an empty policy")
        },

        ConformanceTest(name: "scripts.channel-round-trip") { context in
            context.scripts([script(
                "window.__reply = window.webkit.messageHandlers.echo.postMessage({n: 1, s: 'x'});",
                world: "conformance",
                channels: ["echo"],
            )])
            let page = try await context.page("/html/basic")
            let reply = try await page.evaluate("window.__reply", world: "conformance")
            try expectEqual(JSON.canonical(reply), #"{"n":1,"s":"x"}"#, "promise resolved with Refrax's reply")
            let message = try await eventually("the script message") { page.scriptMessages.first }
            try expectEqual(message["channel"] as? String, "echo", "channel")
            try expectEqual(JSON.canonical(message["world"]), #"{"isolated":{"name":"conformance"}}"#, "world")
            try expectEqual(message["isMainFrame"] as? Bool, true, "isMainFrame")
            try expect((message["frameURL"] as? String)?.hasPrefix(context.url("/")) == true, "frameURL \(message["frameURL"] ?? "nil") is the frame's origin")
        },

        ConformanceTest(name: "scripts.channel-error-rejects") { context in
            context.scripts([script(
                "window.__result = window.webkit.messageHandlers.echo.postMessage(1).then(() => 'resolved', e => 'rejected: ' + e.message);",
                world: "conformance",
                channels: ["echo"],
            )])
            let page = try context.engine.makePage(context.url("/html/basic"))
            page.reply = { _ in ["error": ["message": "denied-9"]] }
            try await page.waitForFinish()
            let result = try await page.evaluate("window.__result", world: "conformance") as? String
            try expectEqual(result, "rejected: denied-9", "postMessage after an error reply")
        },

        ConformanceTest(name: "scripts.channels-stay-in-their-world") { context in
            // Isolated-world channels are the bridge to Refrax; page content must never reach them.
            context.scripts([
                script("window.__granted = typeof window.webkit.messageHandlers.secret;", world: "conformance", channels: ["secret"]),
            ])
            let page = try await context.page("/html/basic")
            let inWorld = try await page.evaluate("window.__granted", world: "conformance") as? String
            try expectEqual(inWorld, "object", "the channel in its own world")
            let fromPage = try await page.evaluate("typeof (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.secret)") as? String
            try expectEqual(fromPage, "undefined", "the channel from the page world")
            let fromOther = try await page.evaluate("typeof (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.secret)", world: "conformance-other") as? String
            try expectEqual(fromOther, "undefined", "the channel from another isolated world")
            let forged = try await page.evaluate("""
            (() => { try { window.webkit.messageHandlers.secret.postMessage('forged'); return 'posted'; } catch (e) { return 'unreachable'; } })()
            """) as? String
            try expectEqual(forged, "unreachable", "posting from the page world")
            try await pause(0.3)
            try expect(page.scriptMessages.isEmpty, "a message reached Refrax: \(page.scriptMessages)")
        },
    ]

    /// Whether the injected script ran in `page`'s child frame, as the child reports it.
    @MainActor
    static func childFrameResult(_ page: TestPage) async throws -> Bool {
        try await eventuallyAsync("the child frame reported") {
            guard try await page.evaluate("window.__childLoaded === true") as? Bool == true else { return nil }
            return try await page.evaluate("window.__childRan === true") as? Bool
        }
    }
}
