import AppKit

/// Turns ⌃ + scroll on the page into table motion, ahead of the page.
///
/// ``CanvasPageGestures`` hands every scroll event in the window here first; what this
/// returns `true` for never reaches the page. ⌃ going down warms the cover's snapshots for
/// the slide it may start.
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
        return perform(decision, sample: sample, at: event.timestamp)
    }

    /// ⌃ went down or up.
    func controlChanged(isDown: Bool) {
        guard isDown, !router.isSliding else { return }
        Task { await table.captureLiveSlabs() }
    }

    private func perform(_ decision: TableScrollRouter.Decision, sample: TableScrollRouter.Sample, at time: TimeInterval) -> Bool {
        switch decision {
        case .pass:
            return false
        case .consume:
            return true
        case let .begin(delta):
            momentumWindow?.cancel()
            table.beginPan(delta, at: time)
            armSmoothWheelQuiet(for: sample)
            return true
        case let .pan(delta):
            momentumWindow?.cancel()
            table.pan(delta, at: time)
            armSmoothWheelQuiet(for: sample)
            return true
        case .liftOff:
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                _ = perform(router.momentumWindowElapsed(), sample: sample, at: time)
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
            _ = perform(router.smoothWheelWentQuiet(), sample: sample, at: 0)
        }
        smoothWheelQuiet = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.smoothWheelQuiet, execute: work)
    }
}
