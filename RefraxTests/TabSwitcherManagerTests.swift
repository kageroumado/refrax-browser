import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for TabSwitcherManager operations.
    @Tag static var tabSwitcherManager: Self
}

// MARK: - Test Helper

/// Helper class to manage TabSwitcherManager lifecycle in tests.
///
/// TabSwitcherManager holds an `unowned` reference to WindowState and TabPreviewProvider,
/// and starts an async observation task. This helper ensures proper cleanup order to
/// prevent "unowned reference deallocated" crashes.
@MainActor
final class TabSwitcherTestContext {
    let env: TabManagerTestEnvironment
    let space: Space
    let windowState: WindowState
    let previewProvider: TabPreviewProvider
    var switcher: TabSwitcherManager?

    init() throws {
        self.env = try TabManagerTestEnvironment()
        self.space = env.makeSpace()
        self.windowState = env.makeActiveWindowState(with: space)
        self.previewProvider = TabPreviewProvider(
            tabManager: env.tabManager,
            windowState: windowState,
        )
        self.switcher = TabSwitcherManager(
            tabManager: env.tabManager,
            windowState: windowState,
            previewProvider: previewProvider,
        )
    }

    /// Cleans up in the correct order to prevent crashes.
    func cleanup() {
        // Deallocate switcher first (cancels its observation task)
        switcher = nil
        // Now windowState and previewProvider can be safely deallocated when this context is released
    }
}

// MARK: - TabSwitcherManager Initial State Tests

@Suite("TabSwitcherManager Initial State", .tags(.tabSwitcherManager), .serialized)
@MainActor
struct TabSwitcherInitialStateTests {
    @Test("Initially not active")
    func initiallyNotActive() throws {
        let ctx = try TabSwitcherTestContext()
        defer { ctx.cleanup() }

        #expect(ctx.switcher?.isActive == false)
        #expect(ctx.switcher?.selectedIndex == 0)
    }

    @Test("Initially has empty recent tabs")
    func initiallyEmptyRecentTabs() throws {
        let ctx = try TabSwitcherTestContext()
        defer { ctx.cleanup() }

        #expect(ctx.switcher?.recentTabs.isEmpty == true)
    }

    @Test("Cannot show switcher with no recent tabs")
    func cannotShowWithNoTabs() throws {
        let ctx = try TabSwitcherTestContext()
        defer { ctx.cleanup() }

        #expect(ctx.switcher?.canShowSwitcher == false)
    }
}

// MARK: - TabSwitcherManager Show/Dismiss Tests

@Suite("TabSwitcherManager Show Dismiss", .tags(.tabSwitcherManager), .serialized)
@MainActor
struct TabSwitcherShowDismissTests {
    @Test("Show is no-op when cannot show")
    func showNoOpWhenCannotShow() throws {
        let ctx = try TabSwitcherTestContext()
        defer { ctx.cleanup() }

        #expect(ctx.switcher?.canShowSwitcher == false)

        ctx.switcher?.show()

        #expect(ctx.switcher?.isActive == false, "Should not activate when cannot show")
    }

    @Test("Dismiss is no-op when not active")
    func dismissNoOpWhenNotActive() throws {
        let ctx = try TabSwitcherTestContext()
        defer { ctx.cleanup() }

        #expect(ctx.switcher?.isActive == false)

        ctx.switcher?.dismiss()

        #expect(ctx.switcher?.isActive == false)
        #expect(ctx.switcher?.selectedIndex == 0)
    }

    @Test("Cancel resets state")
    func cancelResetsState() throws {
        let ctx = try TabSwitcherTestContext()
        defer { ctx.cleanup() }

        ctx.switcher?.cancel()

        #expect(ctx.switcher?.isActive == false)
        #expect(ctx.switcher?.selectedIndex == 0)
    }
}

// MARK: - TabSwitcherManager Navigation Tests

