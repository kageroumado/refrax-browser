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
/// - **⌃-scroll** on a page brings the desk up at page size and slides it under the wheel;
///   releasing ⌃ settles into the tile nearest the middle of the window.
@MainActor
final class CanvasPageGestures {
    private enum PinchState {
        case idle
        case undecided(began: NSEvent)
        case passing
        case opening(scale: CGFloat, lastStep: CGFloat)
    }

    private enum Constants {
        /// A pinch released at or below this scale completes the opening.
        static let commitScale: CGFloat = 0.85
        /// A last step closing at least this fast completes the opening from anywhere.
        static let flickStep: CGFloat = -0.02
        /// Smallest scale tracked; the opening ends long before.
        static let minimumScale: CGFloat = 0.05
    }

    private weak var window: NSWindow?
    private unowned let canvas: TabCanvasManager
    private let isEligible: (NSEvent) -> Bool
    private var pinch = PinchState.idle
    private var monitor: Any?

    /// - Parameter isEligible: Whether a gesture starting with this event may reach the
    ///   canvas: the window's state allows it and the pointer is over the page.
    init(window: NSWindow, canvas: TabCanvasManager, isEligible: @escaping (NSEvent) -> Bool) {
        self.window = window
        self.canvas = canvas
        self.isEligible = isEligible
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.magnify, .scrollWheel, .flagsChanged]) { [weak self] event in
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
        switch event.type {
        case .magnify: return handlePinch(event)
        case .scrollWheel: return handleScroll(event)
        case .flagsChanged: return handleFlags(event)
        default: return event
        }
    }

    // MARK: - ⌃-Scroll

    private func handleScroll(_ event: NSEvent) -> NSEvent? {
        if canvas.isPanningFromPage {
            canvas.pan(by: CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY))
            return nil
        }
        guard event.modifierFlags.contains(.control), !canvas.isActive,
              event.phase == .began || event.phase == [], isEligible(event)
        else { return event }
        canvas.beginPan()
        canvas.pan(by: CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY))
        return nil
    }

    private func handleFlags(_ event: NSEvent) -> NSEvent? {
        if canvas.isPanningFromPage, !event.modifierFlags.contains(.control) {
            canvas.endPan()
        }
        return event
    }

    // MARK: - Pinch

    private func handlePinch(_ event: NSEvent) -> NSEvent? {
        switch event.phase {
        case .began:
            if !canvas.isActive, isEligible(event) {
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
            case let .opening(scale, lastStep):
                canvas.endInteractiveOpen(commit: scale <= Constants.commitScale || lastStep <= Constants.flickStep)
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
                pinch = .opening(scale: scale, lastStep: event.magnification)
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

        case let .opening(scale, _):
            let next = max(Constants.minimumScale, scale * (1 + event.magnification))
            pinch = .opening(scale: next, lastStep: event.magnification)
            canvas.updateInteractiveOpen(scale: next)
            return nil

        case .idle, .passing:
            return event
        }
    }
}
