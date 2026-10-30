import CoreGraphics
import Foundation
import Testing
@testable import Refrax

struct ControlIslandEdgeHidingTests {
    private let area = CGRect(x: 0, y: 0, width: 1_600, height: 1_000)
    private let rail = CGRect(x: 12, y: 200, width: 48, height: 500)

    @Test
    func `only a rail snapped to the left or right edge has an edge to hide past`() {
        #expect(ControlIslandPlacement(x: 0, y: 0.5).horizontalEdge == .left)
        #expect(ControlIslandPlacement(x: 1, y: 0).horizontalEdge == .right)
        #expect(ControlIslandPlacement(x: 0.5, y: 0).horizontalEdge == nil)
        #expect(ControlIslandPlacement(x: 0.3, y: 0.2).horizontalEdge == nil)
    }

    @Test
    func `the flap sits on the hidden edge at the rail's resting height, inside the window`() {
        let left = ControlIslandPlacement.flapFrame(for: rail, at: .left, in: area)
        #expect(left == CGRect(x: 0, y: 418, width: 6, height: 64), "centered on the rail's middle")
        let trailing = CGRect(x: 1_540, y: 200, width: 48, height: 500)
        let right = ControlIslandPlacement.flapFrame(for: trailing, at: .right, in: area)
        #expect(right == CGRect(x: 1_594, y: 418, width: 6, height: 64))
        let high = ControlIslandPlacement.flapFrame(for: CGRect(x: 12, y: 0, width: 48, height: 40), at: .left, in: area)
        #expect(high.minY == 0)
        let low = ControlIslandPlacement.flapFrame(for: CGRect(x: 12, y: 980, width: 48, height: 40), at: .right, in: area)
        #expect(low.maxY == area.maxY)
    }

    @Test @MainActor
    func `light from a rail hidden at the right edge starts on that edge's flap, not on the left`() {
        let configuration = ControlIslandConfiguration(defaults: nil)
        configuration.setHidesAtEdge(true)
        let state = ControlIslandState(defaults: nil, configuration: configuration)
        state.placement = ControlIslandPlacement(x: 1, y: 0.5)
        state.areaBounds = area
        let resting = CGRect(x: 1_540, y: 250, width: 48, height: 500)
        state.railLayoutFrame = resting
        #expect(state.side == .right)

        // Hidden from launch (the placement is snapped and hiding is on): the rail reports no frame.
        #expect(state.isHiddenAtEdge)
        state.railFrame = .zero
        let hidden = state.lightSource
        #expect(hidden == ControlIslandPlacement.flapFrame(for: resting, at: .right, in: area))
        #expect(hidden.minX >= area.maxX - ControlIslandPlacement.flapWidth, "on the right edge")
        #expect(abs(hidden.midY - resting.midY) < 0.01, "at the rail's height")

        // Back on screen: the rail itself.
        state.revealAtEdge(.pointer)
        state.railFrame = resting
        #expect(state.lightSource == resting)

        // Away again: the flap again.
        state.hideAtEdge()
        state.railFrame = .zero
        #expect(state.lightSource == hidden)
    }

    @Test @MainActor
    func `light from a rail hidden at the left edge starts on the left flap, and a shown rail is its own source`() {
        let configuration = ControlIslandConfiguration(defaults: nil)
        configuration.setHidesAtEdge(true)
        let state = ControlIslandState(defaults: nil, configuration: configuration)
        state.placement = ControlIslandPlacement(x: 0, y: 0)
        state.areaBounds = area
        state.railLayoutFrame = rail
        #expect(state.side == .left)
        #expect(state.lightSource == ControlIslandPlacement.flapFrame(for: rail, at: .left, in: area))
        #expect(state.lightSource.minX == area.minX)

        let shown = ControlIslandState(defaults: nil, configuration: ControlIslandConfiguration(defaults: nil))
        shown.placement = ControlIslandPlacement(x: 1, y: 0.5)
        shown.areaBounds = area
        shown.railLayoutFrame = CGRect(x: 1_540, y: 250, width: 48, height: 500)
        shown.railFrame = shown.railLayoutFrame
        #expect(!shown.isHiddenAtEdge)
        #expect(shown.lightSource == shown.railFrame, "a rail that does not hide lights from itself")
        shown.railFrame = .zero
        #expect(shown.lightSource == .zero, "before the first layout there is no source yet")
    }

