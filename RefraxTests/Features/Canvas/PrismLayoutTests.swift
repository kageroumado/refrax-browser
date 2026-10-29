import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Refrax

struct PrismLayoutTests {
    private let bounds = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
    private let lens = CGRect(x: 480, y: 198, width: 640, height: 52)
    private let rail = CGRect(x: 12, y: 200, width: 48, height: 420)
    private let railLens = CGRect(x: 16, y: 312, width: 40, height: 32)
    private let violet = Color.Components(red: 0.5, green: 0.2, blue: 0.9)

    private func onEdge(_ point: CGPoint, of rect: CGRect) -> Bool {
        let touches = abs(point.x - rect.minX) < 0.01 || abs(point.x - rect.maxX) < 0.01
            || abs(point.y - rect.minY) < 0.01 || abs(point.y - rect.maxY) < 0.01
        return touches && rect.insetBy(dx: -0.01, dy: -0.01).contains(point)
    }

    private func pages(_ count: Int) -> [CGRect] {
        (0 ..< count).map { FloatingTabPlacement.initial(index: $0, count: count).frame(in: bounds) }
    }

    @Test
    func `the entry beam leaves the rail's lens row and ends on the lens's facing edge`() {
        let layout = PrismLayout(railLensFrame: railLens, railFrame: rail, lensFrame: lens, pageFrames: [], bounds: bounds)
        #expect(layout.entry.count == 2)
        #expect(onEdge(layout.entry[0], of: railLens))
        #expect(abs(layout.entry[0].x - railLens.maxX) < 0.01, "it leaves from the row's edge that faces the lens")
        #expect(onEdge(layout.entry[1], of: lens))
        #expect(abs(layout.entry[1].x - lens.minX) < 0.01 && abs(layout.entry[1].y - lens.midY) < 0.01)
    }

    @Test
    func `without a row frame the beam leaves the rail, and without a rail the window's left edge`() {
        let fromRail = PrismLayout(railLensFrame: .zero, railFrame: rail, lensFrame: lens, pageFrames: [], bounds: bounds)
        #expect(onEdge(fromRail.entry[0], of: rail))
        let fromEdge = PrismLayout(railLensFrame: .zero, railFrame: .zero, lensFrame: lens, pageFrames: [], bounds: bounds)
        #expect(fromEdge.entry[0] == CGPoint(x: bounds.minX, y: lens.midY))
        #expect(onEdge(fromEdge.entry[1], of: lens))
    }

    @Test
    func `each band leaves the lens and ends on its page's outline edge`() {
        let frames = pages(5)
        let layout = PrismLayout(railLensFrame: railLens, railFrame: rail, lensFrame: lens, pageFrames: frames, bounds: bounds)
        #expect(layout.bands.count == frames.count)
        for (band, frame) in zip(layout.bands, frames) {
            #expect(band.target == frame)
            #expect(band.points.count == 2)
            #expect(onEdge(band.points[0], of: lens), "the band leaves from the lens's edge")
            #expect(onEdge(band.points[1], of: frame), "the band ends on the outline")
        }
    }

    @Test
    func `three placeholder outlines stand on the right with no pages, on the left when the rail is there`() {
        let right = PrismLayout.placeholderFrames(in: bounds, railFrame: rail)
        #expect(right.count == 3)
        #expect(right.allSatisfy { $0.midX > bounds.midX && bounds.contains($0) })
        #expect(right.allSatisfy { $0.size == FloatingCardShape.tab.naturalSize })
        #expect(right[0].minY < right[1].minY && right[1].minY < right[2].minY)
        let railOnRight = CGRect(x: 1_540, y: 200, width: 48, height: 420)
        let left = PrismLayout.placeholderFrames(in: bounds, railFrame: railOnRight)
        #expect(left.allSatisfy { $0.midX < bounds.midX && bounds.contains($0) })
        let layout = PrismLayout(railLensFrame: railLens, railFrame: rail, lensFrame: lens, pageFrames: right, bounds: bounds)
        #expect(layout.bands.count == 3)
    }

    @Test
    func `three bands take the dispersion hues in angular order`() {
        let frames = PrismLayout.placeholderFrames(in: bounds, railFrame: rail)
        let layout = PrismLayout(railLensFrame: railLens, railFrame: rail, lensFrame: lens, pageFrames: frames, bounds: bounds)
        let offsets = layout.bands.map(\.hueOffset)
        #expect(offsets == [-PrismLayout.hueSpread, 0, PrismLayout.hueSpread], "top to bottom on the right turns the hue up")
        let one = PrismLayout(railLensFrame: railLens, railFrame: rail, lensFrame: lens, pageFrames: [frames[0]], bounds: bounds)
        #expect(one.bands.map(\.hueOffset) == [0])
    }

