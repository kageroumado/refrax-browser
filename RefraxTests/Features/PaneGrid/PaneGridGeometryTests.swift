import AppKit
import Testing
@testable import Refrax

/// Where panes and dividers stand in a page: whole points, exact gaps, the split ratios kept
/// in and out of layout mode.
struct PaneGridGeometryTests {
    private typealias Fixtures = PaneGridFixtures

    static let sizes: [CGSize] = [
        CGSize(width: 1_440, height: 900),
        CGSize(width: 1_000.5, height: 733.25),
        CGSize(width: 1_279.7, height: 801.3),
        CGSize(width: 321, height: 241),
    ]
    static let splits: [Double] = [0.5, 0.3, 0.7, 0.4137]
    private static let metrics: [PaneGridMetrics] = [.page, .editing]

    private func isWhole(_ value: CGFloat) -> Bool {
        value == value.rounded()
    }

    /// Fractional pane frames left WebKit compositing at half points and blurred the panes'
    /// edges; every frame, in every layout, window size, and split, is whole points.
    @Test(arguments: PaneGridGeometryTests.sizes, PaneGridGeometryTests.splits)
    func `Every pane frame is in whole points`(size: CGSize, split: Double) {
        for metrics in Self.metrics {
            let geometry = PaneGridGeometry(size: size, columnSplit: split, rowSplit: 1 - split, metrics: metrics)
            for spans in Fixtures.tilings + [[.whole]] {
                for frame in geometry.frames(for: Fixtures.grid(spans).grid).values {
                    #expect(isWhole(frame.minX) && isWhole(frame.minY) && isWhole(frame.width) && isWhole(frame.height), "\(frame)")
                }
            }
            for divider in geometry.dividers(for: Fixtures.grid(GridCell.all.map(PaneSpan.init)).grid) {
                #expect(isWhole(divider.frame.minX) && isWhole(divider.frame.minY) && isWhole(divider.frame.width) && isWhole(divider.frame.height))
            }
        }
    }

    @Test(arguments: PaneGridGeometryTests.sizes, PaneGridGeometryTests.splits)
    func `Neighboring panes stand exactly one gap apart and never overlap`(size: CGSize, split: Double) {
        for metrics in Self.metrics {
            let geometry = PaneGridGeometry(size: size, columnSplit: split, rowSplit: split, metrics: metrics)
            for spans in Fixtures.tilings {
                let frames = spans.map(geometry.frame(of:))
                for (i, first) in frames.enumerated() {
                    for (j, second) in frames.enumerated() where i != j {
                        let overlap = first.intersection(second)
                        #expect(overlap.isNull || overlap.width * overlap.height == 0)
                        let horizontal = second.minX - first.maxX
                        let vertical = second.minY - first.maxY
                        if first.maxY > second.minY, second.maxY > first.minY, horizontal >= 0 {
                            #expect(horizontal == metrics.gap)
                        }
                        if first.maxX > second.minX, second.maxX > first.minX, vertical >= 0 {
                            #expect(vertical == metrics.gap)
                        }
                    }
                }
            }
        }
    }

    /// On the page the panes run edge to edge and the dividers fill the gaps: no point of the
    /// page is under two panes or under none and no divider.
    @Test(arguments: PaneGridFixtures.tilings)
    func `On the page, panes and dividers cover the page once`(spans: [PaneSpan]) {
        let geometry = PaneGridGeometry(size: CGSize(width: 301, height: 211), columnSplit: 0.37, rowSplit: 0.61, metrics: .page)
        let grid = Fixtures.grid(spans).grid
        let panes = Array(geometry.frames(for: grid).values)
        let dividers = geometry.dividers(for: grid).map(\.frame)
        var underTwo: [CGPoint] = []
        var underNone: [CGPoint] = []
        for x in stride(from: 0.5, to: 301, by: 1) {
            for y in stride(from: 0.5, to: 211, by: 1) {
                let point = CGPoint(x: x, y: y)
                let inPanes = panes.filter { $0.contains(point) }.count
                if inPanes > 1 {
                    underTwo.append(point)
                } else if inPanes == 0, !dividers.contains(where: { $0.contains(point) }) {
                    underNone.append(point)
                }
            }
        }
        #expect(underTwo.isEmpty, "\(underTwo.prefix(3))")
        #expect(underNone.isEmpty, "\(underNone.prefix(3))")
    }

    /// Layout mode once laid every pane out at a quarter of the page whatever the dividers
    /// said, so a 30/70 split jumped to 50/50 on entering and back on leaving.
    @Test(arguments: [0.3, 0.5, 0.7])
    func `Layout mode keeps the page's split ratios`(split: Double) {
        let size = CGSize(width: 1_200, height: 800)
        for metrics in Self.metrics {
            let geometry = PaneGridGeometry(size: size, columnSplit: split, rowSplit: split, metrics: metrics)
            let usable = geometry.content.width - metrics.gap
            let left = geometry.frame(of: Fixtures.leftColumn)
            #expect(abs(left.width - usable * split) <= 0.5)
            let top = geometry.frame(of: Fixtures.topRow)
            #expect(abs(top.height - (geometry.content.height - metrics.gap) * split) <= 0.5)
        }
    }

