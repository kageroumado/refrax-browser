import Foundation
import Testing

@testable import Refrax

/// Tests for overlay frame calculations and positioning.
///
/// These tests verify:
/// - Overlay frame at different drag positions
/// - Frame calculations during mode transitions
/// - Target position calculations for return animation
/// - Tab row width calculations
@Suite("Overlay Frame", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragOverlayFrameTests {
    // MARK: - Test Helpers

    private func setupStandardFrames(_ support: SidebarTestSupport, startY _: CGFloat = 100, sidebarWidth: CGFloat = 200) {
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: sidebarWidth, height: 500))
    }

    // MARK: - Basic Frame Tests

    @Test("Overlay position updated during drag")
    func overlayPositionUpdatedDuringDrag() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
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

        // Update position
        support.dragCoordinator.overlayPosition = CGPoint(x: 100, y: 150)

        // Verify position was set
        #expect(support.dragCoordinator.overlayPosition == CGPoint(x: 100, y: 150))
    }

    @Test("Original frame captured at drag start")
    func originalFrameCapturedAtDragStart() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
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

        // The original frame is computed from section geometry (with 8pt padding on each side)
        // rather than taken directly from metadata, so verify it has reasonable values
        let frame = support.dragCoordinator._draggedItemOriginalFrame
        #expect(frame != nil)
        #expect(frame!.height == Constants.Layout.tabItemHeight)
        #expect(frame!.width > 0)
    }

    @Test("Tab row width calculated from sidebar bounds")
    func tabRowWidthFromSidebarBounds() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()

        // Set sidebar bounds with specific width and setup frames with same width
        setupStandardFrames(support, sidebarWidth: 300)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Tab row width should be sidebar width minus padding
        let expectedWidth = 300 - 2 * Constants.Layout.tabHorizontalPadding
        #expect(support.dragCoordinator.tabRowWidth == expectedWidth)
    }

    @Test("Tab row width has minimum value")
    func tabRowWidthHasMinimum() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()

        // Set very narrow sidebar bounds
        setupStandardFrames(support, sidebarWidth: 100)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Should have minimum width of 200
        #expect(support.dragCoordinator.tabRowWidth >= 200)
    }

    @Test("Tab row width falls back when sidebar bounds zero")
    func tabRowWidthFallback() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()

        // Setup frames first with default width
        setupStandardFrames(support)

        // Then set zero sidebar bounds AFTER setup
        support.dragCoordinator.updateSidebarBounds(.zero)

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Should fall back to 300 when sidebar width is 0
        #expect(support.dragCoordinator.tabRowWidth == 300)
    }

    // MARK: - Overlay Target Size Tests

    @Test("Overlay target size in tab row mode")
    func overlayTargetSizeInTabRowMode() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
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

        #expect(support.dragCoordinator.currentOverlayMode == .tabRow)

        let targetSize = support.dragCoordinator.overlayTargetSize
        #expect(targetSize.width == support.dragCoordinator.tabRowWidth)
        #expect(targetSize.height == Constants.Layout.tabItemHeight)
    }

    @Test("Overlay target size in tile mode")
    func overlayTargetSizeInTileMode() throws {
        let support = try SidebarTestSupport()
        let fav = support.createFavorite(title: "Fav", url: "https://fav.com")
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let favFrame = support.dragCoordinator.computedItemFrame(for: fav.id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(fav),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: favFrame.midX, y: favFrame.midY),
        )

        // Favorites start in tile mode
        if case .tile = support.dragCoordinator.currentOverlayMode {
            let targetSize = support.dragCoordinator.overlayTargetSize
            // Should match tile size from grid layout
            let expectedSize = support.dragCoordinator._favoritesGridLayout?.tileSize ?? CGSize(width: 80, height: 80)
            #expect(targetSize == expectedSize)
        }
    }

    @Test("Overlay position in sidebar coordinate system")
    func overlayPositionInSidebarCoordinateSystem() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()

        // Set sidebar bounds with non-zero origin
        setupStandardFrames(support)
        support.dragCoordinator.updateSidebarBounds(CGRect(x: 50, y: 100, width: 200, height: 500))

        let tabItem = support.layoutManager.normalItems.first!
        let originIndex = support.layoutManager.metadata[tabItem.id]!.globalIndex

        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = support.dragCoordinator.computedItemFrame(for: tabItem.id)!
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Set overlay position in global coordinates
        support.dragCoordinator.overlayPosition = CGPoint(x: 150, y: 250)

        // Position in sidebar should subtract sidebar origin
        let inSidebar = support.dragCoordinator.overlayPositionInSidebar
        #expect(inSidebar.x == 100) // 150 - 50
        #expect(inSidebar.y == 150) // 250 - 100
    }
}
