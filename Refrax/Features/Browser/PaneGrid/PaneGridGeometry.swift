import CoreGraphics

/// The spacing of a pane grid: how far the panes stand from each other and from the page's
/// edges, and how round their corners are.
nonisolated struct PaneGridMetrics: Equatable, Sendable {
    /// Between two panes; on the page the divider line fills it.
    let gap: CGFloat
    /// Between the panes and the page's edges.
    let inset: CGFloat
    /// The panes' own corners; the window's corners round the page's.
    let cornerRadius: CGFloat

    /// The page as people use it: panes edge to edge, a one-point divider between them.
    static let page = PaneGridMetrics(gap: 1, inset: 0, cornerRadius: 0)

    /// Layout mode: panes lifted apart, their corners concentric with the window's.
    static let editing = PaneGridMetrics(gap: 8, inset: 8, cornerRadius: WindowCorner.radius - 8)
}

/// The line between two columns or two rows of panes, drawn in the gap between them.
nonisolated struct PaneDivider: Hashable, Sendable {
    nonisolated enum Axis: Hashable, Sendable {
        /// A vertical line between the leading and trailing columns.
        case column
        /// A horizontal line between the top and bottom rows.
        case row
    }

    let axis: Axis
    /// The line: exactly the gap between the panes on either side, in whole points.
    let frame: CGRect

    /// Where a drag takes hold of the line: the line widened to `reach` across it.
    func grabFrame(reach: CGFloat) -> CGRect {
        switch axis {
        case .column: frame.insetBy(dx: -(reach - frame.width) / 2, dy: 0)
        case .row: frame.insetBy(dx: 0, dy: -(reach - frame.height) / 2)
        }
    }
}

