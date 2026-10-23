import CoreGraphics
import Foundation
import Testing
@testable import Refrax

struct FloatingCardPlacementTests {
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
