import AppKit

/// Shared wheel semantics for the overview and the persistent camera mode.
nonisolated enum CanvasWheelInput {
    enum Action: Equatable {
        case step(TableDirection)
        case pan(CGPoint)
        case zoom(CGFloat)
        case none
    }

    private enum Constants {
        static let zoomPerLine: CGFloat = 1.1
        static let preciseZoomGain: CGFloat = 0.01
        static let maximumZoomDelta: CGFloat = 3
    }

    static func action(for event: NSEvent) -> Action {
        action(
            delta: CGPoint(x: event.scrollingDeltaX, y: event.scrollingDeltaY),
            source: TableScrollSource.classify(hasPreciseDeltas: event.hasPreciseScrollingDeltas, phase: event.phase, momentumPhase: event.momentumPhase),
            shift: event.modifierFlags.contains(.shift),
            zoom: event.modifierFlags.contains(.option),
        )
    }

    static func action(delta: CGPoint, source: TableScrollSource, shift: Bool, zoom: Bool) -> Action {
        guard delta.x.isFinite, delta.y.isFinite, delta != .zero else { return .none }
        if zoom {
            let gain = source == .wheel ? 1 : Constants.preciseZoomGain
            let amount = min(Constants.maximumZoomDelta, max(-Constants.maximumZoomDelta, delta.y * gain))
            return amount == 0 ? .none : .zoom(pow(Constants.zoomPerLine, amount))
        }
        if source == .wheel {
            return TableDirection.wheelStep(deltaX: delta.x, deltaY: delta.y, shift: shift).map(Action.step) ?? .none
        }
        return .pan(delta)
    }
}
