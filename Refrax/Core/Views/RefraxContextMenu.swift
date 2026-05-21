import AppKit
import SwiftUI

// MARK: - View Modifier

/// A context menu modifier that uses AppKit's NSMenu directly, avoiding SwiftUI's
/// ContextMenuResponder retain cycle bug.
///
/// This is a drop-in replacement for `.contextMenu { }` that doesn't leak memory.
///
/// ## Usage
///
/// Basic usage with NSMenu:
/// ```swift
/// Text("Right-click me")
///     .refraxContextMenu {
///         let menu = NSMenu()
///         menu.addItem(withTitle: "Copy", action: #selector(copy(_:)), keyEquivalent: "c")
///         return menu
///     }
/// ```
///
/// Using the result builder for cleaner syntax:
/// ```swift
/// Text("Right-click me")
///     .refraxContextMenu {
///         MenuItem("Rename") { onRename() }
///         MenuItem("Get Info") { onGetInfo() }
///         MenuDivider()
///         MenuItem("Pin", systemImage: "pin.fill") { togglePin() }
///             .disabled(isLocked)
///         SubMenu("Move to Group") {
///             for group in groups {
///                 MenuItem(group.name) { moveToGroup(group) }
///             }
///         }
///     }
/// ```
///
/// ## Why This Exists
///
/// SwiftUI's `.contextMenu` modifier has a retain cycle in its internal
/// `ContextMenuResponder` class where the delegate holds a strong reference
/// back to the responder. Each context menu invocation leaks ~22KB.
///
/// This implementation uses NSMenu directly with proper weak references,
/// avoiding the leak entirely.
public struct RefraxContextMenuModifier<MenuContent: MenuItemConvertible>: ViewModifier {
    private let menuBuilder: () -> MenuContent

    public init(@MenuBuilder menuBuilder: @escaping () -> MenuContent) {
        self.menuBuilder = menuBuilder
    }

    public func body(content: Content) -> some View {
        content.overlay {
            ContextMenuInterceptor(menuBuilder: { menuBuilder().asNSMenu() })
        }
    }
}

