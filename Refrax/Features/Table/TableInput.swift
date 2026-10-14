import AppKit

/// Turns ⌃ + scroll on the page into table motion, ahead of the page.
///
/// ``CanvasPageGestures`` hands every scroll event in the window here first; what this
/// returns `true` for never reaches the page. A click, a key, ⌃ let go, or the window losing
/// key ends a slide in a rest.
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
        table.onForcedRest = { [weak self] in self?.forcedRest() }
    }

    /// Whether a slide owns the scroll events now, wherever the pointer is.
    var isSliding: Bool {
        router.isSliding
    }

    /// Routes a scroll event. `canStart` is `false` while something above the page (a card,
    /// the island, the desk) owns the pointer. Returns `true` when the table took the event.
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
        let controlDown = event.modifierFlags.contains(.control)
        let mayStart = controlDown && canStart() && table.canSlide(atWindowPoint: event.locationInWindow)
        let decision = router.route(sample, controlDown: controlDown, canStart: mayStart)
        return perform(decision, sample: sample)
    }

    /// Ends a slide in progress: the view settles and the rest of the gesture is swallowed.
    func interrupt() {
        guard router.isSliding else { return }
        _ = perform(router.interrupt(), sample: TableScrollRouter.Sample(source: .trackpad, delta: .zero))
    }

    /// The table settled on its own; what is left of the gesture is swallowed.
    private func forcedRest() {
        momentumWindow?.cancel()
        smoothWheelQuiet?.cancel()
        _ = router.interrupt()
    }

    private func perform(_ decision: TableScrollRouter.Decision, sample: TableScrollRouter.Sample) -> Bool {
        switch decision {
        case .pass:
            return false
        case .consume:
            return true
        case let .begin(delta):
            momentumWindow?.cancel()
            table.beginPan(delta, fingersDown: !sample.phase.isEmpty)
            armSmoothWheelQuiet(for: sample)
            return true
        case let .pan(delta):
            momentumWindow?.cancel()
            table.pan(delta)
            armSmoothWheelQuiet(for: sample)
            return true
        case .liftOff:
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                _ = perform(router.momentumWindowElapsed(), sample: sample)
            }
            momentumWindow = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Layout.momentumWindow, execute: work)
            return true
        case .settle:
            momentumWindow?.cancel()
            smoothWheelQuiet?.cancel()
            table.endPan()
            return true
        case let .step(direction):
            table.step(direction)
            return true
        }
    }

    private func armSmoothWheelQuiet(for sample: TableScrollRouter.Sample) {
        guard sample.source == .smoothWheel else { return }
        smoothWheelQuiet?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            _ = perform(router.smoothWheelWentQuiet(), sample: sample)
        }
        smoothWheelQuiet = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.smoothWheelQuiet, execute: work)
    }
}
