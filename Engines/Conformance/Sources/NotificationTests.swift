// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import Foundation

/// Web notifications (CONTRACT.md §4.1, §4.5, §4.6): Refrax's policy is the only permission,
/// shown notifications reach Refrax, and its clicks and dismissals reach the page or worker.
enum NotificationTests {
    /// A page on the notify fixture in a persistent profile of its own (Chromium denies
    /// notifications off the record without asking).
    @MainActor
    static func notifyPage(_ context: Context) async throws -> (page: TestPage, profile: [String: Any], id: String) {
        try context.engine.require("notifications")
        let id = UUID().uuidString
        let profile: [String: Any] = ["isolated": ["id": id]]
        let page = try context.engine.makePage(context.url("/html/notify"), profile: profile)
        try await page.waitForFinish()
        return (page, profile, id)
    }

    /// The fixture server's origin, as the contract serializes origins.
    @MainActor
    static func origin(_ context: Context) -> String {
        context.url("")
    }

    @MainActor
    static func permission(_ page: TestPage) async throws -> String? {
        try await page.evaluate("Notification.permission") as? String
    }

    @MainActor
    static func waitForPageEvent(_ page: TestPage, _ entry: String) async throws {
        try await eventuallyAsync("page event \(entry)") {
            let events = try await page.evaluate("events") as? [String] ?? []
            return events.contains(entry) ? true : nil
        }
    }