@Suite("TabSwitcherManager Navigation", .tags(.tabSwitcherManager), .serialized)
@MainActor
struct TabSwitcherNavigationTests {
    @Test("Select next is no-op when not active")
    func selectNextNoOpWhenNotActive() throws {
        let ctx = try TabSwitcherTestContext()
        defer { ctx.cleanup() }

        #expect(ctx.switcher?.isActive == false)
        #expect(ctx.switcher?.selectedIndex == 0)

        ctx.switcher?.selectNext()

        #expect(ctx.switcher?.selectedIndex == 0, "Should not change when not active")
    }

    @Test("Select previous is no-op when not active")
    func selectPreviousNoOpWhenNotActive() throws {
        let ctx = try TabSwitcherTestContext()
        defer { ctx.cleanup() }

        #expect(ctx.switcher?.isActive == false)

        ctx.switcher?.selectPrevious()

        #expect(ctx.switcher?.selectedIndex == 0, "Should not change when not active")
    }
}

// MARK: - TabSwitcherManager Preview Tests

@Suite("TabSwitcherManager Preview", .tags(.tabSwitcherManager), .serialized)
@MainActor
struct TabSwitcherPreviewTests {
    @Test("Preview returns nil for uncached tab")
    func previewReturnsNilUncached() throws {
        let ctx = try TabSwitcherTestContext()
        defer { ctx.cleanup() }

        let tab = ctx.env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: ctx.space,
            makeActive: true,
        )

        // Preview is nil because no WebPage is loaded (no WKWebView in tests)
        #expect(ctx.switcher?.preview(for: tab) == nil)
    }
}

@Suite("Tab switcher interactions", .serialized)
@MainActor
struct TabSwitcherInteractionTests {
    private func activateAndObserve(_ tab: Tab, in ctx: TabSwitcherTestContext) async throws {
        ctx.env.tabManager.setActiveTab(tab, in: ctx.windowState)
        for _ in 0..<100 where ctx.switcher?.recentTabs.first?.id != tab.id {
            try await Task.sleep(for: .milliseconds(2))
        }
        #expect(ctx.switcher?.recentTabs.first?.id == tab.id)
    }

    private func makePair(in ctx: TabSwitcherTestContext) async throws -> (Tab, Tab) {
        let first = ctx.env.tabManager.createTab(url: URL(string: "about:blank#first")!, in: ctx.space, makeActive: false)
        let second = ctx.env.tabManager.createTab(url: URL(string: "about:blank#second")!, in: ctx.space, makeActive: false)
        try await activateAndObserve(first, in: ctx)
        try await activateAndObserve(second, in: ctx)
        return (first, second)
    }

    @Test
    func pointerPickerTogglesAndIgnoresModifierRelease() async throws {
        let ctx = try TabSwitcherTestContext()
        defer { ctx.cleanup() }
        let (_, second) = try await makePair(in: ctx)
        let switcher = try #require(ctx.switcher)
        switcher.toggle()
        #expect(switcher.isActive)
        switcher.controlReleased()
        #expect(switcher.isActive)
        #expect(ctx.windowState.activeTabID == second.id)
        switcher.toggle()
        #expect(!switcher.isActive)
        switcher.toggle()
        switcher.cancel()
        #expect(!switcher.isActive)
        #expect(ctx.windowState.activeTabID == second.id)
    }

    @Test
    func controlTabReturnsAcrossSpaces() async throws {
        let ctx = try TabSwitcherTestContext()
        defer { ctx.cleanup() }
        let (_, firstSpaceTab) = try await makePair(in: ctx)
        let otherSpace = ctx.env.makeSpace(name: "Preview space")
        let preview = ctx.env.tabManager.createTab(url: URL(string: "about:blank#preview")!, in: otherSpace, makeActive: false)
        ctx.env.spaceManager.switchToSpaceSync(otherSpace, for: ctx.windowState)
        try await activateAndObserve(preview, in: ctx)
        let switcher = try #require(ctx.switcher)
        switcher.show()
        switcher.controlReleased()
        #expect(ctx.windowState.activeSpaceID == ctx.space.id)
        #expect(ctx.windowState.activeTabID == firstSpaceTab.id)
        switcher.show()
        switcher.controlReleased()
        #expect(ctx.windowState.activeSpaceID == otherSpace.id)
        #expect(ctx.windowState.activeTabID == preview.id)
        #expect(ctx.windowState.focusedPageID == preview.activePage.id)
    }

