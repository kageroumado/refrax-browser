import CoreGraphics
import Foundation

/// A tab's presentation and position on the shared table, in points with a top-left origin.
nonisolated struct FloatingTabPlacement: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var shape: FloatingCardShape
    var isPinned: Bool
    /// A placed card keeps this table position across window sizes and overview zoom levels.
    var tableOrigin: CGPoint?
    /// The tab shape's width, kept while the card wears another shape.
    var tabWidth: Double?
    /// The live page's size, kept while the card wears another shape.
    var previewWidth: Double?
    var previewHeight: Double?
    var region: FloatingPageRegion?
    /// The window side the tab fills at full height. A docked tab is always visible, and its
    /// floating frame stays where it was so undocking returns it there.
    var dock: FloatingDockEdge?
    /// The docked column's share of the window's width, before ``FloatingDockLayout`` clamps it.
    var dockFraction: Double?

    var isDocked: Bool {
        dock != nil
    }

    /// The docked column's requested share of the window's width.
    var dockWidthFraction: Double {
        dockFraction ?? FloatingDockLayout.defaultFraction
    }

    static func initial(index: Int, count: Int = 10, shape: FloatingCardShape = .tab) -> Self {
        let columns = max(2, Int(ceil(Double(count) / 5)))
        let rows = max(2, Int(ceil(Double(count) / Double(columns))))
        return Self(
            x: Double(index % columns) / Double(columns - 1),
            y: min(1, Double(index / columns) / Double(rows - 1)),
            shape: shape,
            isPinned: false,
        )
    }

    /// The places a tab starts at before anyone moves it: the window's four corners.
    static let startingSlotCount = 4

    /// The starting slot whose card would cover none of `occupied`, nearest to `anchor`;
    /// without an anchor, the first free slot in grid order.
    static func freeStartingSlot(
        nearest anchor: CGPoint?, avoiding occupied: [FloatingTabPlacement], in bounds: CGRect, shape: FloatingCardShape,
    ) -> FloatingTabPlacement? {
        let taken = occupied.map { $0.frame(in: bounds) }
        let free = (0 ..< startingSlotCount)
            .map { initial(index: $0, count: startingSlotCount, shape: shape) }
            .filter { slot in !taken.contains { $0.intersects(slot.frame(in: bounds)) } }
        guard let anchor else { return free.first }
        return free.min { lhs, rhs in
            let a = lhs.frame(in: bounds), b = rhs.frame(in: bounds)
            return hypot(a.midX - anchor.x, a.midY - anchor.y) < hypot(b.midX - anchor.x, b.midY - anchor.y)
        }
    }

    static let headerHeight: CGFloat = 34
    static let previewInset: CGFloat = 6

    /// The card's size in its shape, before the window's area limits it.
    var size: CGSize {
        switch shape {
        case .icon: shape.naturalSize
        case .tab: shape.fitted(CGSize(width: tabWidth ?? .nan, height: .nan))
        case .live: shape.fitted(CGSize(width: previewWidth ?? .nan, height: previewHeight ?? .nan))
        }
    }

    func frame(in bounds: CGRect) -> CGRect {
        if let tableOrigin {
            return CGRect(origin: tableOrigin, size: size)
        }
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
        if tableOrigin != nil {
            tableOrigin = CGPoint(
                x: min(max(origin.x, area.minX), max(area.minX, area.maxX - frame.width)),
                y: min(max(origin.y, area.minY), max(area.minY, area.maxY - frame.height)),
            )
        }
        x = Self.unit((origin.x - area.minX) / max(1, area.width - frame.width))
        y = Self.unit((origin.y - area.minY) / max(1, area.height - frame.height))
    }

    /// Changes shape at the size the card last had in it, keeping its top-leading corner.
    mutating func setShape(_ shape: FloatingCardShape, in bounds: CGRect) {
        let origin = frame(in: bounds).origin
        self.shape = shape
        move(to: origin, in: bounds)
    }

    /// Resizes from the bottom-trailing corner, keeping the top-leading corner in place; a size
    /// past a shape threshold changes the shape, and a dimension that is not finite keeps its size.
    mutating func resize(to size: CGSize, in bounds: CGRect) {
        let start = frame(in: bounds)
        let width = size.width.isFinite ? size.width : start.width
        let height = size.height.isFinite ? size.height : start.height
        let translation = CGSize(width: width - start.width, height: height - start.height)
        resize(dragging: .bottomTrailing, from: start, by: translation, in: bounds)
    }

    /// Resizes as the pointer drags `handle` by `translation` from where the card was at
    /// `start`, with the opposite sides fixed. The shape follows the size it is dragged to;
    /// on crossing into a new shape, the card takes that shape's size closest to the pointer.
    ///
    /// - Returns: Whether the shape changed.
    @discardableResult
    mutating func resize(dragging handle: FloatingResizeHandle, from start: CGRect, by translation: CGSize, in bounds: CGRect) -> Bool {
        let proposed = handle.proposedSize(from: start.size, translation: translation)
        let previous = shape
        shape = FloatingCardShape.shape(after: shape, proposing: proposed)
        let area = Self.availableArea(in: bounds)
        let frame = handle.frame(from: start, size: shape.fitted(proposed), minimum: shape.minimumSize, within: area)
        switch shape {
        case .icon: break
        case .tab: tabWidth = frame.width
        case .live:
            previewWidth = frame.width
            previewHeight = frame.height
        }
        move(to: frame.origin, in: bounds)
        return shape != previous
    }

    static let edgeInset: CGFloat = 16

    static func availableArea(in bounds: CGRect) -> CGRect {
        CGRect(
            x: bounds.minX + edgeInset,
            y: bounds.minY + edgeInset,
            width: max(1, bounds.width - 2 * edgeInset),
            height: max(1, bounds.height - 2 * edgeInset),
        )
    }

    private static func unit(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
}