    static let all: [ConformanceTest] = [
        ConformanceTest(name: "notifications.permission-is-refrax-policy") { context in
            let (page, profile, _) = try await notifyPage(context)
            let origin = origin(context)
            try expectEqual(try await permission(page), "default", "permission with no decision")

            context.notifications(granted: [origin])
            try expectEqual(try await permission(page), "granted", "permission once granted")
            context.notifications(denied: [origin])
            try expectEqual(try await permission(page), "denied", "permission once denied")
            context.notifications(asksByDefault: false)
            try expectEqual(try await permission(page), "denied", "permission when origins may not ask")
            context.notifications()
            try expectEqual(try await permission(page), "default", "permission once the decision is removed")

            // Refrax answers without sending a policy: Chromium must remember nothing.
            page.answer = { request in request.name == "permission" ? ["allow": [:]] : TestPage.defaultAnswer(request) }
            try expectEqual(try await page.evaluate("Notification.requestPermission()", gesture: true) as? String, "granted", "request answered allow")
            try expectEqual(try await permission(page), "default", "permission after an answer with no policy")
            // After a denial Chromium cancels the tab's notification requests until a navigation the
            // user starts; each attempt loads the page again, as Refrax's navigations do.
            page.answer = TestPage.defaultAnswer
            for attempt in 1 ... 4 {
                try await page.load(context.url("/html/notify"))
                try expectEqual(try await page.evaluate("Notification.requestPermission()", gesture: true) as? String, "denied", "request \(attempt) answered deny")
            }
            let asked = page.requests.count { $0.name == "permission" && $0.fields["kind"] as? String == "notifications" }
            try expectEqual(asked, 5, "requests that reached Refrax (none remembered or embargoed)")
            page.close()
            try await context.engine.removeProfile(profile)
        },

        ConformanceTest(name: "notifications.page-notifications-reach-refrax") { context in
            let (page, profile, _) = try await notifyPage(context)
            let origin = origin(context)
            context.notifications(granted: [origin])

            _ = try await page.evaluate("show('T1', {body: 'B1', tag: 't1', icon: '/asset/pic.png', silent: true})")
            let shown = try await page.waitForEvent("notificationShown")
            let notification = shown["notification"] as? [String: Any] ?? [:]
            try expectEqual(notification["title"] as? String, "T1", "title")
            try expectEqual(notification["body"] as? String, "B1", "body")
            try expectEqual(notification["tag"] as? String, "t1", "tag")
            try expectEqual(notification["origin"] as? String, origin, "origin")
            try expectEqual(notification["isSilent"] as? Bool, true, "isSilent")
            try expect((notification["iconURL"] as? String)?.hasSuffix("/asset/pic.png") == true, "iconURL \(notification["iconURL"] ?? "nil")")
            let id = try expectID(notification)
            try await waitForPageEvent(page, "show:T1")

            page.command("notificationClicked", ["id": id])
            try await waitForPageEvent(page, "click:T1")

            _ = try await page.evaluate("show('T2', {})")
            let second = try await page.waitForEvent("notificationShown") { ($0["notification"] as? [String: Any])?["title"] as? String == "T2" }
            let secondID = try expectID(second["notification"] as? [String: Any] ?? [:])
            _ = try await page.evaluate("last.close(), true")
            try await page.waitForEvent("notificationClosed") { $0["id"] as? String == secondID }

            _ = try await page.evaluate("show('T3', {})")
            let third = try await page.waitForEvent("notificationShown") { ($0["notification"] as? [String: Any])?["title"] as? String == "T3" }
            page.command("notificationClosed", ["id": try expectID(third["notification"] as? [String: Any] ?? [:])])
            try await waitForPageEvent(page, "close:T3")

            // Only allowed origins show anything.
            context.notifications(denied: [origin])
            _ = try? await page.evaluate("show('T4', {})")
            try await pause(1)
            try expect(!page.events.contains { ($0.fields["notification"] as? [String: Any])?["title"] as? String == "T4" }, "a denied origin's notification reached Refrax")
            page.close()
            try await context.engine.removeProfile(profile)
        },

        ConformanceTest(name: "notifications.worker-notifications-are-engine-events") { context in
            let (page, profile, spaceID) = try await notifyPage(context)
            let origin = origin(context)
            context.notifications(granted: [origin])
            let isW = { (title: String) in { (fields: [String: Any]) in (fields["notification"] as? [String: Any])?["title"] as? String == title } }

            _ = try await page.evaluate("worker.then(r => r.showNotification('W1', {body: 'wb', tag: 'w1'})).then(() => true)")
            let shown = try await context.engine.waitForEvent("notificationShown", matching: isW("W1"))
            let isolated = (shown["profile"] as? [String: Any])?["isolated"] as? [String: Any]
            try expectEqual((isolated?["id"] as? String)?.lowercased(), spaceID.lowercased(), "profile")
            let notification = shown["notification"] as? [String: Any] ?? [:]
            try expectEqual(notification["body"] as? String, "wb", "body")
            try expectEqual(notification["origin"] as? String, origin, "origin")
            try expect(!page.events.contains { $0.name == "notificationShown" }, "a worker's notification was reported as the page's")

            try context.engine.command("notificationClicked", ["id": try expectID(notification)])
            try await waitForPageEvent(page, "notificationclick:W1")

            _ = try await page.evaluate("worker.then(r => r.showNotification('W2')).then(() => true)")
            let second = try await context.engine.waitForEvent("notificationShown", matching: isW("W2"))
            try context.engine.command("notificationClosed", ["id": try expectID(second["notification"] as? [String: Any] ?? [:])])
            try await waitForPageEvent(page, "notificationclose:W2")

            _ = try await page.evaluate("worker.then(r => r.showNotification('W3')).then(() => true)")
            let third = try await context.engine.waitForEvent("notificationShown", matching: isW("W3"))
            let thirdID = try expectID(third["notification"] as? [String: Any] ?? [:])
            _ = try await page.evaluate("worker.then(r => r.getNotifications()).then(list => list.forEach(n => n.close())).then(() => true)")
            try await context.engine.waitForEvent("notificationClosed") { $0["id"] as? String == thirdID }
            let remaining = try await page.evaluate("worker.then(r => r.getNotifications()).then(list => list.map(n => n.title))") as? [String]
            try expectEqual(remaining, [], "the worker's notifications after a click, a dismissal and a close")
            page.close()
            try await context.engine.removeProfile(profile)
        },
    ]

    static func expectID(_ notification: [String: Any]) throws -> String {
        guard let id = notification["id"] as? String, !id.isEmpty else {
            throw Failure("notification without an id: \(JSON.canonical(notification))")
        }
        return id
    }
}
