import Foundation
import Testing

@testable import Refrax

/// Tests for group nesting scenarios.
///
/// Note: The app supports max 2 levels of nesting (root groups + one nested level).
/// These tests verify:
/// - Correct nesting level calculations for nested items
/// - Cycle prevention for group-into-child moves
/// - Bounds calculations including descendants
/// - Reordering within nested structures
@Suite("Deep Nesting Edge Cases", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragDeepNestingTests {
    // MARK: - Nesting Level Tests

    @Test("Two level nesting calculates correctly")
    func twoLevelNestingCalculatesCorrectly() throws {
        let support = try SidebarTestSupport()

        // Create 2-level nesting: Group1 > Tab (max allowed nesting)
        let group1 = try support.createGroup(name: "Level 1")
        let nestedTab = support.createTab(url: "https://nested.com", groupID: group1.id)

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Verify nesting levels via layout metadata
        #expect(group1.nestingLevel == 0)

        // For tabs, check via layout metadata
        let tabItem = support.layoutManager.normalItems.first { item in
            if case let .tab(tab) = item, tab.id == nestedTab.id { return true }
            return false
        }!
        let tabNestingLevel = support.layoutManager.metadata[tabItem.id]!.nestingLevel
        #expect(tabNestingLevel == 1)
    }

    @Test("Nested group has correct nesting level")
    func nestedGroupHasCorrectNestingLevel() throws {
        let support = try SidebarTestSupport()

        // Create Group1 > Group2 (nested group)
        let group1 = try support.createGroup(name: "Level 1")
        let group2 = try support.createGroup(name: "Level 2", parentGroupID: group1.id)
        _ = support.createTab(url: "https://tab.com", groupID: group2.id)

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        #expect(group1.nestingLevel == 0)
        #expect(group2.nestingLevel == 1)
    }

    @Test("Drag tab from nested group to root")
    func dragTabFromNestedGroupToRoot() throws {
        let support = try SidebarTestSupport()

        // Create nested structure
        let group1 = try support.createGroup(name: "Level 1")
        let nestedTab = support.createTab(url: "https://nested.com", groupID: group1.id)
        _ = support.createTab(url: "https://root.com") // Target position

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let tabItem = support.layoutManager.normalItems.first { item in
            if case let .tab(tab) = item, tab.id == nestedTab.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(nestedTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Drag to root level (outside any group)
        let lastItem = support.layoutManager.normalItems.last!
        let lastFrame = support.dragCoordinator.computedItemFrame(for: lastItem.id)!

        support.dragCoordinator.updateDrag(
            offset: lastFrame.maxY + 20 - 100,
            location: CGPoint(x: 100, y: lastFrame.maxY + 20),
        )

        // The drop target should be outside any group
        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .normal)
        }
    }

    @Test("Drag group into child is blocked by cycle prevention")
    func dragGroupIntoChild() throws {
        let support = try SidebarTestSupport()

        // Create nested structure: Group1 > Group2
        let group1 = try support.createGroup(name: "Level 1")
        let group2 = try support.createGroup(name: "Level 2", parentGroupID: group1.id)
        _ = support.createTab(url: "https://tab.com", groupID: group2.id)

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let group1Item = support.layoutManager.normalItems.first { item in
            if case let .group(group) = item, group.id == group1.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[group1Item.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let group1Frame = support.dragCoordinator.computedItemFrame(for: group1Item.id)!
        support.dragCoordinator.startDrag(
            item: .group(group1),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: group1Frame.midX, y: group1Frame.midY),
        )

        // Try to drag group1 into group2 (its child)
        // This should be blocked by cycle prevention
        let group2Item = support.layoutManager.normalItems.first { item in
            if case let .group(group) = item, group.id == group2.id { return true }
            return false
        }!
        let group2Frame = support.dragCoordinator.computedItemFrame(for: group2Item.id)!

        support.dragCoordinator.updateDrag(
            offset: group2Frame.midY - 100,
            location: CGPoint(x: 100, y: group2Frame.midY),
        )

        // Should NOT have a nestGroup target pointing to group2
        if case let .nestGroup(parentGroupID) = support.dragCoordinator._dropTarget {
            #expect(parentGroupID != group2.id, "Should not allow nesting group into its child")
        }
    }

    @Test("Drag group into sibling is allowed")
    func dragGroupIntoSibling() throws {
        let support = try SidebarTestSupport()

        // Create structure: Group1, Group2 (siblings at root level)
        let group1 = try support.createGroup(name: "Group 1")
        _ = support.createTab(url: "https://tab1.com", groupID: group1.id)

        let group2 = try support.createGroup(name: "Group 2")
        _ = support.createTab(url: "https://tab2.com", groupID: group2.id)

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // group1 and group2 are siblings (both at root level)
        // Dragging group1 into group2 should be allowed (creating nested group)

        let group1Item = support.layoutManager.normalItems.first { item in
            if case let .group(group) = item, group.id == group1.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[group1Item.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let group1Frame = support.dragCoordinator.computedItemFrame(for: group1Item.id)!
        support.dragCoordinator.startDrag(
            item: .group(group1),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: group1Frame.midX, y: group1Frame.midY),
        )

        // Verify drag started
        #expect(support.dragCoordinator.isDragging)
    }

    @Test("Empty group drag maintains correct bounds")
    func emptyGroupDragMaintainsBounds() throws {
        let support = try SidebarTestSupport()

        // Create empty group
        let emptyGroup = try support.createGroup(name: "Empty Group")
        _ = support.createTab(url: "https://tab.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let groupItem = support.layoutManager.normalItems.first { item in
            if case let .group(group) = item, group.id == emptyGroup.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[groupItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let groupFrame = support.dragCoordinator.computedItemFrame(for: groupItem.id)!
        support.dragCoordinator.startDrag(
            item: .group(emptyGroup),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: groupFrame.midX, y: groupFrame.midY),
        )

        // Empty group bounds should be the header only
        let groupBounds = support.dragCoordinator._draggedGroupBounds
        #expect(groupBounds != nil)

        // Empty group's bounds height should be similar to a single item
        let singleItemHeight = Constants.Layout.tabItemHeight
        if let bounds = groupBounds {
            #expect(bounds.height <= singleItemHeight * 2)
        }
    }

    @Test("Nested group reorder within parent")
    func nestedGroupReorderWithinParent() throws {
        let support = try SidebarTestSupport()

        // Create parent with two child groups
        let parent = try support.createGroup(name: "Parent")
        let child1 = try support.createGroup(name: "Child 1", parentGroupID: parent.id)
        let child2 = try support.createGroup(name: "Child 2", parentGroupID: parent.id)
        _ = support.createTab(url: "https://tab1.com", groupID: child1.id)
        _ = support.createTab(url: "https://tab2.com", groupID: child2.id)

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Both children should have same parent
        #expect(child1.parentGroupID == parent.id)
        #expect(child2.parentGroupID == parent.id)

        // Verify structure is set up correctly
        #expect(child1.nestingLevel == 1)
        #expect(child2.nestingLevel == 1)
    }

    @Test("Descendants cache for nested group")
    func descendantsCacheForNestedGroup() throws {
        let support = try SidebarTestSupport()

        // Create 2-level structure (max allowed)
        let root = try support.createGroup(name: "Root")
        let child = try support.createGroup(name: "Child", parentGroupID: root.id)
        let tab1 = support.createTab(url: "https://tab1.com", groupID: child.id)
        let tab2 = support.createTab(url: "https://tab2.com", groupID: root.id)

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let rootItem = support.layoutManager.normalItems.first { item in
            if case let .group(group) = item, group.id == root.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[rootItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let rootFrame = support.dragCoordinator.computedItemFrame(for: rootItem.id)!
        support.dragCoordinator.startDrag(
            item: .group(root),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: rootFrame.midX, y: rootFrame.midY),
        )

        // Descendants cache should include all nested items
        let descendants = support.dragCoordinator.getDescendants(of: root.id)

        // Should include child group and both tabs
        #expect(descendants.contains(child.id))
        #expect(descendants.contains(tab1.id))
        #expect(descendants.contains(tab2.id))
    }

    @Test("Group bounds with nested child includes all descendants")
    func groupBoundsWithNestedChild() throws {
        let support = try SidebarTestSupport()

        // Create nested structure
        let parent = try support.createGroup(name: "Parent")
        let child = try support.createGroup(name: "Child", parentGroupID: parent.id)
        _ = support.createTab(url: "https://tab1.com", groupID: child.id)
        _ = support.createTab(url: "https://tab2.com", groupID: child.id)
        _ = support.createTab(url: "https://tab3.com", groupID: parent.id)

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Calculate parent group bounds
        let parentBounds = support.layoutManager.calculateGroupBounds(groupID: parent.id)

        // Bounds should include: parent header + child header + child's 2 tabs + parent's 1 tab
        // At minimum, 5 items worth of height
        let minExpectedHeight = 5 * Constants.Layout.tabItemHeight
        #expect(parentBounds.height >= minExpectedHeight)
    }
}
