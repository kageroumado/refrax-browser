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
    func `the setting survives relaunch and starts the rail hidden at its edge`() throws {
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

    @Test
    func `a card dropped on loose cards groups with the topmost under the pointer`() {
        let cards: [(id: Int, frame: CGRect)] = [
            (1, CGRect(x: 0, y: 0, width: 300, height: 200)),
            (2, CGRect(x: 100, y: 100, width: 300, height: 200)),
        ]
        #expect(FloatingGroupLayout.cardDropTarget(at: CGPoint(x: 150, y: 150), among: cards) == 2)
        #expect(FloatingGroupLayout.cardDropTarget(at: CGPoint(x: 50, y: 50), among: cards) == 1)
        #expect(FloatingGroupLayout.cardDropTarget(at: CGPoint(x: 900, y: 900), among: cards) == nil)
    }
}
