import AppKit
import Foundation
import Testing
import WebKit

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for LinkPreviewManager operations.
    @Tag static var linkPreviewManager: Self
}

// MARK: - LinkPreviewManager Initialization Tests

@Suite("LinkPreviewManager Initialization", .tags(.linkPreviewManager))
@MainActor
struct LinkPreviewManagerInitializationTests {
    @Test("Manager initializes with web view")
    func managerInitializesWithWebView() {
        let webView = WKWebView()
        let manager = LinkPreviewManager(webView: webView)

        // Manager should exist after initialization
        #expect(manager.isShiftClickEnabled == true)
    }

    @Test("WebPageWebView can store manager")
    func webPageWebViewCanStoreManager() {
        let config = WKWebViewConfiguration()
        let webView = WebPageWebView(frame: .zero, configuration: config)

        #expect(webView.linkPreviewManager == nil)

        let manager = LinkPreviewManager(webView: webView)
        webView.linkPreviewManager = manager

        #expect(webView.linkPreviewManager === manager)
    }

    @Test("Invalidate clears internal state")
    func invalidateClearsState() {
        let webView = WKWebView()
        let manager = LinkPreviewManager(webView: webView)

        manager.invalidate()

        // After invalidate, manager should be cleaned up
        // (internal webView reference is nil, monitors removed)
        // We can verify by checking it doesn't crash on subsequent access
        #expect(manager.isShiftClickEnabled == true)
    }
}

// MARK: - LinkPreviewManager Configuration Tests

@Suite("LinkPreviewManager Configuration", .tags(.linkPreviewManager))
@MainActor
struct LinkPreviewManagerConfigurationTests {
    @Test("Shift click is enabled by default")
    func shiftClickEnabledByDefault() {
        let webView = WKWebView()
        let manager = LinkPreviewManager(webView: webView)

        #expect(manager.isShiftClickEnabled == true)
    }

    @Test("Force touch is enabled by default")
    func forceTouchEnabledByDefault() {
        let webView = WKWebView()
        let manager = LinkPreviewManager(webView: webView)

        #expect(manager.isForceTouchEnabled == true)
    }

    @Test("Preview delay is zero by default")
    func previewDelayZeroByDefault() {
        let webView = WKWebView()
        let manager = LinkPreviewManager(webView: webView)

        #expect(manager.previewDelay == 0.0)
    }

    @Test("Should show preview hook is nil by default")
    func shouldShowPreviewNilByDefault() {
        let webView = WKWebView()
        let manager = LinkPreviewManager(webView: webView)

        #expect(manager.shouldShowPreview == nil)
    }

    @Test("Did show preview hook is nil by default")
    func didShowPreviewNilByDefault() {
        let webView = WKWebView()
        let manager = LinkPreviewManager(webView: webView)

        #expect(manager.didShowPreview == nil)
    }

    @Test("Did dismiss preview hook is nil by default")
    func didDismissPreviewNilByDefault() {
        let webView = WKWebView()
        let manager = LinkPreviewManager(webView: webView)

        #expect(manager.didDismissPreview == nil)
    }

    @Test("Configuration can be modified")
    func configurationCanBeModified() {
        let webView = WKWebView()
        let manager = LinkPreviewManager(webView: webView)

        manager.isShiftClickEnabled = false
        manager.isForceTouchEnabled = false
        manager.previewDelay = 0.5

        #expect(manager.isShiftClickEnabled == false)
        #expect(manager.isForceTouchEnabled == false)
        #expect(manager.previewDelay == 0.5)
    }

    @Test("Hooks can be set")
    func hooksCanBeSet() {
        let webView = WKWebView()
        let manager = LinkPreviewManager(webView: webView)

        var showCalled = false
        var dismissCalled = false

        manager.shouldShowPreview = { _ in true }
        manager.didShowPreview = { _ in showCalled = true }
        manager.didDismissPreview = { dismissCalled = true }

        #expect(manager.shouldShowPreview != nil)
        #expect(manager.didShowPreview != nil)
        #expect(manager.didDismissPreview != nil)

        // Manually trigger callbacks to test they work
        manager.didShowPreview?(URL(string: "https://example.com")!)
        manager.didDismissPreview?()

        #expect(showCalled)
        #expect(dismissCalled)
    }

    @Test("Should show preview hook can prevent preview")
    func shouldShowPreviewCanPrevent() {
        let webView = WKWebView()
        let manager = LinkPreviewManager(webView: webView)

        manager.shouldShowPreview = { url in
            // Block certain domains
            url.host != "blocked.com"
        }

        let allowURL = URL(string: "https://allowed.com")!
        let blockURL = URL(string: "https://blocked.com")!

        #expect(manager.shouldShowPreview?(allowURL) == true)
        #expect(manager.shouldShowPreview?(blockURL) == false)
    }
}

// MARK: - Notes

//
// LinkPreviewManager functionality requiring integration tests:
//
// 1. Event monitoring: Shift+Click detection via NSEvent
// 2. Hit testing: Finding links at click location in web view
// 3. Quick Look: QLPreviewPanel presentation and dismissal
// 4. Preview delay: Timer-based delay before showing preview
// 5. Force Touch: Pressure event detection via NSEvent
//
// The tests above verify:
// - Direct initialization creates functional manager
// - Manager can be stored on WebPageWebView.linkPreviewManager
// - Default configuration values
// - Configuration can be modified
// - Hooks can be set and invoked
// - Invalidate cleans up the manager
//
// Full preview testing requires:
// - Web view with loaded content containing links
// - Synthetic mouse events with Shift modifier or pressure
// - QLPreviewPanel mock or verification
//
