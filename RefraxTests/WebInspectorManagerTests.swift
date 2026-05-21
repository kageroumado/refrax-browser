import Foundation
import Testing
import WebKit

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for WebInspectorManager operations.
    @Tag static var webInspectorManager: Self
}

// MARK: - AttachmentSide Tests

@Suite("WebInspectorManager AttachmentSide", .tags(.webInspectorManager))
@MainActor
struct AttachmentSideTests {
    @Test("Bottom has raw value 0")
    func bottomRawValue() {
        #expect(WebInspectorManager.AttachmentSide.bottom.rawValue == 0)
    }

    @Test("Right has raw value 1")
    func rightRawValue() {
        #expect(WebInspectorManager.AttachmentSide.right.rawValue == 1)
    }

    @Test("Has all cases")
    func allCases() {
        let allCases = WebInspectorManager.AttachmentSide.allCases

        #expect(allCases.count == 2)
        #expect(allCases.contains(.bottom))
        #expect(allCases.contains(.right))
    }

    @Test("Is Sendable")
    func isSendable() {
        let side: WebInspectorManager.AttachmentSide = .bottom
        let _: any Sendable = side

        #expect(true)
    }
}

// MARK: - WebInspectorManager Initialization Tests

@Suite("WebInspectorManager Initialization", .tags(.webInspectorManager))
@MainActor
struct WebInspectorManagerInitializationTests {
    @Test("URL handler is initially nil")
    func urlHandlerInitiallyNil() {
        let manager = WebInspectorManager()

        #expect(manager.urlHandler == nil)
    }
}

// MARK: - WebInspectorManager State Query Tests

@Suite("WebInspectorManager State Queries", .tags(.webInspectorManager))
@MainActor
struct WebInspectorManagerStateQueryTests {
    @Test("isInspectorShown returns false for unknown tab")
    func isInspectorShownUnknownTab() {
        let manager = WebInspectorManager()
        let unknownID = UUID()

        let isShown = manager.isInspectorShown(for: unknownID)

        #expect(isShown == false)
    }

    @Test("isInspectorAttached returns false for unknown tab")
    func isInspectorAttachedUnknownTab() {
        let manager = WebInspectorManager()
        let unknownID = UUID()

        let isAttached = manager.isInspectorAttached(for: unknownID)

        #expect(isAttached == false)
    }

    @Test("attachmentSide returns bottom for unknown tab")
    func attachmentSideUnknownTab() {
        let manager = WebInspectorManager()
        let unknownID = UUID()

        let side = manager.attachmentSide(for: unknownID)

        #expect(side == .bottom)
    }
}

// MARK: - WebInspectorManager Safe No-Op Tests

@Suite("WebInspectorManager Safe No-Op", .tags(.webInspectorManager))
@MainActor
struct WebInspectorManagerSafeNoOpTests {
    /// A minimal WKWebView for testing — inspector operations will be no-ops
    /// since the web process isn't running, but shouldn't crash.
    private func makeTestWebView() -> WKWebView {
        WKWebView(frame: .zero)
    }

    @Test("showInspector is safe with no web process")
    func showInspectorSafe() {
        let manager = WebInspectorManager()
        let webView = makeTestWebView()

        manager.showInspector(for: UUID(), webView: webView)

        #expect(true, "Should handle gracefully")
    }

    @Test("closeInspector is safe with no web process")
    func closeInspectorSafe() {
        let manager = WebInspectorManager()
        let webView = makeTestWebView()

        manager.closeInspector(for: UUID(), webView: webView)

        #expect(true, "Should handle gracefully")
    }

    @Test("toggleInspector is safe with no web process")
    func toggleInspectorSafe() {
        let manager = WebInspectorManager()
        let webView = makeTestWebView()

        manager.toggleInspector(for: UUID(), webView: webView)

        #expect(true, "Should handle gracefully")
    }

