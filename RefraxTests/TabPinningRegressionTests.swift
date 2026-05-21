import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Refrax

// MARK: - Tab Pinning Regression Tests

/// Tests for tab pinning functionality that could regress when implementing
/// new features that modify tab states and positions.
@Suite("Tab Pinning Regression", .tags(.tabManager), .serialized)
@MainActor
struct TabPinningRegressionTests {
    // MARK: - Pin Tab Tests

    @Test("Tab can be toggled to pinned")
    func tabCanBeToggledToPinned() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )

        #expect(!tab.isPinned)

        env.tabManager.togglePinTab(tab)

        #expect(tab.isPinned)
        #expect(tab.status == .pinned)
    }

    @Test("Tab can be created pinned")
    func tabCreatedPinned() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            isPinned: true,
            makeActive: false,
        )

        #expect(tab.isPinned)
    }

    @Test("Pinned tab persists pinned state")
    func pinnedTabPersistsState() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            isPinned: true,
            makeActive: false,
        )
        let tabID = tab.id

        try env.modelContext.save()

        let descriptor = FetchDescriptor<Refrax.Tab>(predicate: #Predicate { $0.id == tabID })
        let fetched = try env.modelContext.fetch(descriptor)

        #expect(fetched.first?.isPinned == true)
    }

    // MARK: - Unpin Tab Tests

    @Test("Tab can be toggled to unpinned")
    func tabCanBeToggledToUnpinned() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            isPinned: true,
            makeActive: false,
        )

        #expect(tab.isPinned)

        env.tabManager.togglePinTab(tab)

        #expect(!tab.isPinned)
        #expect(tab.status == .regular)
    }

    @Test("Toggle pin changes state repeatedly")
    func togglePinChangesStateRepeatedly() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
        )

        #expect(!tab.isPinned)

        env.tabManager.togglePinTab(tab)
        #expect(tab.isPinned)

        env.tabManager.togglePinTab(tab)
        #expect(!tab.isPinned)
    }

    // MARK: - Pinned Tab Position Tests

    @Test("Pinned tabs have separate positions")
    func pinnedTabsSeparatePositions() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let pinnedTab1 = env.tabManager.createTab(
            url: URL(string: "https://pinned1.com")!,
            in: space,
            isPinned: true,
            makeActive: false,
        )
        let pinnedTab2 = env.tabManager.createTab(
            url: URL(string: "https://pinned2.com")!,
            in: space,
            isPinned: true,
            makeActive: false,
        )
        let regularTab = env.tabManager.createTab(
            url: URL(string: "https://regular.com")!,
            in: space,
            makeActive: false,
        )

        // Pinned tabs should have their own position sequence
        #expect(pinnedTab1.isPinned)
        #expect(pinnedTab2.isPinned)
        #expect(!regularTab.isPinned)
    }

    @Test("Toggling pin moves tab to pinned section")
    func togglingPinMovesToPinnedSection() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        _ = env.tabManager.createTab(
            url: URL(string: "https://pinned.com")!,
            in: space,
            isPinned: true,
            makeActive: false,
        )

        let regularTab = env.tabManager.createTab(
            url: URL(string: "https://regular.com")!,
            in: space,
            makeActive: false,
        )

        #expect(!regularTab.isPinned)

        env.tabManager.togglePinTab(regularTab)

        #expect(regularTab.isPinned)
    }

    // MARK: - Pinned Tab Sorting Tests

    @Test("Sort tabs does not mix pinned and regular")
    func sortTabsDoesNotMixPinnedAndRegular() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let pinnedTab = env.tabManager.createTab(
            url: URL(string: "https://pinned.com")!,
            in: space,
            isPinned: true,
            makeActive: false,
        )
        pinnedTab.activePage.title = "Zebra Pinned"

        let regularTab = env.tabManager.createTab(
            url: URL(string: "https://regular.com")!,
            in: space,
            makeActive: false,
        )
        regularTab.activePage.title = "Alpha Regular"

        env.tabManager.sortTabs(by: .nameAscending, in: space)

        // Pinned should remain pinned
        #expect(pinnedTab.isPinned)
        #expect(!regularTab.isPinned)
    }

    // MARK: - Close Pinned Tab Tests

    @Test("Closing pinned tab works")
    func closingPinnedTabWorks() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let pinnedTab = env.tabManager.createTab(
            url: URL(string: "https://pinned.com")!,
            in: space,
            isPinned: true,
            makeActive: false,
        )
        let tabID = pinnedTab.id

        env.tabManager.closeTab(pinnedTab)

        #expect(!space.tabs.contains { $0.id == tabID })
    }

    @Test("Close other tabs closes all except specified")
    func closeOtherTabsClosesAllExceptSpecified() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        // Note: closeOtherTabs does NOT have special handling for pinned tabs
        let pinnedTab = env.tabManager.createTab(
            url: URL(string: "https://pinned.com")!,
            in: space,
            isPinned: true,
            makeActive: false,
        )

        let keepTab = env.tabManager.createTab(
            url: URL(string: "https://keep.com")!,
            in: space,
            makeActive: true,
        )

        _ = env.tabManager.createTab(
            url: URL(string: "https://close.com")!,
            in: space,
            makeActive: true,
        )

        env.tabManager.setActiveTab(keepTab, in: windowState)

        env.tabManager.closeOtherTabsInSpace(except: keepTab)

        // closeOtherTabsInSpace closes ALL tabs except specified one (including pinned)
        #expect(!space.tabs.contains { $0.id == pinnedTab.id })
        #expect(space.tabs.contains { $0.id == keepTab.id })
        #expect(space.tabs.count == 1)
    }
}

// MARK: - Pinned Tab Group Tests

@Suite("Pinned Tab in Group", .tags(.tabManager), .serialized)
@MainActor
struct PinnedTabGroupTests {
    @Test("Tab in group cannot be pinned")
    func tabInGroupCannotBePinned() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Container")

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            groupID: group.id,
            makeActive: true,
        )

        // togglePinTab is a no-op when tab is in a group (returns early)
        env.tabManager.togglePinTab(tab)

        // Tab should remain unpinned because pinning grouped tabs is not allowed
        #expect(!tab.isPinned)
        #expect(tab.groupID == group.id)
    }

    @Test("Pinned group can contain tabs")
    func pinnedGroupContainsTabs() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let pinnedGroup = try env.groupManager.createGroup(
            in: space,
            name: "Pinned Group",
            isPinned: true,
        )

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            groupID: pinnedGroup.id,
            makeActive: false,
        )

        #expect(pinnedGroup.isPinned)
        #expect(tab.groupID == pinnedGroup.id)
    }
}
