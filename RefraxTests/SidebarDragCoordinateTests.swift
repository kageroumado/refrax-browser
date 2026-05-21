import Foundation
import Testing

@testable import Refrax

/// Tests for coordinate transformations between visual and static space.
///
/// These tests verify:
/// - Location conversion with push offsets
/// - Frame adjustments during zone animations
/// - Sidebar bounds handling
/// - Round-trip coordinate conversion
@Suite("Coordinate System", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragCoordinateTests {
    // MARK: - Static Space Conversion Tests

    @Test("Location in static space with large push offset")
    func locationInStaticSpaceWithLargePushOffset() throws {
        let support = try SidebarTestSupport()
        // No favorites, no pinned - drop zones can appear
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(.zero)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let frame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Drag above to trigger drop zones and push offset
        support.dragCoordinator.updateDrag(
            offset: -80,
            location: CGPoint(x: 100, y: 20),
        )

        let pushOffset = support.dragCoordinator.tabListPushOffset
        let visualLocation = CGPoint(x: 100, y: 150)
        let staticLocation = support.dragCoordinator.locationInStaticSpace(visualLocation)

        // Static location Y should be visual Y minus push offset
        #expect(staticLocation.x == visualLocation.x)
        #expect(staticLocation.y == visualLocation.y - pushOffset)
    }

    @Test("Location in static space with zero push offset")
    func locationInStaticSpaceWithZeroPushOffset() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        _ = support.createTab(url: "https://tab2.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let frame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Stay within tab list (no drop zone activation)
        support.dragCoordinator.updateDrag(
            offset: 30,
            location: CGPoint(x: 100, y: 130),
        )

        let pushOffset = support.dragCoordinator.tabListPushOffset
        if pushOffset == 0 {
            let visualLocation = CGPoint(x: 100, y: 150)
            let staticLocation = support.dragCoordinator.locationInStaticSpace(visualLocation)

            // With no push offset, static equals visual
            #expect(staticLocation == visualLocation)
        }
    }

    @Test("Adjusted pinned frame during zone animation")
    func adjustedPinnedFrameDuringZoneAnimation() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://pinned.com", isPinned: true)
        let normalTab = support.createTab(url: "https://normal.com")
        support.rebuildLayout()

        // No favorites so favorites drop zone can appear
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(.zero)

        let normalItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[normalItem.id]!.globalIndex
        let normalFrame = support.dragCoordinator.computedItemFrame(for: normalItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(normalTab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: normalFrame.midX, y: normalFrame.midY),
        )

        // Drag above to activate drop zones
        support.dragCoordinator.updateDrag(
            offset: -80,
            location: CGPoint(x: 100, y: 20),
        )

        let pushOffset = support.dragCoordinator.tabListPushOffset
        if pushOffset > 0 {
            let originalFrame = support.dragCoordinator.computedPinnedSectionFrame
            let adjustedFrame = support.dragCoordinator._adjustedPinnedSectionFrame

            #expect(adjustedFrame.minY == originalFrame.minY + pushOffset)
        }
    }

    @Test("Adjusted normal frame during zone animation")
    func adjustedNormalFrameDuringZoneAnimation() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(.zero)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let tabFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Drag above to activate drop zones
        support.dragCoordinator.updateDrag(
            offset: -80,
            location: CGPoint(x: 100, y: 20),
        )

        let pushOffset = support.dragCoordinator.tabListPushOffset
        if pushOffset > 0 {
            let originalFrame = support.dragCoordinator.computedNormalSectionFrame
            let adjustedFrame = support.dragCoordinator._adjustedNormalSectionFrame

            #expect(adjustedFrame.minY == originalFrame.minY + pushOffset)
        }
    }

    @Test("Sidebar bounds at zero origin")
    func sidebarBoundsAtZeroOrigin() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 400))

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let frame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Overlay position in sidebar should equal overlay position when origin is zero
        support.dragCoordinator.overlayPosition = CGPoint(x: 100, y: 150)
        let inSidebar = support.dragCoordinator.overlayPositionInSidebar

        #expect(inSidebar.x == 100)
        #expect(inSidebar.y == 150)
    }

    @Test("Overlay position in sidebar before bounds set")
    func overlayPositionInSidebarBeforeBoundsSet() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()

        // Don't set sidebar bounds (use default .zero)
        support.setupTestGeometry(sidebarBounds: .zero)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let tabFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Set overlay position
        support.dragCoordinator.overlayPosition = CGPoint(x: 100, y: 150)

        // With zero bounds, sidebar-local position is same as global
        let inSidebar = support.dragCoordinator.overlayPositionInSidebar
        #expect(inSidebar.x == 100)
        #expect(inSidebar.y == 150)
    }

    @Test("Static space conversion round trip preserves location")
    func staticSpaceConversionRoundTrip() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(.zero)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex
        let tabFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: tabFrame.midX, y: tabFrame.midY),
        )

        // Activate some push offset
        support.dragCoordinator.updateDrag(
            offset: -80,
            location: CGPoint(x: 100, y: 20),
        )

        let pushOffset = support.dragCoordinator.tabListPushOffset
        let originalVisualLocation = CGPoint(x: 100, y: 150)
        let staticLocation = support.dragCoordinator.locationInStaticSpace(originalVisualLocation)

        // Convert back to visual space
        let visualLocation = CGPoint(x: staticLocation.x, y: staticLocation.y + pushOffset)

        #expect(visualLocation == originalVisualLocation)
    }
}
