import Foundation
import Testing
@testable import Refrax

/// Checks every invariant ``TableLayout`` promises after an edit.
func expectTableInvariants(_ layout: TableLayout, sourceLocation: SourceLocation = #_sourceLocation) {
    let tolerance = 1e-9
    #expect(layout.rows.allSatisfy { !$0.slabs.isEmpty }, "no empty rows", sourceLocation: sourceLocation)
    #expect(Set(layout.tabIDs).count == layout.tabIDs.count, "each tab once", sourceLocation: sourceLocation)
    if layout.isEmpty {
        #expect(layout.focus == nil, sourceLocation: sourceLocation)
    } else {
        #expect(layout.rows.indices.contains(layout.focusedRow), sourceLocation: sourceLocation)
    }
    for row in layout.rows {
        #expect(row.slabs.indices.contains(row.focusedSlab), sourceLocation: sourceLocation)
        #expect(row.offset >= -tolerance, "offset not below 0", sourceLocation: sourceLocation)
        #expect(row.offset <= row.maxOffset + tolerance, "offset not past the row's end", sourceLocation: sourceLocation)
        if row.length <= 1 + tolerance {
            #expect(abs(row.offset) < tolerance, "short rows rest left-aligned", sourceLocation: sourceLocation)
        }
        #expect(row.isWhole(row.focusedSlab, at: row.offset), "focus whole at rest", sourceLocation: sourceLocation)
    }
}

struct TableLayoutTests {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()
    private let e = UUID()

    private func approx(_ lhs: Double, _ rhs: Double) -> Bool {
        abs(lhs - rhs) < 1e-9
    }

    private func row(_ widths: [(UUID, TableWidth)], offset: Double = 0, focus: Int = 0) -> TableLayout.Row {
        TableLayout.Row(slabs: widths.map { TableLayout.Slab(tabID: $0.0, width: $0.1) }, offset: offset, focusedSlab: focus)
    }

    /// The focused slab's left edge on screen, in viewport widths.
    private func focusedScreenLeft(_ layout: TableLayout) throws -> Double {
        let focus = try #require(layout.focus)
        let row = layout.rows[focus.row]
        return row.start(of: focus.slab) - row.offset
    }

    // MARK: - Presets

    @Test
    func `Width presets are a third, a half, two thirds and the full width`() {
        #expect(approx(TableWidth.third.fraction, 1.0 / 3.0))
        #expect(TableWidth.half.fraction == 0.5)
        #expect(approx(TableWidth.twoThirds.fraction, 2.0 / 3.0))
        #expect(TableWidth.full.fraction == 1)
        #expect(TableWidth.third.next == .half)
        #expect(TableWidth.half.next == .twoThirds)
        #expect(TableWidth.twoThirds.next == .full)
        #expect(TableWidth.full.next == .third)
    }

    @Test
    func `Three thirds make exactly one viewport`() {
        let layout = TableLayout(rows: [row([(a, .third), (b, .third), (c, .third)])])
        #expect(approx(layout.rows[0].length, 1))
        #expect(layout.rows[0].maxOffset == 0)
        #expect(layout.rows[0].isWhole(2, at: 0))
    }

    // MARK: - First layout

    @Test
    func `A new table is one row of the tabs in order, full width, focused on the first`() {
        let layout = TableLayout(tabIDs: [a, b, c])
        #expect(layout.rows.count == 1)
        #expect(layout.tabIDs == [a, b, c])
        #expect(layout.rows[0].slabs.allSatisfy { $0.width == .full && !$0.fills })
        #expect(layout.focus == TableLayout.Position(row: 0, slab: 0))
        #expect(layout.rows[0].offset == 0)
        expectTableInvariants(layout)
    }

    @Test
    func `An empty table has no focus`() {
        let layout = TableLayout(tabIDs: [])
        #expect(layout.isEmpty)
        #expect(layout.focus == nil)
        #expect(layout.focusedTabID == nil)
    }

    // MARK: - Insert

    @Test
    func `A new tab opens right of the focused slab and takes focus`() {
        let layout = TableLayout(tabIDs: [a, b, c]).inserting(d)
        #expect(layout.tabIDs == [a, d, b, c])
        #expect(layout.focusedTabID == d)
        #expect(layout.rows[0].offset == 1)
        expectTableInvariants(layout)
    }

    @Test
    func `A new tab beside a half slab keeps the view where it fits`() throws {
        let layout = TableLayout(rows: [row([(a, .half), (b, .half)])])
        let inserted = layout.inserting(c, width: .half)
        #expect(inserted.tabIDs == [a, c, b])
        #expect(inserted.focusedTabID == c)
        #expect(inserted.rows[0].offset == 0)
        #expect(try approx(focusedScreenLeft(inserted), 0.5))
        expectTableInvariants(inserted)
    }

