import Foundation
import SwiftData
import SwiftUI
import Testing
import WebKit
@testable import Refrax

// MARK: - TabManager Convert Tab To Favorite Tests

@Suite("TabManager Convert Tab To Favorite", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerConvertToFavoriteTests {
    @Test
    func `Convert tab to live favorite creates bookmark`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )
        tab.activePage.title = "Example"

        let success = env.tabManager.convertTabToFavorite(tab, mode: .liveFavorite)

        #expect(success != nil, "Conversion should succeed")
        #expect(tab.isFavorite, "The same tab should become the favorite")

        // Check a favorite bookmark was created
        let favorites = env.bookmarksManager.favorites
        #expect(favorites.contains(where: { $0.bookmark?.url == tab.activePage.url }), "Favorite should exist")
    }

    @Test
    func `Convert tab to shortcut creates bookmark`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://shortcut.com")),
            in: space,
            makeActive: true,
        )
        tab.activePage.title = "Shortcut"

        let success = env.tabManager.convertTabToFavorite(tab, mode: .shortcut)

        #expect(success != nil, "Conversion should succeed")

        let favorites = env.bookmarksManager.favorites
        #expect(favorites.contains(where: { $0.bookmark?.url == tab.activePage.url }), "Shortcut favorite should exist")
    }

    @Test
    func `Convert tab copies favicon data to bookmark`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://favicon.com")),
            in: space,
            makeActive: true,
        )
        tab.activePage.title = "Favicon Test"

        // Set fake favicon data
        let faviconData = Data("fake-icon".utf8)
        tab.activePage.faviconData = faviconData

        env.tabManager.convertTabToFavorite(tab, mode: .shortcut)

        let favorites = env.bookmarksManager.favorites
        let favoriteItem = favorites.first { $0.bookmark?.url == tab.activePage.url }
        #expect(favoriteItem?.bookmark?.faviconData == faviconData, "Favicon data should be copied")
    }

    @Test
    func `Convert tab increments content version`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://version.com")),
            in: space,
            makeActive: true,
        )

        let versionBefore = env.browserState.tabContentVersion

        env.tabManager.convertTabToFavorite(tab, mode: .liveFavorite)

        #expect(env.browserState.tabContentVersion > versionBefore, "Should increment content version")
    }
}

// MARK: - TabManager Add Tab To Group Tests

@Suite("TabManager Add Tab To Group", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerAddToGroupTests {
    @Test
    func `Add tab to group sets group ID`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Test Group")

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        #expect(tab.groupID == nil, "Tab should start ungrouped")

        let success = env.tabManager.addTabToGroup(tab, groupID: group.id)

        #expect(success, "Should succeed")
        #expect(tab.groupID == group.id, "Tab should be in group")
    }

    @Test
    func `Add tab to group increments list version`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Test Group")
        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        let versionBefore = env.browserState.tabListVersion

        env.tabManager.addTabToGroup(tab, groupID: group.id)

        #expect(env.browserState.tabListVersion > versionBefore, "Should increment list version")
    }

    @Test
    func `Add tab to non-existent group fails`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        let fakeGroupID = UUID()
        let success = env.tabManager.addTabToGroup(tab, groupID: fakeGroupID)

        #expect(!success, "Should fail for non-existent group")
        #expect(tab.groupID == nil, "Tab should remain ungrouped")
    }

    @Test
    func `Add tab to group in different space fails`() throws {
        let env = try TabManagerTestEnvironment()
        let space1 = env.makeSpace(name: "Space 1")
        let space2 = env.makeSpace(name: "Space 2")
        _ = env.makeActiveWindowState(with: space1)

        let group = try env.groupManager.createGroup(in: space2, name: "Group in Space 2")

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space1,
            makeActive: true,
        )

        let success = env.tabManager.addTabToGroup(tab, groupID: group.id)

        #expect(!success, "Should fail for group in different space")
    }
}

// MARK: - TabManager Pin Group Tests

