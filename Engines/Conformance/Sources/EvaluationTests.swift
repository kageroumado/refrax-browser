// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import Foundation

/// `evaluateScript` (CONTRACT.md §4.4): results are plain JSON, errors carry the page's own
/// message, promises settle before the call completes, worlds are separate.
enum EvaluationTests {
    static let all: [ConformanceTest] = [
        ConformanceTest(name: "eval.values") { context in
            let page = try await context.page("/html/basic")
            let value = try await page.evaluate("({a: [1, 'x', true, null], b: {c: 2.5}, d: ''})")
            try expectEqual(JSON.canonical(value), #"{"a":[1,"x",true,null],"b":{"c":2.5},"d":""}"#, "structure")
        },

        ConformanceTest(name: "eval.undefined-is-null") { context in
            let page = try await context.page("/html/basic")
            for source in ["undefined", "void 0", "(() => {})()", "Promise.resolve()"] {
                let raw = String(decoding: try await page.evaluateRaw(source), as: UTF8.self)
                try expectEqual(raw, "null", source)
            }
        },

        ConformanceTest(name: "eval.integers-stay-integral") { context in
            let page = try await context.page("/html/basic")
            // Beyond int32, where engines tend to switch to doubles and print "1099511627776.0".
            for (source, expected) in [("2 ** 40", "1099511627776"), ("3", "3"), ("-7", "-7"), ("[2 ** 33]", "[8589934592]")] {
                let raw = String(decoding: try await page.evaluateRaw(source), as: UTF8.self)
                try expectEqual(raw, expected, source)
            }
            let fraction = try await page.evaluate("0.1 + 0.2") as? Double
            try expectEqual(fraction, 0.30000000000000004, "0.1 + 0.2")
        },

        ConformanceTest(name: "eval.exception-message") { context in
            let page = try await context.page("/html/basic")
            let message = try await page.evaluationError("throw new Error('boom-42')")
            try expect(message.contains("boom-42"), "error message \(message) lacks the thrown text")
            let thrownString = try await page.evaluationError("throw 'plain-string-9'")
            try expect(thrownString.contains("plain-string-9"), "error message \(thrownString) lacks the thrown string")
        },

        ConformanceTest(name: "eval.syntax-error-says-so") { context in
            // Refrax retries a script as a program only when the error names a SyntaxError.
            let page = try await context.page("/html/basic")
            let message = try await page.evaluationError("function (")
            try expect(message.contains("SyntaxError"), "error message \(message) does not name SyntaxError")
        },

        ConformanceTest(name: "eval.promises-settle-first") { context in
            let page = try await context.page("/html/basic")
            let late = try await page.evaluate("new Promise(r => setTimeout(() => r('late'), 300))") as? String
            try expectEqual(late, "late", "resolved value")
            let message = try await page.evaluationError("Promise.reject(new Error('nope-7'))")
            try expect(message.contains("nope-7"), "rejection message \(message) lacks the reason")
        },

        ConformanceTest(name: "eval.isolated-worlds") { context in
            let page = try await context.page("/html/basic")
            _ = try await page.evaluate("window.pageSecret = 1")
            let seen = try await page.evaluate("typeof window.pageSecret", world: "conformance") as? String
            try expectEqual(seen, "undefined", "page global seen from an isolated world")
            let title = try await page.evaluate("document.title", world: "conformance") as? String
            try expectEqual(title, "basic", "the DOM is shared")
            _ = try await page.evaluate("window.worldState = 5", world: "conformance")
            let kept = try await page.evaluate("window.worldState", world: "conformance") as? Int
            try expectEqual(kept, 5, "a world's globals across evaluations")
            let other = try await page.evaluate("typeof window.worldState", world: "conformance-2") as? String
            try expectEqual(other, "undefined", "another world's global")
            let fromPage = try await page.evaluate("typeof window.worldState") as? String
            try expectEqual(fromPage, "undefined", "a world's global from the page")
        },

        ConformanceTest(name: "eval.user-gesture-only-when-asked") { context in
            let page = try await context.page("/html/basic")
            let without = try await page.evaluate("navigator.userActivation.isActive") as? Bool
            try expectEqual(without, false, "activation without userGesture")
            let with = try await page.evaluate("navigator.userActivation.isActive", gesture: true) as? Bool
            try expectEqual(with, true, "activation with userGesture")
        },

        ConformanceTest(name: "eval.burst-results-reach-their-callers") { context in
            // 200 evaluations in flight at once: each completion must carry its own result.
            let page = try await context.page("/html/basic")
            var results: [Int: Int] = [:]
            var failures: [String] = []
            for index in 0..<200 {
                page.page.evaluateScript(JSON.data(["source": "new Promise(r => setTimeout(() => r(\(index) * 3), \(index % 7)))", "world": ["page": [:]], "userGesture": false])) { data, error in
                    MainActor.assumeIsolated {
                        if let data, let value = JSON.parse(data) as? Int {
                            results[index] = value
                        } else {
                            failures.append("\(index): \(error?.localizedDescription ?? "bad result")")
                        }
                    }
                }
            }
            try await eventually("all 200 completions (have \(results.count + failures.count))", timeout: 30) {
                results.count + failures.count == 200 ? true : nil
            }
            try expect(failures.isEmpty, "failures: \(failures.prefix(3))")
            let wrong = results.filter { $0.value != $0.key * 3 }
            try expect(wrong.isEmpty, "\(wrong.count) results reached the wrong caller, e.g. \(wrong.first.map { "\($0.key) → \($0.value)" } ?? "")")
        },

        ConformanceTest(name: "eval.unserializable-results-complete") { context in
            // A cycle, a function, a DOM node: never JSON. The call must still complete, and the
            // page must stay usable.
            let page = try await context.page("/html/basic")
            for source in ["(() => { const a = {}; a.self = a; return a; })()", "() => 1", "document.body", "Symbol('s')", "10n"] {
                _ = try? await page.evaluateRaw(source, timeout: 10)
            }
            let alive = try await page.evaluate("1 + 1") as? Int
            try expectEqual(alive, 2, "the page after unserializable results")
        },

        ConformanceTest(name: "eval.close-while-pending-completes") { context in
            // Refrax awaits every evaluation; one that never completes after close leaks forever.
            let page = try await context.page("/html/basic")
            var completed = false
            page.page.evaluateScript(JSON.data(["source": "new Promise(() => {})", "world": ["page": [:]], "userGesture": false])) { _, _ in
                MainActor.assumeIsolated { completed = true }
            }
            try await pause(0.3)
            page.close()
            try await eventually("the pending evaluation's completion after close", timeout: 10) { completed ? true : nil }
        },
    ]
}
