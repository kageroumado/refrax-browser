// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import AppKit

/// Native input through the page's view, the way AppKit delivers it inside Refrax: drags that
/// start a system drag session, selections, and command keys the page leaves unhandled, which
/// must come back to Refrax's menus exactly once.
///
/// These need the runner to be the active app: the page takes input only in the key window.
enum InputTests {
    /// The runner's menu item bound to ⌘J; counts how often it fires.
    @MainActor
    final class MenuProbe: NSObject {
        static let shared = MenuProbe()
        private(set) var fired = 0

        @objc func conformanceKey(_ sender: Any?) {
            fired += 1
        }

        func reset() { fired = 0 }
    }

    /// Where the element `id`'s center is, in the page window's coordinates.
    @MainActor
    static func center(of id: String, in page: TestPage) async throws -> NSPoint {
        let rect = try await page.evaluate("(() => { const r = document.getElementById('\(id)').getBoundingClientRect(); return [r.x + r.width / 2, r.y + r.height / 2]; })()") as? [Double] ?? []
        guard rect.count == 2 else { throw Failure("no element \(id)") }
        return point(x: rect[0], y: rect[1], in: page)
    }

    /// A CSS-pixel point (at zoom 1) in window coordinates.
    @MainActor
    static func point(x: Double, y: Double, in page: TestPage) -> NSPoint {
        let view = page.page.view
        let local = NSPoint(x: x, y: view.isFlipped ? y : view.bounds.height - y)
        return view.convert(local, to: nil)
    }

    @MainActor private static var activationRefused = false

    /// Makes the runner the active app and the page's window key, and focuses the page; the
    /// page only takes input in the key window. macOS grants activation to an app launched from
    /// the frontmost app (cooperative activation), so a runner started from a background shell
    /// skips these tests.
    @MainActor
    static func focus(_ page: TestPage, _ context: Context) async throws {
        guard !activationRefused else {
            throw Skip("the runner was not made the active app; run it from a foreground terminal")
        }
        NSApp.activate()
        page.window.makeKeyAndOrderFront(nil)
        do {
            try await eventually("activation", timeout: 10) { NSApp.isActive && page.window.isKeyWindow ? true : nil }
        } catch {
            activationRefused = true
            throw Skip("the runner was not made the active app; run it from a foreground terminal")
        }
        page.command("focus")
        try await pause(0.3)
    }

    /// Delivers a key event through NSApplication as the window server would, key equivalents
    /// first. Built from a CGEvent, so it carries everything a real keystroke does; posting the
    /// CGEvent instead would need Accessibility permission, without which it is dropped.
    @MainActor
    static func post(_ event: CGEvent?) {
        if let event, let nsEvent = NSEvent(cgEvent: event) {
            NSApp.sendEvent(nsEvent)
        }
    }

    /// A mouse event for the page's window, through NSApplication. (One built from a CGEvent
    /// names no window, and NSApplication drops it.)
    @MainActor
    static func mouse(_ type: NSEvent.EventType, at point: NSPoint, in page: TestPage) {
        let event = NSEvent.mouseEvent(
            with: type,
            location: point,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: page.window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: type == .leftMouseUp ? 0 : 1,
        )!
        NSApp.sendEvent(event)
    }

    /// Presses the left button at `from`, moves to `to` in steps, releases.
    @MainActor
    static func drag(from: NSPoint, to: NSPoint, in page: TestPage) async throws {
        mouse(.leftMouseDown, at: from, in: page)
        try await pause(0.08)
        let steps = 16
        for step in 1...steps {
            let t = Double(step) / Double(steps)
            mouse(.leftMouseDragged, at: NSPoint(x: from.x + (to.x - from.x) * t, y: from.y + (to.y - from.y) * t), in: page)
            try await pause(0.03)
        }
        mouse(.leftMouseUp, at: to, in: page)
        try await pause(0.4)
    }

    @MainActor
    static func commandKey(_ character: String, keyCode: UInt16, in page: TestPage) {
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: keyCode, keyDown: down)
            event?.flags = .maskCommand
            post(event)
        }
    }

    static let all: [ConformanceTest] = [
        ConformanceTest(name: "input.drag-selects-text") { context in
            let page = try await context.page("/html/input")
            try await focus(page, context)
            let rect = try await page.evaluate("(() => { const r = document.getElementById('text').getBoundingClientRect(); return [r.left + 2, r.top + 8, r.right - 4, r.top + 8]; })()") as? [Double] ?? []
            try expect(rect.count == 4, "text geometry")
            try await drag(from: point(x: rect[0], y: rect[1], in: page), to: point(x: rect[2], y: rect[3], in: page), in: page)
            let selected = try await eventuallyAsync("a selection") {
                let text = try await page.evaluate("String(getSelection())") as? String ?? ""
                return text.count > 10 ? text : nil
            }
            try expect(selected.hasPrefix("The quick"), "selected \(selected.prefix(40))")
        },

        ConformanceTest(name: "input.dragging-an-image-starts-a-drag") { context in
            // The browser side builds the drag image in Refrax's process; this crashed when the
            // client never told Chromium its screen scale factors.
            let page = try await context.page("/html/input")
            try await focus(page, context)
            let start = try await center(of: "pic", in: page)
            try await drag(from: start, to: NSPoint(x: start.x + 160, y: start.y - 120), in: page)
            let log = try await eventuallyAsync("dragstart in the page") {
                let log = try await page.evaluate("log") as? [String] ?? []
                return log.contains("dragstart") ? log : nil
            }
            try expect(log.contains("mousedown"), "page log \(log)")
            try expectEqual(try await page.evaluate("document.title") as? String, "input", "the page after the drag")
        },

        ConformanceTest(name: "input.unhandled-command-key-reaches-the-menu-once") { context in
            let page = try await context.page("/html/input")
            try await focus(page, context)
            MenuProbe.shared.reset()
            commandKey("j", keyCode: 38, in: page)
            try await eventually("the ⌘J menu item") { MenuProbe.shared.fired > 0 ? true : nil }
            try await pause(0.5)
            try expectEqual(MenuProbe.shared.fired, 1, "⌘J menu action count")
            let log = try await page.evaluate("log") as? [String] ?? []
            try expect(log.contains("keydown:meta+j"), "the page saw the key first: \(log)")
        },

        ConformanceTest(name: "input.handled-command-key-stays-in-the-page") { context in
            let page = try await context.page("/html/input")
            try await focus(page, context)
            _ = try await page.evaluate("window.__swallow = true")
            MenuProbe.shared.reset()
            commandKey("j", keyCode: 38, in: page)
            try await eventuallyAsync("the page to see ⌘J") {
                (try await page.evaluate("log") as? [String] ?? []).contains("keydown:meta+j") ? true : nil
            }
            try await pause(0.5)
            try expectEqual(MenuProbe.shared.fired, 0, "⌘J menu action count after the page handled it")
        },

        ConformanceTest(name: "input.select-all") { context in
            let page = try await context.page("/html/input")
            try await focus(page, context)
            commandKey("a", keyCode: 0, in: page)
            let selected = try await eventuallyAsync("select all") {
                let text = try await page.evaluate("String(getSelection())") as? String ?? ""
                return text.contains("quick brown fox") && text.contains("a link to drag") ? text : nil
            }
            try expect(!selected.isEmpty, "selection")
        },
    ]
}
