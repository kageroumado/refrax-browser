import CoreGraphics
import Foundation
import Testing
@testable import Refrax

@Suite
struct BrowserBeamCueTests {
    private let button = CGRect(x: 16, y: 336, width: 40, height: 32)
    private let lens = CGRect(x: 480, y: 180, width: 640, height: 300)
    private let row = CGRect(x: 16, y: 304, width: 40, height: 32)
    private let card = CGRect(x: 68, y: 200, width: 416, height: 44)
    private let area = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)

    private func lensReading(open: Bool, source: CGRect?, frame: CGRect) -> BrowserBeamCues.LensReading {
        .init(isOpen: open, source: source, frame: frame)
    }

    @Test func `the rail's lens button gets a ray once the lens has a frame, once per opening`() throws {
        var cues = BrowserBeamCues()
        cues.reviewLens(lensReading(open: true, source: button, frame: .zero), tourIsActive: false)
        #expect(cues.lensRay == nil, "the lens frame arrives a frame after the lens")

        cues.reviewLens(lensReading(open: true, source: button, frame: lens), tourIsActive: false)
        let ray = try #require(cues.lensRay)
        #expect(ray.style == .guide)
        #expect(ray.from == button)
        #expect(ray.to == lens)

        cues.reviewLens(lensReading(open: true, source: button, frame: lens.offsetBy(dx: 0, dy: 20)), tourIsActive: false)
        #expect(cues.lensRay == ray, "a lens that moves keeps its one ray")

        cues.finish(ray)
        #expect(cues.lensRay == nil)
        cues.reviewLens(lensReading(open: true, source: button, frame: lens), tourIsActive: false)
        #expect(cues.lensRay == nil, "one ray per opening")

        cues.reviewLens(lensReading(open: false, source: nil, frame: .zero), tourIsActive: false)
        cues.reviewLens(lensReading(open: true, source: button, frame: lens), tourIsActive: false)
        #expect(cues.lensRay?.revision == ray.revision + 1, "the next opening lights again")
    }

    @Test func `a lens opened by a key gets no ray`() {
        var cues = BrowserBeamCues()
        cues.reviewLens(lensReading(open: true, source: nil, frame: lens), tourIsActive: false)
        #expect(cues.lensRay == nil)
        cues.reviewLens(lensReading(open: true, source: nil, frame: lens.offsetBy(dx: 0, dy: 20)), tourIsActive: false)
        #expect(cues.lensRay == nil)
    }

    @Test func `closing the lens ends a ray in flight`() {
        var cues = BrowserBeamCues()
        cues.reviewLens(lensReading(open: true, source: button, frame: lens), tourIsActive: false)
        #expect(cues.lensRay != nil)
        cues.reviewLens(lensReading(open: false, source: nil, frame: .zero), tourIsActive: false)
        #expect(cues.lensRay == nil)
    }

    @Test func `the page icon's hover or click trails to the card once per unfold`() throws {
        var cues = BrowserBeamCues()
        cues.reviewCard(.init(frame: .zero, isDeliberate: false, row: row), tourIsActive: false)
        #expect(cues.trail == nil, "a rail at rest draws nothing")

        cues.reviewCard(.init(frame: card, isDeliberate: true, row: row), tourIsActive: false)
        let trail = try #require(cues.trail)
        #expect(trail.style == .trail)
        #expect(trail.from == row)
        #expect(trail.to == card)

        cues.reviewCard(.init(frame: card.offsetBy(dx: 0, dy: 4), isDeliberate: true, row: row), tourIsActive: false)
        #expect(cues.trail == trail, "the card settling keeps its one trail")
        cues.finish(trail)
        cues.reviewCard(.init(frame: card, isDeliberate: true, row: row), tourIsActive: false)
        #expect(cues.trail == nil, "one trail per unfold")

        cues.reviewCard(.init(frame: .zero, isDeliberate: false, row: row), tourIsActive: false)
        cues.reviewCard(.init(frame: card, isDeliberate: true, row: row), tourIsActive: false)
        #expect(cues.trail?.revision == trail.revision + 1, "the next unfold trails again")
    }

    @Test func `a card unfolded by a settled hover or the tab layer draws no trail`() {
        var cues = BrowserBeamCues()
        cues.reviewCard(.init(frame: card, isDeliberate: false, row: row), tourIsActive: false)
        #expect(cues.trail == nil)
        cues.reviewCard(.init(frame: card, isDeliberate: true, row: row), tourIsActive: false)
        #expect(cues.trail == nil, "hovering the icon under a card already open is the same unfold")
    }

    @Test func `the card folding ends a trail in flight`() {
        var cues = BrowserBeamCues()
        cues.reviewCard(.init(frame: card, isDeliberate: true, row: row), tourIsActive: false)
        #expect(cues.trail != nil)
        cues.reviewCard(.init(frame: .zero, isDeliberate: false, row: row), tourIsActive: false)
        #expect(cues.trail == nil)
    }

    @Test func `while the tour runs its overlay draws the pair, so the cues stay quiet`() {
        var cues = BrowserBeamCues()
        cues.reviewLens(lensReading(open: true, source: button, frame: lens), tourIsActive: true)
        cues.reviewCard(.init(frame: card, isDeliberate: true, row: row), tourIsActive: true)
        #expect(cues.lensRay == nil)
        #expect(cues.trail == nil)

        cues.reviewLens(lensReading(open: true, source: button, frame: lens), tourIsActive: false)
        cues.reviewCard(.init(frame: card, isDeliberate: true, row: row), tourIsActive: false)
        #expect(cues.lensRay == nil, "a tour ending mid-opening lights nothing late")
        #expect(cues.trail == nil)
    }

    @Test func `a guide refracts into the lens and a trail runs straight to the card's near edge`() throws {
        var cues = BrowserBeamCues()
        cues.reviewLens(lensReading(open: true, source: button, frame: lens), tourIsActive: false)
        cues.reviewCard(.init(frame: card, isDeliberate: true, row: row), tourIsActive: false)
        let ray = try #require(cues.lensRay)
        let guide = ray.points(in: area)
        let expected = FloatingRayPath(from: button, to: lens, in: area)
        #expect(guide == [expected.start, expected.bend, expected.end])
        #expect(abs(guide[2].x - lens.minX) < 0.01, "the ray lands on the lens's near edge")

        let trail = try #require(cues.trail).points(in: area)
        #expect(trail == [CGPoint(x: row.midX, y: row.midY), CGPoint(x: card.minX, y: card.maxY)], "the near edge, level with the icon when the card allows")
        let mirrored = BrowserBeamCues.Request(style: .trail, from: row, to: CGRect(x: -500, y: 300, width: 416, height: 44), revision: 9)
        #expect(mirrored.points(in: area)[1] == CGPoint(x: -84, y: 320), "a card on the other side is entered from its trailing edge")
        let paths = [ray, cues.trail!].map { $0.style.path($0.points(in: area), color: .init(red: 1, green: 1, blue: 1)) }
        #expect(Int(LightPacking.pack(paths)[1]) == 3)
    }
}

@Suite(.serialized)
@MainActor
struct LensSourceTests {
    @Test func `the rail passes its row as the lens's source and a key passes none`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        _ = env.createActiveTab(url: try #require(URL(string: "about:blank#page")), in: space, for: window)
        let button = CGRect(x: 16, y: 336, width: 40, height: 32)

        window.openCommandLens(source: button)
        #expect(window.commandLensEntrance?.source == button)
        #expect(window.showsAnchoredLens == false)
        window.closeCommandLens()
        #expect(window.commandLensEntrance == nil)

        window.openCommandLens()
        #expect(window.showsCommandLens)
        #expect(window.commandLensEntrance?.source == nil)
        window.closeCommandLens()
    }
}
