import CoreGraphics
import Foundation

/// Turns a table's viewport-width units into points on one plane, and answers the questions a
/// scrolling view asks: where a slab is, which slabs a rect shows, where to rest to reveal one.
///
/// The plane has a top-left origin. Rows start at x = 0 and stack downward; an expanded row
/// is the viewport's height, a collapsed one a band. One unit is `viewport.width + gap`, so a
/// row whose fractions sum to 1 fills the viewport exactly with the gap between its slabs,
/// and a full-width slab at rest is the page filling the window.
nonisolated struct TableGeometry: Equatable, Sendable {
    /// The space between slabs and between rows.
    static let gap: CGFloat = 12
    /// A slab's corner, concentric with the window's.
    static let cornerRadius: CGFloat = 12
    /// A collapsed row's height.
    static let bandHeight: CGFloat = 56

    /// One slab the plane shows, with its frame in points.
    struct VisibleSlab: Equatable, Sendable, Identifiable {
        var tabID: UUID
        var position: TableLayout.Position
        var frame: CGRect

        var id: UUID { tabID }
    }

    var viewport: CGSize
    var gap: CGFloat
    var bandHeight: CGFloat

    init(viewport: CGSize, gap: CGFloat = TableGeometry.gap, bandHeight: CGFloat = TableGeometry.bandHeight) {
        self.viewport = viewport
        self.gap = gap
        self.bandHeight = bandHeight
    }

    /// The point length of one viewport-width unit.
    var unit: CGFloat {
        viewport.width + gap
    }

    // MARK: - Rows

    func rowHeight(_ row: TableLayout.Row) -> CGFloat {
        row.isCollapsed ? bandHeight : viewport.height
    }

    /// A row's length in points: its slabs and the gaps between them.
    func rowLength(_ row: TableLayout.Row) -> CGFloat {
        max(0, row.length * unit - gap)
    }

    func rowTop(_ index: Int, in layout: TableLayout) -> CGFloat {
        layout.rows[..<index].reduce(0) { $0 + rowHeight($1) + gap }
    }

    /// A row's frame: its slabs, or its band, which spans the viewport's width.
    func rowFrame(_ index: Int, in layout: TableLayout) -> CGRect {
        let row = layout.rows[index]
        return CGRect(
            x: 0, y: rowTop(index, in: layout),
            width: row.isCollapsed ? viewport.width : rowLength(row),
            height: rowHeight(row),
        )
    }

    /// The empty row below the last one, always there to move a slab into, like Niri's empty
    /// workspace at the end: a viewport tall, the viewport wide.
    func emptyRowFrame(in layout: TableLayout) -> CGRect {
        let top = layout.rows.indices.last.map { rowFrame($0, in: layout).maxY + gap } ?? 0
        return CGRect(x: 0, y: top, width: viewport.width, height: viewport.height)
    }

    /// The whole plane: the longest row across, every row down, and the empty row after them,
    /// never narrower than the viewport, so a short table still rests at its left edge.
    func tableSize(of layout: TableLayout) -> CGSize {
        let width = layout.rows.indices.map { rowFrame($0, in: layout).maxX }.max() ?? 0
        return CGSize(width: max(width, viewport.width), height: emptyRowFrame(in: layout).maxY)
    }

    // MARK: - Slabs

    /// A slab's frame; in a collapsed row, the band's.
    func frame(of position: TableLayout.Position, in layout: TableLayout) -> CGRect {
        let row = layout.rows[position.row]
        guard !row.isCollapsed else { return rowFrame(position.row, in: layout) }
        let slab = row.slabs[position.slab]
        return CGRect(
            x: row.start(of: position.slab) * unit,
            y: rowTop(position.row, in: layout),
            width: slab.fraction * unit - gap,
            height: viewport.height,
        )
    }

    func frame(of tabID: UUID, in layout: TableLayout) -> CGRect? {
        layout.position(of: tabID).map { frame(of: $0, in: layout) }
    }

    /// The slabs of expanded rows that `rect` touches, row by row.
    func slabs(in rect: CGRect, of layout: TableLayout) -> [VisibleSlab] {
        var result: [VisibleSlab] = []
        for (rowIndex, row) in layout.rows.enumerated() where !row.isCollapsed {
            guard rowFrame(rowIndex, in: layout).intersects(rect) else { continue }
            for slabIndex in row.slabs.indices {
                let position = TableLayout.Position(row: rowIndex, slab: slabIndex)
                let frame = frame(of: position, in: layout)
                if frame.intersects(rect) {
                    result.append(VisibleSlab(tabID: row.slabs[slabIndex].tabID, position: position, frame: frame))
                }
            }
        }
        return result
    }

    /// The rows `rect` touches, expanded or collapsed.
    func rows(in rect: CGRect, of layout: TableLayout) -> [Int] {
        layout.rows.indices.filter { rowFrame($0, in: layout).intersects(rect) }
    }

    /// The slab under `point`, or `nil` over a gap, a band, or bare table.
    func slab(at point: CGPoint, in layout: TableLayout) -> TableLayout.Position? {
        slabs(in: CGRect(origin: point, size: CGSize(width: 1, height: 1)), of: layout)
            .first { $0.frame.contains(point) }?.position
    }

    /// The slab showing the most of itself in `rect`; between equals, the one whose center
    /// is nearest the rect's.
    func mostVisibleSlab(in rect: CGRect, of layout: TableLayout) -> TableLayout.Position? {
        var best: (position: TableLayout.Position, area: CGFloat, distance: CGFloat)?
        for slab in slabs(in: rect, of: layout) {
            let shown = slab.frame.intersection(rect)
            let area = shown.width * shown.height
            let distance = hypot(slab.frame.midX - rect.midX, slab.frame.midY - rect.midY)
            if best == nil || area > best!.area + 0.5 || (abs(area - best!.area) <= 0.5 && distance < best!.distance) {
                best = (slab.position, area, distance)
            }
        }
        return best?.position
    }

    // MARK: - Resting

    /// `origin` held on the plane: a viewport never looks past the table's edges.
    func clamped(_ origin: CGPoint, in layout: TableLayout) -> CGPoint {
        let size = tableSize(of: layout)
        return CGPoint(
            x: min(max(origin.x, 0), max(0, size.width - viewport.width)),
            y: min(max(origin.y, 0), max(0, size.height - viewport.height)),
        )
    }

    /// The viewport origin nearest `origin` that shows `frame` whole: the view moves only as
    /// far as it must, on each axis, and a frame larger than the viewport is centered on it.
    func origin(revealing frame: CGRect, from origin: CGPoint, in layout: TableLayout) -> CGPoint {
        func shift(_ low: CGFloat, _ high: CGFloat, _ start: CGFloat, _ length: CGFloat) -> CGFloat {
            if high - low > length {
                return (low + high) / 2 - length / 2 - start
            }
            if low < start {
                return low - start
            }
            return max(0, high - (start + length))
        }
        let revealed = CGPoint(
            x: origin.x + shift(frame.minX, frame.maxX, origin.x, viewport.width),
            y: origin.y + shift(frame.minY, frame.maxY, origin.y, viewport.height),
        )
        return clamped(revealed, in: layout)
    }

    /// Whether `frame` lies entirely inside the viewport at `origin`, to the half point.
    func isWhole(_ frame: CGRect, at origin: CGPoint) -> Bool {
        frame.minX >= origin.x - 0.5 && frame.maxX <= origin.x + viewport.width + 0.5
            && frame.minY >= origin.y - 0.5 && frame.maxY <= origin.y + viewport.height + 0.5
    }
}
