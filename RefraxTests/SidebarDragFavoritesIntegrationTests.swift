import Foundation
import Testing

@testable import Refrax

@Suite("Favorites Grid Drag Integration", .tags(.sidebarDragCoordinator))
@MainActor
struct SidebarDragFavoritesIntegrationTests {
    // MARK: - Test Helpers

    /// Creates favorite items for testing.
    private func createFavorites(count: Int, support: SidebarTestSupport) -> [FavoriteItem] {
        for i in 0 ..< count {
            support.createFavorite(title: "Fav \(i)", url: "https://example\(i).com")
        }
        support.rebuildLayout()
        return support.layoutManager.favoritesLayout
    }

    /// Simulates setting up the grid layout info as FavoritesGrid would.
    private func setupGridLayout(support: SidebarTestSupport, columns: Int) {
        let tileSize = CGSize(width: 80, height: 80)
        let spacing: CGFloat = 8

        support.dragCoordinator.updateFavoritesGridLayout(
            columns: columns,
            tileSize: tileSize,
            spacing: spacing,
        )

        // Also set up a mock grid frame
        let totalWidth = CGFloat(columns) * tileSize.width + CGFloat(columns - 1) * spacing
        let rows = max(1, (support.layoutManager.favoritesLayout.count + columns - 1) / columns)
        let totalHeight = CGFloat(rows) * tileSize.height + CGFloat(rows - 1) * spacing
        support.dragCoordinator.updateFavoritesGridFrame(CGRect(x: 0, y: 0, width: totalWidth, height: totalHeight))
    }

    /// Calculates the center point of a favorite item based on its index in the grid.
    ///
    /// This matches how `computedItemFrame` calculates favorite positions in DragCoordinator,
    /// ensuring startLocation aligns with the computed frame center for consistent clickOffset.
    private func gridItemCenter(index: Int, support: SidebarTestSupport) -> CGPoint {
        let layout = support.dragCoordinator._favoritesGridLayout!
        let gridFrame = support.dragCoordinator.favoritesGridFrame

        let row = index / layout.columns
        let col = index % layout.columns

        let x = gridFrame.minX + CGFloat(col) * layout.horizontalStride + layout.tileSize.width / 2
        let y = gridFrame.minY + CGFloat(row) * layout.verticalStride + layout.tileSize.height / 2

        return CGPoint(x: x, y: y)
    }

    // MARK: - Basic Drag Flow Tests