/// Where a tab's panes stand in a page of a given size: every pane, divider, and cell frame,
/// in whole points.
///
/// The page's area (``content``) is the bounds less the inset, its near edges rounded to the
/// nearest point and its far edges down. Each split puts its line at a whole point, so every
/// pane's origin and size are whole points and two neighbors are exactly ``PaneGridMetrics/gap``
/// apart: nothing WebKit lays out at a fractional size, nothing of a page under a divider.
nonisolated struct PaneGridGeometry: Equatable, Sendable {
    let bounds: CGRect
    /// The share of the width left of the column line.
    let columnSplit: CGFloat
    /// The share of the height above the row line.
    let rowSplit: CGFloat
    let metrics: PaneGridMetrics

    init(bounds: CGRect, columnSplit: Double, rowSplit: Double, metrics: PaneGridMetrics) {
        self.bounds = bounds
        self.columnSplit = CGFloat(PaneSplitRatio.clamped(columnSplit))
        self.rowSplit = CGFloat(PaneSplitRatio.clamped(rowSplit))
        self.metrics = metrics
    }

    init(size: CGSize, columnSplit: Double, rowSplit: Double, metrics: PaneGridMetrics) {
        self.init(bounds: CGRect(origin: .zero, size: size), columnSplit: columnSplit, rowSplit: rowSplit, metrics: metrics)
    }

    /// A geometry for `configuration`'s splits; a page without one divides in the middle.
    init(size: CGSize, configuration: LayoutConfiguration?, metrics: PaneGridMetrics) {
        self.init(
            size: size, columnSplit: configuration?.horizontalDivider ?? 0.5, rowSplit: configuration?.verticalDivider ?? 0.5,
            metrics: metrics,
        )
    }

    // MARK: - Lines

    /// The area the panes share, in whole points.
    var content: CGRect {
        let minX = (bounds.minX + metrics.inset).rounded()
        let minY = (bounds.minY + metrics.inset).rounded()
        let maxX = max(minX, (bounds.maxX - metrics.inset).rounded(.down))
        let maxY = max(minY, (bounds.maxY - metrics.inset).rounded(.down))
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Where the leading column ends; the gap runs from here.
    var columnLine: CGFloat {
        let content = content
        return Self.line(from: content.minX, length: content.width, gap: metrics.gap, split: columnSplit)
    }

    /// Where the top row ends; the gap runs from here.
    var rowLine: CGFloat {
        let content = content
        return Self.line(from: content.minY, length: content.height, gap: metrics.gap, split: rowSplit)
    }

    private static func line(from start: CGFloat, length: CGFloat, gap: CGFloat, split: CGFloat) -> CGFloat {
        let usable = max(0, length - gap)
        return start + (usable * split).rounded()
    }

    // MARK: - Frames

    /// The frame of a pane covering `span`.
    func frame(of span: PaneSpan) -> CGRect {
        let content = content
        let column = columnLine
        let row = rowLine
        let minX = span.columns.lowerBound == 0 ? content.minX : column + metrics.gap
        let maxX = span.columns.upperBound == 0 ? column : content.maxX
        let minY = span.rows.lowerBound == 0 ? content.minY : row + metrics.gap
        let maxY = span.rows.upperBound == 0 ? row : content.maxY
        return CGRect(x: minX, y: minY, width: max(0, maxX - minX), height: max(0, maxY - minY))
    }

    func frame(of cell: GridCell) -> CGRect {
        frame(of: PaneSpan(cell))
    }

    /// Every page's pane frame.
    func frames(for grid: PaneGrid) -> [UUID: CGRect] {
        grid.spans.mapValues(frame(of:))
    }

    /// The cell whose frame, widened to the middle of the gaps, holds `point`; nil outside
    /// the content.
    func cell(at point: CGPoint) -> GridCell? {
        let content = content
        guard content.contains(point) else { return nil }
        let column = point.x < columnLine + metrics.gap / 2 ? 0 : 1
        let row = point.y < rowLine + metrics.gap / 2 ? 0 : 1
        return GridCell(column: column, row: row)
    }

    // MARK: - Dividers

    /// The lines between neighboring panes of a complete grid: the column line runs along
    /// each row whose two cells hold different pages, the row line along each such column.
    func dividers(for grid: PaneGrid) -> [PaneDivider] {
        guard grid.count > 1 else { return [] }
        let content = content
        let column = columnLine
        let row = rowLine
        let gap = metrics.gap
        func differ(_ a: GridCell, _ b: GridCell) -> Bool {
            guard let first = grid.page(at: a), let second = grid.page(at: b) else { return false }
            return first != second
        }
        var dividers: [PaneDivider] = []
        let topSplit = differ(.topLeft, .topRight)
        let bottomSplit = differ(.bottomLeft, .bottomRight)
        if topSplit || bottomSplit {
            let minY = topSplit ? content.minY : row + gap
            let maxY = bottomSplit ? content.maxY : row
            dividers.append(PaneDivider(axis: .column, frame: CGRect(x: column, y: minY, width: gap, height: maxY - minY)))
        }
        let leadingSplit = differ(.topLeft, .bottomLeft)
        let trailingSplit = differ(.topRight, .bottomRight)
        if leadingSplit || trailingSplit {
            let minX = leadingSplit ? content.minX : column + gap
            let maxX = trailingSplit ? content.maxX : column
            dividers.append(PaneDivider(axis: .row, frame: CGRect(x: minX, y: row, width: maxX - minX, height: gap)))
        }
        return dividers
    }

    /// The split a divider dragged to `location` (an x for the column line, a y for the row
    /// line) sets: the line centered under the pointer, held between the ratio's limits.
    func split(for axis: PaneDivider.Axis, at location: CGFloat) -> Double {
        let content = content
        let start = axis == .column ? content.minX : content.minY
        let length = axis == .column ? content.width : content.height
        let usable = max(1, length - metrics.gap)
        return PaneSplitRatio.clamped(Double((location - metrics.gap / 2 - start) / usable))
    }
}

/// The limits and resting points of a split ratio.
nonisolated enum PaneSplitRatio {
    /// No pane narrower than a fifth of the page.
    static let range: ClosedRange<Double> = 0.2 ... 0.8
    /// Ratios a released divider settles on when it is let go near one.
    static let restingPoints: [Double] = [0.5, 1.0 / 3.0, 2.0 / 3.0]
    /// How near counts as near.
    static let restingReach = 0.03

    static func clamped(_ ratio: Double) -> Double {
        guard ratio.isFinite else { return 0.5 }
        return min(max(ratio, range.lowerBound), range.upperBound)
    }

    /// The ratio a divider let go at `ratio` rests at.
    static func settled(_ ratio: Double) -> Double {
        let clamped = clamped(ratio)
        return restingPoints.first { abs($0 - clamped) < restingReach } ?? clamped
    }
}
