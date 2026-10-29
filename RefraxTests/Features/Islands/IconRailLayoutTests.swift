import CoreGraphics
import Testing
@testable import Refrax

struct IconRailLayoutTests {
    private let bounds = CGRect(x: 0, y: 0, width: 900, height: 650)

    @Test(arguments: [0.0, 0.5, 1.0], [0.0, 0.5, 1.0])
    func `Rails clear control islands at every anchor`(_ x: Double, _ y: Double) {
        let placement = ControlIslandPlacement(x: x, y: y)
        let control = placement.railFrame(in: bounds, height: 282)
        let rail = IconRailLayout.frame(placement: placement, height: 240, in: bounds, obstacles: [control])
        #expect(rail.width == 36)
        #expect(bounds.insetBy(dx: 8, dy: 8).contains(rail))
        #expect(!rail.intersects(control.insetBy(dx: -7.9, dy: -7.9)))
    }

    @Test
    func `Clear placements retain their anchors while a crowded edge finds another position`() {
        let control = CGRect(x: 8, y: 8, width: 36, height: 282)
        let placement = ControlIslandPlacement(x: 0, y: 1)
        let preferred = placement.railFrame(in: bounds, height: 240)
        #expect(IconRailLayout.frame(placement: placement, height: 240, in: bounds, obstacles: [control]) == preferred)
        let crowded = IconRailLayout.frame(placement: placement, height: 600, in: bounds, obstacles: [control])
        #expect(crowded.minX >= control.maxX + 8)
        #expect(bounds.insetBy(dx: 8, dy: 8).contains(crowded))
    }

    @Test(arguments: [false, true])
    func `Drawer stays clear of the controls at either window edge`(_ right: Bool) {
        let rail = ControlIslandPlacement(x: right ? 1 : 0, y: 0).railFrame(in: bounds, height: 282)
        let x = DetailTrayLayout.leading(in: bounds, controlRail: rail, width: 320)
        let drawer = CGRect(x: x, y: 8, width: 320, height: bounds.height - 16)
        #expect(bounds.insetBy(dx: 8, dy: 8).contains(drawer))
        #expect(!drawer.intersects(rail))
    }
}
