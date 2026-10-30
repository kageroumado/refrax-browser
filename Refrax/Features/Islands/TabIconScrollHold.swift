import CoreGraphics

/// The hold a scroll on the rail's page icon keeps: the islands stay revealed, as under the
/// reveal key, from the first step until the pointer leaves the icon.
///
/// The hold begins only once a scroll has slid or stepped, so fingers resting on the trackpad
/// over the icon reveal nothing. While it lasts, every scroll over the icon belongs to the
/// islands, and the icon's row is read with a little slack so a pointer that drifts a point
/// or two keeps the hold. The pointer leaving the row, the rail going away, or whatever else
/// ends the reveal (a click, a key, the window losing key) ends the hold.
nonisolated struct TabIconScrollHold: Equatable, Sendable {
    /// How far past the icon's row the pointer may drift before the hold ends.
    static let slack: CGFloat = 6

    private(set) var isHolding = false

    /// Whether a scroll with the pointer at `point` may begin a hold, or belongs to the one
    /// under way. `icon` is the page icon's row in window content coordinates, nil while the
    /// rail is away or shows no page.
    func claims(_ point: CGPoint, icon: CGRect?) -> Bool {
        Self.icon(icon, holds: point, slack: isHolding ? Self.slack : 0)
    }

    /// A scroll the islands took began a slide or stepped: the hold is on. Returns whether it
    /// began with this call.
    mutating func begin() -> Bool {
        guard !isHolding else { return false }
        isHolding = true
        return true
    }

    /// The pointer is at `point`. Returns whether the hold ended with this move.
    mutating func pointerMoved(to point: CGPoint, icon: CGRect?) -> Bool {
        guard isHolding, !Self.icon(icon, holds: point, slack: Self.slack) else { return false }
        isHolding = false
        return true
    }

    /// Something else ended the reveal. Returns whether a hold was on.
    mutating func end() -> Bool {
        defer { isHolding = false }
        return isHolding
    }

    static func icon(_ icon: CGRect?, holds point: CGPoint, slack: CGFloat) -> Bool {
        guard let icon, !icon.isEmpty else { return false }
        return icon.insetBy(dx: -slack, dy: -slack).contains(point)
    }
}
