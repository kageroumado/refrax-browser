// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import Foundation

/// Requests (CONTRACT.md §4.3): the engine asks, Refrax answers once, and the page acts on
/// exactly that answer.
enum RequestTests {
    /// A profile of its own, so permission answers never persist into other tests.
    static func ephemeral() -> [String: Any] {
        ["ephemeral": ["id": UUID().uuidString]]
    }

    static let all: [ConformanceTest] = [
        ConformanceTest(name: "dialogs.answers-reach-the-page") { context in
            let page = try await context.page("/html/basic")
            _ = try await page.evaluate("alert('a1')", gesture: true)
            let alert = try await page.waitForRequest("javaScriptDialog")
            let dialog = alert["dialog"] as? [String: Any] ?? [:]
            try expectEqual(dialog["kind"] as? String, "alert", "kind")
            try expectEqual(dialog["message"] as? String, "a1", "message")
            try expect((dialog["origin"] as? String)?.hasPrefix("http://127.0.0.1") == true, "origin \(dialog["origin"] ?? "nil")")
            try expectEqual(try await page.evaluate("confirm('c1')", gesture: true) as? Bool, true, "confirm after confirm")
            try expectEqual(try await page.evaluate("prompt('p1', 'default')", gesture: true) as? String, "conformance", "prompt text")
            page.answer = { _ in ["cancel": [:]] }
            try expectEqual(try await page.evaluate("confirm('c2')", gesture: true) as? Bool, false, "confirm after cancel")
            try expect(try await page.evaluate("prompt('p2')", gesture: true) is NSNull, "prompt after cancel is null")
        },

        ConformanceTest(name: "dialogs.long-messages-are-capped") { context in
            let page = try await context.page("/html/basic")
            _ = try await page.evaluate("alert('x'.repeat(100000))", gesture: true)
            let request = try await page.waitForRequest("javaScriptDialog")
            let message = (request["dialog"] as? [String: Any])?["message"] as? String ?? ""
            try expect(message.count <= 2000, "a \(message.count)-character message reached Refrax (cap 2,000)")
        },

        ConformanceTest(name: "dialogs.unanswered-dialog-never-blocks-navigation") { context in
            let page = try await context.page("/html/basic")
            page.answer = { request in request.name == "javaScriptDialog" ? nil : TestPage.defaultAnswer(request) }
            page.page.evaluateScript(JSON.data(["source": "alert('pending')", "world": ["page": [:]], "userGesture": true])) { _, _ in }
            try await page.waitForRequest("javaScriptDialog")
            let finished = try await page.load(context.url("/html/other"))
            try expect((finished["url"] as? String)?.hasSuffix("/html/other") == true, "navigated to \(finished["url"] ?? "nil")")
            // Refrax may answer after the page moved on; the late reply must be harmless.
            page.pendingReplies.forEach { $0(JSON.data(["confirm": [:]])) }
            try expectEqual(try await page.evaluate("document.title") as? String, "other", "the page after a late answer")
        },

        ConformanceTest(name: "permissions.denied-is-denied") { context in
            let page = try await context.page("/html/basic", profile: ephemeral())
            let camera = try await page.evaluate("navigator.mediaDevices.getUserMedia({video: true}).then(() => 'granted', e => e.name)", gesture: true) as? String
            try expectEqual(camera, "NotAllowedError", "getUserMedia after deny")
            let request = try await page.waitForRequest("permission")
            try expect(["camera", "cameraAndMicrophone"].contains(request["kind"] as? String ?? ""), "kind \(request["kind"] ?? "nil")")
            try expect((request["origin"] as? String)?.hasPrefix("http://127.0.0.1") == true, "origin \(request["origin"] ?? "nil")")
            let geolocation = try await page.evaluate("new Promise(r => navigator.geolocation.getCurrentPosition(() => r(0), e => r(e.code)))", gesture: true) as? Int
            try expectEqual(geolocation, 1, "geolocation error code (PERMISSION_DENIED)")
        },

        ConformanceTest(name: "permissions.allowed-is-allowed") { context in
            // An isolated profile: Chromium denies notifications in off-the-record profiles
            // without asking, so incognito can't be told apart by the prompt.
            let profile: [String: Any] = ["isolated": ["id": UUID().uuidString]]
            let page = try context.engine.makePage(context.url("/html/basic"), profile: profile)
            page.answer = { request in request.name == "permission" ? ["allow": [:]] : TestPage.defaultAnswer(request) }
            try await page.waitForFinish()
            let result = try await page.evaluate("Notification.requestPermission()", gesture: true) as? String
            try expectEqual(result, "granted", "notification permission after allow")
            let request = try await page.waitForRequest("permission")
            try expectEqual(request["kind"] as? String, "notifications", "kind")
            page.close()
            try await context.engine.removeProfile(profile)
        },

        ConformanceTest(name: "downloads.land-where-refrax-says") { context in
            let folder = FileManager.default.temporaryDirectory.appending(path: "conformance-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            defer { try? FileManager.default.trashItem(at: folder, resultingItemURL: nil) }
            let destination = folder.appending(path: "saved.bin")
            let page = try context.engine.makePage(context.url("/html/download"))
            page.answer = { request in
                request.name == "download" ? ["saveTo": ["url": destination.absoluteString]] : TestPage.defaultAnswer(request)
            }
            try await page.waitForFinish()
            _ = try await page.evaluate("document.getElementById('link').click()", gesture: true)
            let request = try await page.waitForRequest("download")
            try expectEqual(request["suggestedFilename"] as? String, "payload.bin", "suggestedFilename")
            let id = JSON.canonical(request["id"])
            try await page.waitForEvent("downloadFinished", timeout: 30) { JSON.canonical($0["id"]) == id }
            let size = try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? Int
            try expectEqual(size, 100_000, "bytes on disk")
        },

        ConformanceTest(name: "downloads.cancel-means-no-file") { context in
            let page = try await context.page("/html/download")
            _ = try await page.evaluate("document.getElementById('link').click()", gesture: true)
            try await page.waitForRequest("download")
            try await pause(2)
            try expect(!page.events.contains { $0.name == "downloadFinished" }, "a cancelled download finished")
            try expectEqual(try await page.evaluate("document.title") as? String, "download", "the page after a cancelled download")
        },

        ConformanceTest(name: "open-url.window-open-asks-refrax") { context in
            let page = try await context.page("/html/basic")
            _ = try await page.evaluate("void window.open('/html/other')", gesture: true)
            let request = try await page.waitForRequest("openURL")
            try expect((request["url"] as? String)?.hasSuffix("/html/other") == true, "url \(request["url"] ?? "nil")")
            try expect(["foregroundTab", "backgroundTab", "popup", "newWindow"].contains(request["disposition"] as? String ?? ""), "disposition \(request["disposition"] ?? "nil")")
            try expectEqual(request["userGesture"] as? Bool, true, "userGesture")
        },
    ]
}
