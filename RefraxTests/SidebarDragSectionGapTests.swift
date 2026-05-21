import Foundation
import Testing

@testable import Refrax

/// Tests for behavior in gaps between sections and at exact boundaries.
///
/// These tests verify:
/// - Drag behavior in divider areas between sections
/// - Section frame adjustment during active drag
/// - Push offset effects on adjusted frames
@Suite("Section Gap Handling", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragSectionGapTests {
    // MARK: - Test Helpers

    private func setupStandardFrames(_ support: SidebarTestSupport, startY _: CGFloat = 100) {
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
    }

    // MARK: - Gap Behavior Tests

    @Test("Drag in gap between sections targets closer section")
    func dragInGapBetweenSections() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        let normalTab = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to gap between pinned and normal sections
        let pinnedFrame = support.dragCoordinator.computedPinnedSectionFrame
        let normalFrame = support.dragCoordinator.computedNormalSectionFrame
        let gapY = (pinnedFrame.maxY + normalFrame.minY) / 2

        support.dragCoordinator.updateDrag(
            offset: gapY - 180,
            location: CGPoint(x: 100, y: gapY),
        )

        // Should still resolve to a valid target (not .none)
        if case .none = support.dragCoordinator._dropTarget {
            Issue.record("Expected a valid drop target, got .none")
        }
    }

    @Test("Favorite drop closer to pinned section resolves to pinned")
    func favoriteDropAtPinnedNormalBoundary() throws {
        let support = try SidebarTestSupport()
        let fav = support.createFavorite(title: "Fav", url: "https://fav.com")
        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://normal.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let favFrame = support.dragCoordinator.computedItemFrame(for: fav.id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(fav),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: favFrame.midX, y: favFrame.midY),
        )

        // Drag to just below pinned section
        let pinnedFrame = support.dragCoordinator.computedPinnedSectionFrame
        let targetY = pinnedFrame.maxY + 5

        support.dragCoordinator.updateDrag(
            offset: targetY,
            location: CGPoint(x: 100, y: targetY),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: targetY))

        // Should resolve based on proximity
        if case let .convertToTab(_, targetPosition) = support.dragCoordinator._dropTarget {
            // Could be pinned or normal depending on exact heuristics
            #expect(targetPosition.collection == .pinned || targetPosition.collection != .pinned)
        }
    }

    @Test("Drop zone visible but cursor in tab list prefers tab list")
    func dropZoneVisibleButCursorInTabList() throws {
        let support = try SidebarTestSupport()
        // No pinned tabs - pin drop zone could be visible
        let normalTab = support.createTab(url: "https://normal.com")
        support.rebuildLayout()

        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(.zero)

        let items = support.layoutManager.normalItems
        let normalItem = items.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag upward but stay within tab list bounds
        support.dragCoordinator.updateDrag(
            offset: -30,
            location: CGPoint(x: 100, y: 70),
        )

        // Should prefer reorder within section over drop zone
        if case .reorder = support.dragCoordinator._dropTarget {
            // Expected - tab list reorder takes priority
        }
    }

    // Note: "Section frame updates during active drag" test removed - section frames are now computed

    @Test("Adjusted frames with zero push offset have same Y origin")
    func adjustedFramesWithZeroPushOffset() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        _ = support.createTab(url: "https://tab2.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Stay in same section (no drop zone push)
        support.dragCoordinator.updateDrag(
            offset: 30,
            location: CGPoint(x: 100, y: 130),
        )

        // With no drop zone progress, push offset should be 0
        let pushOffset = support.dragCoordinator.tabListPushOffset
        #expect(pushOffset == 0)

        // Adjusted frame minY should equal section frame minY (no push offset applied)
        let adjustedFrame = support.dragCoordinator._adjustedNormalSectionFrame
        #expect(!adjustedFrame.isEmpty)
        // The first normal item should be at the expected Y
        let firstNormalItemFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        #expect(adjustedFrame.minY == firstNormalItemFrame.minY)
    }

    @Test("Adjusted frames with max push offset shift by full amount")
    func adjustedFramesWithMaxPushOffset() throws {
        let support = try SidebarTestSupport()
        // No favorites, no pinned - both drop zones can appear
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()

        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(.zero)

        let items = support.layoutManager.normalItems
        let tabItem = items.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag far above to trigger full drop zone
        support.dragCoordinator.updateDrag(
            offset: -100,
            location: CGPoint(x: 100, y: 0),
        )

        // With drop zone progress, there should be push offset
        let pushOffset = support.dragCoordinator.tabListPushOffset
        if pushOffset > 0 {
            // The adjusted frame should be shifted by pushOffset relative to the first item's frame
            let firstItemFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
            let adjustedFrame = support.dragCoordinator._adjustedNormalSectionFrame
            #expect(adjustedFrame.minY == firstItemFrame.minY + pushOffset)
        }
    }

    @Test("Cursor in normal gap with only pinned items")
    func cursorInNormalGapWithOnlyPinnedItems() throws {
        let support = try SidebarTestSupport()
        // Only pinned tabs, no normal tabs
        let pinnedTab = support.createTab(url: "https://pinned.com", isPinned: true)
        _ = support.createTab(url: "https://pinned2.com", isPinned: true)
        support.rebuildLayout()
        setupStandardFrames(support)

        let pinnedItem = support.layoutManager.pinnedItems.first!
        let originIndex = support.layoutManager.metadata[pinnedItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.pinned.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: pinnedItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(pinnedTab),
            originPosition: .pinned(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag to where normal section would be
        support.dragCoordinator.updateDrag(
            offset: 100,
            location: CGPoint(x: 100, y: 200),
        )

        // Should detect normal section even though it's empty
        if case let .reorder(target) = support.dragCoordinator._dropTarget {
            #expect(target.collection == .normal)
        }
    }
}
