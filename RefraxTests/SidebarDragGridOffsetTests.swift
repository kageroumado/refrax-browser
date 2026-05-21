import Foundation
import Testing

@testable import Refrax

@Suite("Grid Offset Calculations", .tags(.sidebarDragCoordinator))
@MainActor
struct SidebarDragGridOffsetTests {
    // MARK: - Test Helpers

    /// Creates mock favorite items for testing grid offset calculations.
    ///
    /// Uses the test support to create real favorites through the BookmarksManager.
    private func createMockItems(count: Int, support: SidebarTestSupport) -> [FavoriteItem] {
        for i in 0 ..< count {
            support.createFavorite(title: "Item \(i)", url: "https://example\(i).com")
        }
        support.rebuildLayout()
        return support.layoutManager.favoritesLayout
    }

    /// Standard grid layout for tests: 4 columns, 80x80 tiles, 8px spacing.
    private var standardLayout: Sidebar.DragCoordinator.GridLayoutInfo {
        Sidebar.DragCoordinator.GridLayoutInfo(
            columns: 4,
            tileSize: CGSize(width: 80, height: 80),
            spacing: 8,
        )
    }

    // MARK: - GridPosition Tests

    @Test("GridPosition converts to linear index correctly")
    func gridPositionToLinearIndex() {
        let pos = Sidebar.DragCoordinator.GridPosition(row: 1, column: 2)
        #expect(pos.toLinearIndex(columns: 4) == 6) // 1*4 + 2 = 6

        let pos2 = Sidebar.DragCoordinator.GridPosition(row: 0, column: 0)
        #expect(pos2.toLinearIndex(columns: 4) == 0)

        let pos3 = Sidebar.DragCoordinator.GridPosition(row: 2, column: 3)
        #expect(pos3.toLinearIndex(columns: 4) == 11) // 2*4 + 3 = 11
    }

    @Test("GridPosition converts from linear index correctly")
    func gridPositionFromLinearIndex() {
        let pos = Sidebar.DragCoordinator.GridPosition.fromLinearIndex(6, columns: 4)
        #expect(pos.row == 1)
        #expect(pos.column == 2)

        let pos2 = Sidebar.DragCoordinator.GridPosition.fromLinearIndex(0, columns: 4)
        #expect(pos2.row == 0)
        #expect(pos2.column == 0)

        let pos3 = Sidebar.DragCoordinator.GridPosition.fromLinearIndex(11, columns: 4)
        #expect(pos3.row == 2)
        #expect(pos3.column == 3)
    }

    // MARK: - Single Row Tests

    @Test("Single row: drag first to last")
    func singleRowDragFirstToLast() throws {
        // [A B C D] -> [B C D A]
        // A drags from 0 to 3
        // B, C, D should each shift left by one tile width
        let support = try SidebarTestSupport()
        let items = createMockItems(count: 4, support: support)
        let layout = standardLayout

        let offsets = support.dragCoordinator.computeGridOffsets(
            items: items,
            draggedIndex: 0,
            targetIndex: 3,
            layout: layout,
        )

        let expectedShift = -layout.horizontalStride // Shift left

        // Items 1, 2, 3 (B, C, D) should shift left
        #expect(offsets[items[1].id] == CGPoint(x: expectedShift, y: 0))
        #expect(offsets[items[2].id] == CGPoint(x: expectedShift, y: 0))
        #expect(offsets[items[3].id] == CGPoint(x: expectedShift, y: 0))

        // Item 0 (A) is dragged, should not have offset
        #expect(offsets[items[0].id] == nil)
    }

    @Test("Single row: drag last to first")
    func singleRowDragLastToFirst() throws {
        // [A B C D] -> [D A B C]
        // D drags from 3 to 0
        // A, B, C should each shift right by one tile width
        let support = try SidebarTestSupport()
        let items = createMockItems(count: 4, support: support)
        let layout = standardLayout

        let offsets = support.dragCoordinator.computeGridOffsets(
            items: items,
            draggedIndex: 3,
            targetIndex: 0,
            layout: layout,
        )

        let expectedShift = layout.horizontalStride // Shift right

        // Items 0, 1, 2 (A, B, C) should shift right
        #expect(offsets[items[0].id] == CGPoint(x: expectedShift, y: 0))
        #expect(offsets[items[1].id] == CGPoint(x: expectedShift, y: 0))
        #expect(offsets[items[2].id] == CGPoint(x: expectedShift, y: 0))

        // Item 3 (D) is dragged, should not have offset
        #expect(offsets[items[3].id] == nil)
    }

    // MARK: - Multi-Row Tests

