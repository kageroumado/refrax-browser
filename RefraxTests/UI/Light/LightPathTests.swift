import CoreGraphics
import Foundation
import SwiftUI
import Testing
@testable import Refrax

@Suite
struct LightPathTests {
    private let violet = Color.Components(red: 0.5, green: 0.2, blue: 0.9)

    @Test func `length and points along an L-shaped path follow its segments`() {
        let path = LightPath(points: [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0), CGPoint(x: 30, y: 40)], color: violet)
        #expect(path.length == 70)
        #expect(path.segmentLengths == [30, 40])
        #expect(path.point(at: 0) == CGPoint(x: 0, y: 0))
        #expect(path.point(at: 0.5) == CGPoint(x: 30, y: 5))
        #expect(path.point(at: 1) == CGPoint(x: 30, y: 40))
        #expect(path.point(at: 2) == CGPoint(x: 30, y: 40), "fractions clamp to the ends")
        #expect(path.point(at: -1) == CGPoint(x: 0, y: 0))
    }

    @Test func `a zero-length path is a spot at its point`() {
        let path = LightPath(points: [CGPoint(x: 5, y: 5), CGPoint(x: 5, y: 5)], color: violet)
        #expect(path.length == 0)
        #expect(path.point(at: 0.5) == CGPoint(x: 5, y: 5))
    }

    @Test func `a ray becomes its three points`() {
        let ray = FloatingRayPath(start: CGPoint(x: 10, y: 10), bend: CGPoint(x: 50, y: 60), end: CGPoint(x: 60, y: 90))
        let path = LightPath(ray: ray, color: violet)
        #expect(path.points == [ray.start, ray.bend, ray.end])
        #expect(abs(path.length - ray.length) < 0.001)
    }

    @Test func `dispersion bands sit on either side of the color's hue`() {
        let bands = LightPath(points: [.zero, CGPoint(x: 1, y: 0)], color: violet).bandColors
        #expect(bands.low != violet)
        #expect(bands.high != violet)
        #expect(bands.low != bands.high)
        #expect(bands.low.blue > bands.low.red, "violet turned down is blue")
        #expect(bands.high.red > bands.low.red, "violet turned up is pink")
        for band in [bands.low, bands.high] {
            #expect(abs(max(band.red, band.green, band.blue) - 0.9) < 0.001, "brightness is kept")
            #expect(abs(min(band.red, band.green, band.blue) - 0.2) < 0.001, "chroma is kept")
        }
        #expect(violet.rotatingHue(by: 360) == violet)
        let gray = Color.Components(red: 0.5, green: 0.5, blue: 0.5)
        #expect(gray.rotatingHue(by: 34) == gray)
    }

    @Test func `a frame sets progress and scales intensity and spot`() {
        var path = LightPath(points: [.zero, CGPoint(x: 10, y: 0)], color: violet)
        path.intensity = 0.5
        let lit = path.applying(LightTravel.Frame(progress: 0.25, intensity: 0.5, spotScale: 1.7, isFinished: false))
        #expect(lit.progress == 0.25)
        #expect(lit.intensity == 0.25)
        #expect(lit.spotScale == 1.7)
    }

    @Test func `packing lays out the header, the path record, and the segments`() {
        var path = LightPath(points: [CGPoint(x: 0, y: 0), CGPoint(x: 30, y: 0), CGPoint(x: 30, y: 40)], color: violet)
        path.progress = 0.5
        path.dispersion = 0.25
        let data = LightPacking.pack([path])
        #expect(data.count == LightPacking.headerLength + LightPacking.pathStride + 2 * LightPacking.segmentStride)
        #expect(data[0] == 1)
        #expect(data[1] == 2)
        let record = LightPacking.headerLength
        #expect(data[record] == 0)
        #expect(data[record + 1] == 2)
        #expect(data[record + 2] == 70)
        #expect(data[record + 3] == 35, "lit length is progress along the whole path")
        #expect(data[record + 4] == 0.5 && data[record + 5] == 0.2 && data[record + 6] == 0.9)
        #expect(data[record + 7] == 1)
        #expect(data[record + 8] == Float(LightPath.Layout.coreWidth))
        #expect(data[record + 9] == Float(LightPath.Layout.glowWidth))
        #expect(data[record + 10] == 0.25)
        #expect(data[record + 11] == 1)
        let segments = record + LightPacking.pathStride
        #expect(Array(data[segments ..< segments + 8]) == [0, 0, 30, 0, 0, 30, 1, 0])
        #expect(Array(data[segments + 8 ..< segments + 16]) == [30, 0, 30, 40, 30, 40, 0, 1])
    }

    @Test func `packing keeps whole paths up to the segment cap`() {
        let short = LightPath(points: [.zero, CGPoint(x: 1, y: 0)], color: violet)
        let long = LightPath(points: (0 ... 30).map { CGPoint(x: CGFloat($0), y: 0) }, color: violet)
        let data = LightPacking.pack([long, short, short, short])
        #expect(data[0] == 3, "the fourth path would cross the cap")
        #expect(data[1] == Float(LightPacking.maximumSegments))
        #expect(LightPacking.pack([]).count == LightPacking.headerLength)
    }
}

@Suite
struct LightTravelTests {
    private let timing = LightTravel.Timing()

    @Test func `the beam travels with an ease-out, pulses on hold, then fades out`() {
        let start = timing.frame(at: 0, reduceMotion: false)
        #expect(start.progress == 0 && start.intensity == 1 && start.spotScale == 1 && !start.isFinished)

        let early = timing.frame(at: 0.1, reduceMotion: false)
        let late = timing.frame(at: 0.4, reduceMotion: false)
        #expect(early.progress > 0.1, "ease-out moves fast at first")
        #expect(late.progress > 0.95 && late.progress < 1)

        let landed = timing.frame(at: 0.5, reduceMotion: false)
        #expect(landed.progress == 1 && landed.spotScale == 1)
        let peak = timing.frame(at: 0.65, reduceMotion: false)
        #expect(abs(peak.spotScale - timing.pulseScale) < 0.001, "the pulse peaks midway through the hold")

        let fading = timing.frame(at: 0.95, reduceMotion: false)
        #expect(fading.progress == 1 && fading.intensity > 0 && fading.intensity < 1 && !fading.isFinished)
        let done = timing.frame(at: timing.total(reduceMotion: false), reduceMotion: false)
        #expect(done.intensity == 0 && done.isFinished)
    }

    @Test func `reduce motion shows the whole path at once and only fades`() {
        let start = timing.frame(at: 0, reduceMotion: true)
        #expect(start.progress == 1 && start.intensity == 1 && start.spotScale == 1)
        let held = timing.frame(at: 0.3, reduceMotion: true)
        #expect(held.spotScale == 1 && held.intensity == 1)
        let fading = timing.frame(at: 0.75, reduceMotion: true)
        #expect(fading.intensity < 1 && !fading.isFinished)
        #expect(timing.frame(at: 0.9, reduceMotion: true).isFinished)
        #expect(abs(timing.total(reduceMotion: true) - 0.9) < 0.001)
        #expect(abs(timing.total(reduceMotion: false) - 1.1) < 0.001)
    }
}