    @Test
    func `A background tab opens right of focus without moving the view`() {
        let layout = TableLayout(tabIDs: [a, b]).movingFocus(.right)
        let inserted = layout.inserting(c, focus: false)
        #expect(inserted.tabIDs == [a, b, c])
        #expect(inserted.focusedTabID == b)
        #expect(inserted.rows[0].offset == layout.rows[0].offset)
        expectTableInvariants(inserted)
    }

    @Test
    func `The first tab on an empty table opens a row`() {
        let layout = TableLayout().inserting(a, width: .half)
        #expect(layout.rows.count == 1)
        #expect(layout.focusedTabID == a)
        #expect(layout.rows[0].slabs[0].width == .half)
        expectTableInvariants(layout)
    }

    @Test
    func `Inserting a tab already on the table moves it instead of duplicating it`() {
        let layout = TableLayout(tabIDs: [a, b, c]).inserting(c)
        #expect(layout.tabIDs == [a, c, b])
        expectTableInvariants(layout)
    }

    // MARK: - Remove

    @Test
    func `Closing the focused slab focuses the neighbor that slides in from the right`() throws {
        let layout = TableLayout(tabIDs: [a, b, c]).movingFocus(.right)
        let before = try focusedScreenLeft(layout)
        let removed = layout.removing(b)
        #expect(removed.tabIDs == [a, c])
        #expect(removed.focusedTabID == c)
        #expect(try focusedScreenLeft(removed) == before)
        expectTableInvariants(removed)
    }

    @Test
    func `Closing the last slab of a row focuses the one on its left`() {
        let layout = TableLayout(tabIDs: [a, b, c]).movingFocus(.right).movingFocus(.right)
        let removed = layout.removing(c)
        #expect(removed.focusedTabID == b)
        #expect(removed.rows[0].offset == 1)
        expectTableInvariants(removed)
    }

    @Test
    func `Closing a slab left of focus keeps the focused slab where it is on screen`() throws {
        let layout = TableLayout(rows: [row([(a, .half), (b, .half), (c, .half), (d, .half)], offset: 1, focus: 3)])
        let before = try focusedScreenLeft(layout)
        let removed = layout.removing(a)
        #expect(removed.focusedTabID == d)
        #expect(approx(removed.rows[0].offset, 0.5))
        #expect(try approx(focusedScreenLeft(removed), before))
        expectTableInvariants(removed)
    }

    @Test
    func `Closing a slab right of focus keeps the view`() {
        let layout = TableLayout(rows: [row([(a, .half), (b, .half), (c, .half), (d, .half)], offset: 0.5, focus: 1)])
        let removed = layout.removing(d)
        #expect(removed.focusedTabID == b)
        #expect(removed.rows[0].offset == 0.5)
        expectTableInvariants(removed)
    }

    @Test
    func `Closing the last slab of a row closes the row and the row below moves up`() {
        let layout = TableLayout(rows: [row([(a, .full)]), row([(b, .full), (c, .full)], offset: 1, focus: 1)])
        let removed = layout.removing(a)
        #expect(removed.rows.count == 1)
        #expect(removed.focusedRow == 0)
        #expect(removed.focusedTabID == c)
        expectTableInvariants(removed)
    }

    @Test
    func `Closing the only slab of the bottom row focuses the row above`() {
        let layout = TableLayout(rows: [row([(a, .full)]), row([(b, .full)])], focusedRow: 1)
        let removed = layout.removing(b)
        #expect(removed.rows.count == 1)
        #expect(removed.focusedTabID == a)
        expectTableInvariants(removed)
    }

    @Test
    func `Closing a row above the focused one keeps focus on the same slab`() {
        let layout = TableLayout(rows: [row([(a, .full)]), row([(b, .full)]), row([(c, .full)])], focusedRow: 2)
        let removed = layout.removing(a)
        #expect(removed.focusedTabID == c)
        #expect(removed.focusedRow == 1)
        expectTableInvariants(removed)
    }

    @Test
    func `Closing the last tab empties the table`() {
        let removed = TableLayout(tabIDs: [a]).removing(a)
        #expect(removed.isEmpty)
        #expect(removed.focus == nil)
    }

    @Test
    func `Removing a tab not on the table changes nothing`() {
        let layout = TableLayout(tabIDs: [a, b])
        #expect(layout.removing(c) == layout)
    }

