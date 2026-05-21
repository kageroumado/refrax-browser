import Foundation
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for SidebarManagers wiring.
    @Tag static var sidebarManagers: Self
}

// MARK: - SidebarManagers Initialization Tests

@Suite("SidebarManagers Initialization", .tags(.sidebarManagers))
@MainActor
struct SidebarManagersInitializationTests {
    @Test("Creates all managers")
    func createsAllManagers() throws {
        let env = try TabManagerTestEnvironment()

        let managers = SidebarManagers(
            tabManager: env.tabManager,
            bookmarksManager: env.bookmarksManager,
            windowState: env.makeWindowState(),
            groupManager: env.groupManager,
            undoRedoManager: env.undoRedoManager,
            settings: env.settings,
        )

        _ = managers.layoutManager
        _ = managers.dragCoordinator
        _ = managers.filterManager
        _ = managers.selectionManager
    }
}

// MARK: - SidebarManagers Wiring Tests

@Suite("SidebarManagers Wiring", .tags(.sidebarManagers))
@MainActor
struct SidebarManagersWiringTests {
    @Test("LayoutManager has tabManager")
    func layoutManagerHasTabManager() throws {
        let env = try TabManagerTestEnvironment()

        let managers = SidebarManagers(
            tabManager: env.tabManager,
            bookmarksManager: env.bookmarksManager,
            windowState: env.makeWindowState(),
            groupManager: env.groupManager,
            undoRedoManager: env.undoRedoManager,
            settings: env.settings,
        )

        #expect(managers.layoutManager.tabManager === env.tabManager)
    }

    @Test("LayoutManager has bookmarksManager")
    func layoutManagerHasBookmarksManager() throws {
        let env = try TabManagerTestEnvironment()

        let managers = SidebarManagers(
            tabManager: env.tabManager,
            bookmarksManager: env.bookmarksManager,
            windowState: env.makeWindowState(),
            groupManager: env.groupManager,
            undoRedoManager: env.undoRedoManager,
            settings: env.settings,
        )

        #expect(managers.layoutManager.bookmarksManager === env.bookmarksManager)
    }

    @Test("LayoutManager has filterManager")
    func layoutManagerHasFilterManager() throws {
        let env = try TabManagerTestEnvironment()

        let managers = SidebarManagers(
            tabManager: env.tabManager,
            bookmarksManager: env.bookmarksManager,
            windowState: env.makeWindowState(),
            groupManager: env.groupManager,
            undoRedoManager: env.undoRedoManager,
            settings: env.settings,
        )

        #expect(managers.layoutManager.filterManager === managers.filterManager)
    }

    @Test("LayoutManager has dragCoordinator")
    func layoutManagerHasDragCoordinator() throws {
        let env = try TabManagerTestEnvironment()

        let managers = SidebarManagers(
            tabManager: env.tabManager,
            bookmarksManager: env.bookmarksManager,
            windowState: env.makeWindowState(),
            groupManager: env.groupManager,
            undoRedoManager: env.undoRedoManager,
            settings: env.settings,
        )

        #expect(managers.layoutManager.dragCoordinator === managers.dragCoordinator)
    }

    @Test("LayoutManager has windowState")
    func layoutManagerHasWindowState() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let managers = SidebarManagers(
            tabManager: env.tabManager,
            bookmarksManager: env.bookmarksManager,
            windowState: windowState,
            groupManager: env.groupManager,
            undoRedoManager: env.undoRedoManager,
            settings: env.settings,
        )

        #expect(managers.layoutManager.windowState === windowState)
    }

    @Test("DragCoordinator has layoutManager")
    func dragCoordinatorHasLayoutManager() throws {
        let env = try TabManagerTestEnvironment()

        let managers = SidebarManagers(
            tabManager: env.tabManager,
            bookmarksManager: env.bookmarksManager,
            windowState: env.makeWindowState(),
            groupManager: env.groupManager,
            undoRedoManager: env.undoRedoManager,
            settings: env.settings,
        )

        #expect(managers.dragCoordinator.layoutManager === managers.layoutManager)
    }

    @Test("DragCoordinator has tabManager")
    func dragCoordinatorHasTabManager() throws {
        let env = try TabManagerTestEnvironment()

        let managers = SidebarManagers(
            tabManager: env.tabManager,
            bookmarksManager: env.bookmarksManager,
            windowState: env.makeWindowState(),
            groupManager: env.groupManager,
            undoRedoManager: env.undoRedoManager,
            settings: env.settings,
        )

        #expect(managers.dragCoordinator.tabManager === env.tabManager)
    }

    @Test("SelectionManager has layoutManager")
    func selectionManagerHasLayoutManager() throws {
        let env = try TabManagerTestEnvironment()

        let managers = SidebarManagers(
            tabManager: env.tabManager,
            bookmarksManager: env.bookmarksManager,
            windowState: env.makeWindowState(),
            groupManager: env.groupManager,
            undoRedoManager: env.undoRedoManager,
            settings: env.settings,
        )

        #expect(managers.selectionManager.layoutManager === managers.layoutManager)
    }

    @Test("SelectionManager has windowState")
    func selectionManagerHasWindowState() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let managers = SidebarManagers(
            tabManager: env.tabManager,
            bookmarksManager: env.bookmarksManager,
            windowState: windowState,
            groupManager: env.groupManager,
            undoRedoManager: env.undoRedoManager,
            settings: env.settings,
        )

        #expect(managers.selectionManager.windowState === windowState)
    }

    @Test("FilterManager has pageLookup closure")
    func filterManagerHasPageLookup() throws {
        let env = try TabManagerTestEnvironment()

        let managers = SidebarManagers(
            tabManager: env.tabManager,
            bookmarksManager: env.bookmarksManager,
            windowState: env.makeWindowState(),
            groupManager: env.groupManager,
            undoRedoManager: env.undoRedoManager,
            settings: env.settings,
        )

        #expect(managers.filterManager.pageLookup != nil)
    }
}

// MARK: - Notes

//
// SidebarManagers tests verify the wiring contract:
// - All four managers are created
// - LayoutManager receives all dependencies
// - DragCoordinator references LayoutManager and TabManager
// - SelectionManager references LayoutManager and WindowState
// - FilterManager receives pageLookup closure
//
// This is critical for sidebar functionality since:
// - Managers use unowned references (must be wired before use)
// - Cross-references enable coordinated operations
// - Missing dependencies cause runtime crashes
//
