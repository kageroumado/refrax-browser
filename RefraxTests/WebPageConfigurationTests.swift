import Foundation
import Testing
import WebKit

@testable import Refrax

// Type alias to disambiguate from WebKit's WebPage.Configuration
private typealias RefraxConfiguration = Refrax.WebPage.Configuration
private typealias RefraxNavigationPreferences = Refrax.WebPage.NavigationPreferences

// MARK: - Test Tags

extension Tag {
    /// Tests for WebPage.Configuration functionality.
    @Tag static var webPageConfiguration: Self
}

// MARK: - Configuration applyTo Tests

@Suite("WebPage.Configuration applyTo", .tags(.webPageConfiguration), .serialized)
@MainActor
struct ConfigurationApplyToTests {
    @Test("applyTo merges JavaScript setting into provided config")
    func mergesJavaScriptSetting() {
        // Create Refrax config with JavaScript disabled
        var refraxConfig = RefraxConfiguration()
        refraxConfig.defaultNavigationPreferences.allowsContentJavaScript = false

        // Create WebKit config with JavaScript enabled (simulating popup)
        let providedConfig = WKWebViewConfiguration()
        providedConfig.defaultWebpagePreferences.allowsContentJavaScript = true

        // Apply Refrax settings
        refraxConfig.applyTo(providedConfig)

        // Refrax setting should override WebKit's
        #expect(providedConfig.defaultWebpagePreferences.allowsContentJavaScript == false)
    }

    @Test("applyTo always enables developer tools")
    func alwaysEnablesDeveloperTools() {
        let refraxConfig = RefraxConfiguration()
        let providedConfig = WKWebViewConfiguration()

        refraxConfig.applyTo(providedConfig)

        let devToolsEnabled = providedConfig.preferences.value(forKey: "developerExtrasEnabled") as? Bool
        #expect(devToolsEnabled == true)
    }

    @Test("applyTo preserves WebKit's data store")
    func preservesDataStore() {
        let refraxConfig = RefraxConfiguration()

        let providedConfig = WKWebViewConfiguration()
        let originalStore = providedConfig.websiteDataStore

        refraxConfig.applyTo(providedConfig)

        // Data store should not be modified (handled separately by WebPagePool)
        #expect(providedConfig.websiteDataStore === originalStore)
    }

    @Test("applyTo does not merge user scripts to prevent duplication")
    func doesNotMergeUserScripts() {
        // User scripts are NOT merged in applyTo because for popups, WebKit clones
        // the opener's configuration including its userContentController. Merging
        // would duplicate scripts and flood WebKit's IPC queue.
        let refraxConfig = RefraxConfiguration()
        let refraxScript = WKUserScript(
            source: "// Refrax Script",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true,
        )
        refraxConfig.userContentController.addUserScript(refraxScript)

        let providedConfig = WKWebViewConfiguration()
        let webkitScript = WKUserScript(
            source: "// WebKit Popup Script",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
        )
        providedConfig.userContentController.addUserScript(webkitScript)

        let initialCount = providedConfig.userContentController.userScripts.count
        #expect(initialCount == 1)

        refraxConfig.applyTo(providedConfig)

        // Scripts should NOT be merged - original scripts remain untouched
        #expect(providedConfig.userContentController.userScripts.count == 1)
    }

    @Test("applyTo applies autoplay policy")
    func appliesAutoplayPolicy() {
        var refraxConfig = RefraxConfiguration()
        refraxConfig.mediaTypesRequiringUserActionForPlayback = WKAudiovisualMediaTypes.all

        let providedConfig = WKWebViewConfiguration()
        providedConfig.mediaTypesRequiringUserActionForPlayback = []

        refraxConfig.applyTo(providedConfig)

        // Refrax policy should be applied
        #expect(providedConfig.mediaTypesRequiringUserActionForPlayback == WKAudiovisualMediaTypes.all)
    }

    @Test("applyTo attaches web extension controller")
    func attachesExtensionController() {
        var refraxConfig = RefraxConfiguration()
        let extensionController = WKWebExtensionController()
        refraxConfig.webExtensionController = extensionController

        let providedConfig = WKWebViewConfiguration()

        refraxConfig.applyTo(providedConfig)

        #expect(providedConfig.webExtensionController === extensionController)
    }

    @Test("applyTo does not override extension controller when not set")
    func doesNotOverrideExtensionControllerWhenNotSet() {
        let refraxConfig = RefraxConfiguration()
        // webExtensionController is nil by default

        let providedConfig = WKWebViewConfiguration()
        let originalController = WKWebExtensionController()
        providedConfig.webExtensionController = originalController

        refraxConfig.applyTo(providedConfig)

        // Original should be preserved when Refrax has no controller
        #expect(providedConfig.webExtensionController === originalController)
    }

    @Test("applyTo applies HTTPS upgrade setting")
    func appliesHTTPSUpgrade() {
        var refraxConfig = RefraxConfiguration()
        refraxConfig.upgradeKnownHostsToHTTPS = true

        let providedConfig = WKWebViewConfiguration()
        providedConfig.upgradeKnownHostsToHTTPS = false

        refraxConfig.applyTo(providedConfig)

        #expect(providedConfig.upgradeKnownHostsToHTTPS == true)
    }

    @Test("applyTo applies inline predictions setting")
    func appliesInlinePredictions() {
        var refraxConfig = RefraxConfiguration()
        refraxConfig.allowsInlinePredictions = false

        let providedConfig = WKWebViewConfiguration()
        providedConfig.allowsInlinePredictions = true

        refraxConfig.applyTo(providedConfig)

        #expect(providedConfig.allowsInlinePredictions == false)
    }

    @Test("applyTo applies content mode preference")
    func appliesContentMode() {
        var refraxConfig = RefraxConfiguration()
        refraxConfig.defaultNavigationPreferences.preferredContentMode = RefraxNavigationPreferences.ContentMode.desktop

        let providedConfig = WKWebViewConfiguration()

        refraxConfig.applyTo(providedConfig)

        #expect(providedConfig.defaultWebpagePreferences.preferredContentMode == WKWebpagePreferences.ContentMode.desktop)
    }
}

// MARK: - Configuration makeWKWebViewConfiguration Tests

@Suite("WebPage.Configuration makeWKWebViewConfiguration", .tags(.webPageConfiguration), .serialized)
@MainActor
struct ConfigurationMakeTests {
    @Test("makeWKWebViewConfiguration creates config with JavaScript setting")
    func createsWithJavaScriptSetting() {
        var config = RefraxConfiguration()
        config.defaultNavigationPreferences.allowsContentJavaScript = false

        let wkConfig = config.makeWKWebViewConfiguration()

        #expect(wkConfig.defaultWebpagePreferences.allowsContentJavaScript == false)
    }

    @Test("makeWKWebViewConfiguration always enables developer tools")
    func createsWithDeveloperTools() {
        let config = RefraxConfiguration()

        let wkConfig = config.makeWKWebViewConfiguration()

        let devToolsEnabled = wkConfig.preferences.value(forKey: "developerExtrasEnabled") as? Bool
        #expect(devToolsEnabled == true)
    }

    @Test("makeWKWebViewConfiguration applies user content controller")
    func appliesUserContentController() {
        let config = RefraxConfiguration()
        let script = WKUserScript(
            source: "console.log('test')",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
        )
        config.userContentController.addUserScript(script)

        let wkConfig = config.makeWKWebViewConfiguration()

        #expect(wkConfig.userContentController.userScripts.count == 1)
    }
}
