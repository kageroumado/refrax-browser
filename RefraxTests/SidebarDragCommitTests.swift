import Foundation
import Testing

@testable import Refrax

@Suite("Sidebar.DragCoordinator Commit", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragCommitTests {
    @Test("Commit drag reorders tabs")
    func commitDragReordersTabs() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://one.com")
        _ = support.createTab(url: "https://two.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Get actual ordering
        var items = support.layoutManager.pinnedItems + support.layoutManager.normalItems
        let originalFirst = support.layoutManager.normalItems[0]
        let originalSecond = support.layoutManager.normalItems[1]
        let firstTab = originalFirst.tab!

        let originIndex = support.layoutManager.metadata[originalFirst.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let frame = support.dragCoordinator.computedItemFrame(for: originalFirst.id)!
        support.dragCoordinator.startDrag(
            item: .tab(firstTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Drag down by one slot height - location must be within the normal section bounds
        // for drop target detection to work (otherwise it may trigger drop zone logic)
        let tabSlotHeight = Constants.Layout.tabItemHeight + Constants.Layout.tabSpacing
        support.dragCoordinator.updateDrag(
            offset: tabSlotHeight,
            location: CGPoint(x: frame.midX, y: frame.midY + tabSlotHeight),
        )

        let didCommit = support.dragCoordinator.commitDrag()
        #expect(didCommit)

        support.rebuildLayout()
        items = support.layoutManager.normalItems
        let orderedIDs = items.compactMap { $0.tab?.id }

        // After dragging first item down past second, order should be swapped
        #expect(orderedIDs.first == originalSecond.tab?.id)
        #expect(orderedIDs.last == originalFirst.tab?.id)
    }

    @Test("Cancel drag clears offsets and resets state")
    func cancelDragClearsOffsets() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://one.com")
        _ = support.createTab(url: "https://two.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Use actual ordering
        let firstItem = support.layoutManager.normalItems[0]
        let firstTab = firstItem.tab!

        let originIndex = support.layoutManager.metadata[firstItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let frame = support.dragCoordinator.computedItemFrame(for: firstItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(firstTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Drag down within the normal section bounds
        support.dragCoordinator.updateDrag(
            offset: 50,
            location: CGPoint(x: frame.midX, y: frame.midY + 50),
        )

        support.dragCoordinator.cancelDrag()

        #expect(support.dragCoordinator.isAnimatingReturn)
        #expect(support.dragCoordinator.itemPushOffsets.values.allSatisfy { $0 == .zero })
    }
}
