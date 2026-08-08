import Foundation
import SwiftData
import Testing

@testable import Refrax

// MARK: - External Scheme Handler Tests

@Suite("ExternalSchemeHandler", .tags(.navigation))
@MainActor
struct ExternalSchemeHandlerTests {
    let stubOpener = StubURLOpener()

    var handler: ExternalSchemeHandler {
        ExternalSchemeHandler(urlOpener: stubOpener)
    }

    @Test("mailto: opens externally")
    func mailtoOpensExternally() async {
        let action = MockNavigationAction(url: TestURLs.mailto)
        let policy = await handler.evaluate(action)

        #expect(policy == .cancel)
        #expect(stubOpener.openedURLs.contains(TestURLs.mailto))
    }

    @Test("tel: opens externally")
    func telOpensExternally() async {
        let action = MockNavigationAction(url: TestURLs.tel)
        let policy = await handler.evaluate(action)

        #expect(policy == .cancel)
        #expect(stubOpener.openedURLs.contains(TestURLs.tel))
    }

    @Test("Custom scheme (slack:) opens externally")
    func customSchemeOpensExternally() async {
        let action = MockNavigationAction(url: TestURLs.slack)
        let policy = await handler.evaluate(action)

        #expect(policy == .cancel)
        #expect(stubOpener.openedURLs.contains(TestURLs.slack))
    }

    @Test("http: passes through")
    func httpPassesThrough() async {
        let action = MockNavigationAction(url: TestURLs.http)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
        #expect(stubOpener.openedURLs.isEmpty)
    }

    @Test("https: passes through")
    func httpsPassesThrough() async {
        let action = MockNavigationAction(url: TestURLs.https)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
        #expect(stubOpener.openedURLs.isEmpty)
    }

    @Test("file: passes through")
    func filePassesThrough() async {
        let action = MockNavigationAction(url: TestURLs.file)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
        #expect(stubOpener.openedURLs.isEmpty)
    }

    @Test("data: passes through")
    func dataPassesThrough() async {
        let action = MockNavigationAction(url: TestURLs.data)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
        #expect(stubOpener.openedURLs.isEmpty)
    }

    @Test("blob: passes through")
    func blobPassesThrough() async {
        let action = MockNavigationAction(url: TestURLs.blob)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
        #expect(stubOpener.openedURLs.isEmpty)
    }

    @Test("javascript: passes through")
    func javascriptPassesThrough() async {
        let action = MockNavigationAction(url: TestURLs.javascript)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
        #expect(stubOpener.openedURLs.isEmpty)
    }

    @Test("refrax: passes through")
    func refraxPassesThrough() async {
        let action = MockNavigationAction(url: TestURLs.refrax)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
        #expect(stubOpener.openedURLs.isEmpty)
    }

    @Test("nil URL passes through")
    func nilURLPassesThrough() async {
        let action = MockNavigationAction(url: nil)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
        #expect(stubOpener.openedURLs.isEmpty)
    }
}

// MARK: - Modifier Click Handler Tests

@Suite("ModifierClickHandler", .tags(.navigation))
@MainActor
struct ModifierClickHandlerTests {
    let handler = ModifierClickHandler()

    @Test("Middle-click opens in new tab")
    func middleClickOpensNewTab() async {
        let action = MockNavigationAction.middleClick(url: TestURLs.https)
        let policy = await handler.evaluate(action)

        if case let .openInNewTab(url, activate) = policy {
            #expect(url == TestURLs.https)
            #expect(activate == false)
        } else {
            Issue.record("Expected .openInNewTab, got \(policy)")
        }
    }

    @Test("Cmd+click opens in new background tab")
    func cmdClickOpensNewTab() async {
        let action = MockNavigationAction.commandClick(url: TestURLs.https)
        let policy = await handler.evaluate(action)

        if case let .openInNewTab(url, activate) = policy {
            #expect(url == TestURLs.https)
            #expect(activate == false)
        } else {
            Issue.record("Expected .openInNewTab, got \(policy)")
        }
    }

    @Test("Cmd+Shift+click activates new tab")
    func cmdShiftClickActivatesNewTab() async {
        let action = MockNavigationAction.commandClick(url: TestURLs.https, withShift: true)
        let policy = await handler.evaluate(action)

        if case let .openInNewTab(url, activate) = policy {
            #expect(url == TestURLs.https)
            #expect(activate == true)
        } else {
            Issue.record("Expected .openInNewTab, got \(policy)")
        }
    }

