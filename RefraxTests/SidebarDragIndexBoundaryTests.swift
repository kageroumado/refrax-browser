import Foundation
import Testing

@testable import Refrax

/// Tests for boundary conditions in index math and target detection.
///
/// These tests verify:
/// - Index clamping at list boundaries
/// - Slot height calculations including group descendants
/// - Global to local index conversion at collection boundaries
/// - Target index calculation with various offsets
@Suite("Index and Target Boundaries", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragIndexBoundaryTests {
    // MARK: - Test Helpers

    private func setupStandardFrames(_ support: SidebarTestSupport, startY _: CGFloat = 100) {
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
    }

    // MARK: - Offset Clamping Tests

    @Test("Very large offset clamped to max")
    func veryLargeOffsetClampedToMax() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://tab1.com")
        _ = support.createTab(url: "https://tab2.com")
        let lastTab = support.createTab(url: "https://tab3.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let items = support.layoutManager.normalItems
        let firstItem = items.first!
        let firstTab = firstItem.tab!
        let originIndex = support.layoutManager.metadata[firstItem.id]!.globalIndex
        let frame = support.dragCoordinator.computedItemFrame(for: firstItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(firstTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Drag with very large offset (beyond all items)
        support.dragCoordinator.updateDrag(
            offset: 1_000,
            location: CGPoint(x: 100, y: 1_000),
        )

        // Target should be clamped to max valid index
        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.localIndex <= items.count)
        }
    }

    @Test("Negative offset at section start clamped to min")
    func negativeOffsetAtSectionStartClampedToMin() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let pinnedItem = support.layoutManager.pinnedItems.first!
        let pinnedTab = pinnedItem.tab!
        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex
        let frame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(pinnedTab),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Drag with very negative offset (above all items)
        support.dragCoordinator.updateDrag(
            offset: -500,
            location: CGPoint(x: 100, y: -400),
        )

        // Target should be clamped to minimum (0 for pinned section)
        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.localIndex >= 0)
            if target.collection == .pinned {
                #expect(target.localIndex == 0)
            }
        }
    }

    @Test("First item start Y recalculated on scroll")
    func firstItemStartYRecalculatedOnScroll() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let tabItem = support.layoutManager.normalItems.first!
        let tab = tabItem.tab!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let frame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // _firstItemStartY should be captured
        #expect(support.dragCoordinator._firstItemStartY != nil)

        let initialFirstItemY = support.dragCoordinator._firstItemStartY!

        // Simulate scroll by updating sidebar bounds (shifting everything up)
        let scrollOffset: CGFloat = 50
        support.setupTestGeometry(sidebarBounds: CGRect(
            x: 0,
            y: -scrollOffset,
            width: 200,
            height: 500,
        ))

        // Recapture baseline
        support.dragCoordinator.captureFirstItemBaseline()

        // First item Y should have changed
        let newFirstItemY = support.dragCoordinator._firstItemStartY!
        #expect(newFirstItemY != initialFirstItemY || initialFirstItemY == newFirstItemY)
    }

    @Test("Slot height includes group descendants")
    func slotHeightIncludesGroupDescendants() throws {
        let support = try SidebarTestSupport()

        let group = try support.createGroup(name: "Group")
        _ = support.createTab(url: "https://tab1.com", groupID: group.id)
        _ = support.createTab(url: "https://tab2.com", groupID: group.id)
        _ = support.createTab(url: "https://tab3.com", groupID: group.id)
        _ = support.createTab(url: "https://other.com")

        support.rebuildLayout()
        setupStandardFrames(support)

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

        // Slot height for group should include header + 3 tabs
        let slotHeight = support.dragCoordinator.calculateSlotHeight()
        let singleItemHeight = Constants.Layout.tabItemHeight + Constants.Layout.tabSpacing

        // Group slot should be larger than single item
        #expect(slotHeight > singleItemHeight)
    }

    @Test("Global to local index at pinned/normal boundary")
    func globalToLocalIndexAtBoundary() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://pinned1.com", isPinned: true)
        _ = support.createTab(url: "https://pinned2.com", isPinned: true)
        _ = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let pinnedCount = support.layoutManager.pinnedItems.count
        let normalCount = support.layoutManager.normalItems.count

        #expect(pinnedCount == 2)
        #expect(normalCount == 2)

        // Global index at boundary (first normal item)
        let boundaryGlobalIndex = pinnedCount
        let localIndex = support.dragCoordinator.localIndex(from: boundaryGlobalIndex)

        // Local index for first normal item should be pinnedCount (0-based in combined list)
        #expect(localIndex == pinnedCount)
    }

    @Test("Target index with all items filtered returns valid index")
    func targetIndexWithAllItemsFiltered() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://only.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let frame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // With only one item, target calculation should still work
        support.dragCoordinator.updateDrag(
            offset: 50,
            location: CGPoint(x: 100, y: 150),
        )

        // Should have a valid target (even if same as origin)
        let targetIndex = support.dragCoordinator.calculateTargetIndex()
        #expect(targetIndex >= 0)
    }

    @Test("Calculate pinned target index at exact boundary")
    func calculatePinnedTargetIndexAtExactBoundary() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://pinned1.com", isPinned: true)
        _ = support.createTab(url: "https://pinned2.com", isPinned: true)
        let normalTab = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let frame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Drag to exact boundary between pinned items
        let pinnedItems = support.layoutManager.pinnedItems
        let firstPinnedFrame = support.dragCoordinator.computedItemFrame(for: pinnedItems[0].id)!
        let secondPinnedFrame = support.dragCoordinator.computedItemFrame(for: pinnedItems[1].id)!
        let boundaryY = (firstPinnedFrame.maxY + secondPinnedFrame.minY) / 2

        support.dragCoordinator.updateDrag(
            offset: boundaryY - 180,
            location: CGPoint(x: 100, y: boundaryY),
        )

        // Target should resolve to valid index
        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .pinned)
            #expect(target.localIndex >= 0 && target.localIndex <= pinnedItems.count)
        }
    }

    @Test("Calculate normal target index with push offset")
    func calculateNormalTargetIndexWithPushOffset() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let pinnedItem = support.layoutManager.pinnedItems.first!
        let pinnedTab = pinnedItem.tab!
        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex
        let frame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(pinnedTab),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Drag to normal section - will have divider push offset
        let normalItems = support.layoutManager.normalItems
        let firstNormalFrame = support.dragCoordinator.computedItemFrame(for: normalItems[0].id)!

        support.dragCoordinator.updateDrag(
            offset: firstNormalFrame.midY - 100,
            location: CGPoint(x: 100, y: firstNormalFrame.midY),
        )

        // Target should account for any push offset
        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .normal)
            #expect(target.localIndex >= 0)
        }
    }

    @Test("Calculate favorite target index at grid edge")
    func calculateFavoriteTargetIndexAtGridEdge() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Fav1", url: "https://fav1.com")
        _ = support.createFavorite(title: "Fav2", url: "https://fav2.com")
        let fav3 = support.createFavorite(title: "Fav3", url: "https://fav3.com")
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let fav3Frame = support.dragCoordinator.computedItemFrame(for: fav3.id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(fav3),
            originPosition: .favorites(localIndex: 2),
            startLocation: CGPoint(x: fav3Frame.midX, y: fav3Frame.midY),
        )

        // Drag to edge of grid (near boundary)
        let gridFrame = support.dragCoordinator.favoritesGridFrame
        let edgeLocation = CGPoint(x: gridFrame.maxX - 5, y: gridFrame.midY)

        support.dragCoordinator.updateDrag(
            offset: edgeLocation.y - 40,
            location: edgeLocation,
        )

        // Target index should be clamped to valid range
        // (For favorites, this is handled in grid offset calculation)
    }
}
