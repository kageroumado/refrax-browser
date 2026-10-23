import CoreGraphics
import Foundation

/// Turns an island's rows into points: the island's size, each row's frame, and the row a
/// point falls on.
///
/// An island is a band and a column of rows inside the Control Island's corner. The band
/// holds the island's color and, under the pointer, its controls; the rows are the tabs.
nonisolated struct IslandGeometry: Equatable, Sendable {
    static let rowHeight: CGFloat = 30
    /// The width of an island of titles, and of one of icons alone.
    static let titleWidth: CGFloat = 236
    static let iconWidth: CGFloat = 46
    static let padding: CGFloat = 8
    /// The band above the rows: the island's color, and its controls under the pointer.
    static let bandHeight: CGFloat = 26
    /// The Control Island's corner.
    static let cornerRadius: CGFloat = ControlIslandPlacement.cornerRadius
    static let rowCornerRadius: CGFloat = 8
    /// The largest share of the window's height an island takes before its rows scroll.
    static let maximumShare: CGFloat = 0.4

    var iconsOnly: Bool

    var width: CGFloat {
        iconsOnly ? Self.iconWidth : Self.titleWidth
    }

    /// The height of the band, `rows` rows, the new-tab row, and the padding.
    func contentHeight(rows: Int) -> CGFloat {
        Self.bandHeight + CGFloat(rows + 1) * Self.rowHeight + 2 * Self.padding
    }

    /// The island's size on screen: its content, held to the window's share.
    func size(rows: Int, in window: CGSize) -> CGSize {
        let least = contentHeight(rows: 1)
        return CGSize(width: width, height: min(contentHeight(rows: rows), max(least, window.height * Self.maximumShare)))
    }

    /// Row `index`'s frame in the island, before any scrolling.
    func rowFrame(_ index: Int) -> CGRect {
        CGRect(
            x: Self.padding, y: Self.bandHeight + Self.padding + CGFloat(index) * Self.rowHeight,
            width: width - 2 * Self.padding, height: Self.rowHeight,
        )
    }

    /// Where a row dropped at `point` goes among `count` rows: before the row whose top half it
    /// is on, after the one whose bottom half, so 0 through `count`.
    func insertion(at point: CGPoint, count: Int) -> Int {
        let y = point.y - Self.bandHeight - Self.padding
        return min(count, max(0, Int((y / Self.rowHeight).rounded())))
    }

    /// The row `point` is on, when it is on one's middle: a drop there joins that row's tab
    /// instead of landing beside it.
    func joinedRow(at point: CGPoint, count: Int) -> Int? {
        let y = point.y - Self.bandHeight - Self.padding
        guard y >= 0 else { return nil }
        let row = Int(y / Self.rowHeight)
        let within = (y - CGFloat(row) * Self.rowHeight) / Self.rowHeight
        guard row < count, within > Self.joinBand, within < 1 - Self.joinBand else { return nil }
        return row
    }

    /// The part of a row's height at its top and bottom where a drop lands beside it.
    private static let joinBand: CGFloat = 0.25
}