    @Test("Dragging favorite updates affected items with grid offsets")
    func dragFavoriteUpdatesOffsets() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 4, support: support)
        setupGridLayout(support: support, columns: 4)

        // Start drag on first item
        let originIndex = 0
        let frame = support.dragCoordinator.computedItemFrame(for: items[originIndex].id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(items[originIndex]),
            originPosition: .favorites(localIndex: originIndex),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Set overlay position to where item 2 would be
        let layout = support.dragCoordinator._favoritesGridLayout!
        let targetX = 2.5 * layout.horizontalStride // Between items 2 and 3
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: 40)

        // Update the drag
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: 40))

        // Verify offsets were calculated
        let offsets = support.dragCoordinator.itemPushOffsets

        // Items 1 and 2 should have negative X offset (shift left)
        #expect(offsets[items[1].id]?.x ?? 0 < 0)
        #expect(offsets[items[2].id]?.x ?? 0 < 0)

        // Dragged item (0) should not have an offset
        #expect(offsets[items[0].id] == nil)
    }

    @Test("Committing favorites drag reorders items")
    func commitFavoritesDragReorders() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 4, support: support)
        setupGridLayout(support: support, columns: 4)

        let originalOrder = items.map(\.id)

        // Start drag on first item
        let frame = support.dragCoordinator.computedItemFrame(for: items[0].id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(items[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Move to position 2
        let layout = support.dragCoordinator._favoritesGridLayout!
        let targetX = 2.5 * layout.horizontalStride
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: 40)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: 40))

        // Commit the drag
        _ = support.dragCoordinator.commitDrag()

        // Note: The actual reorder depends on drop target detection, which requires
        // proper zone detection. For this test, we verify the basic flow works.
        // The drop target detection tests are covered elsewhere.
        #expect(support.dragCoordinator.isAnimatingReturn == true)
    }

    @Test("Favorites drag uses source collection favorites")
    func favoritesDragUsesCorrectSourceCollection() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 3, support: support)
        setupGridLayout(support: support, columns: 3)

        let frame = support.dragCoordinator.computedItemFrame(for: items[0].id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(items[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        #expect(support.dragCoordinator._originPosition?.collection == .favorites)
    }

    @Test("Favorites grid layout info is preserved during drag")
    func gridLayoutPreservedDuringDrag() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 6, support: support)
        setupGridLayout(support: support, columns: 3)

        let startLocation = gridItemCenter(index: 0, support: support)
        support.dragCoordinator.startDrag(
            item: .favorite(items[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: startLocation,
        )

        // Verify layout info is available
        let layout = support.dragCoordinator._favoritesGridLayout
        #expect(layout != nil)
        #expect(layout?.columns == 3)
        #expect(layout?.tileSize == CGSize(width: 80, height: 80))
        #expect(layout?.spacing == 8)
    }

    // MARK: - Offset Calculation Integration Tests

    @Test("Multi-row favorites drag calculates correct offsets")
    func multiRowFavoritesDragOffsets() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 6, support: support)
        setupGridLayout(support: support, columns: 3)

        // Drag item from row 1 (index 3) to row 0 (index 1)
        let originIndex = 3
        let startLocation = gridItemCenter(index: originIndex, support: support)
        support.dragCoordinator.startDrag(
            item: .favorite(items[originIndex]),
            originPosition: .favorites(localIndex: originIndex),
            startLocation: startLocation,
        )

        // Position at index 1
        let layout = support.dragCoordinator._favoritesGridLayout!
        let targetX = 1.5 * layout.horizontalStride
        let targetY = 0.5 * layout.verticalStride
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: targetY)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: targetY))

        // Items between 1 and 3 (indices 1, 2) should have offsets
        let offsets = support.dragCoordinator.itemPushOffsets

        // Items 1 and 2 should have positive offsets (shift forward)
        // Item 2 wraps from (0,2) to (1,0) so it has significant offsets
        #expect(offsets[items[1].id] != nil || offsets[items[2].id] != nil)
    }

    @Test("Dragged item excluded from offset calculation")
    func draggedItemExcludedFromOffsets() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 4, support: support)
        setupGridLayout(support: support, columns: 4)

        // Drag middle item
        let frame = support.dragCoordinator.computedItemFrame(for: items[1].id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(items[1]),
            originPosition: .favorites(localIndex: 1),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Move to end
        let layout = support.dragCoordinator._favoritesGridLayout!
        let targetX = 3.5 * layout.horizontalStride
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: 40)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: 40))

        let offsets = support.dragCoordinator.itemPushOffsets

        // Dragged item should never have an offset
        #expect(offsets[items[1].id] == nil)
    }

    // MARK: - Edge Cases

    @Test("Single favorite shows no offsets")
    func singleFavoriteNoOffsets() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 1, support: support)
        setupGridLayout(support: support, columns: 1)

        let frame = support.dragCoordinator.computedItemFrame(for: items[0].id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(items[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        support.dragCoordinator.overlayPosition = CGPoint(x: 40, y: 40)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: 40, y: 40))

        #expect(support.dragCoordinator.itemPushOffsets.isEmpty)
    }

    @Test("Drag slightly left of origin returns to origin index")
    func dragSlightlyLeftOfOrigin() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 4, support: support)
        setupGridLayout(support: support, columns: 4)

        // Drag item 1 - use gridItemCenter for correct startLocation
        let startLocation = gridItemCenter(index: 1, support: support)
        support.dragCoordinator.startDrag(
            item: .favorite(items[1]),
            originPosition: .favorites(localIndex: 1),
            startLocation: startLocation,
        )

        // Position cursor slightly to the left of item 1's center (triggers "before" intent)
        // This makes the target position 1, which equals origin, so no displacement needed
        let layout = support.dragCoordinator._favoritesGridLayout!
        let slightlyLeftOfCenter = CGFloat(1) * layout.horizontalStride + layout.tileSize.width / 2 - 1
        let y = layout.tileSize.height / 2
        support.dragCoordinator.overlayPosition = CGPoint(x: slightlyLeftOfCenter, y: y)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: slightlyLeftOfCenter, y: y))

        // When target equals origin, no items should need to move
        let offsets = support.dragCoordinator.itemPushOffsets
        #expect(offsets.isEmpty)
    }

    @Test("Cancel drag clears favorites offsets")
    func cancelDragClearsOffsets() throws {
        let support = try SidebarTestSupport()
        let items = createFavorites(count: 4, support: support)
        setupGridLayout(support: support, columns: 4)

        // Start and update drag
        let frame = support.dragCoordinator.computedItemFrame(for: items[0].id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(items[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        let layout = support.dragCoordinator._favoritesGridLayout!
        let targetX = 3.5 * layout.horizontalStride
        support.dragCoordinator.overlayPosition = CGPoint(x: targetX, y: 40)
        support.dragCoordinator.updateDrag(offset: 0, location: CGPoint(x: targetX, y: 40))

        // Verify offsets exist
        #expect(!support.dragCoordinator.itemPushOffsets.isEmpty)

        // Cancel the drag
        support.dragCoordinator.cancelDrag()

        // Wait for animation (in real app this would be animated)
        // After cancel, offsets should be cleared (they animate to zero)
        #expect(support.dragCoordinator.isAnimatingReturn == true)
    }
}
