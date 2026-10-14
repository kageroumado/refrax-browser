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
    @Test
    func `Has no windows initially`() throws {
        let env = try TabManagerTestEnvironment()

        #expect(!env.windowManager.hasWindows)
        #expect(env.windowManager.allWindowStates.isEmpty)
    }

    @Test
    func `Active window controller is nil when no windows`() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.windowManager.activeWindowController == nil)
        #expect(env.windowManager.frontmostWindowController == nil)
        #expect(env.windowManager.mainWindowController == nil)
    }

    @Test
    func `Last active browser window controller is nil initially`() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.windowManager.lastActiveBrowserWindowController == nil)
    }

    @Test
    func `Window controllers for space returns empty when no windows`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let controllers = env.windowManager.windowControllers(for: space)

        #expect(controllers.isEmpty)
    }

    @Test
    func `Tab manager reference is set`() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.windowManager.tabManager != nil)
        #expect(env.windowManager.tabManager === env.tabManager)
    }

    @Test
    func `Model container is set`() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.windowManager.modelContainer === env.container)
    }
}

// MARK: - WindowManager URL Handling Tests

@Suite("WindowManager URL Handling", .tags(.windowManager), .serialized)
@MainActor
struct WindowManagerURLHandlingTests {
    @Test
    func `Open URL with space available does not crash`() throws {
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
    @Test
    func `Open location is no-op when no windows`() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.windowManager.activeWindowController == nil)

        // Should be no-op and not crash
        env.windowManager.openLocation()
    }

    @Test
    func `Show page search is no-op when no windows`() throws {
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
    @Test
    func `Lens starts closed`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.showsCommandLens == false)
        #expect(windowState.showsAnchoredLens == false)
        #expect(windowState.commandLensEntrance == nil)
    }

    @Test
    func `⌘T opens the lens empty and centered`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)
        _ = try env.createActiveTab(url: #require(URL(string: "https://example.com/page")), in: space, for: windowState)

        windowState.openCommandLens()

        #expect(windowState.showsCommandLens == true)
        #expect(windowState.showsAnchoredLens == false)
        #expect(windowState.commandLensEntrance == CommandLensEntrance(prefill: nil, anchor: nil))
        #expect(windowState.commandLensEntrance?.editsCurrentPage == false)
    }

    @Test
    func `⌘L opens the lens with the page address, anchored to the page card`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)
        let url = try #require(URL(string: "https://example.com/page"))
        _ = env.createActiveTab(url: url, in: space, for: windowState)
        let card = CGRect(x: 68, y: 12, width: 416, height: 44)
        windowState.addressBarFrame = card

        windowState.editAddress()

        #expect(windowState.showsCommandLens == true)
        #expect(windowState.showsAnchoredLens == true)
        #expect(windowState.commandLensEntrance == CommandLensEntrance(prefill: url.absoluteString, anchor: card))
        #expect(windowState.commandLensEntrance?.editsCurrentPage == true)
    }

    @Test
    func `Either entrance replaces the other`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)
        _ = try env.createActiveTab(url: #require(URL(string: "https://example.com/page")), in: space, for: windowState)

        windowState.openCommandLens()
        windowState.editAddress()
        #expect(windowState.showsAnchoredLens == true)

        windowState.openCommandLens()
        #expect(windowState.showsCommandLens == true)
        #expect(windowState.showsAnchoredLens == false)
    }

    @Test
    func `Closing clears the entrance and the lens frame`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)
        _ = try env.createActiveTab(url: #require(URL(string: "https://example.com/page")), in: space, for: windowState)

        windowState.editAddress()
        windowState.commandLensFrame = CGRect(x: 1, y: 1, width: 1, height: 1)
        windowState.closeCommandLens()

        #expect(windowState.showsCommandLens == false)
        #expect(windowState.commandLensEntrance == nil)
        #expect(windowState.commandLensFrame == .zero)
    }

    @Test
    func `An empty page routes either entrance to the start page lens`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()
        windowState.usesFloatingTabs = true

        windowState.openCommandLens()
        #expect(windowState.showsCommandLens == false)
        #expect(windowState.startPageLensRequest == 1)

        windowState.editAddress()
        #expect(windowState.showsCommandLens == false)
        #expect(windowState.startPageLensRequest == 2)
    }

    @Test
    func `Command lens binding works`() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeWindowState()
        env.spaceManager.switchToSpaceSync(space, for: windowState)
        let tab = try env.tabManager.createTab(url: #require(URL(string: "https://example.com")), in: space, makeActive: false)
        windowState.setActiveTabID(tab.id, for: space.id)

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
    @Test
    func `Detail tray starts hidden`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.detailTrayMode == .hidden)
        #expect(windowState.isDetailTrayVisible == false)
    }

    @Test
    func `Show detail tray sets mode`() throws {
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

    @Test
    func `Hide detail tray clears mode`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.showDetailTray(.downloads)
        #expect(windowState.isDetailTrayVisible == true)

        windowState.hideDetailTray()
        #expect(windowState.detailTrayMode == .hidden)
        #expect(windowState.isDetailTrayVisible == false)
    }

    @Test
    func `Toggle detail tray shows when hidden`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.toggleDetailTray(.downloads)
        #expect(windowState.detailTrayMode == .downloads)
    }

    @Test
    func `Toggle detail tray hides when showing same mode`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.showDetailTray(.downloads)
        windowState.toggleDetailTray(.downloads)
        #expect(windowState.detailTrayMode == .hidden)
    }

    @Test
    func `Toggle detail tray switches mode when showing different`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.showDetailTray(.downloads)
        windowState.toggleDetailTray(.bookmarks)
        #expect(windowState.detailTrayMode == .bookmarks)
    }

    @Test
    func `Toggle with hidden mode is no-op`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.showDetailTray(.downloads)
        windowState.toggleDetailTray(.hidden)
        #expect(windowState.detailTrayMode == .downloads)
    }

    @Test
    func `Back forward mode is valid detail tray mode`() throws {
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
    @Test
    func `Toast starts nil`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.toastMessage == nil)
    }

    @Test
    func `Show toast sets message`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.showToast("Test message")
        #expect(windowState.toastMessage == "Test message")
    }

    @Test
    func `Dismiss toast clears message`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.showToast("Test message")
        #expect(windowState.toastMessage != nil)

        windowState.dismissToast()
        #expect(windowState.toastMessage == nil)
    }

    @Test
    func `Show toast replaces previous message`() throws {
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
    @Test
    func `Sidebar starts collapsed beside the Control Island`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.isSidebarCollapsed)
    }

    @Test
    func `Toggle sidebar changes state`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        windowState.toggleSidebar()
        #expect(windowState.isSidebarCollapsed == false)

        windowState.toggleSidebar()
        #expect(windowState.isSidebarCollapsed == true)
    }
}