    // MARK: - Focus

    @Test
    func `Focus along a row moves the view the least that shows the slab whole`() {
        let layout = TableLayout(rows: [row([(a, .third), (b, .third), (c, .third), (d, .third), (e, .third)])])
        let atC = layout.movingFocus(.right).movingFocus(.right)
        #expect(atC.focusedTabID == c)
        #expect(atC.rows[0].offset == 0)
        let atD = atC.movingFocus(.right)
        #expect(approx(atD.rows[0].offset, 1.0 / 3.0))
        let atE = atD.movingFocus(.right)
        #expect(approx(atE.rows[0].offset, 2.0 / 3.0))
        let backToB = atE.movingFocus(.left).movingFocus(.left).movingFocus(.left)
        #expect(backToB.focusedTabID == b)
        #expect(approx(backToB.rows[0].offset, 1.0 / 3.0))
        for step in [atC, atD, atE, backToB] {
            expectTableInvariants(step)
        }
    }

    @Test
    func `Focus stops at the table's edges`() {
        let layout = TableLayout(tabIDs: [a, b])
        #expect(layout.movingFocus(.left) == layout)
        #expect(layout.movingFocus(.up) == layout)
        #expect(layout.movingFocus(.down) == layout)
        let atB = layout.movingFocus(.right)
        #expect(atB.movingFocus(.right) == atB)
    }

    @Test
    func `Focus between rows returns to each row's remembered slab`() {
        let layout = TableLayout(rows: [row([(a, .full), (b, .full)], offset: 1, focus: 1), row([(c, .half), (d, .half)])])
        let down = layout.movingFocus(.down)
        #expect(down.focusedTabID == c)
        let back = down.movingFocus(.right).movingFocus(.up)
        #expect(back.focusedTabID == b)
        #expect(back.movingFocus(.down).focusedTabID == d)
    }

    @Test
    func `Focusing a tab reveals it`() {
        let layout = TableLayout(tabIDs: [a, b, c]).focusing(c)
        #expect(layout.focusedTabID == c)
        #expect(layout.rows[0].offset == 2)
        #expect(layout.focusing(UUID()) == layout)
    }

    // MARK: - Move

    @Test
    func `Moving the focused slab right swaps it with its neighbor and keeps focus`() {
        let layout = TableLayout(tabIDs: [a, b, c]).movingFocusedSlab(.right)
        #expect(layout.tabIDs == [b, a, c])
        #expect(layout.focusedTabID == a)
        #expect(layout.rows[0].offset == 1)
        expectTableInvariants(layout)
        #expect(layout.movingFocusedSlab(.left).tabIDs == [a, b, c])
    }

    @Test
    func `A slab moved down lands nearest its old horizontal center`() {
        let layout = TableLayout(rows: [
            row([(a, .twoThirds), (b, .third)], focus: 1),
            row([(c, .third), (d, .third), (e, .third)]),
        ])
        let moved = layout.movingFocusedSlab(.down)
        #expect(moved.rows.count == 2)
        #expect(moved.rows[0].slabs.map(\.tabID) == [a])
        #expect(moved.rows[1].slabs.map(\.tabID) == [c, d, b, e])
        #expect(moved.focus == TableLayout.Position(row: 1, slab: 2))
        #expect(moved.rows[1].offset == 0)
        expectTableInvariants(moved)
    }

    @Test
    func `A slab moved between rows keeps its left edge on screen when it can`() throws {
        let layout = TableLayout(rows: [
            row([(a, .half), (b, .half), (c, .half)], offset: 0.5, focus: 2),
            row([(d, .half), (e, .half), (UUID(), .half), (UUID(), .half)], offset: 1, focus: 2),
        ])
        let before = try focusedScreenLeft(layout)
        let moved = layout.movingFocusedSlab(.down)
        #expect(moved.focusedTabID == c)
        #expect(try approx(focusedScreenLeft(moved), before))
        expectTableInvariants(moved)
    }

    @Test
    func `Moving a row's only slab into another row closes the empty row`() {
        let layout = TableLayout(rows: [row([(a, .full)]), row([(b, .full)])])
        let moved = layout.movingFocusedSlab(.down)
        #expect(moved.rows.count == 1)
        #expect(moved.focusedTabID == a)
        #expect(Set(moved.tabIDs) == [a, b])
        expectTableInvariants(moved)
    }

