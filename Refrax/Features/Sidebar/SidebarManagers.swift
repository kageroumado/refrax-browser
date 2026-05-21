import Foundation
import Observation

// MARK: - Sidebar Namespace Extensions

extension Sidebar {
    /// Container holding dependencies needed for building the sidebar empty area context menu.
    ///
    /// This container is passed via environment to avoid capturing managers in closures
    /// within `SidebarEmptyAreaContextMenu`. All managers are `@ObservationIgnored` since
    /// they are already observable and we don't want this container to trigger updates
    /// when the managers change.
    ///
    /// ## Usage
    ///
    /// ```swift
    /// @Environment(Sidebar.DependencyContainer.self) private var dependencies
    ///
    /// SidebarEmptyAreaContextMenu {
    ///     SidebarContextMenus.buildEmptyAreaMenu(
    ///         tabManager: dependencies.tabManager,
    ///         windowState: dependencies.windowState,
    ///         ...
    ///     )
    /// }
    /// ```
    @Observable
    final class DependencyContainer {
        @ObservationIgnored let tabManager: TabManager
        @ObservationIgnored let windowState: WindowState
        @ObservationIgnored let layoutManager: Sidebar.LayoutManager
        @ObservationIgnored let filterManager: Sidebar.FilterManager
        @ObservationIgnored let selectionManager: Sidebar.TabSelectionManager
        @ObservationIgnored let groupManager: TabGroupManager
        @ObservationIgnored let undoRedoManager: UndoRedoManager
        @ObservationIgnored let settings: BrowserSettings

        /// Toggled from the empty-area context menu to show the window background popover.
        var showWindowBackgroundPopover = false

        init(
            tabManager: TabManager,
            windowState: WindowState,
            layoutManager: Sidebar.LayoutManager,
            filterManager: Sidebar.FilterManager,
            selectionManager: Sidebar.TabSelectionManager,
            groupManager: TabGroupManager,
            undoRedoManager: UndoRedoManager,
            settings: BrowserSettings,
        ) {
            self.tabManager = tabManager
            self.windowState = windowState
            self.layoutManager = layoutManager
            self.filterManager = filterManager
            self.selectionManager = selectionManager
            self.groupManager = groupManager
            self.undoRedoManager = undoRedoManager
            self.settings = settings
        }
    }
}

// MARK: - SidebarManagers

/// Container for sidebar-related managers that persist for the window lifecycle.
///
/// These managers are created once per window in `RefraxWindowController` and injected
/// into the environment. This avoids recreating them when the sidebar view rebuilds
/// (e.g., during hover-to-appear animations).
///
/// ## Architecture
///
/// The managers maintain cross-references to coordinate sidebar operations:
///
/// ```
/// ┌──────────────────────────────────────────────────────────────┐
/// │                    SidebarManagers                            │
/// ├──────────────────────────────────────────────────────────────┤
/// │  LayoutManager ←──────── DragCoordinator                     │
/// │       │                       │                               │
/// │       ├── FilterManager       │                               │
/// │       │                       │                               │
/// │       └── TabSelectionManager │                               │
/// └──────────────────────────────────────────────────────────────┘
/// ```
///
/// ## Lifecycle
///
/// Created during window initialization and persisted until window closes.
/// The sidebar view reads these managers from the environment instead of
/// creating them locally with `@State`.
struct SidebarManagers {
    let layoutManager: Sidebar.LayoutManager
    let dragCoordinator: Sidebar.DragCoordinator
    let filterManager: Sidebar.FilterManager
    let selectionManager: Sidebar.TabSelectionManager
    let mediaControlsManager: Sidebar.MediaControlsManager
    let shelfManager: ShelfManager
    let transitionCoordinator: Sidebar.TransitionCoordinator
    let middleClickCoordinator: Sidebar.MiddleClickCoordinator
    let dependencyContainer: Sidebar.DependencyContainer
    let frameRegistry: Sidebar.FrameRegistry
    let geometryState: Sidebar.GeometryState

