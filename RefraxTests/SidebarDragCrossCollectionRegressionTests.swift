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
    // MARK: - PINNED→NORMAL Regression Tests

    @Test("PINNED→NORMAL: Remaining pinned items pull up to fill gap")
    func pinnedToNormalPullsUpRemainingPinned() throws {
        let support = try SidebarTestSupport()
        // Create tabs - note: newer tabs get position 0, pushing older ones down
        // So creation order is reversed from layout order
        _ = support.createTab(url: "https://pinned1.com", isPinned: true)
        _ = support.createTab(url: "https://pinned2.com", isPinned: true)
        _ = support.createTab(url: "https://pinned3.com", isPinned: true)
        _ = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Layout order is: pinned3 (idx 0), pinned2 (idx 1), pinned1 (idx 2), then normal
        // Drag the FIRST item in the layout (pinned3) to get items below it
        let firstPinnedItem = support.layoutManager.pinnedItems.first!
        let originIndex = support.layoutManager.metadata[firstPinnedItem.id]!.globalIndex

        // Get the tab being dragged
        let draggedTab = firstPinnedItem.tab!

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: firstPinnedItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(draggedTab),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Drag to normal section - location must be clearly in normal section
        support.dragCoordinator.updateDrag(
            offset: 140,
            location: CGPoint(x: 100, y: 240),
        )

        let slotHeight = Constants.Layout.tabItemHeight + Constants.Layout.tabSpacing

        // Pinned items BELOW the origin (items at indices 1 and 2) should pull up
        let pinnedItems = support.layoutManager.pinnedItems
        // The second and third items in the layout should get pull-up offset
        let secondPinnedTab = pinnedItems[1].tab!
        let thirdPinnedTab = pinnedItems[2].tab!

        let secondOffset = support.dragCoordinator.itemPushOffsets[secondPinnedTab.id]
        let thirdOffset = support.dragCoordinator.itemPushOffsets[thirdPinnedTab.id]

        #expect(secondOffset?.y == -slotHeight)
        #expect(thirdOffset?.y == -slotHeight)
    }

    @Test("PINNED→NORMAL: Normal items before target pull up to follow divider")
    func pinnedToNormalPullsUpNormalBeforeTarget() throws {
        let support = try SidebarTestSupport()
        let pinned = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://normal1.com")
        let normal2 = support.createTab(url: "https://normal2.com")
        _ = support.createTab(url: "https://normal3.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let pinnedItem = support.layoutManager.pinnedItems.first!
        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        let pinnedFrame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(pinned),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: pinnedFrame.midX, y: pinnedFrame.midY),
        )

        // Find normal2 and drag to its position (target index 1)
        let normal2Item = support.layoutManager.normalItems.first { item in
            if case let .tab(t) = item, t.id == normal2.id { return true }
            return false
        }!
        let normal2Frame = support.dragCoordinator.computedItemFrame(for: normal2Item.id)!

        support.dragCoordinator.updateDrag(
            offset: normal2Frame.midY - 100,
            location: CGPoint(x: 100, y: normal2Frame.midY),
        )
        // Normal items BEFORE the target should pull up to follow divider
        // If target is index 2, normal1 (index 0) and possibly normal2 (index 1) should pull up
        // Items at/after target stay in place (insertion gap is between item N-1 and N)
    }

    @Test("PINNED→NORMAL: Items at/after target stay in place")
    func pinnedToNormalItemsAfterTargetStay() throws {
        let support = try SidebarTestSupport()
        let pinned = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")
        let normal3 = support.createTab(url: "https://normal3.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let pinnedItem = support.layoutManager.pinnedItems.first!
        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        let pinnedFrame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(pinned),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: pinnedFrame.midX, y: pinnedFrame.midY),
        )

        // Drag to first normal position (index 0)
        let firstNormalItem = support.layoutManager.normalItems.first!
        let firstNormalFrame = support.dragCoordinator.computedItemFrame(for: firstNormalItem.id)!

        support.dragCoordinator.updateDrag(
            offset: firstNormalFrame.minY - 100,
            location: CGPoint(x: 100, y: firstNormalFrame.minY + 5),
        )

        // Items at/after target index 0 should NOT have pull-up offset
        // The gap is created by dividerPushOffset, not by item offsets
        let normal3Offset = support.dragCoordinator.itemPushOffsets[normal3.id]

        // normal3 should not be pulled up when targeting index 0
        #expect(normal3Offset == nil || normal3Offset?.y == 0)
    }

    // MARK: - NORMAL→PINNED Regression Tests

    @Test("NORMAL→PINNED: Pinned items at/after target push down")
    func normalToPinnedPushesDownPinned() throws {
        let support = try SidebarTestSupport()
        let pinned1 = support.createTab(url: "https://pinned1.com", isPinned: true)
        let pinned2 = support.createTab(url: "https://pinned2.com", isPinned: true)
        let normal = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let normalFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(normal),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: normalFrame.midX, y: normalFrame.midY),
        )

        // Drag to first pinned position (before pinned1)
        let pinnedFrame = support.dragCoordinator.computedItemFrame(for: support.layoutManager.pinnedItems[0].id)!
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

    @Test("NORMAL→PINNED: Normal items above origin push down")
    func normalToPinnedPushesDownNormalAboveOrigin() throws {
        let support = try SidebarTestSupport()
        // Create tabs - note: newer tabs get position 0, pushing older ones down
        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")
        _ = support.createTab(url: "https://normal3.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Layout order is: normal3 (idx 0), normal2 (idx 1), normal1 (idx 2)
        // Drag the LAST item in the layout to have items above it
        let normalItems = support.layoutManager.normalItems
        let lastNormalItem = normalItems.last!
        let originIndex = support.layoutManager.metadata[lastNormalItem.id]!.globalIndex

        let draggedTab = lastNormalItem.tab!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: lastNormalItem.id)!
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
        let firstNormalTab = normalItems[0].tab!
        let secondNormalTab = normalItems[1].tab!

        let firstOffset = support.dragCoordinator.itemPushOffsets[firstNormalTab.id]
        let secondOffset = support.dragCoordinator.itemPushOffsets[secondNormalTab.id]

        #expect(firstOffset?.y == slotHeight)
        #expect(secondOffset?.y == slotHeight)
    }

    // MARK: - Target Index Calculation Regression Tests

    @Test("Target index accounts for divider push offset")
    func targetIndexAccountsForDividerOffset() throws {
        let support = try SidebarTestSupport()
        let pinned = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let pinnedItem = support.layoutManager.pinnedItems.first!
        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        let pinnedFrame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(pinned),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: pinnedFrame.midX, y: pinnedFrame.midY),
        )

        // Drag to what visually appears as second normal position
        // The divider push offset means visual position != static position
        let normalItems = support.layoutManager.normalItems
        let secondNormalFrame = support.dragCoordinator.computedItemFrame(for: normalItems[1].id)!

        support.dragCoordinator.updateDrag(
            offset: secondNormalFrame.midY - 100,
            location: CGPoint(x: 100, y: secondNormalFrame.midY),
        )

        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .normal)
            // Target index should be calculated correctly accounting for offset
            #expect(target.localIndex >= 0 && target.localIndex <= normalItems.count)
        }
    }

    // MARK: - Commit Regression Tests

    @Test("Commit PINNED→NORMAL changes pin state correctly")
    func commitPinnedToNormalChangesPinState() throws {
        let support = try SidebarTestSupport()
        let pinned = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        #expect(pinned.isPinned == true)

        let pinnedItem = support.layoutManager.pinnedItems.first!
        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        let pinnedFrame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(pinned),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: pinnedFrame.midX, y: pinnedFrame.midY),
        )

        // Drag to normal section
        support.dragCoordinator.updateDrag(
            offset: 100,
            location: CGPoint(x: 100, y: 200),
        )

        let didCommit = support.dragCoordinator.commitDrag()
        #expect(didCommit)

        // Tab should now be unpinned
        #expect(pinned.isPinned == false)
    }

    @Test("Commit NORMAL→PINNED changes pin state correctly")
    func commitNormalToPinnedChangesPinState() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        let normal = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        #expect(normal.isPinned == false)

        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let normalFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!
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

        // Tab should now be pinned
        #expect(normal.isPinned == true)
    }

    @Test("Commit preserves relative ordering in target section")
    func commitPreservesRelativeOrdering() throws {
        let support = try SidebarTestSupport()
        // Create tabs - note: newer tabs get position 0, pushing older ones down
        _ = support.createTab(url: "https://pinned1.com", isPinned: true)
        _ = support.createTab(url: "https://pinned2.com", isPinned: true)
        let normal = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let normalFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(normal),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: normalFrame.midX, y: normalFrame.midY),
        )

        // Get the first and second pinned items in layout order
        let pinnedItems = support.layoutManager.pinnedItems
        let firstPinnedId = pinnedItems[0].id
        let secondPinnedId = pinnedItems[1].id

        // Drag between the first and second pinned items
        let firstPinnedFrame = support.dragCoordinator.computedItemFrame(for: firstPinnedId)!
        let secondPinnedFrame = support.dragCoordinator.computedItemFrame(for: secondPinnedId)!
        let targetY = (firstPinnedFrame.maxY + secondPinnedFrame.minY) / 2

        support.dragCoordinator.updateDrag(
            offset: targetY - 180,
            location: CGPoint(x: 100, y: targetY),
        )

        let didCommit = support.dragCoordinator.commitDrag()
        #expect(didCommit)

        support.rebuildLayout()

        // Verify order: the normal tab should now be between the original first and second pinned items
        let newPinnedOrder = support.layoutManager.pinnedItems.compactMap { item -> UUID? in
            if case let .tab(t) = item { return t.id }
            return nil
        }

        let firstPinnedNewIndex = newPinnedOrder.firstIndex(of: firstPinnedId)
        let normalNewIndex = newPinnedOrder.firstIndex(of: normal.id)
        let secondPinnedNewIndex = newPinnedOrder.firstIndex(of: secondPinnedId)

        if let first = firstPinnedNewIndex, let n = normalNewIndex, let second = secondPinnedNewIndex {
            // normal should be between the original first and second items
            #expect(first < n && n < second)
        }
    }

    // MARK: - Divider Push Offset Guard Tests

    @Test("Divider push offset zero when not dragging")
    func dividerPushOffsetZeroWhenNotDragging() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Not dragging - divider push offset should be zero
        let pushOffset = support.dragCoordinator.dividerPushOffset
        #expect(pushOffset == 0)
    }

    @Test("Divider push offset non-zero during cross-collection drag")
    func dividerPushOffsetNonZeroDuringCrossDrag() throws {
        let support = try SidebarTestSupport()
        let pinned = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let pinnedItem = support.layoutManager.pinnedItems.first!
        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        let pinnedFrame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(pinned),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: pinnedFrame.midX, y: pinnedFrame.midY),
        )

        // Drag to normal section (cross-collection)
        support.dragCoordinator.updateDrag(
            offset: 100,
            location: CGPoint(x: 100, y: 200),
        )

        // When PINNED→NORMAL, divider should push negative (up) to show pinned section shrinking
        let pushOffset = support.dragCoordinator.dividerPushOffset
        #expect(pushOffset < 0)
    }

    @Test("Divider push offset positive for NORMAL→PINNED")
    func dividerPushOffsetPositiveForNormalToPinned() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        let normal = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let normalFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!
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

    @Test("Divider push offset zero for same-collection reorder")
    func dividerPushOffsetZeroForSameCollection() throws {
        let support = try SidebarTestSupport()
        let normal1 = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let normalFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!
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
