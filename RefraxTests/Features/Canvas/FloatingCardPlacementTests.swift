import CoreGraphics
import Foundation
import Testing
@testable import Refrax

struct FloatingCardPlacementTests {
    // MARK: Clearance from the island's rail

    @Test
    func `A card beside the rail keeps the island's adjacent gap`() {
        let bounds = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let rail = CGRect(x: 12, y: 160, width: 48, height: 300)
        var placement = FloatingTabPlacement(x: 0, y: 0.3, shape: .tab, isPinned: false)
        placement.move(to: CGPoint(x: rail.maxX + 3.5, y: 200), in: bounds)
        placement.keepClear(of: rail, gap: ControlIslandPlacement.adjacentGap, in: bounds)
        let frame = placement.frame(in: bounds)
        #expect(abs(frame.minX - (rail.maxX + ControlIslandPlacement.adjacentGap)) < 0.5)
    }

    @Test
    func `A card already clear of the rail stays put`() {
        let bounds = CGRect(x: 0, y: 0, width: 1_200, height: 800)
        let rail = CGRect(x: 12, y: 160, width: 48, height: 300)
        var placement = FloatingTabPlacement(x: 0.5, y: 0.5, shape: .tab, isPinned: false)
        let before = placement
        placement.keepClear(of: rail, gap: ControlIslandPlacement.adjacentGap, in: bounds)
        #expect(placement == before)
    }

    // MARK: Beam between windows

    @Test
    func `The beam's panel holds both ends and their halos`() {
        let source = CGRect(x: 100, y: 100, width: 200, height: 100)
        let destination = CGRect(x: 600, y: 400, width: 800, height: 600)
        let panel = ScreenBeam.panelFrame(from: source, to: destination)
        #expect(panel.contains(source.union(destination)))
        let local = ScreenBeam.local(destination, in: panel)
        #expect(local.minY == panel.maxY - destination.maxY)
        #expect(local.minX == destination.minX - panel.minX)
    }
}