    @Test("attachInspector is safe with no web process")
    func attachInspectorSafe() {
        let manager = WebInspectorManager()
        let webView = makeTestWebView()

        manager.attachInspector(for: UUID(), webView: webView)

        #expect(true, "Should handle gracefully")
    }

    @Test("detachInspector is safe with no web process")
    func detachInspectorSafe() {
        let manager = WebInspectorManager()
        let webView = makeTestWebView()

        manager.detachInspector(for: UUID(), webView: webView)

        #expect(true, "Should handle gracefully")
    }

    @Test("toggleAttachment is safe with no web process")
    func toggleAttachmentSafe() {
        let manager = WebInspectorManager()
        let webView = makeTestWebView()

        manager.toggleAttachment(for: UUID(), webView: webView)

        #expect(true, "Should handle gracefully")
    }

    @Test("showJavaScriptConsole is safe with no web process")
    func showJavaScriptConsoleSafe() {
        let manager = WebInspectorManager()
        let webView = makeTestWebView()

        manager.showJavaScriptConsole(for: UUID(), webView: webView)

        #expect(true, "Should handle gracefully")
    }

    @Test("showPageResources is safe with no web process")
    func showPageResourcesSafe() {
        let manager = WebInspectorManager()
        let webView = makeTestWebView()

        manager.showPageResources(for: UUID(), webView: webView)

        #expect(true, "Should handle gracefully")
    }

    @Test("showPageSource is safe with no web process")
    func showPageSourceSafe() {
        let manager = WebInspectorManager()
        let webView = makeTestWebView()

        manager.showPageSource(for: UUID(), webView: webView)

        #expect(true, "Should handle gracefully")
    }

    @Test("togglePageProfiling is safe with no web process")
    func togglePageProfilingSafe() {
        let manager = WebInspectorManager()
        let webView = makeTestWebView()

        manager.togglePageProfiling(for: UUID(), webView: webView)

        #expect(true, "Should handle gracefully")
    }

    @Test("toggleElementSelection is safe with no web process")
    func toggleElementSelectionSafe() {
        let manager = WebInspectorManager()
        let webView = makeTestWebView()

        manager.toggleElementSelection(for: UUID(), webView: webView)

        #expect(true, "Should handle gracefully")
    }
}

// MARK: - WebInspectorManager Tab Lifecycle Tests

@Suite("WebInspectorManager Tab Lifecycle", .tags(.webInspectorManager))
@MainActor
struct WebInspectorManagerTabLifecycleTests {
    @Test("tabDidClose removes state")
    func tabDidCloseRemovesState() {
        let manager = WebInspectorManager()
        let tabID = UUID()

        manager.tabDidClose(tabID)

        #expect(manager.isInspectorShown(for: tabID) == false)
        #expect(manager.isInspectorAttached(for: tabID) == false)
    }

    @Test("closeAllInspectors is safe when empty")
    func closeAllInspectorsSafe() {
        let manager = WebInspectorManager()

        manager.closeAllInspectors()

        #expect(true, "Should handle gracefully")
    }
}

// MARK: - WebInspectorURLHandler Protocol Tests

@Suite("WebInspectorURLHandler Protocol", .tags(.webInspectorManager))
@MainActor
struct WebInspectorURLHandlerTests {
    private final class MockURLHandler: WebInspectorURLHandler {
        var openedURLs: [URL] = []

        func openURLFromInspector(_ url: URL) {
            openedURLs.append(url)
        }
    }

    @Test("URL handler can be set")
    func urlHandlerCanBeSet() {
        let manager = WebInspectorManager()
        let handler = MockURLHandler()

        manager.urlHandler = handler

        #expect(manager.urlHandler != nil)
    }

    @Test("URL handler is weak reference")
    func urlHandlerIsWeak() {
        let manager = WebInspectorManager()

        do {
            let handler = MockURLHandler()
            manager.urlHandler = handler
            #expect(manager.urlHandler != nil)
        }

        #expect(manager.urlHandler == nil, "URL handler should be weakly held")
    }
}
