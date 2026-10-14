import CoreGraphics
import Foundation
import SwiftUI

/// Where the window looks onto the table while it moves.
///
/// `row` is the continuous row position: 2 shows row 2 exactly, 2.5 shows the lower half of
/// row 2 above the upper half of row 3. `shift` is a horizontal displacement in points added
/// to every row's resting offset, so a pan slides the whole table and each row keeps its own
/// offset underneath. At rest a layout is seen from `(focusedRow, 0)`.
nonisolated struct TableViewpoint: Equatable, Sendable {
    var row: Double
    var shift: CGFloat

    init(row: Double, shift: CGFloat = 0) {
        self.row = row
        self.shift = shift
    }

    /// The viewpoint of `layout` at rest.
    static func resting(on layout: TableLayout) -> TableViewpoint {
        TableViewpoint(row: Double(layout.focusedRow))
    }
}

/// A slab the viewport shows, with its frame in viewport coordinates.
nonisolated struct TableVisibleSlab: Equatable, Sendable {
    var position: TableLayout.Position
    var tabID: UUID
    /// The slab's frame in the viewport, top-left origin; it may extend past the edges.
    var frame: CGRect
    /// The slab lies entirely inside the viewport: at rest it is live, otherwise a snapshot.
    var isWhole: Bool
}

