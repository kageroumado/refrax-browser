// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import Foundation

/// The `siteSettings` policy (CONTRACT.md §4.5): per-site JavaScript, content blocking and
/// autoplay take effect on the next load, a rule covers its host's subdomains, and popups reach
/// Refrax whatever the engine would have blocked.
enum SiteSettingsTests {
    /// Whether the scripted fixture's own script ran when loaded from `host`.
    @MainActor
    static func scriptRan(_ context: Context, host: String) async throws -> Bool {
        let path = "/asset/js-ran-\(host)"
        let before = context.server.hits(path)
        let page = try await context.page("/html/scripted", host: host)
        defer { page.close() }
        try await pause(0.5)
        return context.server.hits(path) > before
    }

    /// The state of an AudioContext the page makes without a gesture: `running` where
    /// media may autoplay with sound, `suspended` where it waits for the user.
    @MainActor
    static func audioState(_ context: Context, host: String) async throws -> String? {
        let page = try await context.page("/html/basic", host: host)
        defer { page.close() }
        let state = try await page.evaluate("""
        (async () => {
          const audio = new AudioContext();
          await new Promise(done => setTimeout(done, 300));
          return audio.state;
        })()
        """)
        return state as? String
    }

    static let all: [ConformanceTest] = [
        ConformanceTest(name: "site-settings.javascript-off-for-a-site") { context in
            context.siteSettings(rules: [["host": "localhost", "javaScriptEnabled": false]])
            try expect(!(try await scriptRan(context, host: "sub.localhost")), "script ran on sub.localhost with JavaScript off for localhost")
            try expect(try await scriptRan(context, host: "127.0.0.1"), "script did not run on 127.0.0.1")
        },

        ConformanceTest(name: "site-settings.javascript-off-by-default-with-an-exception") { context in
            context.siteSettings(javaScriptEnabled: false, rules: [["host": "localhost", "javaScriptEnabled": true]])
            try expect(!(try await scriptRan(context, host: "127.0.0.1")), "script ran with JavaScript off by default")
            try expect(try await scriptRan(context, host: "localhost"), "script did not run on the excepted localhost")
            context.siteSettings()
            try expect(try await scriptRan(context, host: "127.0.0.1"), "script did not run once the policy was cleared")
        },

        ConformanceTest(name: "site-settings.content-blocking-off-for-a-site", timeout: 300) { context in
            try context.engine.require("contentBlocking")
            context.contentBlocking(lists: [Fixtures.blockingList])
            try await eventuallyAsync("blocking on 127.0.0.1", timeout: 240, interval: .milliseconds(500)) {
                try await BlockingTests.results(context)["image"] == "blocked" ? true : nil
            }
            context.siteSettings(rules: [["host": "localhost", "contentBlockingEnabled": false]])
            let spared = try await BlockingTests.results(context, host: "sub.localhost")
            try expectEqual(spared["image"], "loaded", "sub.localhost with blocking off for localhost")
            try expectEqual(try await BlockingTests.results(context)["image"], "blocked", "127.0.0.1 without a rule")
        },

        ConformanceTest(name: "site-settings.autoplay-with-sound") { context in
            context.siteSettings(rules: [["host": "localhost", "autoplayWithSound": true]])
            try expectEqual(try await audioState(context, host: "localhost"), "running", "audio on localhost, allowed to autoplay")
            try expectEqual(try await audioState(context, host: "127.0.0.1"), "suspended", "audio on 127.0.0.1 before a gesture")
        },

        ConformanceTest(name: "site-settings.popups-without-a-gesture-reach-refrax") { context in
            let page = try await context.page("/html/basic")
            let mark = page.requests.count
            _ = try await page.evaluate("void window.open('/html/other')")
            let request = try await page.waitForRequest("openURL", after: mark)
            try expectEqual(request["userGesture"] as? Bool, false, "userGesture")
            try expectEqual(request["isNewWindowRequest"] as? Bool, true, "isNewWindowRequest")
        },
    ]
}
