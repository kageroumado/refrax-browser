import Foundation

/// A direction between the islands' rows and across the window.
nonisolated enum TableDirection: String, Codable, CaseIterable, Sendable {
    case left
    case right
    case up
    case down

    /// The arrow key that steps this way, as `NSEvent.keyCode`.
    var keyCode: UInt16 {
        switch self {
        case .left: 123
        case .right: 124
        case .down: 125
        case .up: 126
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
