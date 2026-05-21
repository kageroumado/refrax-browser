import Foundation
import Testing

@testable import Refrax

/// Tests for cache validity, invalidation, and rebuild timing.
///
/// These tests verify:
/// - All items cache rebuilds on generation change
/// - Descendants cache for empty groups
/// - Cache invalidation mechanics
/// - Exclusion set updates for multi-drag
@Suite("Cache Edge Cases", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragCacheTests {
    // MARK: - Test Helpers

    private func setupTestGeometry(_ support: SidebarTestSupport) {
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(CGRect(x: 0, y: 0, width: 200, height: 90))
        support.dragCoordinator.updateFavoritesGridLayout(
            columns: 3,
            tileSize: CGSize(width: 80, height: 80),
            spacing: 8,
        )
    }

    // MARK: - All Items Cache Tests

    @Test("All items cache rebuilds on generation change before drag")
    func allItemsCacheRebuildsOnGenerationChange() throws {
        let support = try SidebarTestSupport()

        // Create first tab and build cache BEFORE starting drag
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        // Get items to build cache (no drag active yet)
        let items1 = support.dragCoordinator.getAllItems()
        let generation1 = support.dragCoordinator._cachedAllItemsGeneration

        // Add second tab and rebuild (still no drag)
        _ = support.createTab(url: "https://tab2.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        // Cache should rebuild due to generation change
        let items2 = support.dragCoordinator.getAllItems()
        let generation2 = support.dragCoordinator._cachedAllItemsGeneration

        #expect(items2.count > items1.count)
        #expect(generation2 > generation1)
    }

    @Test("Visible items cache with stale frames handled correctly")
    func visibleItemsCacheWithStaleFrames() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        _ = support.createTab(url: "https://tab2.com")
        _ = support.createTab(url: "https://tab3.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Build visible items cache
        let visibleItems = support.dragCoordinator.getVisibleItems()

        // Verify cache is built
        #expect(!visibleItems.isEmpty)
    }

    @Test("Descendants cache for empty group returns empty set")
    func descendantsCacheForEmptyGroup() throws {
        let support = try SidebarTestSupport()
        let emptyGroup = try support.createGroup(name: "Empty")
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        let groupItem = support.layoutManager.normalItems.first { item in
            if case let .group(group) = item, group.id == emptyGroup.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[groupItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: groupItem.id)!
        support.dragCoordinator.startDrag(
            item: .group(emptyGroup),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Get descendants of empty group
        let descendants = support.dragCoordinator.getDescendants(of: emptyGroup.id)

        // Should return empty set, not crash
        #expect(descendants.isEmpty)
    }

    @Test("Forced cache invalidation causes rebuild")
    func forcedCacheInvalidationCausesRebuild() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Get initial items
        _ = support.dragCoordinator.getAllItems()
        let initialGeneration = support.dragCoordinator._cachedAllItemsGeneration

        // Force cache invalidation by setting generation to -1
        support.dragCoordinator._cachedAllItemsGeneration = -1

        // Next call should detect mismatch and rebuild
        _ = support.dragCoordinator.getAllItems()
        let newGeneration = support.dragCoordinator._cachedAllItemsGeneration

        // Should have rebuilt to current generation
        #expect(newGeneration == initialGeneration)
    }

    @Test("RebuildLayout during drag starts cancellation animation")
    func rebuildLayoutDuringDragStartsCancellation() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        #expect(support.dragCoordinator.isDragging)
        #expect(support.dragCoordinator.isAnimatingReturn == false)

        // rebuildLayout during drag should trigger cancellation animation
        support.rebuildLayout()

        // Drag is now in "animating return" state
        // isDragging is still true until reset() clears draggedItems after animation
        #expect(support.dragCoordinator.isAnimatingReturn == true)
    }

    @Test("Exclusion set rebuilt on multi-drag change")
    func exclusionSetRebuiltOnMultiDragChange() throws {
        let support = try SidebarTestSupport()
        let tab1 = support.createTab(url: "https://tab1.com")
        let tab2 = support.createTab(url: "https://tab2.com")
        let tab3 = support.createTab(url: "https://tab3.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex

        // Start with multiple items
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            items: [.tab(tab1), .tab(tab2)],
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Check exclusion set contains both tabs
        let exclusionSet = support.dragCoordinator._draggedItemExclusionSet
        #expect(exclusionSet.contains(tab1.id))
        #expect(exclusionSet.contains(tab2.id))
        #expect(!exclusionSet.contains(tab3.id))
    }

    @Test("Visible items cache built during drag")
    func visibleItemsCacheBuiltDuringDrag() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        _ = support.createTab(url: "https://tab2.com")
        support.rebuildLayout()
        setupTestGeometry(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Build cache
        _ = support.dragCoordinator.getVisibleItems()
        let cachedGeneration = support.dragCoordinator._cachedVisibleItemsGeneration

        // Cached generation should match layout manager's generation
        #expect(cachedGeneration == support.layoutManager.frameGeneration)
    }
}
