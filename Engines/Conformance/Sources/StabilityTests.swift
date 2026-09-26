// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import AppKit

/// Pages under churn, renderers dying, profiles kept apart, and the page-level commands whose
/// effect only shows inside the page.
enum StabilityTests {
    static let all: [ConformanceTest] = [
        ConformanceTest(name: "renderer.terminate-then-reload") { context in
            try context.engine.require("rendererControl")
            let page = try await context.page("/html/basic")
            let mark = page.events.count
            page.command("terminateRenderer")
            let terminated = try await page.waitForEvent("rendererHealthChanged", after: mark) {
                ($0["health"] as? [String: Any])?["terminated"] != nil
            }
            let reason = ((terminated["health"] as? [String: Any])?["terminated"] as? [String: Any])?["reason"] as? String
            try expectEqual(reason, "requestedByBrowser", "termination reason")
            try await page.load(context.url("/html/other"))
            try expectEqual(try await page.evaluate("document.title") as? String, "other", "the page after a new renderer")
        },

        ConformanceTest(name: "pages.events-reach-their-own-page") { context in
            // Twelve pages at once: each page's events and evaluations must be its own.
            let pages = try (0..<12).map { try context.engine.makePage(context.url("/html/basic?page=\($0)")) }
            for page in pages {
                try await page.waitForFinish()
            }
            for (index, page) in pages.enumerated() {
                let search = try await page.evaluate("location.search") as? String
                try expectEqual(search, "?page=\(index)", "page \(index) evaluated in")
                let committed = page.events.filter { $0.name == "navigationCommitted" }.compactMap { $0.fields["url"] as? String }
                try expect(committed.allSatisfy { $0.hasSuffix("?page=\(index)") }, "page \(index) saw commits \(committed)")
            }
        },

        ConformanceTest(name: "pages.churn", timeout: 120) { context in
            // Pages closed at every stage of loading, some before a response ever arrives.
            var closed: [TestPage] = []
            for index in 0..<24 {
                let path = ["/html/basic", "/slow?ms=400", "/hang", "/html/frames"][index % 4]
                let page = try context.engine.makePage(context.url(path))
                try await pause(Double(index % 5) * 0.05)
                if index % 3 == 0 {
                    _ = try? await page.evaluateRaw("document.readyState", timeout: 3)
                }
                page.close()
                closed.append(page)
            }
            try await pause(1.5)
            let late = closed.map(\.callbacksAfterClose).reduce(0, +)
            try expectEqual(late, 0, "delegate callbacks after close")
            let survivor = try await context.page("/html/basic")
            try expectEqual(try await survivor.evaluate("document.title") as? String, "basic", "a page after the churn")
        },

        ConformanceTest(name: "pages.close-while-the-host-builds-views", timeout: 120) { context in
            // Closing a page while the host is still attaching its views: the host must never
            // be left addressing a container the client no longer knows (a CHECK in the
            // client's process, which is Refrax's).
            for iteration in 0..<40 {
                let page = try context.engine.makePage(context.url("/html/basic?close=\(iteration)"))
                if iteration % 4 != 0 {
                    try await Task.sleep(for: .milliseconds(iteration % 12))
                }
                page.close()
            }
            try await pause(1)
            let survivor = try await context.page("/html/basic")
            try expectEqual(try await survivor.evaluate("1 + 1") as? Int, 2, "a page after the closes")
        },

        ConformanceTest(name: "pages.close-before-first-response") { context in
            let page = try context.engine.makePage(context.url("/hang"))
            try await pause(0.2)
            page.close()
            let next = try await context.page("/html/basic")
            try expectEqual(try await next.evaluate("1") as? Int, 1, "a page after closing a hung one")
        },

        ConformanceTest(name: "profiles.storage-stays-in-its-profile", timeout: 90) { context in
            let a: [String: Any] = ["isolated": ["id": UUID().uuidString]]
            let b: [String: Any] = ["isolated": ["id": UUID().uuidString]]
            let ephemeral: [String: Any] = ["ephemeral": ["id": UUID().uuidString]]
            let shared = try await context.page("/html/basic")
            _ = try await shared.evaluate("localStorage.setItem('k', 'shared'); document.cookie = 'c=shared; path=/'")
            let inA = try await context.page("/html/basic", profile: a)
            try expect(try await inA.evaluate("localStorage.getItem('k')") is NSNull, "profile A sees shared storage")
            try expectEqual(try await inA.evaluate("document.cookie") as? String, "", "profile A's cookies")
            _ = try await inA.evaluate("localStorage.setItem('k', 'a')")
            let againA = try await context.page("/html/basic", profile: a)
            try expectEqual(try await againA.evaluate("localStorage.getItem('k')") as? String, "a", "a second page in profile A")
            let inB = try await context.page("/html/basic", profile: b)
            try expect(try await inB.evaluate("localStorage.getItem('k')") is NSNull, "profile B sees profile A")
            let inEphemeral = try await context.page("/html/basic", profile: ephemeral)
            try expect(try await inEphemeral.evaluate("localStorage.getItem('k')") is NSNull, "an ephemeral profile sees shared storage")
        },

        ConformanceTest(name: "profiles.remove-deletes-storage", timeout: 400) { context in
            let isolated: [String: Any] = ["isolated": ["id": UUID().uuidString]]
            let ephemeral: [String: Any] = ["ephemeral": ["id": UUID().uuidString]]
            for profile in [isolated, ephemeral] {
                let page = try await context.page("/html/basic", profile: profile)
                _ = try await page.evaluate("localStorage.setItem('k', 'kept')")
                page.close()
                let started = Date()
                try await context.engine.removeProfile(profile)
                context.note(String(format: "removeProfile %@ took %.1f s", profile.keys.first ?? "", -started.timeIntervalSinceNow))
                let fresh = try await context.page("/html/basic", profile: profile)
                try expect(try await fresh.evaluate("localStorage.getItem('k')") is NSNull, "storage survived removeProfile for \(JSON.canonical(profile))")
            }
        },

        ConformanceTest(name: "snapshot.matches-the-view") { context in
            try context.engine.require("snapshots")
            let page = try await context.page("/html/basic")
            let scale = page.window.backingScaleFactor
            let bounds = page.page.view.bounds
            let whole = try await page.snapshot()
            try expectEqual(whole.width, Int(bounds.width * scale), "full snapshot width")
            try expectEqual(whole.height, Int(bounds.height * scale), "full snapshot height")
            let part = try await page.snapshot(NSRect(x: 10, y: 20, width: 100, height: 50))
            try expectEqual(part.width, Int(100 * scale), "partial snapshot width")
            try expectEqual(part.height, Int(50 * scale), "partial snapshot height")
        },

        ConformanceTest(name: "zoom.applies-and-reports") { context in
            try context.engine.require("zoom")
            let page = try await context.page("/html/basic")
            let base = try await page.evaluate("devicePixelRatio") as? Double ?? 0
            let mark = page.events.count
            page.command("setZoom", ["factor": 1.5])
            try await page.waitForEvent("zoomChanged", after: mark) { ($0["factor"] as? Double).map { abs($0 - 1.5) < 0.01 } ?? false }
            let zoomed = try await eventuallyAsync("devicePixelRatio to follow the zoom") {
                let ratio = try await page.evaluate("devicePixelRatio") as? Double ?? 0
                return abs(ratio - base * 1.5) < 0.01 ? ratio : nil
            }
            try expect(zoomed > base, "zoom")
        },

        ConformanceTest(name: "zoom.stays-in-its-page") { context in
            // Refrax owns zoom and sends it per page; the engine keeps none of its own.
            try context.engine.require("zoom")
            let zoomed = try await context.page("/html/basic")
            let base = try await zoomed.evaluate("devicePixelRatio") as? Double ?? 0
            zoomed.command("setZoom", ["factor": 2.0])
            try await eventuallyAsync("the zoomed page") {
                abs((try await zoomed.evaluate("devicePixelRatio") as? Double ?? 0) - base * 2) < 0.01 ? true : nil
            }
            let sibling = try await context.page("/html/other")
            let ratio = try await sibling.evaluate("devicePixelRatio") as? Double ?? 0
            try expectEqual(ratio, base, "devicePixelRatio of another page on the same host")
        },

        ConformanceTest(name: "visibility.reaches-the-page") { context in
            let page = try await context.page("/html/basic")
            page.command("setVisibility", ["visibility": "hidden"])
            try await eventuallyAsync("document.visibilityState hidden") {
                try await page.evaluate("document.visibilityState") as? String == "hidden" ? true : nil
            }
            page.command("setVisibility", ["visibility": "visible"])
            try await eventuallyAsync("document.visibilityState visible") {
                try await page.evaluate("document.visibilityState") as? String == "visible" ? true : nil
            }
        },
    ]
}
