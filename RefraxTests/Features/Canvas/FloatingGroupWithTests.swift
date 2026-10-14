import CoreGraphics
import Foundation
import Testing
@testable import Refrax

@Suite(.serialized)
@MainActor
struct FloatingGroupWithTests {
    @Test
    func `Group With sets cards from across the window side by side`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        _ = try env.createActiveTab(url: #require(URL(string: "about:blank#current")), in: space, for: window)
        let first = try env.tabManager.createTab(url: #require(URL(string: "about:blank#first")), in: space, makeActive: false)
        let second = try env.tabManager.createTab(url: #require(URL(string: "about:blank#second")), in: space, makeActive: false)
        canvas.updateFloatingPlacement(.init(x: 0, y: 0.5, shape: .tab, isPinned: false), for: first)
        canvas.updateFloatingPlacement(.init(x: 1, y: 1, shape: .tab, isPinned: false), for: second)

        canvas.groupFloatingCard(first, with: [second])

        let area = canvas.floatingArea
        let a = canvas.floatingFrame(for: first, in: area)
        let b = canvas.floatingFrame(for: second, in: area)
        #expect(first.group != nil)
        #expect(first.group?.id == second.group?.id)
        #expect(abs(a.minY - b.minY) < 1 || abs(a.minX - b.minX) < 1)
        #expect(hypot(b.minX - a.minX, b.minY - a.minY) < max(a.width, a.height) * 2)
    }

    @Test
    func `A group of only the current page draws no outline`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        let current = try env.createActiveTab(url: #require(URL(string: "about:blank#current")), in: space, for: window)
        let other = try env.tabManager.createTab(url: #require(URL(string: "about:blank#other")), in: space, makeActive: false)
        canvas.updateFloatingPlacement(.init(x: 0.5, y: 0.5, shape: .tab, isPinned: false), for: current)
        canvas.updateFloatingPlacement(.init(x: 0.2, y: 0.2, shape: .tab, isPinned: false), for: other)

        canvas.groupFloatingCard(current, with: [other])
        let group = try #require(current.group)
        #expect(canvas.floatingGroupItems(in: canvas.floatingArea).first { $0.id == group.id }?.members.map(\.id) == [other.id])

        env.tabManager.closeTab(other)
        #expect(!canvas.floatingGroupItems(in: canvas.floatingArea).contains { $0.id == group.id })
    }
}
