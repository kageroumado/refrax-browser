import AppKit
import SwiftUI

// MARK: - View Modifier

/// A context menu modifier that shows an AppKit `NSMenu` from a SwiftUI view.
///
/// SwiftUI's `.contextMenu` keeps a retain cycle between its `ContextMenuResponder` and the
/// responder's AppKit delegate, so every open leaks the menu and its images. This modifier
/// never creates a SwiftUI context menu: an invisible overlay registers with a per-window
/// right-click monitor, and the monitor pops the menu the builder returns.
///
/// ```swift
/// Text("Right-click me")
///     .refraxContextMenu {
///         NSMenuRenderer.menu(tree)
///     }
/// ```
public struct RefraxNSMenuModifier: ViewModifier {
    private let menuBuilder: () -> NSMenu

    public init(menuBuilder: @escaping () -> NSMenu) {
        self.menuBuilder = menuBuilder
    }

    public func body(content: Content) -> some View {
        content.overlay {
            ContextMenuInterceptor(menuBuilder: menuBuilder)
        }
    }
}

// MARK: - View Extension

public extension View {
    /// Attaches a context menu built as an `NSMenu` when the right-click lands.
    func refraxContextMenu(_ menuBuilder: @escaping () -> NSMenu) -> some View {
        modifier(RefraxNSMenuModifier(menuBuilder: menuBuilder))
    }
}

// MARK: - NSViewRepresentable

/// Invisible NSView overlay that intercepts right-clicks and shows a context menu.
private struct ContextMenuInterceptor: NSViewRepresentable {
    let menuBuilder: () -> NSMenu

    func makeNSView(context _: Context) -> ContextMenuInterceptorNSView {
        let view = ContextMenuInterceptorNSView()
        view.menuBuilder = { menuBuilder() }
        return view
    }

    func updateNSView(_ nsView: ContextMenuInterceptorNSView, context _: Context) {
        nsView.menuBuilder = { menuBuilder() }
    }
}

/// Manages a single right-click event monitor per window.
///
/// This is the cleanest way to add context menus to SwiftUI views because:
/// - The overlay view returns nil from hitTest, so it never interferes with
///   SwiftUI's hover tracking, gestures, or other event handling
/// - The monitor only intercepts right-clicks; all other events flow normally
/// - One monitor per window is minimal overhead
/// - Event number tracking prevents the "replay after menu close" issue
private final class ContextMenuWindowMonitor {
    private static var monitors: [ObjectIdentifier: ContextMenuWindowMonitor] = [:]
    private static var lastProcessedEventNumber: Int = -1

    private weak var window: NSWindow?
    private var interceptors: [Weak<ContextMenuInterceptorNSView>] = []
    /// nonisolated(unsafe) for access in deinit
    private nonisolated(unsafe) var eventMonitor: Any?

    private struct Weak<T: AnyObject> {
        weak var value: T?
        init(_ value: T) {
            self.value = value
        }
    }

    static func register(_ interceptor: ContextMenuInterceptorNSView, for window: NSWindow) {
        let key = ObjectIdentifier(window)
        let monitor = monitors[key] ?? ContextMenuWindowMonitor(window: window)
        monitors[key] = monitor
        monitor.interceptors.removeAll { $0.value == nil }
        monitor.interceptors.append(Weak(interceptor))
    }

    static func unregister(_ interceptor: ContextMenuInterceptorNSView, for window: NSWindow) {
        let key = ObjectIdentifier(window)
        guard let monitor = monitors[key] else { return }
        monitor.interceptors.removeAll { $0.value == nil || $0.value === interceptor }
        if monitor.interceptors.isEmpty {
            monitor.tearDown()
            monitors.removeValue(forKey: key)
        }
    }

    private init(window: NSWindow) {
        self.window = window
        self.eventMonitor = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            self?.handleRightMouseDown(event) ?? event
        }
    }

    private func tearDown() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }

    deinit {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    private func handleRightMouseDown(_ event: NSEvent) -> NSEvent? {
        guard let window,
              event.window === window else {
            return event
        }

        // Skip if we already processed this event (gets replayed after menu closes)
        guard event.eventNumber != Self.lastProcessedEventNumber else {
            return event
        }

        let locationInWindow = event.locationInWindow

        // Find the topmost interceptor whose bounds contain the click and wants to show a menu
        for ref in interceptors.reversed() {
            guard let view = ref.value else { continue }

            // Skip views that aren't actually visible (e.g., a hidden card)
            guard view.isEffectivelyVisible else { continue }

            let locationInView = view.convert(locationInWindow, from: nil)
            guard view.bounds.contains(locationInView) else { continue }

            // Menu builder returns nil to indicate "pass through, don't handle"
            guard let menu = view.menuBuilder?() else { continue }

            Self.lastProcessedEventNumber = event.eventNumber
            NSMenu.popUpContextMenu(menu, with: event, for: view)
            return nil
        }

        return event
    }
}

/// Invisible NSView that registers with the window's event monitor for context menus.
///
/// Returns nil from hitTest so it never interferes with SwiftUI's event handling.
/// The actual right-click interception happens via ContextMenuWindowMonitor.
final class ContextMenuInterceptorNSView: NSView {
    /// Menu builder that returns `nil` to indicate "pass through, don't handle this click".
    var menuBuilder: (() -> NSMenu?)?

    override func hitTest(_: NSPoint) -> NSView? {
        nil // Completely transparent - event monitor handles right-clicks
    }

    /// Whether the view is actually visible on screen.
    ///
    /// Returns false if the view or any ancestor is hidden, has zero size,
    /// or has been removed from the visible hierarchy (e.g., a hidden card).
    var isEffectivelyVisible: Bool {
        guard !isHidden, !isHiddenOrHasHiddenAncestor else { return false }
        guard bounds.width > 0, bounds.height > 0 else { return false }

        // Check if the view has a visible frame in window coordinates
        guard let window else { return false }
        let frameInWindow = convert(bounds, to: nil)
        let windowBounds = window.contentView?.bounds ?? .zero
        return frameInWindow.intersects(windowBounds)
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if let window {
            ContextMenuWindowMonitor.register(self, for: window)
        }
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if let oldWindow = window, oldWindow !== newWindow {
            ContextMenuWindowMonitor.unregister(self, for: oldWindow)
        }
        super.viewWillMove(toWindow: newWindow)
    }
}
