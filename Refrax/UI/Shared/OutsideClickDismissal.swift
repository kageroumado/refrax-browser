import AppKit
import SwiftUI

/// Makes Refrax's overlays close the way a menu does: a click anywhere outside a sheet, a popover
/// or a panel puts it away, and that click does nothing else, so it never also switches a tab or
/// presses what was under it. Esc closes them too.
///
/// Sheets and popovers need nothing: every sheet attached to a window and every transient popover
/// is covered. Alerts and open/save panels (`NSPanel` sheets) and popovers that close themselves
/// (`.applicationDefined`, like the save-password prompt) keep their own rules. A sheet that holds
/// work worth keeping marks itself with ``SwiftUI/View/keepsOpenOnOutsideClick(_:)``. A panel drawn
/// inside a window, like the library drawer, registers itself with ``register(in:frame:dismiss:)``.
@MainActor
final class OutsideClickDismissal: NSObject {
    static let shared = OutsideClickDismissal()

    /// What a click or an Esc does to the overlays above it.
    nonisolated enum Action: Equatable {
        /// The event goes on as usual.
        case pass
        /// A popover closed for this click: the click stops there.
        case swallow
        /// The window's sheet cancels, and the click stops there.
        case cancelSheet
        /// The panel at this index closes, and the event stops there.
        case dismissPanel(Int)
        /// The popover at this index closes, and the Esc stops there.
        case closePopover(Int)
    }

    /// The overlays a mouse-down meets, read from the windows at that moment.
    nonisolated struct Scene: Equatable {
        /// A popover outside the click was showing, or closed for it.
        var popoverAboveClick = false
        /// The clicked window holds a sheet that may close.
        var hasDismissibleSheet = false
        /// Panels open in the clicked window, oldest first, in window coordinates.
        var panelFrames: [CGRect] = []
    }

    /// The overlays an Esc meets.
    nonisolated struct EscapeScene: Equatable {
        /// Text is being composed (an input method's marked text): Esc belongs to it.
        var isComposingText = false
        /// Transient popovers shown from, or as, the key window, oldest first.
        var popoverCount = 0
        /// The key window has a sheet attached; the sheet handles its own Esc.
        var hasAttachedSheet = false
        /// Panels open in the key window, oldest first.
        var panelCount = 0
    }

    /// One layer per click: the newest overlay closes first.
    nonisolated static func mouseDownAction(at point: CGPoint, in scene: Scene) -> Action {
        if scene.popoverAboveClick {
            return .swallow
        }
        if scene.hasDismissibleSheet {
            return .cancelSheet
        }
        guard let top = scene.panelFrames.indices.last else { return .pass }
        return scene.panelFrames[top].contains(point) ? .pass : .dismissPanel(top)
    }

    nonisolated static func escapeAction(in scene: EscapeScene) -> Action {
        if scene.isComposingText {
            return .pass
        }
        if scene.popoverCount > 0 {
            return .closePopover(scene.popoverCount - 1)
        }
        if scene.hasAttachedSheet {
            return .pass
        }
        return scene.panelCount > 0 ? .dismissPanel(scene.panelCount - 1) : .pass
    }

    /// How soon after a mouse-down a popover's own close still counts as caused by it.
    nonisolated static let popoverCloseWindow: TimeInterval = 0.5

    /// Whether a popover that closed at `closedAt` (system uptime) closed for the mouse-down
    /// stamped `eventTime`: transient popovers close while that very event is dispatched.
    nonisolated static func popoverClosed(at closedAt: TimeInterval?, for eventTime: TimeInterval) -> Bool {
        guard let closedAt else { return false }
        return closedAt >= eventTime && closedAt - eventTime < popoverCloseWindow
    }

    // MARK: - Registration

    /// A panel drawn inside a window; ``unregister(_:)`` with its token when it hides.
    private struct Panel {
        let id: UUID
        weak var window: NSWindow?
        let frame: () -> CGRect?
        let dismiss: () -> Void
    }

