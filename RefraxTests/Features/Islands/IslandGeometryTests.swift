import CoreGraphics
import Foundation
import Testing
@testable import Refrax

@Suite("Island geometry")
struct IslandGeometryTests {
    private let titles = IslandGeometry(iconsOnly: false)

    private func rowCenter(_ row: Int) -> CGPoint {
        let frame = titles.rowFrame(row)
        return CGPoint(x: frame.midX, y: frame.midY)
    }

    @Test("An island is as wide as its kind and as tall as its band, rows, the New Tab row, and padding")
    func size() {
        #expect(titles.width == IslandGeometry.titleWidth)
        #expect(IslandGeometry(iconsOnly: true).width == IslandGeometry.iconWidth)
        let three = titles.contentHeight(rows: 3)
        #expect(three == IslandGeometry.bandHeight + 4 * IslandGeometry.rowHeight + 2 * IslandGeometry.padding)
        #expect(titles.size(rows: 3, in: CGSize(width: 1600, height: 1000)).height == three)
    }

    @Test("Past the window's share of height the island stops growing")
    func capped() {
        let window = CGSize(width: 1600, height: 500)
        #expect(titles.size(rows: 40, in: window).height == window.height * IslandGeometry.maximumShare)
        #expect(titles.size(rows: 0, in: CGSize(width: 1600, height: 10)).height == titles.contentHeight(rows: 0))
    }

    @Test("Rows stack under the band, each a row tall")
    func rowFrames() {
        let first = titles.rowFrame(0)
        let second = titles.rowFrame(1)
        #expect(first.minY == IslandGeometry.bandHeight + IslandGeometry.padding)
        #expect(second.minY == first.maxY)
        #expect(first.width == IslandGeometry.titleWidth - 2 * IslandGeometry.padding)
    }

    @Test("A drop on a row's top half goes before it, on its bottom half after it, and never past the end")
    func insertion() {
        let row1 = titles.rowFrame(1)
        #expect(titles.insertion(at: CGPoint(x: 10, y: row1.minY + 2), count: 4) == 1)
        #expect(titles.insertion(at: CGPoint(x: 10, y: row1.maxY - 2), count: 4) == 2)
        #expect(titles.insertion(at: CGPoint(x: 10, y: -50), count: 4) == 0)
        #expect(titles.insertion(at: CGPoint(x: 10, y: 5000), count: 4) == 4)
    }

    @Test("A drop on a row's middle joins it; on its edges it does not; past the rows it is nothing")
    func joinedRow() {
        #expect(titles.joinedRow(at: rowCenter(2), count: 4) == 2)
        let row2 = titles.rowFrame(2)
        #expect(titles.joinedRow(at: CGPoint(x: 10, y: row2.minY + 1), count: 4) == nil)
        #expect(titles.joinedRow(at: CGPoint(x: 10, y: row2.maxY - 1), count: 4) == nil)
        #expect(titles.joinedRow(at: rowCenter(4), count: 4) == nil)
        #expect(titles.joinedRow(at: CGPoint(x: 10, y: -10), count: 4) == nil)
    }
}

@Suite("Island state")
struct IslandStateTests {
    @Test("Placements and detached tabs survive a round trip through JSON")
    func roundTrip() throws {
        let island = UUID()
        let tab = UUID()
        var state = IslandState()
        state.islands[island] = IslandPlacement(x: 0.25, y: 0.5, isPinned: true, iconsOnly: true)
        state.detached.insert(tab)
        let decoded = IslandState.decode(state.encoded())
        #expect(decoded == state)
        #expect(decoded.islands[island]?.isPinned == true)
        #expect(decoded.detached.contains(tab))
    }

    @Test("Bytes that are not a state decode to an empty one")
    func garbage() {
        #expect(IslandState.decode(Data("not json".utf8)) == IslandState())
        #expect(IslandState.decode(nil) == IslandState())
    }

    @Test("Pruning forgets islands and detached tabs that are gone")
    func prune() {
        let kept = UUID(), gone = UUID()
        var state = IslandState(islands: [kept: IslandPlacement(x: 0, y: 0), gone: IslandPlacement(x: 1, y: 1)], detached: [kept, gone])
        state.prune(tabs: [kept], islands: [kept])
        #expect(state.islands.keys.contains(kept))
        #expect(!state.islands.keys.contains(gone))
        #expect(state.detached == [kept])
    }
}
