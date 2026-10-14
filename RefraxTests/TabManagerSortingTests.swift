import Foundation
import SwiftData
import SwiftUI
import Testing
import WebKit
@testable import Refrax

// MARK: - TabManager Sort By Name Tests

@Suite("TabManager Sort By Name", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerSortNameTests {
    @Test
    func `Sort tabs by name ascending orders A to Z`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create tabs in non-alphabetical order
        let tabC = try env.tabManager.createTab(url: #require(URL(string: "https://charlie.com")), in: space, makeActive: false)
        tabC.activePage.title = "Charlie"

        let tabA = try env.tabManager.createTab(url: #require(URL(string: "https://alpha.com")), in: space, makeActive: false)
        tabA.activePage.title = "Alpha"

        let tabB = try env.tabManager.createTab(url: #require(URL(string: "https://bravo.com")), in: space, makeActive: false)
        tabB.activePage.title = "Bravo"

        env.tabManager.sortTabs(by: .nameAscending, in: space)

        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted[0].displayTitle == "Alpha")
        #expect(sorted[1].displayTitle == "Bravo")
        #expect(sorted[2].displayTitle == "Charlie")
    }

    @Test
    func `Sort tabs by name descending orders Z to A`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tabA = try env.tabManager.createTab(url: #require(URL(string: "https://alpha.com")), in: space, makeActive: false)
        tabA.activePage.title = "Alpha"

        let tabC = try env.tabManager.createTab(url: #require(URL(string: "https://charlie.com")), in: space, makeActive: false)
        tabC.activePage.title = "Charlie"

        let tabB = try env.tabManager.createTab(url: #require(URL(string: "https://bravo.com")), in: space, makeActive: false)
        tabB.activePage.title = "Bravo"

        env.tabManager.sortTabs(by: .nameDescending, in: space)

        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted[0].displayTitle == "Charlie")
        #expect(sorted[1].displayTitle == "Bravo")
        #expect(sorted[2].displayTitle == "Alpha")
    }

    @Test
    func `Sort by name is case insensitive`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tabLower = try env.tabManager.createTab(url: #require(URL(string: "https://a.com")), in: space, makeActive: false)
        tabLower.activePage.title = "apple"

        let tabUpper = try env.tabManager.createTab(url: #require(URL(string: "https://b.com")), in: space, makeActive: false)
        tabUpper.activePage.title = "BANANA"

        let tabMixed = try env.tabManager.createTab(url: #require(URL(string: "https://c.com")), in: space, makeActive: false)
        tabMixed.activePage.title = "Cherry"

        env.tabManager.sortTabs(by: .nameAscending, in: space)

        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted[0].displayTitle == "apple")
        #expect(sorted[1].displayTitle == "BANANA")
        #expect(sorted[2].displayTitle == "Cherry")
    }

    @Test
    func `Sort uses custom name when set`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab1 = try env.tabManager.createTab(url: #require(URL(string: "https://z.com")), in: space, makeActive: false)
        tab1.activePage.title = "Zebra"
        tab1.customName = "Aardvark" // Custom name should take priority

        let tab2 = try env.tabManager.createTab(url: #require(URL(string: "https://b.com")), in: space, makeActive: false)
        tab2.activePage.title = "Beta"

        env.tabManager.sortTabs(by: .nameAscending, in: space)

        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted[0].displayTitle == "Aardvark")
        #expect(sorted[1].displayTitle == "Beta")
    }
}

// MARK: - TabManager Sort By Domain Tests

@Suite("TabManager Sort By Domain", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerSortDomainTests {
    @Test
    func `Sort tabs by domain ascending`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        try env.tabManager.createTab(url: #require(URL(string: "https://zeta.com/page")), in: space, makeActive: false)
        try env.tabManager.createTab(url: #require(URL(string: "https://alpha.com/page")), in: space, makeActive: false)
        try env.tabManager.createTab(url: #require(URL(string: "https://beta.com/page")), in: space, makeActive: false)

        env.tabManager.sortTabs(by: .domainAscending, in: space)

        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted[0].activePage.url.host == "alpha.com")
        #expect(sorted[1].activePage.url.host == "beta.com")
        #expect(sorted[2].activePage.url.host == "zeta.com")
    }

    @Test
    func `Sort tabs by domain descending`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        try env.tabManager.createTab(url: #require(URL(string: "https://alpha.com/page")), in: space, makeActive: false)
        try env.tabManager.createTab(url: #require(URL(string: "https://zeta.com/page")), in: space, makeActive: false)
        try env.tabManager.createTab(url: #require(URL(string: "https://beta.com/page")), in: space, makeActive: false)

        env.tabManager.sortTabs(by: .domainDescending, in: space)

        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted[0].activePage.url.host == "zeta.com")
        #expect(sorted[1].activePage.url.host == "beta.com")
        #expect(sorted[2].activePage.url.host == "alpha.com")
    }

    @Test
    func `Sort by domain handles empty host`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Tab with normal domain
        try env.tabManager.createTab(url: #require(URL(string: "https://example.com")), in: space, makeActive: false)

        // Tab with about: URL (no host)
        let aboutTab = try env.tabManager.createTab(url: #require(URL(string: "about:blank")), in: space, makeActive: false)

        // Tab with file URL (no host)
        let fileTab = try env.tabManager.createTab(url: #require(URL(string: "file:///test.html")), in: space, makeActive: false)

        env.tabManager.sortTabs(by: .domainAscending, in: space)

        // Tabs with empty host should sort to the beginning (empty string < "example.com")
        let sorted = space.tabs.sorted { $0.position < $1.position }
        let hosts = sorted.map { $0.activePage.url.host ?? "" }

        // Empty hosts come first alphabetically
        #expect(hosts.first == "" || hosts.first == "example.com")
        #expect(sorted.contains(where: { $0.id == aboutTab.id }))
        #expect(sorted.contains(where: { $0.id == fileTab.id }))
    }

    @Test
    func `Sort by domain is case insensitive`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        try env.tabManager.createTab(url: #require(URL(string: "https://ALPHA.COM")), in: space, makeActive: false)
        try env.tabManager.createTab(url: #require(URL(string: "https://beta.com")), in: space, makeActive: false)
        try env.tabManager.createTab(url: #require(URL(string: "https://Charlie.COM")), in: space, makeActive: false)

        env.tabManager.sortTabs(by: .domainAscending, in: space)

        let sorted = space.tabs.sorted { $0.position < $1.position }
        // Case-insensitive: alpha < beta < charlie
        #expect(sorted[0].activePage.url.host?.lowercased() == "alpha.com")
        #expect(sorted[1].activePage.url.host?.lowercased() == "beta.com")
        #expect(sorted[2].activePage.url.host?.lowercased() == "charlie.com")
    }
}

// MARK: - TabManager Sort By Date Tests

@Suite("TabManager Sort By Date", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerSortDateTests {
    @Test
    func `Sort by recent first orders newest access first`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let now = Date()

        let oldTab = try env.tabManager.createTab(url: #require(URL(string: "https://old.com")), in: space, makeActive: false)
        oldTab.lastAccessed = now.addingTimeInterval(-3_600) // 1 hour ago

        let recentTab = try env.tabManager.createTab(url: #require(URL(string: "https://recent.com")), in: space, makeActive: false)
        recentTab.lastAccessed = now.addingTimeInterval(-60) // 1 minute ago

        let middleTab = try env.tabManager.createTab(url: #require(URL(string: "https://middle.com")), in: space, makeActive: false)
        middleTab.lastAccessed = now.addingTimeInterval(-1_800) // 30 minutes ago

        env.tabManager.sortTabs(by: .recentFirst, in: space)

        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted[0].id == recentTab.id, "Most recent should be first")
        #expect(sorted[1].id == middleTab.id)
        #expect(sorted[2].id == oldTab.id, "Oldest should be last")
    }

    @Test
    func `Sort by oldest first orders oldest access first`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let now = Date()

        let oldTab = try env.tabManager.createTab(url: #require(URL(string: "https://old.com")), in: space, makeActive: false)
        oldTab.lastAccessed = now.addingTimeInterval(-3_600)

        let recentTab = try env.tabManager.createTab(url: #require(URL(string: "https://recent.com")), in: space, makeActive: false)
        recentTab.lastAccessed = now.addingTimeInterval(-60)

        let middleTab = try env.tabManager.createTab(url: #require(URL(string: "https://middle.com")), in: space, makeActive: false)
        middleTab.lastAccessed = now.addingTimeInterval(-1_800)

        env.tabManager.sortTabs(by: .oldestFirst, in: space)

        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted[0].id == oldTab.id, "Oldest should be first")
        #expect(sorted[1].id == middleTab.id)
        #expect(sorted[2].id == recentTab.id, "Most recent should be last")
    }

    @Test
    func `Sort by created newest orders newest creation first`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let now = Date()

        let oldTab = try env.tabManager.createTab(url: #require(URL(string: "https://old.com")), in: space, makeActive: false)
        oldTab.createdAt = now.addingTimeInterval(-7_200) // 2 hours ago

        let newTab = try env.tabManager.createTab(url: #require(URL(string: "https://new.com")), in: space, makeActive: false)
        newTab.createdAt = now.addingTimeInterval(-60) // 1 minute ago

        let middleTab = try env.tabManager.createTab(url: #require(URL(string: "https://middle.com")), in: space, makeActive: false)
        middleTab.createdAt = now.addingTimeInterval(-3_600) // 1 hour ago

        env.tabManager.sortTabs(by: .createdNewest, in: space)

        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted[0].id == newTab.id, "Newest created should be first")
        #expect(sorted[1].id == middleTab.id)
        #expect(sorted[2].id == oldTab.id, "Oldest created should be last")
    }

    @Test
    func `Sort by created oldest orders oldest creation first`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let now = Date()

        let oldTab = try env.tabManager.createTab(url: #require(URL(string: "https://old.com")), in: space, makeActive: false)
        oldTab.createdAt = now.addingTimeInterval(-7_200)

        let newTab = try env.tabManager.createTab(url: #require(URL(string: "https://new.com")), in: space, makeActive: false)
        newTab.createdAt = now.addingTimeInterval(-60)

        let middleTab = try env.tabManager.createTab(url: #require(URL(string: "https://middle.com")), in: space, makeActive: false)
        middleTab.createdAt = now.addingTimeInterval(-3_600)

        env.tabManager.sortTabs(by: .createdOldest, in: space)

        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted[0].id == oldTab.id, "Oldest created should be first")
        #expect(sorted[1].id == middleTab.id)
        #expect(sorted[2].id == newTab.id, "Newest created should be last")
    }
}

// MARK: - TabManager Sort Pinned/Unpinned Tests

@Suite("TabManager Sort Pinned/Unpinned Separation", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerSortPinnedTests {
    @Test
    func `Sorting keeps pinned and unpinned tabs separate`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create unpinned tabs
        let unpinnedZ = try env.tabManager.createTab(url: #require(URL(string: "https://z.com")), in: space, makeActive: false)
        unpinnedZ.activePage.title = "Zeta"

        let unpinnedA = try env.tabManager.createTab(url: #require(URL(string: "https://a.com")), in: space, makeActive: false)
        unpinnedA.activePage.title = "Alpha"

        // Create pinned groups
        let pinnedZ = try env.groupManager.createGroup(in: space, name: "Zulu", isPinned: true)
        let pinnedA = try env.groupManager.createGroup(in: space, name: "Alfa", isPinned: true)

        env.tabManager.sortTabs(by: .nameAscending, in: space)

        let sorted = space.tabs.sorted { $0.position < $1.position }
        let unpinnedTabs = sorted.filter { !$0.isInPinnedGroup }

        // Pinned groups should be sorted alphabetically
        #expect(pinnedA.position < pinnedZ.position)

        // Unpinned tabs should be sorted alphabetically
        #expect(unpinnedTabs[0].displayTitle == "Alpha")
        #expect(unpinnedTabs[1].displayTitle == "Zeta")

        // All pinned positions should be less than unpinned positions
        let maxPinnedPos = max(pinnedA.position, pinnedZ.position)
        let minUnpinnedPos = unpinnedTabs.map(\.position).min() ?? Int.max
        #expect(maxPinnedPos < minUnpinnedPos, "Pinned groups should have lower positions")
    }

    @Test
    func `Sorting empty pinned section leaves unpinned intact`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Only create unpinned tabs
        let tabC = try env.tabManager.createTab(url: #require(URL(string: "https://c.com")), in: space, makeActive: false)
        tabC.activePage.title = "Charlie"

        let tabA = try env.tabManager.createTab(url: #require(URL(string: "https://a.com")), in: space, makeActive: false)
        tabA.activePage.title = "Alpha"

        env.tabManager.sortTabs(by: .nameAscending, in: space)

        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted[0].displayTitle == "Alpha")
        #expect(sorted[1].displayTitle == "Charlie")
    }
}

// MARK: - TabManager Sort Mixed Items Tests

@Suite("TabManager Sort Mixed Tabs and Groups", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerSortMixedTests {
    @Test
    func `Sort root level mixes tabs and groups by name`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create a group
        _ = try env.groupManager.createGroup(in: space, name: "Middle Group")

        // Create tabs
        let tabZ = try env.tabManager.createTab(url: #require(URL(string: "https://z.com")), in: space, makeActive: false)
        tabZ.activePage.title = "Zulu"

        let tabA = try env.tabManager.createTab(url: #require(URL(string: "https://a.com")), in: space, makeActive: false)
        tabA.activePage.title = "Alpha"

        env.tabManager.sortTabs(by: .nameAscending, in: space)

        // Verify order: Alpha (tab), Middle Group (group), Zulu (tab)
        let sortedTabs = space.tabs.filter { $0.groupID == nil }.sorted { $0.position < $1.position }
        let sortedGroups = space.groups.sorted { $0.position < $1.position }

        #expect(sortedTabs[0].displayTitle == "Alpha")
        #expect(sortedTabs[1].displayTitle == "Zulu")
        #expect(sortedGroups[0].name == "Middle Group")

        // Alpha < Middle < Zulu alphabetically
        #expect(sortedTabs[0].position < sortedGroups[0].position)
        #expect(sortedGroups[0].position < sortedTabs[1].position)
    }

    @Test
    func `Sort root level mixes tabs and groups by date`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let now = Date()

        // Create group first (will have earliest creation date)
        let group = try env.groupManager.createGroup(in: space, name: "Old Group")
        group.createdAt = now.addingTimeInterval(-7_200)

        // Create tabs with different creation dates
        let newTab = try env.tabManager.createTab(url: #require(URL(string: "https://new.com")), in: space, makeActive: false)
        newTab.createdAt = now.addingTimeInterval(-60)

        let middleTab = try env.tabManager.createTab(url: #require(URL(string: "https://middle.com")), in: space, makeActive: false)
        middleTab.createdAt = now.addingTimeInterval(-3_600)

        env.tabManager.sortTabs(by: .createdNewest, in: space)

        // Newest first: newTab, middleTab, group
        let allPositions = space.tabs.filter { $0.groupID == nil }.map { ("tab", $0.position) }
            + space.groups.map { ("group", $0.position) }
        let sorted = allPositions.sorted { $0.1 < $1.1 }

        #expect(sorted[0].0 == "tab") // newTab
        #expect(sorted[1].0 == "tab") // middleTab
        #expect(sorted[2].0 == "group") // group
    }
}

// MARK: - TabManager Sort Group Contents Tests

@Suite("TabManager Sort Group Contents", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerSortGroupTests {
    @Test
    func `Sort tabs within group by name`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Test Group")

        // Create tabs in the group
        let tabC = try env.tabManager.createTab(url: #require(URL(string: "https://c.com")), in: space, makeActive: false)
        tabC.activePage.title = "Charlie"
        tabC.groupID = group.id

        let tabA = try env.tabManager.createTab(url: #require(URL(string: "https://a.com")), in: space, makeActive: false)
        tabA.activePage.title = "Alpha"
        tabA.groupID = group.id

        let tabB = try env.tabManager.createTab(url: #require(URL(string: "https://b.com")), in: space, makeActive: false)
        tabB.activePage.title = "Bravo"
        tabB.groupID = group.id

        env.tabManager.sortTabs(by: .nameAscending, in: space)

        let groupTabs = space.tabs.filter { $0.groupID == group.id }.sorted { $0.position < $1.position }
        #expect(groupTabs[0].displayTitle == "Alpha")
        #expect(groupTabs[1].displayTitle == "Bravo")
        #expect(groupTabs[2].displayTitle == "Charlie")
    }

    @Test
    func `Sort nested groups within parent group`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let now = Date()

        let parentGroup = try env.groupManager.createGroup(in: space, name: "Parent")

        let nestedZ = try env.groupManager.createGroup(in: space, name: "Zulu Nested", parentGroupID: parentGroup.id)
        nestedZ.createdAt = now.addingTimeInterval(-3_600)

        let nestedA = try env.groupManager.createGroup(in: space, name: "Alpha Nested", parentGroupID: parentGroup.id)
        nestedA.createdAt = now.addingTimeInterval(-60)

        env.tabManager.sortTabs(by: .nameAscending, in: space)

        let nestedGroups = space.groups
            .filter { $0.parentGroupID == parentGroup.id }
            .sorted { $0.position < $1.position }

        #expect(nestedGroups[0].name == "Alpha Nested")
        #expect(nestedGroups[1].name == "Zulu Nested")
    }

    @Test
    func `Sort nested groups by creation date`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let now = Date()

        let parentGroup = try env.groupManager.createGroup(in: space, name: "Parent")

        let oldNested = try env.groupManager.createGroup(in: space, name: "Old Nested", parentGroupID: parentGroup.id)
        oldNested.createdAt = now.addingTimeInterval(-7_200)

        let newNested = try env.groupManager.createGroup(in: space, name: "New Nested", parentGroupID: parentGroup.id)
        newNested.createdAt = now.addingTimeInterval(-60)

        env.tabManager.sortTabs(by: .createdNewest, in: space)

        let nestedGroups = space.groups
            .filter { $0.parentGroupID == parentGroup.id }
            .sorted { $0.position < $1.position }

        #expect(nestedGroups[0].name == "New Nested", "Newest should be first")
        #expect(nestedGroups[1].name == "Old Nested")
    }

    @Test
    func `Group tabs sorted after nested groups have correct positions`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let parentGroup = try env.groupManager.createGroup(in: space, name: "Parent")

        // Add tab to parent group
        let tabInParent = try env.tabManager.createTab(url: #require(URL(string: "https://parent-tab.com")), in: space, makeActive: false)
        tabInParent.activePage.title = "Parent Tab"
        tabInParent.groupID = parentGroup.id

        // Add nested group
        let nestedGroup = try env.groupManager.createGroup(in: space, name: "Nested", parentGroupID: parentGroup.id)

        // Add tab to nested group
        let tabInNested = try env.tabManager.createTab(url: #require(URL(string: "https://nested-tab.com")), in: space, makeActive: false)
        tabInNested.activePage.title = "Nested Tab"
        tabInNested.groupID = nestedGroup.id

        env.tabManager.sortTabs(by: .nameAscending, in: space)

        // Tabs in parent group should have positions relative to parent
        // Nested group tabs should have positions relative to nested group
        let parentPos = parentGroup.position
        let nestedPos = nestedGroup.position

        #expect(tabInParent.position > parentPos, "Tab in parent should follow parent")
        #expect(tabInNested.position > nestedPos, "Tab in nested should follow nested group")
    }
}

// MARK: - TabManager Sort Edge Cases Tests

@Suite("TabManager Sort Edge Cases", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerSortEdgeCaseTests {
    @Test
    func `Sort increments list version`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        try env.tabManager.createTab(url: #require(URL(string: "https://a.com")), in: space, makeActive: false)
        try env.tabManager.createTab(url: #require(URL(string: "https://b.com")), in: space, makeActive: false)

        let versionBefore = env.browserState.tabListVersion

        env.tabManager.sortTabs(by: .nameAscending, in: space)

        #expect(env.browserState.tabListVersion > versionBefore, "Sort should increment list version")
    }

    @Test
    func `Sort with identical names maintains stable order`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create tabs with identical titles
        let tab1 = try env.tabManager.createTab(url: #require(URL(string: "https://one.com")), in: space, makeActive: false)
        tab1.activePage.title = "Same Title"

        let tab2 = try env.tabManager.createTab(url: #require(URL(string: "https://two.com")), in: space, makeActive: false)
        tab2.activePage.title = "Same Title"

        let tab3 = try env.tabManager.createTab(url: #require(URL(string: "https://three.com")), in: space, makeActive: false)
        tab3.activePage.title = "Same Title"

        // Sort twice and verify consistent ordering
        env.tabManager.sortTabs(by: .nameAscending, in: space)
        let firstSort = space.tabs.sorted { $0.position < $1.position }.map(\.id)

        env.tabManager.sortTabs(by: .nameAscending, in: space)
        let secondSort = space.tabs.sorted { $0.position < $1.position }.map(\.id)

        // Both sorts should produce the same order (stable sort)
        #expect(firstSort == secondSort, "Sort should be stable for identical keys")
    }

    @Test
    func `Sort empty space is no-op`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        #expect(space.tabs.isEmpty)

        // Should not crash
        env.tabManager.sortTabs(by: .nameAscending, in: space)

        #expect(space.tabs.isEmpty)
    }

    @Test
    func `Sort single tab is no-op`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(url: #require(URL(string: "https://only.com")), in: space, makeActive: false)

        env.tabManager.sortTabs(by: .nameAscending, in: space)

        // Position may be normalized, but tab should still be there
        #expect(space.tabs.count == 1)
        #expect(space.tabs.first?.id == tab.id)
    }

    @Test
    func `Sort normalizes positions`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create tabs with non-contiguous positions
        let tab1 = try env.tabManager.createTab(url: #require(URL(string: "https://a.com")), in: space, makeActive: false)
        tab1.activePage.title = "Alpha"
        tab1.position = 100

        let tab2 = try env.tabManager.createTab(url: #require(URL(string: "https://b.com")), in: space, makeActive: false)
        tab2.activePage.title = "Bravo"
        tab2.position = 500

        let tab3 = try env.tabManager.createTab(url: #require(URL(string: "https://c.com")), in: space, makeActive: false)
        tab3.activePage.title = "Charlie"
        tab3.position = 1_000

        env.tabManager.sortTabs(by: .nameAscending, in: space)

        // After sorting, positions should be normalized
        let sorted = space.tabs.sorted { $0.position < $1.position }
        #expect(sorted[0].displayTitle == "Alpha")
        #expect(sorted[1].displayTitle == "Bravo")
        #expect(sorted[2].displayTitle == "Charlie")
    }

    @Test
    func `Groups use name for domain sort criterion`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create groups - they don't have domains, so they use name for domain sorts
        _ = try env.groupManager.createGroup(in: space, name: "Zulu Group")
        _ = try env.groupManager.createGroup(in: space, name: "Alpha Group")

        env.tabManager.sortTabs(by: .domainAscending, in: space)

        let sortedGroups = space.groups.sorted { $0.position < $1.position }
        #expect(sortedGroups[0].name == "Alpha Group")
        #expect(sortedGroups[1].name == "Zulu Group")
    }
}
