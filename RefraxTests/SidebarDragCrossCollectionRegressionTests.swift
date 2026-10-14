import Foundation
import Testing
@testable import Refrax

/// Regression tests for cross-collection drag bugs.
///
/// These tests cover bugs that were fixed in commit 2c2cafc and 7a01db4:
/// - PINNED→NORMAL visual feedback: Pull up remaining items correctly
/// - NORMAL→PINNED visual feedback: Push down items correctly
/// - Target index calculation with divider offset
/// - Animation target position for layout shifts
/// - Divider push offset guards
@Suite("Cross-Collection Regression", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragCrossCollectionRegressionTests {
    // MARK: - NORMAL→PINNED Regression Tests

    @Test
    func `NORMAL→PINNED: Pinned items at/after target push down`() throws {
        let support = try SidebarTestSupport()
        let pinned1 = try support.createGroup(name: "Pinned 1", isPinned: true)
        let pinned2 = try support.createGroup(name: "Pinned 2", isPinned: true)
        let normal = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let normalItem = try #require(support.layoutManager.normalItems.first)
        let originIndex = try #require(support.layoutManager.metadata[normalItem.id]?.globalIndex)

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let normalFrame = try #require(support.dragCoordinator.computedItemFrame(for: normalItem.id))
        support.dragCoordinator.startDrag(
            item: .tab(normal),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: normalFrame.midX, y: normalFrame.midY),
        )

        // Drag to first pinned position (before pinned1)
        let pinnedFrame = try #require(support.dragCoordinator.computedItemFrame(for: support.layoutManager.pinnedItems[0].id))
        support.dragCoordinator.updateDrag(
            offset: pinnedFrame.minY - 180,
            location: CGPoint(x: 100, y: pinnedFrame.minY + 5),
        )

        let slotHeight = Constants.Layout.tabItemHeight + Constants.Layout.tabSpacing

        // All pinned items should push down (positive offset) to make room
        let pinned1Offset = support.dragCoordinator.itemPushOffsets[pinned1.id]
        let pinned2Offset = support.dragCoordinator.itemPushOffsets[pinned2.id]

        #expect(pinned1Offset?.y == slotHeight)
        #expect(pinned2Offset?.y == slotHeight)
    }

    @Test
    func `NORMAL→PINNED: Normal items above origin push down`() throws {
        let support = try SidebarTestSupport()
        // Create tabs - note: newer tabs get position 0, pushing older ones down
        _ = try support.createGroup(name: "Pinned", isPinned: true)
        _ = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")
        _ = support.createTab(url: "https://normal3.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Layout order is: normal3 (idx 0), normal2 (idx 1), normal1 (idx 2)
        // Drag the LAST item in the layout to have items above it
        let normalItems = support.layoutManager.normalItems
        let lastNormalItem = try #require(normalItems.last)
        let originIndex = try #require(support.layoutManager.metadata[lastNormalItem.id]?.globalIndex)

        let draggedTab = try #require(lastNormalItem.tab)

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = try #require(support.dragCoordinator.computedItemFrame(for: lastNormalItem.id))
        support.dragCoordinator.startDrag(
            item: .tab(draggedTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Drag to pinned section - must be clearly in pinned section
        support.dragCoordinator.updateDrag(
            offset: -140,
            location: CGPoint(x: 100, y: 120),
        )

        let slotHeight = Constants.Layout.tabItemHeight + Constants.Layout.tabSpacing

        // Normal items ABOVE the origin should push down
        // Items at indices 0 and 1 are above the dragged item at index 2
        let firstNormalTab = try #require(normalItems[0].tab)
        let secondNormalTab = try #require(normalItems[1].tab)

        let firstOffset = support.dragCoordinator.itemPushOffsets[firstNormalTab.id]
        let secondOffset = support.dragCoordinator.itemPushOffsets[secondNormalTab.id]

        #expect(firstOffset?.y == slotHeight)
        #expect(secondOffset?.y == slotHeight)
    }

    // MARK: - Commit Regression Tests

    @Test
    func `Commit NORMAL→PINNED makes the tab a favorite`() throws {
        let support = try SidebarTestSupport()
        _ = try support.createGroup(name: "Pinned", isPinned: true)
        let normal = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        #expect(!normal.isFavorite)

        let normalItem = try #require(support.layoutManager.normalItems.first)
        let originIndex = try #require(support.layoutManager.metadata[normalItem.id]?.globalIndex)

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let normalFrame = try #require(support.dragCoordinator.computedItemFrame(for: normalItem.id))
        support.dragCoordinator.startDrag(
            item: .tab(normal),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: normalFrame.midX, y: normalFrame.midY),
        )

        // Drag to pinned section
        support.dragCoordinator.updateDrag(
            offset: -60,
            location: CGPoint(x: 100, y: 110),
        )

        let didCommit = support.dragCoordinator.commitDrag()
        #expect(didCommit)

        // A tab dropped in the pinned section becomes a favorite
        #expect(normal.isFavorite)
    }

    // MARK: - Divider Push Offset Guard Tests

    @Test
    func `Divider push offset zero when not dragging`() throws {
        let support = try SidebarTestSupport()
        _ = try support.createGroup(name: "Pinned", isPinned: true)
        _ = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Not dragging - divider push offset should be zero
        let pushOffset = support.dragCoordinator.dividerPushOffset
        #expect(pushOffset == 0)
    }

    @Test
    func `Divider push offset positive for NORMAL→PINNED`() throws {
        let support = try SidebarTestSupport()
        _ = try support.createGroup(name: "Pinned", isPinned: true)
        let normal = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let normalItem = try #require(support.layoutManager.normalItems.first)
        let originIndex = try #require(support.layoutManager.metadata[normalItem.id]?.globalIndex)

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let normalFrame = try #require(support.dragCoordinator.computedItemFrame(for: normalItem.id))
        support.dragCoordinator.startDrag(
            item: .tab(normal),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: normalFrame.midX, y: normalFrame.midY),
        )

        // Drag to pinned section (cross-collection)
        support.dragCoordinator.updateDrag(
            offset: -60,
            location: CGPoint(x: 100, y: 110),
        )

        // When NORMAL→PINNED, divider should push positive (down) to show pinned section growing
        let pushOffset = support.dragCoordinator.dividerPushOffset
        #expect(pushOffset > 0)
    }

    @Test
    func `Divider push offset zero for same-collection reorder`() throws {
        let support = try SidebarTestSupport()
        let normal1 = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let normalItem = try #require(support.layoutManager.normalItems.first)
        let originIndex = try #require(support.layoutManager.metadata[normalItem.id]?.globalIndex)

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let normalFrame = try #require(support.dragCoordinator.computedItemFrame(for: normalItem.id))
        support.dragCoordinator.startDrag(
            item: .tab(normal1),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: normalFrame.midX, y: normalFrame.midY),
        )

        // Drag within normal section (same-collection)
        support.dragCoordinator.updateDrag(
            offset: 50,
            location: CGPoint(x: 100, y: 150),
        )

        // Same-collection reorder should have zero divider push
        let pushOffset = support.dragCoordinator.dividerPushOffset
        #expect(pushOffset == 0)
    }
}
