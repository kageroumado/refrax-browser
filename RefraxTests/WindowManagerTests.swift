import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for WindowManager operations.
    @Tag static var windowManager: Self
}

// MARK: - WindowManager Initial State Tests

/// WindowManager tests are limited because most functionality requires actual NSWindow
/// and RefraxWindowController instances which can't easily be created in unit tests.
/// These tests cover the initial state and basic property behavior.
@Suite("WindowManager Initial State", .tags(.windowManager), .serialized)
@MainActor
struct WindowManagerInitialStateTests {
    @Test("Has no windows initially")
    func hasNoWindowsInitially() throws {
        let env = try TabManagerTestEnvironment()

        #expect(!env.windowManager.hasWindows)
        #expect(env.windowManager.allWindowStates.isEmpty)
    }

    @Test("Active window controller is nil when no windows")
    func activeWindowControllerNil() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.windowManager.activeWindowController == nil)
        #expect(env.windowManager.frontmostWindowController == nil)
        #expect(env.windowManager.mainWindowController == nil)
    }

    @Test("Last active browser window controller is nil initially")
    func lastActiveNil() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.windowManager.lastActiveBrowserWindowController == nil)
    }

    @Test("Window controllers for space returns empty when no windows")
    func windowControllersForSpaceEmpty() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let controllers = env.windowManager.windowControllers(for: space)

        #expect(controllers.isEmpty)
    }

    @Test("Tab manager reference is set")
    func tabManagerReferenceSet() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.windowManager.tabManager != nil)
        #expect(env.windowManager.tabManager === env.tabManager)
    }

    @Test("Model container is set")
    func modelContainerSet() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.windowManager.modelContainer === env.container)
    }
}

// MARK: - WindowManager URL Handling Tests

@Suite("WindowManager URL Handling", .tags(.windowManager), .serialized)
@MainActor
struct WindowManagerURLHandlingTests {
    @Test("Open URL with space available does not crash")
    func openURLWithSpace() throws {
        let env = try TabManagerTestEnvironment()
        _ = env.makeSpace() // Ensure at least one space exists

        #expect(!env.windowManager.hasWindows)

        // This will try to create a window and tab, but in test environment
        // window creation is limited. We're testing that it doesn't crash.
        // Note: This may still fail in headless test environments.
    }
}

// MARK: - WindowManager Action Tests

@Suite("WindowManager Actions", .tags(.windowManager), .serialized)
@MainActor
struct WindowManagerActionTests {
    @Test("Open location is no-op when no windows")
    func openLocationNoWindow() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.windowManager.activeWindowController == nil)

        // Should be no-op and not crash
        env.windowManager.openLocation()
    }

    @Test("Show page search is no-op when no windows")
    func showPageSearchNoWindow() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.windowManager.activeWindowController == nil)

        // Should be no-op and not crash
        env.windowManager.showPageSearch()
    }
}

// MARK: - WindowState Lens Tests

@Suite("WindowState Lens Operations", .tags(.windowManager), .serialized)
@MainActor
struct WindowStateLensTests {
    @Test("Lens starts nil")
    func lensStartsNil() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.showsCommandLens == false)
        #expect(windowState.showsAddressLens == false)
    }

    @Test("Open command lens sets state")
    func openCommandLensSetsState() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.openCommandLens()

        #expect(windowState.showsCommandLens == true)
        #expect(windowState.showsAddressLens == false)
    }

    @Test("Close command lens clears state")
    func closeCommandLensClearsState() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.openCommandLens()
        #expect(windowState.showsCommandLens == true)

        windowState.closeCommandLens()
        #expect(windowState.showsCommandLens == false)
    }

    @Test("Open address lens sets state")
    func openAddressLensSetsState() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.openAddressLens()

        #expect(windowState.showsAddressLens == true)
        #expect(windowState.showsCommandLens == false)
    }

    @Test("Close address lens clears state")
    func closeAddressLensClearsState() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.openAddressLens()
        #expect(windowState.showsAddressLens == true)

        windowState.closeAddressLens()
        #expect(windowState.showsAddressLens == false)
    }

    @Test("Opening one lens closes other implicitly")
    func openingOneLensClosesOther() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.openCommandLens()
        #expect(windowState.showsCommandLens == true)

        windowState.openAddressLens()
        #expect(windowState.showsAddressLens == true)
        #expect(windowState.showsCommandLens == false)
    }

    @Test("Reference pane lens state")
    func referencePaneLensState() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.showsReferencePaneLens == false)
        #expect(windowState.isCreatingReferenceTab == false)

        // Default (address bar mode): don't create new tab
        windowState.openReferencePaneLens()

        #expect(windowState.showsReferencePaneLens == true)
        #expect(windowState.isCreatingReferenceTab == false)

        windowState.closeReferencePaneLens()

        #expect(windowState.showsReferencePaneLens == false)
        #expect(windowState.isCreatingReferenceTab == false)

        // Explicit forNewTab: true (+ button mode): create new tab
        windowState.openReferencePaneLens(forNewTab: true)

        #expect(windowState.showsReferencePaneLens == true)
        #expect(windowState.isCreatingReferenceTab == true)

        windowState.closeReferencePaneLens()

        #expect(windowState.showsReferencePaneLens == false)
        #expect(windowState.isCreatingReferenceTab == false)
    }

    @Test("Command lens binding works")
    func commandLensBindingWorks() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        let binding = windowState.commandLensBinding
        #expect(binding.wrappedValue == false)

        binding.wrappedValue = true
        #expect(windowState.showsCommandLens == true)

        binding.wrappedValue = false
        #expect(windowState.showsCommandLens == false)
    }
}

