import AppKit
import Foundation
import Testing
@testable import Refrax

@MainActor
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

@MainActor
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
        #expect(router.route(momentum(.changed, 0, -0.3), controlDown: false, canStart: false) == .settle)
        #expect(router.route(momentum(.changed, 0, -0.1), controlDown: false, canStart: false) == .consume)
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
    func `Late momentum stays with the table after the lift-off timeout`() {
        var router = TableScrollRouter()
        _ = router.route(gesture(.began, 0, -4), controlDown: true, canStart: true)
        _ = router.route(gesture(.ended), controlDown: true, canStart: true)
        #expect(router.momentumWindowElapsed() == .settle)
        #expect(router.route(momentum(.began, 0, -20), controlDown: false, canStart: true) == .consume)
        #expect(router.route(momentum(.changed, 0, -8), controlDown: false, canStart: true) == .consume)
        #expect(router.route(momentum(.ended), controlDown: false, canStart: true) == .consume)
        #expect(router.state == .idle)
        #expect(router.route(gesture(.began, 0, -4), controlDown: false, canStart: true) == .pass)
    }

    @Test
    func `A new page gesture receives its beginning while table momentum settles`() {
        var router = TableScrollRouter()
        _ = router.route(gesture(.began, 0, -4), controlDown: true, canStart: true)
        _ = router.route(gesture(.ended), controlDown: true, canStart: true)
        _ = router.route(momentum(.began, 0, -20), controlDown: true, canStart: true)
        #expect(router.route(gesture(.began, 0, -3), controlDown: false, canStart: true) == .settleAndPass)
        #expect(router.route(gesture(.changed, 0, -8), controlDown: false, canStart: true) == .pass)
        #expect(router.state == .passing)
    }

    @Test
    func `Touching down arrests old momentum until the new gesture begins`() {
        var router = TableScrollRouter()
        _ = router.route(gesture(.began, 0, -4), controlDown: true, canStart: true)
        _ = router.route(gesture(.ended), controlDown: true, canStart: true)
        _ = router.route(momentum(.began, 0, -20), controlDown: true, canStart: true)
        #expect(router.route(gesture(.mayBegin), controlDown: false, canStart: true) == .settle)
        #expect(router.route(momentum(.changed, 0, -8), controlDown: false, canStart: true) == .consume)
        #expect(router.route(gesture(.began, 0, -3), controlDown: false, canStart: true) == .pass)
    }

    @Test
    func `Smooth wheel tails stay out of the page after releasing Control`() {
        var router = TableScrollRouter()
        let sample = Sample(source: .smoothWheel, delta: CGSize(width: 0, height: -3))
        _ = router.route(sample, controlDown: true, canStart: true)
        #expect(router.interrupt() == .settle)
        #expect(router.route(sample, controlDown: false, canStart: true) == .consume)
        #expect(router.route(sample, controlDown: false, canStart: true) == .consume)
        #expect(router.smoothWheelWentQuiet() == .consume)
        #expect(router.state == .idle)
        #expect(router.route(sample, controlDown: false, canStart: true) == .pass)
    }

    @Test
    func `A cancelled gesture settles`() {
        var router = TableScrollRouter()
        _ = router.route(gesture(.began, 0, -4), controlDown: true, canStart: true)
        #expect(router.route(gesture(.cancelled), controlDown: true, canStart: true) == .settle)
    }

    @Test
    func `Each wheel notch with the key is one step along the row; ⇧ turns it through rows`() {
        var router = TableScrollRouter()
        #expect(router.route(wheel(0, -1), controlDown: true, canStart: true) == .step(.right))
        #expect(router.route(wheel(0, 1), controlDown: true, canStart: true) == .step(.left))
        #expect(router.route(wheel(0, -1, shift: true), controlDown: true, canStart: true) == .step(.down))
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

    @Test
    func `A click, a key, or ⌃ let go mid-gesture settles it and swallows the rest`() {
        var router = TableScrollRouter()
        _ = router.route(gesture(.began, 0, -4), controlDown: true, canStart: true)
        #expect(router.interrupt() == .settle)
        #expect(router.route(gesture(.changed, 0, -6), controlDown: false, canStart: true) == .consume)
        #expect(router.route(gesture(.ended), controlDown: false, canStart: true) == .consume)
        #expect(router.route(momentum(.began, 0, -20), controlDown: false, canStart: true) == .consume)
        #expect(router.route(momentum(.changed, 0, -10), controlDown: false, canStart: true) == .consume)
        #expect(router.route(momentum(.ended), controlDown: false, canStart: true) == .consume)
        #expect(router.state == .idle)
    }

    @Test
    func `Interrupting momentum settles it; the momentum still to come is swallowed`() {
        var router = TableScrollRouter()
        _ = router.route(gesture(.began, 0, -4), controlDown: true, canStart: true)
        _ = router.route(gesture(.ended), controlDown: true, canStart: true)
        _ = router.route(momentum(.began, 0, -20), controlDown: false, canStart: false)
        #expect(router.interrupt() == .settle)
        #expect(router.route(momentum(.changed, 0, -10), controlDown: false, canStart: false) == .consume)
    }

    @Test
    func `Interrupting while waiting for momentum settles at once`() {
        var router = TableScrollRouter()
        _ = router.route(gesture(.began, 0, -4), controlDown: true, canStart: true)
        _ = router.route(gesture(.ended), controlDown: true, canStart: true)
        #expect(router.interrupt() == .settle)
        #expect(router.momentumWindowElapsed() == .consume)
    }

    @Test
    func `Interrupting a smooth wheel settles it`() {
        var router = TableScrollRouter()
        _ = router.route(Sample(source: .smoothWheel, delta: CGSize(width: 0, height: -3)), controlDown: true, canStart: true)
        #expect(router.interrupt() == .settle)
        #expect(router.smoothWheelWentQuiet() == .consume)
    }

    @Test
    func `Interrupting with no slide does nothing`() {
        var router = TableScrollRouter()
        #expect(router.interrupt() == .consume)
        _ = router.route(gesture(.began, 0, -4), controlDown: false, canStart: true)
        #expect(router.interrupt() == .consume)
        #expect(router.state == .passing)
    }

    @Test
    func `After a swallowed gesture, a new one is judged afresh`() {
        var router = TableScrollRouter()
        _ = router.route(gesture(.began, 0, -4), controlDown: true, canStart: true)
        _ = router.interrupt()
        _ = router.route(gesture(.ended), controlDown: false, canStart: true)
        #expect(router.route(gesture(.began, 0, -4), controlDown: false, canStart: true) == .pass)
        #expect(router.route(gesture(.changed, 0, -4), controlDown: false, canStart: true) == .pass)
    }

    @Test
    func `A wheel event after a swallowed gesture is judged afresh`() {
        var router = TableScrollRouter()
        _ = router.route(gesture(.began, 0, -4), controlDown: true, canStart: true)
        _ = router.interrupt()
        #expect(router.route(wheel(0, -1), controlDown: true, canStart: true) == .step(.right))
        #expect(router.state == .idle)
    }
}
