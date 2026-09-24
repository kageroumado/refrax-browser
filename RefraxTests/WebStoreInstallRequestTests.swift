import Foundation
@testable import Refrax
import Testing

@Suite("Web store install requests")
@MainActor
struct WebStoreInstallRequestTests {
    private static let chromeID = "cjpalhdlnbpafiamejdnhcphjbkeiagm"

    private func message(
        from url: String,
        store: String = "chrome",
        id: String = chromeID,
        isMainFrame: Bool = true,
    ) -> ScriptMessage {
        ScriptMessage(
            channel: WebStoreIntegrationScript.messageHandlerName,
            world: .isolated(name: WebStoreIntegrationScript.worldName),
            body: .object(["store": .string(store), "extensionID": .string(id), "name": .string("  uBlock Origin  ")]),
            frameURL: URL(string: url),
            isMainFrame: isMainFrame,
        )
    }

    @Test("A store's main frame with a well-formed ID is accepted")
    func accepted() throws {
        let request = try #require(WebStoreInstallRequest(message(from: "https://chromewebstore.google.com/detail/x/\(Self.chromeID)")))
        #expect(request.store == .chrome)
        #expect(request.name == "uBlock Origin")
        #expect(request.source == .chromeWebStore(extensionID: Self.chromeID))

        let firefox = WebStoreInstallRequest(message(from: "https://addons.mozilla.org/en-US/firefox/addon/ublock-origin/", store: "firefox", id: "ublock-origin"))
        #expect(firefox?.store == .firefox)
    }

    @Test("Requests from anywhere else, or with a malformed ID, are rejected", arguments: [
        ("https://evil.example/", "chrome", chromeID, true),
        ("http://chromewebstore.google.com/", "chrome", chromeID, true),
        ("https://chromewebstore.google.com/", "chrome", chromeID, false),
        ("https://chromewebstore.google.com/", "firefox", "ublock-origin", true),
        ("https://chromewebstore.google.com/", "chrome", "ABCDEFGHIJKLMNOPQRSTUVWXYZABCDEF", true),
        ("https://chromewebstore.google.com/", "chrome", chromeID + "%26x", true),
        ("https://addons.mozilla.org/", "firefox", "..", true),
        ("https://addons.mozilla.org/", "firefox", "a/../../b", true),
    ])
    func rejected(url: String, store: String, id: String, isMainFrame: Bool) {
        #expect(WebStoreInstallRequest(message(from: url, store: store, id: id, isMainFrame: isMainFrame)) == nil)
    }

    @Test("Frame origins take location.origin form")
    func origins() {
        #expect(FrameContentExtractor.origin(of: URL(string: "https://consent.example/path?q")!) == "https://consent.example")
        #expect(FrameContentExtractor.origin(of: URL(string: "http://localhost:8080/")!) == "http://localhost:8080")
    }
}
