import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Refrax

// MARK: - TabGroup Regression Tests

/// Tests for TabGroup functionality that could regress when implementing
/// nested groups (2.9), tab templates (2.10), and related features.
@Suite("TabGroup Regression", .tags(.tabManager), .serialized)
@MainActor
struct TabGroupRegressionTests {
    // MARK: - Group Creation Tests

    @Test("Create group in space")
    func createGroupInSpace() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Test Group")

        #expect(group.name == "Test Group")
        #expect(group.space?.id == space.id)
    }

    @Test("Group has unique ID")
    func groupHasUniqueID() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group1 = try env.groupManager.createGroup(in: space, name: "Group 1")
        let group2 = try env.groupManager.createGroup(in: space, name: "Group 2")

        #expect(group1.id != group2.id)
    }

    @Test("Group persists to database")
    func groupPersistsToDatabase() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Persistent")
        let groupID = group.id

        try env.modelContext.save()

        let descriptor = FetchDescriptor<TabGroup>(predicate: #Predicate { $0.id == groupID })
        let fetched = try env.modelContext.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched.first?.name == "Persistent")
    }

    // MARK: - Group Pinning Tests

    @Test("Group can be created pinned")
    func groupCreatedPinned() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Pinned", isPinned: true)

        #expect(group.isPinned)
    }

    @Test("Group can be pinned after creation")
    func groupPinnedAfterCreation() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Unpinned")
        #expect(!group.isPinned)

        group.isPinned = true
        #expect(group.isPinned)
    }

    @Test("Pinned groups sorted separately")
    func pinnedGroupsSortedSeparately() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        _ = try env.groupManager.createGroup(in: space, name: "Normal")
        let pinnedGroup = try env.groupManager.createGroup(in: space, name: "Pinned", isPinned: true)

        let pinnedGroups = space.groups.filter(\.isPinned)
        let allGroups = space.groups

        #expect(pinnedGroups.count == 1)
        #expect(pinnedGroups.first?.id == pinnedGroup.id)
        #expect(allGroups.count == 2)
    }

    // MARK: - Tab Group Membership Tests

    @Test("Tab can be added to group")
    func tabAddedToGroup() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Container")

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            groupID: group.id,
            makeActive: false,
        )

        #expect(tab.groupID == group.id)
    }

    @Test("Group tabs returns group members")
    func groupTabsReturnsMembers() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Container")

        let tab1 = env.tabManager.createTab(
            url: URL(string: "https://one.com")!,
            in: space,
            groupID: group.id,
            makeActive: false,
        )
        let tab2 = env.tabManager.createTab(
            url: URL(string: "https://two.com")!,
            in: space,
            groupID: group.id,
            makeActive: false,
        )

        #expect(group.tabs.count == 2)
        #expect(group.tabs.contains { $0.id == tab1.id })
        #expect(group.tabs.contains { $0.id == tab2.id })
    }

    @Test("Tab removed from group clears groupID")
    func tabRemovedFromGroup() throws {
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

        // Use tab.group = nil to properly update the relationship
        // (tab.groupID = nil doesn't update the @Relationship)
        tab.group = nil

        #expect(tab.group == nil)
        #expect(!group.tabs.contains { $0.id == tab.id })
    }

    // MARK: - Group Collapse State Tests

    @Test("Group isCollapsed starts false")
    func groupIsCollapsedStartsFalse() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Expandable")

        #expect(!group.isCollapsed)
    }

    @Test("Group isCollapsed can be toggled")
    func groupIsCollapsedToggled() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Collapsible")

        group.isCollapsed = true
        #expect(group.isCollapsed)

        group.isCollapsed = false
        #expect(!group.isCollapsed)
    }

    @Test("Group collapse state persists")
    func groupCollapseStatePersists() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Collapsible")
        group.isCollapsed = true
        let groupID = group.id

        try env.modelContext.save()

        let descriptor = FetchDescriptor<TabGroup>(predicate: #Predicate { $0.id == groupID })
        let fetched = try env.modelContext.fetch(descriptor)

        #expect(fetched.first?.isCollapsed == true)
    }

    // MARK: - Group Position Tests

    @Test("Groups have distinct positions")
    func groupsHaveDistinctPositions() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group1 = try env.groupManager.createGroup(in: space, name: "First")
        let group2 = try env.groupManager.createGroup(in: space, name: "Second")
        let group3 = try env.groupManager.createGroup(in: space, name: "Third")

        // Positions use fractional indexing - test that they are all distinct
        let positions = Set([group1.position, group2.position, group3.position])
        #expect(positions.count == 3)
    }

    // MARK: - Group Rename Tests

    @Test("Group can be renamed")
    func groupCanBeRenamed() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Original")

        env.groupManager.renameGroup(group, to: "Renamed")

        #expect(group.name == "Renamed")
    }

    @Test("Group rename persists")
    func groupRenamePersists() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Original")
        env.groupManager.renameGroup(group, to: "New Name")
        let groupID = group.id

        try env.modelContext.save()

        let descriptor = FetchDescriptor<TabGroup>(predicate: #Predicate { $0.id == groupID })
        let fetched = try env.modelContext.fetch(descriptor)

        #expect(fetched.first?.name == "New Name")
    }

    // MARK: - Group Deletion Tests

    @Test("Group can be deleted")
    func groupDeleted() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "ToDelete")
        let groupID = group.id

        env.groupManager.deleteGroup(group)

        try env.modelContext.save()

        let descriptor = FetchDescriptor<TabGroup>(predicate: #Predicate { $0.id == groupID })
        let fetched = try env.modelContext.fetch(descriptor)

        #expect(fetched.isEmpty)
    }

    @Test("Deleting group ungroups tabs")
    func deletingGroupUngroupsTabs() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Container")

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            groupID: group.id,
            makeActive: false,
        )

        env.groupManager.deleteGroup(group)

        // Tab should be ungrouped but still exist
        #expect(tab.groupID == nil)
        #expect(space.tabs.contains { $0.id == tab.id })
    }

    @Test("Deleting group with closeTabs option closes tabs")
    func deletingGroupCloseTabs() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Container")

        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            groupID: group.id,
            makeActive: false,
        )
        let tabID = tab.id

        env.groupManager.deleteGroup(group, deleteContainedTabs: true)

        #expect(!space.tabs.contains { $0.id == tabID })
    }
}

// MARK: - Nested Group Tests

@Suite("Nested TabGroup", .tags(.tabManager), .serialized)
@MainActor
struct NestedTabGroupTests {
    @Test("Group can have parent group")
    func groupCanHaveParent() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let parentGroup = try env.groupManager.createGroup(in: space, name: "Parent")
        let childGroup = try env.groupManager.createGroup(
            in: space,
            name: "Child",
            parentGroupID: parentGroup.id,
        )

        #expect(childGroup.parentGroupID == parentGroup.id)
    }

    @Test("Root group has nil parentGroupID")
    func rootGroupNilParent() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Root")

        #expect(group.parentGroupID == nil)
    }

    @Test("Child groups persist parent relationship")
    func childGroupsPersistParent() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let parentGroup = try env.groupManager.createGroup(in: space, name: "Parent")
        let childGroup = try env.groupManager.createGroup(
            in: space,
            name: "Child",
            parentGroupID: parentGroup.id,
        )
        let childID = childGroup.id

        try env.modelContext.save()

        let descriptor = FetchDescriptor<TabGroup>(predicate: #Predicate { $0.id == childID })
        let fetched = try env.modelContext.fetch(descriptor)

        #expect(fetched.first?.parentGroupID == parentGroup.id)
    }
}
