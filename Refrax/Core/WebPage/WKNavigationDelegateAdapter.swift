import Foundation
import UniformTypeIdentifiers
import WebKit

// MARK: - WKNavigationDelegateAdapter

/// Navigation delegate adapter that bridges `WKNavigationDelegate` to `BrowserNavigationDecider`.
///
/// This class implements `WKNavigationDelegate` and forwards events to the configured
/// `BrowserNavigationDecider`, converting between WebKit types and our wrapper types.
///
/// ## Design Notes
///
/// This adapter mirrors WebKit's `WKNavigationDelegateAdapter` to maintain API compatibility.
/// Key responsibilities:
/// - Navigation policy decisions (action, response, auth challenges)
/// - Navigation progress events (start, redirect, commit, finish, fail)
/// - Back-forward list updates
/// - Process termination handling (via WKNavigationDelegatePrivate)
/// - Process responsiveness monitoring
final class WKNavigationDelegateAdapter: NSObject, WKNavigationDelegate, WKDownloadDelegate {
    // MARK: - Properties

    /// The navigation decider that handles policy decisions.
    private var navigationDecider: BrowserNavigationDecider

    /// Reference to the owning WebPage.
    weak var owner: WebPage?

    /// Reference to the page pool for process termination handling.
    weak var pagePool: WebPagePool?

    /// Download manager for handling completed downloads.
    weak var downloadManager: DownloadManager?

    /// Last time extension dispatch was performed (for rate limiting).
    private var lastExtensionDispatchTime: Date?

    // MARK: - Initialization

    init(navigationDecider: BrowserNavigationDecider) {
        self.navigationDecider = navigationDecider
        super.init()
    }

    // MARK: - Policy Decisions

    func webView(
        _: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        preferences: WKWebpagePreferences,
    ) async -> (WKNavigationActionPolicy, WKWebpagePreferences) {
        let action = WebPage.NavigationAction(navigationAction, redirectChain: owner?.redirectChain)

        if let owner, action.isMainFrame, action.isUserInitiated {
            owner.redirectChain.reset()
            if let url = action.url {
                owner.redirectChain.append(url)
            }
        }

        let convertedAction = WebPage.NavigationAction(navigationAction, redirectChain: owner?.redirectChain)
        var convertedPreferences = WebPage.NavigationPreferences(preferences)

        let result = await navigationDecider.decidePolicy(for: convertedAction, preferences: &convertedPreferences)
        let newPreferences = WKWebpagePreferences(convertedPreferences)

        // Apply per-site user agent for main-frame navigations.
        // Must be set before the request is sent so the server sees the correct UA.
        if navigationAction.targetFrame?.isMainFrame == true,
           let url = navigationAction.request.url {
            let policy = UserAgentPolicy.policy(for: url.host?.lowercased() ?? "")
            let provider = UserAgentProvider()
            owner?.customUserAgent = provider.userAgent(for: policy)
        }

        // Apply per-site autoplay policy via WebKit's native enforcement.
        // This lets WebKit handle autoplay gating correctly, distinguishing
        // user-initiated playback from true autoplay.
        if let url = navigationAction.request.url,
           let coordinator = owner?.siteSettingsCoordinator {
            let policy = coordinator.autoPlayPolicy(for: url)
            newPreferences._autoplayPolicy = policy.websiteAutoplayPolicy
        }

        return (result, newPreferences)
    }

    func webView(
        _: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
    ) async -> WKNavigationResponsePolicy {
        let convertedResponse = WebPage.NavigationResponse(navigationResponse)
        return await navigationDecider.decidePolicy(for: convertedResponse)
    }