    @Test
    func `Moving a slab past the top or bottom opens a new row for it`() {
        let layout = TableLayout(tabIDs: [a, b, c]).movingFocus(.right)
        let up = layout.movingFocusedSlab(.up)
        #expect(up.rows.count == 2)
        #expect(up.rows[0].slabs.map(\.tabID) == [b])
        #expect(up.focusedRow == 0)
        #expect(up.rows[1].slabs.map(\.tabID) == [a, c])
        expectTableInvariants(up)

        let down = layout.movingFocusedSlab(.down)
        #expect(down.rows.count == 2)
        #expect(down.rows[1].slabs.map(\.tabID) == [b])
        #expect(down.focusedRow == 1)
        expectTableInvariants(down)
    }

    @Test
    func `A slab alone in the only row stays put`() {
        let layout = TableLayout(tabIDs: [a])
        #expect(layout.movingFocusedSlab(.up) == layout)
        #expect(layout.movingFocusedSlab(.down) == layout)
        #expect(layout.movingFocusedSlab(.left) == layout)
    }

    // MARK: - Width

    @Test
    func `Cycling width runs a third, a half, two thirds, full`() {
        var layout = TableLayout(tabIDs: [a])
        var widths: [TableWidth] = []
        for _ in 0 ..< 4 {
            layout = layout.cyclingWidth()
            widths.append(layout.rows[0].slabs[0].width)
            expectTableInvariants(layout)
        }
        #expect(widths == [.third, .half, .twoThirds, .full])
    }

    @Test
    func `Resizing keeps the focused slab's left edge on screen`() throws {
        let layout = TableLayout(rows: [row([(a, .third), (b, .third), (c, .third)], focus: 1)])
        let before = try focusedScreenLeft(layout)
        let resized = layout.cyclingWidth()
        #expect(resized.rows[0].slabs[1].width == .half)
        #expect(try approx(focusedScreenLeft(resized), before))
        expectTableInvariants(resized)
    }

    @Test
    func `Resizing moves the view only as far as keeps the slab whole`() {
        let layout = TableLayout(rows: [row([(a, .third), (b, .third), (c, .third)], focus: 2)])
        let resized = layout.cyclingWidth()
        #expect(resized.rows[0].slabs[2].width == .half)
        #expect(approx(resized.rows[0].offset, 1.0 / 6.0))
        expectTableInvariants(resized)
    }

    @Test
    func `Fill takes the full width and toggles back to the preset`() {
        let layout = TableLayout(rows: [row([(a, .half), (b, .half)], focus: 1)])
        let filled = layout.togglingFill()
        #expect(filled.rows[0].slabs[1].fills)
        #expect(filled.rows[0].slabs[1].width == .half)
        #expect(filled.rows[0].slabs[1].fraction == 1)
        #expect(filled.rows[0].offset == 0.5)
        expectTableInvariants(filled)

        let restored = filled.togglingFill()
        #expect(restored.rows[0].slabs[1].fraction == 0.5)
        expectTableInvariants(restored)
    }

    @Test
    func `Cycling a filling slab returns it to its preset`() {
        let filled = TableLayout(rows: [row([(a, .half)])]).togglingFill()
        let cycled = filled.cyclingWidth()
        #expect(!cycled.rows[0].slabs[0].fills)
        #expect(cycled.rows[0].slabs[0].width == .half)
    }

    // MARK: - Reconcile

    @Test
    func `Reconcile drops closed tabs and appends new ones to the focused row`() {
        let layout = TableLayout(rows: [row([(a, .full)]), row([(b, .half), (c, .half)])], focusedRow: 1)
        let reconciled = layout.reconciled(with: [a, c, d, e])
        #expect(reconciled.rows[0].slabs.map(\.tabID) == [a])
        #expect(reconciled.rows[1].slabs.map(\.tabID) == [c, d, e])
        #expect(reconciled.focusedTabID == c)
        expectTableInvariants(reconciled)
    }

    @Test
    func `Reconcile keeps the arrangement when nothing changed`() {
        let layout = TableLayout(rows: [row([(a, .full)]), row([(b, .half), (c, .half)])], focusedRow: 1)
        #expect(layout.reconciled(with: [c, b, a]) == layout)
    }

    @Test
    func `Reconcile with no tabs empties the table, and with tabs again starts a row`() {
        let empty = TableLayout(tabIDs: [a, b]).reconciled(with: [])
        #expect(empty.isEmpty)
        let refilled = empty.reconciled(with: [c, d])
        #expect(refilled.tabIDs == [c, d])
        #expect(refilled.focusedTabID == c)
        expectTableInvariants(refilled)
    }

    @Test
    func `Reconcile ignores repeated IDs`() {
        let layout = TableLayout(tabIDs: [a, b, a, b])
        #expect(layout.tabIDs == [a, b])
    }

