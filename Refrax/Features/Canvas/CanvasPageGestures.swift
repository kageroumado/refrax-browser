import AppKit

/// Turns input on the page into the reveal of the islands and the floating cards.
///
/// Watches the window's events ahead of the page, whichever engine renders it:
///
/// - **The reveal key** held alone shows adjacent pages immediately; clicks keep those
///   destinations available while the key is down. Releasing it leaves pinned previews
///   visible.
/// - **The reveal key + scroll** steps between the islands' rows; over an island or the
///   Control Island the scroll is theirs. Either way it never ends the hold.
@MainActor
final class CanvasPageGestures {
    private enum Constants {
        static let escapeKeyCode: UInt16 = 53
        static let returnKeyCode: UInt16 = 36
        static let tabKeyCode: UInt16 = 48
    }

    private weak var window: NSWindow?
    private unowned let canvas: TabCanvasManager
    private let floatingEligible: () -> Bool
    private let floatingContains: (CGPoint) -> Bool
    private let floatingHasKeyboardFocus: () -> Bool
    private var resignObserver: (any NSObjectProtocol)?
    private var monitor: Any?

    /// Directional keys step to the adjacent chip.
    var islands: IslandController?
    /// Scroll events with the reveal key down step between chips.
    var islandInput: IslandInput?

    /// - Parameters:
    ///   - floatingEligible: Whether the window's state lets the floating layer reveal.
    ///   - floatingContains: Whether a point in window coordinates is over the floating
    ///     layer's controls, cards, or docked columns.
    ///   - floatingHasKeyboardFocus: Whether a floating card's page is the first responder.
    init(window: NSWindow, canvas: TabCanvasManager, floatingEligible: @escaping () -> Bool, floatingContains: @escaping (CGPoint) -> Bool, floatingHasKeyboardFocus: @escaping () -> Bool) {
        self.window = window
        self.canvas = canvas
        self.floatingEligible = floatingEligible
        self.floatingContains = floatingContains
        self.floatingHasKeyboardFocus = floatingHasKeyboardFocus
        self.resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.interruptControl()
                self?.canvas.dismissFloatingTabs()
            }
        }
        self.monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .flagsChanged, .keyDown, .keyUp, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseDragged, .rightMouseUp, .otherMouseDown, .otherMouseDragged, .otherMouseUp]) { [weak self] event in
            guard let self else { return event }
            return handle(event)
        }
    }

    isolated deinit {
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Returns the event to deliver, or nil when the floating layer takes it.
    func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else { return event }
        // With the reveal key down, a scroll anywhere over the page steps between chips; over
        // an island or the Control Island it is theirs. Either way it never ends the hold.
        if event.type == .scrollWheel, let islandInput {
            let keyHeld = FloatingRevealKey.current.matchesHold(event.modifierFlags.intersection([.control, .option, .command]))
            if islandInput.route(
                event,
                canStart: floatingEligible() && !floatingContains(event.locationInWindow),
            ) {
                return nil
            }
            if keyHeld {
                return event
            }
        }
        if [
            .leftMouseDown,
            .leftMouseUp,
            .leftMouseDragged,
            .rightMouseDown,
            .rightMouseUp,
            .rightMouseDragged,
            .otherMouseDown,
            .otherMouseUp,
            .otherMouseDragged,
            .scrollWheel,
        ].contains(event.type), floatingContains(event.locationInWindow) {
            return canvas.floatingVisibility.isHeld ? FloatingPreviewInput.removingRevealModifier(from: event) : event
        }
        switch event.type {
        case .flagsChanged: return handleFlags(event)
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp: return handleMouse(event)
        case .keyDown: return handleKey(event)
        case .keyUp:
            return floatingHasKeyboardFocus() && canvas.floatingVisibility.isHeld
                ? FloatingPreviewInput.removingRevealModifier(from: event) : event
        default:
            interruptControl()
            return event
        }
    }

    // MARK: - Mouse and Keys

    private func handleMouse(_ event: NSEvent) -> NSEvent? {
        if canvas.isMomentaryNavigation {
            return FloatingPreviewInput.removingRevealModifier(from: event)
        }
        if event.type == .leftMouseDown {
            interruptControl()
        }
        return event
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if FloatingRevealKey.current == .command, event.modifierFlags.contains(.command) {
            interruptControl()
            return event
        }
        if event.keyCode == Constants.tabKeyCode, event.modifierFlags.contains(.control) {
            interruptControl()
            canvas.dismissFloatingTabs()
            return event
        }
        if canvas.floatingVisibility.isRevealed, event.keyCode == Constants.escapeKeyCode, !floatingHasKeyboardFocus() {
            interruptControl()
            canvas.dismissFloatingTabs()
            return nil
        }
        if floatingHasKeyboardFocus(), canvas.floatingVisibility.isHeld {
            return FloatingPreviewInput.removingRevealModifier(from: event)
        }
        if canvas.floatingVisibility.isRevealed, !floatingHasKeyboardFocus() {
            let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control]).subtracting(FloatingRevealKey.current.flag)
            if modifiers.isEmpty, let islands,
               let direction = TableDirection.allCases.first(where: { $0.keyCode == event.keyCode }) {
                islands.step(direction)
                return nil
            }
            if modifiers.isEmpty, event.keyCode == Constants.returnKeyCode {
                canvas.openFocusedFloatingTab()
                return nil
            }
        }
        interruptControl()
        return event
    }

    // MARK: - The Reveal Key

    private func handleFlags(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let revealKey = FloatingRevealKey.current

        if canvas.floatingVisibility.isHeld, modifiers.contains(revealKey.flag), floatingHasKeyboardFocus() {
            return event
        }
        if revealKey.matchesHold(modifiers) {
            guard !canvas.floatingVisibility.isHeld else { return event }
            if floatingEligible() {
                canvas.revealFloatingTabs()
            }
            return event
        }

        // The reveal key went up, or another modifier joined it.
        canvas.releaseFloatingTabs()
        return event
    }

    /// Other input while the reveal key is down makes it part of a shortcut or a modified click.
    private func interruptControl() {
        islandInput?.interrupt()
        canvas.releaseFloatingTabs()
    }
}
