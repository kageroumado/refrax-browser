import Foundation
import Testing

@testable import Refrax

@Suite("Sidebar.FilterManager Integration", .tags(.sidebarFilterManager), .serialized)
@MainActor
struct SidebarFilterManagerIntegrationTests {
    @Test("Text search filters by title and URL")
    func textSearchFiltersByTitleAndURL() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://apple.com")
        let tab2 = support.createTab(url: "https://example.com")

        tab1.activePage.title = "Apple"
        tab2.activePage.title = "Example"

        support.rebuildLayout()
        support.filterManager.applyQuickFilter(searchText: "apple", inTitle: true, inURL: false)

        let items = support.layoutManager.normalItems
        let filtered = support.filterManager.filterItems(items)
        let filteredIDs = Set(filtered.compactMap { $0.tab?.id })

        #expect(filteredIDs.contains(tab1.id))
        #expect(!filteredIDs.contains(tab2.id))
    }

    @Test("Unread quick filter selects unread tabs")
    func unreadQuickFilterSelectsUnread() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://one.com")
        let tab2 = support.createTab(url: "https://two.com")

        tab1.isUnread = true
        tab2.isUnread = false

        support.rebuildLayout()
        support.filterManager.setQuickFilter(.unread)

        let items = support.layoutManager.normalItems
        let filtered = support.filterManager.filterItems(items)
        let filteredIDs = Set(filtered.compactMap { $0.tab?.id })

        #expect(filteredIDs.contains(tab1.id))
        #expect(!filteredIDs.contains(tab2.id))
    }

    @Test("Saved filter applies search text and flags")
    func savedFilterAppliesQuery() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://match.com")
        let tab2 = support.createTab(url: "https://other.com")

        tab1.activePage.title = "Match"
        tab2.activePage.title = "Other"

        let saved = SavedFilter(
            name: "Match",
            searchText: "match",
            searchInTitle: true,
            searchInURL: false,
        )

        support.rebuildLayout()
        support.filterManager.applySavedFilter(saved)

        let items = support.layoutManager.normalItems
        let filtered = support.filterManager.filterItems(items)
        let filteredIDs = Set(filtered.compactMap { $0.tab?.id })

        #expect(filteredIDs.contains(tab1.id))
        #expect(!filteredIDs.contains(tab2.id))
    }

    @Test("Groups with matching descendants remain visible")
    func groupsWithMatchingDescendantsRemainVisible() throws {
        let support = try SidebarTestSupport()
        let parent = try support.createGroup(name: "Parent")
        let child = try support.createGroup(name: "Child", parentGroupID: parent.id)

        let tab = support.createTab(url: "https://match.com", groupID: child.id)
        tab.activePage.title = "Match"

        support.rebuildLayout()
        support.filterManager.applyQuickFilter(searchText: "match", inTitle: true, inURL: false)

        let items = support.layoutManager.normalItems
        let filtered = support.filterManager.filterItems(items)
        let filteredIDs = Set(filtered.map(
            \.id,
        ))

        #expect(filteredIDs.contains(parent.id))
        #expect(filteredIDs.contains(child.id))
        #expect(filteredIDs.contains(tab.id))
    }

    @Test("Audible filter ignores tabs without page lookup")
    func audibleFilterRequiresPageLookup() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://one.com")

        support.rebuildLayout()
        support.filterManager.pageLookup = { _ in nil }
        support.filterManager.setQuickFilter(.audible)

        let items = support.layoutManager.normalItems
        let filtered = support.filterManager.filterItems(items)

        #expect(filtered.isEmpty)
    }
}
