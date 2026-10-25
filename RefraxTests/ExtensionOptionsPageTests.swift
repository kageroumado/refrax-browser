import Foundation
import Testing
import WebKit
@testable import Refrax

/// Refrax opens an extension's options page from its own settings, as the extension's
/// `runtime.openOptionsPage()` does: uBlock Origin's dashboard is reachable only that way
/// or through its popup.
@Suite("Extension options page", .tags(.extensionManager), .serialized)
struct ExtensionOptionsPageTests {
    @MainActor
    private func loadedContext(in env: TabManagerTestEnvironment, manifest: String) async throws -> WKWebExtensionContext {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("refrax-test-extension-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try manifest.write(to: folder.appendingPathComponent("manifest.json"), atomically: true, encoding: .utf8)
        try "<!doctype html><title>Options</title>".write(
            to: folder.appendingPathComponent("dashboard.html"),
            atomically: true,
            encoding: .utf8,
        )
        let context = WKWebExtensionContext(for: try await WKWebExtension(resourceBaseURL: folder))
        try env.extensionManager.defaultController.load(context)
        return context
    }

    @MainActor
    private func optionsTabs(in space: Space, for context: WKWebExtensionContext) -> [Refrax.Tab] {
        space.tabs.filter { tab in
            tab.pages.contains { ExtensionPageRouting.isSamePage($0.url, context.optionsPageURL!) }
        }
    }

    @Test @MainActor
    func `Opening the options page opens one tab with it, and reuses that tab`() async throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)
        let context = try await loadedContext(in: env, manifest: #"""
        {"manifest_version": 2, "name": "Test", "version": "1.0",
         "options_ui": {"page": "dashboard.html", "open_in_tab": true}}
        """#)
        #expect(context.optionsPageURL != nil)

        try await env.extensionManager.openOptionsPage(for: context)
        #expect(optionsTabs(in: space, for: context).count == 1)

        try await env.extensionManager.openOptionsPage(for: context)
        #expect(optionsTabs(in: space, for: context).count == 1)
    }

    @Test @MainActor
    func `An extension without an options page reports it`() async throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)
        let context = try await loadedContext(in: env, manifest: #"""
        {"manifest_version": 2, "name": "Test", "version": "1.0"}
        """#)

        await #expect(throws: (any Error).self) {
            try await env.extensionManager.openOptionsPage(for: context)
        }
        #expect(space.tabs.isEmpty)
    }
}