/// The view math of the table for one viewport size: slab frames, what a viewpoint shows,
/// where a free pan comes to rest, and how an edit is animated.
///
/// Frames on the table are in points with a top-left origin: row `r` spans
/// `r × height ..< (r + 1) × height`, and a slab's x is its start in the row times the
/// viewport width. Viewport frames subtract the row's drawn offset and the row position.
nonisolated struct TableCamera: Equatable, Sendable {
    /// Points of slack when testing whether a slab is whole, absorbing rounding.
    static let wholeTolerance: CGFloat = 0.5

    var viewport: CGSize

    // MARK: - Frames

    /// The slab's width in points.
    func width(of slab: TableLayout.Slab) -> CGFloat {
        CGFloat(slab.fraction) * viewport.width
    }

    /// The slab's frame on the table.
    func tableFrame(of position: TableLayout.Position, in layout: TableLayout) -> CGRect {
        let row = layout.rows[position.row]
        return CGRect(
            x: CGFloat(row.start(of: position.slab)) * viewport.width,
            y: CGFloat(position.row) * viewport.height,
            width: width(of: row.slabs[position.slab]),
            height: viewport.height,
        )
    }

    /// The row's drawn offset in points at `viewpoint`: its resting offset plus the shift.
    func drawnOffset(ofRow index: Int, in layout: TableLayout, at viewpoint: TableViewpoint) -> CGFloat {
        CGFloat(layout.rows[index].offset) * viewport.width + viewpoint.shift
    }

    /// The slabs the viewport shows at `viewpoint`, top row first, left to right.
    func visibleSlabs(in layout: TableLayout, at viewpoint: TableViewpoint) -> [TableVisibleSlab] {
        guard !layout.rows.isEmpty else { return [] }
        let bounds = CGRect(origin: .zero, size: viewport)
        let first = max(Int(viewpoint.row.rounded(.down)), 0)
        let last = min(Int(viewpoint.row.rounded(.up)), layout.rows.count - 1)
        guard first <= last else { return [] }

        var result: [TableVisibleSlab] = []
        for rowIndex in first ... last {
            let offset = drawnOffset(ofRow: rowIndex, in: layout, at: viewpoint)
            let y = CGFloat(Double(rowIndex) - viewpoint.row) * viewport.height
            for slabIndex in layout.rows[rowIndex].slabs.indices {
                let position = TableLayout.Position(row: rowIndex, slab: slabIndex)
                var frame = tableFrame(of: position, in: layout)
                frame.origin = CGPoint(x: frame.minX - offset, y: y)
                let visible = frame.intersection(bounds)
                guard !visible.isNull, visible.width > Self.wholeTolerance, visible.height > Self.wholeTolerance else { continue }
                result.append(TableVisibleSlab(
                    position: position,
                    tabID: layout[position].tabID,
                    frame: frame,
                    isWhole: bounds.insetBy(dx: -Self.wholeTolerance, dy: -Self.wholeTolerance).contains(frame),
                ))
            }
        }
        return result
    }

    /// The slabs that are live when `layout` is at rest: those of the current row fully in
    /// view. The rest of the visible slabs stay snapshots.
    func liveSlabs(in layout: TableLayout) -> [TableLayout.Position] {
        visibleSlabs(in: layout, at: .resting(on: layout)).filter(\.isWhole).map(\.position)
    }

    // MARK: - Panning

    /// The viewpoint after a free pan by `delta` points, following `NSEvent.scrollingDelta`:
    /// positive y reveals the row above, positive x the slabs to the left. The row stays
    /// within the table and the current row's drawn offset within its resting range.
    func panned(_ viewpoint: TableViewpoint, by delta: CGSize, in layout: TableLayout) -> TableViewpoint {
        guard !layout.rows.isEmpty, viewport.width > 0, viewport.height > 0 else { return viewpoint }
        var result = viewpoint
        result.row = min(max(viewpoint.row - Double(delta.height / viewport.height), 0), Double(layout.rows.count - 1))
        let anchor = layout.rows[anchorRow(of: result, in: layout)]
        let base = CGFloat(anchor.offset) * viewport.width
        let shifted = base + viewpoint.shift - delta.width
        let clamped = min(max(shifted, 0), CGFloat(anchor.maxOffset) * viewport.width)
        result.shift = clamped - base
        return result
    }

    /// The row a viewpoint snaps to: the nearest one on the table.
    func anchorRow(of viewpoint: TableViewpoint, in layout: TableLayout) -> Int {
        min(max(Int(viewpoint.row.rounded()), 0), max(layout.rows.count - 1, 0))
    }

    // MARK: - Resting

    /// Where the view settles after a free pan ends at `viewpoint`, row first, then slab.
    ///
    /// The row is the nearest one. In it, the slab closest to the viewport's center is made
    /// whole by Niri's on-overflow rule: when it fits beside the neighbor that shares the
    /// view, both stay in view with the least movement; otherwise the slab is centered. The
    /// row's remembered slab stays current if it is whole there; otherwise the centered slab
    /// becomes current. `nil` for an empty table.
    func restingTarget(in layout: TableLayout, from viewpoint: TableViewpoint) -> TableRest? {
        guard !layout.rows.isEmpty, viewport.width > 0 else { return nil }
        let rowIndex = anchorRow(of: viewpoint, in: layout)
        let row = layout.rows[rowIndex]
        let current = row.clamped(row.offset + Double(viewpoint.shift / viewport.width))
        let target = slabNearestCenter(of: row, at: current)
        let offset = row.clamped(restingOffset(showing: target, in: row, from: current))
        let focused = row.isWhole(row.focusedSlab, at: offset) ? row.focusedSlab : target
        return TableRest(row: rowIndex, offset: offset, focusedSlab: focused)
    }

    /// The viewpoint, in `layout`'s terms, that shows the table as `rest` will.
    func viewpoint(for rest: TableRest, in layout: TableLayout) -> TableViewpoint {
        guard layout.rows.indices.contains(rest.row) else { return .resting(on: layout) }
        let shift = CGFloat(rest.offset - layout.rows[rest.row].offset) * viewport.width
        return TableViewpoint(row: Double(rest.row), shift: shift)
    }

    /// The offset change, in viewport widths, that brings the slab at `position` whole into
    /// view with the least movement: 0 when it is already whole.
    func revealDelta(for position: TableLayout.Position, in layout: TableLayout) -> Double {
        let row = layout.rows[position.row]
        return row.offset(revealing: position.slab, from: row.offset) - row.offset
    }

    /// The starting viewpoint for animating an edit from `old` to `new`: in `new`'s terms,
    /// it shows what `old` showed at rest, so springing to ``TableViewpoint/resting(on:)`` of
    /// `new` moves the view from where it was. Rows are matched by ID; when the old current
    /// row is gone the animation starts from the new current row.
    func transition(from old: TableLayout, to new: TableLayout) -> TableViewpoint {
        guard old.rows.indices.contains(old.focusedRow) else { return .resting(on: new) }
        let oldRow = old.rows[old.focusedRow]
        guard let newIndex = new.rows.firstIndex(where: { $0.id == oldRow.id }) else {
            return .resting(on: new)
        }
        let shift = CGFloat(oldRow.offset - new.rows[newIndex].offset) * viewport.width
        return TableViewpoint(row: Double(newIndex), shift: shift)
    }

    // MARK: - Private

    private func slabNearestCenter(of row: TableLayout.Row, at offset: Double) -> Int {
        let center = offset + 0.5
        var best = 0
        var bestDistance = Double.infinity
        for index in row.slabs.indices {
            let distance = abs(row.start(of: index) + row.slabs[index].fraction / 2 - center)
            if distance < bestDistance - TableLayout.tolerance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }

    private func restingOffset(showing index: Int, in row: TableLayout.Row, from offset: Double) -> Double {
        guard let neighbor = sharingNeighbor(of: index, in: row, at: offset) else {
            return row.offset(revealing: index, from: offset)
        }
        let low = max(row.end(of: index), row.end(of: neighbor)) - 1
        let high = min(row.start(of: index), row.start(of: neighbor))
        if low <= high + TableLayout.tolerance {
            return min(max(offset, low), max(low, high))
        }
        return row.start(of: index) + row.slabs[index].fraction / 2 - 0.5
    }

    /// The neighbor of `index` with more of itself in view at `offset`, or `nil` when
    /// neither shows.
    private func sharingNeighbor(of index: Int, in row: TableLayout.Row, at offset: Double) -> Int? {
        func visibleLength(_ neighbor: Int) -> Double {
            guard row.slabs.indices.contains(neighbor) else { return 0 }
            return max(0, min(row.end(of: neighbor), offset + 1) - max(row.start(of: neighbor), offset))
        }
        let left = visibleLength(index - 1)
        let right = visibleLength(index + 1)
        guard max(left, right) > TableLayout.tolerance else { return nil }
        return right > left ? index + 1 : index - 1
    }
}

/// A queue of discrete wheel steps: each notch moves focus one slab or one row, notches
/// accumulate while the view is moving, and the queue resolves to the layout they lead to.
///
/// Steps that would run past the table's edge are dropped, and a step against the last
/// pending one cancels it.
nonisolated struct TableStepQueue: Equatable, Sendable {
    /// The time each queued step holds the view before the next one starts.
    static let stepInterval: TimeInterval = 0.12

    private(set) var pending: [TableDirection] = []

    var isEmpty: Bool {
        pending.isEmpty
    }

    /// Queues one notch, measured against `layout` with the steps already pending.
    mutating func push(_ step: TableDirection, from layout: TableLayout) {
        if pending.last == step.opposite {
            pending.removeLast()
            return
        }
        let end = resolved(from: layout)
        guard end.movingFocus(step).focus != end.focus else { return }
        pending.append(step)
    }

    /// Takes the next step to animate, or `nil` when the queue is empty.
    mutating func next() -> TableDirection? {
        pending.isEmpty ? nil : pending.removeFirst()
    }

    mutating func removeAll() {
        pending.removeAll()
    }

    /// The layout after every pending step, applied to `layout` in order.
    func resolved(from layout: TableLayout) -> TableLayout {
        pending.reduce(layout) { $0.movingFocus($1) }
    }
}

/// The spring that carries the table to rest: critically damped, so it settles without
/// bouncing.
nonisolated enum TableSpring {
    /// Seconds for the spring to complete most of its motion.
    static let response: Double = 0.3
    /// 1 is critical damping: the fastest approach with no overshoot.
    static let dampingFraction: Double = 1
    /// Motion below this many points, and speed below this many points a second, is at rest.
    static let restThreshold: Double = 0.5

    static var angularFrequency: Double {
        2 * .pi / response
    }

    /// The SwiftUI animation with the same parameters.
    static var animation: Animation {
        .spring(response: response, dampingFraction: dampingFraction)
    }

    /// The value at `time` seconds of a critically damped spring from `start` to `target`
    /// that begins with `velocity` units per second.
    static func value(from start: Double, to target: Double, velocity: Double = 0, at time: Double) -> Double {
        let omega = angularFrequency
        let displacement = start - target
        let t = max(time, 0)
        return target + (displacement + (velocity + omega * displacement) * t) * exp(-omega * t)
    }

    /// The spring's velocity at `time`, in units per second.
    static func velocity(from start: Double, to target: Double, velocity: Double = 0, at time: Double) -> Double {
        let omega = angularFrequency
        let displacement = start - target
        let t = max(time, 0)
        let slope = velocity + omega * displacement
        return (slope - omega * (displacement + slope * t)) * exp(-omega * t)
    }

    /// The viewpoint `elapsed` seconds into the spring from `start` to `target`, with an
    /// initial velocity in rows and points per second.
    static func interpolate(
        from start: TableViewpoint,
        to target: TableViewpoint,
        velocity: TableViewpoint = TableViewpoint(row: 0),
        elapsed: TimeInterval,
    ) -> TableViewpoint {
        TableViewpoint(
            row: value(from: start.row, to: target.row, velocity: velocity.row, at: elapsed),
            shift: CGFloat(value(from: Double(start.shift), to: Double(target.shift), velocity: Double(velocity.shift), at: elapsed)),
        )
    }

    /// Whether the spring has settled `elapsed` seconds in, for a viewport `rowHeight` tall:
    /// both axes within ``restThreshold`` points of the target and slower than it per second.
    static func isSettled(
        from start: TableViewpoint,
        to target: TableViewpoint,
        velocity: TableViewpoint = TableViewpoint(row: 0),
        elapsed: TimeInterval,
        rowHeight: CGFloat,
    ) -> Bool {
        let height = Double(rowHeight)
        let current = interpolate(from: start, to: target, velocity: velocity, elapsed: elapsed)
        let rowSpeed = self.velocity(from: start.row, to: target.row, velocity: velocity.row, at: elapsed) * height
        let shiftSpeed = self.velocity(from: Double(start.shift), to: Double(target.shift), velocity: Double(velocity.shift), at: elapsed)
        return abs(current.row - target.row) * height < restThreshold
            && abs(Double(current.shift - target.shift)) < restThreshold
            && abs(rowSpeed) < restThreshold
            && abs(shiftSpeed) < restThreshold
    }
}