    @Test("Multi-row: drag causes row wrap")
    func multiRowWrap() throws {
        // 3 columns:
        // [A B C]    ->    [A B D]
        // [D E F]          [C E F]
        // C drags from 2 to 3
        // D shifts from (1,0) to (0,2): wraps to previous row
        let support = try SidebarTestSupport()
        let items = createMockItems(count: 6, support: support)
        let layout = Sidebar.DragCoordinator.GridLayoutInfo(
            columns: 3,
            tileSize: CGSize(width: 80, height: 80),
            spacing: 8,
        )

        let offsets = support.dragCoordinator.computeGridOffsets(
            items: items,
            draggedIndex: 2, // C at position 2
            targetIndex: 3, // Move to position 3
            layout: layout,
        )

        // Item 3 (D) shifts backward by one position: index 3 -> index 2
        // D is at (1,0) [row 1, col 0], shifts to (0,2) [row 0, col 2]
        // dx = (2 - 0) * stride = 2 * stride (wraps right)
        // dy = (0 - 1) * stride = -stride (moves up one row)
        let expectedOffset = CGPoint(
            x: 2 * layout.horizontalStride, // Wrap to column 2 from column 0
            y: -layout.verticalStride, // Move up one row
        )

        // Item 3 (D) shifts backward by one with row wrap
        #expect(offsets[items[3].id] == expectedOffset)

        // Items before dragged (0, 1) and items after target (4, 5) should not move
        #expect(offsets[items[0].id] == nil)
        #expect(offsets[items[1].id] == nil)
        #expect(offsets[items[4].id] == nil)
        #expect(offsets[items[5].id] == nil)
    }

    @Test("Multi-row: drag across multiple rows")
    func multiRowCrossing() throws {
        // 3 columns:
        // [A B C]    ->    [A B C]
        // [D E F]          [G D E]
        // [G H I]          [F H I]
        // G drags from 6 to 3
        // D, E, F each shift forward by one position (with row wrap)
        let support = try SidebarTestSupport()
        let items = createMockItems(count: 9, support: support)
        let layout = Sidebar.DragCoordinator.GridLayoutInfo(
            columns: 3,
            tileSize: CGSize(width: 80, height: 80),
            spacing: 8,
        )

        let offsets = support.dragCoordinator.computeGridOffsets(
            items: items,
            draggedIndex: 6, // G at position 6
            targetIndex: 3, // Move to position 3
            layout: layout,
        )

        // D (index 3) shifts from (1,0) to (1,1): dx = stride, dy = 0
        #expect(offsets[items[3].id] == CGPoint(x: layout.horizontalStride, y: 0))

        // E (index 4) shifts from (1,1) to (1,2): dx = stride, dy = 0
        #expect(offsets[items[4].id] == CGPoint(x: layout.horizontalStride, y: 0))

        // F (index 5) shifts from (1,2) to (2,0): dx = -2*stride, dy = stride (wrap)
        let expectedFOffset = CGPoint(
            x: -2 * layout.horizontalStride,
            y: layout.verticalStride,
        )
        #expect(offsets[items[5].id] == expectedFOffset)

        // Items before target (0, 1, 2) and after dragged (7, 8) should not move
        #expect(offsets[items[0].id] == nil)
        #expect(offsets[items[1].id] == nil)
        #expect(offsets[items[2].id] == nil)
        #expect(offsets[items[7].id] == nil)
        #expect(offsets[items[8].id] == nil)
    }

    // MARK: - Edge Cases

    @Test("Edge: drag to position 0")
    func dragToFirstPosition() throws {
        // [A B C D] -> [D A B C]
        // D drags from 3 to 0
        // All items before 3 shift forward
        let support = try SidebarTestSupport()
        let items = createMockItems(count: 4, support: support)
        let layout = standardLayout

        let offsets = support.dragCoordinator.computeGridOffsets(
            items: items,
            draggedIndex: 3,
            targetIndex: 0,
            layout: layout,
        )

        // All items 0, 1, 2 should shift right
        #expect(offsets[items[0].id] == CGPoint(x: layout.horizontalStride, y: 0))
        #expect(offsets[items[1].id] == CGPoint(x: layout.horizontalStride, y: 0))
        #expect(offsets[items[2].id] == CGPoint(x: layout.horizontalStride, y: 0))
    }

    @Test("Edge: drag to last position")
    func dragToLastPosition() throws {
        // [A B C D] -> [B C D A]
        // A drags from 0 to 3
        // All items after 0 shift backward
        let support = try SidebarTestSupport()
        let items = createMockItems(count: 4, support: support)
        let layout = standardLayout

        let offsets = support.dragCoordinator.computeGridOffsets(
            items: items,
            draggedIndex: 0,
            targetIndex: 3,
            layout: layout,
        )

        // All items 1, 2, 3 should shift left
        #expect(offsets[items[1].id] == CGPoint(x: -layout.horizontalStride, y: 0))
        #expect(offsets[items[2].id] == CGPoint(x: -layout.horizontalStride, y: 0))
        #expect(offsets[items[3].id] == CGPoint(x: -layout.horizontalStride, y: 0))
    }

    @Test("Edge: single item grid")
    func singleItemGrid() throws {
        // No offsets needed, item stays in place
        let support = try SidebarTestSupport()
        let items = createMockItems(count: 1, support: support)
        let layout = standardLayout

        let offsets = support.dragCoordinator.computeGridOffsets(
            items: items,
            draggedIndex: 0,
            targetIndex: 0,
            layout: layout,
        )

        #expect(offsets.isEmpty)
    }

