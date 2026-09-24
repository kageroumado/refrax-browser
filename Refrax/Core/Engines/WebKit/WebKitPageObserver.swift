import WebKit

/// Translates a `WKWebView`'s observable properties into ``PageEvent``s.
///
/// Events are delivered synchronously on the main thread, inside the KVO
/// callback, so page state is current the moment WebKit changes — code that
/// reads a page's title right after a commit sees the new title, as it did
/// when those properties were read live from the web view.
///
/// Navigation lifecycle events (start, commit, finish, failure, renderer health)
/// come from the navigation delegate, which reports them through the same sink.
final class WebKitPageObserver {
    /// Minimum change in `estimatedProgress` worth an event; WebKit reports
    /// 50–100 increments per load.
    private static let progressThreshold = 0.01

    private var observations: [NSKeyValueObservation] = []
    private var lastProgress = 0.0

    /// Observes `webView` from now on and reports through `sink`.
    init(webView: WKWebView, sink: @escaping @MainActor (PageEvent) -> Void) {
        func observe<Value>(
            _ keyPath: KeyPath<WKWebView, Value>,
            _ event: @escaping @MainActor (WKWebView, Value) -> PageEvent?,
        ) -> NSKeyValueObservation {
            // Read only on the main thread, where WKWebView delivers KVO.
            nonisolated(unsafe) let keyPath = keyPath
            return webView.observe(keyPath, options: [.new]) { webView, _ in
                MainActor.assumeIsolated {
                    if let pageEvent = event(webView, webView[keyPath: keyPath]) {
                        sink(pageEvent)
                    }
                }
            }
        }

        observations = [
            observe(\.url) { _, url in url.map { .urlChanged(url: $0) } },
            observe(\.title) { _, title in .titleChanged(title: title ?? "") },
            observe(\.isLoading) { _, isLoading in .loadingChanged(isLoading: isLoading) },
            observe(\.canGoBack) { webView, _ in
                .backForwardChanged(canGoBack: webView.canGoBack, canGoForward: webView.canGoForward)
            },
            observe(\.canGoForward) { webView, _ in
                .backForwardChanged(canGoBack: webView.canGoBack, canGoForward: webView.canGoForward)
            },
            observe(\.estimatedProgress) { [unowned self] _, progress in
                guard abs(progress - lastProgress) >= Self.progressThreshold || progress >= 1 || progress < lastProgress else {
                    return nil
                }
                lastProgress = progress
                return .progressChanged(progress: progress)
            },
        ]
    }

    /// The web view's current state, for seeding a page's state when WebKit takes over rendering.
    static func snapshot(of webView: WKWebView) -> PageSnapshot {
        PageSnapshot(
            url: webView.url,
            title: webView.title ?? "",
            isLoading: webView.isLoading,
            progress: webView.estimatedProgress,
            canGoBack: webView.canGoBack,
            canGoForward: webView.canGoForward,
            zoom: webView.pageZoom,
        )
    }

    deinit {
        for observation in observations {
            observation.invalidate()
        }
    }
}

// MARK: - Navigation Lifecycle

extension PageEvent {
    /// The contract event for a WebKit main-frame navigation failure.
    static func webKitNavigationFailed(_ error: any Error, url: URL?, isProvisional: Bool) -> PageEvent {
        let nsError = error as NSError
        let kind: NavigationFailure.Kind = switch (nsError.domain, nsError.code) {
        case (NSURLErrorDomain, NSURLErrorCancelled): .cancelled
        case (NSURLErrorDomain, NSURLErrorCannotFindHost), (NSURLErrorDomain, NSURLErrorDNSLookupFailed): .cannotFindHost
        case (NSURLErrorDomain, NSURLErrorCannotConnectToHost): .cannotConnectToHost
        case (NSURLErrorDomain, NSURLErrorNotConnectedToInternet): .notConnectedToInternet
        case (NSURLErrorDomain, NSURLErrorNetworkConnectionLost): .connectionLost
        case (NSURLErrorDomain, NSURLErrorTimedOut): .timedOut
        case (NSURLErrorDomain, NSURLErrorServerCertificateUntrusted),
             (NSURLErrorDomain, NSURLErrorServerCertificateHasBadDate),
             (NSURLErrorDomain, NSURLErrorServerCertificateHasUnknownRoot),
             (NSURLErrorDomain, NSURLErrorServerCertificateNotYetValid),
             (NSURLErrorDomain, NSURLErrorSecureConnectionFailed): .certificateInvalid
        // WebKitErrorFrameLoadInterruptedByPolicyChange: the navigation became a download or was replaced.
        case ("WebKitErrorDomain", 102): .cancelled
        default: .other
        }
        let failedURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? url
        return .navigationFailed(failure: NavigationFailure(
            kind: kind,
            url: failedURL,
            isProvisional: isProvisional,
            engineCode: nsError.code,
            description: nsError.localizedDescription,
        ))
    }
}

extension RendererTerminationReason {
    init(_ reason: _WKProcessTerminationReason) {
        self = switch reason {
        case .exceededMemoryLimit: .exceededMemoryLimit
        case .exceededCPULimit: .exceededCPULimit
        case .requestedByClient: .requestedByBrowser
        case .crash: .crashed
        default: .unknown
        }
    }
}
