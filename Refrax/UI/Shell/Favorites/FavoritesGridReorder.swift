import CoreGraphics
import Foundation

/// A tile drag in the favorites grid: which tile is held, where it is, and the order the grid
/// shows while it is held. Pure geometry, so the grid's reorder can be tested without a view.
///
/// The grid places tiles by index, so the slots (the tile frames at the mouse-down) stay put
/// for the whole drag while the tiles move between them. The held tile is drawn floating under
/// the pointer; its slot in `order` is the one nearest the floating tile's centre.
nonisolated struct FavoritesGridReorder: Equatable {
    /// The favorites before the drag, in grid order.
    let originalOrder: [UUID]
    /// The tile frames before the drag, index-aligned with `originalOrder`, in the grid's space.
    let slots: [CGRect]
    /// The held tile.
    let draggedID: UUID
    /// The held tile's index in `originalOrder`.
    let sourceIndex: Int
    /// Where in the held tile the pointer took hold, from its top-left corner.
    let grabOffset: CGSize
    /// The pointer, in the grid's space.
    private(set) var pointer: CGPoint
    /// The slot the held tile occupies in `order`.
    private(set) var targetIndex: Int
    /// Whether the tile was let go and is settling into its slot: the pointer no longer moves it.
    private(set) var isSettling = false

    /// Starts a drag of `draggedID` at `start`. Fails when a frame is missing, because the
    /// grid's slots cannot be known then.
    init?(order: [UUID], frames: [UUID: CGRect], draggedID: UUID, start: CGPoint) {
        guard let sourceIndex = order.firstIndex(of: draggedID) else { return nil }
        var slots: [CGRect] = []
        slots.reserveCapacity(order.count)
        for id in order {
            guard let frame = frames[id] else { return nil }
            slots.append(frame)
        }
        self.originalOrder = order
        self.slots = slots
        self.draggedID = draggedID
        self.sourceIndex = sourceIndex
        let held = slots[sourceIndex]
        self.grabOffset = CGSize(width: start.x - held.minX, height: start.y - held.minY)
        self.pointer = start
        self.targetIndex = sourceIndex
    }

    /// The held tile's size: its slot's size.
    var floatingSize: CGSize {
        slots[sourceIndex].size
    }

    /// The held tile's top-left corner while floating, in the grid's space.
    var floatingOrigin: CGPoint {
        CGPoint(x: pointer.x - grabOffset.width, y: pointer.y - grabOffset.height)
    }

    /// The held tile's centre while floating.
    var floatingCenter: CGPoint {
        CGPoint(x: floatingOrigin.x + floatingSize.width / 2, y: floatingOrigin.y + floatingSize.height / 2)
    }

    /// The order the grid shows: the held tile at `targetIndex`, the others closed up around it.
    var order: [UUID] {
        var ids = originalOrder
        ids.remove(at: sourceIndex)
        ids.insert(draggedID, at: targetIndex)
        return ids
    }

    /// Whether letting go now changes the order.
    var changesOrder: Bool {
        targetIndex != sourceIndex
    }

    /// The favorite the held tile lands before in the shared order, or nil when it lands last.
    /// Feeds `BookmarksManager.moveFavorite(_:before:)`.
    var insertionNextID: UUID? {
        let ids = order
        let next = targetIndex + 1
        return ids.indices.contains(next) ? ids[next] : nil
    }

    /// Puts the floating tile exactly on its slot and stops following the pointer.
    mutating func settle() {
        let slot = slots[targetIndex]
        pointer = CGPoint(x: slot.minX + grabOffset.width, y: slot.minY + grabOffset.height)
        isSettling = true
    }

    /// Moves the pointer to `point`. Returns true when the held tile's slot changed.
    @discardableResult
    mutating func move(to point: CGPoint) -> Bool {
        guard !isSettling else { return false }
        pointer = point
        let index = Self.slotIndex(nearest: floatingCenter, in: slots)
        guard index != targetIndex else { return false }
        targetIndex = index
        return true
    }

    /// The slot nearest `point`, the way a grid reads: the nearest row first, then the nearest
    /// slot in that row, so a tile carried past a short last row lands at its end. The first
    /// slot when the slots are empty.
    static func slotIndex(nearest point: CGPoint, in slots: [CGRect]) -> Int {
        guard !slots.isEmpty else { return 0 }
        let rowY = slots.map(\.midY).min { abs($0 - point.y) < abs($1 - point.y) } ?? 0
        var best = 0
        var bestDistance = CGFloat.infinity
        for (index, slot) in slots.enumerated() where abs(slot.midY - rowY) < 0.5 {
            let distance = abs(slot.midX - point.x)
            if distance < bestDistance {
                bestDistance = distance
                best = index
            }
        }
        return best
    }
}