    @Test("Regular click passes through")
    func regularClickPassesThrough() async {
        let action = MockNavigationAction.linkClick(url: TestURLs.https)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Non-link navigation passes through")
    func nonLinkPassesThrough() async {
        let action = MockNavigationAction(
            url: TestURLs.https,
            isMiddleClick: true,
            isLinkActivated: false,
        )
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("javascript: scheme ignored for modifier clicks")
    func javascriptSchemeIgnored() async {
        let action = MockNavigationAction(
            url: TestURLs.javascript,
            isMiddleClick: true,
            isLinkActivated: true,
        )
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("refrax: scheme ignored for modifier clicks")
    func refraxSchemeIgnored() async {
        let action = MockNavigationAction(
            url: TestURLs.refrax,
            isCommandClick: true,
            isLinkActivated: true,
        )
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }
}

// MARK: - Download Action Handler Tests

@Suite("DownloadActionHandler", .tags(.navigation))
@MainActor
struct DownloadActionHandlerTests {
    let handler = DownloadActionHandler()

    @Test("Download attribute triggers download")
    func downloadAttributeDetected() async {
        let action = MockNavigationAction.download(url: TestURLs.pdf)
        let policy = await handler.evaluate(action)

        if case let .download(url) = policy {
            #expect(url == TestURLs.pdf)
        } else {
            Issue.record("Expected .download, got \(policy)")
        }
    }

    @Test("No download attribute passes through")
    func noDownloadAttributePassesThrough() async {
        let action = MockNavigationAction.linkClick(url: TestURLs.pdf)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Download attribute with nil URL passes through")
    func downloadWithNilURLPassesThrough() async {
        let action = MockNavigationAction(
            url: nil,
            shouldPerformDownload: true,
        )
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }
}

// MARK: - Data URL Script Handler Tests

@Suite("DataURLScriptHandler", .tags(.navigation))
@MainActor
struct DataURLScriptHandlerTests {
    let handler = DataURLScriptHandler()

    @Test("Blocks data URL with script tag")
    func blocksScriptTag() async {
        let url = URL(string: "data:text/html,<script>alert(1)</script>")!
        let action = MockNavigationAction.mainFrame(url: url)
        let policy = await handler.evaluate(action)

        #expect(policy == .cancel)
    }

    @Test("Blocks data URL with onclick handler")
    func blocksOnclickHandler() async {
        let url = URL(string: "data:text/html,<div onclick='alert(1)'>click</div>")!
        let action = MockNavigationAction.mainFrame(url: url)
        let policy = await handler.evaluate(action)

        #expect(policy == .cancel)
    }

    @Test("Blocks data URL with onerror handler")
    func blocksOnerrorHandler() async {
        let url = URL(string: "data:text/html,<img onerror='alert(1)'>")!
        let action = MockNavigationAction.mainFrame(url: url)
        let policy = await handler.evaluate(action)

        #expect(policy == .cancel)
    }

    @Test("Blocks data URL with javascript: protocol")
    func blocksJavascriptProtocol() async {
        let url = URL(string: "data:text/html,<a href='javascript:alert(1)'>link</a>")!
        let action = MockNavigationAction.mainFrame(url: url)
        let policy = await handler.evaluate(action)

        #expect(policy == .cancel)
    }

    @Test("Allows safe data URL content")
    func allowsSafeContent() async {
        let url = URL(string: "data:text/html,<h1>Hello World</h1>")!
        let action = MockNavigationAction.mainFrame(url: url)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Allows data URL in subframe")
    func allowsSubframeDataURL() async {
        let url = URL(string: "data:text/html,<script>alert(1)</script>")!
        let action = MockNavigationAction.subframe(url: url)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Passes through non-data URLs")
    func passesNonDataURLs() async {
        let action = MockNavigationAction.mainFrame(url: TestURLs.https)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Handles percent-encoded script tags")
    func handlesPercentEncodedScript() async {
        let url = URL(string: "data:text/html,%3Cscript%3Ealert(1)%3C/script%3E")!
        let action = MockNavigationAction.mainFrame(url: url)
        let policy = await handler.evaluate(action)

        #expect(policy == .cancel)
    }
}

// MARK: - Blob URL Handler Tests

@Suite("BlobURLHandler", .tags(.navigation))
@MainActor
struct BlobURLHandlerTests {
    let handler = BlobURLHandler()

    @Test("User-initiated blob navigation allowed")
    func userInitiatedAllowed() async {
        let action = MockNavigationAction(
            url: TestURLs.blob,
            isMainFrame: true,
            isUserInitiated: true,
        )
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Link-activated blob navigation allowed")
    func linkActivatedAllowed() async {
        let action = MockNavigationAction(
            url: TestURLs.blob,
            isMainFrame: true,
            isLinkActivated: true,
        )
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Form submission blob navigation allowed")
    func formSubmissionAllowed() async {
        let action = MockNavigationAction(
            url: TestURLs.blob,
            isMainFrame: true,
            isFormSubmission: true,
        )
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Script-initiated blob blocked")
    func scriptInitiatedBlocked() async {
        let action = MockNavigationAction.scriptInitiated(url: TestURLs.blob)
        let policy = await handler.evaluate(action)

        #expect(policy == .cancel)
    }

    @Test("Subframe blob navigation allowed")
    func subframeAllowed() async {
        let action = MockNavigationAction.subframe(url: TestURLs.blob)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Non-blob URL passes through")
    func nonBlobPassesThrough() async {
        let action = MockNavigationAction.scriptInitiated(url: TestURLs.https)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }
}

// MARK: - File Scheme Handler Tests

@Suite("FileSchemeHandler", .tags(.navigation))
@MainActor
struct FileSchemeHandlerTests {
    let handler = FileSchemeHandler()

    @Test("User-initiated file navigation allowed")
    func userInitiatedAllowed() async {
        let action = MockNavigationAction(
            url: TestURLs.file,
            isMainFrame: true,
            isUserInitiated: true,
        )
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Link-activated file navigation allowed")
    func linkActivatedAllowed() async {
        let action = MockNavigationAction(
            url: TestURLs.file,
            isMainFrame: true,
            isLinkActivated: true,
        )
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("File-to-file navigation allowed")
    func fileToFileAllowed() async {
        let action = MockNavigationAction.fileToFile(url: TestURLs.file)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Back/forward to file allowed")
    func backForwardAllowed() async {
        let action = MockNavigationAction.backForward(url: TestURLs.file)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Reload file allowed")
    func reloadAllowed() async {
        let action = MockNavigationAction.reload(url: TestURLs.file)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Script-initiated file navigation blocked")
    func scriptInitiatedBlocked() async {
        let action = MockNavigationAction.scriptInitiated(url: TestURLs.file)
        let policy = await handler.evaluate(action)

        #expect(policy == .cancel)
    }

    @Test("Non-file URL passes through")
    func nonFilePassesThrough() async {
        let action = MockNavigationAction.scriptInitiated(url: TestURLs.https)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }
}

// MARK: - Subframe Navigation Handler Tests

@Suite("SubframeNavigationHandler", .tags(.navigation))
@MainActor
struct SubframeNavigationHandlerTests {
    let handler = SubframeNavigationHandler()

    @Test("Subframe navigation allowed")
    func subframeAllowed() async {
        let action = MockNavigationAction.subframe(url: TestURLs.https)
        let policy = await handler.evaluate(action)

        #expect(policy == .allow)
    }

    @Test("Main frame navigation passes through")
    func mainFramePassesThrough() async {
        let action = MockNavigationAction.mainFrame(url: TestURLs.https)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("New window request passes through")
    func newWindowPassesThrough() async {
        let action = MockNavigationAction.popup(url: TestURLs.https)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }
}

// MARK: - Deep Link Handler Tests

@Suite("DeepLinkHandler", .tags(.navigation))
@MainActor
struct DeepLinkHandlerTests {
    let handler = DeepLinkHandler()

    @Test("SSL error deep link allowed for in-tab rendering")
    func sslErrorDeepLinkAllowed() async {
        let action = MockNavigationAction(url: TestURLs.refrax)
        let policy = await handler.evaluate(action)

        #expect(policy == .allow)
    }

    @Test("Focus blocked deep link allowed for in-tab rendering")
    func focusBlockedDeepLinkAllowed() async {
        let action = MockNavigationAction(url: TestURLs.refraxFocusBlocked)
        let policy = await handler.evaluate(action)

        #expect(policy == .allow)
    }

    @Test("Invalid refrax:// deep link cancelled")
    func invalidDeepLinkCancelled() async {
        let url = URL(string: "refrax://unknown-page")!
        let action = MockNavigationAction(url: url)
        let policy = await handler.evaluate(action)

        #expect(policy == .cancel)
    }

    @Test("Non-refrax URL passes through")
    func nonRefraxPassesThrough() async {
        let action = MockNavigationAction(url: TestURLs.https)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }
}

// MARK: - Link Protection Handler Tests

@Suite("LinkProtectionHandler", .tags(.navigation))
@MainActor
struct LinkProtectionHandlerTests {
    let handler = LinkProtectionHandler()

    @Test("URL with tracking parameters redirected")
    func trackingParamsRedirected() async {
        let action = MockNavigationAction.mainFrame(url: TestURLs.withTracking)
        let policy = await handler.evaluate(action)

        if case let .redirect(url) = policy {
            #expect(url.absoluteString.contains("id=123"))
            #expect(!url.absoluteString.contains("utm_source"))
        } else {
            Issue.record("Expected .redirect, got \(policy)")
        }
    }

    @Test("AMP URL redirected to canonical")
    func ampRedirected() async {
        let action = MockNavigationAction.mainFrame(url: TestURLs.amp)
        let policy = await handler.evaluate(action)

        if case let .redirect(url) = policy {
            #expect(url.host == "example.com")
        } else {
            Issue.record("Expected .redirect, got \(policy)")
        }
    }

    @Test("Clean URL passes through")
    func cleanURLPassesThrough() async {
        let action = MockNavigationAction.mainFrame(url: TestURLs.https)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Subframe navigation passes through")
    func subframePassesThrough() async {
        let action = MockNavigationAction.subframe(url: TestURLs.withTracking)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("OAuth URL bypasses cleaning")
    func oauthBypassesCleaning() async {
        let url = URL(string: "https://accounts.google.com/o/oauth2/auth?response_type=code&utm_source=test&client_id=abc")!
        let action = MockNavigationAction.mainFrame(url: url)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Redirect chain with OAuth bypasses cleaning")
    func oauthRedirectChainBypassesCleaning() async {
        var chain = RedirectChain()
        chain.append(TestURLs.oauth)

        let action = MockNavigationAction(
            url: TestURLs.withTracking,
            redirectChain: chain,
            isMainFrame: true,
        )
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }
}

// MARK: - Download Response Handler Tests

@Suite("DownloadResponseHandler", .tags(.navigation))
@MainActor
struct DownloadResponseHandlerTests {
    let handler = DownloadResponseHandler()

    @Test("Content-Disposition: attachment triggers download")
    func attachmentDispositionTriggersDownload() async {
        let response = MockNavigationResponse.download(url: TestURLs.pdf)
        let policy = await handler.evaluate(response)

        #expect(policy == .download)
    }

    @Test("Non-displayable MIME type triggers download")
    func nonDisplayableMIMETriggersDownload() async {
        let response = MockNavigationResponse.nonDisplayable(url: TestURLs.zip, mimeType: "application/zip")
        let policy = await handler.evaluate(response)

        #expect(policy == .download)
    }

    @Test("Displayable content passes through")
    func displayablePassesThrough() async {
        let response = MockNavigationResponse.html(url: TestURLs.https)
        let policy = await handler.evaluate(response)

        #expect(policy == .next)
    }
}

// MARK: - HTTP Error Handler Tests

@Suite("HTTPErrorHandler", .tags(.navigation))
@MainActor
struct HTTPErrorHandlerTests {
    let handler = HTTPErrorHandler()

    @Test("404 shows error page")
    func http404ShowsError() async {
        let response = MockNavigationResponse.httpError(url: TestURLs.https, statusCode: 404)
        let policy = await handler.evaluate(response)

        if case let .showError(code, failedURL) = policy {
            #expect(code == 404)
            #expect(failedURL == TestURLs.https)
        } else {
            Issue.record("Expected .showError, got \(policy)")
        }
    }

    @Test("500 shows error page")
    func http500ShowsError() async {
        let response = MockNavigationResponse.httpError(url: TestURLs.https, statusCode: 500)
        let policy = await handler.evaluate(response)

        if case let .showError(code, _) = policy {
            #expect(code == 500)
        } else {
            Issue.record("Expected .showError, got \(policy)")
        }
    }

    @Test("200 passes through")
    func http200PassesThrough() async {
        let response = MockNavigationResponse.html(url: TestURLs.https)
        let policy = await handler.evaluate(response)

        #expect(policy == .next)
    }

    @Test("Subframe error ignored")
    func subframeErrorIgnored() async {
        let response = MockNavigationResponse(
            isMainFrame: false,
            url: TestURLs.https,
            statusCode: 404,
        )
        let policy = await handler.evaluate(response)

        #expect(policy == .next)
    }
}

// MARK: - Navigation Action Chain Tests

@Suite("NavigationActionChain", .tags(.navigation))
@MainActor
struct NavigationActionChainTests {
    let stubOpener = StubURLOpener()

    @Test("Chain short-circuits on non-next policy")
    func chainShortCircuits() async {
        // ExternalSchemeHandler returns .cancel for mailto:
        let chain = NavigationActionChain(handlers: [
            ExternalSchemeHandler(urlOpener: stubOpener),
            ModifierClickHandler(),
        ])

        let action = MockNavigationAction(url: TestURLs.mailto)
        let policy = await chain.evaluate(action)

        #expect(policy == .cancel)
    }

    @Test("Chain returns allow if all handlers return next")
    func chainReturnsAllowIfAllNext() async {
        let chain = NavigationActionChain(handlers: [
            ExternalSchemeHandler(urlOpener: stubOpener),
            ModifierClickHandler(),
            DownloadActionHandler(),
        ])

        let action = MockNavigationAction.mainFrame(url: TestURLs.https)
        let policy = await chain.evaluate(action)

        #expect(policy == .allow)
    }

    @Test("Empty chain returns allow")
    func emptyChainReturnsAllow() async {
        let chain = NavigationActionChain(handlers: [])
        let action = MockNavigationAction(url: TestURLs.https)
        let policy = await chain.evaluate(action)

        #expect(policy == .allow)
    }
}

// MARK: - Navigation Response Chain Tests

@Suite("NavigationResponseChain", .tags(.navigation))
@MainActor
struct NavigationResponseChainTests {
    @Test("Chain short-circuits on download")
    func chainShortCircuitsOnDownload() async {
        let chain = NavigationResponseChain(handlers: [
            DownloadResponseHandler(),
            HTTPErrorHandler(),
        ])

        let response = MockNavigationResponse.download(url: TestURLs.pdf)
        let policy = await chain.evaluate(response)

        #expect(policy == .download)
    }

    @Test("Chain returns allow if all handlers return next")
    func chainReturnsAllowIfAllNext() async {
        let chain = NavigationResponseChain(handlers: [
            DownloadResponseHandler(),
            HTTPErrorHandler(),
        ])

        let response = MockNavigationResponse.html(url: TestURLs.https)
        let policy = await chain.evaluate(response)

        #expect(policy == .allow)
    }
}

// MARK: - Custom Redirect Handler Tests

@Suite("CustomRedirectHandler", .tags(.navigation))
@MainActor
struct CustomRedirectHandlerTests {
    // MARK: - Test Helpers

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func makeSettings(in context: ModelContext) -> BrowserSettings {
        let settings = BrowserSettings()
        context.insert(settings)
        return settings
    }

    private static func addRedirect(
        to settings: BrowserSettings,
        in context: ModelContext,
        name: String,
        sourcePattern: String,
        destinationTemplate: String,
        isEnabled: Bool = true,
        order: Int = 0,
    ) {
        let redirect = CustomRedirect(
            name: name,
            sourcePattern: sourcePattern,
            destinationTemplate: destinationTemplate,
            isEnabled: isEnabled,
            order: order,
        )
        context.insert(redirect)
        settings.privacyProtection.customRedirects.append(redirect)
    }

    // MARK: - Tests

    @Test("Matching redirect returns redirect policy")
    func matchingRedirect() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)
        Self.addRedirect(
            to: settings,
            in: container.mainContext,
            name: "Example redirect",
            sourcePattern: "example.com/*",
            destinationTemplate: "example.org/$1",
        )

        let handler = CustomRedirectHandler(settings: settings)
        let action = MockNavigationAction.mainFrame(url: URL(string: "https://example.com/user/status/123")!)
        let policy = await handler.evaluate(action)

        if case let .redirect(url) = policy {
            #expect(url.host == "example.org")
            #expect(url.path.contains("user/status/123"))
        } else {
            Issue.record("Expected .redirect, got \(policy)")
        }
    }

    @Test("Non-matching redirect passes through")
    func nonMatchingRedirect() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)
        Self.addRedirect(
            to: settings,
            in: container.mainContext,
            name: "Twitter to Nitter",
            sourcePattern: "twitter.com/*",
            destinationTemplate: "nitter.net/$1",
        )

        let handler = CustomRedirectHandler(settings: settings)
        let action = MockNavigationAction.mainFrame(url: TestURLs.https)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Disabled redirect passes through")
    func disabledRedirect() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)
        Self.addRedirect(
            to: settings,
            in: container.mainContext,
            name: "Twitter to Nitter",
            sourcePattern: "twitter.com/*",
            destinationTemplate: "nitter.net/$1",
            isEnabled: false,
        )

        let handler = CustomRedirectHandler(settings: settings)
        let action = MockNavigationAction.mainFrame(url: URL(string: "https://twitter.com/user")!)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("OAuth URLs bypass redirect rules")
    func oauthBypassesRedirects() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)
        Self.addRedirect(
            to: settings,
            in: container.mainContext,
            name: "OAuth Redirect",
            sourcePattern: "accounts.google.com/*",
            destinationTemplate: "example.com/$1",
        )

        let handler = CustomRedirectHandler(settings: settings)
        let action = MockNavigationAction.mainFrame(url: TestURLs.oauth)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Subframe navigation passes through")
    func subframePassesThrough() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)
        Self.addRedirect(
            to: settings,
            in: container.mainContext,
            name: "Twitter to Nitter",
            sourcePattern: "twitter.com/*",
            destinationTemplate: "nitter.net/$1",
        )

        let handler = CustomRedirectHandler(settings: settings)
        let action = MockNavigationAction.subframe(url: URL(string: "https://twitter.com/embed")!)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("First matching redirect wins by order")
    func firstMatchWins() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)

        // Add two redirects that both match, lower order first
        Self.addRedirect(
            to: settings,
            in: container.mainContext,
            name: "First",
            sourcePattern: "example.com/*",
            destinationTemplate: "first.com/$1",
            order: 0,
        )
        Self.addRedirect(
            to: settings,
            in: container.mainContext,
            name: "Second",
            sourcePattern: "example.com/*",
            destinationTemplate: "second.com/$1",
            order: 1,
        )

        let handler = CustomRedirectHandler(settings: settings)
        let action = MockNavigationAction.mainFrame(url: URL(string: "https://example.com/page")!)
        let policy = await handler.evaluate(action)

        if case let .redirect(url) = policy {
            #expect(url.host == "first.com")
        } else {
            Issue.record("Expected .redirect, got \(policy)")
        }
    }

    @Test("Empty redirects list passes through")
    func emptyRedirectsList() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)

        let handler = CustomRedirectHandler(settings: settings)
        let action = MockNavigationAction.mainFrame(url: TestURLs.https)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Nil URL passes through")
    func nilURLPassesThrough() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)
        Self.addRedirect(
            to: settings,
            in: container.mainContext,
            name: "Test",
            sourcePattern: "*",
            destinationTemplate: "test.com",
        )

        let handler = CustomRedirectHandler(settings: settings)
        let action = MockNavigationAction(url: nil)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }
}

// MARK: - URL Shortener Handler Tests

@Suite("URLShortenerHandler", .tags(.navigation))
@MainActor
struct URLShortenerHandlerTests {
    // MARK: - Test Helpers

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func makeSettings(in context: ModelContext, expandEnabled: Bool = true) -> BrowserSettings {
        let settings = BrowserSettings()
        context.insert(settings)
        settings.privacyProtection.expandURLShorteners = expandEnabled
        return settings
    }

    // MARK: - Tests

    @Test("Non-shortener URL passes through")
    func nonShortenerPassesThrough() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)

        let handler = URLShortenerHandler(settings: settings)
        let action = MockNavigationAction.mainFrame(url: TestURLs.https)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Disabled feature passes through")
    func disabledFeaturePassesThrough() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext, expandEnabled: false)

        let handler = URLShortenerHandler(settings: settings)
        // bit.ly is a known shortener
        let action = MockNavigationAction.mainFrame(url: URL(string: "https://bit.ly/abc123")!)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Subframe navigation passes through")
    func subframePassesThrough() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)

        let handler = URLShortenerHandler(settings: settings)
        let action = MockNavigationAction.subframe(url: URL(string: "https://bit.ly/abc123")!)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Exception domain passes through")
    func exceptionDomainPassesThrough() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)
        settings.privacyProtection.linkProtectionExceptions = ["bit.ly"]

        let handler = URLShortenerHandler(settings: settings)
        let action = MockNavigationAction.mainFrame(url: URL(string: "https://bit.ly/abc123")!)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Nil URL passes through")
    func nilURLPassesThrough() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)

        let handler = URLShortenerHandler(settings: settings)
        let action = MockNavigationAction(url: nil)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }
}

// MARK: - App Redirect Handler Tests

@Suite("AppRedirectHandler", .tags(.navigation))
@MainActor
struct AppRedirectHandlerTests {
    // MARK: - Test Helpers

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private static func makeSettings(in context: ModelContext) -> BrowserSettings {
        let settings = BrowserSettings()
        context.insert(settings)
        return settings
    }

    private static func addAppRule(
        to settings: BrowserSettings,
        in context: ModelContext,
        name: String,
        domainPattern: String,
        pathPattern: String? = nil,
        targetAppBundleID: String,
        isEnabled: Bool = true,
        order: Int = 0,
    ) {
        let rule = AppRedirectRule(
            name: name,
            domainPattern: domainPattern,
            pathPattern: pathPattern,
            targetAppBundleID: targetAppBundleID,
            isEnabled: isEnabled,
            order: order,
        )
        context.insert(rule)
        settings.privacyProtection.appRedirectRules.append(rule)
    }

    // MARK: - Tests

    @Test("Non-matching domain passes through")
    func nonMatchingDomain() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)
        Self.addAppRule(
            to: settings,
            in: container.mainContext,
            name: "YouTube",
            domainPattern: "youtube.com",
            targetAppBundleID: "com.google.Chrome",
        )

        let handler = AppRedirectHandler(settings: settings)
        let action = MockNavigationAction.mainFrame(url: TestURLs.https)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Disabled rule passes through")
    func disabledRule() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)
        Self.addAppRule(
            to: settings,
            in: container.mainContext,
            name: "YouTube",
            domainPattern: "youtube.com",
            targetAppBundleID: "com.google.Chrome",
            isEnabled: false,
        )

        let handler = AppRedirectHandler(settings: settings)
        let action = MockNavigationAction.mainFrame(url: URL(string: "https://youtube.com/watch?v=123")!)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Subframe navigation passes through")
    func subframePassesThrough() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)
        Self.addAppRule(
            to: settings,
            in: container.mainContext,
            name: "YouTube",
            domainPattern: "youtube.com",
            targetAppBundleID: "com.google.Chrome",
        )