    func webView(
        _: WKWebView,
        respondTo challenge: URLAuthenticationChallenge,
    ) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
        await navigationDecider.decideAuthenticationChallengeDisposition(for: challenge)
    }

    // MARK: - Navigation Progress Reporting

    /// Yields a navigation progress event to the owner.
    ///
    /// For `.finished` events, the event is yielded after the next presentation update
    /// to ensure the page is fully rendered before notifying observers.
    ///
    /// - Note: WKNavigationDelegate callbacks are delivered on main thread.
    private func yieldNavigationProgress(kind: WebPage.NavigationEvent, cocoaNavigation: WKNavigation!) {
        // WKNavigationDelegate callbacks are on main thread - use assumeIsolated
        // to call the @MainActor addNavigationEvent method.
        let addEvent: @MainActor () -> Void = { [weak owner] in
            guard let owner else { return }
            owner.addNavigationEvent(.success(kind), for: cocoaNavigation)
        }

        if kind == .finished {
            // A presentation update is only guaranteed when a navigation has finished.
            // The callback from _do(afterNextPresentationUpdate:) is also on main thread.
            owner?.backingWebView._do(afterNextPresentationUpdate: {
                MainActor.assumeIsolated { addEvent() }
            })
        } else {
            MainActor.assumeIsolated { addEvent() }
        }
    }

    /// Yields a navigation failure event to the owner.
    ///
    /// - Note: WKNavigationDelegate callbacks are delivered on main thread.
    private func failNavigationProgress(kind: some Error, cocoaNavigation: WKNavigation?) {
        MainActor.assumeIsolated {
            owner?.addNavigationEvent(.failure(kind), for: cocoaNavigation)
        }
    }

    // MARK: - Navigation Events

    func webView(_: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        yieldNavigationProgress(kind: .startedProvisionalNavigation, cocoaNavigation: navigation)

        // Cancel any in-progress translation when navigating away
        owner?.resetTranslationState()

        // Notify extensions that loading started
        if let tabPage = owner?.tabPage {
            pagePool?.extensionManager?.dispatchLoadingChanged(tabPage)
        }
    }

    func webView(_: WKWebView, didReceiveServerRedirectForProvisionalNavigation navigation: WKNavigation!) {
        if let url = owner?.backingWebView.url {
            owner?.redirectChain.append(url)
        }
        yieldNavigationProgress(kind: .receivedServerRedirect, cocoaNavigation: navigation)
    }

    func webView(_: WKWebView, didCommit navigation: WKNavigation!) {
        yieldNavigationProgress(kind: .committed, cocoaNavigation: navigation)

        // Notify extensions of URL change
        if let tabPage = owner?.tabPage, let url = owner?.backingWebView.url {
            pagePool?.extensionManager?.dispatchNavigationCommitted(tabPage, url: url)
        }
    }

    func webView(_: WKWebView, didFinish navigation: WKNavigation!) {
        owner?.redirectChain.reset()
        yieldNavigationProgress(kind: .finished, cocoaNavigation: navigation)

        // Notify extensions of loading complete and title change
        // Rate limit extension dispatch to once per 100ms to avoid redundant work
        // during rapid navigations (redirects, reloads)
        if let tabPage = owner?.tabPage {
            let now = Date()
            let shouldDispatch = lastExtensionDispatchTime.map { now.timeIntervalSince($0) >= 0.1 } ?? true

            if shouldDispatch {
                lastExtensionDispatchTime = now
                pagePool?.extensionManager?.dispatchLoadingChanged(tabPage)
                pagePool?.extensionManager?.dispatchTitleChanged(tabPage)
            }
        }

        // Update Handoff activity if this is the active tab in any window
        // (respects privacy for private spaces)
        if let owner, let state = pagePool?.state, let tab = owner.tabPage.tab,
           let space = tab.space, let windowManager = pagePool?.windowManager {
            let isActiveTab = windowManager.windowControllers.contains { controller in
                controller.windowState.activeTabID(for: space.id) == tab.id
            }
            if isActiveTab {
                state.handoffManager.updateActivity(for: tab)
            }
        }
    }

    func webView(_: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        owner?.redirectChain.reset()
        failNavigationProgress(kind: WebPage.NavigationError.failedProvisionalNavigation(error), cocoaNavigation: navigation)
    }

    func webView(_: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        owner?.redirectChain.reset()
        failNavigationProgress(kind: error, cocoaNavigation: navigation)
    }

    func webViewWebContentProcessDidTerminate(_: WKWebView) {
        failNavigationProgress(kind: WebPage.NavigationError.webContentProcessTerminated, cocoaNavigation: nil)
        // Also notify page pool with default crash reason
        notifyProcessTermination(reason: .crash)
    }

    // MARK: - Process Termination (WKNavigationDelegatePrivate)

    /// Called when the web content process terminates with a specific reason.
    ///
    /// This private delegate method provides more detail than the public
    /// `webViewWebContentProcessDidTerminate:` by including the termination reason.
    @objc(_webView:webContentProcessDidTerminateWithReason:)
    func _webView(_: WKWebView, webContentProcessDidTerminateWithReason reason: Int) {
        let terminationReason = _WKProcessTerminationReason(rawValue: reason) ?? .crash

        Logger.info(
            "Process termination callback: \(terminationReason.logDescription)",
            category: Logger.tabs,
        )

        failNavigationProgress(kind: WebPage.NavigationError.webContentProcessTerminated, cocoaNavigation: nil)
        notifyProcessTermination(reason: terminationReason)
    }

    /// Called when the web process becomes unresponsive.
    @objc(_webViewWebProcessDidBecomeUnresponsive:)
    func _webViewWebProcessDidBecomeUnresponsive(_: WKWebView) {
        guard let pageID = owner?.tabPage.id, let pagePool else { return }

        Logger.warning("Process became unresponsive", category: Logger.tabs)
        pagePool.handleProcessUnresponsive(for: pageID)
    }

    /// Called when an unresponsive web process becomes responsive again.
    @objc(_webViewWebProcessDidBecomeResponsive:)
    func _webViewWebProcessDidBecomeResponsive(_: WKWebView) {
        guard let pageID = owner?.tabPage.id, let pagePool else { return }

        Logger.info("Process became responsive", category: Logger.tabs)
        pagePool.handleProcessResponsive(for: pageID)
    }

    /// Legacy crash callback (fallback when reason not available).
    @objc(_webViewWebProcessDidCrash:)
    func _webViewWebProcessDidCrash(_: WKWebView) {
        Logger.warning("Process crashed (legacy callback)", category: Logger.tabs)
        failNavigationProgress(kind: WebPage.NavigationError.webContentProcessTerminated, cocoaNavigation: nil)
        notifyProcessTermination(reason: .crash)
    }

    /// Notifies the page pool of process termination.
    private func notifyProcessTermination(reason: _WKProcessTerminationReason) {
        guard let pageID = owner?.tabPage.id, let pagePool else { return }
        pagePool.handleProcessTermination(for: pageID, reason: reason)
    }

    // MARK: - Same-Document Navigation (WKNavigationDelegatePrivate)

    /// Called when a same-document navigation occurs (History API, anchor clicks).
    ///
    /// SPAs like GitHub and YouTube use `history.pushState()` to update the URL
    /// without triggering a full navigation. This callback detects those changes
    /// and updates the TabPage model accordingly.
    ///
    /// - Parameters:
    ///   - webView: The web view that performed the navigation.
    ///   - navigation: The navigation object (may be nil for some navigation types).
    ///   - navigationType: The type of same-document navigation.
    @objc(_webView:navigation:didSameDocumentNavigation:)
    func _webView(
        _ webView: WKWebView!,
        navigation _: WKNavigation!,
        didSameDocumentNavigation navigationType: Int,
    ) {
        let type = _WKSameDocumentNavigationType(rawValue: navigationType)

        // Only update URL for History API navigations (pushState/replaceState)
        // Anchor navigations don't change the meaningful URL
        guard type == .sessionStatePush || type == .sessionStateReplace else { return }

        guard let newURL = webView.url else { return }

        MainActor.assumeIsolated {
            owner?.tabPage.url = newURL
        }
    }

    // MARK: - Back-Forward List Support

    /// Updates the back-forward list when items are added or removed.
    ///
    /// This private delegate method is called by WebKit when the back-forward list changes.
    @objc(_webView:backForwardListItemAdded:removed:)
    func _webView(
        _ webView: WKWebView!,
        backForwardListItemAdded _: WKBackForwardListItem!,
        removed _: [WKBackForwardListItem]!,
    ) {
        owner?.backForwardList = .init(webView.backForwardList)
    }

    // MARK: - Download Interception

    func webView(_: WKWebView, navigationAction _: WKNavigationAction, didBecome download: WKDownload) {
        configureDownload(download)
    }

    func webView(_: WKWebView, navigationResponse _: WKNavigationResponse, didBecome download: WKDownload) {
        configureDownload(download)
    }

    /// Intercepts context menu "Download Linked File" (private API).
    @objc(_webView:contextMenuDidCreateDownload:)
    func _webView(_: WKWebView, contextMenuDidCreateDownload download: WKDownload) {
        configureDownload(download)
        Logger.info("Context menu download intercepted", category: Logger.downloads)
    }

    private func configureDownload(_ download: WKDownload) {
        download.delegate = self
    }

    // MARK: - WKDownloadDelegate

    /// Handles WKDownload destination decisions by delegating to DownloadManager.
    ///
    /// Instead of handling downloads directly (which bypasses progress tracking,
    /// space-specific settings, and aria2 support), we:
    /// 1. Extract the URL and metadata from the WKDownload
    /// 2. Start a proper download via DownloadManager
    /// 3. Return `nil` to cancel the WKDownload
    ///
    /// This ensures all downloads go through the same path with full features:
    /// - Progress tracking with Finder/Dock integration
    /// - Space-aware download directories and color tags
    /// - Proper cookie context from the correct WKWebsiteDataStore
    /// - Aria2 support for large files
    /// - Pause/resume/cancel capabilities
    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
    ) async -> URL? {
        guard let downloadManager else {
            Logger.warning("DownloadManager unavailable, cannot handle WKDownload", category: Logger.downloads)
            return nil
        }

        // Get the download URL (prefer response URL as it reflects redirects)
        guard let downloadURL = response.url ?? download.originalRequest?.url else {
            Logger.warning("No URL available for WKDownload", category: Logger.downloads)
            return nil
        }

        // Get space context from the owning WebPage
        let (customDownloadPath, spaceID, spaceName, colorTag, dataStore, originatingURL, originatingTitle) = getSpaceContext()

        Logger.info(
            "Delegating WKDownload to DownloadManager: \(suggestedFilename)",
            category: Logger.downloads,
        )

        // Start the download via DownloadManager (creates its own URLSession task)
        do {
            try await downloadManager.startDownload(
                from: downloadURL,
                suggestedFilename: suggestedFilename,
                mimeType: response.mimeType,
                contentLength: response.expectedContentLength > 0 ? response.expectedContentLength : nil,
                originatingURL: originatingURL,
                originatingTitle: originatingTitle,
                dataStore: dataStore,
                customDownloadPath: customDownloadPath,
                spaceID: spaceID,
                spaceName: spaceName,
                colorTag: colorTag,
            )
        } catch {
            Logger.error("Failed to start download via DownloadManager: \(error)", category: Logger.downloads)
        }

        // Return nil to cancel the WKDownload - DownloadManager handles it from here
        return nil
    }

    /// Handles WKDownload failures.
    ///
    /// Since we cancel WKDownloads by returning `nil` from `decideDestinationUsing`,
    /// this method will be called with a cancellation error. We suppress logging
    /// for intentional cancellations.
    func download(_: WKDownload, didFailWithError error: any Error, resumeData _: Data?) {
        // WebKit delivers download delegate callbacks on main thread.
        MainActor.assumeIsolated {
            // Check if this is an intentional cancellation (we returned nil from decideDestinationUsing)
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                // Intentional cancellation - we delegated to DownloadManager
                return
            }

            // Unexpected failure - log it
            Logger.warning("WKDownload failed: \(error.localizedDescription)", category: Logger.downloads)
        }
    }

    /// Called when a WKDownload completes.
    ///
    /// Since we cancel WKDownloads by returning `nil` from `decideDestinationUsing`,
    /// this method should never be called. Included for protocol completeness.
    func downloadDidFinish(_: WKDownload) {
        // Should not be called since we cancel WKDownloads in decideDestinationUsing
        Logger.warning("Unexpected downloadDidFinish called - WKDownload should have been cancelled", category: Logger.downloads)
    }

    // MARK: - Space Context Helpers

    /// Extracts space-specific download context from the owning WebPage.
    private func getSpaceContext() -> (
        customDownloadPath: String?,
        spaceID: UUID?,
        spaceName: String?,
        colorTag: Int?,
        dataStore: WKWebsiteDataStore?,
        originatingURL: URL?,
        originatingTitle: String?,
    ) {
        guard let owner else {
            return (nil, nil, nil, nil, nil, nil, nil)
        }

        let originatingURL = owner.url
        let originatingTitle = owner.title
        let dataStore = owner.websiteDataStore

        guard let space = owner.tabPage.tab?.space else {
            return (nil, nil, nil, nil, dataStore, originatingURL, originatingTitle)
        }

        return (
            space.customDownloadPath,
            space.id,
            space.name,
            space.downloadColorTag,
            dataStore,
            originatingURL,
            originatingTitle,
        )
    }
}

