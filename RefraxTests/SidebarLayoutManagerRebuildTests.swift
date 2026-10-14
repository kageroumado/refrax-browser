import Foundation
import Testing
@testable import Refrax

@Suite("Sidebar.LayoutManager Rebuild", .tags(.sidebarLayoutManager), .serialized)
@MainActor
struct SidebarLayoutManagerRebuildTests {
    @Test
    func `Rebuild keeps favorites when no active space`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()
        let managers = SidebarManagers(
            tabManager: env.tabManager,
            bookmarksManager: env.bookmarksManager,
            windowState: windowState,
            groupManager: env.groupManager,
            undoRedoManager: env.undoRedoManager,
            settings: env.settings,
        )

        let bookmark = try env.bookmarksManager.createBookmark(
            url: #require(URL(string: "https://example.com")), title: "Favorite",
        )
        env.bookmarksManager.addToFavorites(bookmark)

        managers.layoutManager.rebuildLayout()

        #expect(managers.layoutManager.favoritesLayout.count == 1)
        #expect(managers.layoutManager.pinnedItems.isEmpty)
        #expect(managers.layoutManager.normalItems.isEmpty)
    }

    @Test
    func `Rebuild partitions pinned and normal items`() throws {
        let support = try SidebarTestSupport()

        _ = try support.createGroup(name: "Pinned Group", isPinned: true)
        _ = try support.createGroup(name: "Pinned", isPinned: true)
        _ = support.createTab(url: "https://normal.com")

        support.rebuildLayout()

        #expect(support.layoutManager.pinnedItems.count == 2)
        #expect(support.layoutManager.normalItems.count == 1)
        #expect(support.layoutManager.pinnedItems.allSatisfy(
            { item in item.isPinned },
        ))
    }

    @Test
    func `Rebuild applies filter only to normal items`() throws {
        let support = try SidebarTestSupport()

        _ = support.createTab(url: "https://match.com")
        _ = support.createTab(url: "https://other.com")
        _ = try support.createGroup(name: "Pinned", isPinned: true)

        support.filterManager.applyQuickFilter(searchText: "match", inTitle: false, inURL: true)
        support.rebuildLayout()

        #expect(support.layoutManager.pinnedItems.count == 1)
        #expect(support.layoutManager.normalItems.count == 1)
        #expect(support.layoutManager.normalItems.first?.tab?.activePage.url.absoluteString.contains("match") == true)
    }

    @Test
    func `Metadata top padding applied only to first normal item when pinned exists`() throws {
        let support = try SidebarTestSupport()

        _ = try support.createGroup(name: "Pinned", isPinned: true)
        _ = support.createTab(url: "https://one.com")
        _ = support.createTab(url: "https://two.com")

        support.rebuildLayout()

        // Use actual ordering from normalItems (prepend insertion means later-created tabs appear first)
        let firstNormalItem = support.layoutManager.normalItems[0]
        let secondNormalItem = support.layoutManager.normalItems[1]

        let firstMetadata = support.layoutManager.metadata[firstNormalItem.id]
        let secondMetadata = support.layoutManager.metadata[secondNormalItem.id]

        #expect(firstMetadata?.topPadding == Constants.Layout.pinnedUnpinnedSpacing)
        #expect(secondMetadata?.topPadding == 0)
    }
}

@Suite("Sidebar.LayoutManager Hierarchy", .tags(.sidebarLayoutManager), .serialized)
@MainActor
struct SidebarLayoutManagerHierarchyTests {
    @Test
    func `Metadata nesting levels reflect group hierarchy`() throws {
        let support = try SidebarTestSupport()

        let rootGroup = try support.createGroup(name: "Root")
        let nestedGroup = try support.createGroup(name: "Nested", parentGroupID: rootGroup.id)

        let rootTab = support.createTab(url: "https://root.com", groupID: rootGroup.id)
        let nestedTab = support.createTab(url: "https://nested.com", groupID: nestedGroup.id)

        support.rebuildLayout()

        #expect(support.layoutManager.metadata[rootGroup.id]?.nestingLevel == 0)
        #expect(support.layoutManager.metadata[nestedGroup.id]?.nestingLevel == 1)
        #expect(support.layoutManager.metadata[rootTab.id]?.nestingLevel == 1)
        #expect(support.layoutManager.metadata[nestedTab.id]?.nestingLevel == 2)
    }

    @Test
    func `Descendants cache includes nested groups and tabs`() throws {
        let support = try SidebarTestSupport()

        let rootGroup = try support.createGroup(name: "Root")
        let nestedGroup = try support.createGroup(name: "Nested", parentGroupID: rootGroup.id)

        let rootTab = support.createTab(url: "https://root.com", groupID: rootGroup.id)
        let nestedTab = support.createTab(url: "https://nested.com", groupID: nestedGroup.id)

        support.rebuildLayout()

        let descendants = support.layoutManager.getAllDescendantIDs(of: rootGroup.id)

        #expect(descendants.contains(rootTab.id))
        #expect(descendants.contains(nestedGroup.id))
        #expect(descendants.contains(nestedTab.id))
    }

    @Test
    func `Group bounds span header and descendants`() throws {
        let support = try SidebarTestSupport()

        let group = try support.createGroup(name: "Group")
        let tab = support.createTab(url: "https://child.com", groupID: group.id)

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let bounds = support.layoutManager.calculateGroupBounds(groupID: group.id)
        let headerFrame = try #require(support.dragCoordinator.computedItemFrame(for: group.id))
        let tabFrame = try #require(support.dragCoordinator.computedItemFrame(for: tab.id))

        #expect(bounds.minY == headerFrame.minY)
        #expect(bounds.maxY == tabFrame.maxY)
    }
}
