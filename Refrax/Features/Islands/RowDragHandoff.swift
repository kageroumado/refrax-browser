import CoreGraphics
import Foundation

/// When a row dragged within the browser window leaves it: past the window's edge the drag
/// stops being a move between islands and becomes a system drag, carrying the page's address
/// and a `.webloc` to Finder or any app, once per drag.
nonisolated struct RowDragHandoff: Equatable, Sendable {
    /// How far past the window's edge the pointer goes before the drag leaves, so a drag along
    /// the edge stays a move.
    static let margin: CGFloat = 6

    /// The row whose drag has left the window, until its system drag ends.
    private(set) var handedOffTabID: UUID?

    /// Whether `tabID`'s drag left the window and is the system's now.
    func isHandedOff(_ tabID: UUID) -> Bool {
        handedOffTabID == tabID
    }

    /// Whether the drag of `tabID` at `point` leaves the window now: the pointer is past
    /// `bounds` by the margin, the row has an address to carry, and no drag has left already.
    /// Leaving is recorded.
    mutating func leaves(_ tabID: UUID, at point: CGPoint, bounds: CGRect, carriesAddress: Bool) -> Bool {
        guard handedOffTabID == nil, carriesAddress, !bounds.isEmpty,
              !bounds.insetBy(dx: -Self.margin, dy: -Self.margin).contains(point) else { return false }
        handedOffTabID = tabID
        return true
    }

    /// The system drag ended, wherever it was let go.
    mutating func end() {
        handedOffTabID = nil
    }
}
