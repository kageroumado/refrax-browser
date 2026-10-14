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
