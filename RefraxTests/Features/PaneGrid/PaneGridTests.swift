import Foundation
import Testing
@testable import Refrax

/// A tab's pages on the two-by-two grid: reading a stored layout, completing it, editing it,
/// and storing it back.
struct PaneGridTests {
    private typealias Fixtures = PaneGridFixtures
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()

    /// How many pages cover `cell`.
    private func coverage(of cell: GridCell, in grid: PaneGrid) -> Int {
        grid.spans.values.filter { $0.contains(cell) }.count
    }

    // MARK: - Reading a stored layout

    @Test
    func `A lone page covers the whole grid and stores no layout`() {
        let grid = PaneGrid(configuration: nil, pageIDs: [a])
        #expect(grid.span(of: a) == .whole)
        #expect(grid.configuration(columnSplit: 0.5, rowSplit: 0.5, activePaneID: a) == nil)
        #expect(grid.positions[a] == .single)
    }

    @Test(arguments: [
        (PanePosition.topLeft, PanePosition.topRight, true),
        (.bottomLeft, .bottomRight, true),
        (.topLeft, .bottomRight, true),
        (.topRight, .bottomLeft, true),
        (.topLeft, .bottomLeft, false),
        (.topRight, .bottomRight, false),
    ])
    func `Two stored panes read as columns side by side or rows one above the other`(first: PanePosition, second: PanePosition, sideBySide: Bool) {
        let grid = PaneGrid(configuration: Fixtures.legacyConfiguration([(a, first), (b, second)]), pageIDs: [a, b])
        #expect(grid.isComplete)
        for id in [a, b] {
            let span = grid.span(of: id)
            #expect(span?.isTall == sideBySide)
            #expect(span?.isWide == !sideBySide)
        }
    }

    /// A triple without a stored expansion once grew two panes over the same empty cell: the
    /// pane before it and the pane below it both took it.
    @Test(arguments: GridCell.all)
    func `A stored triple without an expansion covers every cell exactly once`(missing: GridCell) {
        let present = GridCell.all.filter { $0 != missing }
        let ids = [a, b, c]
        let config = Fixtures.legacyConfiguration(Array(zip(ids, present.map(\.position))))
        let grid = PaneGrid(configuration: config, pageIDs: ids)
        #expect(grid.count == 3)
        for cell in GridCell.all {
            #expect(coverage(of: cell, in: grid) == 1, "\(cell)")
        }
    }

    @Test(arguments: PaneGridFixtures.tilings)
    func `Every tiling reads back from the layout it stores`(spans: [PaneSpan]) {
        let (grid, ids) = Fixtures.grid(spans)
        let config = grid.configuration(columnSplit: 0.4, rowSplit: 0.6, activePaneID: ids.last)
        let read = PaneGrid(configuration: config, pageIDs: ids.reversed())
        #expect(read == grid)
        #expect(config?.horizontalDivider == 0.4)
        #expect(config?.verticalDivider == 0.6)
        #expect(config?.activePaneID == ids.last)
    }

    @Test
    func `A page with no stored cell takes the first free one`() {
        let grid = PaneGrid(configuration: Fixtures.legacyConfiguration([(a, .topLeft)]), pageIDs: [a, b])
        #expect(grid.span(of: a) == Fixtures.leftColumn)
        #expect(grid.span(of: b) == Fixtures.rightColumn)
        #expect(PaneGrid(configuration: nil, pageIDs: [a, b]) == grid)
    }

    @Test
    func `Two pages stored in one cell are given two`() {
        let grid = PaneGrid(configuration: Fixtures.legacyConfiguration([(a, .topLeft), (b, .topLeft)]), pageIDs: [a, b])
        #expect(grid.isComplete)
        #expect(grid.span(of: a) != grid.span(of: b))
    }

    @Test
    func `A stored expansion upward from a bottom cell is kept`() {
        var config = Fixtures.legacyConfiguration([(a, .bottomLeft), (b, .topRight), (c, .bottomRight)])
        config.expansions[.bottomLeft] = .up
        let grid = PaneGrid(configuration: config, pageIDs: [a, b, c])
        #expect(grid.span(of: a) == Fixtures.leftColumn)
        #expect(grid.span(of: b) == PaneSpan(.topRight))
    }

    // MARK: - Completing

    @Test
    func `Empty cells are filled from above first`() {
        let grid = PaneGrid(spans: [a: PaneSpan(.topLeft), b: PaneSpan(.topRight)]).filled()
        #expect(grid.span(of: a) == Fixtures.leftColumn)
        #expect(grid.span(of: b) == Fixtures.rightColumn)
    }

    @Test
    func `A wide pane grows over both cells below it`() {
        let grid = PaneGrid(spans: [a: Fixtures.topRow]).filled()
        #expect(grid.span(of: a) == .whole)
    }

    @Test
    func `A lone pane in one cell fills the grid`() {
        #expect(PaneGrid(spans: [a: PaneSpan(.bottomRight)]).filled().span(of: a) == .whole)
    }

    // MARK: - Inserting

