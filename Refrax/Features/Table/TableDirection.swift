import Foundation

/// A slab's width as a preset share of the window's width.
nonisolated enum TableWidth: String, Codable, CaseIterable, Sendable {
    case third
    case half
    case twoThirds
    case full

    /// The share of the viewport width a slab of this preset takes.
    var fraction: Double {
        switch self {
        case .third: 1.0 / 3.0
        case .half: 0.5
        case .twoThirds: 2.0 / 3.0
        case .full: 1
        }
    }

    /// The next preset in the cycle ⅓ → ½ → ⅔ → 1 → ⅓.
    var next: Self {
        switch self {
        case .third: .half
        case .half: .twoThirds
        case .twoThirds: .full
        case .full: .third
        }
    }
}

/// A direction on the shared spatial table.
nonisolated enum TableDirection: String, Codable, CaseIterable, Sendable {
    case left
    case right
    case up
    case down

    var canvasDirection: CanvasNavigation.Direction {
        switch self {
        case .left: .left
        case .right: .right
        case .up: .up
        case .down: .down
        }
    }

    /// The step one discrete wheel notch takes, or `nil` for an event with no movement.
    ///
    /// Deltas follow `NSEvent.scrollingDeltaX/Y`: a vertical notch moves through rows, a
    /// sideways notch along the row, and ⇧ turns a vertical notch sideways, so a mouse with
    /// one wheel reaches both axes the way it does everywhere else on the Mac.
    static func wheelStep(deltaX: Double, deltaY: Double, shift: Bool) -> Self? {
        if deltaX != 0, abs(deltaX) >= abs(deltaY) {
            return deltaX > 0 ? .left : .right
        }
        guard deltaY != 0 else { return nil }
        if shift {
            return deltaY > 0 ? .left : .right
        }
        return deltaY > 0 ? .up : .down
    }
}
