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
/// - **A scroll on the Control Island's page icon** steps the same way with no key, and
///   holds the islands revealed until the pointer leaves the icon.
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
                // Key going to one of the window's own children (an island, a card, the
                // lens) is a click on the browser, which ends nothing.
                guard let self, NSApp.keyWindow?.parent !== self.window else { return }
                self.interruptControl()
                self.canvas.dismissFloatingTabs()
            }
        }
        self.monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .mouseMoved, .mouseExited, .flagsChanged, .keyDown, .keyUp, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseDragged, .rightMouseUp, .otherMouseDown, .otherMouseDragged, .otherMouseUp]) { [weak self] event in
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
        // The modifiers reach the key window; while that is a card or the lens,
        // the browser window's hold still follows them.
        if event.type == .flagsChanged, event.window !== window, event.window == nil || event.window?.parent === window {
            return handleFlags(event)
        }
        // The pointer leaving the page icon ends the hold a scroll on it keeps.
        if event.type == .mouseMoved || event.type == .mouseExited {
            if event.window === window, let islandInput, islandInput.holdsOnTabIcon {
                islandInput.pointerMoved(to: contentPoint(event.locationInWindow), keyHeld: revealKeyHeld(event))
            }
            return event
        }
        guard event.window === window else { return event }
        // With the reveal key down, a scroll anywhere over the page steps between chips, and
        // a scroll on the page icon does with or without it; over an island or the rest of the
        // Control Island it is theirs. Either way it never ends the hold.
        if event.type == .scrollWheel, let islandInput {
            if islandInput.route(
                event,
                at: contentPoint(event.locationInWindow),
                eligible: floatingEligible(),
                overControls: floatingContains(event.locationInWindow),
            ) {
                return nil
            }
            if revealKeyHeld(event) {
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
        if event.window?.firstResponder is NSTextView {
            return event
        }
        if FloatingRevealKey.current == .command, event.modifierFlags.contains(.command) {
            interruptControl()
            return event
        }
        if event.keyCode == Constants.tabKeyCode, event.modifierFlags.contains(.control) {
            interruptControl()
            canvas.dismissFloatingTabs()
            return event
        }
        // Latched open with the reveal key up, the islands have the keyboard: the arrows choose
        // a row, Return opens it, Delete closes it, Space previews it, typing finds it by
        // title, and Escape steps back. Held, the arrows move between pages.
        if canvas.floatingVisibility.isLatched, !canvas.floatingVisibility.isHeld, !floatingHasKeyboardFocus(), let islands {
            let flags = event.modifierFlags
            if let key = IslandKey(
                keyCode: event.keyCode, characters: event.characters,
                command: flags.contains(.command), control: flags.contains(.control), option: flags.contains(.option),
            ), islands.handleKey(key) {
                return nil
            }
        }
        if canvas.floatingVisibility.isRevealed, event.keyCode == Constants.escapeKeyCode, !floatingHasKeyboardFocus() {
            islands?.endKeyboardBrowsing()
            islands?.cancelRowDrag()
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

    private func revealKeyHeld(_ event: NSEvent) -> Bool {
        FloatingRevealKey.current.matchesHold(event.modifierFlags.intersection([.control, .option, .command]))
    }

    /// A point in the window, in the content view's coordinates with the origin at the top
    /// left, as the rail and the islands report their frames.
    private func contentPoint(_ locationInWindow: CGPoint) -> CGPoint {
        guard let content = window?.contentView else { return locationInWindow }
        let local = content.convert(locationInWindow, from: nil)
        return CGPoint(x: local.x, y: content.isFlipped ? local.y : content.bounds.height - local.y)
    }
}
