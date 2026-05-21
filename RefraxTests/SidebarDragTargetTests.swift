import Foundation
import Testing

@testable import Refrax

@Suite("Sidebar.DragCoordinator Targets", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragTargetTests {
    @Test("Drop zone target favors pinning for groups when pinned section empty")
    func dropZoneTargetForGroupPinning() throws {
        let support = try SidebarTestSupport()
        let group = try support.createGroup(name: "Group")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let originIndex = support.layoutManager.metadata[group.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: group.id)!
        support.dragCoordinator.startDrag(
            item: .group(group),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag up to trigger drop zones. _isDragAboveTabList uses originalFrame.minY + offset
        // to determine if we're above the tab list. The offset must be large enough that
        // the dragged item's Y position is above the first item baseline.
        // Use the normal section start as reference (which is where the group is)
        let normalSectionMinY = support.dragCoordinator.computedNormalSectionFrame.minY
        let largeNegativeOffset = -(startFrame.minY - normalSectionMinY + 50)
        support.dragCoordinator.updateDrag(
            offset: largeNegativeOffset,
            location: CGPoint(x: startFrame.midX, y: normalSectionMinY - 20),
        )

        // The pin drop zone should be active since no pinned items exist and we're above tab list
        #expect(support.dragCoordinator.shouldShowPinDropZone == true)

        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .pinned)
            #expect(target.localIndex == 0)
        } else {
            Issue.record("Expected reorder target for pin drop zone, got \(support.dragCoordinator._dropTarget)")
        }

        #expect(support.dragCoordinator.activeDropZone == .pinnedSection)
    }

    @Test("Favorites grid target converts tabs to favorites")
    func favoritesGridTargetForTab() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://example.com")
        _ = support.createFavorite(title: "Favorite", url: "https://favorite.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(CGRect(x: 0, y: 0, width: 200, height: 100))

        let originIndex = support.layoutManager.metadata[tab.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tab.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 20, y: 20))

        if case let .convertToFavorite(mode) = support.dragCoordinator._dropTarget {
            #expect(mode == .liveFavorite)
        } else {
            Issue.record("Expected convertToFavorite target")
        }

        #expect(support.dragCoordinator.activeDropZone == .favoritesGrid)
    }

    @Test("Normal section target converts favorites to tabs")
    func normalSectionTargetForFavorite() throws {
        let support = try SidebarTestSupport()
        let favorite = support.createFavorite(title: "Favorite", url: "https://favorite.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(CGRect(x: 0, y: 0, width: 200, height: 80))

        support.dragCoordinator.startDrag(
            item: .favorite(favorite),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: 40, y: 40),
        )

        // Target inside the normal section
        let normalFrame = support.dragCoordinator.computedNormalSectionFrame
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 10, y: normalFrame.midY))

        if case let .convertToTab(targetSpace, targetPosition) = support.dragCoordinator._dropTarget {
            #expect(targetSpace.id == support.space.id)
            #expect(targetPosition.localIndex == 0)
            #expect(targetPosition.collection != .pinned)
        } else {
            Issue.record("Expected convertToTab target")
        }
    }

    @Test("Pinned target index uses static space centers")
    func pinnedTargetIndexUsesStaticSpace() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://one.com", isPinned: true)
        _ = support.createTab(url: "https://two.com", isPinned: true)

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Get the first and last pinned items by frame position
        let pinnedItems = support.layoutManager.pinnedItems
        let sortedPinned = pinnedItems.sorted { item1, item2 in
            let frame1 = support.dragCoordinator.computedItemFrame(for: item1.id)!
            let frame2 = support.dragCoordinator.computedItemFrame(for: item2.id)!
            return frame1.minY < frame2.minY
        }
        let lastPinned = sortedPinned.last!
        let firstPinnedTab = sortedPinned.first!.tab!

        let originIndex = support.layoutManager.metadata[sortedPinned.first!.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: sortedPinned.first!.id)!
        support.dragCoordinator.startDrag(
            item: .tab(firstPinnedTab),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Location well below the last pinned item's center should give index = pinnedCount (insert at end)
        let lastFrame = support.dragCoordinator.computedItemFrame(for: lastPinned.id)!
        let location = CGPoint(x: 0, y: lastFrame.maxY + 10)
        let index = support.dragCoordinator.calculatePinnedTargetIndex(at: location, pinnedCount: pinnedItems.count)

        #expect(index == pinnedItems.count)
    }

    @Test("Group header target adds tab to group")
    func groupHeaderTargetAddsTab() throws {
        let support = try SidebarTestSupport()
        // Create tab first, then group - order matters for position assignment
        _ = support.createTab(url: "https://example.com")
        let group = try support.createGroup(name: "Group")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let items = support.layoutManager.pinnedItems + support.layoutManager.normalItems

        // Find the ungrouped tab in actual ordering
        let ungroupedTabItem = items.first { item in
            if case let .tab(tab) = item, tab.groupID == nil { return true }
            return false
        }!
        let ungroupedTab = ungroupedTabItem.tab!

        // Find the group in items
        let groupItem = items.first { item in
            if case .group = item { return true }
            return false
        }!

        // Register frames in the frame registry so getVisibleItems() can find items
        // This is needed for detectGroupHover() which uses getVisibleItems()
        for item in items {
            if let frame = support.dragCoordinator.computedItemFrame(for: item.id) {
                support.managers.frameRegistry.setTestFrame(frame, for: item.id)
            }
        }

        let originIndex = support.layoutManager.metadata[ungroupedTabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: ungroupedTabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(ungroupedTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Update drag to initialize state needed for detection
        let groupFrame = support.dragCoordinator.computedItemFrame(for: groupItem.id)!
        support.dragCoordinator.updateDrag(
            offset: 0,
            location: CGPoint(x: groupFrame.midX, y: groupFrame.midY),
        )

        support.dragCoordinator.detectDropTarget(at: CGPoint(x: groupFrame.midX, y: groupFrame.midY))

        if case let .addToGroup(groupID) = support.dragCoordinator._dropTarget {
            #expect(groupID == group.id)
        } else {
            Issue.record("Expected addToGroup target, got \(support.dragCoordinator._dropTarget)")
        }

        #expect(support.dragCoordinator.activeDropZone == .groupHeader(group.id))
    }

    @Test("Tab list reorder target uses hovered index")
    func tabListReorderTargetUsesHoveredIndex() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://one.com")
        _ = support.createTab(url: "https://two.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let originIndex = support.layoutManager.metadata[tab1.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tab1.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab1),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag down to position after second tab
        let secondTabFrame = support.dragCoordinator.computedItemFrame(
            for: support.layoutManager.normalItems[1].id,
        )!
        support.dragCoordinator.updateDrag(
            offset: 50,
            location: CGPoint(x: 10, y: secondTabFrame.midY),
        )

        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .normal)
            #expect(target.localIndex == 1)
        } else {
            Issue.record("Expected reorder target")
        }
    }
}