        let handler = AppRedirectHandler(settings: settings)
        let action = MockNavigationAction.subframe(url: URL(string: "https://youtube.com/embed/123")!)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Empty rules list passes through")
    func emptyRulesList() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)

        let handler = AppRedirectHandler(settings: settings)
        let action = MockNavigationAction.mainFrame(url: URL(string: "https://youtube.com/watch")!)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("OAuth URLs bypass app redirects")
    func oauthBypassesAppRedirects() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)
        Self.addAppRule(
            to: settings,
            in: container.mainContext,
            name: "Google OAuth",
            domainPattern: "accounts.google.com",
            targetAppBundleID: "com.nonexistent.app.oauth",
        )

        let handler = AppRedirectHandler(settings: settings)
        let action = MockNavigationAction.mainFrame(url: TestURLs.oauth)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Nil URL passes through")
    func nilURLPassesThrough() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)
        Self.addAppRule(
            to: settings,
            in: container.mainContext,
            name: "YouTube",
            domainPattern: "youtube.com",
            targetAppBundleID: "com.google.Chrome",
        )

        let handler = AppRedirectHandler(settings: settings)
        let action = MockNavigationAction(url: nil)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Matching rule with non-existent app falls through")
    func matchingRuleNonExistentApp() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)
        // Use a bundle ID that definitely doesn't exist
        Self.addAppRule(
            to: settings,
            in: container.mainContext,
            name: "YouTube",
            domainPattern: "youtube.com",
            targetAppBundleID: "com.nonexistent.app.that.does.not.exist.12345",
        )

        let handler = AppRedirectHandler(settings: settings)
        let action = MockNavigationAction.mainFrame(url: URL(string: "https://youtube.com/watch?v=123")!)
        let policy = await handler.evaluate(action)

        // Should fall through since app doesn't exist
        #expect(policy == .next)
    }

    @Test("Path pattern non-match passes through")
    func pathPatternNonMatch() async throws {
        let container = try Self.makeContainer()
        let settings = Self.makeSettings(in: container.mainContext)
        Self.addAppRule(
            to: settings,
            in: container.mainContext,
            name: "YouTube Watch",
            domainPattern: "youtube.com",
            pathPattern: "/watch*",
            targetAppBundleID: "com.nonexistent.12345",
        )

        let handler = AppRedirectHandler(settings: settings)
        // This URL has /channel path, not /watch
        let action = MockNavigationAction.mainFrame(url: URL(string: "https://youtube.com/channel/abc")!)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }
}

