import CoreGraphics
import Foundation
import Testing
@testable import Refrax

/// Where a page dropped on a tab's panes joins it, and where a pane dragged in layout mode
/// lands.
struct PaneDropTests {
    private typealias Fixtures = PaneGridFixtures
    private let page = PaneGridGeometry(size: CGSize(width: 1_000, height: 800), columnSplit: 0.5, rowSplit: 0.5, metrics: .page)
    private let editing = PaneGridGeometry(size: CGSize(width: 1_000, height: 800), columnSplit: 0.5, rowSplit: 0.5, metrics: .editing)
    private let a = UUID()
    private let b = UUID()

    @Test(arguments: [
        (PaneEdge.leading, CGPoint(x: 50, y: 400)),
        (.trailing, CGPoint(x: 950, y: 400)),
        (.top, CGPoint(x: 500, y: 50)),
        (.bottom, CGPoint(x: 500, y: 750)),
    ])
    func `A page dropped near a side of a lone page takes that side`(edge: PaneEdge, point: CGPoint) {
        let grid = PaneGrid(spans: [a: .whole])
        #expect(PaneDrop.placement(at: point, in: grid, geometry: page) == .split(PaneSplit(target: a, edge: edge)))
    }

    @Test
    func `The middle of a pane joins nothing, and the nearest side wins in a corner`() {
        let grid = PaneGrid(spans: [a: .whole])
        #expect(PaneDrop.placement(at: CGPoint(x: 500, y: 400), in: grid, geometry: page) == nil)
        #expect(PaneDrop.placement(at: CGPoint(x: 30, y: 100), in: grid, geometry: page) == .split(PaneSplit(target: a, edge: .leading)))
    }

    @Test
    func `A pane one column wide only splits across its rows`() {
        let grid = PaneGrid(spans: [a: Fixtures.leftColumn, b: Fixtures.rightColumn])
        #expect(PaneDrop.placement(at: CGPoint(x: 30, y: 700), in: grid, geometry: page) == .split(PaneSplit(target: a, edge: .bottom)))
        #expect(PaneDrop.placement(at: CGPoint(x: 30, y: 400), in: grid, geometry: page) == nil)
        #expect(PaneDrop.placement(at: CGPoint(x: 900, y: 40), in: grid, geometry: page) == .split(PaneSplit(target: b, edge: .top)))
    }

    @Test
    func `A full grid takes no page`() {
        let quad = Fixtures.grid(GridCell.all.map(PaneSpan.init)).grid
        for point in [CGPoint(x: 10, y: 10), CGPoint(x: 500, y: 400), CGPoint(x: 990, y: 790)] {
            #expect(PaneDrop.placement(at: point, in: quad, geometry: page) == nil)
        }
    }

    @Test
    func `In layout mode an empty cell takes the page dropped on it`() {
        let grid = PaneGrid(spans: [a: PaneSpan(.topLeft), b: PaneSpan(.topRight)])
        #expect(PaneDrop.placement(at: CGPoint(x: 250, y: 600), in: grid, geometry: editing) == .cell(.bottomLeft))
        #expect(PaneDrop.placement(at: CGPoint(x: 750, y: 600), in: grid, geometry: editing) == .cell(.bottomRight))
    }

    @Test
    func `The landing frame is the half the page will take`() {
        let grid = PaneGrid(spans: [a: .whole])
        let frame = PaneDrop.frame(of: .split(PaneSplit(target: a, edge: .trailing)), joining: b, in: grid, geometry: page)
        #expect(frame == page.frame(of: Fixtures.rightColumn))
        let below = PaneDrop.frame(of: .split(PaneSplit(target: a, edge: .bottom)), joining: b, in: grid, geometry: page)
        #expect(below == page.frame(of: Fixtures.bottomRow))
    }

    @Test
    func `A dragged pane lands on the cell under its center, and nowhere over its own`() {
        let grid = PaneGrid(spans: [a: Fixtures.leftColumn, b: Fixtures.rightColumn])
        #expect(PaneDrop.cell(forDragging: a, by: CGSize(width: 500, height: -200), in: grid, geometry: editing) == .topRight)
        #expect(PaneDrop.cell(forDragging: a, by: CGSize(width: 500, height: 200), in: grid, geometry: editing) == .bottomRight)
        #expect(PaneDrop.cell(forDragging: a, by: CGSize(width: 10, height: 300), in: grid, geometry: editing) == nil)
        #expect(PaneDrop.cell(forDragging: a, by: CGSize(width: -2_000, height: 0), in: grid, geometry: editing) == nil)
    }
}