    @Test(arguments: PaneEdge.allCases)
    func `A page beside a lone page takes the half at that side`(edge: PaneEdge) throws {
        let grid = PaneGrid(spans: [a: .whole])
        let joined = try #require(grid.inserting(b, at: .split(PaneSplit(target: a, edge: edge))))
        #expect(joined.span(of: b) == PaneSpan.whole.half(at: edge))
        #expect(joined.span(of: a) == PaneSpan.whole.half(at: edge.opposite))
        #expect(joined.isComplete)
    }

    @Test
    func `A page put on a covered cell splits the pane there toward it`() throws {
        let joined = try #require(PaneGrid(spans: [a: .whole]).inserting(b, at: .cell(.topRight)))
        #expect(joined.span(of: b) == Fixtures.rightColumn)
        #expect(joined.span(of: a) == Fixtures.leftColumn)
    }

    @Test
    func `A page put on an empty cell takes that cell alone`() throws {
        let grid = PaneGrid(spans: [a: PaneSpan(.topLeft), b: PaneSpan(.topRight)])
        let joined = try #require(grid.inserting(c, at: .cell(.bottomRight)))
        #expect(joined.span(of: c) == PaneSpan(.bottomRight))
        #expect(joined.emptyCells == [.bottomLeft])
    }

    @Test
    func `The automatic place halves the first of the largest panes`() throws {
        let (columns, ids) = Fixtures.grid([Fixtures.leftColumn, Fixtures.rightColumn])
        let joined = try #require(columns.inserting(c, at: .automatic))
        #expect(joined.span(of: c) == PaneSpan(.bottomLeft))
        #expect(joined.span(of: ids[0]) == PaneSpan(.topLeft))
        #expect(PaneGrid(spans: [a: .whole]).automaticSplit == PaneSplit(target: a, edge: .trailing))
    }

    @Test
    func `A fifth page and a split of a single cell are refused`() {
        let (quad, ids) = Fixtures.grid(GridCell.all.map(PaneSpan.init))
        #expect(quad.inserting(UUID(), at: .automatic) == nil)
        let triple = Fixtures.grid([Fixtures.topRow, PaneSpan(.bottomLeft), PaneSpan(.bottomRight)])
        #expect(triple.grid.inserting(UUID(), at: .split(PaneSplit(target: triple.ids[1], edge: .trailing))) == nil)
        #expect(quad.hasRoom == false)
        #expect(quad.inserting(ids[0], at: .automatic) == nil)
    }

    // MARK: - Editing

    @Test
    func `Moving a pane onto another trades their places`() throws {
        let grid = PaneGrid(spans: [a: Fixtures.leftColumn, b: Fixtures.rightColumn])
        let moved = try #require(grid.moving(a, to: .bottomRight))
        #expect(moved.span(of: a) == Fixtures.rightColumn)
        #expect(moved.span(of: b) == Fixtures.leftColumn)
        #expect(grid.moving(a, to: .bottomLeft) == nil)
    }

    @Test
    func `Moving a pane onto an empty cell leaves its own cells empty`() throws {
        let grid = PaneGrid(spans: [a: PaneSpan(.topLeft), b: PaneSpan(.topRight)])
        let moved = try #require(grid.moving(a, to: .bottomLeft))
        #expect(moved.span(of: a) == PaneSpan(.bottomLeft))
        #expect(moved.emptyCells == [.topLeft, .bottomRight])
    }

    @Test
    func `A pane grows only over empty cells and shrinks only where it is two thick`() throws {
        let grid = PaneGrid(spans: [a: PaneSpan(.topLeft), b: PaneSpan(.topRight)])
        let grown = try #require(grid.expanding(a, toward: .bottom))
        #expect(grown.span(of: a) == Fixtures.leftColumn)
        #expect(grid.expanding(a, toward: .trailing) == nil)
        #expect(grid.expanding(a, toward: .leading) == nil)
        #expect(grown.shrinking(a, from: .top)?.span(of: a) == PaneSpan(.bottomLeft))
        #expect(grid.shrinking(a, from: .bottom) == nil)
    }

    @Test
    func `A removed pane's cells go to its neighbors once filled`() {
        let (quad, ids) = Fixtures.grid(GridCell.all.map(PaneSpan.init))
        let grid = quad.removing(ids[3]).filled()
        #expect(grid.span(of: ids[1]) == Fixtures.rightColumn)
        #expect(grid.isComplete)
    }

    @Test
    func `Reconciling drops pages that left and places pages that joined`() {
        let grid = PaneGrid(spans: [a: Fixtures.leftColumn, b: Fixtures.rightColumn]).reconciled(with: [a, c])
        #expect(grid.contains(b) == false)
        #expect(grid.contains(c))
        #expect(grid.filled().isComplete)
    }

    @Test
    func `A page's stored position is its top-leading cell`() {
        let grid = PaneGrid(spans: [a: Fixtures.rightColumn, b: Fixtures.leftColumn])
        #expect(grid.positions == [a: .topRight, b: .topLeft])
        #expect(grid.pageIDs == [b, a])
    }

    @Test
    func `Cell and edge names read back`() {
        for cell in GridCell.all {
            #expect(GridCell(name: cell.description) == cell)
            #expect(GridCell(cell.position) == cell)
        }
        #expect(PaneEdge(word: "up") == .top)
        #expect(PaneEdge(word: "left") == .leading)
        #expect(PaneEdge(word: "sideways") == nil)
    }
}
