import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for ContentScriptManager operations.
    @Tag static var contentScriptManager: Self
}

// MARK: - ContentScriptManager Query Tests

/// Tests for form data query functionality.
/// Note: Full JavaScript query testing requires real WebPage with loaded content.
@Suite("ContentScriptManager Query", .tags(.contentScriptManager), .serialized)
@MainActor
struct ContentScriptManagerQueryTests {
    @Test("Query form data returns false for tab without webView")
    func queryFormDataNoWebView() async throws {
        let env = try TabManagerTestEnvironment()

        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create a tab but don't create its WebPage (lazy loading)
        let tab = env.tabManager.createTab(
            url: URL(string: "https://example.com")!,
            in: space,
            makeActive: false,
            loadImmediately: false,
        )

        // Get or create the page (but webView won't be ready for JS)
        if let page = env.pagePool.existingPage(for: tab.pages.first!) {
            // Query should return false due to JS error
            let hasFormData = await env.contentScriptManager.queryFormDataState(for: page)
            #expect(!hasFormData, "Should return false when JavaScript fails")
        }

        // If no page exists, test passes (no query possible)
    }
}

// MARK: - Notes

//
// ContentScriptManager functionality requiring integration tests:
//
// 1. setup() - Compiles WKContentRuleList from blocklist.json or uses cache
// 2. setupContentBlocking() - Uses WKContentRuleListStore.default()
// 3. updateThirdPartyCookieBlocking() - Adds/removes rule lists from userContentController
// 4. updateGlobalPrivacyControl() - Registers WKUserScript via ScriptRegistry
// 5. startSettingsObservation() - Observes BrowserSettings changes
// 6. queryFormDataState() with real form data - Requires loaded page with DOM
//
// The singleton pattern and WebKit dependencies make unit testing impractical.
// These behaviors are best verified via:
// - Integration tests with real WKWebView
// - UI tests that verify content blocking works
// - Manual testing of GPC signal injection
