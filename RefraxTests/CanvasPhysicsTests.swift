import CoreGraphics
import Foundation
import Testing

@testable import Refrax

@Suite("Canvas Physics")
@MainActor
struct CanvasPhysicsTests {
    private static let desk = CGRect(x: 0, y: 0, width: 4800, height: 3000)
    private static let tileSize = CGSize(width: 320, height: 200)

    private static func tile(at x: CGFloat, _ y: CGFloat) -> CGRect {
        CGRect(origin: CGPoint(x: x, y: y), size: tileSize)
    }

    /// Steps until nothing moves, collecting every event. Fails if it never settles.
    private static func runToRest(_ world: inout CanvasPhysics, seconds: CGFloat = 10) -> [CanvasPhysics.Event] {
        var events: [CanvasPhysics.Event] = []
        var elapsed: CGFloat = 0
        while world.isRunning, elapsed < seconds {
            events += world.step(1.0 / 60)
            elapsed += 1.0 / 60
        }
        #expect(!world.isRunning, "world still moving after \(seconds) s")
        return events
    }

    private static func overlappingPairs(_ world: CanvasPhysics) -> Int {
        let boxes = world.bodies.values.map { CanvasPhysics.collisionBox($0.frame).insetBy(dx: 1, dy: 1) }
        var count = 0
        for i in boxes.indices {
            for j in (i + 1) ..< boxes.count where boxes[i].intersects(boxes[j]) {
                count += 1
            }
        }
        return count
    }

    @Test("Tiles that touch nothing stay put and report nothing")
    func restingTilesAreStable() {
        var world = CanvasPhysics(desk: Self.desk)
        let a = UUID(), b = UUID()
        world.place(a, frame: Self.tile(at: 200, 200))
        world.place(b, frame: Self.tile(at: 800, 200))

        let events = Self.runToRest(&world)

        #expect(events.isEmpty)
        #expect(world.bodies[a]?.frame == Self.tile(at: 200, 200))
        #expect(world.bodies[b]?.frame == Self.tile(at: 800, 200))
    }

    @Test("Overlapping tiles are pushed apart and both report where they rest")
    func overlapSeparates() {
        var world = CanvasPhysics(desk: Self.desk)
        let a = UUID(), b = UUID()
        world.place(a, frame: Self.tile(at: 1000, 1000))
        world.place(b, frame: Self.tile(at: 1100, 1040))

        let events = Self.runToRest(&world)

        #expect(Self.overlappingPairs(world) == 0)
        let settled = Set(events.compactMap { if case let .settled(id, _, dropped) = $0, !dropped { id } else { nil } })
        #expect(settled == [a, b])
    }

    @Test("A hand pressing slowly pushes a resting tile ahead and is not pushed back")
    func slowHandPushes() {
        var world = CanvasPhysics(desk: Self.desk)
        let held = UUID(), resting = UUID()
        world.place(held, frame: Self.tile(at: 980, 1000))
        world.place(resting, frame: Self.tile(at: 1320, 1000))
        _ = Self.runToRest(&world)

        // 0.3 pt per frame is 18 pt/s, below the speed at which a hand parts tiles.
        var frame = Self.tile(at: 980, 1000)
        for _ in 0 ..< 120 {
            frame.origin.x += 0.3
            world.drag(held, to: frame, elapsed: 1.0 / 60)
            _ = world.step(1.0 / 60)
        }

        #expect(world.bodies[held]?.frame == frame)
        let pushed = try! #require(world.bodies[resting]).frame
        #expect(pushed.minY == 1000)
        #expect(pushed.minX >= frame.maxX + CanvasPhysics.Constants.gap - 1)
    }

    @Test("A moving hand parts a tile in its path sideways instead of plowing it ahead")
    func movingHandPartsTiles() {
        var world = CanvasPhysics(desk: Self.desk)
        let held = UUID(), inPath = UUID()
        world.place(held, frame: Self.tile(at: 400, 1000))
        world.place(inPath, frame: Self.tile(at: 1000, 1000))
        _ = Self.runToRest(&world)

        var frame = Self.tile(at: 400, 1000)
        for _ in 0 ..< 60 {
            frame.origin.x += 20
            world.drag(held, to: frame, elapsed: 1.0 / 60)
            _ = world.step(1.0 / 60)
        }
        world.release(held, velocity: .zero, dropped: true)
        _ = Self.runToRest(&world)

        let parted = try! #require(world.bodies[inPath]).frame
        let forward = parted.minX - 1000
        let sideways = abs(parted.minY - 1000)
        #expect(sideways >= Self.tileSize.height)
        #expect(forward < 300, "plowed \(forward) pt ahead of the hand")
        #expect(Self.overlappingPairs(world) == 0)
    }

