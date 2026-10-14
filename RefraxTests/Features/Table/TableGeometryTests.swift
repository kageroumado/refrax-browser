import Foundation
import Testing
@testable import Refrax

struct TableGeometryTests {
    private typealias Row = TableLayout.RowSource
    private typealias Position = TableLayout.Position

    private let space = UUID()
    private let research = UUID()
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let geometry = TableGeometry(viewport: CGSize(width: 1_000, height: 600), gap: 12, bandHeight: 56)

    /// a full in the loose row; b and c half in Research.
    private var layout: TableLayout {
        var state = TableState()
        state.setWidth(.half, of: b)
        state.setWidth(.half, of: c)
        return TableLayout(rows: [Row(id: space, tabIDs: [a]), Row(id: research, tabIDs: [b, c])], state: state)
    }

    @Test
    func `A row of fractions summing to one fills the viewport with the gap between its slabs`() {
        let layout = layout
        #expect(geometry.frame(of: a, in: layout) == CGRect(x: 0, y: 0, width: 1_000, height: 600))
        #expect(geometry.frame(of: b, in: layout) == CGRect(x: 0, y: 612, width: 494, height: 600))
        #expect(geometry.frame(of: c, in: layout) == CGRect(x: 506, y: 612, width: 494, height: 600))
        #expect(geometry.rowLength(layout.rows[1]) == 1_000)
        #expect(geometry.emptyRowFrame(in: layout) == CGRect(x: 0, y: 1_224, width: 1_000, height: 600))
        #expect(geometry.tableSize(of: layout) == CGSize(width: 1_000, height: 1_824))
    }

    @Test
    func `A collapsed row is a band the viewport wide and the rows below move up`() {
        let layout = TableLayout(rows: [Row(id: space, isCollapsed: true, tabIDs: [a]), Row(id: research, tabIDs: [b])])
        #expect(geometry.rowFrame(0, in: layout) == CGRect(x: 0, y: 0, width: 1_000, height: 56))
        #expect(geometry.frame(of: a, in: layout) == CGRect(x: 0, y: 0, width: 1_000, height: 56))
        #expect(geometry.frame(of: b, in: layout) == CGRect(x: 0, y: 68, width: 1_000, height: 600))
        #expect(geometry.slabs(in: CGRect(x: 0, y: 0, width: 1_000, height: 100), of: layout).map(\.tabID) == [b])
        #expect(geometry.rows(in: CGRect(x: 0, y: 0, width: 1_000, height: 60), of: layout) == [0])
    }

    @Test
    func `The plane is never narrower than the viewport and ends with the empty row`() {
        var state = TableState()
        state.setWidth(.third, of: a)
        let layout = TableLayout(rows: [Row(id: space, tabIDs: [a])], state: state)
        #expect(geometry.tableSize(of: layout) == CGSize(width: 1_000, height: 1_212))
        #expect(geometry.clamped(CGPoint(x: 300, y: 300), in: layout) == CGPoint(x: 0, y: 300))
        #expect(geometry.clamped(CGPoint(x: 300, y: 900), in: layout) == CGPoint(x: 0, y: 612))
    }

    @Test
    func `A rect lists the slabs it touches and the point under it`() {
        let layout = layout
        let shown = geometry.slabs(in: CGRect(x: 0, y: 300, width: 1_000, height: 600), of: layout)
        #expect(shown.map(\.tabID) == [a, b, c])
        #expect(geometry.slab(at: CGPoint(x: 700, y: 900), in: layout) == Position(row: 1, slab: 1))
        #expect(geometry.slab(at: CGPoint(x: 500, y: 900), in: layout) == nil)
        #expect(geometry.slab(at: CGPoint(x: 500, y: 605), in: layout) == nil)
    }

    @Test
    func `The most visible slab wins by area, then by distance to the center`() {
        let layout = layout
        #expect(geometry.mostVisibleSlab(in: CGRect(x: 0, y: 400, width: 1_000, height: 600), of: layout) == Position(row: 0, slab: 0))
        #expect(geometry.mostVisibleSlab(in: CGRect(x: 0, y: 612, width: 1_000, height: 600), of: layout) == Position(row: 1, slab: 0))
        #expect(geometry.mostVisibleSlab(in: CGRect(x: 100, y: 612, width: 1_000, height: 600), of: layout) == Position(row: 1, slab: 1))
        #expect(geometry.mostVisibleSlab(in: CGRect(x: 0, y: 2_000, width: 10, height: 10), of: layout) == nil)
    }

    @Test
    func `Revealing moves the least on each axis and clamps to the plane`() {
        let layout = layout
        let frames = (a: geometry.frame(of: a, in: layout)!, c: geometry.frame(of: c, in: layout)!)
        #expect(geometry.origin(revealing: frames.c, from: .zero, in: layout) == CGPoint(x: 0, y: 612))
        #expect(geometry.origin(revealing: frames.a, from: CGPoint(x: 0, y: 612), in: layout) == .zero)
        #expect(geometry.origin(revealing: frames.a, from: CGPoint(x: 0, y: 100), in: layout) == .zero)
        #expect(geometry.origin(revealing: frames.c, from: CGPoint(x: 0, y: 612), in: layout) == CGPoint(x: 0, y: 612))
        #expect(geometry.isWhole(frames.c, at: CGPoint(x: 0, y: 612)))
        #expect(!geometry.isWhole(frames.c, at: CGPoint(x: 0, y: 400)))
    }

    @Test
    func `A frame larger than the viewport is centered on it`() {
        let small = TableGeometry(viewport: CGSize(width: 400, height: 600), gap: 12, bandHeight: 56)
        let layout = TableLayout(rows: [Row(id: space, tabIDs: [a, b])])
        // Two full slabs make a plane 812 wide; b spans 412...812.
        let b = small.frame(of: b, in: layout)!
        #expect(b == CGRect(x: 412, y: 0, width: 400, height: 600))
        #expect(small.origin(revealing: b, from: .zero, in: layout) == CGPoint(x: 412, y: 0))
        let wide = CGRect(x: 0, y: 0, width: 800, height: 600)
        #expect(small.origin(revealing: wide, from: .zero, in: layout) == CGPoint(x: 200, y: 0))
    }
}
