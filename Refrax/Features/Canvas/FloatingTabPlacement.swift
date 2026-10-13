import CoreGraphics
import Foundation

/// A tab's position within the available window area, independent of desk geometry.
nonisolated struct FloatingTabPlacement: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var isCompact: Bool
    var isPinned: Bool
    var previewWidth: Double?
    var previewHeight: Double?
    var region: FloatingPageRegion?
    var showsInEverySpace: Bool?

    static func initial(index: Int, count: Int = 10, isCompact: Bool = true) -> Self {
        let columns = max(2, Int(ceil(Double(count) / 5)))
        let rows = max(2, Int(ceil(Double(count) / Double(columns))))
        return Self(
            x: Double(index % columns) / Double(columns - 1),
            y: min(1, Double(index / columns) / Double(rows - 1)),
            isCompact: isCompact,
            isPinned: false,
        )
    }

    /// The places a tab starts at before anyone moves it: the window's four corners.
    static let startingSlotCount = 4

    /// The starting slot whose card would cover none of `occupied`, nearest to `anchor`;
    /// without an anchor, the first free slot in grid order.
    static func freeStartingSlot(
        nearest anchor: CGPoint?, avoiding occupied: [FloatingTabPlacement], in bounds: CGRect, isCompact: Bool,
    ) -> FloatingTabPlacement? {
        let taken = occupied.map { $0.frame(in: bounds) }
        let free = (0 ..< startingSlotCount).map { initial(index: $0, count: startingSlotCount, isCompact: isCompact) }
            .filter { slot in
                let frame = slot.frame(in: bounds)
                return !taken.contains { $0.intersects(frame) }
            }
        guard let anchor else { return free.first }
        return free.min { lhs, rhs in
            let a = lhs.frame(in: bounds), b = rhs.frame(in: bounds)
            return hypot(a.midX - anchor.x, a.midY - anchor.y) < hypot(b.midX - anchor.x, b.midY - anchor.y)
        }
    }

    static let headerHeight: CGFloat = 34
    static let previewInset: CGFloat = 6

    var size: CGSize {
        isCompact ? CGSize(width: 250, height: Self.headerHeight) : CGSize(
            width: Self.dimension(previewWidth, fallback: 340, minimum: 250),
            height: Self.dimension(previewHeight, fallback: 250, minimum: 180),
        )
    }

    func frame(in bounds: CGRect) -> CGRect {
        let area = Self.availableArea(in: bounds)
        let size = CGSize(width: min(size.width, area.width), height: min(size.height, area.height))
        return CGRect(
            x: area.minX + Self.unit(x) * max(0, area.width - size.width),
            y: area.minY + Self.unit(y) * max(0, area.height - size.height),
            width: size.width,
            height: size.height,
        )
    }

    mutating func move(to origin: CGPoint, in bounds: CGRect) {
        let area = Self.availableArea(in: bounds)
        let frame = frame(in: bounds)
        x = Self.unit((origin.x - area.minX) / max(1, area.width - frame.width))
        y = Self.unit((origin.y - area.minY) / max(1, area.height - frame.height))
    }

    /// Changes presentation while keeping the tab anchored where it was placed.
    mutating func setCompact(_ value: Bool, in bounds: CGRect) {
        let origin = frame(in: bounds).origin
        isCompact = value
        if value {
            isPinned = false
        }
        move(to: origin, in: bounds)
    }

    /// Resizes from the lower-right corner while keeping the upper-left corner in place.
    mutating func resize(to size: CGSize, in bounds: CGRect) {
        let origin = frame(in: bounds).origin
        let area = Self.availableArea(in: bounds)
        previewWidth = min(Self.dimension(size.width, fallback: self.size.width, minimum: 250), area.maxX - origin.x)
        previewHeight = min(Self.dimension(size.height, fallback: self.size.height, minimum: 180), area.maxY - origin.y)
        move(to: origin, in: bounds)
    }

    /// Moves the card sideways off `obstacle` until `gap` separates them at their closest
    /// approach, on the side its center is on; a card already that far away stays put.
    mutating func keepClear(of obstacle: CGRect, gap: CGFloat, in bounds: CGRect) {
        let frame = frame(in: bounds)
        let horizontal = max(obstacle.minX - frame.maxX, frame.minX - obstacle.maxX)
        let vertical = max(obstacle.minY - frame.maxY, frame.minY - obstacle.maxY)
        // Half a point of slack absorbs the rounding of the normalized position.
        guard !obstacle.isEmpty, horizontal < gap - 0.5, vertical < gap - 0.5 else { return }
        let x = frame.midX >= obstacle.midX ? obstacle.maxX + gap : obstacle.minX - gap - frame.width
        move(to: CGPoint(x: x, y: frame.minY), in: bounds)
    }

    private static func dimension(_ value: Double?, fallback: Double, minimum: Double) -> Double {
        guard let value, value.isFinite else { return fallback }
        return max(minimum, value)
    }

    private static func availableArea(in bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.minX + 16,
            y: bounds.minY + 16,
            width: max(1, bounds.width - 32),
            height: max(1, bounds.height - 32),
        )
    }

    private static func unit(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}
