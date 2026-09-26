// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import Darwin
import Foundation

/// Page events (CONTRACT.md §4.1) in the order Refrax's reducer relies on.
enum NavigationTests {
    /// A loopback port nothing listens on.
    static func closedPort() -> UInt16 {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                _ = bind(socket, $0, length)
                _ = getsockname(socket, $0, &length)
            }
        }
        return UInt16(bigEndian: address.sin_port)
    }

    static let all: [ConformanceTest] = [
        ConformanceTest(name: "navigation.event-order") { context in
            let page = try context.engine.makePage(context.url("/html/basic"))
            let finished = try await page.waitForFinish()
            try expectEqual(finished["statusCode"] as? Int, 200, "statusCode")
            let names = page.events.map(\.name)
            guard let started = names.firstIndex(of: "navigationStarted"),
                  let committed = names.firstIndex(of: "navigationCommitted"),
                  let done = names.firstIndex(of: "navigationFinished")
            else { throw Failure("missing navigation events: \(names)") }
            try expect(started < committed && committed < done, "order: \(names)")
            try await page.waitForEvent("titleChanged") { $0["title"] as? String == "basic" }
            let progress = page.events.filter { $0.name == "progressChanged" }.compactMap { $0.fields["progress"] as? Double }
            try expect(progress.allSatisfy { (0...1).contains($0) }, "progress outside 0…1: \(progress)")
            let loading = try await eventually("loading to stop") {
                page.events.last { $0.name == "loadingChanged" }.flatMap { $0.fields["isLoading"] as? Bool == false ? true : nil }
            }
            try expect(loading, "last loadingChanged")
        },

        ConformanceTest(name: "navigation.http-errors-are-pages") { context in
            let page = try await context.page("/html/basic")
            let finished = try await page.load(context.url("/status/404"))
            try expectEqual(finished["statusCode"] as? Int, 404, "statusCode")
            try expect(!page.events.contains { $0.name == "navigationFailed" }, "a 404 was reported as a failure")
        },

        ConformanceTest(name: "navigation.redirects") { context in
            let page = try await context.page("/html/basic")
            let mark = page.events.count
            try await page.load(context.url("/redirect?to=/html/other"))
            try await page.waitForEvent("navigationRedirected", after: mark) { ($0["url"] as? String)?.hasSuffix("/html/other") == true }
            try await page.waitForEvent("navigationCommitted", after: mark) { ($0["url"] as? String)?.hasSuffix("/html/other") == true }
        },

        ConformanceTest(name: "navigation.connection-refused") { context in
            let page = try await context.page("/html/basic")
            let mark = page.events.count
            page.command("load", ["request": ["url": "http://127.0.0.1:\(closedPort())/", "headers": [:]]])
            let failed = try await page.waitForEvent("navigationFailed", after: mark, timeout: 20)
            let failure = failed["failure"] as? [String: Any] ?? [:]
            try expectEqual(failure["kind"] as? String, "cannotConnectToHost", "kind")
            try expectEqual(failure["isProvisional"] as? Bool, true, "isProvisional")
        },

        ConformanceTest(name: "navigation.unknown-host") { context in
            let page = try await context.page("/html/basic")
            let mark = page.events.count
            page.command("load", ["request": ["url": "http://conformance.invalid/", "headers": [:]]])
            let failed = try await page.waitForEvent("navigationFailed", after: mark, timeout: 20)
            try expectEqual((failed["failure"] as? [String: Any])?["kind"] as? String, "cannotFindHost", "kind")
        },

        ConformanceTest(name: "navigation.back-and-forward") { context in
            let page = try await context.page("/html/basic")
            try await page.load(context.url("/html/other"))
            try await page.waitForEvent("backForwardChanged") { $0["canGoBack"] as? Bool == true }
            let mark = page.events.count
            page.command("goBack")
            let back = try await page.waitForEvent("navigationCommitted", after: mark)
            try expectEqual(back["isBackForward"] as? Bool, true, "isBackForward")
            try expect((back["url"] as? String)?.hasSuffix("/html/basic") == true, "went back to \(back["url"] ?? "nil")")
            try await page.waitForEvent("backForwardChanged", after: mark) { $0["canGoForward"] as? Bool == true }
            let forwardMark = page.events.count
            page.command("goForward")
            let forward = try await page.waitForEvent("navigationCommitted", after: forwardMark)
            try expect((forward["url"] as? String)?.hasSuffix("/html/other") == true, "went forward to \(forward["url"] ?? "nil")")
        },

        ConformanceTest(name: "navigation.same-document-changes-only-the-url") { context in
            let page = try await context.page("/html/basic")
            let mark = page.events.count
            _ = try await page.evaluate("history.pushState({}, '', '/html/pushed')")
            try await page.waitForEvent("urlChanged", after: mark) { ($0["url"] as? String)?.hasSuffix("/html/pushed") == true }
            _ = try await page.evaluate("location.hash = 'fragment'")
            try await page.waitForEvent("urlChanged", after: mark) { ($0["url"] as? String)?.hasSuffix("#fragment") == true }
            try expect(!page.events[mark...].contains { $0.name == "navigationCommitted" }, "a same-document change committed a navigation")
        },

        ConformanceTest(name: "navigation.load-sends-headers") { context in
            let page = try await context.page("/html/basic")
            try await page.load(context.url("/echo"), headers: ["X-Conformance": "yes-3"])
            let echo = try await page.evaluate("JSON.parse(document.getElementById('echo').textContent).headers['x-conformance']") as? String
            try expectEqual(echo, "yes-3", "header the server received")
        },

        ConformanceTest(name: "loading.follows-the-main-frame") { context in
            // Refrax shows loadingChanged as the reload button and tab spinner, so only the main
            // frame's new documents may move it: never a frame the page adds, nor a pushState.
            let page = try await context.page("/html/basic")
            let mark = page.events.count
            _ = try await page.evaluate("""
                new Promise(done => {
                  const frame = document.createElement('iframe');
                  frame.onload = () => { history.pushState({}, '', '?pushed'); done(true); };
                  frame.src = '/html/child';
                  document.body.append(frame);
                })
                """)
            try await pause(0.5)
            let changes = page.events[mark...].filter { $0.name == "loadingChanged" }.map { $0.fields["isLoading"] as? Bool }
            try expectEqual(changes.count, 0, "loadingChanged for a subframe and a pushState (\(changes))")

            let next = page.events.count
            try await page.load(context.url("/html/frames"))
            @MainActor func loads() -> [Bool] {
                page.events[next...].filter { $0.name == "loadingChanged" }.compactMap { $0.fields["isLoading"] as? Bool }
            }
            try await eventually("loadingChanged to settle") { loads().last == false ? true : nil }
            try await pause(0.3)
            try expectEqual(loads(), [true, false], "loadingChanged for a new document with a frame")
        },

        ConformanceTest(name: "navigation.stop-loading") { context in
            let page = try await context.page("/html/basic")
            let mark = page.events.count
            page.command("load", ["request": ["url": context.url("/hang"), "headers": [:]]])
            try await page.waitForEvent("loadingChanged", after: mark) { $0["isLoading"] as? Bool == true }
            page.command("stopLoading")
            try await page.waitForEvent("loadingChanged", after: mark) { $0["isLoading"] as? Bool == false }
            try expectEqual(try await page.evaluate("document.title") as? String, "basic", "the page after stopping")
        },
    ]
}
