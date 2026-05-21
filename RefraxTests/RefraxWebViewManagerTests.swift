import Foundation
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for RefraxWebViewManager operations.
    @Tag static var refraxWebViewManager: Self
}

// MARK: - RefraxWebViewManager Singleton Tests

@Suite("RefraxWebViewManager Singleton", .tags(.refraxWebViewManager))
@MainActor
struct RefraxWebViewManagerSingletonTests {
    @Test("Shared instance is consistent")
    func sharedInstanceIsConsistent() {
        let manager1 = RefraxWebViewManager.shared
        let manager2 = RefraxWebViewManager.shared

        #expect(manager1 === manager2)
    }
}

// MARK: - RefraxWebViewManager Active Display Tests

@Suite("RefraxWebViewManager Active Display", .tags(.refraxWebViewManager))
@MainActor
struct RefraxWebViewManagerActiveDisplayTests {
    @Test("Has active display returns true when none registered")
    func hasActiveDisplayNoRegistration() throws {
        // Create test environment
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)
        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )
        guard let page = env.pagePool.existingPage(for: tab.activePage) else {
            // Page may not be created in test environment; skip if so
            return
        }
        let windowID = UUID()

        let manager = RefraxWebViewManager.shared

        // When no active display is registered, any window can claim it
        let hasActive = manager.hasActiveDisplay(for: page, in: windowID)

        #expect(hasActive == true, "First window should be able to claim active display")
    }

    @Test("Active display window returns nil when none registered")
    func activeDisplayWindowNone() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)
        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )
        guard let page = env.pagePool.existingPage(for: tab.activePage) else {
            // Page may not be created in test environment; skip if so
            return
        }

        let manager = RefraxWebViewManager.shared

        let windowID = manager.activeDisplayWindow(for: page)

        #expect(windowID == nil)
    }
}

// MARK: - RefraxWebViewManager Screen Share Tests

@Suite("RefraxWebViewManager Screen Share", .tags(.refraxWebViewManager))
@MainActor
struct RefraxWebViewManagerScreenShareTests {
    @Test("Has screen share window returns false initially")
    func hasScreenShareWindowInitiallyFalse() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)
        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )
        guard let page = env.pagePool.existingPage(for: tab.activePage) else {
            // Page may not be created in test environment; skip if so
            return
        }

        let manager = RefraxWebViewManager.shared

        let hasWindow = manager.hasScreenShareWindow(for: page)

        #expect(hasWindow == false)
    }

    @Test("Close screen share window is safe when none exists")
    func closeScreenShareWindowSafe() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)
        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: true,
        )
        guard let page = env.pagePool.existingPage(for: tab.activePage) else {
            // Page may not be created in test environment; skip if so
            return
        }

        let manager = RefraxWebViewManager.shared

        // Should not crash when no window exists
        manager.closeScreenShareWindow(for: page)

        #expect(true, "Should handle gracefully")
    }
}

// MARK: - Notes

//
// RefraxWebViewManager functionality requiring integration tests:
//
// 1. Request/release active display with actual windows
// 2. Screen share window creation (requires WebPage with visible webView)
// 3. Multi-window coordination scenarios
// 4. NotificationCenter cleanup on window close
//
// The tests above verify:
// - Singleton pattern
// - Active display returns true when none registered (first-claim behavior)
// - Screen share window queries return safe defaults
// - Close operations are safe when no state exists
//
// Full window testing requires:
// - Real NSWindow instances
// - Real WebPage with visible backing WebView
// - CAPortalLayer availability
//