    @Test
    func pointerSelectionActivatesAndCloses() async throws {
        let ctx = try TabSwitcherTestContext()
        defer { ctx.cleanup() }
        let (first, _) = try await makePair(in: ctx)
        let switcher = try #require(ctx.switcher)
        switcher.toggle()
        switcher.activate(tabID: first.id)
        #expect(!switcher.isActive)
        #expect(ctx.windowState.activeTabID == first.id)
    }

    @Test
    func closingSelectedTabCannotActivateItsNeighbor() async throws {
        let ctx = try TabSwitcherTestContext()
        defer { ctx.cleanup() }
        let (first, second) = try await makePair(in: ctx)
        let switcher = try #require(ctx.switcher)
        switcher.show()
        ctx.env.tabManager.closeTab(first)
        switcher.controlReleased()
        #expect(!switcher.isActive)
        #expect(ctx.windowState.activeTabID == second.id)
    }

    @Test
    func reselectingTheActiveTabKeepsVideoInThePage() throws {
        let ctx = try TabSwitcherTestContext()
        defer { ctx.cleanup() }
        ctx.env.settings.autoPiPOnTabSwitch = true
        let tab = ctx.env.tabManager.createTab(url: URL(string: "about:blank")!, in: ctx.space, makeActive: true)
        _ = try #require(ctx.env.pagePool.page(for: tab.activePage))
        ctx.env.tabManager.setActiveTab(tab, in: ctx.windowState)
        #expect(ctx.env.browserState.pipCoordinator.pendingSourceTabID == nil)
    }

    @Test
    func quickReturnCancelsPendingAutoPictureInPicture() throws {
        let ctx = try TabSwitcherTestContext()
        defer { ctx.cleanup() }
        ctx.env.settings.autoPiPOnTabSwitch = true
        let source = ctx.env.tabManager.createTab(url: URL(string: "about:blank#source")!, in: ctx.space, makeActive: true)
        let other = ctx.env.tabManager.createTab(url: URL(string: "about:blank#other")!, in: ctx.space, makeActive: false)
        _ = try #require(ctx.env.pagePool.page(for: source.activePage))
        ctx.env.tabManager.setActiveTab(other, in: ctx.windowState)
        #expect(ctx.env.browserState.pipCoordinator.pendingSourceTabID == source.id)
        ctx.env.tabManager.setActiveTab(source, in: ctx.windowState)
        #expect(ctx.env.browserState.pipCoordinator.pendingSourceTabID != source.id)
        #expect(!ctx.env.browserState.pipCoordinator.isAutoPiP)
    }

    @Test
    func activationFromAnyControlPromotesTheLivePreview() throws {
        let ctx = try TabSwitcherTestContext()
        defer { ctx.cleanup() }
        let tab = ctx.env.tabManager.createTab(url: URL(string: "about:blank")!, in: ctx.space, makeActive: false)
        let page = try #require(ctx.env.pagePool.page(for: tab.activePage))
        let session = FloatingPreviewSession()
        #expect(session.acquire(page, windowID: ObjectIdentifier(ctx.windowState)))
        #expect(page.isInFloatingPreview)
        ctx.env.tabManager.setActiveTab(tab, in: ctx.windowState)
        #expect(page.isOwner(ctx.windowState))
        #expect(!page.isInFloatingPreview)
        session.release()
        #expect(page.isOwner(ctx.windowState))
    }
}
