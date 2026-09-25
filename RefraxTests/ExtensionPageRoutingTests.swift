import Foundation
import Testing
@testable import Refrax

@Suite("Extension page routing", .tags(.extensionManager))
struct ExtensionPageRoutingTests {
    private let uBlock = URL(string: "webkit-extension://7f3a2b1c-uBlock/")!
    private let otherExtension = URL(string: "webkit-extension://0c9d8e7f-other/")!

    @Test(
        arguments: [
            ("webkit-extension://7f3a2b1c/dashboard.html", true),
            ("WebKit-Extension://7f3a2b1c/popup.html", true),
            ("https://github.com/gorhill/uBlock", false),
            ("about:blank", false),
            ("refrax://settings", false),
        ],
    )
    func `Recognizes extension URLs by scheme`(string: String, isExtension: Bool) throws {
        let url = try #require(URL(string: string))
        #expect(ExtensionPageRouting.isExtensionURL(url) == isExtension)
    }

    @Test
    func `An ordinary web view keeps ordinary pages`() {
        #expect(ExtensionPageRouting.canNavigate(from: nil, to: nil))
    }

    @Test
    func `An extension's web view keeps that extension's pages, whatever the path or host case`() throws {
        let dashboard = try #require(URL(string: "webkit-extension://7F3A2B1C-UBLOCK/dashboard.html#settings"))
        #expect(ExtensionPageRouting.canNavigate(from: uBlock, to: dashboard))
    }

    @Test
    func `Crossing into, out of, or between extensions needs a new web view`() {
        #expect(!ExtensionPageRouting.canNavigate(from: nil, to: uBlock))
        #expect(!ExtensionPageRouting.canNavigate(from: uBlock, to: nil))
        #expect(!ExtensionPageRouting.canNavigate(from: uBlock, to: otherExtension))
    }

    @Test(
        arguments: [
            ("webkit-extension://a/dashboard.html#settings.html", "webkit-extension://a/dashboard.html", true),
            ("webkit-extension://a/dashboard.html", "webkit-extension://a/dashboard.html", true),
            ("webkit-extension://a/dashboard.html?tab=1", "webkit-extension://a/dashboard.html", false),
            ("webkit-extension://a/options.html", "webkit-extension://a/dashboard.html", false),
            ("webkit-extension://b/dashboard.html", "webkit-extension://a/dashboard.html", false),
        ],
    )
    func `Matches a page regardless of fragment`(url: String, page: String, isSame: Bool) throws {
        let url = try #require(URL(string: url))
        let page = try #require(URL(string: page))
        #expect(ExtensionPageRouting.isSamePage(url, page) == isSame)
    }
}
