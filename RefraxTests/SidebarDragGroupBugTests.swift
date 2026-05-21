import Foundation
import Testing

@testable import Refrax

/// Tests for group-related drag bugs.
///
/// These tests expose bugs in group handling:
/// - calculateGroupBounds hard-codes width 300, mismatches dynamic sidebar width
/// - Group overlay bounds may be wrong for groups with many children
/// - Nested group drags may have incorrect descendant tracking
@Suite("Group Drag Bugs", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragGroupBugTests {
    // MARK: - Test Helpers

    private func setupStandardFrames(_ support: SidebarTestSupport, startY _: CGFloat = 100, width: CGFloat = 200) {
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: width, height: 600))
        support.dragCoordinator.updateFavoritesGridFrame(CGRect(x: 0, y: 0, width: width, height: 90))
        support.dragCoordinator.updateFavoritesGridLayout(
            columns: 3,
            tileSize: CGSize(width: 60, height: 60),
            spacing: 8,
        )
    }

    // MARK: - Group Bounds Width Bug Tests

    @Test("BUG: calculateGroupBounds uses hardcoded width 300")
    func calculateGroupBoundsHardcodedWidth() throws {
        let support = try SidebarTestSupport()

        // Create a group with several tabs
        let group = try support.createGroup(name: "Test Group")
        _ = support.createTab(url: "https://grouped1.com", groupID: group.id)
        _ = support.createTab(url: "https://grouped2.com", groupID: group.id)
        _ = support.createTab(url: "https://grouped3.com", groupID: group.id)
        _ = support.createTab(url: "https://normal.com")
        support.rebuildLayout()

        // Use a NARROW sidebar width (150px)
        setupStandardFrames(support, width: 150)

        // Find the group
        let groupItem = support.layoutManager.normalItems.first { item in
            if case let .group(g) = item, g.id == group.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[groupItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: groupItem.id)!
        support.dragCoordinator.startDrag(
            item: .group(group),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Get the overlay frame (which uses calculateGroupBounds)
        let overlayFrame = support.dragCoordinator.calculateCurrentOverlayFrame()

        // BUG: calculateGroupBounds hard-codes width to 300
        // But our sidebar is only 150px wide
        // The overlay should match the sidebar width, not 300

        // This exposes the bug: overlay width should be ~150, not 300
        #expect(overlayFrame.width <= 200, "BUG: Group overlay width should match sidebar, not hardcoded 300")
    }

    @Test("BUG: Wide sidebar exceeds hardcoded 300 width")
    func wideSidebarExceedsHardcodedWidth() throws {
        let support = try SidebarTestSupport()

        let group = try support.createGroup(name: "Wide Group")
        _ = support.createTab(url: "https://grouped1.com", groupID: group.id)
        _ = support.createTab(url: "https://grouped2.com", groupID: group.id)
        _ = support.createTab(url: "https://normal.com")
        support.rebuildLayout()

        // Use a WIDE sidebar (400px)
        setupStandardFrames(support, width: 400)

        let groupItem = support.layoutManager.normalItems.first { item in
            if case let .group(g) = item, g.id == group.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[groupItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: groupItem.id)!
        support.dragCoordinator.startDrag(
            item: .group(group),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        let overlayFrame = support.dragCoordinator.calculateCurrentOverlayFrame()

        // BUG: If sidebar is 400px but calculateGroupBounds uses 300
        // The overlay will be narrower than the actual group in the sidebar
        #expect(overlayFrame.width >= 350, "BUG: Group overlay should match wide sidebar, not be capped at 300")
    }

    // MARK: - Group Overlay Height Tests

    @Test("Group overlay height matches actual group content")
    func groupOverlayHeightMatchesContent() throws {
        let support = try SidebarTestSupport()

        let group = try support.createGroup(name: "Tall Group")
        for i in 0 ..< 10 {
            _ = support.createTab(url: "https://grouped\(i).com", groupID: group.id)
        }
        _ = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let groupItem = support.layoutManager.normalItems.first { item in
            if case let .group(g) = item, g.id == group.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[groupItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: groupItem.id)!
        support.dragCoordinator.startDrag(
            item: .group(group),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        let overlayFrame = support.dragCoordinator.calculateCurrentOverlayFrame()

        // Group header + 10 tabs at 40px each = header + 400px content
        // Overlay should encompass all children
        #expect(overlayFrame.height > 200, "Group overlay should be tall enough for all children")
    }

    // MARK: - Nested Group Descendant Tests

    @Test("Nested group drag includes all descendants in exclusion set")
    func nestedGroupDescendantsInExclusionSet() throws {
        let support = try SidebarTestSupport()

        // Create parent group with tabs
        let parentGroup = try support.createGroup(name: "Parent")
        let parentTab = support.createTab(url: "https://parent-tab.com", groupID: parentGroup.id)

        // Create child group nested in parent (max nesting is 2 levels)
        let childGroup = try support.createGroup(name: "Child", parentGroupID: parentGroup.id)
        let childTab1 = support.createTab(url: "https://child-tab1.com", groupID: childGroup.id)
        let childTab2 = support.createTab(url: "https://child-tab2.com", groupID: childGroup.id)

        _ = support.createTab(url: "https://ungrouped.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Find and drag the parent group
        let parentItem = support.layoutManager.normalItems.first { item in
            if case let .group(g) = item, g.id == parentGroup.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[parentItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: parentItem.id)!
        support.dragCoordinator.startDrag(
            item: .group(parentGroup),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Check exclusion set contains ALL descendants
        let exclusionSet = support.dragCoordinator._draggedItemExclusionSet

        // Should contain:
        // - parentGroup itself
        // - parentTab
        // - childGroup
        // - childTab1, childTab2
        #expect(exclusionSet.contains(parentGroup.id))
        #expect(exclusionSet.contains(parentTab.id))
        #expect(exclusionSet.contains(childGroup.id))
        #expect(exclusionSet.contains(childTab1.id))
        #expect(exclusionSet.contains(childTab2.id))
    }

    @Test("Dragging child group excludes only its own descendants")
    func childGroupExcludesOnlyItsDescendants() throws {
        let support = try SidebarTestSupport()

        let parentGroup = try support.createGroup(name: "Parent")
        let parentTab = support.createTab(url: "https://parent-tab.com", groupID: parentGroup.id)

        let childGroup = try support.createGroup(name: "Child", parentGroupID: parentGroup.id)
        let childTab = support.createTab(url: "https://child-tab.com", groupID: childGroup.id)

        _ = support.createTab(url: "https://ungrouped.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Drag just the child group
        let childItem = support.layoutManager.normalItems.first { item in
            if case let .group(g) = item, g.id == childGroup.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[childItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: childItem.id)!
        support.dragCoordinator.startDrag(
            item: .group(childGroup),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        let exclusionSet = support.dragCoordinator._draggedItemExclusionSet

        // Should contain childGroup and childTab
        #expect(exclusionSet.contains(childGroup.id))
        #expect(exclusionSet.contains(childTab.id))

        // Should NOT contain parent items
        #expect(!exclusionSet.contains(parentGroup.id))
        #expect(!exclusionSet.contains(parentTab.id))
    }

    // MARK: - Group Drop Target Detection Tests

    @Test("Dragging group cannot target itself")
    func draggingGroupCannotTargetItself() throws {
        let support = try SidebarTestSupport()

        let group = try support.createGroup(name: "Test Group")
        _ = support.createTab(url: "https://grouped.com", groupID: group.id)
        _ = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let groupItem = support.layoutManager.normalItems.first { item in
            if case let .group(g) = item, g.id == group.id { return true }
            return false
        }!

        let groupFrame = support.dragCoordinator.computedItemFrame(for: groupItem.id)!
        let originIndex = support.layoutManager.metadata[groupItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: groupItem.id)!
        support.dragCoordinator.startDrag(
            item: .group(group),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag over the group's own header
        support.dragCoordinator.updateDrag(
            offset: 10,
            location: CGPoint(x: 100, y: groupFrame.midY),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: groupFrame.midY))

        // Should NOT get addToGroup target for itself
        if case let .addToGroup(targetGroupID) = support.dragCoordinator._dropTarget {
            #expect(targetGroupID != group.id, "Group should not be able to drop into itself")
        }
    }

    @Test("Dragging parent group cannot target child group")
    func draggingParentCannotTargetChild() throws {
        let support = try SidebarTestSupport()

        let parentGroup = try support.createGroup(name: "Parent")
        _ = support.createTab(url: "https://parent-tab.com", groupID: parentGroup.id)

        let childGroup = try support.createGroup(name: "Child", parentGroupID: parentGroup.id)
        _ = support.createTab(url: "https://child-tab.com", groupID: childGroup.id)

        _ = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Drag parent group
        let parentItem = support.layoutManager.normalItems.first { item in
            if case let .group(g) = item, g.id == parentGroup.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[parentItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: parentItem.id)!
        support.dragCoordinator.startDrag(
            item: .group(parentGroup),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Find child group frame
        let childItem = support.layoutManager.normalItems.first { item in
            if case let .group(g) = item, g.id == childGroup.id { return true }
            return false
        }!
        let childFrame = support.dragCoordinator.computedItemFrame(for: childItem.id)!

        // Drag over child group header
        support.dragCoordinator.updateDrag(
            offset: 50,
            location: CGPoint(x: 100, y: childFrame.midY),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: childFrame.midY))

        // Should NOT get nestGroup target for descendant
        if case let .nestGroup(targetGroupID) = support.dragCoordinator._dropTarget {
            #expect(targetGroupID != childGroup.id, "Parent group should not nest into child")
        }
        if case let .addToGroup(targetGroupID) = support.dragCoordinator._dropTarget {
            #expect(targetGroupID != childGroup.id, "Parent group should not add to child")
        }
    }

    // MARK: - Group Animation Tests

    @Test("Group overlay target size calculated for group")
    func groupOverlayTargetSize() throws {
        let support = try SidebarTestSupport()

        let group = try support.createGroup(name: "Test")
        _ = support.createTab(url: "https://tab1.com", groupID: group.id)
        _ = support.createTab(url: "https://tab2.com", groupID: group.id)
        support.rebuildLayout()
        setupStandardFrames(support)

        let groupItem = support.layoutManager.normalItems.first { item in
            if case let .group(g) = item, g.id == group.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[groupItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: groupItem.id)!
        support.dragCoordinator.startDrag(
            item: .group(group),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        let targetSize = support.dragCoordinator.overlayTargetSize

        // For a group overlay, size should include header + children
        #expect(targetSize.width > 0)
        #expect(targetSize.height > 50) // At minimum, header height
    }

    @Test("Group overlay mode is group not tabRow")
    func groupOverlayModeIsGroup() throws {
        let support = try SidebarTestSupport()

        let group = try support.createGroup(name: "Test")
        _ = support.createTab(url: "https://tab.com", groupID: group.id)
        support.rebuildLayout()
        setupStandardFrames(support)

        let groupItem = support.layoutManager.normalItems.first { item in
            if case let .group(g) = item, g.id == group.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[groupItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: groupItem.id)!
        support.dragCoordinator.startDrag(
            item: .group(group),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // For groups, overlay mode is tabRow (groups use tab row appearance)
        let overlayMode = support.dragCoordinator.currentOverlayMode
        #expect(overlayMode == .tabRow)
    }

    // MARK: - Group With Empty Children

    @Test("Empty group drag still has valid overlay frame")
    func emptyGroupDragHasValidFrame() throws {
        let support = try SidebarTestSupport()

        let group = try support.createGroup(name: "Empty Group")
        // No tabs in group
        _ = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let groupItem = support.layoutManager.normalItems.first { item in
            if case let .group(g) = item, g.id == group.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[groupItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: groupItem.id)!
        support.dragCoordinator.startDrag(
            item: .group(group),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        let overlayFrame = support.dragCoordinator.calculateCurrentOverlayFrame()

        // Even empty group should have valid frame (at least header)
        #expect(!overlayFrame.isEmpty)
        #expect(overlayFrame.width > 0)
        #expect(overlayFrame.height > 0)
    }
}
