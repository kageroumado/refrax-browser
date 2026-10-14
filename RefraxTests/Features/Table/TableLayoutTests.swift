import Foundation
import Testing
@testable import Refrax

struct TableLayoutTests {
    private typealias Row = TableLayout.RowSource
    private typealias Position = TableLayout.Position

    private let space = UUID()
    private let research = UUID()
    private let trip = UUID()
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()
    private let e = UUID()

    /// Loose tabs a, b; Research c, d (d half); Trip e, collapsed.
    private var layout: TableLayout {
        var state = TableState()
        state.setWidth(.half, of: d)
        return TableLayout(rows: [
            Row(id: space, tabIDs: [a, b]),
            Row(id: research, title: "Research", colorString: "Steel", tabIDs: [c, d]),
            Row(id: trip, title: "Trip", isCollapsed: true, tabIDs: [e]),
        ], state: state)
    }

    @Test
    func `Rows come from the sources and slabs take their saved widths`() {
        let layout = layout
        #expect(layout.rows.map(\.id) == [space, research, trip])
        #expect(layout.rows[1].title == "Research")
        #expect(layout.rows[1].colorString == "Steel")
        #expect(layout.rows[2].isCollapsed)
        #expect(layout[Position(row: 1, slab: 1)].width == .half)
        #expect(layout[Position(row: 1, slab: 0)].width == .full)
        #expect(layout.rows[1].length == 1.5)
        #expect(layout.tabIDs == [a, b, c, d, e])
    }

    @Test
    func `Empty rows and repeated tabs are dropped`() {
        let layout = TableLayout(rows: [Row(id: space, tabIDs: []), Row(id: research, tabIDs: [a, a, b]), Row(id: trip, tabIDs: [b])])
        #expect(layout.rows.map(\.id) == [research])
        #expect(layout.tabIDs == [a, b])
    }

    @Test
    func `Neighbors follow the row and stop at its ends`() {
        let layout = layout
        #expect(layout.neighbor(of: a, toward: .right) == b)
        #expect(layout.neighbor(of: b, toward: .left) == a)
        #expect(layout.neighbor(of: b, toward: .right) == nil)
        #expect(layout.neighbor(of: a, toward: .up) == nil)
    }

    @Test
    func `Row steps skip collapsed bands and stop at the table's edges`() {
        let layout = layout
        #expect(layout.rowIndex(from: a, toward: .down) == 1)
        #expect(layout.rowIndex(from: c, toward: .down) == nil)
        #expect(layout.rowIndex(from: c, toward: .up) == 0)
        #expect(layout.rowIndex(from: a, toward: .up) == nil)
    }

    @Test
    func `The slab nearest another row's slab is the one overlapping it most`() {
        var state = TableState()
        for tab in [a, b, c] {
            state.setWidth(.third, of: tab)
        }
        state.setWidth(.half, of: d)
        state.setWidth(.half, of: e)
        let layout = TableLayout(rows: [Row(id: space, tabIDs: [a, b, c]), Row(id: research, tabIDs: [d, e])], state: state)
        #expect(layout.slab(inRow: 1, nearest: a) == d)
        #expect(layout.slab(inRow: 1, nearest: c) == e)
        #expect(layout.slab(inRow: 0, nearest: d) == a)
        #expect(layout.slab(inRow: 0, nearest: e) == c)
    }

    @Test
    func `Moving along a row swaps with the neighbor`() {
        let layout = layout
        #expect(layout.moveTarget(of: a, toward: .right) == .row(id: space, index: 1))
        #expect(layout.moveTarget(of: a, toward: .left) == nil)
        #expect(layout.moveTarget(of: d, toward: .left) == .row(id: research, index: 0))
    }

    @Test
    func `Moving between rows lands nearest the old center and opens a row at the edges`() {
        let layout = layout
        // b's center is at 1.5; a full slab in Research would center at 0.5, 1.5, or 2, so
        // b lands between c and d.
        #expect(layout.moveTarget(of: b, toward: .down) == .row(id: research, index: 1))
        // d's center is 1.25; in the loose row the places are 0, 1, 2, so d lands after a.
        #expect(layout.moveTarget(of: d, toward: .up) == .row(id: space, index: 1))
        #expect(layout.moveTarget(of: a, toward: .up) == .newRow(above: true))
        // Research down would land on Trip, which is collapsed, so it opens a new row below.
        #expect(layout.moveTarget(of: c, toward: .down) == .newRow(above: false))
        // A slab alone in its row has no new row to open.
        let lone = TableLayout(rows: [Row(id: space, tabIDs: [a])])
        #expect(lone.moveTarget(of: a, toward: .down) == nil)
    }

    @Test
    func `State cycles widths, toggles fills, prunes, and round-trips`() throws {
        var state = TableState()
        state.cycleWidth(of: a)
        #expect(state.width(of: a) == .third)
        state.toggleFill(of: a)
        #expect(state.fills.contains(a))
        state.cycleWidth(of: a)
        #expect(!state.fills.contains(a))
        #expect(state.width(of: a) == .third)
        state.setWidth(.half, of: b)
        state.toggleFill(of: b)
        state.prune(keeping: [a])
        #expect(state.widths[b] == nil)
        #expect(!state.fills.contains(b))
        let data = try #require(state.encoded())
        #expect(TableState.decode(data) == state)
        #expect(TableState.decode(nil) == TableState())
        let layout = TableLayout(rows: [Row(id: space, tabIDs: [a])], state: state)
        #expect(layout[Position(row: 0, slab: 0)].fraction == 1.0 / 3.0)
    }
}