    @Test
    func `the reveal strip runs along the edge past both ends of the rail`() {
        let left = ControlIslandPlacement.revealStrip(for: rail, at: .left, in: area)
        #expect(left == CGRect(x: 0, y: 160, width: 6, height: 580))
        let right = ControlIslandPlacement.revealStrip(for: rail, at: .right, in: area)
        #expect(right == CGRect(x: 1_594, y: 160, width: 6, height: 580))
    }

    @Test
    func `the reveal strip stays inside the window`() {
        let top = CGRect(x: 12, y: 12, width: 48, height: 500)
        let strip = ControlIslandPlacement.revealStrip(for: top, at: .left, in: area)
        #expect(strip.minY == 0)
        #expect(strip.maxY == 552)
        #expect(area.contains(strip))
    }

    @Test
    func `a hidden rail sits wholly past its edge with room for its shadow`() {
        let left = ControlIslandPlacement.hiddenFrame(for: rail, at: .left, in: area)
        #expect(left.maxX <= area.minX - ControlIslandPlacement.hiddenShadowClearance)
        #expect(left.size == rail.size)
        #expect(left.minY == rail.minY)
        let trailing = CGRect(x: 1_540, y: 200, width: 48, height: 500)
        let right = ControlIslandPlacement.hiddenFrame(for: trailing, at: .right, in: area)
        #expect(right.minX >= area.maxX + ControlIslandPlacement.hiddenShadowClearance)
        #expect(!right.intersects(area))
    }

    @Test @MainActor
    func `the rail shows by default, and the hiding setting survives relaunch`() throws {
        let suite = "ControlIslandEdgeHidingTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let configuration = ControlIslandConfiguration(defaults: defaults)
        #expect(!configuration.hidesAtEdge)
        configuration.setHidesAtEdge(true)
        let restored = ControlIslandConfiguration(defaults: defaults)
        #expect(restored.hidesAtEdge)

        let state = ControlIslandState(defaults: defaults, configuration: restored)
        state.placement = ControlIslandPlacement(x: 0, y: 0.5)
        #expect(state.hiddenEdge == .left)
        state.placement = ControlIslandPlacement(x: 0.5, y: 0)
        #expect(state.hiddenEdge == nil)
        #expect(!state.isHiddenAtEdge)
    }

    @Test @MainActor
    func `the pointer at the edge brings the rail back and Escape sends it away`() {
        let configuration = ControlIslandConfiguration(defaults: nil)
        configuration.setHidesAtEdge(true)
        let state = ControlIslandState(defaults: nil, configuration: configuration)
        state.placement = ControlIslandPlacement(x: 0, y: 0.5)
        state.hideAtEdge()
        #expect(state.isHiddenAtEdge)
        state.revealStrip = ControlIslandPlacement.revealStrip(for: rail, at: .left, in: area)

        _ = state.tracksPointer(CGPoint(x: 400, y: 400))
        #expect(state.isHiddenAtEdge)
        _ = state.tracksPointer(CGPoint(x: 3, y: 400))
        #expect(!state.isHiddenAtEdge)
        #expect(state.edgeReveal == .pointer)

        #expect(state.hideAfterPointerReveal())
        #expect(state.isHiddenAtEdge)
    }

    @Test @MainActor
    func `a requested reveal ignores Escape and hiding closes the card first`() {
        let configuration = ControlIslandConfiguration(defaults: nil)
        configuration.setHidesAtEdge(true)
        let state = ControlIslandState(defaults: nil, configuration: configuration)
        state.placement = ControlIslandPlacement(x: 1, y: 0)
        state.hideAtEdge()
        state.focus()
        #expect(!state.isHiddenAtEdge)
        #expect(state.edgeReveal == .request)
        #expect(!state.hideAfterPointerReveal())

        state.showsAddress = true
        state.hasKeyboardFocus = false
        let dismissals = state.dismissalRequest
        state.hideAtEdge()
        #expect(state.isHiddenAtEdge)
        #expect(!state.showsAddress)
        #expect(state.dismissalRequest == dismissals + 1)
    }

    @Test @MainActor
    func `turning the setting off shows a hidden rail`() {
        let configuration = ControlIslandConfiguration(defaults: nil)
        configuration.setHidesAtEdge(true)
        let state = ControlIslandState(defaults: nil, configuration: configuration)
        state.placement = ControlIslandPlacement(x: 0, y: 0)
        state.hideAtEdge()
        #expect(state.isHiddenAtEdge)
        state.setHidesAtEdge(false)
        #expect(!state.isHiddenAtEdge)
        #expect(state.hiddenEdge == nil)
    }
}
