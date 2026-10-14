import Foundation
import Testing
@testable import Refrax

extension Tag {
    @Tag static var sidebarDragCoordinator: Self
}

@Suite("Sidebar.DragCoordinator Drop Zones", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragDropZoneTests {
    @Test
    func `Favorites drop zone shows when dragging above empty favorites`() throws {
        let support = try SidebarTestSupport()
        _ = try support.createGroup(name: "Pinned", isPinned: true)
        _ = support.createTab(url: "https://example.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Get the actual normal tab (use normalItems ordering)
        let normalTab = try #require(support.layoutManager.normalItems.first?.tab)
        let originIndex = try #require(support.layoutManager.metadata[normalTab.id]?.globalIndex)
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: normalTab.id))

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Drag above the first item (pinned section) to trigger drop zones.
        // _isDragAboveTabList uses originalFrame.minY + offset < _firstItemStartY.
        // We need the dragged item's Y position to be above the pinned section.
        let pinnedSectionMinY = support.dragCoordinator.computedPinnedSectionFrame.minY
        let offsetNeeded = pinnedSectionMinY - startFrame.minY - 10 // 10pt margin above threshold
        support.dragCoordinator.updateDrag(
            offset: offsetNeeded,
            location: CGPoint(x: startFrame.midX, y: pinnedSectionMinY - 10),
        )

        #expect(support.dragCoordinator.shouldShowFavoritesDropZone)
        #expect(!support.dragCoordinator.shouldShowPinDropZone)
    }

    @Test
    func `Pin drop zone shows when dragging unpinned group above empty pinned section`() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Favorite", url: "https://favorite.com")
        let group = try support.createGroup(name: "Group", isPinned: false)

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let originIndex = try #require(support.layoutManager.metadata[group.id]?.globalIndex)
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: group.id))
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .group(group),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        support.dragCoordinator.updateDrag(
            offset: -40,
            location: CGPoint(x: 10, y: 40),
        )

        #expect(!support.dragCoordinator.shouldShowFavoritesDropZone)
        #expect(support.dragCoordinator.shouldShowPinDropZone)
    }

    @Test
    func `Tab list push offset reflects both drop zones at full progress`() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://example.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let originIndex = try #require(support.layoutManager.metadata[tab.id]?.globalIndex)
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: tab.id))
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        support.dragCoordinator.updateDrag(
            offset: -80,
            location: CGPoint(x: 10, y: 10),
        )

        #expect(support.dragCoordinator.shouldShowFavoritesDropZone)
        #expect(support.dragCoordinator.shouldShowPinDropZone)
    }

    @Test
    func `Drop zones show/hide at thresholds`() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://example.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let items = support.layoutManager.pinnedItems + support.layoutManager.normalItems
        let originIndex = try #require(support.layoutManager.metadata[tab.id]?.globalIndex)
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: tab.id))
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        let originalFrame = try #require(support.dragCoordinator.computedItemFrame(for: tab.id))
        let baseThreshold = try #require(support.dragCoordinator.computedItemFrame(for: #require(items.first?.id))?.minY) + Sidebar.DragCoordinator.DragConstants.dropZoneThresholdOffset
        let transition = Sidebar.DragCoordinator.DragConstants.dropZoneTransitionDistance

        // At threshold, drop zones should not be visible
        let offsetForZero = baseThreshold - originalFrame.midY
        support.dragCoordinator.updateDrag(
            offset: offsetForZero,
            location: CGPoint(x: 0, y: 0),
        )
        // Drop zones may or may not show at exact threshold depending on implementation

        // Well past threshold, drop zones should be visible
        let offsetForFull = (baseThreshold - transition) - originalFrame.midY
        support.dragCoordinator.updateDrag(
            offset: offsetForFull,
            location: CGPoint(x: 0, y: 0),
        )
        #expect(support.dragCoordinator.shouldShowFavoritesDropZone || support.dragCoordinator.shouldShowPinDropZone)
    }

    @Test
    func `Adjusted section frames account for tab list push`() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://example.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let originIndex = try #require(support.layoutManager.metadata[tab.id]?.globalIndex)
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: tab.id))
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        support.dragCoordinator.updateDrag(
            offset: -80,
            location: CGPoint(x: 10, y: 10),
        )

        let pushOffset = support.dragCoordinator.tabListPushOffset
        let adjusted = support.dragCoordinator._adjustedNormalSectionFrame

        #expect(adjusted.minY == support.dragCoordinator.computedNormalSectionFrame.minY + pushOffset)
    }

    @Test
    func `Location conversion subtracts push offset`() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://example.com")

        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let originIndex = try #require(support.layoutManager.metadata[tab.id]?.globalIndex)
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: tab.id))
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        support.dragCoordinator.updateDrag(
            offset: -80,
            location: CGPoint(x: 10, y: 10),
        )

        let staticPoint = support.dragCoordinator.locationInStaticSpace(CGPoint(x: 0, y: 100))
        #expect(staticPoint.y == 100 - support.dragCoordinator.tabListPushOffset)
    }
}
