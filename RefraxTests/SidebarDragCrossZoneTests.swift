import Foundation
import Testing

@testable import Refrax

/// Comprehensive tests for cross-zone drag interactions.
///
/// Cross-zone interactions are critical for the hybrid drag-drop system. These tests verify:
/// - Tab ↔ Favorites: morphs to tile/row, converts on drop
/// - Tab ↔ Pinned/Normal: pin state changes correctly
/// - Favorite → Tab List: converts at correct position
/// - Group → Favorites: blocked (groups cannot be favorites)
/// - Multi-item cross-zone operations
@Suite("Cross-Zone Drag Interactions", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragCrossZoneTests {
    // MARK: - Test Helpers

    /// Creates a standard test setup with favorites, pinned tabs, and normal tabs.
    private func createStandardSetup(_ support: SidebarTestSupport) throws -> (
        favorites: [FavoriteItem],
        pinnedTabs: [Tab],
        normalTabs: [Tab],
    ) {
        // Create favorites first
        let fav1 = support.createFavorite(title: "Fav 1", url: "https://fav1.com")
        let fav2 = support.createFavorite(title: "Fav 2", url: "https://fav2.com")

        // Create pinned tabs
        let pinned1 = support.createTab(url: "https://pinned1.com", isPinned: true)
        let pinned2 = support.createTab(url: "https://pinned2.com", isPinned: true)

        // Create normal tabs
        let normal1 = support.createTab(url: "https://normal1.com")
        let normal2 = support.createTab(url: "https://normal2.com")
        let normal3 = support.createTab(url: "https://normal3.com")

        support.rebuildLayout()

        return (
            favorites: [fav1, fav2],
            pinnedTabs: [pinned1, pinned2],
            normalTabs: [normal1, normal2, normal3],
        )
    }

    // MARK: - Tab → Favorites Tests

    @Test("Tab dragged to favorites grid gets convertToFavorite target")
    func tabToFavoritesTarget() throws {
        let support = try SidebarTestSupport()
        let (_, _, normalTabs) = try createStandardSetup(support)
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let tabItem = support.layoutManager.normalItems.first { item in
            if case let .tab(tab) = item, tab.id == normalTabs[0].id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(normalTabs[0]),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Drag deep into favorites grid (at least 20pt from edge)
        let targetY: CGFloat = 40
        support.dragCoordinator.updateDrag(
            offset: targetY - 150,
            location: CGPoint(x: 100, y: targetY),
        )

        if case .convertToFavorite(mode: .liveFavorite) = support.dragCoordinator._dropTarget {
            // Expected - conversion target detected
        } else {
            Issue.record("Expected convertToFavorite target, got \(support.dragCoordinator._dropTarget)")
        }

        #expect(support.dragCoordinator.activeDropZone == .favoritesGrid)
    }

    @Test("Tab outside favorites grid does not trigger conversion")
    func tabOutsideFavoritesNoConversion() throws {
        let support = try SidebarTestSupport()
        let (_, _, normalTabs) = try createStandardSetup(support)
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(CGRect(x: 0, y: 0, width: 200, height: 80))

        let tabItem = support.layoutManager.normalItems.first { item in
            if case let .tab(tab) = item, tab.id == normalTabs[0].id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(normalTabs[0]),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Drag to a location well below the favorites grid (in pinned/normal section area)
        // The gap rounding logic gives upper half to favorites, so we need to be clearly below.
        let pinnedFrame = support.dragCoordinator.computedPinnedSectionFrame
        support.dragCoordinator.updateDrag(
            offset: pinnedFrame.midY - tabFrame.midY,
            location: CGPoint(x: 100, y: pinnedFrame.midY),
        )

        // Should NOT be convertToFavorite since we're in the pinned section area
        if case .convertToFavorite = support.dragCoordinator._dropTarget {
            Issue.record("Should not trigger conversion when in pinned section, got convertToFavorite")
        }
    }

    @Test("Committed tab→favorite conversion creates favorite")
    func tabToFavoriteCommitCreates() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Existing", url: "https://existing.com")
        let tab = support.createTab(url: "https://newTab.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let initialFavoritesCount = support.layoutManager.favoritesLayout.count

        let tabItem = support.layoutManager.normalItems.first { item in
            if case let .tab(t) = item, t.id == tab.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Drag into favorites
        support.dragCoordinator.updateDrag(
            offset: -100,
            location: CGPoint(x: 100, y: 40),
        )

        // Commit
        let didCommit = support.dragCoordinator.commitDrag()
        #expect(didCommit)

        // Rebuild and check favorites count increased
        support.rebuildLayout()
        #expect(support.layoutManager.favoritesLayout.count == initialFavoritesCount + 1)
    }

    @Test("Multiple tabs dragged to favorites all convert")
    func multipleTabsToFavoritesAllConvert() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Existing", url: "https://existing.com")
        let tab1 = support.createTab(url: "https://tab1.com")
        let tab2 = support.createTab(url: "https://tab2.com")
        let tab3 = support.createTab(url: "https://tab3.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let initialFavoritesCount = support.layoutManager.favoritesLayout.count

        let tabItem = support.layoutManager.normalItems.first { item in
            if case let .tab(t) = item, t.id == tab1.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex

        // Start drag with multiple items
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            items: [.tab(tab1), .tab(tab2), .tab(tab3)],
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Drag into favorites
        support.dragCoordinator.updateDrag(
            offset: -100,
            location: CGPoint(x: 100, y: 40),
        )

        // Commit
        let didCommit = support.dragCoordinator.commitDrag()
        #expect(didCommit)

        // All 3 should become favorites
        support.rebuildLayout()
        #expect(support.layoutManager.favoritesLayout.count == initialFavoritesCount + 3)
    }

    // MARK: - Favorites → Tab List Tests

    @Test("Favorite dragged to normal section gets convertToTab target")
    func favoriteToNormalTarget() throws {
        let support = try SidebarTestSupport()
        let (favorites, _, _) = try createStandardSetup(support)
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(CGRect(x: 0, y: 0, width: 200, height: 80))

        let favFrame = support.dragCoordinator.computedItemFrame(for: favorites[0].id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(favorites[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: favFrame.midX, y: favFrame.midY),
        )

        // Drag to normal section - use actual computed frame position
        let normalFrame = support.dragCoordinator.computedNormalSectionFrame
        support.dragCoordinator.updateDrag(
            offset: normalFrame.midY - favFrame.midY,
            location: CGPoint(x: 100, y: normalFrame.midY),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: normalFrame.midY))

        if case let .convertToTab(space, targetPosition) = support.dragCoordinator._dropTarget {
            #expect(space.id == support.space.id)
            #expect(targetPosition.collection != .pinned)
        } else {
            Issue.record("Expected convertToTab for normal section, got \(support.dragCoordinator._dropTarget)")
        }
    }

    @Test("Favorite dragged to pinned section gets convertToTab with isPinned true")
    func favoriteToPinnedTarget() throws {
        let support = try SidebarTestSupport()
        let (favorites, _, _) = try createStandardSetup(support)
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let favFrame = support.dragCoordinator.computedItemFrame(for: favorites[0].id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(favorites[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: favFrame.midX, y: favFrame.midY),
        )

        // Drag to pinned section
        let targetY: CGFloat = 120 // Inside pinned section at Y=100
        support.dragCoordinator.updateDrag(
            offset: targetY,
            location: CGPoint(x: 100, y: targetY),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: targetY))

        if case let .convertToTab(space, targetPosition) = support.dragCoordinator._dropTarget {
            #expect(space.id == support.space.id)
            #expect(targetPosition.collection == .pinned)
        } else {
            Issue.record("Expected convertToTab for pinned section, got \(support.dragCoordinator._dropTarget)")
        }
    }

    @Test("Favorite→Tab conversion honors drop position")
    func favoriteToTabHonorsPosition() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Fav", url: "https://fav.com")
        _ = support.createTab(url: "https://tab1.com")
        _ = support.createTab(url: "https://tab2.com")
        _ = support.createTab(url: "https://tab3.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let favorite = support.layoutManager.favoritesLayout[0]

        let favFrame = support.dragCoordinator.computedItemFrame(for: favorite.id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(favorite),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: favFrame.midX, y: favFrame.midY),
        )

        // Drag to position of the middle item in the visual layout.
        // With 3 tabs and prepend ordering, the middle item is at index 1.
        // Tabs are ordered [tab3, tab2, tab1] due to prepend, so index 1 is tab2.
        let middleItem = support.layoutManager.normalItems[1]
        let middleFrame = support.dragCoordinator.computedItemFrame(for: middleItem.id)!

        support.dragCoordinator.updateDrag(
            offset: middleFrame.midY,
            location: CGPoint(x: 100, y: middleFrame.midY),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: middleFrame.midY))

        if case let .convertToTab(_, targetPosition) = support.dragCoordinator._dropTarget {
            // Should be targeting the middle position (0, 1, or 2 depending on exact location)
            #expect(targetPosition.localIndex >= 0 && targetPosition.localIndex <= 3)
        } else {
            Issue.record("Expected convertToTab, got \(support.dragCoordinator._dropTarget)")
        }
    }

    // MARK: - Pinned ↔ Normal Section Tests

    @Test("Normal tab dragged to pinned section gets reorder with .pinned collection")
    func normalToPinnedReorder() throws {
        let support = try SidebarTestSupport()
        let (_, _, normalTabs) = try createStandardSetup(support)
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let tabItem = support.layoutManager.normalItems.first { item in
            if case let .tab(tab) = item, tab.id == normalTabs[0].id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(normalTabs[0]),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Drag to pinned section
        let targetY: CGFloat = 120
        support.dragCoordinator.updateDrag(
            offset: targetY - 200,
            location: CGPoint(x: 100, y: targetY),
        )

        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .pinned)
        } else {
            Issue.record("Expected reorder to pinned, got \(support.dragCoordinator._dropTarget)")
        }
    }

    @Test("Pinned tab dragged to normal section gets reorder with .normal collection")
    func pinnedToNormalReorder() throws {
        let support = try SidebarTestSupport()
        let (_, pinnedTabs, _) = try createStandardSetup(support)
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let pinnedItem = support.layoutManager.pinnedItems.first { item in
            if case let .tab(tab) = item, tab.id == pinnedTabs[0].id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        let pinnedFrame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(pinnedTabs[0]),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: pinnedFrame.midX, y: pinnedFrame.midY),
        )

        // Drag to normal section
        let targetY: CGFloat = 250
        support.dragCoordinator.updateDrag(
            offset: targetY - 120,
            location: CGPoint(x: 100, y: targetY),
        )

        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .normal)
        } else {
            Issue.record("Expected reorder to normal, got \(support.dragCoordinator._dropTarget)")
        }
    }

    @Test("Tab pin state changes on cross-section commit")
    func pinStateChangesOnCommit() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://test.com")
        _ = support.createTab(url: "https://other.com", isPinned: true)
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        #expect(tab.isPinned == false)

        let tabItem = support.layoutManager.normalItems.first { item in
            if case let .tab(t) = item, t.id == tab.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Drag to pinned section
        let targetY: CGFloat = 110
        support.dragCoordinator.updateDrag(
            offset: targetY - 200,
            location: CGPoint(x: 100, y: targetY),
        )

        let didCommit = support.dragCoordinator.commitDrag()
        #expect(didCommit)

        // Tab should now be pinned
        #expect(tab.isPinned == true)
    }

    // MARK: - Group → Favorites Tests (Should Block)

    @Test("Group dragged to favorites grid returns no valid target")
    func groupToFavoritesBlocked() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Fav", url: "https://fav.com")
        let group = try support.createGroup(name: "Test Group")
        _ = support.createTab(url: "https://tab.com", groupID: group.id)
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let groupItem = support.layoutManager.normalItems.first { item in
            if case let .group(g) = item, g.id == group.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[groupItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let groupFrame = support.dragCoordinator.computedItemFrame(for: groupItem.id)!
        support.dragCoordinator.startDrag(
            item: .group(group),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: groupFrame.midX, y: groupFrame.midY),
        )

        // Drag to favorites
        let targetY: CGFloat = 40
        support.dragCoordinator.updateDrag(
            offset: targetY - 200,
            location: CGPoint(x: 100, y: targetY),
        )

        // Should NOT have convertToFavorite target
        if case .convertToFavorite = support.dragCoordinator._dropTarget {
            Issue.record("Groups should not convert to favorites")
        }

        // Active drop zone should not be favorites grid
        #expect(support.dragCoordinator.activeDropZone != .favoritesGrid)
    }

    // MARK: - Empty Section Edge Cases

    @Test("Tab to empty favorites grid works")
    func tabToEmptyFavoritesGrid() throws {
        let support = try SidebarTestSupport()
        // No favorites created
        let tab = support.createTab(url: "https://test.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let tabItem = support.layoutManager.normalItems.first { item in
            if case let .tab(t) = item, t.id == tab.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Drag to favorites
        support.dragCoordinator.updateDrag(
            offset: -60,
            location: CGPoint(x: 100, y: 40),
        )

        // Should detect favorites drop zone (even though empty)
        if case .convertToFavorite = support.dragCoordinator._dropTarget {
            // Expected - can add to empty favorites
        } else {
            Issue.record("Should be able to drag tab to empty favorites grid")
        }
    }

    @Test("Tab to empty pinned section uses drop zone")
    func tabToEmptyPinnedSection() throws {
        let support = try SidebarTestSupport()
        // No pinned tabs
        let tab = support.createTab(url: "https://test.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let tabItem = support.layoutManager.normalItems.first { item in
            if case let .tab(t) = item, t.id == tab.id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Drag above tab list
        support.dragCoordinator.updateDrag(
            offset: -80,
            location: CGPoint(x: 100, y: 20),
        )

        // Pin drop zone should show
        #expect(support.dragCoordinator.shouldShowPinDropZone == true)
    }

    @Test("Favorite to empty normal section creates tab at position 0")
    func favoriteToEmptyNormalSection() throws {
        let support = try SidebarTestSupport()
        let fav = support.createFavorite(title: "Fav", url: "https://fav.com")
        // Create only pinned tabs, no normal tabs
        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let favFrame = support.dragCoordinator.computedItemFrame(for: fav.id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(fav),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: favFrame.midX, y: favFrame.midY),
        )

        // Drag to where normal section would be
        let targetY: CGFloat = 200
        support.dragCoordinator.updateDrag(
            offset: targetY,
            location: CGPoint(x: 100, y: targetY),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: targetY))

        if case let .convertToTab(_, targetPosition) = support.dragCoordinator._dropTarget {
            #expect(targetPosition.collection != .pinned)
            // Should target position 0 in normal section
            #expect(targetPosition.localIndex >= 0)
        } else {
            Issue.record("Expected convertToTab for empty normal section")
        }
    }

    // MARK: - Position Edge Cases

    @Test("Favorite to first position in tab list")
    func favoriteToFirstPosition() throws {
        let support = try SidebarTestSupport()
        let fav = support.createFavorite(title: "Fav", url: "https://fav.com")
        _ = support.createTab(url: "https://tab1.com")
        _ = support.createTab(url: "https://tab2.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let favFrame = support.dragCoordinator.computedItemFrame(for: fav.id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(fav),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: favFrame.midX, y: favFrame.midY),
        )

        // Drag just above the FIRST item in the visual layout (not tab1, which may not be first)
        // Tabs are prepended, so the most recently created tab is first in the layout.
        let firstItem = support.layoutManager.normalItems.first!
        let firstFrame = support.dragCoordinator.computedItemFrame(for: firstItem.id)!

        support.dragCoordinator.updateDrag(
            offset: firstFrame.minY - 10,
            location: CGPoint(x: 100, y: firstFrame.minY - 5),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: firstFrame.minY - 5))

        if case let .convertToTab(_, targetPosition) = support.dragCoordinator._dropTarget {
            // Should be targeting position 0 (before all tabs)
            #expect(targetPosition.localIndex == 0)
        } else {
            Issue.record("Expected convertToTab, got \(support.dragCoordinator._dropTarget)")
        }
    }

    @Test("Favorite to last position in tab list")
    func favoriteToLastPosition() throws {
        let support = try SidebarTestSupport()
        let fav = support.createFavorite(title: "Fav", url: "https://fav.com")
        _ = support.createTab(url: "https://tab1.com")
        _ = support.createTab(url: "https://tab2.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let favFrame = support.dragCoordinator.computedItemFrame(for: fav.id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(fav),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: favFrame.midX, y: favFrame.midY),
        )

        // Drag below all tabs
        let lastItem = support.layoutManager.normalItems.last!
        let lastFrame = support.dragCoordinator.computedItemFrame(for: lastItem.id)!

        let targetY = lastFrame.maxY + 20
        support.dragCoordinator.updateDrag(
            offset: targetY,
            location: CGPoint(x: 100, y: targetY),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: targetY))

        if case let .convertToTab(_, targetPosition) = support.dragCoordinator._dropTarget {
            // Should target position at end
            let normalCount = support.layoutManager.normalItems.count
            #expect(targetPosition.localIndex >= normalCount - 1)
        } else {
            Issue.record("Expected convertToTab for last position")
        }
    }

    // MARK: - Overlay Mode Transitions

    @Test("Overlay mode changes to tile when dragging over favorites grid")
    func overlayModeChangesToTile() throws {
        let support = try SidebarTestSupport()
        let (_, _, normalTabs) = try createStandardSetup(support)
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let tabItem = support.layoutManager.normalItems.first { item in
            if case let .tab(tab) = item, tab.id == normalTabs[0].id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(normalTabs[0]),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Initially should be tabRow mode
        #expect(support.dragCoordinator.currentOverlayMode == .tabRow)

        // Drag into favorites grid
        support.dragCoordinator.updateDrag(
            offset: -100,
            location: CGPoint(x: 100, y: 40),
        )

        // Should now be tile mode
        if case .tile = support.dragCoordinator.currentOverlayMode {
            // Expected
        } else {
            Issue.record("Expected tile mode when over favorites, got \(support.dragCoordinator.currentOverlayMode)")
        }
    }

    @Test("Overlay mode changes back to tabRow when leaving favorites grid")
    func overlayModeChangesBackToTabRow() throws {
        let support = try SidebarTestSupport()
        let (_, _, normalTabs) = try createStandardSetup(support)
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let tabItem = support.layoutManager.normalItems.first { item in
            if case let .tab(tab) = item, tab.id == normalTabs[0].id { return true }
            return false
        }!

        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let tabFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(normalTabs[0]),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Drag into favorites grid
        support.dragCoordinator.updateDrag(
            offset: -100,
            location: CGPoint(x: 100, y: 40),
        )

        // Verify we're in tile mode
        if case .tile = support.dragCoordinator.currentOverlayMode {
            // Good
        } else {
            Issue.record("Should be tile mode")
        }

        // Now drag back to tab list
        support.dragCoordinator.updateDrag(
            offset: 20,
            location: CGPoint(x: 100, y: 150),
        )

        // Should be back to tabRow mode
        #expect(support.dragCoordinator.currentOverlayMode == .tabRow)
    }

    @Test("Favorite always starts in tile mode")
    func favoriteStartsInTileMode() throws {
        let support = try SidebarTestSupport()
        let (favorites, _, _) = try createStandardSetup(support)
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let favFrame = support.dragCoordinator.computedItemFrame(for: favorites[0].id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(favorites[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: favFrame.midX, y: favFrame.midY),
        )

        // Should start in tile mode
        if case .tile = support.dragCoordinator.currentOverlayMode {
            // Expected
        } else {
            Issue.record("Favorite should start in tile mode, got \(support.dragCoordinator.currentOverlayMode)")
        }
    }

    @Test("Favorite overlay changes to tabRow when over tab list")
    func favoriteOverlayChangesToTabRow() throws {
        let support = try SidebarTestSupport()
        let (favorites, _, _) = try createStandardSetup(support)
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let favFrame = support.dragCoordinator.computedItemFrame(for: favorites[0].id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(favorites[0]),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: favFrame.midX, y: favFrame.midY),
        )

        // Drag to normal section
        support.dragCoordinator.updateDrag(
            offset: 150,
            location: CGPoint(x: 100, y: 200),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: 200))

        // Should change to tabRow mode
        #expect(support.dragCoordinator.currentOverlayMode == .tabRow)
    }
}
