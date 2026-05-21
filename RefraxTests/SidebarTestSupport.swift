import Foundation
import SwiftUI
import Testing

@testable import Refrax

@MainActor
struct SidebarTestSupport {
    let env: TabManagerTestEnvironment
    let space: Space
    let windowState: WindowState
    let managers: SidebarManagers

    var layoutManager: Sidebar.LayoutManager { managers.layoutManager }
    var dragCoordinator: Sidebar.DragCoordinator { managers.dragCoordinator }
    var filterManager: Sidebar.FilterManager { managers.filterManager }
    var selectionManager: Sidebar.TabSelectionManager { managers.selectionManager }

    init() throws {
        self.env = try TabManagerTestEnvironment()
        self.space = env.makeSpace()
        self.windowState = env.makeActiveWindowState(with: space)
        self.managers = SidebarManagers(
            tabManager: env.tabManager,
            bookmarksManager: env.bookmarksManager,
            windowState: windowState,
            groupManager: env.groupManager,
            undoRedoManager: env.undoRedoManager,
            settings: env.settings,
        )
        layoutManager.rebuildLayout()
    }

    @discardableResult
    func createTab(
        url: String,
        isPinned: Bool = false,
        groupID: UUID? = nil,
    ) -> Tab {
        env.tabManager.createTab(
            url: URL(string: url)!,
            in: space,
            groupID: groupID,
            isPinned: isPinned,
            makeActive: false,
        )
    }

    @discardableResult
    func createGroup(
        name: String,
        parentGroupID: UUID? = nil,
        isPinned: Bool = false,
    ) throws -> TabGroup {
        try env.groupManager.createGroup(
            in: space,
            name: name,
            parentGroupID: parentGroupID,
            isPinned: isPinned,
        )
    }

    @discardableResult
    func createFavorite(title: String, url: String) -> FavoriteItem {
        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: url)!,
            title: title,
        )
        env.bookmarksManager.addToFavorites(bookmark)
        layoutManager.rebuildLayout()
        return env.bookmarksManager.favorites.first { item in
            switch item.type {
            case let .liveFavorite(favorite, _):
                favorite.id == bookmark.id
            case let .shortcut(favorite):
                favorite.id == bookmark.id
            case .folder, .appShortcut:
                false
            }
        }!
    }

    func rebuildLayout() {
        layoutManager.rebuildLayout()
    }

    // MARK: - Geometry Setup

    /// Sets up scroll position for computed frame calculations.
    ///
    /// Call this after `rebuildLayout()` to enable computed frames in tests.
    /// The geometry state uses these values plus sidebar bounds to compute item frames.
    ///
    /// - Parameters:
    ///   - topInset: The scroll view top content inset (distance from scroll view frame top to content start).
    ///   - scrollOffset: Current scroll offset (positive when scrolled down).
    func setupScrollPosition(topInset: CGFloat = 0, scrollOffset: CGFloat = 0) {
        managers.geometryState.currentScrollTopInset = topInset
        managers.geometryState.documentToSidebarOffset = scrollOffset
    }

    /// Sets up sidebar geometry for tests.
    ///
    /// This is a convenience that sets sidebar bounds, scroll position, and favorites grid in one call.
    /// Use this at the start of tests that need computed frames.
    ///
    /// If favorites exist, sets up a favorites grid frame at the top of the sidebar.
    /// Also configures the grid layout for proper offset calculations.
    ///
    /// The scroll offset is calculated so that computed frames start at `contentStartY`.
    /// Formula: pinnedSectionMinY = scrollViewInsetPadding (8) + scrollTopInset + scrollOffset
    ///
    /// - Parameters:
    ///   - sidebarBounds: The sidebar container bounds in window coordinates.
    ///   - scrollTopInset: Scroll view top inset (default: 8 to match scrollViewInsetPadding).
    ///   - contentStartY: Y position where pinned section should start (default: 100 for test compatibility).
    ///   - favoritesGridHeight: Height of favorites grid area (default: 100). Set to 0 to disable.
    func setupTestGeometry(
        sidebarBounds: CGRect = CGRect(x: 0, y: 0, width: 200, height: 500),
        scrollTopInset: CGFloat = 8,
        contentStartY: CGFloat = 100,
        favoritesGridHeight: CGFloat = 100,
    ) {
        dragCoordinator.updateSidebarBounds(sidebarBounds)

        // Calculate scroll offset so pinnedSectionMinY = contentStartY
        // pinnedSectionMinY = scrollViewInsetPadding (8) + scrollTopInset + scrollOffset
        let scrollViewInsetPadding: CGFloat = 8
        let scrollOffset = contentStartY - scrollViewInsetPadding - scrollTopInset
        setupScrollPosition(topInset: scrollTopInset, scrollOffset: scrollOffset)

        // Set up favorites grid if there are favorites
        if !layoutManager.favoritesLayout.isEmpty, favoritesGridHeight > 0 {
            let gridFrame = CGRect(x: 0, y: 0, width: sidebarBounds.width, height: favoritesGridHeight)
            dragCoordinator.updateFavoritesGridFrame(gridFrame)
            // Set up grid layout for proper offset calculations
            let tileSize = Constants.Layout.tabItemHeight * 1.5
            dragCoordinator.updateFavoritesGridLayout(
                columns: max(1, Int(sidebarBounds.width / (tileSize + 8))),
                tileSize: CGSize(width: tileSize, height: tileSize),
                spacing: 8,
            )
        }
    }

    // MARK: - Frame Helpers (for validation, not storage)

    func assignSequentialFrames(
        for items: [TabListItem],
        startY: CGFloat = 0,
        width: CGFloat = 200,
    ) -> [UUID: CGRect] {
        var frames: [UUID: CGRect] = [:]
        var currentY = startY
        let height = Constants.Layout.tabItemHeight
        let spacing = Constants.Layout.tabSpacing

        for item in items {
            frames[item.id] = CGRect(x: 0, y: currentY, width: width, height: height)
            currentY += height + spacing
        }

        return frames
    }

    func sectionFrame(for items: [TabListItem], frames: [UUID: CGRect]) -> CGRect {
        let rects = items.compactMap { frames[$0.id] }
        guard var union = rects.first else { return .zero }
        for rect in rects.dropFirst() {
            union = union.union(rect)
        }
        return union
    }

    /// Clears the frame for an item (simulates item scrolling offscreen).
    func clearFrame(for id: UUID) {
        managers.frameRegistry.setTestFrame(nil, for: id)
    }
}
