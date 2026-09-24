import AppKit
import Observation

/// A page's content running in a Chromium browser.
///
/// Mirrors the plug-in browser's state into observable properties so SwiftUI
/// chrome reading them through `WebPage` updates as Chromium reports changes,
/// and relays navigation events to the owning page.
@Observable
final class ChromiumPageSession: NSObject, EnginePageSession {
    let engine: RenderingEngineKind = .chromium
    let capabilities: EngineCapabilities = [.navigation, .javaScriptEvaluation, .zoom, .findInPage, .downloads, .devTools]

    @ObservationIgnored
    private let browser: any RFXChromiumBrowser

    @ObservationIgnored
    weak var delegate: (any EnginePageSessionDelegate)?

    private(set) var url: URL?
    private(set) var title: String = ""
    private(set) var isLoading = false
    private(set) var estimatedProgress: Double = 0
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    var zoomFactor: Double {
        get { browser.zoomFactor }
        set { browser.zoomFactor = newValue }
    }

    init(browser: any RFXChromiumBrowser) {
        self.browser = browser
        url = browser.url
        super.init()
        browser.delegate = self
    }

    var contentView: NSView {
        browser.view
    }

    func load(_ url: URL) {
        self.url = url
        browser.load(url)
    }

    func goBack() {
        browser.goBack()
    }

    func goForward() {
        browser.goForward()
    }

    func reload(fromOrigin: Bool) {
        if fromOrigin {
            browser.reloadIgnoringCache()
        } else {
            browser.reload()
        }
    }

    func stopLoading() {
        browser.stopLoading()
    }

    func evaluateJavaScript(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            browser.evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    nonisolated(unsafe) let value = result
                    continuation.resume(returning: value)
                }
            }
        }
    }

    func setHidden(_ hidden: Bool) {
        browser.setHidden(hidden)
    }

    func focus() {
        browser.focus()
    }

    func showDevTools() {
        browser.showDevTools()
    }

    func find(_ string: String, forward: Bool, matchCase: Bool, findNext: Bool) {
        browser.find(string, forward: forward, matchCase: matchCase, findNext: findNext)
    }

    func stopFinding() {
        browser.stopFinding()
    }

    func close() {
        browser.close()
    }
}

// MARK: - RFXChromiumBrowserDelegate

extension ChromiumPageSession: RFXChromiumBrowserDelegate {
    func chromiumBrowser(_: any RFXChromiumBrowser, didChange url: URL) {
        self.url = url
    }

    func chromiumBrowser(_: any RFXChromiumBrowser, didChangeTitle title: String) {
        self.title = title
        delegate?.engineSession(self, didChangeTitle: title)
    }

    func chromiumBrowser(_: any RFXChromiumBrowser, didChangeLoading isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {
        self.isLoading = isLoading
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        if !isLoading {
            estimatedProgress = 1
        }
    }

    func chromiumBrowser(_: any RFXChromiumBrowser, didChangeProgress progress: Double) {
        // Matches WebPage's throttling: only notify on whole-percent steps.
        if abs(progress - estimatedProgress) >= 0.01 || progress >= 1 {
            estimatedProgress = progress
        }
    }

    func chromiumBrowser(_: any RFXChromiumBrowser, didCommitNavigationBackForward isBackForward: Bool) {
        guard let url else { return }
        delegate?.engineSession(self, didCommitNavigationTo: url, isBackForward: isBackForward)
    }

    func chromiumBrowser(_: any RFXChromiumBrowser, didFinishLoadWithStatusCode statusCode: Int) {
        delegate?.engineSession(self, didFinishNavigationWithStatusCode: statusCode)
    }

    func chromiumBrowser(
        _: any RFXChromiumBrowser,
        didFailLoadWithErrorCode errorCode: Int,
        description: String,
        failedURL: URL?,
    ) {
        delegate?.engineSession(self, didFailNavigationTo: failedURL, code: errorCode, description: description)
    }

    func chromiumBrowser(_: any RFXChromiumBrowser, didChangeFaviconURLs urls: [URL]) {
        delegate?.engineSession(self, didChangeFaviconURLs: urls)
    }

    func chromiumBrowser(_: any RFXChromiumBrowser, didHoverLink url: URL?) {
        delegate?.engineSession(self, didHoverLink: url)
    }

    func chromiumBrowser(
        _: any RFXChromiumBrowser,
        requestsOpening url: URL,
        disposition: RFXChromiumOpenDisposition,
        userGesture _: Bool,
    ) {
        let mapped: EngineOpenDisposition = switch disposition {
        case .currentTab: .currentTab
        case .backgroundTab: .backgroundTab
        case .popup: .popup
        case .newWindow: .newWindow
        default: .foregroundTab
        }
        delegate?.engineSession(self, requestsOpening: url, disposition: mapped)
    }

    /// Element fullscreen in a child-window Chromium view fills the view, so the
    /// window itself follows the page in and out of fullscreen.
    func chromiumBrowser(_: any RFXChromiumBrowser, didChangeFullscreen fullscreen: Bool) {
        guard let window = contentView.window,
              window.styleMask.contains(.fullScreen) != fullscreen else { return }
        window.toggleFullScreen(nil)
    }

    func chromiumBrowser(_: any RFXChromiumBrowser, renderProcessTerminatedWithStatus _: Int) {
        delegate?.engineSessionRenderProcessDidTerminate(self)
    }

    func chromiumBrowser(
        _: any RFXChromiumBrowser,
        destinationForDownloadOf url: URL,
        suggestedName: String,
    ) -> URL? {
        delegate?.engineSession(self, destinationForDownloadOf: url, suggestedFilename: suggestedName)
    }

    func chromiumBrowser(
        _: any RFXChromiumBrowser,
        downloadDidUpdate destination: URL,
        receivedBytes: Int64,
        totalBytes: Int64,
        isComplete: Bool,
        isCanceled _: Bool,
    ) {
        if isComplete {
            Logger.info("Chromium download finished: \(destination.lastPathComponent) (\(receivedBytes) of \(totalBytes) bytes)", category: Logger.downloads)
        }
    }
}