    @Test(arguments: [
        CGRect(x: 12, y: 200, width: 48, height: 420),
        CGRect(x: 1_540, y: 200, width: 48, height: 420),
        CGRect(x: 776, y: 568, width: 48, height: 420),
        CGRect(x: 776, y: 12, width: 48, height: 120),
    ])
    func `every path stays inside the window wherever the rail is`(rail: CGRect) {
        let row = CGRect(x: rail.minX + 4, y: rail.minY + 40, width: 40, height: 32)
        let frames = pages(8)
        let layout = PrismLayout(railLensFrame: row, railFrame: rail, lensFrame: lens, pageFrames: frames, bounds: bounds)
        let points = layout.entry + layout.bands.flatMap(\.points)
        #expect(points.allSatisfy { bounds.insetBy(dx: -0.01, dy: -0.01).contains($0) })
        #expect(onEdge(layout.entry[1], of: lens))
    }

    @Test
    func `twelve pages fit under the segment cap and the thirteenth gets no band`() {
        let twelve = PrismLayout(railLensFrame: railLens, railFrame: rail, lensFrame: lens, pageFrames: pages(12), bounds: bounds)
        #expect(twelve.bands.count == 12)
        #expect(twelve.segmentCount <= LightPacking.maximumSegments)
        let paths = twelve.paths(color: violet, time: 3, tightened: false, reduceMotion: false)
        #expect(paths.count == 13)
        #expect(LightPacking.pack(paths)[0] == 13, "every path is drawn")
        let fifteen = PrismLayout(railLensFrame: railLens, railFrame: rail, lensFrame: lens, pageFrames: pages(15), bounds: bounds)
        #expect(fifteen.bands.count == PrismLayout.maximumBands)
    }

    @Test
    func `the pulse travels the entry beam once every period and the bands breathe between half and full`() throws {
        let layout = PrismLayout(railLensFrame: railLens, railFrame: rail, lensFrame: lens, pageFrames: pages(3), bounds: bounds)
        let early = layout.paths(color: violet, time: 0.7, tightened: false, reduceMotion: false)
        let pulse = try #require(early[0].pulse)
        #expect(abs(pulse.position - 0.5) < 0.001, "halfway through its travel")
        let resting = layout.paths(color: violet, time: PrismLayout.pulseTravel + 0.5, tightened: false, reduceMotion: false)
        #expect(resting[0].pulse == nil, "between pulses the beam is even")
        let again = layout.paths(color: violet, time: PrismLayout.pulsePeriod + 0.7, tightened: false, reduceMotion: false)
        #expect(abs((again[0].pulse?.position ?? 0) - 0.5) < 0.001)

        let full = layout.paths(color: violet, time: 0, tightened: false, reduceMotion: false)
        let half = layout.paths(color: violet, time: PrismLayout.breathPeriods.lowerBound / 2, tightened: false, reduceMotion: false)
        #expect(abs(half[1].intensity / full[1].intensity - 0.5) < 0.001, "the first band is at half after half its period")
        #expect(PrismLayout.breath(at: 0, band: 1) == 1)
        #expect(abs(PrismLayout.breath(at: 3.5, band: 1) - 0.5) < 0.001, "the second band's period is 7 s")
        #expect(full[1].color != full[2].color && full[1].color != violet, "bands carry the dispersion hues")
    }

    @Test
    func `reduce motion rests the light and typing tightens the beam`() {
        let layout = PrismLayout(railLensFrame: railLens, railFrame: rail, lensFrame: lens, pageFrames: pages(2), bounds: bounds)
        let still = layout.paths(color: violet, time: 0.7, tightened: false, reduceMotion: true)
        #expect(still[0].pulse == nil)
        #expect(still[1].intensity == still[2].intensity)
        #expect(layout.paths(color: violet, time: 4, tightened: false, reduceMotion: true) == still)
        let typing = layout.paths(color: violet, time: 0.7, tightened: true, reduceMotion: true)
        #expect(typing[0].glowWidth < still[0].glowWidth)
        #expect(typing[0].intensity > still[0].intensity)
    }

    @Test
    func `edge points land on the boundary and facing points on the near edge's middle`() {
        let rect = CGRect(x: 100, y: 100, width: 200, height: 50)
        #expect(PrismLayout.edgePoint(of: rect, toward: CGPoint(x: 600, y: 125)) == CGPoint(x: 300, y: 125))
        #expect(PrismLayout.edgePoint(of: rect, toward: CGPoint(x: 200, y: 400)) == CGPoint(x: 200, y: 150))
        #expect(PrismLayout.edgePoint(of: rect, toward: CGPoint(x: 200, y: 125)) == CGPoint(x: 200, y: 125), "the center stays")
        #expect(PrismLayout.edgePoint(of: rect, toward: CGPoint(x: 150, y: 110)) == CGPoint(x: 150, y: 110), "a point inside is itself")
        #expect(PrismLayout.facingPoint(of: rect, toward: CGPoint(x: 0, y: 500)) == CGPoint(x: 100, y: 125))
        #expect(PrismLayout.facingPoint(of: rect, toward: CGPoint(x: 1_000, y: 0)) == CGPoint(x: 300, y: 125))
        #expect(PrismLayout.facingPoint(of: rect, toward: CGPoint(x: 150, y: 900)) == CGPoint(x: 200, y: 150))
        #expect(PrismLayout.facingPoint(of: rect, toward: CGPoint(x: 150, y: 0)) == CGPoint(x: 200, y: 100))
    }
}