    @Test("A released tile with speed slides, then reports a drop")
    func flingSlidesAndDrops() {
        var world = CanvasPhysics(desk: Self.desk)
        let id = UUID()
        world.place(id, frame: Self.tile(at: 1000, 1000))
        world.drag(id, to: Self.tile(at: 1000, 1000), elapsed: 0)
        world.release(id, velocity: CGPoint(x: 900, y: 0), dropped: true)

        let events = Self.runToRest(&world)

        guard case let .settled(settledID, frame, dropped)? = events.last else {
            Issue.record("expected a settle, got \(events)")
            return
        }
        #expect(settledID == id)
        #expect(dropped)
        #expect(frame.minX > 1100)
        #expect(frame.minX == frame.minX.rounded())
    }

    @Test("A tile flung past the edge falls off and leaves the world")
    func flingOffEdgeFalls() {
        var world = CanvasPhysics(desk: Self.desk)
        let id = UUID()
        world.place(id, frame: Self.tile(at: 4300, 1000))
        world.release(id, velocity: CGPoint(x: 2000, y: 0), dropped: true)

        let events = Self.runToRest(&world)

        #expect(events.contains(.fell(id)))
        #expect(world.bodies[id] == nil)
    }

    @Test("A knocked tile stops at the edge instead of sliding off")
    func knockedTileStopsAtEdge() {
        var world = CanvasPhysics(desk: Self.desk)
        let id = UUID()
        world.place(id, frame: Self.tile(at: 1000, 200))
        world.release(id, velocity: CGPoint(x: 0, y: -4000), dropped: false)

        let events = Self.runToRest(&world)

        #expect(!events.contains(.fell(id)))
        let frame = try! #require(world.bodies[id]).frame
        #expect(Self.desk.contains(CGPoint(x: frame.midX, y: frame.midY)))
    }

    @Test("A tile left hanging over an edge comes to rest wholly on the desk")
    func restingTileIsDrawnOntoDesk() {
        var world = CanvasPhysics(desk: Self.desk)
        let id = UUID()
        // Center on the desk, most of the tile and its title above the top edge.
        world.place(id, frame: Self.tile(at: 665, -120))

        let events = Self.runToRest(&world)

        let frame = try! #require(world.bodies[id]).frame
        #expect(Self.desk.contains(CanvasPhysics.collisionBox(frame)))
        #expect(events.contains { if case .settled(id, _, _) = $0 { true } else { false } })
    }

    @Test("A tile with no room left falls off")
    func noRoomDropsATile() {
        var world = CanvasPhysics(desk: Self.desk)
        let held = UUID(), cornered = UUID()
        // The cornered tile's center sits 10 pt inside the bottom-right corner, so any
        // push along either axis carries it off.
        world.place(cornered, frame: CGRect(x: Self.desk.maxX - 170, y: Self.desk.maxY - 110, width: 320, height: 200))
        _ = Self.runToRest(&world)
        world.place(held, frame: Self.tile(at: Self.desk.maxX - 400, Self.desk.maxY - 300))
        world.drag(held, to: Self.tile(at: Self.desk.maxX - 400, Self.desk.maxY - 300), elapsed: 0)

        var events: [CanvasPhysics.Event] = []
        for _ in 0 ..< 30 {
            events += world.step(1.0 / 60)
        }

        #expect(events.contains(.fell(cornered)))
    }

    @Test("Opening a desk with more tiles than fit closes nothing and comes to rest")
    func overfullDeskSettlesWithoutFalls() {
        var world = CanvasPhysics(desk: Self.desk)
        // Twelve columns by ten rows fill the desk; the rest stack on the last row,
        // the way tiles for new tabs are placed.
        for index in 0 ..< 200 {
            let row = min(index / 12, 9)
            world.place(UUID(), frame: Self.tile(at: 120 + CGFloat(index % 12) * 368, 120 + CGFloat(row) * 272))
        }

        let events = Self.runToRest(&world)

        #expect(!events.contains { if case .fell = $0 { true } else { false } })
        #expect(world.bodies.count == 200)
    }

    @Test("A crowd dropped on one spot spreads out without overlaps")
    func crowdSpreads() {
        var world = CanvasPhysics(desk: Self.desk)
        // Scattered by two coprime strides, so the pile is the same on every run.
        for index in 0 ..< 60 {
            let x = 1800 + CGFloat(index * 137 % 800)
            let y = 1100 + CGFloat(index * 251 % 600)
            world.place(UUID(), frame: Self.tile(at: x, y))
        }

        _ = Self.runToRest(&world, seconds: 30)

        #expect(Self.overlappingPairs(world) == 0)
    }
}