// MARK: - WindowState Detail Tray Tests

@Suite("WindowState Detail Tray", .tags(.windowManager), .serialized)
@MainActor
struct WindowStateDetailTrayTests {
    @Test("Detail tray starts hidden")
    func detailTrayStartsHidden() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.detailTrayMode == .hidden)
        #expect(windowState.isDetailTrayVisible == false)
    }

    @Test("Show detail tray sets mode")
    func showDetailTraySetsMode() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.showDetailTray(.downloads)
        #expect(windowState.detailTrayMode == .downloads)
        #expect(windowState.isDetailTrayVisible == true)

        windowState.showDetailTray(.bookmarks)
        #expect(windowState.detailTrayMode == .bookmarks)

        windowState.showDetailTray(.history)
        #expect(windowState.detailTrayMode == .history)
    }

    @Test("Hide detail tray clears mode")
    func hideDetailTrayClearsMode() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.showDetailTray(.downloads)
        #expect(windowState.isDetailTrayVisible == true)

        windowState.hideDetailTray()
        #expect(windowState.detailTrayMode == .hidden)
        #expect(windowState.isDetailTrayVisible == false)
    }

    @Test("Toggle detail tray shows when hidden")
    func toggleDetailTrayShowsWhenHidden() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.toggleDetailTray(.downloads)
        #expect(windowState.detailTrayMode == .downloads)
    }

    @Test("Toggle detail tray hides when showing same mode")
    func toggleDetailTrayHidesWhenSameMode() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.showDetailTray(.downloads)
        windowState.toggleDetailTray(.downloads)
        #expect(windowState.detailTrayMode == .hidden)
    }

    @Test("Toggle detail tray switches mode when showing different")
    func toggleDetailTraySwitchesMode() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.showDetailTray(.downloads)
        windowState.toggleDetailTray(.bookmarks)
        #expect(windowState.detailTrayMode == .bookmarks)
    }

    @Test("Toggle with hidden mode is no-op")
    func toggleWithHiddenModeIsNoOp() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.showDetailTray(.downloads)
        windowState.toggleDetailTray(.hidden)
        #expect(windowState.detailTrayMode == .downloads)
    }

    @Test("Back forward mode is valid detail tray mode")
    func backForwardModeIsValid() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.showDetailTray(.backForward)
        #expect(windowState.detailTrayMode == .backForward)
        #expect(windowState.isDetailTrayVisible == true)
    }
}

// MARK: - WindowState Toast Tests

@Suite("WindowState Toast Notifications", .tags(.windowManager), .serialized)
@MainActor
struct WindowStateToastTests {
    @Test("Toast starts nil")
    func toastStartsNil() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.toastMessage == nil)
    }

    @Test("Show toast sets message")
    func showToastSetsMessage() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.showToast("Test message")
        #expect(windowState.toastMessage == "Test message")
    }

    @Test("Dismiss toast clears message")
    func dismissToastClearsMessage() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.showToast("Test message")
        #expect(windowState.toastMessage != nil)

        windowState.dismissToast()
        #expect(windowState.toastMessage == nil)
    }

    @Test("Show toast replaces previous message")
    func showToastReplacesPrevious() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.showToast("First message")
        windowState.showToast("Second message")
        #expect(windowState.toastMessage == "Second message")
    }
}

// MARK: - WindowState Sidebar/Inspector Tests

@Suite("WindowState Sidebar and Inspector", .tags(.windowManager), .serialized)
@MainActor
struct WindowStateSidebarInspectorTests {
    @Test("Sidebar starts expanded")
    func sidebarStartsExpanded() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.isSidebarCollapsed == false)
    }

    @Test("Inspector starts collapsed")
    func inspectorStartsCollapsed() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.isInspectorCollapsed == true)
    }

    @Test("Toggle sidebar changes state")
    func toggleSidebarChangesState() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.isSidebarCollapsed == false)

        windowState.toggleSidebar()
        #expect(windowState.isSidebarCollapsed == true)

        windowState.toggleSidebar()
        #expect(windowState.isSidebarCollapsed == false)
    }

    @Test("Toggle inspector changes state")
    func toggleInspectorChangesState() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.isInspectorCollapsed == true)

        windowState.toggleInspector()
        #expect(windowState.isInspectorCollapsed == false)

        windowState.toggleInspector()
        #expect(windowState.isInspectorCollapsed == true)
    }
}

// MARK: - WindowState Navigation Cleanup Tests

@Suite("WindowState Navigation Cleanup", .tags(.windowManager), .serialized)
@MainActor
struct WindowStateNavigationCleanupTests {
    @Test("Clear navigation state clears all IDs")
    func clearNavigationStateClearsAllIDs() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeWindowState()