// MARK: - Popup Handler Tests

@Suite("PopupHandler", .tags(.navigation))
@MainActor
struct PopupHandlerTests {
    // MARK: - Test Helpers

    private func makeHandler(
        policy: PopUpPolicy = .allow,
        probeResult: PopupContentProbe.ProbeResult = .skipProbe,
    ) -> (PopupHandler, MockPopUpPolicyProvider, MockPopupContentProbe) {
        let policyProvider = MockPopUpPolicyProvider()
        policyProvider.policy = policy
        let contentProbe = MockPopupContentProbe()
        contentProbe.result = probeResult
        let handler = PopupHandler(policyProvider: policyProvider, contentProbe: contentProbe)
        return (handler, policyProvider, contentProbe)
    }

    // MARK: - Basic Flow Tests

    @Test("Non-popup navigation passes through")
    func nonPopupPassesThrough() async {
        let (handler, _, _) = makeHandler()
        let action = MockNavigationAction.mainFrame(url: TestURLs.https)
        let policy = await handler.evaluate(action)

        #expect(policy == .next)
    }

    @Test("Popup with nil URL is cancelled")
    func nilURLCancelled() async {
        let (handler, _, _) = makeHandler()
        let action = MockNavigationAction.popup(url: nil)
        let policy = await handler.evaluate(action)

        #expect(policy == .cancel)
    }