    // MARK: - Normalizing and storage

    @Test
    func `Normalizing drops empty rows and repeats and clamps offsets`() {
        let layout = TableLayout(rows: [
            TableLayout.Row(slabs: []),
            row([(a, .half), (b, .half)], offset: 3, focus: 9),
            row([(a, .full), (c, .half)], offset: -2),
        ], focusedRow: 7)
        #expect(layout.rows.count == 2)
        #expect(layout.tabIDs == [a, b, c])
        #expect(layout.rows[0].offset == 0)
        #expect(layout.rows[0].focusedSlab == 1)
        #expect(layout.focusedRow == 1)
        expectTableInvariants(layout)
    }

    @Test
    func `A row shorter than the viewport rests left-aligned`() {
        let layout = TableLayout(rows: [row([(a, .third), (b, .third)], offset: 0.5, focus: 1)])
        #expect(layout.rows[0].offset == 0)
    }

    @Test
    func `The layout round-trips through JSON`() throws {
        let layout = TableLayout(rows: [row([(a, .full)]), row([(b, .third), (c, .twoThirds)], focus: 1)], focusedRow: 1)
            .togglingFill()
        let data = try JSONEncoder().encode(layout)
        let decoded = try JSONDecoder().decode(TableLayout.self, from: data)
        #expect(decoded == layout)
        #expect(decoded.rows.map(\.id) == layout.rows.map(\.id))
    }

    // MARK: - Invariants under random edits

    @Test(arguments: [1, 7, 42, 1_234, 99_999] as [UInt64])
    func `Every edit keeps the invariants`(seed: UInt64) throws {
        var generator = TableTestRandom(seed: seed)
        var tabs: [UUID] = (0 ..< 4).map { _ in UUID() }
        var layout = TableLayout(tabIDs: tabs)
        for _ in 0 ..< 400 {
            switch Int.random(in: 0 ..< 9, using: &generator) {
            case 0:
                let tab = UUID()
                tabs.append(tab)
                let width = try #require(TableWidth.allCases.randomElement(using: &generator))
                layout = layout.inserting(tab, width: width, focus: Bool.random(using: &generator))
            case 1:
                if let tab = tabs.randomElement(using: &generator) {
                    tabs.removeAll { $0 == tab }
                    layout = layout.removing(tab)
                }
            case 2:
                layout = try layout.movingFocus(#require(TableDirection.allCases.randomElement(using: &generator)))
            case 3:
                layout = try layout.movingFocusedSlab(#require(TableDirection.allCases.randomElement(using: &generator)))
            case 4:
                layout = layout.cyclingWidth()
            case 5:
                layout = layout.togglingFill()
            case 6:
                let extra = UUID()
                tabs.append(extra)
                layout = layout.reconciled(with: tabs.shuffled(using: &generator))
            case 7:
                if let tab = tabs.randomElement(using: &generator) {
                    layout = layout.focusing(tab)
                }
            default:
                if !layout.isEmpty {
                    let rowIndex = Int.random(in: 0 ..< layout.rows.count, using: &generator)
                    let row = layout.rows[rowIndex]
                    layout = layout.resting(at: TableRest(
                        row: rowIndex,
                        offset: Double.random(in: -0.5 ... row.length, using: &generator),
                        focusedSlab: Int.random(in: 0 ..< row.slabs.count, using: &generator),
                    ))
                }
            }
            expectTableInvariants(layout)
            #expect(Set(layout.tabIDs) == Set(tabs), "the table holds exactly the space's tabs")
        }
    }

    // MARK: - Wheel

    @Test
    func `A wheel notch steps rows vertically and slabs horizontally or with shift`() {
        #expect(TableDirection.wheelStep(deltaX: 0, deltaY: 1, shift: false) == .up)
        #expect(TableDirection.wheelStep(deltaX: 0, deltaY: -1, shift: false) == .down)
        #expect(TableDirection.wheelStep(deltaX: 1, deltaY: 0, shift: false) == .left)
        #expect(TableDirection.wheelStep(deltaX: -1, deltaY: 0, shift: false) == .right)
        #expect(TableDirection.wheelStep(deltaX: 0, deltaY: 1, shift: true) == .left)
        #expect(TableDirection.wheelStep(deltaX: 0, deltaY: -1, shift: true) == .right)
        #expect(TableDirection.wheelStep(deltaX: 0, deltaY: 0, shift: false) == nil)
    }
}

/// A deterministic random source, so a failing sequence reproduces.
private struct TableTestRandom: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        self.state = seed &+ 0x9E37_79B9_7F4A_7C15
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
