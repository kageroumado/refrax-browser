import Foundation
import Testing
@testable import Refrax

struct IslandLayoutTests {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()
    private let e = UUID()

    private func cell(_ x: Int, _ y: Int) -> IslandCell {
        IslandCell(x: x, y: y)
    }

    @Test
    func `A tab opened from a chip goes below it, then along the row of children`() {
        var layout = IslandLayout().placing(a, below: nil)
        #expect(layout[a]?.cell == cell(0, 0))
        layout = layout.placing(b, below: a)
        #expect(layout[b]?.cell == cell(0, 1))
        layout = layout.placing(c, below: a)
        #expect(layout[c]?.cell == cell(1, 1))
        layout = layout.placing(d, below: b)
        #expect(layout[d]?.cell == cell(0, 2))
        #expect(layout.isConnected)
        #expect(layout.tabIDs == [a, b, c, d])
    }

    @Test
    func `A tab with no source goes under the island's first column`() {
        let layout = IslandLayout().placing(a, below: nil).placing(b, below: a).placing(c, below: nil)
        #expect(layout[c]?.cell == cell(0, 2))
        #expect(layout.isConnected)
    }

    @Test
    func `Neighbors are found across shared edges and along gaps, never across corners`() {
        let layout = IslandLayout().placing(a, below: nil).placing(b, below: a).placing(c, below: a)
        // a over b, c right of b.
        #expect(layout.neighbor(of: a, toward: .down) == b)
        #expect(layout.neighbor(of: b, toward: .right) == c)
        #expect(layout.neighbor(of: c, toward: .left) == b)
        #expect(layout.neighbor(of: c, toward: .up) == nil)
        #expect(layout.neighbor(of: a, toward: .right) == nil)
        #expect(layout.neighbor(of: b, toward: .up) == a)
        #expect(layout.neighbor(of: a, toward: .up) == nil)
    }

    @Test
    func `A chip may land only beside another chip, on a free cell`() {
        let layout = IslandLayout().placing(a, below: nil).placing(b, below: a)
        #expect(layout.canPlace(nil, at: cell(1, 0)))
        #expect(layout.canPlace(nil, at: cell(-1, 1)))
        #expect(!layout.canPlace(nil, at: cell(0, 0)))
        #expect(!layout.canPlace(nil, at: cell(1, 2)))
        #expect(!layout.canPlace(nil, at: cell(3, 0)))
        #expect(layout.canPlace(b, at: cell(1, 0)))
        #expect(!layout.canPlace(b, at: cell(0, 3)))
        #expect(layout.moving(b, to: cell(1, 0))[b]?.cell == cell(1, 0))
        #expect(layout.moving(b, to: cell(0, 3)) == layout)
    }

    @Test
    func `A preview spans cells and lands only where it fits`() {
        var layout = IslandLayout().placing(a, below: nil).placing(b, below: a)
        layout = layout.reshaping(b, shape: .preview, span: IslandSpan(width: 2, height: 3))
        #expect(layout[b]?.cells.count == 6)
        #expect(layout[b]?.cell == cell(0, 1))
        #expect(layout.isConnected)
        #expect(!layout.canPlace(nil, at: cell(1, 2)))
        #expect(layout.canPlace(nil, at: cell(2, 2)))
        #expect(layout.neighbor(of: a, toward: .down) == b)
        // Growing a beside b to the same span would overlap, so a moves to a free spot.
        let grown = layout.reshaping(a, shape: .preview, span: IslandSpan(width: 2, height: 3))
        #expect(grown[a]?.cells.isDisjoint(with: grown[b]!.cells) == true)
        #expect(grown.isConnected)
    }

    @Test
    func `Closing a chip moves the chips below it up and keeps the island whole`() {
        let layout = IslandLayout().placing(a, below: nil).placing(b, below: a).placing(c, below: b).placing(d, below: a)
        // a; b d; c.
        let closed = layout.removing(b)
        #expect(closed[c]?.cell == cell(0, 1))
        #expect(closed[d]?.cell == cell(1, 1))
        #expect(closed.isConnected)
        let top = layout.removing(a)
        #expect(top[b]?.cell == cell(0, 0))
        #expect(top[c]?.cell == cell(0, 1))
        #expect(top.isConnected)
    }

    @Test
    func `Chips cut loose slide back until they touch`() {
        // a; b; c, with d right of c. Removing b and c leaves d alone two rows down.
        var layout = IslandLayout().placing(a, below: nil).placing(b, below: a).placing(c, below: b)
        layout = layout.placing(d, below: b).moving(d, to: cell(1, 2))
        let cut = layout.removing(b).removing(c)
        #expect(cut.isConnected)
        #expect(cut.chips.count == 2)
    }

    @Test
    func `The subtree below a chip is the column under it`() {
        let layout = IslandLayout().placing(a, below: nil).placing(b, below: a).placing(c, below: b).placing(d, below: a)
        #expect(layout.subtree(below: a) == [a, b, c])
        #expect(layout.subtree(below: d) == [d])
    }

    @Test
    func `Merging places the other island's chips under this one`() {
        let one = IslandLayout().placing(a, below: nil).placing(b, below: a)
        let two = IslandLayout().placing(c, below: nil)
        let merged = one.merging(two)
        #expect(merged[c]?.cell == cell(0, 2))
        #expect(merged.isConnected)
    }

    @Test
    func `State round-trips and prunes`() throws {
        var state = IslandState()
        state.chips[a] = ChipPlacement(cell: cell(2, 3), shape: .preview, span: IslandSpan(width: 2, height: 6))
        state.chips[b] = ChipPlacement(cell: cell(0, 0))
        state.islands[c] = IslandPlacement(x: 0.2, y: 0.1, isPinned: true, iconsOnly: true)
        state.islands[d] = IslandPlacement(x: 0.5, y: 0.5)
        let data = try #require(state.encoded())
        #expect(IslandState.decode(data) == state)
        state.prune(tabs: [a], islands: [c])
        #expect(state.chips[b] == nil)
        #expect(state.islands[d] == nil)
        #expect(state.chips[a]?.span.height == 6)
    }

    @Test
    func `Geometry lays chips out in cells with the island's padding`() {
        let layout = IslandLayout().placing(a, below: nil).placing(b, below: a).placing(c, below: a)
        let geometry = IslandGeometry(iconsOnly: false)
        let cellSize = IslandGeometry.titleCell
        #expect(geometry.frame(of: layout[a]!, in: layout) == CGRect(x: 10, y: 10, width: cellSize.width, height: cellSize.height))
        #expect(geometry.frame(of: layout[c]!, in: layout).minX == 10 + cellSize.width + IslandGeometry.gap)
        #expect(geometry.frame(of: layout[c]!, in: layout).minY == 10 + cellSize.height + IslandGeometry.gap)
        let content = geometry.contentSize(of: layout)
        #expect(content.width == 2 * cellSize.width + IslandGeometry.gap + 20)
        #expect(content.height == 2 * cellSize.height + IslandGeometry.gap + 20 + IslandGeometry.footerHeight)
        #expect(geometry.cell(at: CGPoint(x: 10 + cellSize.width + 8, y: 12), in: layout) == cell(1, 0))
        let capped = geometry.islandSize(of: layout, in: CGSize(width: 500, height: 400))
        #expect(capped.width == 200)
    }
}
