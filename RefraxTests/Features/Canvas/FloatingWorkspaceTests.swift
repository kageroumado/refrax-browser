import Foundation
import Testing
@testable import Refrax

@Suite(.serialized)
@MainActor
struct FloatingWorkspaceTests {
    @Test func `private placements stay in the window while reveal remains stable`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        space.dataStoreMode = .private
        let window = env.makeActiveWindowState(with: space)
        let tab = env.tabManager.createTab(url: try #require(URL(string: "about:blank")), in: space, makeActive: false)
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

    @Test func `window reading state restores valid pages and excludes private space selections`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let other = env.makeSpace(name: "Other")
        let privateSpace = env.makeSpace(name: "Private")
        privateSpace.dataStoreMode = .private
        let window = env.makeActiveWindowState(with: space)
        let source = env.createActiveTab(url: try #require(URL(string: "about:blank#source")), in: space, for: window)
        let reference = env.tabManager.createTab(url: try #require(URL(string: "about:blank#reference")), in: other, makeActive: false)
        let secret = env.tabManager.createTab(url: try #require(URL(string: "about:blank#private")), in: privateSpace, makeActive: false)
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

    @Test func `new pages collect in Recent without moving existing placements`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let canvas = TabCanvasManager(tabManager: env.tabManager, windowState: window, pagePool: env.pagePool, groupManager: env.groupManager)
        var pages: [Tab] = []
        for index in 0..<8 {
            pages.append(env.tabManager.createTab(url: try #require(URL(string: "about:blank#\(index)")), in: space, makeActive: false))
        }
        canvas.toggleFloatingTabs()
        #expect(canvas.unplacedFloatingTabs.count == 4)
        let placed = try #require(pages.first(where: { $0.floatingPlacement != nil }))
        let before = canvas.floatingPlacement(for: placed)
        env.tabManager.createTab(url: try #require(URL(string: "about:blank#new")), in: space, makeActive: false)
        canvas.dismissFloatingTabs()
        canvas.toggleFloatingTabs()
        #expect(canvas.unplacedFloatingTabs.count == 5)
        #expect(canvas.floatingPlacement(for: placed) == before)
    }

    @Test func `each revealed window retains its own placement`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let first = env.makeActiveWindowState(with: space)
        let second = env.makeActiveWindowState(with: space)
        let tab = env.tabManager.createTab(url: try #require(URL(string: "about:blank")), in: space, makeActive: false)
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

    @Test func `favoriting a temporary visit preserves the return destination`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let window = env.makeActiveWindowState(with: space)
        let source = env.createActiveTab(url: try #require(URL(string: "about:blank#source")), in: space, for: window)
        let reference = env.tabManager.createTab(url: try #require(URL(string: "about:blank#reference")), in: space, makeActive: false)
        env.tabManager.look(at: reference, in: window)
        ControlIslandTabActions(tab: reference, windowState: window, tabs: env.tabManager, bookmarks: env.bookmarksManager).toggleFavorite()
        #expect(window.activeTab?.isLiveFavorite == true)
        #expect(window.pageVisit.destination?.tabID == source.id)
        #expect(env.tabManager.returnFromLook(in: window))
        #expect(window.activeTabID == source.id)
    }
}