/// Alternative modifier that takes an NSMenu directly.
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
    /// Attaches a context menu using AppKit's NSMenu, avoiding SwiftUI's memory leak.
    ///
    /// Use the result builder syntax for clean, declarative menu construction:
    /// ```swift
    /// .refraxContextMenu {
    ///     MenuItem("Action") { doAction() }
    ///     MenuDivider()
    ///     SubMenu("More") {
    ///         MenuItem("Sub-action") { doSubAction() }
    ///     }
    /// }
    /// ```
    func refraxContextMenu(
        @MenuBuilder _ menuBuilder: @escaping () -> some MenuItemConvertible,
    ) -> some View {
        modifier(RefraxContextMenuModifier(menuBuilder: menuBuilder))
    }

    /// Attaches a context menu using a raw NSMenu.
    ///
    /// Use this when you need full control over menu construction:
    /// ```swift
    /// .refraxContextMenu {
    ///     let menu = NSMenu()
    ///     menu.addItem(withTitle: "Action", action: #selector(doIt), keyEquivalent: "")
    ///     return menu
    /// }
    /// ```
    func refraxContextMenu(_ menuBuilder: @escaping () -> NSMenu) -> some View {
        modifier(RefraxNSMenuModifier(menuBuilder: menuBuilder))
    }

    /// Attaches a context menu that only appears when clicking on empty areas.
    ///
    /// Use this for scroll views or containers where you want a context menu on
    /// the background but not on content items (which may have their own menus).
    ///
    /// The menu builder is only called when the click hits empty space, not
    /// actual SwiftUI content. This uses view hierarchy depth as a heuristic.
    ///
    /// ```swift
    /// ScrollView {
    ///     content
    /// }
    /// .refraxEmptyAreaContextMenu {
    ///     buildBackgroundMenu()
    /// }
    /// ```
    func refraxEmptyAreaContextMenu(_ menuBuilder: @escaping () -> NSMenu) -> some View {
        overlay {
            EmptyAreaContextMenuInterceptor(menuBuilder: menuBuilder)
        }
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

/// Invisible NSView overlay for empty area context menus.
///
/// Only shows the menu when clicking on empty space (not SwiftUI content).
/// Uses view hierarchy depth as a heuristic to distinguish content from empty space.
struct EmptyAreaContextMenuInterceptor: NSViewRepresentable {
    let menuBuilder: () -> NSMenu

    func makeNSView(context _: Context) -> ContextMenuInterceptorNSView {
        let view = ContextMenuInterceptorNSView()
        view.menuBuilder = { [weak view] in
            guard let view else { return nil }
            return view.shouldShowEmptyAreaMenu() ? menuBuilder() : nil
        }
        return view
    }

    func updateNSView(_ nsView: ContextMenuInterceptorNSView, context _: Context) {
        nsView.menuBuilder = { [weak nsView] in
            guard let nsView else { return nil }
            return nsView.shouldShowEmptyAreaMenu() ? menuBuilder() : nil
        }
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

            // Skip views that aren't actually visible (e.g., sidebar collapsed)
            guard view.isEffectivelyVisible else { continue }

            let locationInView = view.convert(locationInWindow, from: nil)
            guard view.bounds.contains(locationInView) else { continue }

            // Store location for conditional menu builders (empty area detection)
            view.lastClickLocation = locationInWindow

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

    /// Location of the last right-click in window coordinates.
    /// Set by the monitor before calling menuBuilder, used for empty area detection.
    var lastClickLocation: NSPoint = .zero

    override func hitTest(_: NSPoint) -> NSView? {
        nil // Completely transparent - event monitor handles right-clicks
    }

    /// Whether the view is actually visible on screen.
    ///
    /// Returns false if the view or any ancestor is hidden, has zero size,
    /// or has been removed from the visible hierarchy (e.g., sidebar collapsed).
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

    // MARK: - Empty Area Detection

    /// Checks if the last click should trigger an empty area context menu.
    ///
    /// Returns `true` if the click hit empty space (scroll view background),
    /// `false` if it hit actual SwiftUI content that may have its own context menu.
    func shouldShowEmptyAreaMenu() -> Bool {
        guard let contentView = window?.contentView else { return false }

        // Check what view the click actually hit
        guard let targetView = contentView.hitTest(lastClickLocation) else {
            return true // No view hit = empty area
        }

        return !isSwiftUIContentView(targetView)
    }

    /// Determines if a view is actual SwiftUI content (vs empty scroll area).
    ///
    /// SwiftUI views are hosted in NSHostingView. When clicking on actual content
    /// (tabs, buttons, etc.), the hit test returns a view deep in the hierarchy.
    /// When clicking on empty space (scroll view background), we hit a view
    /// close to the hosting view root.
    ///
    /// This uses view hierarchy depth as a heuristic: content is deep, empty space is shallow.
    private func isSwiftUIContentView(_ view: NSView) -> Bool {
        var current: NSView? = view
        var depth = 0

        while let v = current {
            let className = String(describing: type(of: v))

            // Check if we've reached a hosting view (SwiftUI's bridge to AppKit)
            if className.contains("Hosting") {
                // If we traversed through multiple views to get here,
                // we started on actual SwiftUI content that may have its own context menu.
                // Empty scroll areas are shallow (depth 0-2), content is deeper.
                return depth >= 3
            }

            // AppKit view with explicit menu - let it handle the event
            if v.menu != nil {
                return true
            }

            depth += 1
            current = v.superview
        }

        return false
    }
}

// MARK: - Menu Result Builder

/// Result builder for declarative NSMenu construction.
@resultBuilder
public struct MenuBuilder {
    public static func buildBlock(_ components: any MenuItemConvertible...) -> [any MenuItemConvertible] {
        components
    }

    public static func buildOptional(_ component: [any MenuItemConvertible]?) -> [any MenuItemConvertible] {
        component ?? []
    }

    public static func buildEither(first component: [any MenuItemConvertible]) -> [any MenuItemConvertible] {
        component
    }

    public static func buildEither(second component: [any MenuItemConvertible]) -> [any MenuItemConvertible] {
        component
    }

    public static func buildArray(_ components: [[any MenuItemConvertible]]) -> [any MenuItemConvertible] {
        components.flatMap(\.self)
    }

    public static func buildExpression(_ expression: any MenuItemConvertible) -> [any MenuItemConvertible] {
        [expression]
    }

    public static func buildExpression(_ expression: [any MenuItemConvertible]) -> [any MenuItemConvertible] {
        expression
    }
}

// MARK: - Menu Item Protocol

/// Protocol for types that can be converted to NSMenu items.
public protocol MenuItemConvertible {
    func asMenuItems() -> [NSMenuItem]
}

public extension MenuItemConvertible {
    /// Converts to a complete NSMenu.
    func asNSMenu() -> NSMenu {
        let menu = NSMenu()
        for item in asMenuItems() {
            menu.addItem(item)
        }
        return menu
    }
}

extension [any MenuItemConvertible]: MenuItemConvertible {
    public func asMenuItems() -> [NSMenuItem] {
        flatMap { $0.asMenuItems() }
    }
}

// MARK: - Menu Items

/// A menu item with a title, optional image, and action closure.
public struct MenuItem: MenuItemConvertible {
    private let title: String
    private let systemImage: String?
    private let image: NSImage?
    private let keyEquivalent: String
    private let action: @MainActor () -> Void
    private var isDisabled: Bool = false
    private var accessibilityID: String?

    /// Creates a menu item with a title and action.
    public init(
        _ title: String,
        systemImage: String? = nil,
        keyEquivalent: String = "",
        action: @escaping @MainActor () -> Void,
    ) {
        self.title = title
        self.systemImage = systemImage
        self.image = nil
        self.keyEquivalent = keyEquivalent
        self.action = action
    }

    /// Creates a menu item with a title, custom image, and action.
    public init(
        _ title: String,
        image: NSImage?,
        keyEquivalent: String = "",
        action: @escaping @MainActor () -> Void,
    ) {
        self.title = title
        self.systemImage = nil
        self.image = image
        self.keyEquivalent = keyEquivalent
        self.action = action
    }

    /// Disables the menu item.
    public func disabled(_ disabled: Bool = true) -> MenuItem {
        var copy = self
        copy.isDisabled = disabled
        return copy
    }

    /// Sets an accessibility identifier for UI automation.
    public func accessibilityIdentifier(_ identifier: String) -> MenuItem {
        var copy = self
        copy.accessibilityID = identifier
        return copy
    }

    public func asMenuItems() -> [NSMenuItem] {
        let item = ClosureMenuItem.create(title: title, closure: action)
        item.keyEquivalent = keyEquivalent
        item.isEnabled = !isDisabled

        if let systemImage {
            item.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        } else if let image {
            item.image = image
        }

        // Set accessibility identifier for UI automation
        if let accessibilityID {
            item.setAccessibilityIdentifier(accessibilityID)
        }

        return [item]
    }
}

/// A menu separator.
public struct MenuDivider: MenuItemConvertible {
    public init() {}

    public func asMenuItems() -> [NSMenuItem] {
        [.separator()]
    }
}

/// A submenu containing other items.
public struct SubMenu: MenuItemConvertible {
    private let title: String
    private let systemImage: String?
    private let items: [any MenuItemConvertible]
    private var accessibilityID: String?

    public init(
        _ title: String,
        systemImage: String? = nil,
        @MenuBuilder items: () -> [any MenuItemConvertible],
    ) {
        self.title = title
        self.systemImage = systemImage
        self.items = items()
    }

    /// Sets an accessibility identifier for UI automation.
    public func accessibilityIdentifier(_ identifier: String) -> SubMenu {
        var copy = self
        copy.accessibilityID = identifier
        return copy
    }

    public func asMenuItems() -> [NSMenuItem] {
        let submenu = NSMenu(title: title)
        for item in items.flatMap({ $0.asMenuItems() }) {
            submenu.addItem(item)
        }

        let menuItem = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        menuItem.submenu = submenu

        if let systemImage {
            menuItem.image = NSImage(systemSymbolName: systemImage, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        }

        // Set accessibility identifier for UI automation
        if let accessibilityID {
            menuItem.setAccessibilityIdentifier(accessibilityID)
        }

        return [menuItem]
    }
}

/// Conditionally includes menu items.
public struct MenuGroup: MenuItemConvertible {
    private let items: [any MenuItemConvertible]

    public init(@MenuBuilder items: () -> [any MenuItemConvertible]) {
        self.items = items()
    }

    public func asMenuItems() -> [NSMenuItem] {
        items.flatMap { $0.asMenuItems() }
    }
}

// MARK: - Closure-Based Menu Item

/// Creates an NSMenuItem that executes a closure when selected.
///
/// Uses a separate target object to avoid NSMenuItem subclassing issues
/// with Swift 6 concurrency.
private enum ClosureMenuItem {
    /// Creates a menu item with the given title that executes the closure when selected.
    static func create(title: String, closure: @escaping @MainActor () -> Void) -> NSMenuItem {
        let target = ActionTarget(closure: closure)
        let item = NSMenuItem(
            title: title,
            action: #selector(ActionTarget.performAction),
            keyEquivalent: "",
        )
        item.target = target
        // Store the target in representedObject to prevent deallocation
        item.representedObject = target
        return item
    }
}

/// Target object that holds and executes the action closure.
///
/// Stored in NSMenuItem.representedObject to maintain lifecycle.
/// Must be nonisolated to work with AppKit's target/action pattern.
private final nonisolated class ActionTarget: NSObject, Sendable {
    private let closure: @MainActor () -> Void

    init(closure: @escaping @MainActor () -> Void) {
        self.closure = closure
        super.init()
    }

    @objc
    func performAction() {
        MainActor.assumeIsolated {
            closure()
        }
    }
}
