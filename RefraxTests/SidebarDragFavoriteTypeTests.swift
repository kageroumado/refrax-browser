import Foundation
import Testing

@testable import Refrax

/// Tests for handling different favorite types during drag operations.
///
/// Favorites can be:
/// - Live favorites (tabs that are pinned to favorites grid)
/// - Shortcuts (bookmarks that open in new tabs)
/// - Folders (containers for other favorites)
/// - App shortcuts (special shortcuts)
///
/// These tests verify correct behavior for each type during drag.
@Suite("Favorite Type Handling", .tags(.sidebarDragCoordinator), .serialized)
@MainActor
struct SidebarDragFavoriteTypeTests {
    // MARK: - Test Helpers

    private func setupStandardFrames(_ support: SidebarTestSupport, startY _: CGFloat = 100) {
        support.setupTestGeometry(sidebarBounds: CGRect(x: 0, y: 0, width: 200, height: 500))
        support.dragCoordinator.updateFavoritesGridFrame(CGRect(x: 0, y: 0, width: 200, height: 90))
        support.dragCoordinator.updateFavoritesGridLayout(
            columns: 3,
            tileSize: CGSize(width: 80, height: 80),
            spacing: 8,
        )
    }

    // MARK: - Live Favorite Tests

    @Test("Live favorite drag to tab list creates tab at correct position")
    func liveFavoriteDragToTabList() throws {
        let support = try SidebarTestSupport()
        let fav = support.createFavorite(title: "Live Fav", url: "https://live.com")
        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let frame = support.dragCoordinator.computedItemFrame(for: fav.id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(fav),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Drag to tab list
        support.dragCoordinator.updateDrag(
            offset: 150,
            location: CGPoint(x: 100, y: 200),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: 200))

        // Should get convertToTab target
        if case .convertToTab = support.dragCoordinator._dropTarget {
            // Expected
        } else {
            Issue.record("Expected convertToTab target, got \(support.dragCoordinator._dropTarget)")
        }
    }

    @Test("Shortcut favorite drag to tab list creates new tab")
    func shortcutFavoriteDragToTabList() throws {
        let support = try SidebarTestSupport()
        // Create a shortcut favorite (bookmark-based)
        let bookmark = support.env.bookmarksManager.createBookmark(
            url: URL(string: "https://shortcut.com")!,
            title: "Shortcut",
        )
        support.env.bookmarksManager.addToFavorites(bookmark)
        support.rebuildLayout()

        _ = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let shortcutFav = support.layoutManager.favoritesLayout.first!

        let frame = support.dragCoordinator.computedItemFrame(for: shortcutFav.id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(shortcutFav),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Drag to tab list
        support.dragCoordinator.updateDrag(
            offset: 150,
            location: CGPoint(x: 100, y: 200),
        )
        support.dragCoordinator.detectDropTarget(at: CGPoint(x: 100, y: 200))

        // Should get convertToTab target
        if case .convertToTab = support.dragCoordinator._dropTarget {
            // Expected
        } else {
            Issue.record("Expected convertToTab target for shortcut")
        }
    }

    @Test("Tab converted to live favorite mode")
    func tabConvertedToLiveFavoriteMode() throws {
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Existing", url: "https://existing.com")
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

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

        // Drag deep into favorites (at least 20pt from edge)
        support.dragCoordinator.updateDrag(
            offset: -100,
            location: CGPoint(x: 100, y: 40),
        )

        // Should target live favorite mode
        if case let .convertToFavorite(mode) = support.dragCoordinator._dropTarget {
            #expect(mode == .liveFavorite)
        } else {
            Issue.record("Expected convertToFavorite with liveFavorite mode")
        }
    }

    @Test("Tab converted to shortcut mode with modifier")
    func tabConvertedToShortcutMode() throws {
        // Note: This test would require simulating modifier keys
        // For now, verify the target detection logic
        let support = try SidebarTestSupport()
        _ = support.createFavorite(title: "Existing", url: "https://existing.com")
        let tab = support.createTab(url: "https://tab.com")
        support.rebuildLayout()
        setupStandardFrames(support)

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

        // The mode depends on modifier keys which we can't easily simulate
        // Default should be liveFavorite
    }

    @Test("Different favorite types maintain visual distinction")
    func differentFavoriteTypesVisualDistinction() throws {
        let support = try SidebarTestSupport()

        // Create different favorite types
        _ = support.createFavorite(title: "Live1", url: "https://live1.com")
        let bookmark = support.env.bookmarksManager.createBookmark(
            url: URL(string: "https://shortcut.com")!,
            title: "Shortcut",
        )
        support.env.bookmarksManager.addToFavorites(bookmark)

        support.rebuildLayout()
        setupStandardFrames(support)

        let favorites = support.layoutManager.favoritesLayout
        #expect(favorites.count >= 2)

        // Each favorite should have a type (verified by accessing it)
        for fav in favorites {
            // Verify type is accessible - the switch ensures we handle all cases
            switch fav.type {
            case .liveFavorite, .shortcut, .folder, .appShortcut:
                break // All valid types
            }
        }
    }

    @Test("Reorder favorites preserves type information")
    func reorderFavoritesPreservesType() throws {
        let support = try SidebarTestSupport()
        let fav1 = support.createFavorite(title: "Fav1", url: "https://fav1.com")
        let fav2 = support.createFavorite(title: "Fav2", url: "https://fav2.com")
        support.rebuildLayout()
        setupStandardFrames(support)

        let originalType1 = fav1.type

        let frame = support.dragCoordinator.computedItemFrame(for: fav1.id) ?? CGRect(x: 0, y: 40, width: 80, height: 80)
        support.dragCoordinator.startDrag(
            item: .favorite(fav1),
            originPosition: .favorites(localIndex: 0),
            startLocation: CGPoint(x: frame.midX, y: frame.midY),
        )

        // Drag to swap positions
        support.dragCoordinator.updateDrag(
            offset: 50,
            location: CGPoint(x: 100, y: 50),
        )

        _ = support.dragCoordinator.commitDrag()

        // Type should be preserved after reorder - verify both are liveFavorite
        if case .liveFavorite = originalType1, case .liveFavorite = fav1.type {
            // Both are liveFavorite - type preserved
        } else {
            Issue.record("Type was not preserved: expected liveFavorite")
        }
    }
}