    @Test("Popup with javascript: scheme is cancelled")
    func javascriptPopupCancelled() async {
        let (handler, _, _) = makeHandler()
        let action = MockNavigationAction.popup(url: TestURLs.javascript)
        let policy = await handler.evaluate(action)

        #expect(policy == .cancel)
    }

    // MARK: - Policy Tests (Script-Initiated)

    //
    // Popup policy only applies to script-initiated popups (window.open without gesture).
    // User-initiated popups (link clicks) always bypass the policy.

    @Test("Script-initiated popup blocked by .block policy")
    func scriptInitiatedBlockedByPolicy() async {
        let (handler, _, _) = makeHandler(policy: .block)
        let action = MockNavigationAction.popup(url: TestURLs.https, userInitiated: false)
        let policy = await handler.evaluate(action)

        #expect(policy == .cancel)
    }

    @Test("Script-initiated popup blocked by .blockAndNotify policy")
    func scriptInitiatedBlockedByNotifyPolicy() async {
        let (handler, _, _) = makeHandler(policy: .blockAndNotify)
        let action = MockNavigationAction.popup(url: TestURLs.https, userInitiated: false)
        let policy = await handler.evaluate(action)

        #expect(policy == .cancel)
    }

    @Test("Script-initiated popup allowed by .allow policy")
    func scriptInitiatedAllowedByPolicy() async {
        let (handler, _, _) = makeHandler(policy: .allow)
        let action = MockNavigationAction.popup(url: TestURLs.https, userInitiated: false)
        let policy = await handler.evaluate(action)

        if case let .openInNewTab(url, activate) = policy {
            #expect(url == TestURLs.https)
            #expect(activate == true) // Script-initiated popups activate
        } else {
            Issue.record("Expected .openInNewTab, got \(policy)")
        }
    }

