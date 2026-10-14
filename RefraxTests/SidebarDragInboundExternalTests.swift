import Foundation
import Testing
@testable import Refrax

/// Tests for handling external drags (URLs from other apps) entering the sidebar.
///
/// External drops are different from internal drags - they come from outside
/// the app and can contain URLs, files, or other data types.
@Suite("Inbound External Drops", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragInboundExternalTests {
    // MARK: - Test Helpers

    private func setupStandardFrames(_ support: SidebarTestSupport, startY _: CGFloat = 100) {
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
    }

    // MARK: - Inbound Drop Zone Tests

    @Test
    func `Inbound drop zone set on external entry`() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Fav", url: "https://fav.com")
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Initially no inbound drop zone
        #expect(support.dragCoordinator.inboundDropZone == nil)

        // Simulate external drag entry by setting inbound drop zone
        support.dragCoordinator.inboundDropZone = .favoritesGrid

        #expect(support.dragCoordinator.inboundDropZone == .favoritesGrid)
    }

    @Test
    func `isReceivingExternalDrop returns true when inboundDropZone set`() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Initially not receiving external drop
        #expect(support.dragCoordinator.isReceivingExternalDrop == false)

        // Set inbound drop zone
        support.dragCoordinator.inboundDropZone = .normalSection

        #expect(support.dragCoordinator.isReceivingExternalDrop == true)
    }

    @Test
    func `External drop zone highlights favorites`() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Fav", url: "https://fav.com")
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Set inbound drop zone to favorites
        support.dragCoordinator.inboundDropZone = .favoritesGrid

        #expect(support.dragCoordinator.inboundDropZone == .favoritesGrid)
        #expect(support.dragCoordinator.isReceivingExternalDrop == true)
    }

    @Test
    func `External drop zone highlights pinned`() throws {
        let support = try SidebarTestSupport()
        _ = try support.createGroup(name: "Pinned", isPinned: true)
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Set inbound drop zone to pinned
        support.dragCoordinator.inboundDropZone = .pinnedSection

        #expect(support.dragCoordinator.inboundDropZone == .pinnedSection)
        #expect(support.dragCoordinator.isReceivingExternalDrop == true)
    }

    @Test
    func `External drop zone highlights normal`() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Set inbound drop zone to normal
        support.dragCoordinator.inboundDropZone = .normalSection

        #expect(support.dragCoordinator.inboundDropZone == .normalSection)
        #expect(support.dragCoordinator.isReceivingExternalDrop == true)
    }

    @Test
    func `External drop zone transitions between sections`() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Fav", url: "https://fav.com")
        _ = try support.createGroup(name: "Pinned", isPinned: true)
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Start with favorites zone
        support.dragCoordinator.inboundDropZone = .favoritesGrid
        #expect(support.dragCoordinator.inboundDropZone == .favoritesGrid)

        // Transition to pinned
        support.dragCoordinator.inboundDropZone = .pinnedSection
        #expect(support.dragCoordinator.inboundDropZone == .pinnedSection)

        // Transition to normal
        support.dragCoordinator.inboundDropZone = .normalSection
        #expect(support.dragCoordinator.inboundDropZone == .normalSection)
    }

    @Test
    func `External drop cancellation clears state`() throws {
        let support = try SidebarTestSupport()
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        // Set inbound drop zone
        support.dragCoordinator.inboundDropZone = .normalSection
        #expect(support.dragCoordinator.isReceivingExternalDrop == true)

        // Clear on cancellation
        support.dragCoordinator.inboundDropZone = nil
        #expect(support.dragCoordinator.isReceivingExternalDrop == false)
        #expect(support.dragCoordinator.inboundDropZone == nil)
    }

    @Test
    func `External drop does not affect internal drag state`() throws {
        let support = try SidebarTestSupport()
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let tabItem = try #require(support.layoutManager.normalItems.first)
        let originIndex = try #require(support.layoutManager.metadata[tabItem.id]?.globalIndex)

        // Start internal drag
        let localIndex = originIndex - support.layoutManager.collectionBounds.normal.lowerBound
        let startFrame = try #require(support.dragCoordinator.computedItemFrame(for: tabItem.id))
        support.dragCoordinator.startDrag(
            item: .tab(tab),
            originPosition: .normal(localIndex: localIndex),
            startLocation: CGPoint(x: startFrame.midX, y: startFrame.midY),
        )

        // Verify internal drag state
        #expect(support.dragCoordinator.isDragging == true)
        #expect(support.dragCoordinator.draggedItems.count == 1)

        // Setting inbound drop zone shouldn't affect internal state
        support.dragCoordinator.inboundDropZone = .favoritesGrid

        // Internal drag state should be preserved
        #expect(support.dragCoordinator.isDragging == true)
        #expect(support.dragCoordinator.draggedItems.count == 1)
        #expect(support.dragCoordinator.inboundDropZone == .favoritesGrid)
    }
}
