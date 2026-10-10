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
/// - **⌃** held alone over a page for ``Constants/peekDelay`` brings the desk up around the
///   page, eased back a little so the page shows as a tile; releasing ⌃ settles into the
///   tile nearest the middle of the window. A click or key within the delay is a ⌃-click
///   or shortcut, and the desk stays down.
/// - **⌃ double-tapped** brings the desk up and keeps it there in move mode: with no key
///   held, scrolling and dragging move the camera at full trackpad precision, a click
///   enters the tile under it, and a mouse wheel zooms about the pointer. One more tap of
///   ⌃ settles into the nearest tile; Esc goes back to the tab it started from. ⌃ is let
///   go for this because macOS turns ⌃-click into a right click and ⌃-scroll into coarse,
///   accelerated wheel steps.
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
        /// How long ⌃ is held alone before the desk comes up.
        static let peekDelay: TimeInterval = 0.12
        /// Longest press of ⌃ that counts as a tap.
        static let tapDuration: TimeInterval = 0.25
        /// Longest gap between two taps of a double tap.
        static let doubleTapInterval: TimeInterval = 0.35
        /// Pointer travel that turns a click in move mode into a drag.
        static let dragThreshold: CGFloat = 3
        static let escapeKeyCode: UInt16 = 53
        /// Zoom per line of mouse wheel in move mode.
        static let wheelZoomStep: CGFloat = 1.1
    }

    private weak var window: NSWindow?
    private unowned let canvas: TabCanvasManager
    private let isEligible: (CGPoint) -> Bool
    private var pinch = PinchState.idle
    private var monitor: Any?
    private var pendingPeek: DispatchWorkItem?

    /// The desk is up in move mode, until a tap of ⌃, Esc, or a click settles it.
    private var isMoveMode = false
    /// When ⌃ last went down with no other input since, for telling taps from holds.
    private var controlDownAt: Date?
    /// When the last tap of ⌃ ended, for telling a double tap.
    private var lastControlTap: Date?
    /// How far the pointer has moved since the mouse went down in move mode.
    private var dragTravel: CGFloat = 0

    /// - Parameter isEligible: Whether a gesture with the pointer at this point (window
    ///   coordinates) may reach the canvas: the window's state allows it and the point is
    ///   over the page.
    init(window: NSWindow, canvas: TabCanvasManager, isEligible: @escaping (CGPoint) -> Bool) {
        self.window = window
        self.canvas = canvas
        self.isEligible = isEligible
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel, .flagsChanged, .keyDown, .leftMouseDown, .leftMouseDragged, .leftMouseUp, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            self?.handle(event) ?? event
        }
    }

    isolated deinit {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    /// Returns the event to deliver, or nil when the canvas takes it.
    private func handle(_ event: NSEvent) -> NSEvent? {
        guard event.window === window else { return event }
        if !canvas.isPanningFromPage {
            isMoveMode = false
        }
        switch event.type {
        case .magnify: return handlePinch(event)
        case .scrollWheel: return handleScroll(event)
        case .flagsChanged: return handleFlags(event)
        case .leftMouseDown, .leftMouseDragged, .leftMouseUp: return handleMouse(event)
        case .keyDown: return handleKey(event)
        default:
            interruptControl()
            return event
        }
    }

    // MARK: - Move Mode

    private func handleMouse(_ event: NSEvent) -> NSEvent? {
        guard canvas.isPanningFromPage else {
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
        interruptControl()
        guard isMoveMode, event.keyCode == Constants.escapeKeyCode else { return event }
        settle(.origin)
        return nil
    }

    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        if canvas.isPanningFromPage {
            if isMoveMode, !event.hasPreciseScrollingDeltas {
                canvas.zoom(by: pow(Constants.wheelZoomStep, event.scrollingDeltaY), aboutWindowPoint: event.locationInWindow)
            } else {
                canvas.scroll(by: CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY))
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
        let now = Date()
        Logger.debug("flags \(modifiers.rawValue) moveMode \(isMoveMode) panning \(canvas.isPanningFromPage) eligible \(isEligible(pointer(for: event))) sinceTap \(lastControlTap.map { now.timeIntervalSince($0) } ?? -1)", category: Logger.canvas)

        if modifiers == .control {
            controlDownAt = now
            if isMoveMode {
                return event
            }
            if let lastTap = lastControlTap, now.timeIntervalSince(lastTap) <= Constants.doubleTapInterval,
               !canvas.isActive, isEligible(pointer(for: event)) {
                lastControlTap = nil
                // The release of this second tap belongs to the double tap; only a later
                // tap settles.
                controlDownAt = nil
                cancelPeek()
                isMoveMode = true
                canvas.beginPan()
                return event
            }
            if !canvas.isActive, isEligible(pointer(for: event)) {
                schedulePeek()
            }
            return event
        }

        // ⌃ went up, or another modifier joined it.
        cancelPeek()
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
        if canvas.isPanningFromPage, !isMoveMode, !modifiers.contains(.control) {
            canvas.endPan(settlingOn: .nearest)
        }
        return event
    }

    /// Other input while ⌃ is down makes it part of a shortcut or ⌃-click.
    private func interruptControl() {
        cancelPeek()
        controlDownAt = nil
        lastControlTap = nil
    }

    private func schedulePeek() {
        cancelPeek()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            pendingPeek = nil
            guard NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control,
                  !canvas.isActive
            else { return }
            canvas.beginPan()
        }
        pendingPeek = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.peekDelay, execute: work)
    }

    private func cancelPeek() {
        pendingPeek?.cancel()
        pendingPeek = nil
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
            case let .opening(scale, trend):
                // The release event's own step is the fingers lifting, often a jolt
                // outward; the decision uses the pinch as it stood before.
                canvas.endInteractiveOpen(commit: scale <= Constants.commitScale || trend <= Constants.flickTrend)
                return nil
            case let .undecided(began):
                window?.sendEvent(began)
                return event
            case .idle, .passing:
                return event
            }

        default:
            if case .opening = pinch { return nil }
            return event
        }
    }

    private func pinchChanged(_ event: NSEvent) -> NSEvent? {
        switch pinch {
        case let .undecided(began):
            if event.magnification < 0 {
                let scale = max(Constants.minimumScale, 1 + event.magnification)
                pinch = .opening(scale: scale, trend: event.magnification)
                canvas.beginInteractiveOpen()
                canvas.updateInteractiveOpen(scale: scale)
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
            canvas.updateInteractiveOpen(scale: next)
            return nil

        case .idle, .passing:
            return event
        }
    }
}