    // MARK: - User Initiation Tests

    //
    // User-initiated popups (link clicks, form submissions) always bypass popup blocking.
    // This matches browser convention: clicking a link is fundamentally different from
    // script-initiated window.open() calls.

    @Test("User-initiated popup bypasses blocking policy")
    func userInitiatedBypassesBlockingPolicy() async {
        // Even with .blockAndNotify policy, user clicks should open the popup
        let (handler, _, _) = makeHandler(policy: .blockAndNotify, probeResult: .skipProbe)
        let action = MockNavigationAction.popup(url: TestURLs.https, userInitiated: true)
        let policy = await handler.evaluate(action)

        if case .openInNewTab = policy {
            // Success - user click bypassed the blocking policy
        } else {
            Issue.record("Expected .openInNewTab, got \(policy)")
        }
    }

    @Test("User-initiated popup is allowed")
    func userInitiatedAllowed() async {
        let (handler, _, _) = makeHandler(probeResult: .skipProbe)
        let action = MockNavigationAction.popup(url: TestURLs.https, userInitiated: true)
        let policy = await handler.evaluate(action)

        if case .openInNewTab = policy {
            // Success
        } else {
            Issue.record("Expected .openInNewTab, got \(policy)")
        }
    }

    // MARK: - Probe Result Tests