    private struct ShownPopover {
        weak var popover: NSPopover?

        /// Read live: the popover's window exists only once it is on screen.
        var window: NSWindow? {
            popover?.contentViewController?.view.window
        }
    }

    private var panels: [Panel] = []
    private var popovers: [ShownPopover] = []
    private var lastPopoverClose: (time: TimeInterval, window: NSWindow?)?
    private let sheetsKeptOpen = NSHashTable<NSWindow>.weakObjects()
    /// The button whose mouse-down was spent on a dismissal: its drags and its mouse-up stop too.
    private var swallowedButton: Int?
    private var monitor: Any?

    /// Registers a panel in `window`. `frame` returns its frame in window coordinates (nil while
    /// it isn't laid out); `dismiss` closes it.
    @discardableResult
    func register(in window: NSWindow, frame: @escaping () -> CGRect?, dismiss: @escaping () -> Void) -> UUID {
        let id = UUID()
        panels.append(Panel(id: id, window: window, frame: frame, dismiss: dismiss))
        return id
    }

    func unregister(_ id: UUID?) {
        guard let id else { return }
        panels.removeAll { $0.id == id || $0.window == nil }
    }

    /// Marks the sheet window `window` as kept open (or not) when its parent is clicked.
    func setKeepsOpen(_ keepsOpen: Bool, sheet window: NSWindow) {
        if keepsOpen {
            sheetsKeptOpen.add(window)
        } else {
            sheetsKeptOpen.remove(window)
        }
    }

    // MARK: - Monitoring

