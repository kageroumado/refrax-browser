import CoreGraphics
import Foundation

/// Turns an island's rows into points: the island's size, each row's frame, and the row a
/// point falls on.
///
/// An island contains tab rows with a separate header for its name and controls.
nonisolated struct IslandGeometry: Equatable, Sendable {
    static let rowHeight: CGFloat = 30
    /// The width of an island of titles, and of one of icons alone.
    static let titleWidth: CGFloat = 236
    static let iconWidth = ControlIslandPlacement.railWidth
    static let padding: CGFloat = 8
    static let insertionLineHeight: CGFloat = 2
    /// The Control Island's corner.
    static let cornerRadius: CGFloat = ControlIslandPlacement.cornerRadius
    static let rowCornerRadius: CGFloat = 8
    /// The pin, menu, and add button targets in the header.
    static let headerControlSize: CGFloat = 24
    /// The full name header matches the control island's width.
    static let headerHeight = ControlIslandPlacement.railWidth
    /// The distance between the header and the tab list.
    static let headerGap: CGFloat = 6
    /// The header's reserved height keeps the island's bounds stable during disclosure.
    static var headerReserve: CGFloat {
        headerHeight + headerGap
    }
    /// The largest share of the window's height an island takes before its rows scroll.
    static let maximumShare: CGFloat = 0.4

    var iconsOnly: Bool

    var cellHeight: CGFloat { iconsOnly ? ControlIslandPlacement.rowHeight : Self.rowHeight }
    var horizontalPadding: CGFloat { iconsOnly ? ControlIslandPlacement.horizontalInset : Self.padding }

    var width: CGFloat {
        iconsOnly ? Self.iconWidth : Self.titleWidth
    }

    /// The height of `rows` rows, one at least, and the padding.
    func contentHeight(rows: Int) -> CGFloat {
        CGFloat(max(1, rows)) * cellHeight + 2 * Self.padding
    }

    /// The island's size on screen: its content, held to the window's share.
    func size(rows: Int, in window: CGSize) -> CGSize {
        let least = contentHeight(rows: 1)
        return CGSize(width: width, height: min(contentHeight(rows: rows), max(least, window.height * Self.maximumShare)))
    }

    /// Row `index`'s frame in the island, before any scrolling.
    func rowFrame(_ index: Int) -> CGRect {
        CGRect(
            x: horizontalPadding, y: Self.padding + CGFloat(index) * cellHeight,
            width: width - 2 * horizontalPadding, height: cellHeight,
        )
    }

    /// Where a row dropped at `point` goes among `count` rows: before the row whose top half it
    /// is on, after the one whose bottom half, so 0 through `count`.
    func insertion(at point: CGPoint, count: Int) -> Int {
        let y = point.y - Self.padding
        return min(count, max(0, Int((y / cellHeight).rounded())))
    }

    /// The row `point` is on, when it is on one's middle: a drop there joins that row's tab
    /// instead of landing beside it.
    func joinedRow(at point: CGPoint, count: Int) -> Int? {
        let y = point.y - Self.padding
        guard y >= 0 else { return nil }
        let row = Int(y / cellHeight)
        let within = (y - CGFloat(row) * cellHeight) / cellHeight
        guard row < count, within > Self.joinBand, within < 1 - Self.joinBand else { return nil }
        return row
    }

    /// The part of a row's height at its top and bottom where a drop lands beside it.
    private static let joinBand: CGFloat = 0.25
}
