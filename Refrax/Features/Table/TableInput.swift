import AppKit

/// Turns ⌃ + scroll on the page into adjacent tab movement, ahead of the page.
///
/// ``CanvasPageGestures`` hands every scroll event in the window here first; what this
/// returns `true` for never reaches the page. A click, a key, ⌃ let go, or the window losing
/// key ends the claimed gesture.
@MainActor
final class TableInput {
    private unowned let table: TableController
    private var router = TableScrollRouter()
    /// Whether the last routed event requested table navigation.
    private(set) var didNavigate = false
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

    /// Whether a gesture owns the scroll events, wherever the pointer is.
    var isSliding: Bool {
        router.isSliding
    }

    /// Routes a scroll event. `canStart` is `false` while a control or a manipulation
    /// owns the pointer. Returns `true` when table navigation took the event.
    func route(_ event: NSEvent, canStart: @autoclosure () -> Bool) -> Bool {
        if event.modifierFlags.contains([.control, .option]),
           !event.modifierFlags.contains(.command), canStart(), table.canSlide(atWindowPoint: event.locationInWindow),
           case let .zoom(factor) = CanvasWheelInput.action(for: event) {
            interrupt()
            didNavigate = true
            table.zoom(by: factor, at: event.locationInWindow)
            return true
        }
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
        let mayStart = controlDown && event.modifierFlags.intersection([.command, .option]).isEmpty && canStart() && table.canSlide(atWindowPoint: event.locationInWindow)
        let decision = router.route(sample, controlDown: controlDown, canStart: mayStart)
        switch decision {
        case .begin, .pan, .step: didNavigate = true
        default: didNavigate = false
        }
        return perform(decision, sample: sample)
    }

    /// Ends a gesture in progress and swallows its remaining momentum.
    func interrupt() {
        guard router.isSliding else { return }
        _ = perform(router.interrupt(), sample: TableScrollRouter.Sample(source: .trackpad, delta: .zero))
    }

    private func perform(_ decision: TableScrollRouter.Decision, sample: TableScrollRouter.Sample) -> Bool {
        switch decision {
        case .pass:
            return false
        case .consume:
            if sample.source == .smoothWheel, router.state == .smoothDraining {
                armSmoothWheelQuiet()
            }
            return true
        case let .begin(delta):
            momentumWindow?.cancel()
            table.beginPan(delta, shift: sample.shift)
            if sample.source == .smoothWheel {
                armSmoothWheelQuiet()
            }
            return true
        case let .pan(delta):
            momentumWindow?.cancel()
            if sample.momentumPhase.isEmpty {
                table.pan(delta, shift: sample.shift)
            }
            if sample.source == .smoothWheel {
                armSmoothWheelQuiet()
            }
            return true
        case .liftOff:
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                _ = perform(router.momentumWindowElapsed(), sample: sample)
            }
            momentumWindow = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Layout.momentumWindow, execute: work)
            return true
        case .settle, .settleAndPass:
            momentumWindow?.cancel()
            smoothWheelQuiet?.cancel()
            table.endPan()
            if router.state == .smoothDraining {
                armSmoothWheelQuiet()
            }
            return decision != .settleAndPass
        case let .step(direction):
            table.endPan()
            table.step(direction)
            return true
        }
    }

    private func armSmoothWheelQuiet() {
        smoothWheelQuiet?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            _ = perform(router.smoothWheelWentQuiet(), sample: TableScrollRouter.Sample(source: .smoothWheel, delta: .zero))
        }
        smoothWheelQuiet = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Layout.smoothWheelQuiet, execute: work)
    }
}
