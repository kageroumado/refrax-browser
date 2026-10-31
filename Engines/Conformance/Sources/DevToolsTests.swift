// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import AppKit

/// The `devTools` command (CONTRACT.md §4.2) and `devToolsChanged` (§4.1). An out-of-process
/// engine shows its developer tools in a window its client opens in this process, which the
/// test finds among the app's windows.
enum DevToolsTests {
    @MainActor
    static func devToolsWindow() -> NSWindow? {
        NSApp.windows.first { $0.isVisible && $0.title.hasPrefix("Developer Tools") }
    }

    static let all: [ConformanceTest] = [
        ConformanceTest(name: "devtools.open-and-close", timeout: 60) { context in
            try context.engine.require("devTools")
            let page = try await context.page("/html/basic")
            defer { page.close() }
            var mark = page.events.count
            page.command("devTools", ["command": ["show": [:]]])
            let shown = try await page.waitForEvent("devToolsChanged", after: mark)
            try expectEqual(shown["isShown"] as? Bool, true, "devToolsChanged after show")
            let window = try await eventually("the DevTools window", timeout: 10) { devToolsWindow() }
            // The frontend's views arrive in the window once the host has built them.
            try await eventually("the frontend's views in the window", timeout: 20) {
                (window.contentView?.subviews.isEmpty == false) ? true : nil
            }
            mark = page.events.count
            page.command("devTools", ["command": ["showConsole": [:]]])
            try await pause(0.5)
            try expect(!page.events[mark...].contains { $0.name == "devToolsChanged" }, "showConsole on open DevTools reports nothing new")
            mark = page.events.count
            page.command("devTools", ["command": ["hide": [:]]])
            let hidden = try await page.waitForEvent("devToolsChanged", after: mark)
            try expectEqual(hidden["isShown"] as? Bool, false, "devToolsChanged after hide")
            try await eventually("the DevTools window to close", timeout: 10) { devToolsWindow() == nil ? true : nil }
        },

        ConformanceTest(name: "devtools.closing-the-window-reports-hidden", timeout: 60) { context in
            try context.engine.require("devTools")
            let page = try await context.page("/html/basic")
            defer { page.close() }
            var mark = page.events.count
            page.command("devTools", ["command": ["toggleElementSelection": [:]]])
            try await page.waitForEvent("devToolsChanged", after: mark) { $0["isShown"] as? Bool == true }
            let window = try await eventually("the DevTools window", timeout: 10) { devToolsWindow() }
            mark = page.events.count
            window.performClose(nil)
            try await page.waitForEvent("devToolsChanged", after: mark) { $0["isShown"] as? Bool == false }
            try await eventually("the DevTools window to close", timeout: 10) { devToolsWindow() == nil ? true : nil }
        },

        ConformanceTest(name: "devtools.closing-the-page-closes-them", timeout: 60) { context in
            try context.engine.require("devTools")
            let page = try await context.page("/html/basic")
            let mark = page.events.count
            page.command("devTools", ["command": ["show": [:]]])
            try await page.waitForEvent("devToolsChanged", after: mark) { $0["isShown"] as? Bool == true }
            _ = try await eventually("the DevTools window", timeout: 10) { devToolsWindow() }
            page.close()
            try await eventually("the DevTools window to close with its page", timeout: 10) { devToolsWindow() == nil ? true : nil }
        },
    ]
}
