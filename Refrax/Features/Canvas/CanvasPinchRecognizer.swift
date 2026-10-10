import AppKit

/// Turns a pinch on the page into the opening of the tab canvas.
///
/// Watches the window's magnify events ahead of the page, whichever engine renders it.
/// A pinch that closes while the page is at its normal size opens the canvas under the
/// fingers and follows them; releasing past ``Constants/commitProgress``, or with a flick,
/// completes it, and anything less goes back to the page. Every other pinch — one that
/// zooms the page in, or one on a page already zoomed — reaches the page untouched.
///
/// The direction is only known once the fingers move, so the gesture's `began` event is
/// held back until then and handed to the page when the pinch turns out to be its own.
@MainActor
final class CanvasPinchRecognizer {
    private enum State {
        case idle
        case undecided(began: NSEvent)
        case passing
        case opening(scale: CGFloat, lastStep: CGFloat)
    }

    private enum Constants {
        /// Pinch scale at which the canvas is fully open.
        static let fullyOpenScale: CGFloat = 0.5
        /// Progress past which a released pinch completes the opening.
        static let commitProgress: CGFloat = 0.3
        /// A last step closing at least this fast completes the opening from anywhere.
        static let flickStep: CGFloat = -0.02
    }

    private weak var window: NSWindow?
    private unowned let canvas: TabCanvasManager
    private let isEligible: (NSEvent) -> Bool
    private var state = State.idle
    private var monitor: Any?

    /// - Parameter isEligible: Whether a pinch starting with this event may open the
    ///   canvas: the window's state allows it and the fingers are over the page.
    init(window: NSWindow, canvas: TabCanvasManager, isEligible: @escaping (NSEvent) -> Bool) {
        self.window = window
        self.canvas = canvas
        self.isEligible = isEligible
        monitor = NSEvent.addLocalMonitorForEvents(matching: .magnify) { [weak self] event in
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

        switch event.phase {
        case .began:
            if !canvas.isActive, isEligible(event) {
                state = .undecided(began: event)
                return nil
            }
            state = .passing
            return event

        case .changed:
            return changed(event)

        case .ended, .cancelled:
            defer { state = .idle }
            switch state {
            case let .opening(scale, lastStep):
                let progress = Self.progress(for: scale)
                canvas.endInteractiveOpen(commit: progress >= Constants.commitProgress || lastStep <= Constants.flickStep)
                return nil
            case let .undecided(began):
                window?.sendEvent(began)
                return event
            case .idle, .passing:
                return event
            }

        default:
            if case .opening = state { return nil }
            return event
        }
    }

    private func changed(_ event: NSEvent) -> NSEvent? {
        switch state {
        case let .undecided(began):
            if event.magnification < 0 {
                let scale = 1 + event.magnification
                state = .opening(scale: scale, lastStep: event.magnification)
                canvas.beginInteractiveOpen()
                canvas.updateInteractiveOpen(Self.progress(for: scale))
                return nil
            }
            if event.magnification > 0 {
                state = .passing
                canvas.offerHint(.enteringCanvas)
                window?.sendEvent(began)
                return event
            }
            return nil

        case let .opening(scale, _):
            let next = scale * (1 + event.magnification)
            state = .opening(scale: next, lastStep: event.magnification)
            canvas.updateInteractiveOpen(Self.progress(for: next))
            return nil

        case .idle, .passing:
            return event
        }
    }

    /// Opening progress for a pinch scale: 0 at the start, 1 at ``Constants/fullyOpenScale``.
    private static func progress(for scale: CGFloat) -> CGFloat {
        min(1, max(0, (1 - scale) / (1 - Constants.fullyOpenScale)))
    }
}
