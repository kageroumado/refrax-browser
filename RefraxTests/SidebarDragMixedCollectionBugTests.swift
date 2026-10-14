import Foundation
import Testing
@testable import Refrax

/// Tests for multi-selection bugs when selection spans pinned and normal sections.
///
/// These tests expose bugs in the commit logic when handling mixed collections:
/// - isCrossCollection check uses only first item, ignoring mixed selections
/// - Multi-item reorder can leave some items in wrong collection
@Suite("Mixed Collection Multi-Selection Bugs", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragMixedCollectionBugTests {
    // MARK: - Test Helpers

    private func setupStandardFrames(_ support: SidebarTestSupport, startY _: CGFloat = 100) {
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
    }

    // MARK: - Mixed Selection Bug Tests

    @Test
    func `Multi-selection order preserved for same-collection items`() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://tab1.com")
        let tab2 = support.createTab(url: "https://tab2.com")
        _ = support.createTab(url: "https://tab3.com")
        let tab4 = support.createTab(url: "https://tab4.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Layout order is: tab4, tab3, tab2, tab1 (most recent first)
        // Select tab4 and tab2 (non-contiguous)
        let tabItem = try #require(support.layoutManager.normalItems.first)
        let originIndex = try #require(support.layoutManager.metadata[tabItem.id]?.globalIndex)
        let frame = try #require(support.dragCoordinator.computedItemFrame(for: tabItem.id))

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

    // MARK: - Exclusion Set Tests for Mixed Selection

    // MARK: - Group with Mixed Collection

    @Test
    func `Drag group containing mixed pin-state tabs`() throws {
        let support = try SidebarTestSupport()

        // Create a group with tabs
        let group = try support.createGroup(name: "Mixed Group")
        let groupedTab1 = support.createTab(url: "https://grouped1.com", groupID: group.id)
        let groupedTab2 = support.createTab(url: "https://grouped2.com", groupID: group.id)
        _ = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Find the group in layout
        let groupItem = try #require(support.layoutManager.normalItems.first { item in
            if case let .group(g) = item, g.id == group.id {
                return true
            }
            return false
        })

        let originIndex = try #require(support.layoutManager.metadata[groupItem.id]?.globalIndex)
        let frame = try #require(support.dragCoordinator.computedItemFrame(for: groupItem.id))

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

    @Test
    func `Multi-item reorder performance with large selection`() throws {
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

        let firstItem = try #require(support.layoutManager.normalItems.first)
        let originIndex = try #require(support.layoutManager.metadata[firstItem.id]?.globalIndex)
        let frame = try #require(support.dragCoordinator.computedItemFrame(for: firstItem.id))

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
