import AppKit
import Foundation
import Testing
@testable import Refrax

struct TableScrollSourceTests {
    @Test
    func `Phased events are a trackpad, momentum included`() {
        #expect(TableScrollSource.classify(hasPreciseDeltas: true, phase: .began, momentumPhase: []) == .trackpad)
        #expect(TableScrollSource.classify(hasPreciseDeltas: true, phase: [], momentumPhase: .changed) == .trackpad)
    }

    @Test
    func `Phaseless events are a wheel: smooth when precise, notched otherwise`() {
        #expect(TableScrollSource.classify(hasPreciseDeltas: true, phase: [], momentumPhase: []) == .smoothWheel)
        #expect(TableScrollSource.classify(hasPreciseDeltas: false, phase: [], momentumPhase: []) == .wheel)
    }
}

struct TableScrollRouterTests {
    private typealias Sample = TableScrollRouter.Sample

    private func gesture(_ phase: NSEvent.Phase, _ dx: CGFloat = 0, _ dy: CGFloat = 0) -> Sample {
        Sample(source: .trackpad, phase: phase, delta: CGSize(width: dx, height: dy))
    }

    private func momentum(_ phase: NSEvent.Phase, _ dx: CGFloat = 0, _ dy: CGFloat = 0) -> Sample {
        Sample(source: .trackpad, momentumPhase: phase, delta: CGSize(width: dx, height: dy))
    }

    private func wheel(_ dx: CGFloat, _ dy: CGFloat, shift: Bool = false) -> Sample {
        Sample(source: .wheel, delta: CGSize(width: dx, height: dy), shift: shift)
    }

    @Test
    func `A gesture begun with ⌃ over the page slides the table to its end`() {
        var router = TableScrollRouter()
        #expect(router.route(gesture(.began, 0, -4), controlDown: true, canStart: true) == .begin(CGSize(width: 0, height: -4)))
        #expect(router.route(gesture(.changed, 3, -8), controlDown: true, canStart: true) == .pan(CGSize(width: 3, height: -8)))
        #expect(router.route(gesture(.ended), controlDown: true, canStart: true) == .liftOff)
        #expect(router.isSliding)
    }

    @Test
    func `Letting go of ⌃ or leaving the page mid-gesture keeps the slide`() {
        var router = TableScrollRouter()
        _ = router.route(gesture(.began, 0, -4), controlDown: true, canStart: true)
        #expect(router.route(gesture(.changed, 0, -6), controlDown: false, canStart: false) == .pan(CGSize(width: 0, height: -6)))
    }

    @Test
    func `A gesture begun without ⌃ stays the page's, even when ⌃ comes down`() {
        var router = TableScrollRouter()
        #expect(router.route(gesture(.began, 0, -4), controlDown: false, canStart: true) == .pass)
        #expect(router.route(gesture(.changed, 0, -4), controlDown: true, canStart: true) == .pass)
        #expect(router.route(gesture(.ended), controlDown: true, canStart: true) == .pass)
        #expect(router.route(momentum(.began, 0, -4), controlDown: true, canStart: true) == .pass)
        #expect(!router.isSliding)
    }

    @Test
    func `A gesture over a card or the island never starts a slide`() {
        var router = TableScrollRouter()
        #expect(router.route(gesture(.began, 0, -4), controlDown: true, canStart: false) == .pass)
    }

    @Test
    func `Momentum continues the slide and its end settles it`() {
        var router = TableScrollRouter()
        _ = router.route(gesture(.began, 0, -4), controlDown: true, canStart: true)
        _ = router.route(gesture(.ended), controlDown: true, canStart: true)
        #expect(router.route(momentum(.began, 0, -20), controlDown: false, canStart: false) == .pan(CGSize(width: 0, height: -20)))
        #expect(router.route(momentum(.changed, 0, -12), controlDown: false, canStart: false) == .pan(CGSize(width: 0, height: -12)))
        #expect(router.route(momentum(.ended), controlDown: false, canStart: false) == .settle)
        #expect(!router.isSliding)
    }