    @Test("Download probe result triggers download")
    func downloadProbeResult() async {
        let downloadURL = URL(string: "https://example.com/file.zip")!
        let (handler, _, _) = makeHandler(probeResult: .download(url: downloadURL, suggestedFilename: "file.zip"))
        let action = MockNavigationAction.popup(url: TestURLs.https, userInitiated: true)
        let policy = await handler.evaluate(action)

        if case let .download(url) = policy {
            #expect(url == downloadURL)
        } else {
            Issue.record("Expected .download, got \(policy)")
        }
    }

    @Test("Webpage probe result opens in new tab with final URL")
    func webpageProbeResult() async {
        let finalURL = URL(string: "https://final.example.com/page")!
        let (handler, _, _) = makeHandler(probeResult: .webpage(url: finalURL))
        let action = MockNavigationAction.popup(url: TestURLs.https, userInitiated: true)
        let policy = await handler.evaluate(action)

        if case let .openInNewTab(url, _) = policy {
            #expect(url == finalURL)
        } else {
            Issue.record("Expected .openInNewTab, got \(policy)")
        }
    }

    @Test("SkipProbe result opens original URL in new tab")
    func skipProbeResult() async {
        let (handler, _, _) = makeHandler(probeResult: .skipProbe)
        let action = MockNavigationAction.popup(url: TestURLs.https, userInitiated: true)
        let policy = await handler.evaluate(action)

        if case let .openInNewTab(url, _) = policy {
            #expect(url == TestURLs.https)
        } else {
            Issue.record("Expected .openInNewTab, got \(policy)")
        }
    }

