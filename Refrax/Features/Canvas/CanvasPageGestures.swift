import AppKit

/// Turns gestures on the page into ways onto the tab canvas.
///
/// Watches the window's events ahead of the page, whichever engine renders it:
///
/// - **Pinch in** on a page at its normal size opens the canvas under the fingers, the
///   page shrinking exactly as much as they close. Releasing below
///   ``Constants/commitScale``, or with a flick, completes the opening; anything less goes
///   back to the page. Every other pinch (zooming the page in, or a page already zoomed)
///   reaches the page untouched. The direction is only known once the fingers move, so
///   the gesture's `began` event is held back until then and handed to the page when the
///   pinch turns out to be its own.
/// - **⌃** held alone shows adjacent pages immediately; clicks keep those destinations
///   available while the key is down. Releasing it leaves pinned previews visible.
/// - **The scroll key + scroll** slides the table under the window: the events go to the
///   table's scroll view instead of the page, for the whole gesture and its momentum.
@MainActor
final class CanvasPageGestures {
    private enum PinchState {
        case idle
        case undecided(began: NSEvent)
        case passing
        case opening(scale: CGFloat, trend: CGFloat)
    }

    private enum Constants {
        /// A pinch released at or below this scale completes the opening.
        static let commitScale: CGFloat = 0.96
        /// A pinch still closing at least this fast when released completes the opening
        /// from anywhere.
        static let flickTrend: CGFloat = -0.01
        /// Weight of the newest step in the running average of the pinch's direction.
        static let trendWeight: CGFloat = 0.4
        /// Smallest scale tracked; the opening ends long before.
        static let minimumScale: CGFloat = 0.05
        /// Longest press of ⌃ that counts as a tap.
        static let tapDuration: TimeInterval = 0.25
        /// Longest gap between two taps of a double tap.
        static let doubleTapInterval: TimeInterval = 0.35
        /// Pointer travel that turns a click in move mode into a drag.
        static let dragThreshold: CGFloat = 3
        static let escapeKeyCode: UInt16 = 53
    }

    private weak var window: NSWindow?
    private unowned let canvas: TabCanvasManager
    private let floatingEligible: () -> Bool
    private let floatingContains: (CGPoint) -> Bool
    private let floatingControlsContain: (CGPoint) -> Bool
    private let floatingHasKeyboardFocus: () -> Bool
    private var resignObserver: (any NSObjectProtocol)?
    private let isEligible: (CGPoint) -> Bool
    private var pinch = PinchState.idle
    private var monitor: Any?

    /// The desk is up in move mode, until a tap of ⌃, Esc, or a click settles it.
    private var isMoveMode = false
    /// Directional keys step to the adjacent chip.
    var islands: IslandController?
    /// Scroll events with the reveal key down step between chips.
    var islandInput: IslandInput?
    /// When ⌃ last went down with no other input since, for telling taps from holds.
    private var controlDownAt: Date?
    /// When the last tap of ⌃ ended, for telling a double tap.
    private var lastControlTap: Date?
    /// How far the pointer has moved since the mouse went down in move mode.
    private var dragTravel: CGFloat = 0

