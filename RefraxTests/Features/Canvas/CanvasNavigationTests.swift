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
            .left: tile(120, 500), .right: tile(880, 500),
            .up: tile(500, 240), .down: tile(500, 760),
        ]
        let tiles = [center] + neighbors.values
        #expect(CanvasNavigation.neighbor(from: center.id, toward: direction, in: tiles) == neighbors[direction]?.id)
    }

    @Test
    func `nearby preview rows remain connected across their table gap`() {
        let upper = tile(0, 0)
        let lower = tile(0, 272)
        #expect(CanvasNavigation.neighbor(from: upper.id, toward: .down, in: [upper, lower]) == lower.id)
        #expect(CanvasNavigation.neighbor(from: lower.id, toward: .up, in: [upper, lower]) == upper.id)
    }

    @Test
    func `small slabs across open space remain separate`() {
        let left = tile(0, 0, width: 40, height: 40)
        let right = tile(100, 0, width: 40, height: 40)
        #expect(CanvasNavigation.neighbor(from: left.id, toward: .right, in: [left, right]) == nil)
    }

    @Test
    func `An arrow follows an aligned neighbor`() {
        let origin = tile(500, 500)
        let diagonal = tile(850, 750)
        let sameRow = tile(850, 550)
        #expect(CanvasNavigation.neighbor(from: origin.id, toward: .right, in: [origin, diagonal, sameRow]) == sameRow.id)
    }

    @Test
    func `A sparse desk has no unannounced diagonal destination`() {
        let origin = tile(500, 500)
        let behind = tile(0, 500)
        let next = tile(900, 900)
        #expect(CanvasNavigation.neighbor(from: origin.id, toward: .right, in: [origin, behind, next]) == nil)
        #expect(CanvasNavigation.neighbor(from: origin.id, toward: .up, in: [origin, behind, next]) == nil)
    }

    @Test
    func `Equal edge distances favor the closer row center`() {
        let origin = tile(500, 500)
        let first = tile(850, 480)
        let second = tile(850, 530)
        #expect(CanvasNavigation.neighbor(from: origin.id, toward: .right, in: [origin, first, second]) == first.id)
        #expect(CanvasNavigation.nearest(to: CGPoint(x: 1_060, y: 600), in: [first, second]) == first.id)
    }

    @Test
    func `Groups form boundaries even when their cards touch`() {
        let travel = UUID()
        let news = UUID()
        let hotel = CanvasNavigation.Tile(id: UUID(), frame: CGRect(x: 0, y: 0, width: 250, height: 34), groupID: travel)
        let map = CanvasNavigation.Tile(id: UUID(), frame: CGRect(x: 262, y: 0, width: 250, height: 34), groupID: travel)
        let headlines = CanvasNavigation.Tile(id: UUID(), frame: CGRect(x: 524, y: 0, width: 250, height: 34), groupID: news)
        let tiles = [hotel, map, headlines]
        #expect(CanvasNavigation.neighbor(from: hotel.id, toward: .right, in: tiles) == map.id)
        #expect(CanvasNavigation.neighbor(from: map.id, toward: .left, in: tiles) == hotel.id)
        #expect(CanvasNavigation.neighbor(from: map.id, toward: .right, in: tiles) == nil)
    }

    @Test
    func `An asymmetric arrangement has no one way edge`() {
        let a = tile(0, 0, width: 100, height: 40)
        let b = tile(112, 0, width: 100, height: 40)
        let c = tile(112, 25, width: 100, height: 40)
        #expect(CanvasNavigation.neighbor(from: a.id, toward: .right, in: [a, b, c]) == b.id)
        #expect(CanvasNavigation.neighbor(from: c.id, toward: .left, in: [a, b, c]) == nil)
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
