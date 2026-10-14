import AppKit

/// Turns the scroll key + scroll on the page into table motion, ahead of the page.
///
/// ``CanvasPageGestures`` hands every scroll event in the window here first; what this takes
/// never reaches the page. A gesture the router claims is forwarded, event by event, to the
/// table's scroll view, so the motion, momentum, and rubber-banding are AppKit's own. A click,
/// a key, the key let go, or the window losing key ends a slide where it is.
@MainActor
final class TableInput {
    private unowned let table: TableController
    private var router = TableScrollRouter()
    private var momentumWindow: DispatchWorkItem?
    private var smoothWheelQuiet: DispatchWorkItem?

    private enum Layout {
        /// The pause after fingers lift in which momentum may begin.
        static let momentumWindow: TimeInterval = 0.05
        /// The quiet after a smooth wheel's last event that ends its slide.
        static let smoothWheelQuiet: TimeInterval = 0.15
    }

    init(table: TableController) {
        self.table = table
    }

    isolated deinit {
        momentumWindow?.cancel()
        smoothWheelQuiet?.cancel()
    }

    /// Whether a slide owns the scroll events now, wherever the pointer is.
    var isSliding: Bool {
        router.isSliding
    }

    /// Routes a scroll event. `canStart` is `false` while a control or a manipulation owns the
    /// pointer. Returns `true` when the table took the event.
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
        let mayStart = keyDown && canStart() && table.scrollView != nil && !table.layout.isEmpty
        let decision = router.route(sample, controlDown: keyDown, canStart: mayStart)
        return perform(decision, event: event, sample: sample)
    }

    /// Ends a slide in progress where it is; the rest of the gesture is swallowed.
    func interrupt() {
        guard router.isSliding else { return }
        _ = perform(router.interrupt(), event: nil, sample: TableScrollRouter.Sample(source: .trackpad, delta: .zero))
    }

    private func perform(_ decision: TableScrollRouter.Decision, event: NSEvent?, sample: TableScrollRouter.Sample) -> Bool {
        switch decision {
        case .pass:
            return false
        case .consume:
            if sample.source == .smoothWheel, router.state == .smoothDraining {
                armSmoothWheelQuiet()
            }
            return true
        case .begin, .pan:
            momentumWindow?.cancel()
            forward(event)
            if sample.source == .smoothWheel {
                armSmoothWheelQuiet()
            }
            return true
        case .liftOff:
            forward(event)
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                _ = perform(router.momentumWindowElapsed(), event: nil, sample: sample)
            }
            momentumWindow = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Layout.momentumWindow, execute: work)
            return true
        case .settle, .settleAndPass:
            momentumWindow?.cancel()
            smoothWheelQuiet?.cancel()
            if decision == .settle {
                forward(event)
            }
            if router.state == .smoothDraining {
                armSmoothWheelQuiet()
            }
            return decision != .settleAndPass
        case let .step(direction):
            table.wheelStep(direction)
            return true
        }
    }

    /// Hands the event to the scroll view as if it had arrived there.
    private func forward(_ event: NSEvent?) {
        guard let event, let scrollView = table.scrollView else { return }
        scrollView.scrollWheel(with: event)
    }

    private func armSmoothWheelQuiet() {
        smoothWheelQuiet?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            _ = perform(router.smoothWheelWentQuiet(), event: nil, sample: TableScrollRouter.Sample(source: .smoothWheel, delta: .zero))
        }
        smoothWheelQuiet = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.smoothWheelQuiet, execute: work)
    }
}
