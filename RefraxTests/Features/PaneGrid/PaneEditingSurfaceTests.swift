import CoreGraphics
import Foundation
import Testing
@testable import Refrax

/// The layout-mode surface: what a point is over, what a pane can do toward each side, and how
/// much of its controls fit.
struct PaneEditingSurfaceTests {
    private typealias Fixtures = PaneGridFixtures
    private let geometry = PaneGridGeometry(size: CGSize(width: 1_000, height: 800), columnSplit: 0.5, rowSplit: 0.5, metrics: .editing)
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    private func region(_ point: CGPoint, _ grid: PaneGrid) -> PaneEditingRegion {
        PaneEditingSurface.region(at: point, in: grid, geometry: geometry)
    }

    @Test
    func `A point in a pane is the pane, so the whole pane is a handle`() {
        let grid = PaneGrid(spans: [a: Fixtures.leftColumn, b: Fixtures.rightColumn])
        let left = geometry.frame(of: Fixtures.leftColumn)
        for point in [CGPoint(x: left.midX, y: left.midY), CGPoint(x: left.minX + 30, y: left.minY + 30), CGPoint(x: left.minX + 30, y: left.maxY - 30)] {
            #expect(region(point, grid) == .pane(a))
        }
    }

    @Test
    func `The gap between two panes, and a little of each edge, is the divider`() {
        let grid = PaneGrid(spans: [a: Fixtures.leftColumn, b: Fixtures.rightColumn])
        let line = geometry.columnLine
        let gap = geometry.metrics.gap
        for x in [line + gap / 2, line - 2, line + gap + 2] {
            #expect(region(CGPoint(x: x, y: 300), grid) == .divider(.column), "\(x)")
        }
        #expect(region(CGPoint(x: line - 20, y: 300), grid) == .pane(a))
    }

    @Test
    func `A three-pane grid's bars run only between different panes`() {
        let grid = PaneGrid(spans: [a: Fixtures.topRow, b: PaneSpan(.bottomLeft), c: PaneSpan(.bottomRight)])
        let topRowMiddle = CGPoint(x: geometry.columnLine + geometry.metrics.gap / 2, y: 100)
        #expect(region(topRowMiddle, grid) == .pane(a))
        let bottomRowMiddle = CGPoint(x: geometry.columnLine + geometry.metrics.gap / 2, y: 600)
        #expect(region(bottomRowMiddle, grid) == .divider(.column))
        #expect(region(CGPoint(x: 200, y: geometry.rowLine + geometry.metrics.gap / 2), grid) == .divider(.row))
    }

    @Test
    func `An empty cell is a target, and the margins are the surface`() {
        let grid = PaneGrid(spans: [a: PaneSpan(.topLeft), b: PaneSpan(.topRight)])
        let cell = geometry.frame(of: GridCell.bottomLeft)
        #expect(region(CGPoint(x: cell.midX, y: cell.midY), grid) == .emptyCell(.bottomLeft))
        #expect(region(CGPoint(x: 5, y: 5), grid) == .surface)
        #expect(region(CGPoint(x: 500, y: 790), grid) == .surface)
    }

    @Test
    func `Each side of a pane has at most one verb: grow where it is one cell thick, free where two`() {
        let grid = PaneGrid(spans: [a: Fixtures.leftColumn, b: PaneSpan(.topRight)])
        let left = PaneEditingVerbs(pageID: a, grid: grid)
        #expect(left.sides[.top] == .shrink(.top))
        #expect(left.sides[.bottom] == .shrink(.bottom))
        #expect(left.sides[.trailing] == nil)
        #expect(left.sides[.leading] == nil)
        let right = PaneEditingVerbs(pageID: b, grid: grid)
        #expect(right.sides[.bottom] == .grow(.bottom))
        #expect(right.sides[.leading] == nil)
        #expect(right.canLeave)
        #expect(PaneEditingVerbs(pageID: a, grid: PaneGrid(spans: [a: .whole])).canLeave == false)
    }

    @Test
    func `A grow arrow points out across its side and a free arrow points back in`() {
        #expect(PaneEditingVerbs.symbol(of: .grow(.leading)) == "arrow.left")
        #expect(PaneEditingVerbs.symbol(of: .shrink(.leading)) == "arrow.right")
        #expect(PaneEditingVerbs.symbol(of: .grow(.bottom)) == "arrow.down")
    }

    @Test
    func `A pane too small for its full controls gets the compact ones`() {
        #expect(PaneEditingSurface.controlStyle(for: CGSize(width: 600, height: 400)) == .full)
        #expect(PaneEditingSurface.controlStyle(for: CGSize(width: 280, height: 400)) == .compact)
        #expect(PaneEditingSurface.controlStyle(for: CGSize(width: 600, height: 200)) == .compact)
    }
}
