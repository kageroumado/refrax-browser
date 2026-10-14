import CoreGraphics
import Foundation
import Testing
@testable import Refrax

@Suite(.serialized)
@MainActor
struct FloatingGroupWithTests {
    @Test
    func `grouping a selection places its cards together`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        _ = try env.createActiveTab(url: #require(URL(string: "about:blank#current")), in: space, for: window)
        let first = try env.tabManager.createTab(url: #require(URL(string: "about:blank#first")), in: space, makeActive: false)
        let second = try env.tabManager.createTab(url: #require(URL(string: "about:blank#second")), in: space, makeActive: false)
        canvas.updateFloatingPlacement(.init(x: 0, y: 0.5, shape: .tab, isPinned: false), for: first)
        canvas.updateFloatingPlacement(.init(x: 1, y: 0.5, shape: .tab, isPinned: false), for: second)
        canvas.selectedFloatingTabIDs = [first.id, second.id]

        canvas.groupFloatingSelection()

        let area = canvas.floatingArea
        let a = canvas.tablePlacement(for: first).frame(in: area)
        let b = canvas.tablePlacement(for: second).frame(in: area)
        let ids = Set([first.id, second.id])
        #expect(first.group?.id == second.group?.id)
        #expect(abs(b.minX - a.maxX) <= FloatingArrangement.gap + 1 || abs(a.minX - b.maxX) <= FloatingArrangement.gap + 1)
        #expect(canvas.spatialNeighbor(from: first.id, toward: .left, among: ids) == second.id
            || canvas.spatialNeighbor(from: first.id, toward: .right, among: ids) == second.id,
            "First: \(a), second: \(b), folded: \(canvas.isFolded(first))/\(canvas.isFolded(second))")
    }

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
    func `Dropping beside a card connects them without moving either card`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        _ = try env.createActiveTab(url: #require(URL(string: "about:blank#current")), in: space, for: window)
        let first = try env.tabManager.createTab(url: #require(URL(string: "about:blank#first")), in: space, makeActive: false)
        let second = try env.tabManager.createTab(url: #require(URL(string: "about:blank#second")), in: space, makeActive: false)
        canvas.revealFloatingTabs()
        canvas.latchFloatingTabs()
        let area = canvas.floatingArea
        var firstPlacement = canvas.floatingPlacement(for: first)
        firstPlacement.move(to: CGPoint(x: 100, y: 200), in: area)
        canvas.updateFloatingPlacement(firstPlacement, for: first)
        var secondPlacement = canvas.floatingPlacement(for: second)
        secondPlacement.move(to: CGPoint(x: canvas.floatingFrame(for: first, in: area).maxX + 12, y: 200), in: area)
        canvas.updateFloatingPlacement(secondPlacement, for: second)
        let firstFrame = canvas.floatingFrame(for: first, in: area)
        let secondFrame = canvas.floatingFrame(for: second, in: area)

        canvas.updateFloatingDropTarget(at: CGPoint(x: secondFrame.midX, y: secondFrame.midY), dragging: [second], in: area)
        #expect(canvas.floatingDropCardID == first.id)
        #expect(canvas.floatingDropBridge != nil)
        canvas.dropIntoTarget([second])

        #expect(first.group?.id == second.group?.id)
        #expect(canvas.floatingFrame(for: first, in: area) == firstFrame)
        #expect(canvas.floatingFrame(for: second, in: area) == secondFrame)
        #expect(canvas.spatialNeighbor(from: first.id, toward: .right, among: [first.id, second.id]) == second.id)
        #expect(canvas.spatialNeighbor(from: second.id, toward: .left, among: [first.id, second.id]) == first.id)
        #expect(canvas.floatingRenamingGroupID == nil)
        #expect(canvas.floatingDropCardID == nil)
    }

    @Test
    func `joining a group brings a distant card next to its members`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        _ = try env.createActiveTab(url: #require(URL(string: "about:blank#current")), in: space, for: window)
        let first = try env.tabManager.createTab(url: #require(URL(string: "about:blank#first")), in: space, makeActive: false)
        let second = try env.tabManager.createTab(url: #require(URL(string: "about:blank#second")), in: space, makeActive: false)
        let third = try env.tabManager.createTab(url: #require(URL(string: "about:blank#third")), in: space, makeActive: false)
        canvas.updateFloatingPlacement(.init(x: 0, y: 0.5, shape: .tab, isPinned: false), for: first)
        canvas.updateFloatingPlacement(.init(x: 0.3, y: 0.5, shape: .tab, isPinned: false), for: second)
        canvas.updateFloatingPlacement(.init(x: 1, y: 1, shape: .tab, isPinned: false), for: third)
        canvas.groupFloatingCard(first, with: [second])
        let group = try #require(first.group)

        canvas.addToFloatingGroup([third], group: group)

        let frames = [first, second, third].map { canvas.tablePlacement(for: $0).frame(in: canvas.floatingArea) }
        let maxX = try #require(frames.map(\.maxX).max())
        let minX = try #require(frames.map(\.minX).min())
        #expect(third.group?.id == group.id)
        #expect(maxX - minX <= 2 * frames[0].width + FloatingGroupLayout.fanGap + 1)
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