    /// - Parameter isEligible: Whether a gesture with the pointer at this point (window
    ///   coordinates) may reach the canvas: the window's state allows it and the point is
    ///   over the page.
    init(window: NSWindow, canvas: TabCanvasManager, floatingEligible: @escaping () -> Bool, floatingContains: @escaping (CGPoint) -> Bool, floatingControlsContain: @escaping (CGPoint) -> Bool, floatingHasKeyboardFocus: @escaping () -> Bool, isEligible: @escaping (CGPoint) -> Bool) {
        self.window = window
        self.canvas = canvas
        self.isEligible = isEligible
        self.floatingEligible = floatingEligible
        self.floatingContains = floatingContains
        self.floatingControlsContain = floatingControlsContain
        self.floatingHasKeyboardFocus = floatingHasKeyboardFocus
        self.resignObserver = NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.interruptControl()
                self?.canvas.dismissFloatingTabs()
            }
        }
        self.monitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel, .flagsChanged, .keyDown, .keyUp, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .rightMouseDragged, .rightMouseUp, .otherMouseDown, .otherMouseDragged, .otherMouseUp]) { [weak self] event in
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

    /// Returns the event to deliver, or nil when the canvas takes it.
    func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else { return event }
        if !canvas.isPanningFromPage {
            isMoveMode = false
        }
        if event.type == .scrollWheel, canvas.isPanningFromPage {
            return handleScroll(event)
        }
        // With the reveal key down, a scroll anywhere over the page steps between chips; over
        // an island or the Control Island it is theirs. Either way it never ends the hold.
        if event.type == .scrollWheel, let islandInput, !canvas.isActive {
            let keyHeld = FloatingRevealKey.current.matchesHold(event.modifierFlags.intersection([.control, .option, .command]))
            if islandInput.route(event, canStart: floatingEligible() && !canvas.floatingVisibility.isManipulating
                && !floatingContains(event.locationInWindow)) {
                controlDownAt = nil
                lastControlTap = nil
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
            .magnify,
        ].contains(event.type), floatingContains(event.locationInWindow) {
            controlDownAt = nil
            lastControlTap = nil
            return canvas.floatingVisibility.isHeld ? FloatingPreviewInput.removingRevealModifier(from: event) : event
        }
        switch event.type {
        case .magnify: return handlePinch(event)
        case .scrollWheel: return handleScroll(event)
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

    // MARK: - Move Mode

    private func handleMouse(_ event: NSEvent) -> NSEvent? {
        guard canvas.isPanningFromPage else {
            if canvas.isMomentaryNavigation {
                if event.type == .leftMouseDown {
                    controlDownAt = nil
                    lastControlTap = nil
                }
                return FloatingPreviewInput.removingRevealModifier(from: event)
            }
            if event.type == .leftMouseDown {
                interruptControl()
            }
            return event
        }
        switch event.type {
        case .leftMouseDown:
            dragTravel = 0
        case .leftMouseDragged:
            dragTravel += hypot(event.deltaX, event.deltaY)
            canvas.pan(by: CGPoint(x: event.deltaX, y: event.deltaY))
        default:
            if isMoveMode, dragTravel < Constants.dragThreshold {
                settle(.tile(atWindowPoint: event.locationInWindow))
            }
        }
        return nil
    }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if FloatingRevealKey.current == .command, event.modifierFlags.contains(.command) {
            interruptControl()
            return event
        }
        if event.keyCode == 48, event.modifierFlags.contains(.control) {
            interruptControl()
            canvas.dismissFloatingTabs()
            return event
        }
        if canvas.floatingRenamingGroupID != nil, event.keyCode != Constants.escapeKeyCode {
            return event
        }
        if canvas.floatingVisibility.isRevealed, event.keyCode == Constants.escapeKeyCode, !floatingHasKeyboardFocus() {
            interruptControl()
            if canvas.floatingRenamingGroupID != nil {
                canvas.floatingRenamingGroupID = nil
            } else if canvas.selectedFloatingTabIDs.isEmpty {
                canvas.dismissFloatingTabs()
            } else {
                canvas.selectedFloatingTabIDs = []
            }
            return nil
        }
        if floatingHasKeyboardFocus(), canvas.floatingVisibility.isHeld {
            return FloatingPreviewInput.removingRevealModifier(from: event)
        }
        if canvas.floatingVisibility.isRevealed, !floatingHasKeyboardFocus() {
            let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control]).subtracting(FloatingRevealKey.current.flag)
            if modifiers.isEmpty, let islands,
               let direction = TableDirection.allCases.first(where: { $0.canvasDirection.rawValue == event.keyCode }) {
                islands.step(direction)
                return nil
            }
            if modifiers.isEmpty, event.keyCode == 36 {
                canvas.openFocusedFloatingTab()
                return nil
            }
        }
        interruptControl()
        guard isMoveMode, event.keyCode == Constants.escapeKeyCode else { return event }
        settle(.origin)
        return nil
    }

    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        if canvas.isPanningFromPage {
            if event.modifierFlags.contains(.option),
               case let .zoom(factor) = CanvasWheelInput.action(for: event) {
                canvas.zoom(by: factor, aboutWindowPoint: event.locationInWindow)
            } else {
                canvas.pan(by: CanvasWheelInput.cameraPan(for: event))
            }
            return nil
        }
        interruptControl()
        return event
    }

    private func settle(_ place: CanvasPanSettle) {
        isMoveMode = false
        canvas.endPan(settlingOn: place)
    }

    // MARK: - ⌃

    /// Where the pointer is for `event`, in window coordinates. Key and modifier events
    /// carry no pointer location of their own, so for those the window is asked.
    private func pointer(for event: NSEvent) -> CGPoint {
        switch event.type {
        case .flagsChanged, .keyDown, .keyUp:
            window?.mouseLocationOutsideOfEventStream ?? .zero
        default:
            event.locationInWindow
        }
    }

    private func handleFlags(_ event: NSEvent) -> NSEvent? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let revealKey = FloatingRevealKey.current
        let now = Date()
        Logger.debug("flags \(modifiers.rawValue) moveMode \(isMoveMode) panning \(canvas.isPanningFromPage) eligible \(isEligible(pointer(for: event))) sinceTap \(lastControlTap.map { now.timeIntervalSince($0) } ?? -1)", category: Logger.canvas)

        if canvas.floatingVisibility.isHeld, modifiers.contains(revealKey.flag), floatingHasKeyboardFocus() {
            return event
        }
        if revealKey.matchesHold(modifiers) {
            guard !canvas.floatingVisibility.isHeld else { return event }
            controlDownAt = now
            if isMoveMode {
                return event
            }
            if !canvas.isActive, floatingEligible() {
                canvas.revealFloatingTabs()
            }
            return event
        }

        // ⌃ went up, or another modifier joined it.
        canvas.releaseFloatingTabs()
        let wasTap = controlDownAt.map { now.timeIntervalSince($0) <= Constants.tapDuration } ?? false
        controlDownAt = nil
        if modifiers.isEmpty, wasTap {
            if isMoveMode {
                settle(.nearest)
                return event
            }
            lastControlTap = now
        } else {
            lastControlTap = nil
        }
        if canvas.isPanningFromPage, !isMoveMode, !modifiers.contains(revealKey.flag) {
            canvas.endPan(settlingOn: .nearest)
        }
        return event
    }

    /// Other input while ⌃ is down makes it part of a shortcut or ⌃-click.
    private func interruptControl() {
        islandInput?.interrupt()
        canvas.releaseFloatingTabs()
        controlDownAt = nil
        lastControlTap = nil
    }

    // MARK: - Pinch

    private func handlePinch(_ event: NSEvent) -> NSEvent? {
        Logger.debug("pinch phase \(event.phase.rawValue) magnification \(event.magnification) state \(pinch)", category: Logger.canvas)
        switch event.phase {
        case .began:
            if !canvas.isActive, isEligible(pointer(for: event)) {
                pinch = .undecided(began: event)
                return nil
            }
            pinch = .passing
            return event

        case .changed:
            return pinchChanged(event)

        case .ended, .cancelled:
            defer { pinch = .idle }
            switch pinch {
            case .opening:
                // The release event's own step is the fingers lifting, often a jolt
                // outward; the table decides from where the pinch stood before.
                return nil
            case let .undecided(began):
                window?.sendEvent(began)
                return event
            case .idle, .passing:
                return event
            }

        default:
            if case .opening = pinch {
                return nil
            }
            return event
        }
    }

    private func pinchChanged(_ event: NSEvent) -> NSEvent? {
        switch pinch {
        case let .undecided(began):
            if event.magnification < 0 {
                let scale = max(Constants.minimumScale, 1 + event.magnification)
                pinch = .opening(scale: scale, trend: event.magnification)
                return nil
            }
            if event.magnification > 0 {
                pinch = .passing
                canvas.offerHint(.enteringCanvas)
                window?.sendEvent(began)
                return event
            }
            return nil

        case let .opening(scale, trend):
            let next = max(Constants.minimumScale, scale * (1 + event.magnification))
            let nextTrend = trend + (event.magnification - trend) * Constants.trendWeight
            pinch = .opening(scale: next, trend: nextTrend)
            return nil

        case .idle, .passing:
            return event
        }
    }
}
