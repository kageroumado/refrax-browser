import Foundation
import Testing

@testable import Refrax

/// Tests for multi-selection bugs when selection spans pinned and normal sections.
///
/// These tests expose bugs in the commit logic when handling mixed collections:
/// - isCrossCollection check uses only first item, ignoring mixed selections
/// - Multi-item reorder can leave some items in wrong collection
/// - Pin state can drift when selection includes both pinned and normal tabs
@Suite("Mixed Collection Multi-Selection Bugs", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragMixedCollectionBugTests {
    // MARK: - Test Helpers

    private func setupStandardFrames(_ support: SidebarTestSupport, startY _: CGFloat = 100) {
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
    }

    // MARK: - Mixed Selection Bug Tests

    @Test("BUG: Multi-selection with mixed pinned/normal uses first item for isCrossCollection")
    func mixedSelectionUseFirstItemForCrossCollection() throws {
        let support = try SidebarTestSupport()
        // Create pinned tabs
        let pinned1 = support.createTab(url: "https://pinned1.com", isPinned: true)
        _ = support.createTab(url: "https://pinned2.com", isPinned: true)
        // Create normal tabs
        let normal1 = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Start drag with MIXED selection: pinned + normal tabs
        // The bug is that isCrossCollection only checks first item
        let pinnedItem = support.layoutManager.pinnedItems.first!
        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex
        let frame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        support.dragCoordinator.startDrag(
            items: [.tab(pinned1), .tab(normal1)], // Mixed: one pinned, one normal
            originPosition: .pinned(localIndex: localIndex), // Based on first item
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Drag to normal section
        support.dragCoordinator.updateDrag(
            offset: 140,
            location: CGPoint(x: 100, y: 240),
        )

        // Get the drop target - should be normal section
        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .normal)

            // Now commit
            let didCommit = support.dragCoordinator.commitDrag()
            #expect(didCommit)

            // BUG EXPOSURE: After commit, ALL items should be in normal section
            // But the isCrossCollection logic uses only first item
            // So normal1 might not get processed correctly
            #expect(pinned1.isPinned == false, "Pinned tab should now be unpinned")
            // The bug: normal1's isPinned state might be wrong or it might not move correctly
            #expect(normal1.isPinned == false, "Normal tab should stay normal")
        }
    }

    @Test("BUG: Mixed selection dragged to pinned section applies inconsistent pin state")
    func mixedSelectionToPinnedInconsistentPinState() throws {
        let support = try SidebarTestSupport()
        let pinned1 = support.createTab(url: "https://pinned1.com", isPinned: true)
        let normal1 = support.createTab(url: "https://normal1.com")
        let normal2 = support.createTab(url: "https://normal2.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Verify initial pin states
        #expect(pinned1.isPinned == true)
        #expect(normal1.isPinned == false)
        #expect(normal2.isPinned == false)

        // Start drag with MIXED selection: pinned + normal
        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let frame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        // Note: normal1 is most recently created, so it's first in layout order
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            items: [.tab(normal1), .tab(pinned1)], // Mixed: normal first, then pinned
            originPosition: .normal(localIndex: localIndex), // Based on first item (normal)
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Drag UP to pinned section
        support.dragCoordinator.updateDrag(
            offset: -80,
            location: CGPoint(x: 100, y: 120),
        )

        // Check drop target
        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .pinned)

            // Commit
            let didCommit = support.dragCoordinator.commitDrag()
            #expect(didCommit)

            // After committing to pinned section, ALL items should be pinned
            // BUG: The commit logic might not handle mixed selection correctly
            #expect(normal1.isPinned == true, "Normal tab should now be pinned")
            #expect(pinned1.isPinned == true, "Already-pinned tab should stay pinned")
        }
    }

    @Test("Multi-selection order preserved for same-collection items")
    func multiSelectionOrderPreservedSameCollection() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://tab1.com")
        let tab2 = support.createTab(url: "https://tab2.com")
        _ = support.createTab(url: "https://tab3.com")
        let tab4 = support.createTab(url: "https://tab4.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Layout order is: tab4, tab3, tab2, tab1 (most recent first)
        // Select tab4 and tab2 (non-contiguous)
        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let frame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            items: [.tab(tab4), .tab(tab2)], // Non-contiguous selection
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Drag to end of list
        support.dragCoordinator.updateDrag(
            offset: 120,
            location: CGPoint(x: 100, y: 280),
        )

        // Commit
        let didCommit = support.dragCoordinator.commitDrag()
        #expect(didCommit)

        // Rebuild to see final order
        support.rebuildLayout()

        // Check that the selection order is preserved at the target
        // This tests the multi-item reorder logic
        let normalTabs = support.layoutManager.normalItems.compactMap(\.tab)
        let tab4Index = normalTabs.firstIndex { $0.id == tab4.id }
        let tab2Index = normalTabs.firstIndex { $0.id == tab2.id }

        if let t4 = tab4Index, let t2 = tab2Index {
            // tab4 was first in selection, so should come before tab2 at target
            #expect(t4 < t2, "Selection order should be preserved")
        }
    }

    @Test("BUG: Cross-collection check ignores heterogeneous selection")
    func crossCollectionCheckIgnoresHeterogeneousSelection() throws {
        let support = try SidebarTestSupport()
        let pinned1 = support.createTab(url: "https://pinned1.com", isPinned: true)
        _ = support.createTab(url: "https://pinned2.com", isPinned: true)
        let normal1 = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Start drag with mixed selection, normal item first
        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let frame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            items: [.tab(normal1), .tab(pinned1)],
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Drag within normal section - use actual computed frame position
        let normalFrame = support.dragCoordinator.computedNormalSectionFrame
        let targetY = normalFrame.midY + 20 // Slightly below center to ensure we're in the section
        support.dragCoordinator.updateDrag(
            offset: targetY - frame.midY,
            location: CGPoint(x: 100, y: targetY),
        )

        // The drop target should be normal section reorder
        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .normal)

            // BUG ANALYSIS:
            // The commitReorder checks isCrossCollection using only first item:
            //   isCrossCollection = sourceIsPinned != targetIsPinned
            // But selection contains BOTH pinned and normal items.
            //
            // For normal1: sourceIsPinned=false, targetIsPinned=false → not cross-collection
            // For pinned1: sourceIsPinned=true, targetIsPinned=false → IS cross-collection
            //
            // The logic will treat this as NOT cross-collection because first item matches.
            // This means pinned1 won't be properly unpinned or moved.

            let didCommit = support.dragCoordinator.commitDrag()
            #expect(didCommit)

            // After commit, pinned1 should be unpinned (moved to normal)
            // BUG: This might not happen because isCrossCollection=false for first item
            #expect(pinned1.isPinned == false, "BUG: Pinned item in mixed selection should be unpinned when dragged to normal")
        }
    }

    // MARK: - Exclusion Set Tests for Mixed Selection

    @Test("Exclusion set contains all items from mixed selection")
    func exclusionSetContainsMixedSelection() throws {
        let support = try SidebarTestSupport()
        let pinned1 = support.createTab(url: "https://pinned1.com", isPinned: true)
        let normal1 = support.createTab(url: "https://normal1.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let pinnedItem = support.layoutManager.pinnedItems.first!
        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex
        let frame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        support.dragCoordinator.startDrag(
            items: [.tab(pinned1), .tab(normal1)],
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Exclusion set should contain both
        let exclusionSet = support.dragCoordinator._draggedItemExclusionSet
        #expect(exclusionSet.contains(pinned1.id))
        #expect(exclusionSet.contains(normal1.id))
    }

    // MARK: - Group with Mixed Collection

    @Test("Drag group containing mixed pin-state tabs")
    func dragGroupWithMixedPinStateTabs() throws {
        let support = try SidebarTestSupport()

        // Create a group with tabs
        let group = try support.createGroup(name: "Mixed Group")
        let groupedTab1 = support.createTab(url: "https://grouped1.com", groupID: group.id)
        let groupedTab2 = support.createTab(url: "https://grouped2.com", groupID: group.id)
        _ = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Find the group in layout
        let groupItem = support.layoutManager.normalItems.first { item in
            if case let .group(g) = item, g.id == group.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[groupItem.id]!.globalIndex
        let frame = support.dragCoordinator.computedItemFrame(for: groupItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .group(group),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Exclusion set should contain group AND all its children
        let exclusionSet = support.dragCoordinator._draggedItemExclusionSet
        #expect(exclusionSet.contains(group.id))
        #expect(exclusionSet.contains(groupedTab1.id))
        #expect(exclusionSet.contains(groupedTab2.id))
    }

    // MARK: - Per-Item Rebuild Performance Test

    @Test("Multi-item reorder performance with large selection")
    func multiItemReorderPerformance() throws {
        let support = try SidebarTestSupport()

        // Create 10 tabs (enough to test multi-item, not so many they overflow the sidebar)
        var tabs: [Tab] = []
        for i in 0 ..< 10 {
            tabs.append(support.createTab(url: "https://tab\(i).com"))
        }
        support.rebuildLayout()
        // Use larger sidebar to ensure all items have valid frames
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 1_000))

        // Select 5 tabs (half of them)
        let selectedTabs = Array(tabs.prefix(5))
        let draggedItems = selectedTabs.map { Sidebar.DragCoordinator.DraggedItem.tab($0) }

        let firstItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[firstItem.id]!.globalIndex
        let frame = support.dragCoordinator.computedItemFrame(for: firstItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            items: draggedItems,
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Move towards the middle of the normal section (reliable position)
        let normalFrame = support.dragCoordinator.computedNormalSectionFrame
        let targetY = normalFrame.midY
        support.dragCoordinator.updateDrag(
            offset: targetY - frame.midY,
            location: CGPoint(x: frame.midX, y: targetY),
        )

        // Commit - this will rebuild layout for EACH item (O(n²) bug)
        // We're not measuring time here, just ensuring it completes correctly
        let didCommit = support.dragCoordinator.commitDrag()
        #expect(didCommit)

        // Verify all tabs are still in normal section
        support.rebuildLayout()
        let normalTabs = support.layoutManager.normalItems.compactMap(\.tab)
        for tab in selectedTabs {
            #expect(normalTabs.contains { $0.id == tab.id })
        }
    }
}
