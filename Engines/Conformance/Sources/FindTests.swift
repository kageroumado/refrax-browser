// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import Foundation

/// `find` and `stopFinding` (CONTRACT.md §4.2) and the `findResultChanged` event (§4.1).
enum FindTests {
    /// The last `findResultChanged` after `mark` that is final.
    @MainActor
    static func result(_ page: TestPage, after mark: Int) async throws -> (matches: Int, active: Int) {
        let event = try await page.waitForEvent("findResultChanged", after: mark, timeout: 10) { $0["isFinal"] as? Bool == true }
        return (event["matches"] as? Int ?? -1, event["activeMatch"] as? Int ?? -1)
    }

    @MainActor
    static func find(_ page: TestPage, _ text: String, forward: Bool = true, matchCase: Bool = false, next: Bool = false) async throws -> (matches: Int, active: Int) {
        let mark = page.events.count
        page.command("find", ["query": ["text": text, "forward": forward, "matchCase": matchCase, "findNext": next]])
        return try await result(page, after: mark)
    }

    static let all: [ConformanceTest] = [
        ConformanceTest(name: "find.counts-and-steps", timeout: 60) { context in
            try context.engine.require("findInPage")
            let page = try await context.page("/html/find")
            defer { page.close() }
            let first = try await find(page, "needle")
            try expectEqual(first.matches, 3, "matches for needle (case-insensitive)")
            try expectEqual(first.active, 1, "active match after a new search")
            let second = try await find(page, "needle", next: true)
            try expectEqual(second.active, 2, "active match after find next")
            let back = try await find(page, "needle", forward: false, next: true)
            try expectEqual(back.active, 1, "active match after find previous")
            let cased = try await find(page, "NEEDLE", matchCase: true)
            try expectEqual(cased.matches, 1, "matches for NEEDLE with case")
            let none = try await find(page, "haystack")
            try expectEqual(none.matches, 0, "matches for absent text")
            try expectEqual(none.active, 0, "active match with no matches")
        },

        ConformanceTest(name: "find.stop-and-empty", timeout: 60) { context in
            try context.engine.require("findInPage")
            let page = try await context.page("/html/find")
            defer { page.close() }
            _ = try await find(page, "needle")
            let second = try await find(page, "needle", next: true)
            try expectEqual(second.active, 2, "active match after find next")
            page.command("stopFinding")
            // A stopped session is over: continuing starts a new one at the first match.
            let restarted = try await find(page, "needle", next: true)
            try expectEqual(restarted.active, 1, "active match after stopFinding")
            let empty = try await find(page, "")
            try expectEqual(empty.matches, 0, "matches for empty text")
            // Results belong to their document: a new one reports none.
            _ = try await find(page, "needle")
            let mark = page.events.count
            try await page.load(context.url("/html/basic"))
            let reset = try await page.waitForEvent("findResultChanged", after: mark)
            try expectEqual(reset["matches"] as? Int, 0, "matches after navigating away")
        },
    ]
}
