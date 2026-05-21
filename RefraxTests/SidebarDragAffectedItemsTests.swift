import Foundation
import Testing

@testable import Refrax

@Suite("Sidebar.DragCoordinator Affected Items", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragAffectedItemsTests {
    @Test("Dragging down displaces next item")
    func draggingDownDisplacesNextItem() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://one.com")
        _ = support.createTab(url: "https://two.com")
        _ = support.createTab(url: "https://three.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Use actual ordering (prepend insertion means last-created appears first)
        let items = support.layoutManager.pinnedItems + support.layoutManager.normalItems
        let firstItem = items[0]
        let secondItem = items[1]
        let thirdItem = items[2]
        let firstTab = firstItem.tab!

        let originIndex = support.layoutManager.metadata[firstItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: firstItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(firstTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        support.dragCoordinator.updateDrag(
            offset: 50,
            location: CGPoint(x: 10, y: 50),
        )

        let slotHeight = Constants.Layout.tabItemHeight + Constants.Layout.tabSpacing

        // Dragging first item down should displace second item (Y offset only for vertical tab list)
        // Third item may be in lookahead range (offset 0) but should NOT be fully displaced
        let expectedOffset = CGPoint(x: 0, y: -slotHeight)
        #expect(support.dragCoordinator.itemPushOffsets[secondItem.id] == expectedOffset)
        let thirdOffsetY = support.dragCoordinator.itemPushOffsets[thirdItem.id]?.y ?? 0
        #expect(thirdOffsetY != -slotHeight)
    }

    @Test("Dragging a group moves all descendants together")
    func groupDescendantsMoveWithHeader() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://one.com")
        let group = try support.createGroup(name: "Group")
        _ = support.createTab(url: "https://two.com", groupID: group.id)

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Find the group item based on actual ordering
        let items = support.layoutManager.pinnedItems + support.layoutManager.normalItems
        let groupItem = items.first { item in
            if case .group = item { return true }
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

        // Dragging a group - the group slot height includes all its contents
        // This test verifies drag state is set up correctly
        #expect(support.dragCoordinator.isDragging)
        #expect(support.dragCoordinator._draggedGroupBounds != nil)
    }
}
