import CoreGraphics
import Foundation
import Testing
@testable import Refrax

struct IslandArrangementTests {
    @Test(arguments: [CGSize(width: 900, height: 700), CGSize(width: 1_440, height: 1_080)])
    func `An edge arrangement keeps headers inside the window and leaves the page clear`(_ size: CGSize) throws {
        let area = CGRect(x: 56, y: 64, width: size.width - 72, height: size.height - 80)
        let items = (0 ..< 6).map { _ in IslandArrangement.Item(id: UUID(), size: CGSize(width: 236, height: 180)) }
        let arrangement = try #require(IslandArrangement(items: items, area: area))
        #expect(size.width - arrangement.pageInset >= 320)
        for (id, frame) in arrangement.frames {
            let window = frame.insetBy(dx: 0, dy: -IslandGeometry.headerReserve)
            #expect(frame.minY - IslandGeometry.headerReserve >= area.minY)
            #expect(area.contains(frame))
            for (otherID, other) in arrangement.frames where otherID != id {
                #expect(window.intersects(other) == false)
            }
        }
    }

    @Test
    func `Islands keep their full heights when a single column fits`() throws {
        let items = [400.0, 76, 76].map { IslandArrangement.Item(id: UUID(), size: CGSize(width: 236, height: $0)) }
        let arrangement = try #require(IslandArrangement(items: items, area: CGRect(x: 56, y: 64, width: 1_000, height: 900)))
        for item in items {
            #expect(arrangement.frames[item.id]?.height == item.size.height)
        }
    }

    @Test
    func `A window with too little room keeps free placement available`() {
        let items = [IslandArrangement.Item(id: UUID(), size: CGSize(width: 236, height: 76))]
        #expect(IslandArrangement(items: items, area: CGRect(x: 16, y: 16, width: 400, height: 300)) == nil)
    }

    @Test
    func `Existing saved placements decode as free placement`() throws {
        let bytes = try JSONEncoder().encode(IslandState())
        let decoded = IslandState.decode(bytes)
        #expect(decoded.automaticallyArranged == false)
        let old = Data(#"{"islands":{},"detached":[]}"#.utf8)
        #expect(IslandState.decode(old).automaticallyArranged == false)
    }

    @Test
    func `Combining requires a stationary pause and resets when the pointer leaves`() {
        var dwell = IslandJoinDwell()
        let target = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 100)
        let began = dwell.update(candidate: target, at: CGPoint(x: 30, y: 20), now: start)
        #expect(began)
        #expect(dwell.ready(at: start.addingTimeInterval(0.59)) == nil)
        #expect(dwell.ready(at: start.addingTimeInterval(0.61)) == target)
        let moved = dwell.update(candidate: target, at: CGPoint(x: 50, y: 20), now: start.addingTimeInterval(0.7))
        #expect(moved)
        #expect(dwell.ready(at: start.addingTimeInterval(0.8)) == nil)
        let left = dwell.update(candidate: nil, at: .zero, now: start.addingTimeInterval(1.5))
        #expect(left)
        #expect(dwell.ready(at: start.addingTimeInterval(3)) == nil)
    }
}
