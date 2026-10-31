import CoreGraphics
import Foundation
@testable import Refrax

/// Every way two to four rectangles tile the two-by-two grid, and grids built from them.
enum PaneGridFixtures {
    static let leftColumn = PaneSpan(columns: 0 ... 0, rows: 0 ... 1)
    static let rightColumn = PaneSpan(columns: 1 ... 1, rows: 0 ... 1)
    static let topRow = PaneSpan(columns: 0 ... 1, rows: 0 ... 0)
    static let bottomRow = PaneSpan(columns: 0 ... 1, rows: 1 ... 1)

    /// The complete tilings of more than one pane, as spans in reading order.
    static let tilings: [[PaneSpan]] = [
        [leftColumn, rightColumn],
        [topRow, bottomRow],
        [topRow, PaneSpan(.bottomLeft), PaneSpan(.bottomRight)],
        [PaneSpan(.topLeft), PaneSpan(.topRight), bottomRow],
        [leftColumn, PaneSpan(.topRight), PaneSpan(.bottomRight)],
        [PaneSpan(.topLeft), rightColumn, PaneSpan(.bottomLeft)],
        GridCell.all.map(PaneSpan.init),
    ]

    /// A grid of fresh pages covering `spans`, and the pages in the order of the spans.
    static func grid(_ spans: [PaneSpan]) -> (grid: PaneGrid, ids: [UUID]) {
        let ids = spans.map { _ in UUID() }
        return (PaneGrid(spans: Dictionary(uniqueKeysWithValues: zip(ids, spans))), ids)
    }

    /// A stored layout naming each page's cell, without expansions.
    static func legacyConfiguration(_ positions: [(UUID, PanePosition)]) -> LayoutConfiguration {
        LayoutConfiguration(panePositions: Dictionary(uniqueKeysWithValues: positions))
    }
}
