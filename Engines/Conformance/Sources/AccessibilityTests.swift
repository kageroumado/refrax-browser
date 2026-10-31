// Copyright 2026 Refrax. Use of this source code is governed by the license in the repository root.

import AppKit
import ApplicationServices

/// The page's accessibility tree is part of its view (CONTRACT.md §4.8): an assistive technology
/// reading the window reaches the page's content. Read here as VoiceOver does, through the
/// AXUIElement API, which needs this process to be trusted for accessibility; the view's own
/// children are checked either way.
enum AccessibilityTests {
    static func attribute(_ element: AXUIElement, _ name: String) -> AnyObject? {
        var value: AnyObject?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }

    /// Texts and roles under `element`, breadth-first, up to `limit` elements.
    static func walk(_ element: AXUIElement, limit: Int = 400) -> (roles: Set<String>, texts: [String]) {
        var queue = [element]
        var roles = Set<String>()
        var texts: [String] = []
        var seen = 0
        while !queue.isEmpty, seen < limit {
            let current = queue.removeFirst()
            seen += 1
            if let role = attribute(current, kAXRoleAttribute) as? String { roles.insert(role) }
            for name in [kAXValueAttribute, kAXTitleAttribute, kAXDescriptionAttribute] {
                if let text = attribute(current, name) as? String, !text.isEmpty { texts.append(text) }
            }
            if let children = attribute(current, kAXChildrenAttribute) as? [AXUIElement] {
                queue.append(contentsOf: children)
            }
        }
        return (roles, texts)
    }

    static let all: [ConformanceTest] = [
        ConformanceTest(name: "accessibility.page-tree-in-the-view", timeout: 60) { context in
            let page = try await context.page("/html/basic")
            defer { page.close() }
            let view = page.page.view
            // Asking is what turns the engine's tree on; the remote root arrives shortly after.
            let children = try await eventually("the page's root element under its view", timeout: 15, interval: .milliseconds(200)) { () -> [Any]? in
                let children = view.accessibilityChildren() ?? []
                return children.isEmpty ? nil : children
            }
            context.note("view children: \(children.map { String(describing: type(of: $0)) })")
            guard AXIsProcessTrusted() else {
                context.note("not trusted for accessibility: the AXUIElement walk is skipped")
                return
            }
            let app = AXUIElementCreateApplication(getpid())
            let found = try await eventually("the page's text in the window's accessibility tree", timeout: 20, interval: .milliseconds(250)) { () -> (Set<String>, [String])? in
                guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement],
                      let window = windows.first(where: { (attribute($0, kAXTitleAttribute) as? String) == page.window.title })
                else { return nil }
                let (roles, texts) = walk(window)
                return texts.contains(where: { $0.contains("basic page") }) ? (roles, texts) : nil
            }
            try expect(found.0.contains("AXWebArea"), "a web area in the tree; roles \(found.0.sorted())")
        },
    ]
}
