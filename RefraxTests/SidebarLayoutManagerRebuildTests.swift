import Foundation
import Testing

@testable import Refrax

@Suite("Sidebar.LayoutManager Rebuild", .tags(.sidebarLayoutManager), .serialized)
@MainActor
struct SidebarLayoutManagerRebuildTests {
    @Test("Rebuild keeps favorites when no active space")
    func rebuildKeepsFavoritesWithoutSpace() throws {
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

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!, title: "Favorite",
        )
        env.bookmarksManager.addToFavorites(bookmark)

        managers.layoutManager.rebuildLayout()

        #expect(managers.layoutManager.favoritesLayout.count == 1)
        #expect(managers.layoutManager.pinnedItems.isEmpty)
        #expect(managers.layoutManager.normalItems.isEmpty)
    }

    @Test("Rebuild partitions pinned and normal items")
    func rebuildPartitionsPinnedAndNormal() throws {
        let support = try SidebarTestSupport()

        _ = try support.createGroup(name: "Pinned Group", isPinned: true)
        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://normal.com", isPinned: false)

        support.rebuildLayout()

        #expect(support.layoutManager.pinnedItems.count == 2)
        #expect(support.layoutManager.normalItems.count == 1)
        #expect(support.layoutManager.pinnedItems.allSatisfy(
            { item in item.isPinned },
        ))
    }

    @Test("Rebuild applies filter only to normal items")
    func rebuildAppliesFilterToNormal() throws {
        let support = try SidebarTestSupport()

        _ = support.createTab(url: "https://match.com", isPinned: false)
        _ = support.createTab(url: "https://other.com", isPinned: false)
        _ = support.createTab(url: "https://pinned.com", isPinned: true)

        support.filterManager.applyQuickFilter(searchText: "match", inTitle: false, inURL: true)
        support.rebuildLayout()

        #expect(support.layoutManager.pinnedItems.count == 1)
        #expect(support.layoutManager.normalItems.count == 1)
        #expect(support.layoutManager.normalItems.first?.tab?.activePage.url.absoluteString.contains("match") == true)
    }

    @Test("Metadata top padding applied only to first normal item when pinned exists")
    func metadataTopPaddingForFirstNormalItem() throws {
        let support = try SidebarTestSupport()

        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://one.com", isPinned: false)
        _ = support.createTab(url: "https://two.com", isPinned: false)

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
    @Test("Metadata nesting levels reflect group hierarchy")
    func metadataNestingLevels() throws {
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

    @Test("Descendants cache includes nested groups and tabs")
    func descendantsCacheIncludesNestedItems() throws {
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

    @Test("Group bounds span header and descendants")
    func groupBoundsSpanHeaderAndDescendants() throws {
        let support = try SidebarTestSupport()

        let group = try support.createGroup(name: "Group")
        let tab = support.createTab(url: "https://child.com", groupID: group.id)

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let bounds = support.layoutManager.calculateGroupBounds(groupID: group.id)
        let headerFrame = support.dragCoordinator.computedItemFrame(for: group.id)!
        let tabFrame = support.dragCoordinator.computedItemFrame(for: tab.id)!

        #expect(bounds.minY == headerFrame.minY)
        #expect(bounds.maxY == tabFrame.maxY)
    }
}
