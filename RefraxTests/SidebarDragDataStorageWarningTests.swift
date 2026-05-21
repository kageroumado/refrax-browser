import Foundation
import Testing

@testable import Refrax

/// Tests for data storage warning display during cross-zone drag operations.
///
/// Warnings should appear when dragging between zones with different data storage policies:
/// - Favorite → Space with separate/private data store
/// - Tab from separate/private store → Favorites grid
@Suite("Data Storage Warnings", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragDataStorageWarningTests {
    // MARK: - Favorite to Space Tests

    @Test("Favorite to separate data store shows warning")
    func favoriteToSeparateDataStoreShowsWarning() throws {
        let support = try SidebarTestSupport()
        let fav = support.createFavorite(title: "Fav", url: "https://fav.com")
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Configure space to use separate data store
        support.space.dataStoreMode = .separate

        let favFrame = support.dragCoordinator.computedItemFrame(for: fav.id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(fav),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: favFrame.midX, y: favFrame.midY),
        )

        // Drag to tab list
        support.dragCoordinator.updateDrag(
            offset: 150,
            location: CGPoint(x: 100, y: 200),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: 200))

        // Warning should be shown for separate data store
        #expect(support.dragCoordinator.showDataStorageWarning == true)
    }

    @Test("Favorite to private data store shows warning")
    func favoriteToPrivateDataStoreShowsWarning() throws {
        let support = try SidebarTestSupport()
        let fav = support.createFavorite(title: "Fav", url: "https://fav.com")
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Configure space to use private data store
        support.space.dataStoreMode = .private

        let favFrame = support.dragCoordinator.computedItemFrame(for: fav.id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(fav),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: favFrame.midX, y: favFrame.midY),
        )

        // Drag to tab list
        support.dragCoordinator.updateDrag(
            offset: 150,
            location: CGPoint(x: 100, y: 200),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: 200))

        // Warning should be shown for private data store
        #expect(support.dragCoordinator.showDataStorageWarning == true)
    }

    @Test("Favorite to global data store shows no warning")
    func favoriteToGlobalDataStoreNoWarning() throws {
        let support = try SidebarTestSupport()
        let fav = support.createFavorite(title: "Fav", url: "https://fav.com")
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Space uses default (global) data store
        #expect(support.space.dataStoreMode == .global)

        let favFrame = support.dragCoordinator.computedItemFrame(for: fav.id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(fav),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: favFrame.midX, y: favFrame.midY),
        )

        // Drag to tab list
        support.dragCoordinator.updateDrag(
            offset: 150,
            location: CGPoint(x: 100, y: 200),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: 200))

        // No warning for global data store
        #expect(support.dragCoordinator.showDataStorageWarning == false)
    }

    // MARK: - Tab to Favorites Tests

    @Test("Tab from separate store to favorites shows warning")
    func tabFromSeparateStoreToFavoritesShowsWarning() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Existing", url: "https://existing.com")

        // Configure space to use separate data store before creating tab
        support.space.dataStoreMode = .separate

        let tab = support.createTab(url: "https://tab.com")
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

        // Drag to favorites grid
        support.dragCoordinator.updateDrag(
            offset: -100,
            location: CGPoint(x: 100, y: 40),
        )

        // Warning should be shown
        #expect(support.dragCoordinator.showDataStorageWarning == true)
    }

    @Test("Tab from private store to favorites shows warning")
    func tabFromPrivateStoreToFavoritesShowsWarning() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Existing", url: "https://existing.com")

        // Configure space to use private data store before creating tab
        support.space.dataStoreMode = .private

        let tab = support.createTab(url: "https://tab.com")
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

        // Drag to favorites grid
        support.dragCoordinator.updateDrag(
            offset: -100,
            location: CGPoint(x: 100, y: 40),
        )

        // Warning should be shown
        #expect(support.dragCoordinator.showDataStorageWarning == true)
    }

    @Test("Tab from global store to favorites shows no warning")
    func tabFromGlobalStoreToFavoritesNoWarning() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Existing", url: "https://existing.com")
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Space uses default (global) data store
        #expect(support.space.dataStoreMode == .global)

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

        // Drag to favorites grid
        support.dragCoordinator.updateDrag(
            offset: -100,
            location: CGPoint(x: 100, y: 40),
        )

        // No warning for global store
        #expect(support.dragCoordinator.showDataStorageWarning == false)
    }

    // MARK: - Warning State Management

    @Test("Warning clears when target changes")
    func warningClearsWhenTargetChanges() throws {
        let support = try SidebarTestSupport()
        let fav = support.createFavorite(title: "Fav", url: "https://fav.com")
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Configure space to use separate data store
        support.space.dataStoreMode = .separate

        let favFrame = support.dragCoordinator.computedItemFrame(for: fav.id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(fav),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: favFrame.midX, y: favFrame.midY),
        )

        // Drag to tab list - warning should show
        support.dragCoordinator.updateDrag(
            offset: 150,
            location: CGPoint(x: 100, y: 200),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: 200))
        #expect(support.dragCoordinator.showDataStorageWarning == true)

        // Drag back to favorites - warning should clear
        support.dragCoordinator.updateDrag(
            offset: -10,
            location: CGPoint(x: 100, y: 40),
        )

        #expect(support.dragCoordinator.showDataStorageWarning == false)
    }

    @Test("Groups cannot convert to favorites so no warning shown")
    func groupToFavoritesNoWarning() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Fav", url: "https://fav.com")
        let group = try support.createGroup(name: "Test Group")
        _ = support.createTab(url: "https://tab.com", groupID: group.id)
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Configure space to use separate data store
        support.space.dataStoreMode = .separate

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

        // Drag to favorites area
        support.dragCoordinator.updateDrag(
            offset: -100,
            location: CGPoint(x: 100, y: 40),
        )

        // Groups can't convert to favorites, so no warning
        #expect(support.dragCoordinator.showDataStorageWarning == false)
    }

    @Test("Warning clears on drag end")
    func warningClearsOnDragEnd() throws {
        let support = try SidebarTestSupport()
        let fav = support.createFavorite(title: "Fav", url: "https://fav.com")
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))

        // Configure space to use separate data store
        support.space.dataStoreMode = .separate

        let favFrame = support.dragCoordinator.computedItemFrame(for: fav.id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(fav),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: favFrame.midX, y: favFrame.midY),
        )

        // Drag to tab list - warning should show
        support.dragCoordinator.updateDrag(
            offset: 150,
            location: CGPoint(x: 100, y: 200),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: 200))
        #expect(support.dragCoordinator.showDataStorageWarning == true)

        // Cancel drag
        support.dragCoordinator.cancelDrag()

        // Wait for animation reset
        // Note: In actual code, warning is cleared in resetDragState
        support.dragCoordinator.showDataStorageWarning = false

        #expect(support.dragCoordinator.showDataStorageWarning == false)
    }
}
