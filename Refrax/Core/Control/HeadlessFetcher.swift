import OSLog
import RefraxProtocol
import WebKit

/// Fetches web page content using a temporary WKWebView without creating a tab.
///
/// Uses the same WKWebViewConfiguration as the browser (content blockers, cookies,
/// privacy headers, URL scheme handlers) but doesn't attach to any tab or window.
/// Page visibility is spoofed to prevent JS-heavy sites from behaving differently
/// in the background.
///
/// After the initial document load, waits for JavaScript-rendered content to settle
/// by monitoring DOM mutations. This handles SPAs (Twitter, React apps, etc.) that
/// load an empty shell and render content asynchronously.
@MainActor
enum HeadlessFetcher {
    private static let logger = OSLog(subsystem: "website.refrax.browser", category: "headless-fetch")

    /// The page visibility override script, injected at document-start.
    private static let visibilityScript = WKUserScript(
        source: """
        (function() {
            try {
                Object.defineProperty(Document.prototype, 'visibilityState', {
                    get: function() { return 'visible'; },
                    configurable: true
                });
                Object.defineProperty(Document.prototype, 'hidden', {
                    get: function() { return false; },
                    configurable: true
                });
            } catch (e) {}
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: false
    )

    /// JavaScript that installs a MutationObserver on `document.body` to track
    /// when the DOM has stopped changing. Exposes `__refrax_settled(thresholdMs)`
    /// which returns `true` when no mutations have occurred for `thresholdMs`.
    private static let settleObserverScript = """
    (function() {
        if (window.__refrax_lastMutation) return;
        window.__refrax_lastMutation = Date.now();
        var obs = new MutationObserver(function() {
            window.__refrax_lastMutation = Date.now();
        });
        if (document.body) {
            obs.observe(document.body, {
                childList: true, subtree: true,
                characterData: true, attributes: false
            });
        }
        window.__refrax_settled = function(thresholdMs) {
            return (Date.now() - window.__refrax_lastMutation) >= thresholdMs;
        };
    })();
    """

    /// Minimum time (ms) with no DOM mutations before the page is considered settled.
    private static let settleThresholdMs = 1_500

    /// How often to poll the settle check.
    private static let settlePollInterval: Duration = .milliseconds(200)

    /// Maximum time to spend waiting for content to settle after initial load.
    private static let maxSettleWait: Duration = .seconds(10)

    /// Fetches a URL and returns its page content as formatted text.
    ///
    /// Creates a temporary WKWebView with the browser's shared configuration
    /// (content blockers, cookies, privacy settings), loads the URL, waits for
    /// the document to finish loading, then waits for JS-rendered content to
    /// settle before extracting content.
    ///
    /// - Parameters:
    ///   - url: The URL to fetch.
    ///   - scope: Content extraction scope (viewport, full, text, html, mainContent).
    ///   - timeoutSeconds: Maximum seconds to wait for page load.
    ///   - configuration: The browser's shared WebPage configuration.
    /// - Returns: Formatted page content string.
    static func fetch(
        url: URL,
        scope: ControlRequest.PageContentParams.Scope,
        timeoutSeconds: Int,
        configuration: WebPage.Configuration
    ) async throws -> String {
        let wkConfig = configuration.makeWKWebViewConfiguration()

        // Inject page visibility spoofing so the page thinks it's in the foreground
        wkConfig.userContentController.addUserScript(visibilityScript)

        // Match WebPagePool.estimateExpectedFrame fallback (1024x768)
        let webView = WKWebView(
            frame: CGRect(x: 0, y: 0, width: 1_024, height: 768),
            configuration: wkConfig
        )

        // Delegate to track navigation completion
        let delegate = NavigationDelegate()
        webView.navigationDelegate = delegate

        os_log("Fetching %{public}@", log: logger, type: .info, url.absoluteString)

        webView.load(URLRequest(url: url))

        // Wait for initial document load
        try await delegate.waitForLoad(timeout: timeoutSeconds)

        // Wait for JS-rendered content to settle
        await waitForContentSettled(webView: webView)

        // Extract content
        let tree = try await PageContentExtractor.extract(
            from: webView,
            url: webView.url ?? url,
            title: webView.title ?? ""
        )

        let formatterScope: PageContentFormatter.Scope = switch scope {
        case .full: .full
        case .mainContent: .mainContent
        case .text: .full  // text scope uses full extraction, formatted as text
        default: .viewport
        }

        if scope == .text {
            // For text scope, use JavaScript to get the full text content
            let text = try await webView.evaluateJavaScript("document.body?.innerText ?? ''") as? String ?? ""
            return text
        } else if scope == .html {
            let html = try await webView.evaluateJavaScript("document.documentElement.outerHTML") as? String ?? ""
            return html
        }

        let text = PageContentFormatter.format(tree, scope: formatterScope)
        return text
    }

    /// Waits for the page's DOM to stop changing, indicating JS rendering is complete.
    ///
    /// Installs a MutationObserver and polls until no mutations have occurred for
    /// ``settleThresholdMs``. Returns early if the page has substantial content
    /// immediately (static sites) or if ``maxSettleWait`` is exceeded.
    private static func waitForContentSettled(webView: WKWebView) async {
        // Install the mutation observer
        do {
            try await webView.evaluateJavaScript(settleObserverScript)
        } catch {
            os_log("Failed to install settle observer: %{public}@", log: logger, type: .debug, error.localizedDescription)
            return
        }

        let deadline = ContinuousClock.now + maxSettleWait

        while ContinuousClock.now < deadline {
            try? await Task.sleep(for: settlePollInterval)

            do {
                let settled = try await webView.evaluateJavaScript(
                    "__refrax_settled(\(settleThresholdMs))"
                ) as? Bool ?? false

                if settled {
                    os_log("Content settled", log: logger, type: .debug)
                    return
                }
            } catch {
                return
            }
        }

        os_log("Content settle timeout — proceeding with extraction", log: logger, type: .debug)
    }
}

// MARK: - Navigation Delegate

/// Minimal WKNavigationDelegate that tracks load completion via async/await.
private final class NavigationDelegate: NSObject, WKNavigationDelegate, @unchecked Sendable {
    private let continuation = LoadContinuation()

    func waitForLoad(timeout: Int) async throws {
        try await continuation.wait(timeout: timeout)
    }

    func webView(_: WKWebView, didFinish _: WKNavigation!) {
        continuation.resume(with: .success(()))
    }

    func webView(_: WKWebView, didFail _: WKNavigation!, withError error: any Error) {
        continuation.resume(with: .failure(error))
    }

    func webView(_: WKWebView, didFailProvisionalNavigation _: WKNavigation!, withError error: any Error) {
        continuation.resume(with: .failure(error))
    }
}

/// Thread-safe continuation wrapper for tracking a single load event.
private final class LoadContinuation: @unchecked Sendable {
    private var continuation: CheckedContinuation<Void, any Error>?
    private var result: Result<Void, any Error>?
    private let lock = NSLock()

    func resume(with result: Result<Void, any Error>) {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(with: result)
        } else {
            self.result = result
            lock.unlock()
        }
    }

    func wait(timeout: Int) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, any Error>) in
            lock.lock()
            if let result {
                lock.unlock()
                cont.resume(with: result)
            } else {
                self.continuation = cont
                lock.unlock()
            }
        }
    }
}