// MARK: - Preference Conversions

extension WebPage.NavigationPreferences {
    /// Creates navigation preferences from WebKit preferences.
    init(_ preferences: WKWebpagePreferences) {
        self.preferredContentMode = ContentMode(preferences.preferredContentMode)
        self.allowsContentJavaScript = preferences.allowsContentJavaScript
        self.preferredHTTPSNavigationPolicy = UpgradeToHTTPSPolicy(preferences.preferredHTTPSNavigationPolicy)
        self.isLockdownModeEnabled = preferences.isLockdownModeEnabled
    }
}

extension WKWebpagePreferences {
    /// Creates WebKit preferences from navigation preferences.
    convenience init(_ preferences: WebPage.NavigationPreferences) {
        self.init()
        self.preferredContentMode = preferences.preferredContentMode.wkContentMode
        self.allowsContentJavaScript = preferences.allowsContentJavaScript
        self.preferredHTTPSNavigationPolicy = preferences.preferredHTTPSNavigationPolicy.wkPolicy
        self.isLockdownModeEnabled = preferences.isLockdownModeEnabled
    }
}

extension WebPage.NavigationPreferences.ContentMode {
    init(_ wkMode: WKWebpagePreferences.ContentMode) {
        self = switch wkMode {
        case .recommended: .recommended
        case .mobile: .mobile
        case .desktop: .desktop
        @unknown default: .recommended
        }
    }
}

extension WebPage.NavigationPreferences.UpgradeToHTTPSPolicy {
    init(_ wkPolicy: WKWebpagePreferences.UpgradeToHTTPSPolicy) {
        self = switch wkPolicy {
        case .keepAsRequested: .keepAsRequested
        case .automaticFallbackToHTTP: .automaticFallbackToHTTP
        case .userMediatedFallbackToHTTP: .userMediatedFallbackToHTTP
        case .errorOnFailure: .errorOnFailure
        @unknown default: .keepAsRequested
        }
    }
}
