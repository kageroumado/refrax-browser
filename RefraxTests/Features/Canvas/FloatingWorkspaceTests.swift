import Foundation
import Testing
@testable import Refrax

@Suite(.serialized)
@MainActor
struct FloatingWorkspaceTests {
    @Test
    func `private placements stay in the window while reveal remains stable`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        space.dataStoreMode = .private
        let window = env.makeActiveWindowState(with: space)
        let tab = try env.tabManager.createTab(url: #require(URL(string: "about:blank")), in: space, makeActive: false)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        canvas.toggleFloatingTabs()
        #expect(canvas.visibleFloatingTabs.contains(where: { $0.id == tab.id }))
        #expect(canvas.unplacedFloatingTabs.isEmpty)
        var moved = canvas.floatingPlacement(for: tab)
        moved.x = 0.7
        canvas.updateFloatingPlacement(moved, for: tab)
        canvas.dismissFloatingTabs()
        canvas.toggleFloatingTabs()
        #expect(canvas.floatingPlacement(for: tab) == moved)
        #expect(tab.floatingPlacement == nil)
    }

    @Test
    func `window reading state restores valid pages and excludes private space selections`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let other = env.makeSpace(name: "Other")
        let privateSpace = env.makeSpace(name: "Private")
        privateSpace.dataStoreMode = .private
        let window = env.makeActiveWindowState(with: space)
        let source = try env.createActiveTab(url: #require(URL(string: "about:blank#source")), in: space, for: window)
        let reference = try env.tabManager.createTab(url: #require(URL(string: "about:blank#reference")), in: other, makeActive: false)
        let secret = try env.tabManager.createTab(url: #require(URL(string: "about:blank#private")), in: privateSpace, makeActive: false)
        window.setActiveTabID(reference.id, for: other.id)
        window.setActiveTabID(secret.id, for: privateSpace.id)
        let data = try JSONEncoder().encode(window.readingState)
        let saved = try JSONDecoder().decode(WindowReadingState.self, from: data)
        #expect(saved.tabIDsBySpace[privateSpace.id] == nil)
        let restored = env.makeActiveWindowState(with: space)
        #expect(restored.restoreReadingState(saved)?.id == source.id)
        #expect(restored.activeTabID(for: other.id) == reference.id)
        env.tabManager.closeTab(source)
        #expect(restored.restoreReadingState(saved) == nil)
    }

    @Test
    func `new pages extend the table without moving existing placements`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        var pages: [Tab] = []
        for index in 0 ..< 8 {
            try pages.append(env.tabManager.createTab(url: #require(URL(string: "about:blank#\(index)")), in: space, makeActive: false))
        }
        canvas.toggleFloatingTabs()
        #expect(canvas.unplacedFloatingTabs.isEmpty)
        let placed = try #require(pages.first(where: { $0.floatingPlacement != nil }))
        let before = canvas.floatingPlacement(for: placed)
        try env.tabManager.createTab(url: #require(URL(string: "about:blank#new")), in: space, makeActive: false)
        canvas.dismissFloatingTabs()
        canvas.toggleFloatingTabs()
        #expect(canvas.unplacedFloatingTabs.isEmpty)
        #expect(canvas.floatingPlacement(for: placed) == before)
    }

    @Test
    func `a related new page appears beside its parent and can be reached in both directions`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let parent = try env.createActiveTab(url: #require(URL(string: "about:blank#parent")), in: space, for: window)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        canvas.revealFloatingTabs()
        let original = canvas.tablePlacement(for: parent)
        let child = try env.tabManager.createTab(
            url: #require(URL(string: "about:blank#child")), in: space, makeActive: false, insertionStrategy: .afterActive,
        )
        canvas.releaseFloatingTabs()
        canvas.revealFloatingTabs()
        let ids = Set([parent.id, child.id])
        #expect(canvas.tablePlacement(for: parent) == original)
        #expect(canvas.spatialNeighbor(from: parent.id, toward: .right, among: ids) == child.id)
        #expect(canvas.spatialNeighbor(from: child.id, toward: .left, among: ids) == parent.id)
    }

    @Test
    func `a foreground page starts beside the page it replaced`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        let unrelated = try env.tabManager.createTab(url: #require(URL(string: "about:blank#unrelated")), in: space, makeActive: false)
        let parent = try env.createActiveTab(url: #require(URL(string: "about:blank#parent")), in: space, for: window)
        for (tab, origin) in [(unrelated, CGPoint(x: 900, y: 900)), (parent, CGPoint(x: 100, y: 100))] {
            var placement = FloatingTabPlacement.initial(index: 0)
            placement.tableOrigin = origin
            canvas.storeTablePlacement(placement, for: tab)
        }
        let child = try env.tabManager.createTab(
            url: #require(URL(string: "about:blank#child")), in: space, makeActive: true, insertionStrategy: .afterActive,
        )
        let ids = Set([unrelated.id, parent.id, child.id])
        #expect(canvas.spatialNeighbor(from: parent.id, toward: .right, among: ids) == child.id)
        #expect(canvas.spatialNeighbor(from: child.id, toward: .left, among: ids) == parent.id)
        #expect(canvas.tablePlacement(for: unrelated).tableOrigin == CGPoint(x: 900, y: 900))
    }

    @Test
    func `a fresh foreground tab starts outside the current wheel row`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        let current = try env.createActiveTab(url: #require(URL(string: "about:blank#current")), in: space, for: window)
        var placement = FloatingTabPlacement.initial(index: 0)
        placement.tableOrigin = CGPoint(x: 100, y: 100)
        canvas.storeTablePlacement(placement, for: current)

        let fresh = try env.tabManager.createTab(url: #require(URL(string: "about:blank#fresh")), in: space, makeActive: true)

        let ids = Set([current.id, fresh.id])
        #expect(canvas.tablePlacement(for: fresh).tableOrigin != nil)
        #expect(TableDirection.allCases.allSatisfy { canvas.spatialNeighbor(from: current.id, toward: $0, among: ids) == nil })
    }

    @Test
    func `coincident saved cards separate without moving the active card or other neighbors`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let active = try env.createActiveTab(url: #require(URL(string: "about:blank#active")), in: space, for: window)
        let hidden = try env.tabManager.createTab(url: #require(URL(string: "about:blank#hidden")), in: space, makeActive: false)
        let neighbor = try env.tabManager.createTab(url: #require(URL(string: "about:blank#neighbor")), in: space, makeActive: false)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        var shared = FloatingTabPlacement.initial(index: 0)
        shared.tableOrigin = CGPoint(x: 100, y: 100)
        canvas.storeTablePlacement(shared, for: active)
        canvas.storeTablePlacement(shared, for: hidden)
        var separate = FloatingTabPlacement.initial(index: 0)
        separate.tableOrigin = CGPoint(x: 500, y: 500)
        canvas.storeTablePlacement(separate, for: neighbor)

        canvas.revealFloatingTabs()
        let moved = canvas.tablePlacement(for: hidden)
        #expect(canvas.tablePlacement(for: active).tableOrigin == shared.tableOrigin)
        #expect(canvas.tablePlacement(for: neighbor).tableOrigin == separate.tableOrigin)
        #expect(moved.tableOrigin != shared.tableOrigin)
        canvas.releaseFloatingTabs()
        canvas.revealFloatingTabs()
        #expect(canvas.tablePlacement(for: hidden) == moved)
    }

    @Test
    func `each revealed window retains its own placement`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let first = env.makeActiveWindowState(with: space)
        let second = env.makeActiveWindowState(with: space)
        let tab = try env.tabManager.createTab(url: #require(URL(string: "about:blank")), in: space, makeActive: false)
        tab.floatingPlacement = .initial(index: 0)
        let a = TabCanvasManager(tabManager: env.tabManager, windowState: first, pagePool: env.pagePool, groupManager: env.groupManager)
        let b = TabCanvasManager(tabManager: env.tabManager, windowState: second, pagePool: env.pagePool, groupManager: env.groupManager)
        a.toggleFloatingTabs()
        b.toggleFloatingTabs()
        let before = b.floatingPlacement(for: tab)
        var moved = a.floatingPlacement(for: tab)
        moved.x = 0.7
        a.updateFloatingPlacement(moved, for: tab)
        #expect(b.floatingPlacement(for: tab) == before)
        #expect(a.floatingPlacement(for: tab) == moved)
    }

    @Test
    func `favoriting a temporary visit preserves the return destination`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let source = try env.createActiveTab(url: #require(URL(string: "about:blank#source")), in: space, for: window)
        let reference = try env.tabManager.createTab(url: #require(URL(string: "about:blank#reference")), in: space, makeActive: false)
        env.tabManager.look(at: reference, in: window)
        ControlIslandTabActions(tab: reference, windowState: window, tabs: env.tabManager, bookmarks: env.bookmarksManager).toggleFavorite()
        #expect(window.activeTab?.isFavorite == true)
        #expect(window.pageVisit.destination?.tabID == source.id)
        #expect(env.tabManager.returnFromLook(in: window))
        #expect(window.activeTabID == source.id)
    }
}
