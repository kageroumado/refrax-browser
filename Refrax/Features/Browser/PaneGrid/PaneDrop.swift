import CoreGraphics
import Foundation

/// Where something dragged over a tab's panes lands: a page joining the tab (from an island
/// row), or a pane moved in layout mode.
nonisolated enum PaneDrop {
    /// The share of a pane's width or height, at each of its sides, where a joining page
    /// takes that side.
    static let edgeShare: CGFloat = 0.28

    /// Where a page dropped at `point` joins the grid: an empty cell under the point while
    /// the grid is being edited, else the side of the pane under the point the point is
    /// nearest, within ``edgeShare`` of it, when that pane can be halved there.
    ///
    /// - Returns: nil when the grid is full, the point is in no pane, or it rests in a pane's
    ///   middle.
    static func placement(at point: CGPoint, in grid: PaneGrid, geometry: PaneGridGeometry) -> PanePlacement? {
        guard grid.hasRoom else { return nil }
        if let cell = geometry.cell(at: point), grid.page(at: cell) == nil {
            return .cell(cell)
        }
        for (pageID, span) in grid.spans {
            let frame = geometry.frame(of: span)
            guard frame.contains(point), frame.width > 0, frame.height > 0 else { continue }
            let reach: [(PaneEdge, CGFloat)] = [
                (.leading, (point.x - frame.minX) / frame.width),
                (.trailing, (frame.maxX - point.x) / frame.width),
                (.top, (point.y - frame.minY) / frame.height),
                (.bottom, (frame.maxY - point.y) / frame.height),
            ]
            let nearest = reach
                .filter { $0.1 < edgeShare && span.canHalve(at: $0.0) }
                .min { $0.1 < $1.1 }
            return nearest.map { PanePlacement.split(PaneSplit(target: pageID, edge: $0.0)) }
        }
        return nil
    }

    /// The frame the joining page will have at `placement`, to show where it lands.
    static func frame(of placement: PanePlacement, joining pageID: UUID, in grid: PaneGrid, geometry: PaneGridGeometry) -> CGRect? {
        guard let span = grid.inserting(pageID, at: placement)?.span(of: pageID) else { return nil }
        return geometry.frame(of: span)
    }

    /// The cell a pane dragged in layout mode lands on: the cell under the pane's center,
    /// `translation` from where it rests. Nil while the center is over the pane's own cells
    /// or off the grid, where letting go puts it back.
    static func cell(forDragging pageID: UUID, by translation: CGSize, in grid: PaneGrid, geometry: PaneGridGeometry) -> GridCell? {
        guard let span = grid.span(of: pageID) else { return nil }
        let frame = geometry.frame(of: span)
        let center = CGPoint(x: frame.midX + translation.width, y: frame.midY + translation.height)
        guard let cell = geometry.cell(at: center), !span.contains(cell) else { return nil }
        return cell
    }
}
