import Foundation
import Testing
import WebKit
@testable import Refrax

/// A loaded space and one extension context for the default controller, loaded on demand
/// so tabs can exist before it, as tabs restored at launch do.
@MainActor
private struct ExtensionTabsFixture {
    let env: TabManagerTestEnvironment
    let space: Space
    let context: WKWebExtensionContext

    init() async throws {
        env = try TabManagerTestEnvironment()
        space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("refrax-test-extension-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let manifest = #"{"manifest_version": 3, "name": "Test", "version": "1.0"}"#
        try manifest.write(to: folder.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        let webExtension = try await WKWebExtension(resourceBaseURL: folder)
        context = WKWebExtensionContext(for: webExtension)
    }

    /// A tab in the space with no page, created while no extension is loaded.
    func makeTab() -> Refrax.Tab {
        let tab = env.tabManager.createTab(
            url: URL(string: "https://www.youtube.com/watch?v=jNQXAC9IVRw")!,
            in: space,
            makeActive: false,
            loadImmediately: false,
        )
        env.pagePool.removePages(for: tab)
        return tab
    }

    /// Loads the extension, then reports `tabs` to it as tabs restored at launch.
    func loadExtension(restoring tabs: [Refrax.Tab]) throws {
        try env.extensionManager.defaultController.load(context)
        env.extensionManager.dispatchTabsRestored(tabs)
    }

    /// A tab restored from storage and never shown, so it has no page.
    func restoredTab() throws -> Refrax.Tab {
        let tab = makeTab()
        try loadExtension(restoring: [tab])
        return tab
    }

    func extensionTab(for tabPage: TabPage) -> RefraxExtensionTab {
        env.extensionManager.extensionTab(for: tabPage, pagePool: env.pagePool)
    }

    func isOpen(_ extensionTab: RefraxExtensionTab) -> Bool {
        context.openTabs.contains(AnyHashable(extensionTab))
    }
}

/// Tabs that extensions knew without a web view reach them as new tabs once a page
/// exists, so an extension that dropped such a tab (uBlock Origin does after 10 minutes)
/// starts it fresh, as it does a tab the user opens.
@Suite("Extension tabs without a web view", .tags(.extensionManager), .serialized)
struct ExtensionTabsWithoutWebViewTests {
    @Test @MainActor
    func `A restored tab without a page is replaced by a new tab as its page is created`() async throws {
        let fixture = try await ExtensionTabsFixture()
        let tabPage = try #require(try fixture.restoredTab().pages.first)
        #expect(fixture.env.pagePool.existingPage(for: tabPage) == nil)
        #expect(fixture.env.extensionManager.tabsWithoutWebView.contains(tabPage.id))
        let restored = fixture.extensionTab(for: tabPage)
        #expect(fixture.isOpen(restored))

        _ = fixture.env.pagePool.page(for: tabPage)

        let replacement = fixture.extensionTab(for: tabPage)
        #expect(replacement !== restored)
        #expect(!fixture.isOpen(restored))
        #expect(fixture.isOpen(replacement))
        #expect(!fixture.env.extensionManager.tabsWithoutWebView.contains(tabPage.id))
    }

    @Test @MainActor
    func `A tab shown before extensions loaded keeps its extension tab`() async throws {
        let fixture = try await ExtensionTabsFixture()
        let tab = fixture.makeTab()
        let tabPage = try #require(tab.pages.first)
        _ = fixture.env.pagePool.page(for: tabPage)
        try fixture.loadExtension(restoring: [tab])
        let shown = fixture.extensionTab(for: tabPage)

        _ = fixture.env.pagePool.page(for: tabPage)

        #expect(!fixture.env.extensionManager.tabsWithoutWebView.contains(tabPage.id))
        #expect(fixture.extensionTab(for: tabPage) === shown)
        #expect(fixture.isOpen(shown))
    }

    @Test @MainActor
    func `An evicted page's tab is replaced when its page comes back`() async throws {
        let fixture = try await ExtensionTabsFixture()
        let tabPage = try #require(try fixture.restoredTab().pages.first)
        _ = fixture.env.pagePool.page(for: tabPage)
        let shown = fixture.extensionTab(for: tabPage)

        fixture.env.pagePool.removePage(for: tabPage)
        #expect(fixture.env.extensionManager.tabsWithoutWebView.contains(tabPage.id))

        _ = fixture.env.pagePool.page(for: tabPage)
        let replacement = fixture.extensionTab(for: tabPage)
        #expect(replacement !== shown)
        #expect(fixture.isOpen(replacement))
        #expect(!fixture.env.extensionManager.tabsWithoutWebView.contains(tabPage.id))
    }

    @Test @MainActor
    func `A closed tab is forgotten`() async throws {
        let fixture = try await ExtensionTabsFixture()
        let tab = try fixture.restoredTab()
        let tabPage = try #require(tab.pages.first)
        let restored = fixture.extensionTab(for: tabPage)

        fixture.env.extensionManager.dispatchTabClosed(tab, windowClosing: false)

        #expect(!fixture.env.extensionManager.tabsWithoutWebView.contains(tabPage.id))
        #expect(!fixture.isOpen(restored))
    }
}