    /// Starts watching clicks, Esc and popovers. Call once at launch.
    func install() {
        guard monitor == nil else { return }
        let center = NotificationCenter.default
        center.addObserver(self, selector: #selector(popoverWillShow(_:)), name: NSPopover.willShowNotification, object: nil)
        center.addObserver(self, selector: #selector(popoverWillClose(_:)), name: NSPopover.willCloseNotification, object: nil)
        monitor = NSEvent.addLocalMonitorForEvents(
            matching: [
                .leftMouseDown, .rightMouseDown, .otherMouseDown,
                .leftMouseDragged, .rightMouseDragged, .otherMouseDragged,
                .leftMouseUp, .rightMouseUp, .otherMouseUp,
                .keyDown,
            ],
        ) { event in
            OutsideClickDismissal.shared.handle(event)
        }
    }

    @objc private func popoverWillShow(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover, popover.behavior != .applicationDefined else { return }
        popovers.removeAll { $0.popover == nil || $0.popover === popover }
        popovers.append(ShownPopover(popover: popover))
    }

    @objc private func popoverWillClose(_ notification: Notification) {
        let popover = notification.object as? NSPopover
        guard let index = popovers.firstIndex(where: { $0.popover === popover }) else { return }
        lastPopoverClose = (ProcessInfo.processInfo.systemUptime, popovers[index].window)
        popovers.remove(at: index)
    }

    private func handle(_ event: NSEvent) -> NSEvent? {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            swallowedButton = nil
            return mouseDown(event)
        case .leftMouseDragged, .rightMouseDragged, .otherMouseDragged:
            return swallowedButton == event.buttonNumber ? nil : event
        case .leftMouseUp, .rightMouseUp, .otherMouseUp:
            guard swallowedButton == event.buttonNumber else { return event }
            swallowedButton = nil
            return nil
        case .keyDown:
            return keyDown(event)
        default:
            return event
        }
    }

    private func mouseDown(_ event: NSEvent) -> NSEvent? {
        guard let window = event.window else { return event }
        popovers.removeAll { $0.popover?.isShown != true }
        panels.removeAll { $0.window == nil }

        let closedPopover = lastPopoverClose.flatMap { close in
            close.window !== window && Self.popoverClosed(at: close.time, for: event.timestamp) ? close : nil
        }
        let popoverOutside = popovers.contains { shown in
            guard let popoverWindow = shown.window else { return true }
            return !window.isDescendant(of: popoverWindow)
        }
        let sheet = window.deepestSheet
        let windowPanels = panels.filter { $0.window === window }
        let scene = Scene(
            popoverAboveClick: closedPopover != nil || popoverOutside,
            hasDismissibleSheet: sheet.map { mayCancel($0) } ?? false,
            panelFrames: windowPanels.map { $0.frame() ?? .null },
        )

        switch Self.mouseDownAction(at: event.locationInWindow, in: scene) {
        case .pass, .closePopover:
            return event
        case .swallow:
            lastPopoverClose = nil
            for shown in popovers {
                shown.popover?.performClose(nil)
            }
        case .cancelSheet:
            sheet?.cancelOperation(nil)
        case let .dismissPanel(index):
            windowPanels[index].dismiss()
        }
        swallowedButton = event.buttonNumber
        return nil
    }

    private func keyDown(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == 53,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
              let window = event.window
        else { return event }
        popovers.removeAll { $0.popover?.isShown != true }
        let host = window.parent.flatMap { parent in popovers.contains { $0.window === window } ? parent : nil } ?? window
        let windowPopovers = popovers.filter { $0.window === window || $0.window?.parent === host || $0.window == nil && NSApp.keyWindow === host }
        let windowPanels = panels.filter { $0.window === host }
        let composing = (window.firstResponder as? any NSTextInputClient)?.hasMarkedText() ?? false
        let scene = EscapeScene(
            isComposingText: composing,
            popoverCount: windowPopovers.count,
            hasAttachedSheet: host.attachedSheet != nil,
            panelCount: windowPanels.count,
        )

        switch Self.escapeAction(in: scene) {
        case .pass, .swallow, .cancelSheet:
            return event
        case let .closePopover(index):
            windowPopovers[index].popover?.performClose(nil)
        case let .dismissPanel(index):
            windowPanels[index].dismiss()
        }
        return nil
    }

    /// Sheets that close on an outside click: SwiftUI and plain window sheets. Alerts and
    /// open/save panels are `NSPanel`s and wait for their own buttons.
    private func mayCancel(_ sheet: NSWindow) -> Bool {
        !(sheet is NSPanel) && !sheetsKeptOpen.contains(sheet)
    }
}

private extension NSWindow {
    /// The sheet on top of this window's chain of sheets, if it has one.
    var deepestSheet: NSWindow? {
        var sheet = attachedSheet
        while let next = sheet?.attachedSheet {
            sheet = next
        }
        return sheet
    }

    /// Whether this window is `ancestor` or one of its child windows, at any depth.
    func isDescendant(of ancestor: NSWindow) -> Bool {
        var window: NSWindow? = self
        while let current = window {
            if current === ancestor {
                return true
            }
            window = current.parent
        }
        return false
    }
}

// MARK: - Keeping a sheet open

extension View {
    /// Keeps the sheet this view sits in open when its window is clicked, while `keepsOpen` is
    /// true: for sheets holding work that would be lost, like an edited script. Esc and the
    /// sheet's own buttons still close it.
    func keepsOpenOnOutsideClick(_ keepsOpen: Bool = true) -> some View {
        background(SheetKeepsOpenMarker(keepsOpen: keepsOpen))
    }
}

private struct SheetKeepsOpenMarker: NSViewRepresentable {
    let keepsOpen: Bool

    func makeNSView(context _: Context) -> MarkerView {
        MarkerView()
    }

    func updateNSView(_ view: MarkerView, context _: Context) {
        view.keepsOpen = keepsOpen
    }

    final class MarkerView: NSView {
        var keepsOpen = false {
            didSet { mark() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            mark()
        }

        override func hitTest(_: NSPoint) -> NSView? {
            nil
        }

        private func mark() {
            guard let window else { return }
            OutsideClickDismissal.shared.setKeepsOpen(keepsOpen, sheet: window)
        }
    }
}
