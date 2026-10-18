import CoreGraphics
import Foundation

/// Turns an island's cells into points: chip frames inside the island, the island's size,
/// and how much of it the window lets it show.
///
/// A cell is one title chip. Icon-only islands use square cells. A preview chip spans a
/// rectangle of cells, so its frame is that rectangle plus the gaps inside it.
nonisolated struct IslandGeometry: Equatable, Sendable {
    /// A title cell: favicon, a short title, and room for the pointer.
    static let titleCell = CGSize(width: 168, height: 34)
    /// An icon cell: the favorites column's square.
    static let iconCell = CGSize(width: 34, height: 34)
    /// The gap between chips.
    static let gap: CGFloat = 6
    /// The island's padding around its chips, and the footer's height.
    static let padding: CGFloat = 10
    static let footerHeight: CGFloat = 28
    /// The Control Island's corner.
    static let cornerRadius: CGFloat = ControlIslandPlacement.cornerRadius
    /// The chips' corner, concentric with the island's.
    static let chipCornerRadius: CGFloat = cornerRadius - padding
    /// The largest share of the window an island takes before it scrolls inside.
    static let maximumShare: CGFloat = 0.4
    /// Preview presets, in cells of a title island: small, medium, large.
    static let previewSpans: [IslandSpan] = [
        IslandSpan(width: 2, height: 6), IslandSpan(width: 3, height: 9), IslandSpan(width: 4, height: 12),
    ]

    var cell: CGSize

    init(iconsOnly: Bool) {
        cell = iconsOnly ? Self.iconCell : Self.titleCell
    }

    /// The frame of a chip's cells, relative to the island's grid origin at cell (0, 0),
    /// before the island's padding.
    func frame(of chip: ChipPlacement, in layout: IslandLayout) -> CGRect {
        guard let bounds = layout.bounds else { return .zero }
        let x = CGFloat(chip.cell.x - bounds.minX) * (cell.width + Self.gap)
        let y = CGFloat(chip.cell.y - bounds.minY) * (cell.height + Self.gap)
        let width = CGFloat(chip.span.width) * cell.width + CGFloat(chip.span.width - 1) * Self.gap
        let height = CGFloat(chip.span.height) * cell.height + CGFloat(chip.span.height - 1) * Self.gap
        return CGRect(x: x + Self.padding, y: y + Self.padding, width: width, height: height)
    }

    /// The size of the whole grid with the island's padding and footer.
    func contentSize(of layout: IslandLayout) -> CGSize {
        guard let bounds = layout.bounds else {
            return CGSize(width: cell.width + 2 * Self.padding, height: cell.height + 2 * Self.padding + Self.footerHeight)
        }
        let columns = CGFloat(bounds.maxX - bounds.minX + 1)
        let rows = CGFloat(bounds.maxY - bounds.minY + 1)
        return CGSize(
            width: columns * cell.width + (columns - 1) * Self.gap + 2 * Self.padding,
            height: rows * cell.height + (rows - 1) * Self.gap + 2 * Self.padding + Self.footerHeight,
        )
    }

    /// The island's size on screen: its content, held to the window's share. Past that the
    /// grid scrolls inside.
    func islandSize(of layout: IslandLayout, in window: CGSize) -> CGSize {
        let content = contentSize(of: layout)
        return CGSize(
            width: min(content.width, max(cell.width + 2 * Self.padding, window.width * Self.maximumShare)),
            height: min(content.height, max(cell.height + 2 * Self.padding + Self.footerHeight, window.height * Self.maximumShare)),
        )
    }

    /// The cell under `point`, relative to the island's grid origin, whether or not a chip
    /// is there.
    func cell(at point: CGPoint, in layout: IslandLayout) -> IslandCell {
        let bounds = layout.bounds ?? (0, 0, 0, 0)
        let x = Int(((point.x - Self.padding) / (cell.width + Self.gap)).rounded(.down))
        let y = Int(((point.y - Self.padding) / (cell.height + Self.gap)).rounded(.down))
        return IslandCell(x: x + bounds.minX, y: y + bounds.minY)
    }
}
