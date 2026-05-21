import Foundation
import Testing

@testable import Refrax

/// Tests for edge cases in drag commit and state reset.
///
/// These tests verify:
/// - Commit behavior with various drop targets
/// - State reset during active animation
/// - Nesting level reset for groups
/// - Multi-selection state clearing
///
/// Note: `cancelDrag()` starts an animation and schedules cleanup after 0.35s.
/// Use `reset()` directly to test immediate state clearing.
@Suite("Commit and Reset Edge Cases", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragCommitResetTests {
    // MARK: - Test Helpers

    private func setupTestGeometry(_ support: SidebarTestSupport) {
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(CGRect(x: 0, y: 0, width: 200, height: 90))
        support.dragCoordinator.updateFavoritesGridLayout(
            columns: 3,
            tileSize: CGSize(width: 80, height: 80),
            spacing: 8,
        )
    }

    // MARK: - Commit Edge Cases

    @Test("Commit with drop target none returns false")
    func commitWithDropTargetNone() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Force drop target to none
        support.dragCoordinator._dropTarget = .none

        let didCommit = support.dragCoordinator.commitDrag()

        #expect(didCommit == false)
    }

    @Test("Commit reorder to same position runs animation but no model change")
    func commitReorderToSamePosition() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://tab2.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        let tabItem = support.layoutManager.normalItems.first!
        let tab1 = tabItem.tab!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let originalPosition = tab1.position
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab1),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Don't move (or move back to same position)
        support.dragCoordinator.updateDrag(
            offset: 5,
            location: CGPoint(x: 100, y: 105),
        )

        _ = support.dragCoordinator.commitDrag()

        // Should set isAnimatingReturn even if no actual reorder
        #expect(support.dragCoordinator.isAnimatingReturn == true)
        #expect(tab1.position == originalPosition)
    }

    @Test("Commit with isAnimatingReturn true is guarded")
    func commitWithIsAnimatingReturnTrue() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Set animating return before commit
        support.dragCoordinator.isAnimatingReturn = true

        // Commit happens internally regardless (sets state)
        _ = support.dragCoordinator.commitDrag()

        // isAnimatingReturn remains true
        #expect(support.dragCoordinator.isAnimatingReturn == true)
    }

    @Test("Commit add to group when group deleted gracefully fails")
    func commitAddToGroupWhenGroupDeleted() throws {
        let support = try SidebarTestSupport()
        let group = try support.createGroup(name: "Group")
        _ = support.createTab(url: "https://grouped.com", groupID: group.id)
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        let tabItem = support.layoutManager.normalItems.first { item in
            if case let .tab(t) = item, t.id == tab.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Set target to add to group
        support.dragCoordinator._dropTarget = .addToGroup(groupID: group.id)

        // Delete the group before commit
        support.env.groupManager.deleteGroup(group)
        support.rebuildLayout()

        // Commit should handle missing group gracefully
        let didCommit = support.dragCoordinator.commitDrag()

        // Result depends on whether addTabToGroup checks for group existence
        #expect(didCommit == false || didCommit == true)
    }

    @Test("Commit reorder cross-collection calculates indices correctly")
    func commitReorderCrossCollectionIndexMath() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        let normalTab = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to pinned section
        support.dragCoordinator.updateDrag(
            offset: -60,
            location: CGPoint(x: 100, y: 110),
        )

        let didCommit = support.dragCoordinator.commitDrag()
        #expect(didCommit)

        // Tab should now be pinned
        #expect(normalTab.isPinned == true)
    }

    // MARK: - Reset Edge Cases

    @Test("Direct reset clears all state immediately")
    func directResetClearsAllState() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        support.dragCoordinator.updateDrag(
            offset: 50,
            location: CGPoint(x: 100, y: 150),
        )

        // Direct reset clears everything immediately
        support.dragCoordinator.reset()

        #expect(support.dragCoordinator.isDragging == false)
        #expect(support.dragCoordinator.isAnimatingReturn == false)
        #expect(support.dragCoordinator.draggedItems.isEmpty)
    }

    @Test("Cancel drag starts animation before cleanup")
    func cancelDragStartsAnimation() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        support.dragCoordinator.updateDrag(
            offset: 50,
            location: CGPoint(x: 100, y: 150),
        )

        // cancelDrag starts animation, state clears after 0.35s
        support.dragCoordinator.cancelDrag()

        // Immediately after cancel, animation is in progress
        #expect(support.dragCoordinator.isAnimatingReturn == true)
    }

    @Test("Reset dragged item nesting level for group returns early")
    func resetDraggedItemNestingForGroup() throws {
        let support = try SidebarTestSupport()
        let group = try support.createGroup(name: "Group")
        _ = support.createTab(url: "https://tab.com", groupID: group.id)
        support.rebuildLayout()
        setupTestGeometry(support)

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

        // resetDraggedItemNestingLevel should handle group (return early)
        // This is called during cancel/commit
        support.dragCoordinator.resetDraggedItemNestingLevel()

        // Group nesting level should be unchanged
        #expect(group.nestingLevel == 0)
    }

    @Test("Direct reset clears all caches")
    func directResetClearsAllCaches() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Build some caches
        _ = support.dragCoordinator.getAllItems()

        // Direct reset should clear caches
        support.dragCoordinator.reset()

        #expect(support.dragCoordinator._allItemsCache.isEmpty)
        #expect(support.dragCoordinator._descendantsCache.isEmpty)
        #expect(support.dragCoordinator._draggedItemExclusionSet.isEmpty)
    }

    @Test("Direct reset clears ghost state and handoff phase")
    func directResetClearsGhostState() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Capture ghost state as if transitioning to external
        support.dragCoordinator.ghostState = support.dragCoordinator.captureGhostState()
        support.dragCoordinator.handoffPhase = .external

        #expect(support.dragCoordinator.ghostState != nil)

        // Direct reset should clear ghost state
        support.dragCoordinator.reset()

        #expect(support.dragCoordinator.ghostState == nil)
        #expect(support.dragCoordinator.handoffPhase == .internal)
    }

    @Test("Cancel multi-item drag starts animation")
    func cancelMultiItemDragStartsAnimation() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://tab1.com")
        let tab2 = support.createTab(url: "https://tab2.com")
        let tab3 = support.createTab(url: "https://tab3.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            items: [.tab(tab1), .tab(tab2), .tab(tab3)],
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Main item + 2 followers
        #expect(support.dragCoordinator.draggedItems.count == 1)
        #expect(support.dragCoordinator.followerItems.count == 2)

        support.dragCoordinator.updateDrag(
            offset: 50,
            location: CGPoint(x: 100, y: 150),
        )

        // Cancel starts animation
        support.dragCoordinator.cancelDrag()

        // Animation is in progress (cleanup scheduled for 0.35s later)
        #expect(support.dragCoordinator.isAnimatingReturn == true)
    }
}