    @Test("Edge: two items swap")
    func twoItemSwap() throws {
        // [A B] -> [B A]
        // A drags from 0 to 1
        // B should shift left by one
        let support = try SidebarTestSupport()
        let items = createMockItems(count: 2, support: support)
        let layout = standardLayout

        let offsets = support.dragCoordinator.computeGridOffsets(
            items: items,
            draggedIndex: 0,
            targetIndex: 1,
            layout: layout,
        )

        #expect(offsets[items[1].id] == CGPoint(x: -layout.horizontalStride, y: 0))
        #expect(offsets[items[0].id] == nil) // Dragged item
    }

    @Test("Edge: no movement when target equals origin")
    func noMovementWhenSamePosition() throws {
        let support = try SidebarTestSupport()
        let items = createMockItems(count: 4, support: support)
        let layout = standardLayout

        let offsets = support.dragCoordinator.computeGridOffsets(
            items: items,
            draggedIndex: 2,
            targetIndex: 2,
            layout: layout,
        )

        #expect(offsets.isEmpty)
    }

    // MARK: - Insertion Intent Tests

    @Test("Insertion intent: horizontal flow, cursor left of centroid")
    func insertionIntentHorizontalBefore() throws {
        let support = try SidebarTestSupport()

        let intent = support.dragCoordinator.determineInsertionIntent(
            cursorPosition: CGPoint(x: 30, y: 50),
            targetCentroid: CGPoint(x: 50, y: 50),
            isHorizontalFlow: true,
        )

        #expect(intent == .before)
    }

    @Test("Insertion intent: horizontal flow, cursor right of centroid")
    func insertionIntentHorizontalAfter() throws {
        let support = try SidebarTestSupport()

        let intent = support.dragCoordinator.determineInsertionIntent(
            cursorPosition: CGPoint(x: 70, y: 50),
            targetCentroid: CGPoint(x: 50, y: 50),
            isHorizontalFlow: true,
        )

        #expect(intent == .after)
    }

    @Test("Insertion intent: vertical flow, cursor above centroid")
    func insertionIntentVerticalBefore() throws {
        let support = try SidebarTestSupport()

        let intent = support.dragCoordinator.determineInsertionIntent(
            cursorPosition: CGPoint(x: 50, y: 30),
            targetCentroid: CGPoint(x: 50, y: 50),
            isHorizontalFlow: false,
        )

        #expect(intent == .before)
    }

    @Test("Insertion intent: vertical flow, cursor below centroid")
    func insertionIntentVerticalAfter() throws {
        let support = try SidebarTestSupport()

        let intent = support.dragCoordinator.determineInsertionIntent(
            cursorPosition: CGPoint(x: 50, y: 70),
            targetCentroid: CGPoint(x: 50, y: 50),
            isHorizontalFlow: false,
        )

        #expect(intent == .after)
    }

    // MARK: - Easing Tests

    @Test("Offset applies smoothstep easing at 0%")
    func offsetEasingAtZero() throws {
        let support = try SidebarTestSupport()
        let offsets: [UUID: CGPoint] = [
            UUID(): CGPoint(x: 100, y: 50),
        ]

        let eased = support.dragCoordinator.applyGridOffsetEasing(offsets: offsets, progress: 0)

        for (_, offset) in eased {
            #expect(offset == .zero)
        }
    }

    @Test("Offset applies smoothstep easing at 100%")
    func offsetEasingAtFull() throws {
        let support = try SidebarTestSupport()
        let testID = UUID()
        let offsets: [UUID: CGPoint] = [
            testID: CGPoint(x: 100, y: 50),
        ]

        let eased = support.dragCoordinator.applyGridOffsetEasing(offsets: offsets, progress: 1.0)

        #expect(eased[testID] == CGPoint(x: 100, y: 50))
    }

    @Test("Offset applies smoothstep easing at 50%")
    func offsetEasingAtHalf() throws {
        let support = try SidebarTestSupport()
        let testID = UUID()
        let offsets: [UUID: CGPoint] = [
            testID: CGPoint(x: 100, y: 100),
        ]

        let eased = support.dragCoordinator.applyGridOffsetEasing(offsets: offsets, progress: 0.5)

        // smoothstep(0.5) = 0.5 (exactly at midpoint)
        #expect(eased[testID] == CGPoint(x: 50, y: 50))
    }

    @Test("Offset applies smoothstep easing with characteristic curve")
    func offsetEasingSmoothstepCurve() throws {
        let support = try SidebarTestSupport()
        let testID = UUID()
        let offsets: [UUID: CGPoint] = [
            testID: CGPoint(x: 100, y: 0),
        ]

        // Test characteristic smoothstep values
        // smoothstep(0.25) = 0.15625
        // smoothstep(0.75) = 0.84375
        let eased25 = support.dragCoordinator.applyGridOffsetEasing(offsets: offsets, progress: 0.25)
        let eased75 = support.dragCoordinator.applyGridOffsetEasing(offsets: offsets, progress: 0.75)

        #expect(abs(eased25[testID]!.x - 15.625) < 0.01)
        #expect(abs(eased75[testID]!.x - 84.375) < 0.01)
    }
}
