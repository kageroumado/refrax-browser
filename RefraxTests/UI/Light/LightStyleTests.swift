import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Refrax

struct LightStyleTests {
    private let accent = Color.Components(red: 0.2, green: 0.5, blue: 0.9)
    private let space = Color.Components(red: 0.9, green: 0.3, blue: 0.4)
    private let ray = FloatingRayPath(start: CGPoint(x: 40, y: 300), bend: CGPoint(x: 400, y: 220), end: CGPoint(x: 460, y: 200))

    @Test
    func `every style packs under the engine's segment cap together`() {
        let paths = LightStyle.allCases.map { $0.path(ray: ray, color: accent) }
        let packed = LightPacking.pack(paths)
        #expect(Int(packed[0]) == LightStyle.allCases.count)
        #expect(Int(packed[1]) == LightStyle.allCases.count * 2)
        #expect(Int(packed[1]) <= LightPacking.maximumSegments)
    }

    @Test(arguments: LightStyle.allCases)
    func `a style's widths and intensity are drawable`(style: LightStyle) {
        let path = style.path(ray: ray, color: accent)
        #expect(path.coreWidth > 0)
        #expect(path.glowWidth > path.coreWidth)
        #expect(path.intensity > 0 && path.intensity <= 1)
        #expect(path.intensity == style.intensity)
        #expect(path.points == [ray.start, ray.bend, ray.end])
    }

    @Test
    func `the trail is gentler and quicker than a guide`() {
        #expect(LightStyle.trail.intensity == LightStyle.guide.intensity / 2)
        #expect(LightStyle.trail.timing.travel == .milliseconds(350))
        #expect(LightStyle.guide.timing == .default)
        #expect(LightStyle.displaced.timing == .default)
        #expect(LightStyle.displaced.intensity == 1)
    }

    @Test
    func `the trail takes the space color and the others the accent`() {
        #expect(LightStyle.trail.color(accent: accent, space: space) == space)
        #expect(LightStyle.trail.color(accent: accent, space: nil) == accent)
        #expect(LightStyle.guide.color(accent: accent, space: space) == accent)
        #expect(LightStyle.displaced.color(accent: accent, space: space) == accent)
    }
}
