import AppKit
import Observation
import Synchronization
import Testing
@testable import Refrax

@MainActor
struct ControlIslandInteractionTests {
    private let area = CGRect(x: 0, y: 0, width: 900, height: 650)

    @Test(arguments: [0.0, 0.5, 1.0], [0.0, 0.5, 1.0])
    func `the page branch unfolds beside the rail's top row within the window`(x: Double, y: Double) {
        let placement = ControlIslandPlacement(x: x, y: y)
        let rail = placement.railFrame(in: area, height: 520)
        let top = CGRect(x: rail.minX, y: rail.minY, width: rail.width, height: ControlIslandPlacement.railWidth)
        let page = placement.pageBranchFrame(in: area, anchor: top, height: 40)
        #expect(area.contains(rail))
        #expect(area.contains(page))
        #expect(rail.intersects(page) == false)
        #expect(page.minY == rail.minY)
    }

    @Test
    func `the rail rests when the pointer is far or still and wakes as it approaches`() {
        let state = ControlIslandState(defaults: nil, configuration: .init(defaults: nil))
        state.hitRegions = [CGRect(x: 12, y: 12, width: 48, height: 400)]
        let start = Date(timeIntervalSince1970: 1_000)
        _ = state.tracksPointer(CGPoint(x: 100, y: 100), now: start)
        #expect(!state.isQuiet)
        #expect(!state.quietIfStill(now: start.addingTimeInterval(1)))
        #expect(state.quietIfStill(now: start.addingTimeInterval(ControlIslandState.stillDelay)))
        #expect(state.isQuiet)
        _ = state.tracksPointer(CGPoint(x: 700, y: 500), now: start.addingTimeInterval(4))
        #expect(state.isQuiet)
        _ = state.tracksPointer(CGPoint(x: 150, y: 200), now: start.addingTimeInterval(5))
        #expect(!state.isQuiet)
        _ = state.tracksPointer(CGPoint(x: 250, y: 200), now: start.addingTimeInterval(6))
        #expect(!state.isQuiet)
        _ = state.tracksPointer(CGPoint(x: 300, y: 200), now: start.addingTimeInterval(7))
        #expect(state.isQuiet)
    }

    @Test
    func `magnetic placement attracts nearby edges and preserves free placement`() {
        let corner = ControlIslandPlacement(x: 0.01, y: 0.01).snapped(in: area, height: 48)
        #expect(corner == ControlIslandPlacement(x: 0, y: 0))
        let edge = ControlIslandPlacement(x: 0.99, y: 0.51).snapped(in: area, height: 48)
        #expect(edge == ControlIslandPlacement(x: 1, y: 0.5))
        let free = ControlIslandPlacement(x: 0.4, y: 0.4)
        #expect(free.snapped(in: area, height: 48) == free)
    }

    @Test
    func `diagonal travel keeps the destination open without claiming surrounding page space`() {
        let origin = CGPoint(x: 20, y: 20)
        let target = CGRect(x: 100, y: 100, width: 80, height: 40)
        #expect(ControlIslandHoverPath.bridges(CGPoint(x: 60, y: 60), from: origin, to: target))
        #expect(ControlIslandHoverPath.bridges(CGPoint(x: 25, y: 120), from: origin, to: target) == false)
        #expect(ControlIslandHoverPath.bridges(CGPoint(x: 300, y: 20), from: origin, to: target) == false)
    }

    @Test
    func `hover grace expires when the pointer parks between branches`() {
        var path = ControlIslandHoverPath()
        let start = Date(timeIntervalSince1970: 1_000)
        let regions = [CGRect(x: 0, y: 0, width: 48, height: 48), CGRect(x: 100, y: 100, width: 80, height: 40)]
        let inside = path.phase(at: CGPoint(x: 20, y: 20), regions: regions, now: start)
        let crossing = path.phase(at: CGPoint(x: 60, y: 60), regions: regions, now: start.addingTimeInterval(0.2))
        let expired = path.phase(at: CGPoint(x: 60, y: 60), regions: regions, now: start.addingTimeInterval(1))
        let arrived = path.phase(at: CGPoint(x: 120, y: 120), regions: regions, now: start.addingTimeInterval(2))
        #expect(inside == .inside)
        #expect(crossing == .crossing)
        #expect(expired == .outside)
        #expect(arrived == .inside)
    }

    @Test
    func `avoidance chooses a nearby clear place and leaves partial overlaps stable`() throws {
        let frame = CGRect(x: 100, y: 100, width: 48, height: 48)
        let origin = try #require(ControlIslandAvoidance.proposedOrigin(for: frame, in: area, obstacles: [frame]))
        let moved = CGRect(origin: origin, size: frame.size)
        #expect(moved.intersects(frame) == false)
        #expect(area.contains(moved))
        #expect(hypot(origin.x - frame.minX, origin.y - frame.minY) <= 160)
        let broadButton = CGRect(x: 100, y: 100, width: 300, height: 48)
        #expect(ControlIslandAvoidance.proposedOrigin(for: frame, in: area, obstacles: [broadButton]) == nil)
    }

    @Test
    func `avoidance stays still when every nearby destination is occupied`() {
        let frame = CGRect(x: 100, y: 100, width: 48, height: 48)
        #expect(ControlIslandAvoidance.proposedOrigin(for: frame, in: area, obstacles: [frame, area]) == nil)
    }

    @Test
    func `avoidance clears a chain of neighboring controls`() throws {
        let frame = CGRect(x: 12, y: 12, width: 48, height: 48)
        let neighbors = [frame, CGRect(x: 12, y: 60, width: 48, height: 48), CGRect(x: 60, y: 12, width: 48, height: 96)]
        let origin = try #require(ControlIslandAvoidance.proposedOrigin(for: frame, in: area, obstacles: neighbors))
        let result = CGRect(origin: origin, size: frame.size)
        #expect(neighbors.allSatisfy { !$0.insetBy(dx: -7.9, dy: -7.9).intersects(result) })
        #expect(origin == CGPoint(x: 116, y: 12) || origin == CGPoint(x: 12, y: 116))
    }

    @Test
    func `pointer bookkeeping leaves observation quiet until disclosure changes`() {
        let state = ControlIslandState(defaults: nil, configuration: .init(defaults: nil))
        let notifications = Mutex(0)
        withObservationTracking {
            _ = state.hitRegions
            _ = state.lastPointerMovement
            _ = state.isQuiet
            _ = state.isEngaged
        } onChange: {
            notifications.withLock { $0 += 1 }
        }
        state.hitRegions = [CGRect(x: 0, y: 0, width: 48, height: 48)]
        for x in 0 ..< 40 {
            _ = state.tracksPointer(CGPoint(x: x, y: 20))
        }
        #expect(notifications.withLock { $0 } == 0)
        state.isHovered = true
        #expect(notifications.withLock { $0 } == 1)
    }

    @Test
    func `panel defaults and placement preferences survive a restart`() throws {
        let name = "ControlIslandInteractionTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let config = ControlIslandConfiguration(defaults: defaults)
        #expect(config.restsWhenIdle)
        #expect(config.tintsWithSpaceColor)
        config.apply(config.items, optionDragTarget: .window, avoidsPageControls: false, restsWhenIdle: false, tintsWithSpaceColor: false)
        let restored = ControlIslandConfiguration(defaults: defaults)
        #expect(restored.avoidsPageControls == false)
        #expect(restored.optionDragTarget == .window)
        #expect(restored.restsWhenIdle == false)
        #expect(restored.tintsWithSpaceColor == false)
    }
}