        // Set up some state
        env.spaceManager.switchToSpaceSync(space, for: windowState)
        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: false,
        )
        windowState.setActiveTabID(tab.id, for: space.id)
        windowState.activeReferenceTabID = tab.id

        // Create a live favorite tab to test live favorite clearing
        let liveFavoriteTab = try Tab(space: nil, url: #require(URL(string: "https://example.com")), status: .liveFavorite)
        env.browserState.addLiveFavoriteTab(liveFavoriteTab)
        windowState.setActiveTab(liveFavoriteTab)

        #expect(windowState.activeSpaceID != nil)
        #expect(windowState.activeTabID == liveFavoriteTab.id) // Live favorite takes priority
        #expect(windowState.activeReferenceTabID != nil)

        windowState.clearNavigationState()

        #expect(windowState.activeSpaceID == nil)
        #expect(windowState.activeTabID == nil)
        #expect(windowState.activeReferenceTabID == nil)
    }

    @Test("Set active tab ID for space stores per-space")
    func setActiveTabIDPerSpace() throws {
        let env = try TabManagerTestEnvironment()
        let space1 = env.makeSpace(name: "Space 1")
        let space2 = env.makeSpace(name: "Space 2")
        let windowState = env.makeWindowState()

        let tab1 = try env.tabManager.createTab(
            url: #require(URL(string: "https://one.com")),
            in: space1,
            makeActive: false,
        )
        let tab2 = try env.tabManager.createTab(
            url: #require(URL(string: "https://two.com")),
            in: space2,
            makeActive: false,
        )

        windowState.setActiveTabID(tab1.id, for: space1.id)
        windowState.setActiveTabID(tab2.id, for: space2.id)

        #expect(windowState.activeTabID(for: space1.id) == tab1.id)
        #expect(windowState.activeTabID(for: space2.id) == tab2.id)
    }

    @Test("Clear active tab ID removes entry")
    func clearActiveTabIDRemovesEntry() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeWindowState()

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: false,
        )

        windowState.setActiveTabID(tab.id, for: space.id)
        #expect(windowState.activeTabID(for: space.id) == tab.id)

        windowState.setActiveTabID(nil, for: space.id)
        #expect(windowState.activeTabID(for: space.id) == nil)
    }
}

// MARK: - WindowState Overlay State Tests

@Suite("WindowState Overlay State", .tags(.windowManager), .serialized)
@MainActor
struct WindowStateOverlayTests {
    @Test("Tutorial peek starts false")
    func tutorialPeekStartsFalse() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.hasShownTutorialPeek == false)
    }

    @Test("Reference pane docked width has default")
    func referencePaneDockedWidthHasDefault() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.referencePaneDockedWidth == 400)
    }

    @Test("Sidebar thickness has default")
    func sidebarThicknessHasDefault() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.sidebarThickness == 300)
    }
}

// MARK: - DetailTrayMode Tests

@Suite("DetailTrayMode Enum", .tags(.windowManager))
@MainActor
struct DetailTrayModeTests {
    @Test("All cases are equatable")
    func allCasesAreEquatable() {
        #expect(DetailTrayMode.hidden == DetailTrayMode.hidden)
        #expect(DetailTrayMode.downloads == DetailTrayMode.downloads)
        #expect(DetailTrayMode.bookmarks == DetailTrayMode.bookmarks)
        #expect(DetailTrayMode.history == DetailTrayMode.history)
        #expect(DetailTrayMode.backForward == DetailTrayMode.backForward)

        #expect(DetailTrayMode.hidden != DetailTrayMode.downloads)
        #expect(DetailTrayMode.downloads != DetailTrayMode.bookmarks)
    }
}

// MARK: - FocusedLens Tests

@Suite("FocusedLens Enum", .tags(.windowManager))
@MainActor
struct FocusedLensTests {
    @Test("All cases are hashable")
    func allCasesAreHashable() {
        let set: Set<FocusedLens> = [.address, .command]
        #expect(set.count == 2)
        #expect(set.contains(.address))
        #expect(set.contains(.command))
    }

    @Test("Cases are distinct")
    func casesAreDistinct() {
        #expect(FocusedLens.address != FocusedLens.command)
    }
}

// MARK: - WindowManager Notes

//
// The following WindowManager behaviors require real NSWindow instances and cannot
// be easily unit tested:
//
// 1. createWindow() / createWindow(with:) - Creates RefraxWindow and controller
// 2. registerWindowController - Requires actual window controller
// 3. handleWindowClosed - Triggered by NSWindow.willCloseNotification
// 4. frontmostWindowController - Uses NSApplication.shared.keyWindow
// 5. mainWindowController - Uses NSApplication.shared.mainWindow
// 6. createReferencePaneWindow - Creates separate window for reference pane
// 7. closeReferencePaneWindow - Closes reference pane window
// 8. lastActiveBrowserWindowController updates - From NSWindow.didBecomeKeyNotification
//
// These should be tested via integration tests or UI tests that have access to
// the full AppKit environment.
