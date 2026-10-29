import AppKit

/// Turns the reveal key + swipe or wheel on the page into steps between chips, ahead of the
/// page.
///
/// ``CanvasPageGestures`` hands every scroll event in the window here first; what this takes
/// never reaches the page. A trackpad gesture claimed by the router steps once, in the
/// direction the fingers moved past a short distance, and the rest of the gesture and its
/// momentum are swallowed. A wheel notch is one step.
@MainActor
final class IslandInput {
    private unowned let islands: IslandController
    private var router = TableScrollRouter()
    private var travel = CGSize.zero
    private var hasStepped = false

    private enum Layout {
        /// How far the fingers move before a swipe counts.
        static let swipeDistance: CGFloat = 48
    }

    init(islands: IslandController) {
        self.islands = islands
    }

    var isSliding: Bool {
        router.isSliding
    }

    /// Routes a scroll event. Returns `true` when the islands took it.
    func route(_ event: NSEvent, canStart: @autoclosure () -> Bool) -> Bool {
        let sample = TableScrollRouter.Sample(
            source: TableScrollSource.classify(
                hasPreciseDeltas: event.hasPreciseScrollingDeltas, phase: event.phase, momentumPhase: event.momentumPhase,
            ),
            phase: event.phase,
            momentumPhase: event.momentumPhase,
            delta: CGSize(width: event.scrollingDeltaX, height: event.scrollingDeltaY),
            shift: event.modifierFlags.contains(.shift),
        )
        let keyDown = FloatingRevealKey.current.matchesHold(event.modifierFlags.intersection([.control, .option, .command]))
        let mayStart = keyDown && canStart() && islands.currentTab != nil
        switch router.route(sample, controlDown: keyDown, canStart: mayStart) {
        case .pass:
            return false
        case .settleAndPass:
            reset()
            return false
        case .consume, .liftOff:
            return true
        case .settle:
            reset()
            return true
        case let .begin(delta):
            travel = .zero
            hasStepped = false
            accumulate(delta)
            return true
        case let .pan(delta):
            accumulate(delta)
            return true
        case let .step(direction):
            islands.step(direction)
            return true
        }
    }

    /// A click, a key, the key let go, or the window losing key ends the gesture.
    func interrupt() {
        _ = router.interrupt()
        reset()
    }

    private func accumulate(_ delta: CGSize) {
        guard !hasStepped else { return }
        travel.width += delta.width
        travel.height += delta.height
        let direction: TableDirection?
        if abs(travel.width) >= Layout.swipeDistance, abs(travel.width) >= abs(travel.height) {
            // Fingers moving left bring the chip on the right into view.
            direction = travel.width < 0 ? .right : .left
        } else if abs(travel.height) >= Layout.swipeDistance {
            direction = travel.height < 0 ? .down : .up
        } else {
            direction = nil
        }
        if let direction {
            hasStepped = true
            islands.step(direction)
        }
    }

    private func reset() {
        travel = .zero
        hasStepped = false
    }
}
