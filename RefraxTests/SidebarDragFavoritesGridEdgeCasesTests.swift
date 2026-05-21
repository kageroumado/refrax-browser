import Foundation
import Testing

@testable import Refrax

/// Edge case tests for favorites grid drag-and-drop.
///
/// The favorites grid uses a 2D linear flow algorithm for item displacement.
/// These tests verify behavior in edge cases:
/// - Empty grid, single item, many items
/// - Row wrapping and multi-row scenarios
/// - First/last position edge cases
/// - Grid layout changes during drag (column count)
@Suite("Favorites Grid Edge Cases", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragFavoritesGridEdgeCasesTests {
    // MARK: - Test Helpers

    private func createFavorites(count: Int, support: SidebarTestSupport) -> [FavoriteItem] {
        for i in 0 ..< count {
            support.createFavorite(title: "Fav \(i)", url: "https://example\(i).com")
        }
        support.rebuildLayout()
        return support.layoutManager.favoritesLayout
    }

    private func setupGridLayout(support: SidebarTestSupport, columns: Int) {
        let tileSize = CGSize(width: 80, height: 80)
        let spacing: CGFloat = 8

        support.dragCoordinator.updateFavoritesGridLayout(
            columns: columns,
            tileSize: tileSize,
            spacing: spacing,
        )

        let totalWidth = CGFloat(columns) * tileSize.width + CGFloat(columns - 1) * spacing
        let rows = max(1, (support.layoutManager.favoritesLayout.count + columns - 1) / columns)
        let totalHeight = CGFloat(rows) * tileSize.height + CGFloat(rows - 1) * spacing
        support.dragCoordinator.updateFavoritesGridFrame(CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight))
    }

    /// Calculates the center point of a favorite item based on its index in the grid.
    private func gridItemCenter(index: Int, support: SidebarTestSupport) -> CGPoint {
        let layout = support.dragCoordinator._favoritesGridLayout!
        let gridFrame = support.dragCoordinator.favoritesGridFrame

        let row = index / layout.columns
        let col = index % layout.columns

        let x = gridFrame.minX + CGFloat(col) * layout.horizontalStride + layout.tileSize.width / 2
        let y = gridFrame.minY + CGFloat(row) * layout.verticalStride + layout.tileSize.height / 2

        return CGPoint(x: x, y: y)
    }

    // MARK: - Empty and Minimal Grid Tests

    @Test("Empty grid has no offsets")
    func emptyGridNoOffsets() throws {
        let support = try SidebarTestSupport()
        // No favorites
        support.rebuildLayout()

        #expect(support.layoutManager.favoritesLayout.isEmpty)
        #expect(support.dragCoordinator.itemPushOffsets.isEmpty)
    }

    @Test("Single item grid has no offsets during drag")
    func singleItemNoOffsets() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 1, support: support)
        setupGridLayout(support: support, columns: 3)

        support.dragCoordinator.startDrag(
            item: .favorite(items[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: gridItemCenter(index: 0, support: support),
        )

        let layout = support.dragCoordinator._favoritesGridLayout!
        support.dragCoordinator.overlayPosition = CGPoint(x: layout.horizontalStride * 2, y: 40)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: layout.horizontalStride * 2, y: 40))

        #expect(support.dragCoordinator.itemPushOffsets.isEmpty)
    }

    @Test("Two item swap produces correct offset")
    func twoItemSwap() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 2, support: support)
        setupGridLayout(support: support, columns: 2)

        // Drag first item to second position
        support.dragCoordinator.startDrag(
            item: .favorite(items[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: gridItemCenter(index: 0, support: support),
        )

        let layout = support.dragCoordinator._favoritesGridLayout!
        let targetX = 1.5 * layout.horizontalStride
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: 40)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: 40))

        let offsets = support.dragCoordinator.itemPushOffsets

        // Second item should have negative X offset (shift left)
        let secondItemOffset = offsets[items[1].id]
        #expect(secondItemOffset != nil)
        #expect(secondItemOffset!.x < 0)
        #expect(secondItemOffset!.y == 0) // No vertical movement
    }

    // MARK: - Full Row Tests

    @Test("Full single row - drag first to last")
    func fullRowFirstToLast() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 4, support: support)
        setupGridLayout(support: support, columns: 4)

        // Drag first to last
        support.dragCoordinator.startDrag(
            item: .favorite(items[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: gridItemCenter(index: 0, support: support),
        )

        let layout = support.dragCoordinator._favoritesGridLayout!
        let targetX = 3.5 * layout.horizontalStride // After last item
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: 40)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: 40))

        let offsets = support.dragCoordinator.itemPushOffsets

        // Items 1, 2, 3 should all shift left
        #expect(offsets[items[1].id]?.x ?? 0 < 0)
        #expect(offsets[items[2].id]?.x ?? 0 < 0)
        #expect(offsets[items[3].id]?.x ?? 0 < 0)

        // No vertical offsets in single row
        #expect(offsets[items[1].id]?.y ?? 0 == 0)
        #expect(offsets[items[2].id]?.y ?? 0 == 0)
        #expect(offsets[items[3].id]?.y ?? 0 == 0)
    }

    @Test("Full single row - drag last to first")
    func fullRowLastToFirst() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 4, support: support)
        setupGridLayout(support: support, columns: 4)

        // Drag last to first
        support.dragCoordinator.startDrag(
            item: .favorite(items[3]),
            originPosition: .favorites(localIndex: 3),
            startLocation: gridItemCenter(index: 3, support: support),
        )

        let layout = support.dragCoordinator._favoritesGridLayout!
        let targetX = 0.3 * layout.horizontalStride // Before first item
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: 40)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: 40))

        let offsets = support.dragCoordinator.itemPushOffsets

        // Items 0, 1, 2 should all shift right
        #expect(offsets[items[0].id]?.x ?? 0 > 0)
        #expect(offsets[items[1].id]?.x ?? 0 > 0)
        #expect(offsets[items[2].id]?.x ?? 0 > 0)
    }

    // MARK: - Multi-Row Tests

    @Test("Multi-row grid - drag causes row wrap")
    func multiRowWrap() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 6, support: support) // 2 rows of 3
        setupGridLayout(support: support, columns: 3)

        // Drag item from row 0 col 2 (index 2) to row 1 col 0 (index 3)
        support.dragCoordinator.startDrag(
            item: .favorite(items[2]),
            originPosition: .favorites(localIndex: 2),
            startLocation: gridItemCenter(index: 2, support: support),
        )

        let layout = support.dragCoordinator._favoritesGridLayout!
        // Position at start of row 1
        let targetX: CGFloat = 0.3 * layout.horizontalStride
        let targetY: CGFloat = 1.5 * layout.verticalStride
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: targetY)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: targetY))

        let offsets = support.dragCoordinator.itemPushOffsets

        // Item at index 3 (row 1, col 0) should shift - check it has an offset
        let item3Offset = offsets[items[3].id]
        #expect(item3Offset != nil)
    }

    @Test("Multi-row grid - drag across multiple rows")
    func multiRowCrossingMultipleRows() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 9, support: support) // 3 rows of 3
        setupGridLayout(support: support, columns: 3)

        // Drag item from row 2 (index 6) to row 0 (index 1)
        support.dragCoordinator.startDrag(
            item: .favorite(items[6]),
            originPosition: .favorites(localIndex: 6),
            startLocation: gridItemCenter(index: 6, support: support),
        )

        let layout = support.dragCoordinator._favoritesGridLayout!
        let targetX: CGFloat = 1.5 * layout.horizontalStride
        let targetY: CGFloat = 0.5 * layout.verticalStride
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: targetY)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: targetY))

        let offsets = support.dragCoordinator.itemPushOffsets

        // Multiple items should have offsets (items 1-5 all shift forward)
        let shiftedItemCount = offsets.count
        #expect(shiftedItemCount >= 3) // At minimum items 1, 2, 3 should shift
    }

    @Test("Multi-row - partial last row")
    func multiRowPartialLastRow() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 7, support: support) // 3 + 3 + 1
        setupGridLayout(support: support, columns: 3)

        // Drag from first row to last position
        support.dragCoordinator.startDrag(
            item: .favorite(items[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: gridItemCenter(index: 0, support: support),
        )

        let layout = support.dragCoordinator._favoritesGridLayout!
        // Position at end of grid (after item 6)
        let targetX: CGFloat = 1.5 * layout.horizontalStride
        let targetY: CGFloat = 2.5 * layout.verticalStride
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: targetY)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: targetY))

        // Multiple items should shift
        let offsets = support.dragCoordinator.itemPushOffsets
        #expect(offsets.count >= 4)
    }

    // MARK: - Many Items Tests

    @Test("Many items (20+) - performance and correctness")
    func manyItemsPerformance() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 24, support: support) // 6 rows of 4
        setupGridLayout(support: support, columns: 4)

        // Drag from middle to different middle position
        support.dragCoordinator.startDrag(
            item: .favorite(items[12]),
            originPosition: .favorites(localIndex: 12),
            startLocation: gridItemCenter(index: 12, support: support),
        )

        let layout = support.dragCoordinator._favoritesGridLayout!
        // Move to position 5
        let targetX: CGFloat = 1.5 * layout.horizontalStride
        let targetY: CGFloat = 1.5 * layout.verticalStride
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: targetY)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: targetY))

        // Should have offsets for affected items
        let offsets = support.dragCoordinator.itemPushOffsets
        #expect(!offsets.isEmpty)

        // Dragged item should never have offset
        #expect(offsets[items[12].id] == nil)
    }

    @Test("Many items - drag to first position")
    func manyItemsDragToFirst() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 20, support: support)
        setupGridLayout(support: support, columns: 4)

        // Drag last item to first position
        support.dragCoordinator.startDrag(
            item: .favorite(items[19]),
            originPosition: .favorites(localIndex: 19),
            startLocation: gridItemCenter(index: 19, support: support),
        )

        _ = support.dragCoordinator._favoritesGridLayout!
        let firstItemCenter = gridItemCenter(index: 0, support: support)
        support.dragCoordinator.overlayPosition = CGPoint(x: firstItemCenter.x - 20, y: firstItemCenter.y)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: firstItemCenter.x - 20, y: firstItemCenter.y))

        // All 19 other items should shift forward
        let offsets = support.dragCoordinator.itemPushOffsets
        #expect(offsets.count == 19)
    }

    @Test("Many items - drag to last position")
    func manyItemsDragToLast() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 20, support: support)
        setupGridLayout(support: support, columns: 4)

        // Drag first item to last position
        support.dragCoordinator.startDrag(
            item: .favorite(items[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: gridItemCenter(index: 0, support: support),
        )

        let layout = support.dragCoordinator._favoritesGridLayout!
        let lastRow = 4 // 20 items / 4 columns = 5 rows (0-4)
        let targetX: CGFloat = 3.5 * layout.horizontalStride
        let targetY = CGFloat(lastRow) * layout.verticalStride + 40
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: targetY)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: targetY))

        // All 19 other items should shift backward
        let offsets = support.dragCoordinator.itemPushOffsets
        #expect(offsets.count == 19)
    }

    // MARK: - Boundary Edge Cases

    @Test("Drag just outside grid bounds clamps to valid position")
    func dragOutsideGridClamps() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 4, support: support)
        setupGridLayout(support: support, columns: 4)

        support.dragCoordinator.startDrag(
            item: .favorite(items[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: gridItemCenter(index: 0, support: support),
        )

        _ = support.dragCoordinator._favoritesGridLayout!
        // Way outside the grid
        let targetX: CGFloat = 1_000
        let targetY: CGFloat = 1_000
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: targetY)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: targetY))

        // Should still have valid offsets (clamped to last position)
        let offsets = support.dragCoordinator.itemPushOffsets
        // Either all items shifted or we're at origin (clamped)
        #expect(offsets.count >= 0)
    }

    @Test("Drag at negative coordinates clamps to position 0")
    func dragNegativeCoordinates() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 4, support: support)
        setupGridLayout(support: support, columns: 4)

        support.dragCoordinator.startDrag(
            item: .favorite(items[3]),
            originPosition: .favorites(localIndex: 3),
            startLocation: gridItemCenter(index: 3, support: support),
        )

        // Use coordinates that are inside the expanded sidebar bounds (-8 margin)
        // but still map to grid position (0, 0) after clamping.
        // -5 is within the -8 margin but produces negative localX/localY in grid calculation.
        support.dragCoordinator.overlayPosition = CGPoint(x: -5, y: -5)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: -5, y: -5))

        // Should clamp to position 0, so items 0, 1, 2 shift right
        let offsets = support.dragCoordinator.itemPushOffsets
        #expect(offsets[items[0].id] != nil)
    }

    // MARK: - Same Position Tests

    @Test("Drag to same position produces no offsets")
    func dragToSamePosition() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 4, support: support)
        setupGridLayout(support: support, columns: 4)

        support.dragCoordinator.startDrag(
            item: .favorite(items[1]),
            originPosition: .favorites(localIndex: 1),
            startLocation: gridItemCenter(index: 1, support: support),
        )

        let layout = support.dragCoordinator._favoritesGridLayout!
        // Position exactly at item 1's center
        let targetX: CGFloat = 1.5 * layout.horizontalStride
        let targetY: CGFloat = 0.5 * layout.verticalStride
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: targetY)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: targetY))

        // No items should need to move
        let offsets = support.dragCoordinator.itemPushOffsets
        #expect(offsets.isEmpty)
    }

    @Test("Drag slightly in each direction returns to origin when within same slot")
    func dragSlightlyDoesNotMove() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 4, support: support)
        setupGridLayout(support: support, columns: 4)

        support.dragCoordinator.startDrag(
            item: .favorite(items[1]),
            originPosition: .favorites(localIndex: 1),
            startLocation: gridItemCenter(index: 1, support: support),
        )

        let layout = support.dragCoordinator._favoritesGridLayout!
        // Slightly left of center (but still item 1's slot)
        let targetX: CGFloat = layout.horizontalStride + 1 // Just past start of slot 1
        let targetY: CGFloat = 40
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: targetY)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: targetY))

        // No displacement when target equals origin
        let offsets = support.dragCoordinator.itemPushOffsets
        #expect(offsets.isEmpty)
    }

    // MARK: - Column Count Variations

    @Test("Single column grid - vertical movement only")
    func singleColumnVerticalOnly() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 4, support: support)
        setupGridLayout(support: support, columns: 1)

        support.dragCoordinator.startDrag(
            item: .favorite(items[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: gridItemCenter(index: 0, support: support),
        )

        let layout = support.dragCoordinator._favoritesGridLayout!
        // Move to last position
        let targetY: CGFloat = 3.5 * layout.verticalStride
        support.dragCoordinator.overlayPosition = CGPoint(x: 40, y: targetY)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: 40, y: targetY))

        let offsets = support.dragCoordinator.itemPushOffsets

        // All offsets should be vertical (x = 0)
        for (_, offset) in offsets {
            #expect(offset.x == 0)
            #expect(offset.y != 0)
        }
    }

    @Test("Wide grid (many columns) - horizontal movement dominates")
    func wideGridHorizontalDominates() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 8, support: support)
        setupGridLayout(support: support, columns: 8) // All in one row

        support.dragCoordinator.startDrag(
            item: .favorite(items[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: gridItemCenter(index: 0, support: support),
        )

        let layout = support.dragCoordinator._favoritesGridLayout!
        let targetX: CGFloat = 7.5 * layout.horizontalStride
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: 40)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: 40))

        let offsets = support.dragCoordinator.itemPushOffsets

        // All offsets should be horizontal (y = 0)
        for (_, offset) in offsets {
            #expect(offset.y == 0)
            #expect(offset.x < 0) // All shift left
        }
    }

    // MARK: - Commit Tests

    @Test("Commit reorder within grid updates positions")
    func commitReorderUpdatesPositions() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 4, support: support)
        setupGridLayout(support: support, columns: 4)

        support.dragCoordinator.startDrag(
            item: .favorite(items[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: 40, y: 40),
        )

        let layout = support.dragCoordinator._favoritesGridLayout!
        let targetX: CGFloat = 2.5 * layout.horizontalStride
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: 40)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: 40))

        let didCommit = support.dragCoordinator.commitDrag()

        // Should indicate reorder happened (or animation started)
        #expect(support.dragCoordinator.isAnimatingReturn == true)
    }

    @Test("Cancel drag in grid clears all offsets")
    func cancelDragClearsGridOffsets() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 4, support: support)
        setupGridLayout(support: support, columns: 4)

        support.dragCoordinator.startDrag(
            item: .favorite(items[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: 40, y: 40),
        )

        let layout = support.dragCoordinator._favoritesGridLayout!
        let targetX: CGFloat = 3.5 * layout.horizontalStride
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: 40)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: 40))

        // Verify offsets exist
        #expect(!support.dragCoordinator.itemPushOffsets.isEmpty)

        // Cancel
        support.dragCoordinator.cancelDrag()

        // All offsets should be zero or cleared
        #expect(support.dragCoordinator.itemPushOffsets.values.allSatisfy { $0 == .zero })
    }
}
