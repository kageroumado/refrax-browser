// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import Foundation

/// The `contentBlocking` policy (CONTRACT.md §4.5): lists block, allowlisted hosts and their
/// subdomains are spared, and turning blocking off and on takes effect on the next load.
enum BlockingTests {
    /// What the blocking fixture could load: `image`, `allowed`, `script`, `fetch` →
    /// `loaded` | `blocked`.
    @MainActor
    static func results(_ context: Context, host: String = "127.0.0.1") async throws -> [String: String] {
        let page = try await context.page("/html/blocking", host: host)
        defer { page.close() }
        let value = try await page.evaluate("window.done")
        guard let results = value as? [String: String] else {
            throw Failure("blocking page returned \(JSON.canonical(value))")
        }
        return results
    }

    static let all: [ConformanceTest] = [
        ConformanceTest(name: "blocking.lists-block", timeout: 300) { context in
            try context.engine.require("contentBlocking")
            let applied = Date()
            context.contentBlocking(lists: [Fixtures.blockingList])
            // Compiling and indexing a new list takes a moment; pages loaded before it's ready
            // aren't filtered. Measure how long.
            let results = try await eventuallyAsync("the image to be blocked", timeout: 240, interval: .milliseconds(500)) {
                let results = try await Self.results(context)
                return results["image"] == "blocked" ? results : nil
            }
            context.note(String(format: "ruleset effective %.1f s after the policy", -applied.timeIntervalSinceNow))
            try expectEqual(results["allowed"], "loaded", "unlisted image")
            try expectEqual(results["script"], "blocked", "first-party script ($script,1p)")
            try expectEqual(results["fetch"], "blocked", "fetch() ($xhr)")
        },

        ConformanceTest(name: "blocking.allowlisted-hosts-and-subdomains", timeout: 300) { context in
            try context.engine.require("contentBlocking")
            context.contentBlocking(lists: [Fixtures.blockingList], allowlistedHosts: ["localhost", "0.1"])
            try await eventuallyAsync("blocking on 127.0.0.1", timeout: 240, interval: .milliseconds(500)) {
                try await Self.results(context)["image"] == "blocked" ? true : nil
            }
            let subdomain = try await Self.results(context, host: "sub.localhost")
            try expectEqual(subdomain, ["image": "loaded", "allowed": "loaded", "script": "loaded", "fetch": "loaded"], "sub.localhost under an allowlisted localhost")
            // "0.1" is no parent of 127.0.0.1.
            let address = try await Self.results(context)
            try expectEqual(address["image"], "blocked", "127.0.0.1 with 0.1 allowlisted")
        },

        ConformanceTest(name: "blocking.off-and-on-again", timeout: 300) { context in
            try context.engine.require("contentBlocking")
            context.contentBlocking(lists: [Fixtures.blockingList])
            try await eventuallyAsync("blocking", timeout: 240, interval: .milliseconds(500)) {
                try await Self.results(context)["image"] == "blocked" ? true : nil
            }
            context.contentBlocking(enabled: false, lists: [Fixtures.blockingList])
            let off = try await eventuallyAsync("unblocked after turning off", timeout: 10) {
                let results = try await Self.results(context)
                return results["image"] == "loaded" ? results : nil
            }
            try expectEqual(off["script"], "loaded", "script with blocking off")
            let reenabled = Date()
            context.contentBlocking(lists: [Fixtures.blockingList])
            try await eventuallyAsync("blocked after turning on", timeout: 10) {
                try await Self.results(context)["image"] == "blocked" ? true : nil
            }
            context.note(String(format: "re-enabled in %.1f s (same lists: nothing to re-index)", -reenabled.timeIntervalSinceNow))
        },
    ]
}