    @Test
    func `Slow momentum settles early and the rest of it is swallowed`() {
        var router = TableScrollRouter()
        _ = router.route(gesture(.began, 0, -4), controlDown: true, canStart: true)
        _ = router.route(gesture(.ended), controlDown: true, canStart: true)
        _ = router.route(momentum(.began, 0, -20), controlDown: false, canStart: false)
        #expect(router.route(momentum(.changed, 0, -1), controlDown: false, canStart: false) == .settle)
        #expect(router.route(momentum(.changed, 0, -0.5), controlDown: false, canStart: false) == .consume)
        #expect(router.route(momentum(.ended), controlDown: false, canStart: false) == .consume)
        #expect(router.state == .idle)
    }

    @Test
    func `With no momentum the pause after lift-off settles`() {
        var router = TableScrollRouter()
        _ = router.route(gesture(.began, 0, -4), controlDown: true, canStart: true)
        _ = router.route(gesture(.ended), controlDown: true, canStart: true)
        #expect(router.momentumWindowElapsed() == .settle)
        #expect(router.momentumWindowElapsed() == .consume)
    }

    @Test
    func `Fingers touching down stop the momentum`() {
        var router = TableScrollRouter()
        _ = router.route(gesture(.began, 0, -4), controlDown: true, canStart: true)
        _ = router.route(gesture(.ended), controlDown: true, canStart: true)
        _ = router.route(momentum(.began, 0, -20), controlDown: false, canStart: false)
        #expect(router.route(gesture(.mayBegin), controlDown: false, canStart: true) == .settle)
    }

    @Test
    func `A new ⌃ gesture during momentum starts a new slide`() {
        var router = TableScrollRouter()
        _ = router.route(gesture(.began, 0, -4), controlDown: true, canStart: true)
        _ = router.route(gesture(.ended), controlDown: true, canStart: true)
        _ = router.route(momentum(.began, 0, -20), controlDown: false, canStart: false)
        #expect(router.route(gesture(.began, 2, 0), controlDown: true, canStart: true) == .begin(CGSize(width: 2, height: 0)))
        #expect(router.state == .tracking)
    }

    @Test
    func `A cancelled gesture settles`() {
        var router = TableScrollRouter()
        _ = router.route(gesture(.began, 0, -4), controlDown: true, canStart: true)
        #expect(router.route(gesture(.cancelled), controlDown: true, canStart: true) == .settle)
    }

    @Test
    func `Each wheel notch with ⌃ is one step; ⇧ turns the wheel along the row`() {
        var router = TableScrollRouter()
        #expect(router.route(wheel(0, -1), controlDown: true, canStart: true) == .step(.down))
        #expect(router.route(wheel(0, 1), controlDown: true, canStart: true) == .step(.up))
        #expect(router.route(wheel(0, -1, shift: true), controlDown: true, canStart: true) == .step(.right))
        #expect(router.route(wheel(1, 0), controlDown: true, canStart: true) == .step(.left))
    }

    @Test
    func `A wheel without ⌃, or away from the page, scrolls the page`() {
        var router = TableScrollRouter()
        #expect(router.route(wheel(0, -1), controlDown: false, canStart: true) == .pass)
        #expect(router.route(wheel(0, -1), controlDown: true, canStart: false) == .pass)
    }

    @Test
    func `A smooth wheel pans until it goes quiet`() {
        var router = TableScrollRouter()
        let first = Sample(source: .smoothWheel, delta: CGSize(width: 0, height: -3))
        #expect(router.route(first, controlDown: true, canStart: true) == .begin(CGSize(width: 0, height: -3)))
        #expect(router.route(first, controlDown: false, canStart: false) == .pan(CGSize(width: 0, height: -3)))
        #expect(router.smoothWheelWentQuiet() == .settle)
        #expect(router.route(first, controlDown: false, canStart: true) == .pass)
    }
}

@MainActor
struct TableMotionTests {
    private let camera = TableCamera(viewport: CGSize(width: 1_000, height: 600))
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()
    private let d = UUID()

