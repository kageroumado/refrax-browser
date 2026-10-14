import Foundation
import Testing
@testable import Refrax

/// How the table follows its space's tabs when one leaves, arrives, or is activated.
struct TableSyncTests {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    /// `a`, `b`, `c` in one row with `b` current.
    private var threeWithMiddleCurrent: TableLayout {
        TableLayout(tabIDs: [a, b, c]).focusing(b)
    }

    @Test
    func `A favorited current page keeps the window on it`() {
        let change = TableSync.following(threeWithMiddleCurrent, tabIDs: [a, c], activeTabID: b, arrivalSide: .left)
        #expect(change.activating == nil)
        #expect(change.layout.position(of: b) == nil)
        #expect(change.layout.tabIDs.count == 2)
        expectTableInvariants(change.layout)
    }

    @Test
    func `A closed current slab gives way to the neighbor in its gap`() {
        let change = TableSync.following(threeWithMiddleCurrent, tabIDs: [a, c], activeTabID: a, arrivalSide: .left)
        let neighbor = change.layout.focusedTabID
        #expect(neighbor != nil)
        #expect(neighbor != b)
        let expected: UUID? = neighbor == a ? nil : neighbor
        #expect(change.activating == expected)
        expectTableInvariants(change.layout)
    }

    @Test
    func `An unfavorited page returns to the table as the current slab`() {
        let start = TableLayout(tabIDs: [a, c]).focusing(a)
        let change = TableSync.following(start, tabIDs: [a, b, c], activeTabID: b, arrivalSide: .right)
        #expect(change.activating == nil)
        #expect(change.layout.focusedTabID == b)
        expectTableInvariants(change.layout)
    }

    @Test
    func `Activating another slab focuses it without a neighbor hand-off`() {
        let change = TableSync.following(threeWithMiddleCurrent, tabIDs: [a, b, c], activeTabID: c, arrivalSide: .left)
        #expect(change.activating == nil)
        #expect(change.layout.focusedTabID == c)
        expectTableInvariants(change.layout)
    }
}
