import CoreGraphics
import Foundation
import Testing
@testable import Refrax

struct CanvasNavigationTests {
    private func tile(_ x: CGFloat, _ y: CGFloat, width: CGFloat = 320, height: CGFloat = 200) -> CanvasNavigation.Tile {
        CanvasNavigation.Tile(id: UUID(), frame: CGRect(x: x, y: y, width: width, height: height))
    }

    @Test(arguments: CanvasNavigation.Direction.allCases)
    func `Arrows follow the spatial grid in all four directions`(_ direction: CanvasNavigation.Direction) {
        let center = tile(500, 500)
        let neighbors: [CanvasNavigation.Direction: CanvasNavigation.Tile] = [
            .left: tile(100, 500), .right: tile(900, 500),
            .up: tile(500, 200), .down: tile(500, 800),
        ]
        let tiles = [center] + neighbors.values
        #expect(CanvasNavigation.neighbor(from: center.id, toward: direction, in: tiles) == neighbors[direction]?.id)
    }

    @Test
    func `An arrow prefers its row over a closer diagonal tile`() {
        let origin = tile(500, 500)
        let diagonal = tile(550, 750)
        let sameRow = tile(1_200, 550)
        #expect(CanvasNavigation.neighbor(from: origin.id, toward: .right, in: [origin, diagonal, sameRow]) == sameRow.id)
    }

    @Test
    func `A sparse desk still supports diagonal neighbors`() {
        let origin = tile(500, 500)
        let behind = tile(0, 500)
        let next = tile(900, 900)
        #expect(CanvasNavigation.neighbor(from: origin.id, toward: .right, in: [origin, behind, next]) == next.id)
        #expect(CanvasNavigation.neighbor(from: origin.id, toward: .up, in: [origin, behind, next]) == nil)
    }

    @Test
    func `Equal distances use stable tab order`() {
        let origin = tile(500, 500)
        let first = tile(900, 250)
        let second = tile(900, 750)
        #expect(CanvasNavigation.neighbor(from: origin.id, toward: .right, in: [origin, first, second]) == first.id)
        #expect(CanvasNavigation.nearest(to: CGPoint(x: 1_060, y: 600), in: [first, second]) == first.id)
    }

    @Test
    func `Peek retains its destination across small movements at the boundary`() {
        let left = tile(0, 0)
        let right = tile(400, 0)
        let tiles = [left, right]
        #expect(CanvasNavigation.nearest(to: CGPoint(x: 363, y: 100), in: tiles, retaining: left.id, hysteresis: 18) == left.id)
        #expect(CanvasNavigation.nearest(to: CGPoint(x: 380, y: 100), in: tiles, retaining: left.id, hysteresis: 18) == right.id)
        #expect(CanvasNavigation.nearest(to: CGPoint(x: 405, y: 100), in: tiles, retaining: left.id, hysteresis: 18) == right.id)
    }

    @Test
    func `Removed targets and empty desks are handled`() {
        let remaining = tile(500, 500)
        #expect(CanvasNavigation.nearest(to: .zero, in: [remaining], retaining: UUID()) == remaining.id)
        #expect(CanvasNavigation.neighbor(from: UUID(), toward: .left, in: [remaining]) == nil)
        #expect(CanvasNavigation.nearest(to: .zero, in: []) == nil)
    }

    @Test
    func `A closing pinch stays on the desk`() {
        var intent = CanvasPinchIntent()
        intent.update(by: -0.2)
        intent.update(by: 0.03)
        #expect(intent.shouldEnter == false)
    }

    @Test
    func `An opening pinch can enter its starting tile`() {
        var intent = CanvasPinchIntent()
        intent.update(by: 0.2)
        intent.update(by: 0)
        #expect(intent.shouldEnter)
    }

    @Test
    func `Reversing a pinch before release stays on the desk`() {
        var intent = CanvasPinchIntent()
        intent.update(by: 0.4)
        intent.update(by: -0.05)
        #expect(intent.scale > 1)
        #expect(intent.shouldEnter == false)
    }

    @Test
    func `Stationary and non-finite pinch steps do not trigger entry`() {
        var intent = CanvasPinchIntent()
        intent.update(by: .nan)
        intent.update(by: .infinity)
        intent.update(by: 0.001)
        #expect(intent.shouldEnter == false)
        #expect(intent.scale.isFinite)
    }
}
