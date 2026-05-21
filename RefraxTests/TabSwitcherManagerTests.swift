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

// MARK: - Notes

//
// Full TabSwitcherManager functionality requires async observation of WindowState.activeTabID.
// The following behaviors require the observation to fire (tested via integration tests):
//
// 1. Tab activation recording - happens via @Observable observation
// 2. Recent tabs population - requires tab activations to be recorded
// 3. Show with selection - requires populated recent tabs
// 4. Navigation wrap-around - requires active state with tabs
// 5. Preview caching - requires WebView snapshot capability
//
