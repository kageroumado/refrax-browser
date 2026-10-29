import CoreGraphics

/// Where an island made by a drop goes: the frame its ghost shows while the row travels, and
/// the placement that lays the island out there once the row is let go.
nonisolated enum IslandDropPlacement {
    /// The full frame, header included, of an island of `rows` rows let go at `point`: the
    /// pointer on the middle of its first row, the whole held inside `area`, so the ghost
    /// stands where the island will really be. `window` is the size the island's height is
    /// shared from, as the layer lays it out.
    static func frame(at point: CGPoint, rows: Int, geometry: IslandGeometry, area: CGRect, window: CGSize) -> CGRect {
        let size = geometry.size(rows: rows, in: window)
        let reserve = IslandGeometry.headerReserve
        let full = CGSize(width: size.width, height: size.height + reserve)
        var origin = CGPoint(
            x: point.x - full.width / 2,
            y: point.y - reserve - IslandGeometry.padding - geometry.cellHeight / 2,
        )
        origin.x = min(max(area.minX, origin.x), max(area.minX, area.maxX - full.width))
        origin.y = min(max(area.minY, origin.y), max(area.minY, area.maxY - full.height))
        return CGRect(origin: origin, size: full)
    }

    /// The placement that lays an island of titles out at `frame`, normalized to `area` the
    /// way the layer reads it back: its rows start a header below the frame's top.
    static func placement(for frame: CGRect, in area: CGRect) -> IslandPlacement {
        IslandPlacement(
            x: min(1, max(0, (frame.minX - area.minX) / max(1, area.width))),
            y: min(1, max(0, (frame.minY + IslandGeometry.headerReserve - area.minY) / max(1, area.height))),
        )
    }

    /// Where the one-time hint stands beside the loose tabs' island: to its right on its
    /// header's line, below it when the right has no room, else to its left.
    static func hintOrigin(beside island: CGRect, size: CGSize, gap: CGFloat, in area: CGRect) -> CGPoint {
        if island.maxX + gap + size.width <= area.maxX {
            return CGPoint(x: island.maxX + gap, y: island.minY)
        }
        if island.maxY + gap + size.height <= area.maxY {
            return CGPoint(x: min(island.minX, area.maxX - size.width), y: island.maxY + gap)
        }
        return CGPoint(x: max(area.minX, island.minX - gap - size.width), y: island.minY)
    }
}
