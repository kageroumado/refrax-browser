import Foundation
import Testing

@testable import Refrax

@Suite("Sidebar.TabSelectionManager Integration", .tags(.sidebarTabSelectionManager), .serialized)
@MainActor
struct SidebarTabSelectionManagerIntegrationTests {
    @Test("Command click toggles selection")
    func commandClickTogglesSelection() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://example.com")

        support.rebuildLayout()

        let shouldActivate = support.selectionManager.handleClick(
            on: tab,
            commandDown: true,
            shiftDown: false,
        )

        #expect(shouldActivate == false)
        #expect(support.selectionManager.isSelected(tab))

        _ = support.selectionManager.handleClick(
            on: tab,
            commandDown: true,
            shiftDown: false,
        )

        #expect(!support.selectionManager.isSelected(tab))
    }

    @Test("Shift click selects range from anchor")
    func shiftClickSelectsRange() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://one.com")
        let tab2 = support.createTab(url: "https://two.com")
        let tab3 = support.createTab(url: "https://three.com")

        support.rebuildLayout()

        _ = support.selectionManager.handleClick(
            on: tab1,
            commandDown: true,
            shiftDown: false,
        )

        _ = support.selectionManager.handleClick(
            on: tab3,
            commandDown: false,
            shiftDown: true,
        )

        #expect(support.selectionManager.isSelected(tab1))
        #expect(support.selectionManager.isSelected(tab2))
        #expect(support.selectionManager.isSelected(tab3))
    }

    @Test("Regular click clears selection and activates tab")
    func regularClickClearsSelection() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://one.com")
        let tab2 = support.createTab(url: "https://two.com")

        support.rebuildLayout()

        _ = support.selectionManager.handleClick(
            on: tab2,
            commandDown: true,
            shiftDown: false,
        )

        let shouldActivate = support.selectionManager.handleClick(
            on: tab1,
            commandDown: false,
            shiftDown: false,
        )

        #expect(shouldActivate)
        #expect(!support.selectionManager.hasSelection)
    }

    @Test("Selected tabs include active tab")
    func selectedTabsIncludeActive() throws {
        let support = try SidebarTestSupport()
        let tab = support.env.createActiveTab(
            url: URL(string: "https://example.com")!,
            in: support.space,
            for: support.windowState,
        )

        support.rebuildLayout()

        let selected = support.selectionManager.selectedTabsIncludingActive
        #expect(selected.contains { $0.id == tab.id })
    }

    @Test("Select all and invert selection")
    func selectAllAndInvertSelection() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://one.com")
        let tab2 = support.createTab(url: "https://two.com")

        support.rebuildLayout()

        support.selectionManager.selectAll()
        #expect(support.selectionManager.isSelected(tab1))
        #expect(support.selectionManager.isSelected(tab2))

        support.selectionManager.invertSelection()
        #expect(!support.selectionManager.isSelected(tab1))
        #expect(!support.selectionManager.isSelected(tab2))
    }
}
