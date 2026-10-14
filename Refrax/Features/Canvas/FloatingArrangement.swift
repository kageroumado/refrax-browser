import CoreGraphics

/// The ways Arrange lays out the floating layer of a space.
nonisolated enum FloatingArrangement: String, CaseIterable, Hashable, Sendable {
    /// Every placed card in columns from the island's side, most recent first.
    case grid
    /// Cards from one site gathered into a folded group named by the site.
    case stacksBySite
    /// Every group folded to its header.
    case stacksByGroup

    var title: String {
        switch self {
        case .grid: "Grid"
        case .stacksBySite: "Stacks by Site"
        case .stacksByGroup: "Stacks by Group"
        }
    }

    var symbol: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .stacksBySite: "square.stack.3d.up"
        case .stacksByGroup: "rectangle.stack"
        }
    }

    /// The Command Lens command for the arrangement.
    var commandTitle: String {
        switch self {
        case .grid: "Arrange in Grid"
        case .stacksBySite: "Stack by Site"
        case .stacksByGroup: "Stack by Group"
        }
    }

    // MARK: - Geometry

    /// The space between cells.
    static let gap: CGFloat = 12
    /// The window margin around arranged cards.
    static let margin: CGFloat = 16

    /// The area cards are arranged in: the window inside its margin, beside the island's rail
    /// on the side away from it.
    static func arrangeArea(in bounds: CGRect, rail: CGRect) -> CGRect {
        let area = bounds.insetBy(dx: margin, dy: margin)
        guard !rail.isEmpty, rail.intersects(bounds) else { return area }
        if rail.midX <= bounds.midX {
            let minX = min(area.maxX, max(area.minX, rail.maxX + gap))
            return CGRect(x: minX, y: area.minY, width: area.maxX - minX, height: area.height)
        }
        let maxX = max(area.minX, min(area.maxX, rail.minX - gap))
        return CGRect(x: area.minX, y: area.minY, width: maxX - area.minX, height: area.height)
    }

    /// Whether arranged cards fill from the trailing edge: the island sits on the trailing side.
    static func fillsFromTrailing(bounds: CGRect, rail: CGRect) -> Bool {
        !rail.isEmpty && rail.midX > bounds.midX
    }

    /// Origins for cells of `sizes`, in order, on a grid of columns as wide as the widest
    /// cell: each column fills top to bottom, and columns advance away from the island's side.
    /// A cell whose cards reach further down than the cell itself (a folded stack's header over
    /// its pile) starts a new column unless its `reaches` fit, so placement never clamps the
    /// pile and moves the header. Columns past the area's far edge keep going; placement
    /// clamps them into the window.
    static func gridOrigins(for sizes: [CGSize], reaching reaches: [CGSize]? = nil, in area: CGRect, fromTrailing: Bool) -> [CGPoint] {
        guard let columnWidth = sizes.map(\.width).max() else { return [] }
        var origins: [CGPoint] = []
        var column = 0
        var y = area.minY
        for (index, size) in sizes.enumerated() {
            let reach = max(size.height, reaches.flatMap { $0.indices.contains(index) ? $0[index].height : nil } ?? 0)
            if y > area.minY, y + reach > area.maxY {
                column += 1
                y = area.minY
            }
            let offset = CGFloat(column) * (columnWidth + gap)
            let x = fromTrailing ? area.maxX - offset - columnWidth : area.minX + offset
            origins.append(CGPoint(x: x, y: y))
            y += size.height + gap
        }
        return origins
    }

    /// The first cell of the arrange grid where a card of `size` keeps a gap from every frame
    /// in `taken`: the column beside the island first, top to bottom, then the next one out.
    /// Returns `nil` when every cell in `area` is taken.
    static func freeCell(for size: CGSize, avoiding taken: [CGRect], in area: CGRect, fromTrailing: Bool) -> CGPoint? {
        guard size.width > 0, size.height > 0, size.width.isFinite, size.height.isFinite else { return nil }
        let rows = max(1, Int((area.height + gap) / (size.height + gap)))
        let columns = max(1, Int((area.width + gap) / (size.width + gap)))
        let origins = gridOrigins(for: Array(repeating: size, count: rows * columns), in: area, fromTrailing: fromTrailing)
        // Half a point of slack lets a card sit exactly one gap from its neighbor.
        let clearance = gap - 0.5
        return origins.first { origin in
            let cell = CGRect(origin: origin, size: size)
            return !taken.contains { !$0.isEmpty && $0.insetBy(dx: -clearance, dy: -clearance).intersects(cell) }
        }
    }

    /// Items by site, keeping only sites with two or more items: those become stacks. Each
    /// stack lists its items in the order given; sites come out in the order of their first item.
    static func siteStacks<ID: Hashable>(_ items: [(id: ID, site: String?)]) -> [(site: String, ids: [ID])] {
        var order: [String] = []
        var members: [String: [ID]] = [:]
        for item in items {
            guard let site = item.site, !site.isEmpty else { continue }
            if members[site] == nil {
                order.append(site)
            }
            members[site, default: []].append(item.id)
        }
        return order.compactMap { site in
            guard let ids = members[site], ids.count > 1 else { return nil }
            return (site, ids)
        }
    }

    /// The translation that keeps a dragged selection's `bounds` inside `area`.
    static func clampedTranslation(_ translation: CGSize, moving bounds: CGRect, in area: CGRect) -> CGSize {
        CGSize(
            width: min(max(translation.width, area.minX - bounds.minX), area.maxX - bounds.maxX),
            height: min(max(translation.height, area.minY - bounds.minY), area.maxY - bounds.maxY),
        )
    }

    /// Where a selection's options capsule of `size` goes: centered under the selection, or
    /// above it when there is no room below, always inside `area`.
    static func capsuleOrigin(for selection: CGRect, size: CGSize, in area: CGRect) -> CGPoint {
        let below = selection.maxY + gap
        let y = below + size.height <= area.maxY ? below : max(area.minY, selection.minY - gap - size.height)
        let x = min(max(area.minX, selection.midX - size.width / 2), max(area.minX, area.maxX - size.width))
        return CGPoint(x: x, y: y)
    }
}
