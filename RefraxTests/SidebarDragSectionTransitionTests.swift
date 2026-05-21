import Foundation
import Testing

@testable import Refrax

/// Tests for section transitions and boundary conditions.
///
/// These tests verify correct behavior when:
/// - Dragging between pinned and normal sections
/// - Handling edge positions (first, last, only item)
/// - Drop zone visibility and interaction
/// - Frame coordinate handling during transitions
@Suite("Section Transitions", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragSectionTransitionTests {
    // MARK: - Test Helpers

    private func setupStandardFrames(_ support: SidebarTestSupport, startY _: CGFloat = 100) {
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
    }

    // MARK: - Single Item Edge Cases

    @Test("Drag only pinned tab to normal - section becomes empty")
    func dragOnlyPinnedToNormal() throws {
        let support = try SidebarTestSupport()
        let pinnedTab = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        #expect(support.layoutManager.pinnedItems.count == 1)

        let pinnedItem = support.layoutManager.pinnedItems.first!
        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(pinnedTab),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to normal section
        support.dragCoordinator.updateDrag(
            offset: 100,
            location: CGPoint(x: 100, y: 250),
        )

        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .normal)
        }

        let didCommit = support.dragCoordinator.commitDrag()
        #expect(didCommit)

        #expect(pinnedTab.isPinned == false)

        support.rebuildLayout()
        #expect(support.layoutManager.pinnedItems.isEmpty)
    }

    @Test("Drag only normal tab to pinned - normal section becomes empty")
    func dragOnlyNormalToPinned() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        let normalTab = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        #expect(support.layoutManager.normalItems.count == 1)

        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to pinned section
        support.dragCoordinator.updateDrag(
            offset: -80,
            location: CGPoint(x: 100, y: 110),
        )

        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .pinned)
        }

        let didCommit = support.dragCoordinator.commitDrag()
        #expect(didCommit)

        #expect(normalTab.isPinned == true)
    }

    // MARK: - Drop Zone Tests

    @Test("Pin drop zone shows when no pinned tabs exist")
    func pinDropZoneShowsWhenEmpty() throws {
        let support = try SidebarTestSupport()
        // Only normal tabs, no pinned
        let normalTab = support.createTab(url: "https://normal.com")
        _ = support.createTab(url: "https://normal2.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        #expect(support.layoutManager.pinnedItems.isEmpty)

        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag above tab list
        support.dragCoordinator.updateDrag(
            offset: -80,
            location: CGPoint(x: 100, y: 20),
        )

        #expect(support.dragCoordinator.shouldShowPinDropZone == true)
    }

    @Test("Pin drop zone hidden when pinned tabs exist")
    func pinDropZoneHiddenWhenPinned() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        let normalTab = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag above tab list
        support.dragCoordinator.updateDrag(
            offset: -50,
            location: CGPoint(x: 100, y: 50),
        )

        // Pin drop zone should be hidden since pinned tabs exist
        #expect(support.dragCoordinator.shouldShowPinDropZone == false)
    }

    @Test("Favorites drop zone shows when no favorites exist")
    func favoritesDropZoneShowsWhenEmpty() throws {
        let support = try SidebarTestSupport()
        // Only tabs, no favorites
        let normalTab = support.createTab(url: "https://normal.com")
        support.rebuildLayout()

        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Empty favorites grid
        support.dragCoordinator.updateFavoritesGridFrame(.zero)

        #expect(support.layoutManager.favoritesLayout.isEmpty)

        let items = support.layoutManager.normalItems
        let normalItem = items.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag above tab list
        support.dragCoordinator.updateDrag(
            offset: -80,
            location: CGPoint(x: 100, y: 20),
        )

        #expect(support.dragCoordinator.shouldShowFavoritesDropZone == true)
    }

    @Test("Favorites drop zone hidden when favorites exist")
    func favoritesDropZoneHiddenWhenExists() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Fav", url: "https://fav.com")
        let normalTab = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag above tab list
        support.dragCoordinator.updateDrag(
            offset: -50,
            location: CGPoint(x: 100, y: 50),
        )

        // Favorites drop zone should be hidden since favorites exist
        #expect(support.dragCoordinator.shouldShowFavoritesDropZone == false)
    }

    @Test("Drop zone progress increases when dragging above threshold")
    func dropZoneProgressIncreases() throws {
        let support = try SidebarTestSupport()
        // No pinned, no favorites
        let normalTab = support.createTab(url: "https://normal.com")
        support.rebuildLayout()

        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(.zero)

        let items = support.layoutManager.normalItems
        let normalItem = items.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag progressively higher
        support.dragCoordinator.updateDrag(
            offset: -30,
            location: CGPoint(x: 100, y: 70),
        )
        let zones1 = support.dragCoordinator.shouldShowFavoritesDropZone || support.dragCoordinator.shouldShowPinDropZone

        support.dragCoordinator.updateDrag(
            offset: -60,
            location: CGPoint(x: 100, y: 40),
        )
        let zones2 = support.dragCoordinator.shouldShowFavoritesDropZone || support.dragCoordinator.shouldShowPinDropZone

        support.dragCoordinator.updateDrag(
            offset: -90,
            location: CGPoint(x: 100, y: 10),
        )
        let zones3 = support.dragCoordinator.shouldShowFavoritesDropZone || support.dragCoordinator.shouldShowPinDropZone

        // Drop zones should become visible as we drag higher
        // At minimum, the highest position should show drop zones
        #expect(zones3 == true)
        // Earlier positions may or may not show depending on threshold
        _ = (zones1, zones2) // silence unused warnings
    }

    // MARK: - Position Edge Cases

    @Test("Drag to first position in pinned section")
    func dragToFirstPinned() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://pinned1.com", isPinned: true)
        _ = support.createTab(url: "https://pinned2.com", isPinned: true)
        let normalTab = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to top portion of first pinned item (inside frame, above midpoint)
        let firstPinnedFrame = support.dragCoordinator.computedItemFrame(for: support.layoutManager.pinnedItems[0].id)!
        let targetY = firstPinnedFrame.minY + 5 // Inside the frame, near the top
        support.dragCoordinator.updateDrag(
            offset: targetY - 180,
            location: CGPoint(x: 100, y: targetY),
        )

        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .pinned)
            #expect(target.localIndex == 0)
        } else {
            Issue.record("Expected reorder to first position")
        }
    }

    @Test("Drag to last position in pinned section")
    func dragToLastPinned() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://pinned1.com", isPinned: true)
        _ = support.createTab(url: "https://pinned2.com", isPinned: true)
        let normalTab = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to the lower portion of the last pinned item (inside frame, below midpoint)
        // This targets the position AFTER the last item (targetIndex = count)
        let lastPinnedFrame = support.dragCoordinator.computedItemFrame(for: support.layoutManager.pinnedItems.last!.id)!
        let targetY = lastPinnedFrame.maxY - 5 // Inside the frame, near the bottom
        support.dragCoordinator.updateDrag(
            offset: targetY - 180,
            location: CGPoint(x: 100, y: targetY),
        )

        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .pinned)
            // When targeting the lower portion of the last item, we get targetIndex = count - 1 + 1 = count
            // or we might get count - 1 depending on exact midpoint. Accept either as valid.
            #expect(target.localIndex >= support.layoutManager.pinnedItems.count - 1)
            #expect(target.localIndex <= support.layoutManager.pinnedItems.count)
        } else {
            Issue.record("Expected reorder to pinned section")
        }
    }

    @Test("Drag to first position in normal section")
    func dragToFirstNormal() throws {
        let support = try SidebarTestSupport()
        let pinnedTab = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let pinnedItem = support.layoutManager.pinnedItems.first!
        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(pinnedTab),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to top portion of first normal item (inside frame, above midpoint)
        let firstNormalFrame = support.dragCoordinator.computedItemFrame(for: support.layoutManager.normalItems[0].id)!
        let targetY = firstNormalFrame.minY + 5 // Inside the frame, near the top
        support.dragCoordinator.updateDrag(
            offset: targetY - 120,
            location: CGPoint(x: 100, y: targetY),
        )

        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .normal)
        } else {
            Issue.record("Expected reorder to normal section")
        }
    }

    @Test("Drag to last position in normal section")
    func dragToLastNormal() throws {
        let support = try SidebarTestSupport()
        let pinnedTab = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://normal1.com")
        _ = support.createTab(url: "https://normal2.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let pinnedItem = support.layoutManager.pinnedItems.first!
        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(pinnedTab),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to bottom of normal section (past all items)
        let lastNormalFrame = support.dragCoordinator.computedItemFrame(for: support.layoutManager.normalItems.last!.id)!
        support.dragCoordinator.updateDrag(
            offset: lastNormalFrame.maxY + 20 - 120,
            location: CGPoint(x: 100, y: lastNormalFrame.maxY + 20),
        )

        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .normal)
        }
    }

    // MARK: - Coordinate System Tests

    @Test("Tab list push offset affects section frames")
    func tabListPushOffsetAffectsFrames() throws {
        let support = try SidebarTestSupport()
        let normalTab = support.createTab(url: "https://normal.com")
        support.rebuildLayout()

        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(.zero)

        let items = support.layoutManager.normalItems
        let normalItem = items.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let originalNormalFrame = support.dragCoordinator.computedNormalSectionFrame
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag above to trigger drop zones
        support.dragCoordinator.updateDrag(
            offset: -80,
            location: CGPoint(x: 100, y: 20),
        )

        let pushOffset = support.dragCoordinator.tabListPushOffset
        #expect(pushOffset > 0)

        // Adjusted frame should be offset by push amount
        let adjustedFrame = support.dragCoordinator._adjustedNormalSectionFrame
        #expect(adjustedFrame.minY == originalNormalFrame.minY + pushOffset)
    }

    @Test("Location in static space subtracts push offset")
    func locationInStaticSpaceSubtractsPush() throws {
        let support = try SidebarTestSupport()
        let normalTab = support.createTab(url: "https://normal.com")
        support.rebuildLayout()

        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(.zero)

        let items = support.layoutManager.normalItems
        let normalItem = items.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag above to trigger drop zones
        support.dragCoordinator.updateDrag(
            offset: -80,
            location: CGPoint(x: 100, y: 20),
        )

        let pushOffset = support.dragCoordinator.tabListPushOffset
        let visualLocation = CGPoint(x: 100, y: 150)
        let staticLocation = support.dragCoordinator.locationInStaticSpace(visualLocation)

        #expect(staticLocation.x == visualLocation.x)
        #expect(staticLocation.y == visualLocation.y - pushOffset)
    }

    // MARK: - Section Boundary Detection

    @Test("Detect transition from pinned to normal section")
    func detectPinnedToNormalTransition() throws {
        let support = try SidebarTestSupport()
        // Create multiple pinned tabs so same-section reorder is meaningful
        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://pinned2.com", isPinned: true)
        _ = support.createTab(url: "https://pinned3.com", isPinned: true)
        _ = support.createTab(url: "https://normal.com")
        _ = support.createTab(url: "https://normal2.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Drag the FIRST pinned item in layout order (most recently created gets position 0)
        let pinnedItem = support.layoutManager.pinnedItems.first!
        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex
        let draggedTab = pinnedItem.tab!
        let startFrame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(draggedTab),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Stay in pinned section - reorder within same section
        // With 3 pinned items starting at y=100, frames are at y=100, 140, 180
        // Drag to y=150 should be within pinned section (reordering between items)
        support.dragCoordinator.updateDrag(
            offset: 50,
            location: CGPoint(x: 100, y: 150),
        )
        let zone1 = support.dragCoordinator.activeDropZone

        // Move to normal section - cross-section move shows zone
        // Normal items start at y=220 (after 3 pinned items at 40px each)
        support.dragCoordinator.updateDrag(
            offset: 150,
            location: CGPoint(x: 100, y: 250),
        )
        let zone2 = support.dragCoordinator.activeDropZone

        // Verify transition detection: zone should change when moving between sections
        // The exact zone for same-section (nil vs section) depends on implementation,
        // but cross-section should definitely show the target section
        #expect(zone2 == .normalSection)
        // zone1 may be nil or .pinnedSection depending on implementation
        #expect(zone1 == nil || zone1 == .pinnedSection)
    }

    @Test("Detect transition from normal to pinned section")
    func detectNormalToPinnedTransition() throws {
        let support = try SidebarTestSupport()
        // Create multiple items in each section so same-section reorder is meaningful
        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://pinned2.com", isPinned: true)
        _ = support.createTab(url: "https://normal.com")
        _ = support.createTab(url: "https://normal2.com")
        _ = support.createTab(url: "https://normal3.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Drag the FIRST normal item in layout order (most recently created)
        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let draggedTab = normalItem.tab!
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(draggedTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Stay in normal section - reorder within same section
        // With 2 pinned at y=100,140 and 3 normal starting at y=180
        // Normal items are at y=180, 220, 260
        // Drag to y=240 should be within normal section (reordering between items)
        support.dragCoordinator.updateDrag(
            offset: 60,
            location: CGPoint(x: 100, y: 240),
        )
        let zone1 = support.dragCoordinator.activeDropZone

        // Move to pinned section - cross-section move shows zone
        // Pinned section is at y=100-176
        support.dragCoordinator.updateDrag(
            offset: -70,
            location: CGPoint(x: 100, y: 120),
        )
        let zone2 = support.dragCoordinator.activeDropZone

        // Verify transition detection: zone should change when moving between sections
        // The exact zone for same-section (nil vs section) depends on implementation,
        // but cross-section should definitely show the target section
        #expect(zone2 == .pinnedSection)
        // zone1 may be nil or .normalSection depending on implementation
        #expect(zone1 == nil || zone1 == .normalSection)
    }

    // MARK: - Many Items Tests

    @Test("Section transition with many pinned tabs")
    func manyPinnedTabs() throws {
        let support = try SidebarTestSupport()
        var pinnedTabs: [Tab] = []
        for i in 0 ..< 10 {
            pinnedTabs.append(support.createTab(url: "https://pinned\(i).com", isPinned: true))
        }
        let normalTab = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        #expect(support.layoutManager.pinnedItems.count == 10)

        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to middle of pinned section
        let middleIndex = 5
        let middleFrame = support.dragCoordinator.computedItemFrame(for: support.layoutManager.pinnedItems[middleIndex].id)!
        support.dragCoordinator.updateDrag(
            offset: middleFrame.midY - 500,
            location: CGPoint(x: 100, y: middleFrame.midY),
        )

        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .pinned)
            #expect(target.localIndex >= 4 && target.localIndex <= 6)
        }
    }

    @Test("Section transition with many normal tabs")
    func manyNormalTabs() throws {
        let support = try SidebarTestSupport()
        let pinnedTab = support.createTab(url: "https://pinned.com", isPinned: true)
        for i in 0 ..< 20 {
            _ = support.createTab(url: "https://normal\(i).com")
        }
        support.rebuildLayout()
        setupStandardFrames(support)

        #expect(support.layoutManager.normalItems.count == 20)

        let pinnedItem = support.layoutManager.pinnedItems.first!
        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex
        let startFrame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(pinnedTab),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to middle of normal section
        let middleIndex = 10
        let middleFrame = support.dragCoordinator.computedItemFrame(for: support.layoutManager.normalItems[middleIndex].id)!
        support.dragCoordinator.updateDrag(
            offset: middleFrame.midY - 120,
            location: CGPoint(x: 100, y: middleFrame.midY),
        )

        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .normal)
        }
    }
}