    @Test
    func `Layout mode insets the panes on every side, their corners concentric with the window's`() {
        let geometry = PaneGridGeometry(size: CGSize(width: 1_000, height: 700), columnSplit: 0.5, rowSplit: 0.5, metrics: .editing)
        #expect(geometry.content == CGRect(x: 8, y: 8, width: 984, height: 684))
        #expect(PaneGridMetrics.editing.cornerRadius == WindowCorner.radius - PaneGridMetrics.editing.inset)
        let page = PaneGridGeometry(size: CGSize(width: 1_000, height: 700), columnSplit: 0.5, rowSplit: 0.5, metrics: .page)
        #expect(page.frame(of: .whole) == CGRect(x: 0, y: 0, width: 1_000, height: 700))
    }

    /// Tab previews laid the top row out at the bottom and gave it the bottom row's height.
    @Test
    func `The top row is at the top with the top row's share`() {
        let geometry = PaneGridGeometry(size: CGSize(width: 400, height: 301), columnSplit: 0.5, rowSplit: 0.25, metrics: .page)
        let top = geometry.frame(of: GridCell.topLeft)
        let bottom = geometry.frame(of: GridCell.bottomLeft)
        #expect(top.minY == 0)
        #expect(top.height == 75)
        #expect(bottom.minY == top.maxY + 1)
        #expect(bottom.maxY == 301)
    }

    @Test @MainActor
    func `Tab previews lay out from the top left as the page does`() {
        #expect(ThumbnailAdapter(frame: .zero).isFlipped)
    }

    @Test
    func `A divider runs only where the panes on either side differ`() throws {
        let geometry = PaneGridGeometry(size: CGSize(width: 1_001, height: 801), columnSplit: 0.5, rowSplit: 0.5, metrics: .page)
        let wideTop = Fixtures.grid([Fixtures.topRow, PaneSpan(.bottomLeft), PaneSpan(.bottomRight)]).grid
        let topDividers = geometry.dividers(for: wideTop)
        let column = try #require(topDividers.first { $0.axis == .column })
        #expect(column.frame.minY == geometry.rowLine + 1)
        #expect(column.frame.maxY == geometry.content.maxY)
        let row = try #require(topDividers.first { $0.axis == .row })
        #expect(row.frame.width == geometry.content.width)

        let tallLeft = Fixtures.grid([Fixtures.leftColumn, PaneSpan(.topRight), PaneSpan(.bottomRight)]).grid
        let leftRow = try #require(geometry.dividers(for: tallLeft).first { $0.axis == .row })
        #expect(leftRow.frame.minX == geometry.columnLine + 1)
        #expect(leftRow.frame.maxX == geometry.content.maxX)

        let columns = Fixtures.grid([Fixtures.leftColumn, Fixtures.rightColumn]).grid
        #expect(geometry.dividers(for: columns).map(\.axis) == [.column])
        #expect(geometry.dividers(for: PaneGrid(spans: [UUID(): .whole])).isEmpty)
    }

    @Test
    func `A divider's line fills the gap between its panes`() {
        let geometry = PaneGridGeometry(size: CGSize(width: 1_000, height: 700), columnSplit: 0.42, rowSplit: 0.5, metrics: .page)
        let columns = Fixtures.grid([Fixtures.leftColumn, Fixtures.rightColumn]).grid
        let line = geometry.dividers(for: columns)[0].frame
        #expect(line.minX == geometry.frame(of: Fixtures.leftColumn).maxX)
        #expect(line.maxX == geometry.frame(of: Fixtures.rightColumn).minX)
        #expect(line.height == 700)
        #expect(geometry.dividers(for: columns)[0].grabFrame(reach: 9).width == 9)
    }

    @Test
    func `A point names the cell it is in, and none off the page`() {
        let geometry = PaneGridGeometry(size: CGSize(width: 1_000, height: 800), columnSplit: 0.5, rowSplit: 0.5, metrics: .editing)
        #expect(geometry.cell(at: CGPoint(x: 100, y: 100)) == .topLeft)
        #expect(geometry.cell(at: CGPoint(x: 900, y: 100)) == .topRight)
        #expect(geometry.cell(at: CGPoint(x: 100, y: 700)) == .bottomLeft)
        #expect(geometry.cell(at: CGPoint(x: 900, y: 700)) == .bottomRight)
        #expect(geometry.cell(at: CGPoint(x: 2, y: 2)) == nil)
    }

    @Test
    func `A dragged divider sets the split under the pointer, within limits`() {
        let geometry = PaneGridGeometry(size: CGSize(width: 1_001, height: 801), columnSplit: 0.5, rowSplit: 0.5, metrics: .page)
        let split = geometry.split(for: .column, at: geometry.columnLine + 0.5)
        #expect(abs(split - 0.5) < 0.001)
        #expect(geometry.split(for: .column, at: 0) == PaneSplitRatio.range.lowerBound)
        #expect(geometry.split(for: .row, at: 5_000) == PaneSplitRatio.range.upperBound)
    }

    @Test
    func `A released split rests at a resting point it is near`() {
        #expect(PaneSplitRatio.settled(0.51) == 0.5)
        #expect(PaneSplitRatio.settled(0.34) == 1.0 / 3.0)
        #expect(PaneSplitRatio.settled(0.45) == 0.45)
        #expect(PaneSplitRatio.settled(0.95) == 0.8)
        #expect(PaneSplitRatio.clamped(.nan) == 0.5)
    }
}