@Suite("TabManager Pin Group", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerPinGroupTests {
    @Test
    func `Pin group sets group isPinned`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Test Group")

        #expect(!group.isPinned, "Group should start unpinned")

        env.tabManager.pinGroup(group)

        #expect(group.isPinned, "Group should be pinned")
    }

    @Test
    func `Pin group pins all tabs in group`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Test Group")

        let tab1 = try env.tabManager.createTab(url: #require(URL(string: "https://one.com")), in: space, groupID: group.id, makeActive: false)
        let tab2 = try env.tabManager.createTab(url: #require(URL(string: "https://two.com")), in: space, groupID: group.id, makeActive: false)

        #expect(!tab1.isInPinnedGroup)
        #expect(!tab2.isInPinnedGroup)

        env.tabManager.pinGroup(group)

        #expect(tab1.isInPinnedGroup, "Tab 1 should be pinned")
        #expect(tab2.isInPinnedGroup, "Tab 2 should be pinned")
    }

    @Test
    func `Pin group pins nested groups and their tabs`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let parentGroup = try env.groupManager.createGroup(in: space, name: "Parent")
        let nestedGroup = try env.groupManager.createGroup(in: space, name: "Nested", parentGroupID: parentGroup.id)

        let tabInParent = try env.tabManager.createTab(url: #require(URL(string: "https://parent.com")), in: space, groupID: parentGroup.id, makeActive: false)
        let tabInNested = try env.tabManager.createTab(url: #require(URL(string: "https://nested.com")), in: space, groupID: nestedGroup.id, makeActive: false)

        env.tabManager.pinGroup(parentGroup)

        #expect(parentGroup.isPinned, "Parent should be pinned")
        #expect(nestedGroup.isPinned, "Nested group should be pinned")
        #expect(tabInParent.isInPinnedGroup, "Tab in parent should be pinned")
        #expect(tabInNested.isInPinnedGroup, "Tab in nested should be pinned")
    }

    @Test
    func `Pin group increments list version`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Test Group")

        let versionBefore = env.browserState.tabListVersion

        env.tabManager.pinGroup(group)

        #expect(env.browserState.tabListVersion > versionBefore, "Should increment list version")
    }
}

// MARK: - TabManager Nest Group Tests

@Suite("TabManager Nest Group", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerNestGroupTests {
    @Test
    func `Nest group prevents same group nesting`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Test Group")

        // Create mock layout manager
        let layoutManager = createTestLayoutManager(env: env, windowState: windowState)

        let success = env.tabManager.nestGroup(group, in: group.id, using: layoutManager)

        #expect(!success, "Should not allow nesting group in itself")
    }

    @Test
    func `Nest group only allows root groups to be nested`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let parentGroup = try env.groupManager.createGroup(in: space, name: "Parent")
        let nestedGroup = try env.groupManager.createGroup(in: space, name: "Nested", parentGroupID: parentGroup.id)
        let targetGroup = try env.groupManager.createGroup(in: space, name: "Target")

        let layoutManager = createTestLayoutManager(env: env, windowState: windowState)

        // Try to nest an already-nested group
        let success = env.tabManager.nestGroup(nestedGroup, in: targetGroup.id, using: layoutManager)

        #expect(!success, "Already nested group should not be allowed to nest")
    }

    @Test
    func `Nest group only allows nesting into root groups`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let rootGroup = try env.groupManager.createGroup(in: space, name: "Root")
        let parentGroup = try env.groupManager.createGroup(in: space, name: "Parent")
        let nestedGroup = try env.groupManager.createGroup(in: space, name: "Nested", parentGroupID: parentGroup.id)

        let layoutManager = createTestLayoutManager(env: env, windowState: windowState)

        // Try to nest into an already-nested group (would create depth > 2)
        let success = env.tabManager.nestGroup(rootGroup, in: nestedGroup.id, using: layoutManager)

        #expect(!success, "Should not allow nesting into nested group")
    }

    @Test
    func `Nest group succeeds for valid nesting`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let childGroup = try env.groupManager.createGroup(in: space, name: "Child")
        let parentGroup = try env.groupManager.createGroup(in: space, name: "Parent")

        let layoutManager = createTestLayoutManager(env: env, windowState: windowState)

        #expect(childGroup.parentGroupID == nil, "Child should start at root")

        let success = env.tabManager.nestGroup(childGroup, in: parentGroup.id, using: layoutManager)

        #expect(success, "Valid nesting should succeed")
        #expect(childGroup.parentGroupID == parentGroup.id, "Child should be nested")
    }

    @Test
    func `Nest group increments list version on success`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let childGroup = try env.groupManager.createGroup(in: space, name: "Child")
        let parentGroup = try env.groupManager.createGroup(in: space, name: "Parent")

        let layoutManager = createTestLayoutManager(env: env, windowState: windowState)

        let versionBefore = env.browserState.tabListVersion

        env.tabManager.nestGroup(childGroup, in: parentGroup.id, using: layoutManager)

        #expect(env.browserState.tabListVersion > versionBefore, "Should increment list version")
    }

    // MARK: - Helper

    private func createTestLayoutManager(env: TabManagerTestEnvironment, windowState: WindowState) -> Sidebar.LayoutManager {
        let filterManager = Sidebar.FilterManager()
        filterManager.pageLookup = { _ in nil }

        let layoutManager = Sidebar.LayoutManager()
        layoutManager.windowState = windowState
        layoutManager.tabManager = env.tabManager
        layoutManager.bookmarksManager = env.bookmarksManager
        layoutManager.filterManager = filterManager

        // Create a minimal drag coordinator
        let dragCoordinator = Sidebar.DragCoordinator()
        dragCoordinator.layoutManager = layoutManager
        dragCoordinator.windowState = windowState
        layoutManager.dragCoordinator = dragCoordinator

        // Trigger initial layout build
        layoutManager.rebuildLayout()

        return layoutManager
    }
}

