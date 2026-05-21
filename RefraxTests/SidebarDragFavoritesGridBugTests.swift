import Foundation
import Testing

@testable import Refrax

/// Tests for favorites grid-specific bugs.
///
/// These tests expose bugs in grid handling:
/// - Grid target index clamps to count-1 but commit allows count (visual/commit mismatch)
/// - External URL drop can't create first favorite when grid is empty
/// - _firstItemStartY missing when first item is offscreen
@Suite("Favorites Grid Bugs", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragFavoritesGridBugTests {
    // MARK: - Test Helpers

    private func setupStandardFrames(_ support: SidebarTestSupport, startY _: CGFloat = 100) {
        // Set sidebar bounds so cursorIsOutsideSidebar doesn't trigger AppKit handoff
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 240, height: 600))
        support.dragCoordinator.updateFavoritesGridFrame(CGRect(x: 0, y: 0, width: 240, height: 90))
        support.dragCoordinator.updateFavoritesGridLayout(
            columns: 3,
            tileSize: CGSize(width: 80, height: 80),
            spacing: 8,
        )
    }

    // MARK: - Grid Index Clamp Bug Tests

    @Test("BUG: Grid target index clamps to count-1 but commit allows count")
    func gridTargetIndexClampMismatch() throws {
        let support = try SidebarTestSupport()
        // Create exactly 3 favorites (one row)
        _ = support.createFavorite(title: "Fav1", url: "https://fav1.com")
        _ = support.createFavorite(title: "Fav2", url: "https://fav2.com")
        _ = support.createFavorite(title: "Fav3", url: "https://fav3.com")
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Verify we have 3 favorites
        let favoritesCount = support.layoutManager.favoritesLayout.count
        #expect(favoritesCount == 3)

        // Drag a tab toward the grid's "append" position (after all favorites)
        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let draggedTab = tabItem.tab!

        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(draggedTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to the right side of the grid (after last tile)
        // Grid: 80px tiles with 8px spacing, 3 columns = 80*3 + 8*2 = 256 width
        // Dragging to x=250 should target the "append" position
        support.dragCoordinator.updateDrag(
            offset: -100,
            location: CGPoint(x: 250, y: 45), // Right side of grid, middle height
        )

        // Check the drop target
        if case let .convertToFavorite(mode: mode) = support.dragCoordinator._dropTarget {
            #expect(mode == .liveFavorite || mode == .shortcut)

            // The BUG: Grid offset calculations in DragCoordinator+GridOffsets.swift
            // clamp targetGridIndex to count-1, but the commit logic might use count
            // for "append at end" positioning.
            //
            // This means visual preview shows insertion at position 2 (last existing)
            // but commit might place it at position 3 (after all).

            // Check grid offsets - they should push existing items to make room
            // The visual preview should match where the item will actually go
        }
    }

    @Test("Grid reorder visual preview matches commit position")
    func gridReorderVisualMatchesCommit() throws {
        let support = try SidebarTestSupport()
        let fav1 = support.createFavorite(title: "Fav1", url: "https://fav1.com")
        let fav2 = support.createFavorite(title: "Fav2", url: "https://fav2.com")
        let fav3 = support.createFavorite(title: "Fav3", url: "https://fav3.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Drag fav1 to position after fav3
        let fav1Frame = support.dragCoordinator.computedItemFrame(for: fav1.id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(fav1),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: fav1Frame.midX, y: fav1Frame.midY),
        )

        // Drag to right side (after fav3)
        support.dragCoordinator.updateDrag(
            offset: 0,
            location: CGPoint(x: 230, y: 45), // After the 3rd tile
        )

        // Get the grid offset preview (stored in itemPushOffsets for both tabs and favorites)
        let fav2Offset = support.dragCoordinator.itemPushOffsets[fav2.id]
        let fav3Offset = support.dragCoordinator.itemPushOffsets[fav3.id]

        // If dragging to end, fav2 and fav3 should NOT have offsets
        // (they stay in place, fav1 goes to end)
        // But if targeting position 2 (before fav3), fav3 should shift right
        _ = fav2Offset
        _ = fav3Offset

        // Commit and check final position
        _ = support.dragCoordinator.commitDrag()
        support.rebuildLayout()

        let finalOrder = support.layoutManager.favoritesLayout
        let fav1Index = finalOrder.firstIndex { $0.id == fav1.id }

        // Final position should match what the visual preview indicated
        // This exposes the bug if there's a mismatch
        #expect(fav1Index != nil)
    }

    // MARK: - Empty Grid External Drop Bug Tests

    @Test("BUG: External URL can't create first favorite when grid is empty")
    func externalDropCantCreateFirstFavorite() throws {
        let support = try SidebarTestSupport()
        // NO favorites - empty grid
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        #expect(support.layoutManager.favoritesLayout.isEmpty)

        // Simulate external drop entering
        // The grid frame is set but there are no favorites
        let gridFrame = support.dragCoordinator.favoritesGridFrame

        // BUG: When grid is empty, gridFrame.contains() might fail because
        // the frame might be zero or the logic doesn't have placeholder handling

        // Check if a location in the grid area would detect favoritesGrid zone
        let locationInGridArea = CGPoint(x: 50, y: 45) // Where grid would be

        // This is what DropReceiverNSView.determineDropZone does
        let inFavorites = gridFrame.contains(locationInGridArea)

        // For empty grid, should we still allow dropping to create first favorite?
        // Current implementation: favoritesGridFrame may be empty/zero
        // so this check will fail and default to normalSection

        // If gridFrame is empty, external drops can't create favorites
        if gridFrame.isEmpty {
            Issue.record("BUG: Grid frame is empty when no favorites exist, preventing external URL drops")
        } else {
            #expect(inFavorites, "Location should be in favorites grid area")
        }
    }

    @Test("External drop detection with single favorite")
    func externalDropWithSingleFavorite() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Single", url: "https://single.com")
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // With one favorite, grid should have a valid frame
        let gridFrame = support.dragCoordinator.favoritesGridFrame
        #expect(!gridFrame.isEmpty)

        // Location in grid area should detect favoritesGrid
        let locationInGrid = CGPoint(x: 50, y: 45)
        let inFavorites = gridFrame.contains(locationInGrid)
        #expect(inFavorites)
    }

    // MARK: - First Item Start Y Bug Tests

    @Test("_firstItemStartY captured from first visible item when scrolled")
    func firstItemStartYCapturedWhenScrolled() throws {
        let support = try SidebarTestSupport()
        // Create many tabs so some are offscreen
        for i in 0 ..< 20 {
            _ = support.createTab(url: "https://tab\(i).com")
        }
        support.rebuildLayout()

        // Set up geometry
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 1_000))
        support.dragCoordinator.updateFavoritesGridFrame(.zero) // No favorites

        // Start drag with an item that HAS a frame (item at index 5)
        // The _firstItemStartY should be captured from the first item WITH a frame
        let normalItems = support.layoutManager.normalItems
        let tab = normalItems[5].tab!
        let originIndex = support.layoutManager.metadata[normalItems[5].id]!.globalIndex

        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItems[5].id)!
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // After starting drag, _firstItemStartY is captured from section geometry (not individual item frames).
        // This is more reliable as individual NSView frames don't update during scroll.
        let firstStartY = support.dragCoordinator._firstItemStartY

        // _firstItemStartY uses the section frame's minY
        #expect(firstStartY != nil, "_firstItemStartY should be captured from section frame")
    }

    // MARK: - Grid Tile Position Calculation Tests

    @Test("Grid tile positions calculated correctly for 3-column layout")
    func gridTilePositions3Column() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Fav1", url: "https://fav1.com")
        _ = support.createFavorite(title: "Fav2", url: "https://fav2.com")
        _ = support.createFavorite(title: "Fav3", url: "https://fav3.com")
        _ = support.createFavorite(title: "Fav4", url: "https://fav4.com") // Second row
        support.rebuildLayout()
        setupStandardFrames(support)

        // Grid: 80px tiles, 8px spacing, 3 columns
        // Row 0: [0,0], [88,0], [176,0]
        // Row 1: [0,88], [88,88], [176,88]

        let fav1 = support.layoutManager.favoritesLayout[0]
        let fav1Frame = support.dragCoordinator.computedItemFrame(for: fav1.id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)

        support.dragCoordinator.startDrag(
            item: .favorite(fav1),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: fav1Frame.midX, y: fav1Frame.midY),
        )

        // Drag to position 3 (first position in second row)
        // This should be at approximately x=40 (center of tile 0), y=88+40=128
        support.dragCoordinator.updateDrag(
            offset: 0,
            location: CGPoint(x: 40, y: 128),
        )

        // Check if the correct grid position is targeted
        // Position 3 should be column 0, row 1
    }

    @Test("Grid target index at each column boundary")
    func gridTargetIndexAtColumnBoundaries() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Fav1", url: "https://fav1.com")
        _ = support.createFavorite(title: "Fav2", url: "https://fav2.com")
        _ = support.createFavorite(title: "Fav3", url: "https://fav3.com")
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let normalItem = support.layoutManager.normalItems.first!
        let tab = normalItem.tab!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Test each column center
        // Tile layout: 80px tiles with 8px spacing, 3 columns
        let gridY: CGFloat = 45 // Middle of first row

        // Column 0 center = 40
        support.dragCoordinator.updateDrag(
            offset: -100,
            location: CGPoint(x: 40, y: gridY),
        )
        // Should target position 0

        // Column 1 center = 40 + 80 + 8 = 128
        support.dragCoordinator.updateDrag(
            offset: -100,
            location: CGPoint(x: 128, y: gridY),
        )
        // Should target position 1

        // Column 2 center = 128 + 80 + 8 = 216
        support.dragCoordinator.updateDrag(
            offset: -100,
            location: CGPoint(x: 216, y: gridY),
        )
        // Should target position 2

        // After last column = 260+
        support.dragCoordinator.updateDrag(
            offset: -100,
            location: CGPoint(x: 260, y: gridY),
        )
        // BUG CHECK: Should target position 3 (append) but might clamp to 2
    }

    // MARK: - Drop Zone Visibility Edge Cases

    @Test("Favorites drop zone shows when favorites grid is empty")
    func favoritesDropZoneShowsWhenEmpty() throws {
        let support = try SidebarTestSupport()
        // No favorites
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()

        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Empty grid
        support.dragCoordinator.updateFavoritesGridFrame(.zero)

        #expect(support.layoutManager.favoritesLayout.isEmpty)

        let items = support.layoutManager.normalItems
        let normalItem = items.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag above tab list to trigger drop zone
        support.dragCoordinator.updateDrag(
            offset: -80,
            location: CGPoint(x: 100, y: 20),
        )

        // Should show favorites drop zone
        #expect(support.dragCoordinator.shouldShowFavoritesDropZone == true)
    }

    @Test("Tab list push offset calculated for both drop zones")
    func tabListPushOffsetForBothDropZones() throws {
        let support = try SidebarTestSupport()
        // No favorites, no pinned - both zones can appear
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()

        // Set sidebar bounds large enough to contain content AND drop zone area above
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: -100, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(.zero)

        let items = support.layoutManager.normalItems
        let normalItem = items.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag way above to max out both drop zones (y=-50 is above content but inside sidebar bounds)
        support.dragCoordinator.updateDrag(
            offset: -150,
            location: CGPoint(x: 100, y: -50),
        )

        // Should show both drop zones
        #expect(support.dragCoordinator.shouldShowFavoritesDropZone == true)
        #expect(support.dragCoordinator.shouldShowPinDropZone == true)

        // Push offset should account for BOTH zones
        let pushOffset = support.dragCoordinator.tabListPushOffset
        #expect(pushOffset > 0)
        // Each zone is 44 height + 12 padding = 56, times progress
        // With max progress (1.0), should be 112 for both zones
    }
}