    @Test
    func `Rebasing keeps the view in place when an edit changes the row's offset`() {
        let old = TableLayout(rows: [TableLayout.Row(slabs: [a, b, c].map { TableLayout.Slab(tabID: $0, width: .half) })])
        let new = old.movingFocus(.right).movingFocus(.right)
        let viewpoint = TableViewpoint(row: 0, shift: 120)
        let rebased = camera.rebased(viewpoint, from: old, to: new)
        #expect(camera.drawnOffset(ofRow: 0, in: new, at: rebased) == camera.drawnOffset(ofRow: 0, in: old, at: viewpoint))
        #expect(rebased.row == 0)
    }

    @Test
    func `Rebasing follows the anchor row when rows above it come and go`() {
        let old = TableLayout(rows: [
            TableLayout.Row(slabs: [TableLayout.Slab(tabID: a)]),
            TableLayout.Row(slabs: [TableLayout.Slab(tabID: b)]),
        ], focusedRow: 1)
        let new = old.removing(a)
        let rebased = camera.rebased(TableViewpoint(row: 1), from: old, to: new)
        #expect(rebased.row == 0)
    }

    @Test
    func `A resting frame places a slab of another row a viewport above or below`() {
        let layout = TableLayout(rows: [
            TableLayout.Row(slabs: [TableLayout.Slab(tabID: a)]),
            TableLayout.Row(slabs: [TableLayout.Slab(tabID: b, width: .half), TableLayout.Slab(tabID: c, width: .half)]),
        ], focusedRow: 1)
        #expect(camera.restingFrame(of: c, in: layout) == CGRect(x: 500, y: 0, width: 500, height: 600))
        #expect(camera.restingFrame(of: a, in: layout) == CGRect(x: 0, y: -600, width: 1_000, height: 600))
        #expect(camera.restingFrame(of: d, in: layout) == nil)
    }

    @Test
    func `A long jump passes a neighbor or a row`() {
        typealias Position = TableLayout.Position
        #expect(!TableCamera.isLongJump(from: Position(row: 0, slab: 1), to: Position(row: 0, slab: 2)))
        #expect(TableCamera.isLongJump(from: Position(row: 0, slab: 0), to: Position(row: 0, slab: 2)))
        #expect(!TableCamera.isLongJump(from: Position(row: 0, slab: 0), to: Position(row: 1, slab: 3)))
        #expect(TableCamera.isLongJump(from: Position(row: 0, slab: 0), to: Position(row: 2, slab: 0)))
    }
}

struct TableEditTests {
    private let a = UUID()
    private let b = UUID()
    private let c = UUID()

    @Test
    func `Setting a width ends a fill and leaves other slabs alone`() {
        let layout = TableLayout(tabIDs: [a, b]).togglingFill().settingWidth(.half, of: a)
        let slab = layout[TableLayout.Position(row: 0, slab: 0)]
        #expect(slab.width == .half)
        #expect(!slab.fills)
        #expect(layout[TableLayout.Position(row: 0, slab: 1)].width == .full)
    }

    @Test
    func `Moving a slab to a new row opens the row below and focuses it`() {
        let layout = TableLayout(tabIDs: [a, b, c]).movingToNewRow(b)
        #expect(layout.rows.count == 2)
        #expect(layout.rows[0].slabs.map(\.tabID) == [a, c])
        #expect(layout.rows[1].slabs.map(\.tabID) == [b])
        #expect(layout.focusedTabID == b)
    }

    @Test
    func `A slab alone in its row stays put`() {
        let layout = TableLayout(tabIDs: [a])
        #expect(layout.movingToNewRow(a) == layout)
    }

    @Test
    func `Going to a row focuses the slab it remembers`() {
        let layout = TableLayout(tabIDs: [a, b, c]).movingToNewRow(b).focusingRow(0)
        #expect(layout.focusedRow == 0)
        #expect(layout.focusingRow(5) == layout)
    }

    @Test
    func `The lens reads a row number after the word row`() {
        #expect(TableCommand.rowNumber(in: "go to row 3") == 3)
        #expect(TableCommand.rowNumber(in: "Row12") == 12)
        #expect(TableCommand.rowNumber(in: "rows") == nil)
    }
}