    /// Creates sidebar managers with all dependencies wired.
    ///
    /// - Parameters:
    ///   - tabManager: The tab manager for accessing tabs and spaces.
    ///   - bookmarksManager: The bookmarks manager for favorites access.
    ///   - windowState: The window state for active space/tab tracking.
    ///   - groupManager: The tab group manager for group operations.
    ///   - undoRedoManager: The undo/redo manager for browser-level undo.
    ///   - settings: The browser settings for preferences access.
    init(
        tabManager: TabManager,
        bookmarksManager: BookmarksManager,
        windowState: WindowState,
        groupManager: TabGroupManager,
        undoRedoManager: UndoRedoManager,
        settings: BrowserSettings,
    ) {
        let layoutManager = Sidebar.LayoutManager()
        let dragCoordinator = Sidebar.DragCoordinator()
        let filterManager = Sidebar.FilterManager()
        let selectionManager = Sidebar.TabSelectionManager()
        let mediaControlsManager = Sidebar.MediaControlsManager()
        let shelfManager = ShelfManager()
        let transitionCoordinator = Sidebar.TransitionCoordinator()
        let middleClickCoordinator = Sidebar.MiddleClickCoordinator()
        let frameRegistry = Sidebar.FrameRegistry()
        let geometryState = Sidebar.GeometryState()

        self.layoutManager = layoutManager
        self.dragCoordinator = dragCoordinator
        self.filterManager = filterManager
        self.selectionManager = selectionManager
        self.mediaControlsManager = mediaControlsManager
        self.shelfManager = shelfManager
        self.transitionCoordinator = transitionCoordinator
        self.middleClickCoordinator = middleClickCoordinator
        self.frameRegistry = frameRegistry
        self.geometryState = geometryState
        self.dependencyContainer = Sidebar.DependencyContainer(
            tabManager: tabManager,
            windowState: windowState,
            layoutManager: layoutManager,
            filterManager: filterManager,
            selectionManager: selectionManager,
            groupManager: groupManager,
            undoRedoManager: undoRedoManager,
            settings: settings,
        )

        layoutManager.tabManager = tabManager
        layoutManager.bookmarksManager = bookmarksManager
        layoutManager.filterManager = filterManager
        layoutManager.dragCoordinator = dragCoordinator
        layoutManager.windowState = windowState

        // Wire incremental layout update callbacks
        tabManager.state.onIncrementalRemoval = { [weak layoutManager] itemID, context in
            guard let layoutManager else { return false }
            guard let activeSpace = layoutManager.windowState?.activeSpace,
                  activeSpace.id == context.spaceID else {
                return false // Not active space, let full rebuild handle it
            }
            layoutManager.removeItemIncremental(itemID, context: context)
            return true
        }

        tabManager.state.onBatchRemoval = { [weak layoutManager] itemIDs, spaceID in
            guard let layoutManager else { return false }
            guard let activeSpace = layoutManager.windowState?.activeSpace,
                  activeSpace.id == spaceID else {
                return false // Not active space, let full rebuild handle it
            }
            layoutManager.batchRemoveItems(itemIDs, from: spaceID)
            return true
        }

        // Wire collapse handler for incremental collapse/expand updates
        groupManager.collapseHandler = layoutManager

        geometryState.layoutManager = layoutManager

        dragCoordinator.layoutManager = layoutManager
        dragCoordinator.tabManager = tabManager
        dragCoordinator.windowState = windowState
        dragCoordinator.frameRegistry = frameRegistry
        dragCoordinator.state = geometryState

        selectionManager.layoutManager = layoutManager
        selectionManager.windowState = windowState

        middleClickCoordinator.layoutManager = layoutManager
        middleClickCoordinator.tabManager = tabManager
        middleClickCoordinator.windowState = windowState
        middleClickCoordinator.state = geometryState

        transitionCoordinator.layoutManager = layoutManager

        frameRegistry.layoutManager = layoutManager

        filterManager.pageLookup = { [weak tabManager] tabPage in
            tabManager?.pagePool.existingPage(for: tabPage)
        }

        mediaControlsManager.pagePool = tabManager.pagePool

        mediaControlsManager.tabLookup = { [weak tabManager] pageID in
            guard let state = tabManager?.state else { return nil }

            // Search in all spaces
            for space in state.spaces {
                if let tab = state.tabs(in: space).first(where: { $0.pages.contains { $0.id == pageID } }) {
                    return tab
                }
            }

            // Search in live favorite tabs
            return state.liveFavoriteTabs.first { $0.pages.contains { $0.id == pageID } }
        }

        mediaControlsManager.activeSpaceIDLookup = { [weak windowState] in
            windowState?.activeSpaceID
        }
    }
}