// MARK: - TabManager Favorite Group Tests

@Suite("TabManager Favorite Group", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerFavoriteGroupTests {
    @Test
    func `Favorite group creates live favorites for all tabs`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Test Group")

        let tab1 = try env.tabManager.createTab(url: #require(URL(string: "https://one.com")), in: space, makeActive: false)
        tab1.groupID = group.id

        let tab2 = try env.tabManager.createTab(url: #require(URL(string: "https://two.com")), in: space, makeActive: false)
        tab2.groupID = group.id

        let favoritesBefore = env.bookmarksManager.favorites.count

        env.tabManager.favoriteGroup(group)

        let favoritesAfter = env.bookmarksManager.favorites.count
        #expect(favoritesAfter == favoritesBefore + 2, "Should create 2 favorites")
    }

    @Test
    func `Favorite group includes nested group tabs`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let parentGroup = try env.groupManager.createGroup(in: space, name: "Parent")
        let nestedGroup = try env.groupManager.createGroup(in: space, name: "Nested", parentGroupID: parentGroup.id)

        let tabInParent = try env.tabManager.createTab(url: #require(URL(string: "https://parent.com")), in: space, groupID: parentGroup.id, makeActive: false)
        let tabInNested = try env.tabManager.createTab(url: #require(URL(string: "https://nested.com")), in: space, groupID: nestedGroup.id, makeActive: false)

        let favoritesBefore = env.bookmarksManager.favorites.count

        env.tabManager.favoriteGroup(parentGroup)

        let favoritesAfter = env.bookmarksManager.favorites.count
        #expect(favoritesAfter == favoritesBefore + 2, "Should create favorites for both tabs")
    }

    @Test
    func `Favorite group increments content version`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Test Group")

        let tab = try env.tabManager.createTab(url: #require(URL(string: "https://one.com")), in: space, makeActive: false)
        tab.groupID = group.id

        let versionBefore = env.browserState.tabContentVersion

        env.tabManager.favoriteGroup(group)

        #expect(env.browserState.tabContentVersion > versionBefore, "Should increment content version")
    }
}
