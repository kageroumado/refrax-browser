import CoreGraphics
import Foundation
import Testing
@testable import Refrax

struct FloatingRayPathTests {
    private let area = CGRect(x: 0, y: 0, width: 1_200, height: 800)
    private let lens = CGRect(x: 280, y: 180, width: 640, height: 48)

    private func contains(_ path: FloatingRayPath) -> Bool {
        [path.start, path.bend, path.end].allSatisfy { area.contains($0) || area.maxX == $0.x || area.maxY == $0.y }
    }

    @Test(arguments: [
        CGRect(x: 16, y: 750, width: 250, height: 34),
        CGRect(x: 934, y: 750, width: 250, height: 34),
        CGRect(x: 16, y: 16, width: 250, height: 34),
        CGRect(x: 934, y: 16, width: 250, height: 34),
        CGRect(x: 1_000, y: 300, width: 250, height: 34),
    ])
    func `the ray stays in the window and lands on the destination's edge`(destination: CGRect) {
        let path = FloatingRayPath(from: lens, to: destination, in: area)
        #expect(contains(path))
        let onEdge = abs(path.end.x - destination.minX) < 0.01 || abs(path.end.x - destination.maxX) < 0.01
            || abs(path.end.y - destination.minY) < 0.01 || abs(path.end.y - destination.maxY) < 0.01
        #expect(onEdge)
        #expect(destination.insetBy(dx: -0.01, dy: -0.01).contains(path.end))
        #expect(path.length > 0)
    }

    @Test
    func `the bend turns the ray toward the pane's normal`() throws {
        let destination = CGRect(x: 16, y: 750, width: 250, height: 34)
        let path = FloatingRayPath(from: lens, to: destination, in: area)
        let side = try #require(FloatingRayPath.nearSide(of: destination, from: path.start))
        #expect(side == .top)
        let sines = path.sines(normal: side.inwardNormal)
        #expect(sines.incidence > 0)
        #expect(sines.refraction < sines.incidence)
        #expect(abs(sines.refraction - sines.incidence / FloatingRayPath.refractiveIndex) < 0.05)
        #expect(abs(path.bend.y - (destination.minY - FloatingRayPath.paneGap)) < 0.01)
        #expect(path.bend.x < path.start.x, "the first run heads for the destination's center")
        #expect(path.end.x < path.bend.x, "the second run keeps the same tangential sense")
    }

    @Test
    func `a ray straight down the normal keeps its line`() {
        let destination = CGRect(x: 475, y: 700, width: 250, height: 34)
        let path = FloatingRayPath(from: lens, to: destination, in: area)
        #expect(abs(path.start.x - path.bend.x) < 0.01)
        #expect(abs(path.bend.x - path.end.x) < 0.01)
        #expect(abs(path.end.y - destination.minY) < 0.01)
    }

    @Test
    func `a destination beside the source enters through its side`() {
        let destination = CGRect(x: 1_000, y: 190, width: 180, height: 34)
        let path = FloatingRayPath(from: lens, to: destination, in: area)
        #expect(FloatingRayPath.nearSide(of: destination, from: path.start) == .leading)
        let gap = FloatingRayPath.paneGap(forApproach: destination.minX - path.start.x)
        #expect(gap < FloatingRayPath.paneGap, "a short approach draws the pane in")
        #expect(abs(path.bend.x - (destination.minX - gap)) < 0.01)
        #expect(abs(path.end.x - destination.minX) < 0.01)
        #expect(contains(path))
    }

    @Test(arguments: [
        CGRect(x: 300, y: 190, width: 250, height: 34),
        CGRect(x: 280, y: 180, width: 640, height: 48),
        CGRect(x: 600, y: 240, width: 250, height: 34),
        CGRect(x: 0, y: 0, width: 0, height: 0),
        CGRect(x: CGFloat.nan, y: CGFloat.infinity, width: 10, height: 10),
    ])
    func `overlapping, touching, and invalid rects give a short finite path`(destination: CGRect) {
        let path = FloatingRayPath(from: lens, to: destination, in: area)
        for point in [path.start, path.bend, path.end] {
            #expect(point.x.isFinite && point.y.isFinite)
        }
        #expect(contains(path))
        #expect(path.length < hypot(lens.width, lens.height) + 1)
    }

    @Test
    func `an empty source starts the ray at its point`() {
        let destination = CGRect(x: 934, y: 750, width: 250, height: 34)
        let path = FloatingRayPath(from: .zero, to: destination, in: area)
        #expect(path.start == .zero)
        #expect(contains(path))
        #expect(path.length > 0)
    }
}