    @Test("Unknown probe result opens in new tab")
    func unknownProbeResult() async {
        let (handler, _, _) = makeHandler(probeResult: .unknown)
        let action = MockNavigationAction.popup(url: TestURLs.https, userInitiated: true)
        let policy = await handler.evaluate(action)

        if case let .openInNewTab(url, _) = policy {
            #expect(url == TestURLs.https)
        } else {
            Issue.record("Expected .openInNewTab, got \(policy)")
        }
    }

    // MARK: - Tab Activation Tests

    @Test("Popup respects shouldActivateNewTab")
    func respectsActivateFlag() async {
        let (handler, _, _) = makeHandler(probeResult: .skipProbe)
        // Create a popup action with shouldActivateNewTab = true
        let action = MockNavigationAction(
            url: TestURLs.https,
            isNewWindowRequest: true,
            isUserInitiated: true,
            shouldActivateNewTab: true,
            targetIsMainFrame: nil,
        )
        let policy = await handler.evaluate(action)

        if case let .openInNewTab(_, activate) = policy {
            #expect(activate == true)
        } else {
            Issue.record("Expected .openInNewTab, got \(policy)")
        }
    }

    @Test("Popup with activate false opens in background")
    func activateFalseOpensBackground() async {
        let (handler, _, _) = makeHandler(probeResult: .skipProbe)
        let action = MockNavigationAction(
            url: TestURLs.https,
            isNewWindowRequest: true,
            isUserInitiated: true,
            shouldActivateNewTab: false,
            targetIsMainFrame: nil,
        )
        let policy = await handler.evaluate(action)

        if case let .openInNewTab(_, activate) = policy {
            #expect(activate == false)
        } else {
            Issue.record("Expected .openInNewTab, got \(policy)")
        }
    }
}
