import Foundation
import Testing
@testable import Refrax

@Suite(.serialized)
@MainActor
struct FloatingWorkspaceTests {
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
