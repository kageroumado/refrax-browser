import Foundation
import Testing
@testable import Refrax

/// Comprehensive tests for multi-selection drag operations.
///
/// Multi-selection drag is a key feature for power users. These tests verify:
/// - Multiple tabs can be dragged together
/// - Groups are filtered from multi-selection
/// - Relative order is preserved during reorder
/// - Multi-item conversions (to favorites, to group)
/// - Non-contiguous selection handling
@Suite("Multi-Selection Drag", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragMultiSelectionTests {
    // MARK: - Test Helpers

    private func setupStandardFrames(_ support: SidebarTestSupport) {
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
    }

    // MARK: - Basic Multi-Selection Tests

    @Test
    func `Multi-selection drag tracks all items`() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://tab1.com")
        let tab2 = support.createTab(url: "https://tab2.com")
        let tab3 = support.createTab(url: "https://tab3.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let items = support.layoutManager.normalItems
        let originIndex = try #require(support.layoutManager.metadata[items[0].id]?.globalIndex)

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: items[0].id))
        support.dragCoordinator.startDrag(
            items: [.tab(tab1), .tab(tab2), .tab(tab3)],
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Main item goes in draggedItems, others become followers
        #expect(support.dragCoordinator.draggedItems.count == 1)
        #expect(support.dragCoordinator.followerItems.count == 2)
        #expect(support.dragCoordinator.primaryDraggedItem?.id == tab1.id)
    }

    @Test
    func `Primary dragged item is first in selection`() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://tab1.com")
        let tab2 = support.createTab(url: "https://tab2.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let items = support.layoutManager.normalItems
        let originIndex = try #require(support.layoutManager.metadata[items[0].id]?.globalIndex)

        // Drag with tab2 first in array
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: items[0].id))
        support.dragCoordinator.startDrag(
            items: [.tab(tab2), .tab(tab1)],
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Primary should be tab2 (first in selection)
        #expect(support.dragCoordinator.primaryDraggedItem?.id == tab2.id)
    }

    // MARK: - Group Filtering Tests

    @Test
    func `Groups are filtered from multi-selection`() throws {
        let support = try SidebarTestSupport()
        let group = try support.createGroup(name: "Test Group")
        let tab1 = support.createTab(url: "https://tab1.com")
        let tab2 = support.createTab(url: "https://tab2.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let items = support.layoutManager.normalItems
        let originIndex = try #require(support.layoutManager.metadata[items[0].id]?.globalIndex)

        // Try to drag tabs and group together
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: items[0].id))
        support.dragCoordinator.startDrag(
            items: [.tab(tab1), .group(group), .tab(tab2)],
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Groups should be filtered out - main item + 1 follower (2 tabs total)
        #expect(support.dragCoordinator.draggedItems.count == 1)
        #expect(support.dragCoordinator.followerItems.count == 1)
        #expect(support.dragCoordinator.draggedItems.allSatisfy { $0.group == nil })
        #expect(support.dragCoordinator.followerItems.allSatisfy { $0.group == nil })
    }

    @Test
    func `Single group is not filtered`() throws {
        let support = try SidebarTestSupport()
        let group = try support.createGroup(name: "Test Group")
        _ = support.createTab(url: "https://tab.com", groupID: group.id)
        support.rebuildLayout()
        setupStandardFrames(support)

        let groupItem = try #require(support.layoutManager.normalItems.first { item in
            if case let .group(g) = item, g.id == group.id {
                return true
            }
            return false
        })
        let originIndex = try #require(support.layoutManager.metadata[groupItem.id]?.globalIndex)

        // Single group drag should work
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: groupItem.id))
        support.dragCoordinator.startDrag(
            item: .group(group),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        #expect(support.dragCoordinator.draggedItems.count == 1)
        #expect(support.dragCoordinator.primaryDraggedItem?.group != nil)
    }

    // MARK: - Exclusion Set Tests

    @Test
    func `All dragged items are in exclusion set`() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://tab1.com")
        let tab2 = support.createTab(url: "https://tab2.com")
        let tab3 = support.createTab(url: "https://tab3.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let items = support.layoutManager.normalItems
        let originIndex = try #require(support.layoutManager.metadata[items[0].id]?.globalIndex)

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: items[0].id))
        support.dragCoordinator.startDrag(
            items: [.tab(tab1), .tab(tab2)],
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        let exclusionSet = support.dragCoordinator._draggedItemExclusionSet
        #expect(exclusionSet.contains(tab1.id))
        #expect(exclusionSet.contains(tab2.id))
        #expect(!exclusionSet.contains(tab3.id))
    }

    @Test
    func `Dragged items don't get push offsets`() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://tab1.com")
        let tab2 = support.createTab(url: "https://tab2.com")
        _ = support.createTab(url: "https://tab3.com")
        _ = support.createTab(url: "https://tab4.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let items = support.layoutManager.normalItems
        let originIndex = try #require(support.layoutManager.metadata[items[0].id]?.globalIndex)

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: items[0].id))
        support.dragCoordinator.startDrag(
            items: [.tab(tab1), .tab(tab2)],
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag down
        support.dragCoordinator.updateDrag(
            offset: 80,
            location: CGPoint(x: 100, y: 250),
        )

        let offsets = support.dragCoordinator.itemPushOffsets

        // Dragged items should not have offsets
        #expect(offsets[tab1.id] == nil)
        #expect(offsets[tab2.id] == nil)
    }

    // MARK: - Multi-Item Reorder Tests

    @Test
    func `Multi-item reorder moves all items together`() throws {
        let support = try SidebarTestSupport()
        // Note: Newer tabs are inserted at the top, so creation order is reversed in normalItems
        // Creating: tab1, tab2, tab3, tab4 results in order: [tab4, tab3, tab2, tab1]
        let tab1 = support.createTab(url: "https://tab1.com")
        let tab2 = support.createTab(url: "https://tab2.com")
        let tab3 = support.createTab(url: "https://tab3.com")
        let tab4 = support.createTab(url: "https://tab4.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Get actual positions - tab4 is at the top (index 0), tab1 at the bottom (index 3)
        let items = support.layoutManager.normalItems
        let tab4Item = try #require(items.first {
            if case let .tab(t) = $0, t.id == tab4.id {
                return true
            }; return false
        })
        let tab4Index = try #require(support.layoutManager.metadata[tab4Item.id]?.globalIndex)
        let tab4Frame = try #require(support.dragCoordinator.computedItemFrame(for: tab4Item.id))

        // Drag tab4 and tab3 (top two tabs) to the bottom
        let localIndex = tab4Index - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            items: [.tab(tab4), .tab(tab3)],
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tab4Frame.midX, y: tab4Frame.midY),
        )

        // Drag to below the last item (tab1)
        let tab1Item = try #require(items.first {
            if case let .tab(t) = $0, t.id == tab1.id {
                return true
            }; return false
        })
        let tab1Frame = try #require(support.dragCoordinator.computedItemFrame(for: tab1Item.id))

        support.dragCoordinator.updateDrag(
            offset: tab1Frame.maxY + 20 - tab4Frame.minY,
            location: CGPoint(x: 100, y: tab1Frame.maxY + 20),
        )

        let didCommit = support.dragCoordinator.commitDrag()
        #expect(didCommit)

        support.rebuildLayout()

        // Verify tab1 and tab2 now come before tab4 and tab3
        let newOrder = support.layoutManager.normalItems.compactMap { item -> UUID? in
            if case let .tab(t) = item {
                return t.id
            }
            return nil
        }

        // tab2 should be before tab4 (tab4 moved down)
        let tab2Index = try #require(newOrder.firstIndex(of: tab2.id))
        let tab4NewIndex = try #require(newOrder.firstIndex(of: tab4.id))
        #expect(tab2Index < tab4NewIndex)
    }

    @Test
    func `Multi-item reorder preserves relative order`() throws {
        let support = try SidebarTestSupport()
        // Note: Newer tabs are inserted at the top, so creation order is reversed in normalItems
        // Creating: tab1, tab2, tab3, tab4 results in order: [tab4, tab3, tab2, tab1]
        let tab1 = support.createTab(url: "https://tab1.com")
        _ = support.createTab(url: "https://tab2.com")
        let tab3 = support.createTab(url: "https://tab3.com")
        let tab4 = support.createTab(url: "https://tab4.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Get actual positions - tab4 is at the top (index 0)
        let items = support.layoutManager.normalItems
        let tab4Item = try #require(items.first {
            if case let .tab(t) = $0, t.id == tab4.id {
                return true
            }; return false
        })
        let tab4Index = try #require(support.layoutManager.metadata[tab4Item.id]?.globalIndex)
        let tab4Frame = try #require(support.dragCoordinator.computedItemFrame(for: tab4Item.id))

        // Drag tab4 and tab3 downward
        let localIndex = tab4Index - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            items: [.tab(tab4), .tab(tab3)],
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tab4Frame.midX, y: tab4Frame.midY),
        )

        support.dragCoordinator.updateDrag(
            offset: 120,
            location: CGPoint(x: 100, y: tab4Frame.minY + 120),
        )

        let didCommit = support.dragCoordinator.commitDrag()
        #expect(didCommit)

        support.rebuildLayout()
        let newOrder = support.layoutManager.normalItems.compactMap { item -> UUID? in
            if case let .tab(t) = item {
                return t.id
            }
            return nil
        }

        // tab4 should still come before tab3 (relative order preserved)
        let tab4NewIndex = try #require(newOrder.firstIndex(of: tab4.id))
        let tab3NewIndex = try #require(newOrder.firstIndex(of: tab3.id))
        #expect(tab4NewIndex < tab3NewIndex)
    }

    // MARK: - Multi-Item Conversion Tests

    @Test
    func `Multi-item conversion to favorites converts all`() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://tab1.com")
        let tab2 = support.createTab(url: "https://tab2.com")
        let tab3 = support.createTab(url: "https://tab3.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let initialFavCount = support.layoutManager.favoritesLayout.count

        let items = support.layoutManager.normalItems
        let tab1Item = try #require(items.first {
            if case let .tab(t) = $0, t.id == tab1.id {
                return true
            }; return false
        })
        let originIndex = try #require(support.layoutManager.metadata[tab1Item.id]?.globalIndex)

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: tab1Item.id))
        support.dragCoordinator.startDrag(
            items: [.tab(tab1), .tab(tab2), .tab(tab3)],
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to favorites
        support.dragCoordinator.updateDrag(
            offset: -100,
            location: CGPoint(x: 100, y: 40),
        )

        let didCommit = support.dragCoordinator.commitDrag()
        #expect(didCommit)

        support.rebuildLayout()
        #expect(support.layoutManager.favoritesLayout.count == initialFavCount + 3)
    }

    @Test
    func `Multi-item add to group adds all`() throws {
        let support = try SidebarTestSupport()
        let group = try support.createGroup(name: "Target Group")
        let tab1 = support.createTab(url: "https://tab1.com")
        let tab2 = support.createTab(url: "https://tab2.com")
        _ = support.createTab(url: "https://tab3.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let items = support.layoutManager.normalItems
        let tab1Item = try #require(items.first {
            if case let .tab(t) = $0, t.id == tab1.id {
                return true
            }; return false
        })
        let groupItem = try #require(items.first {
            if case let .group(g) = $0, g.id == group.id {
                return true
            }; return false
        })

        let originIndex = try #require(support.layoutManager.metadata[tab1Item.id]?.globalIndex)
        let groupFrame = try #require(support.dragCoordinator.computedItemFrame(for: groupItem.id))

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: tab1Item.id))
        support.dragCoordinator.startDrag(
            items: [.tab(tab1), .tab(tab2)],
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to group header
        support.dragCoordinator.updateDrag(
            offset: groupFrame.midY - 150,
            location: CGPoint(x: 100, y: groupFrame.midY),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: groupFrame.midY))

        // Verify target is add to group
        if case let .addToGroup(groupID) = support.dragCoordinator._dropTarget {
            #expect(groupID == group.id)
        } else {
            Issue.record("Expected addToGroup target")
        }

        let didCommit = support.dragCoordinator.commitDrag()
        #expect(didCommit)

        // Both tabs should now be in the group
        #expect(tab1.groupID == group.id)
        #expect(tab2.groupID == group.id)
    }

    // MARK: - Cross-Section Multi-Selection Tests

    // MARK: - Non-Contiguous Selection Tests

    @Test
    func `Non-contiguous selection reorders correctly`() throws {
        let support = try SidebarTestSupport()
        // Note: Newer tabs are inserted at the top, so creation order is reversed in normalItems
        // Creating: tab1, tab2, tab3, tab4, tab5 results in order: [tab5, tab4, tab3, tab2, tab1]
        let tab1 = support.createTab(url: "https://tab1.com")
        _ = support.createTab(url: "https://tab2.com")
        let tab3 = support.createTab(url: "https://tab3.com")
        _ = support.createTab(url: "https://tab4.com")
        let tab5 = support.createTab(url: "https://tab5.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Get actual positions - tab5 is at the top (index 0)
        let items = support.layoutManager.normalItems
        let tab5Item = try #require(items.first {
            if case let .tab(t) = $0, t.id == tab5.id {
                return true
            }; return false
        })
        let tab5Index = try #require(support.layoutManager.metadata[tab5Item.id]?.globalIndex)
        let tab5Frame = try #require(support.dragCoordinator.computedItemFrame(for: tab5Item.id))

        // Select tab5 and tab3 (non-contiguous - at indices 0 and 2)
        let localIndex = tab5Index - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            items: [.tab(tab5), .tab(tab3)],
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tab5Frame.midX, y: tab5Frame.midY),
        )

        // Drag to end (below tab1 which is at the bottom)
        let tab1Item = try #require(items.first {
            if case let .tab(t) = $0, t.id == tab1.id {
                return true
            }; return false
        })
        let tab1Frame = try #require(support.dragCoordinator.computedItemFrame(for: tab1Item.id))

        support.dragCoordinator.updateDrag(
            offset: tab1Frame.maxY + 20 - tab5Frame.minY,
            location: CGPoint(x: 100, y: tab1Frame.maxY + 20),
        )

        let didCommit = support.dragCoordinator.commitDrag()
        #expect(didCommit)

        support.rebuildLayout()
        let newOrder = support.layoutManager.normalItems.compactMap { item -> UUID? in
            if case let .tab(t) = item {
                return t.id
            }
            return nil
        }

        // tab5 and tab3 should be at the end, maintaining relative order (tab5 before tab3)
        let tab5NewIndex = try #require(newOrder.firstIndex(of: tab5.id))
        let tab3NewIndex = try #require(newOrder.firstIndex(of: tab3.id))
        #expect(tab5NewIndex < tab3NewIndex) // Relative order preserved
        #expect(tab3NewIndex >= newOrder.count - 2) // Near end
    }

    // MARK: - Edge Cases

    @Test
    func `Empty multi-selection is treated as single item`() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let items = support.layoutManager.normalItems
        let tabItem = try #require(items.first {
            if case let .tab(t) = $0, t.id == tab.id {
                return true
            }; return false
        })
        let originIndex = try #require(support.layoutManager.metadata[tabItem.id]?.globalIndex)

        // Start with single item (not multi-selection)
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: tabItem.id))
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        #expect(support.dragCoordinator.draggedItems.count == 1)
        #expect(support.dragCoordinator.primaryDraggedItem?.id == tab.id)
    }

    @Test
    func `Large multi-selection (10+ items)`() throws {
        let support = try SidebarTestSupport()
        var tabs: [Tab] = []
        for i in 0 ..< 15 {
            tabs.append(support.createTab(url: "https://tab\(i).com"))
        }
        support.rebuildLayout()
        setupStandardFrames(support)

        let items = support.layoutManager.normalItems
        let originIndex = try #require(support.layoutManager.metadata[items[0].id]?.globalIndex)

        // Select first 10 tabs
        let draggedItems = tabs.prefix(10).map { Sidebar.DragCoordinator.DraggedItem.tab($0) }
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: items[0].id))
        support.dragCoordinator.startDrag(
            items: Array(draggedItems),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Main item + 9 followers
        #expect(support.dragCoordinator.draggedItems.count == 1)
        #expect(support.dragCoordinator.followerItems.count == 9)

        // All 10 should be in exclusion set
        let exclusionSet = support.dragCoordinator._draggedItemExclusionSet
        for i in 0 ..< 10 {
            #expect(exclusionSet.contains(tabs[i].id))
        }

        // Remaining tabs should not be excluded
        for i in 10 ..< 15 {
            #expect(!exclusionSet.contains(tabs[i].id))
        }
    }

    @Test
    func `Cancel multi-selection drag clears all state`() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://tab1.com")
        let tab2 = support.createTab(url: "https://tab2.com")
        _ = support.createTab(url: "https://tab3.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let items = support.layoutManager.normalItems
        let originIndex = try #require(support.layoutManager.metadata[items[0].id]?.globalIndex)

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: items[0].id))
        support.dragCoordinator.startDrag(
            items: [.tab(tab1), .tab(tab2)],
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        support.dragCoordinator.updateDrag(
            offset: 80,
            location: CGPoint(x: 100, y: 250),
        )

        support.dragCoordinator.cancelDrag()

        #expect(support.dragCoordinator.isAnimatingReturn == true)
        #expect(support.dragCoordinator.itemPushOffsets.values.allSatisfy { $0 == .zero })
    }
}