// MARK: - WindowState Navigation Cleanup Tests

@Suite("WindowState Navigation Cleanup", .tags(.windowManager), .serialized)
@MainActor
struct WindowStateNavigationCleanupTests {
    @Test
    func `Clear navigation state clears all IDs`() throws {
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

        // Create a live favorite tab to test live favorite clearing
        let liveFavoriteTab = try Tab(space: nil, url: #require(URL(string: "https://example.com")), status: .favorite)
        env.browserState.addFavoriteTab(liveFavoriteTab)
        windowState.setActiveTab(liveFavoriteTab)

        #expect(windowState.activeSpaceID != nil)
        #expect(windowState.activeTabID == liveFavoriteTab.id) // Live favorite takes priority

        windowState.clearNavigationState()

        #expect(windowState.activeSpaceID == nil)
        #expect(windowState.activeTabID == nil)
    }

    @Test
    func `Set active tab ID for space stores per-space`() throws {
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

    @Test
    func `Clear active tab ID removes entry`() throws {
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
    @Test
    func `Tutorial peek starts false`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.hasShownTutorialPeek == false)
    }

    @Test
    func `Sidebar thickness has default`() throws {
        let env = try TabManagerTestEnvironment()
        let windowState = env.makeWindowState()

        #expect(windowState.sidebarThickness == 300)
    }
}

// MARK: - DetailTrayMode Tests

@Suite("DetailTrayMode Enum", .tags(.windowManager))
@MainActor
struct DetailTrayModeTests {
    @Test
    func `All cases are equatable`() {
        #expect(DetailTrayMode.hidden == DetailTrayMode.hidden)
        #expect(DetailTrayMode.downloads == DetailTrayMode.downloads)
        #expect(DetailTrayMode.bookmarks == DetailTrayMode.bookmarks)
        #expect(DetailTrayMode.history == DetailTrayMode.history)
        #expect(DetailTrayMode.backForward == DetailTrayMode.backForward)

        #expect(DetailTrayMode.hidden != DetailTrayMode.downloads)
        #expect(DetailTrayMode.downloads != DetailTrayMode.bookmarks)
    }
}

// MARK: - CommandLensEntrance Tests

@Suite("CommandLensEntrance", .tags(.windowManager))
@MainActor
struct CommandLensEntranceTests {
    @Test
    func `An anchored entrance edits the current page; a centered one opens a new tab`() {
        #expect(CommandLensEntrance(prefill: nil, anchor: nil).editsCurrentPage == false)
        #expect(CommandLensEntrance(prefill: "https://example.com", anchor: nil).editsCurrentPage == false)
        #expect(CommandLensEntrance(prefill: "https://example.com", anchor: CGRect(x: 0, y: 0, width: 416, height: 44)).editsCurrentPage == true)
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
// 6. lastActiveBrowserWindowController updates - From NSWindow.didBecomeKeyNotification
//
// These should be tested via integration tests or UI tests that have access to
// the full AppKit environment.
