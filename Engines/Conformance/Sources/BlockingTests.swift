// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import Foundation

/// The `contentBlocking` policy (CONTRACT.md §4.5): the engine loads the blocking engine Refrax
/// names and reports it, allowlisted hosts and their subdomains are spared, and turning blocking
/// off and on takes effect on the next load.
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
        ConformanceTest(name: "blocking.status-and-blocking", timeout: 60) { context in
            try context.engine.require("contentBlocking")
            let applied = Date()
            try await context.contentBlockingApplied()
            context.note(String(format: "engine applied %.2f s after the policy", -applied.timeIntervalSinceNow))
            let results = try await Self.results(context)
            try expectEqual(results["image"], "blocked", "listed image")
            try expectEqual(results["allowed"], "loaded", "unlisted image")
            try expectEqual(results["script"], "blocked", "listed script ($script)")
            try expectEqual(results["fetch"], "blocked", "fetch() ($xhr)")
        },

        ConformanceTest(name: "blocking.refuses-another-format", timeout: 60) { context in
            try context.engine.require("contentBlocking")
            let mark = context.engine.events.count
            try context.contentBlocking(format: "adblock-0.0.0;shields-0")
            let status = try await context.engine.waitForEvent("contentBlockingStatus", after: mark, timeout: 30) { $0["reason"] != nil }
            try expectEqual(status["status"] as? String, "unfiltered", "status for a foreign format")
            try expect(!((status["reason"] as? String) ?? "").isEmpty, "unfiltered status gives a reason")
            let results = try await Self.results(context)
            try expectEqual(results["image"], "loaded", "listed image with no engine loaded")
        },

        ConformanceTest(name: "blocking.allowlisted-hosts-and-subdomains", timeout: 60) { context in
            try await context.contentBlockingApplied(allowlistedHosts: ["localhost", "0.1"])
            let subdomain = try await Self.results(context, host: "sub.localhost")
            try expectEqual(subdomain, ["image": "loaded", "allowed": "loaded", "script": "loaded", "fetch": "loaded"], "sub.localhost under an allowlisted localhost")
            // "0.1" is no parent of 127.0.0.1.
            let address = try await Self.results(context)
            try expectEqual(address["image"], "blocked", "127.0.0.1 with 0.1 allowlisted")
        },

        ConformanceTest(name: "blocking.off-and-on-again", timeout: 60) { context in
            try await context.contentBlockingApplied()
            try expectEqual(try await Self.results(context)["image"], "blocked", "blocking on")
            let mark = context.engine.events.count
            try context.contentBlocking(enabled: false)
            let off = try await context.engine.waitForEvent("contentBlockingStatus", after: mark, timeout: 30)
            try expectEqual(off["status"] as? String, "unfiltered", "status with blocking off")
            let results = try await Self.results(context)
            try expectEqual(results["image"], "loaded", "image with blocking off")
            try expectEqual(results["script"], "loaded", "script with blocking off")
            let reenabled = Date()
            try await context.contentBlockingApplied()
            try expectEqual(try await Self.results(context)["image"], "blocked", "blocking on again")
            context.note(String(format: "re-enabled in %.2f s", -reenabled.timeIntervalSinceNow))
        },
    ]
}
