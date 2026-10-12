import Foundation
import Testing
@testable import Refrax

@Suite(.serialized)
@MainActor
struct ControlIslandAwakeHoldTests {
    @Test
    func `a hold engages the controls until its end`() {
        let state = ControlIslandState(defaults: nil)
        let start = Date()
        #expect(!state.isEngaged)
        state.holdAwake(for: 4, now: start)
        #expect(state.isEngaged)
        #expect(!state.isQuiet)
        #expect(state.isHeldAwake(now: start.addingTimeInterval(3.9)))
        #expect(!state.isHeldAwake(now: start.addingTimeInterval(4)))
    }

    @Test
    func `a shorter hold never cuts a longer one short`() {
        let state = ControlIslandState(defaults: nil)
        let start = Date()
        state.holdAwake(for: 4, now: start)
        state.holdAwake(for: 1, now: start)
        #expect(state.isHeldAwake(now: start.addingTimeInterval(3)))
        state.holdAwake(for: 6, now: start)
        #expect(state.isHeldAwake(now: start.addingTimeInterval(5)))
    }

    @Test
    func `an expired hold releases the controls`() async throws {
        let state = ControlIslandState(defaults: nil)
        state.holdAwake(for: 0.05)
        #expect(state.isEngaged)
        try await Task.sleep(for: .milliseconds(300))
        #expect(!state.isEngaged)
        #expect(!state.isHeldAwake())
    }
}
