import CoreGraphics
import Testing
@testable import Refrax

/// Where a dropped row's island goes, and where the hint stands.
struct IslandDropPlacementTests {
    private let area = CGRect(x: 16, y: 16, width: 1_408, height: 1_048)
    private let geometry = IslandGeometry(iconsOnly: false)

    @Test
    func `The ghost puts the pointer on the middle of its first row`() {
        let frame = IslandDropPlacement.frame(at: CGPoint(x: 700, y: 400), rows: 1, geometry: geometry, area: area, window: area.size)
        #expect(frame.width == IslandGeometry.titleWidth)
        #expect(frame.height == IslandGeometry.headerReserve + geometry.contentHeight(rows: 1))
        #expect(frame.midX == 700)
        #expect(frame.minY + IslandGeometry.headerReserve + IslandGeometry.padding + IslandGeometry.rowHeight / 2 == 400)
    }

    @Test
    func `A ghost of several rows grows by a row each`() {
        let one = IslandDropPlacement.frame(at: CGPoint(x: 700, y: 400), rows: 1, geometry: geometry, area: area, window: area.size)
        let three = IslandDropPlacement.frame(at: CGPoint(x: 700, y: 400), rows: 3, geometry: geometry, area: area, window: area.size)
        #expect(three.height - one.height == 2 * IslandGeometry.rowHeight)
        #expect(three.minY == one.minY)
    }

    @Test
    func `The ghost is held inside the area at every corner`() {
        for point in [CGPoint(x: -50, y: -50), CGPoint(x: 5_000, y: -50), CGPoint(x: -50, y: 5_000), CGPoint(x: 5_000, y: 5_000)] {
            let frame = IslandDropPlacement.frame(at: point, rows: 2, geometry: geometry, area: area, window: area.size)
            #expect(area.contains(frame), "\(point)")
        }
    }

    @Test
    func `The placement reads back to the ghost's frame`() {
        let frame = IslandDropPlacement.frame(at: CGPoint(x: 1_000, y: 800), rows: 2, geometry: geometry, area: area, window: area.size)
        let placement = IslandDropPlacement.placement(for: frame, in: area)
        let x = area.minX + placement.x * area.width
        let y = area.minY + placement.y * area.height - IslandGeometry.headerReserve
        #expect(abs(x - frame.minX) < 0.001)
        #expect(abs(y - frame.minY) < 0.001)
        #expect(!placement.isPinned && !placement.iconsOnly)
    }

    @Test
    func `The hint stands to the right, then below, then to the left`() {
        let size = CGSize(width: 250, height: 28)
        let left = CGRect(x: 100, y: 100, width: 236, height: 200)
        #expect(IslandDropPlacement.hintOrigin(beside: left, size: size, gap: 10, in: area) == CGPoint(x: 346, y: 100))
        let right = CGRect(x: area.maxX - 236, y: 100, width: 236, height: 200)
        // Below, pulled left so the whole hint stays inside the area.
        #expect(IslandDropPlacement.hintOrigin(beside: right, size: size, gap: 10, in: area) == CGPoint(x: area.maxX - 250, y: 310))
        let corner = CGRect(x: area.maxX - 236, y: area.maxY - 200, width: 236, height: 200)
        let origin = IslandDropPlacement.hintOrigin(beside: corner, size: size, gap: 10, in: area)
        #expect(origin == CGPoint(x: corner.minX - 260, y: corner.minY))
    }
}
