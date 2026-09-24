import AppKit
import WebKit

// MARK: - Engine Switching

extension WebPage {
    /// The engine currently hosting this page's content.
    var activeEngine: RenderingEngineKind {
        engineSession?.engine ?? .webKit
    }

    /// Moves the page's content to `engine` and loads the current URL there.
    ///
    /// The tab, its history entries, and the chrome stay put; only the content
    /// view and the navigation source change. WebKit's view is kept (paused)
    /// while another engine hosts the page, so switching back reuses it.
    func switchEngine(to engine: RenderingEngineKind) throws {
        guard engine != activeEngine else { return }
        let currentURL = url ?? tabPage.url

        switch engine {
        case .webKit:
            let zoom = engineSession?.zoomFactor
            tearDownEngineSession()
            if let zoom { backingWebView.pageZoom = zoom }
            load(currentURL)

        case .chromium:
            let session = try ChromiumEngine.shared.makeSession(
                url: currentURL.isBlank ? nil : currentURL,
                profile: EngineProfile(space: tabPage.tab?.space),
            )
            session.delegate = self
            session.zoomFactor = backingWebView.pageZoom
            backingWebView.stopLoading()
            backingWebView.pauseAllMediaPlayback()
            httpErrorCode = nil
            httpErrorURL = nil
            crashError = nil
            engineSession = session
        }
        Logger.info("Page \(tabPage.id) now renders with \(engine.displayName): \(currentURL.absoluteString)", category: Logger.engines)
    }

    /// Closes the plug-in engine session, if any. Called when the page ends.
    func tearDownEngineSession() {
        guard let session = engineSession else { return }
        session.delegate = nil
        session.close()
        engineSession = nil
    }
}

// MARK: - EnginePageSessionDelegate

extension WebPage: EnginePageSessionDelegate {
    func engineSession(_ session: any EnginePageSession, didCommitNavigationTo url: URL, isBackForward: Bool) {
        let urlChanged = lastCommittedURL != url
        let previousHost = lastCommittedURL?.host

        tabPage.url = url
        if !session.title.isEmpty {
            tabPage.title = session.title
        }
        httpErrorCode = nil
        httpErrorURL = nil
        crashError = nil
        if !url.isDeepLink {
            deepLinkFlag.deepLinkURL = nil
        }
        updateAutoFillURL(url)
        lastCommittedURL = url

        if urlChanged, !isBackForward {
            handleURLChangeForHistory(to: url)
        }
        if previousHost != url.host {
            refreshEngineFavicon(for: url, clearingPrevious: previousHost != nil)
        }
    }

    func engineSession(_ session: any EnginePageSession, didFinishNavigationWithStatusCode statusCode: Int) {
        if !session.title.isEmpty {
            tabPage.title = session.title
            historyManager.updateEntry(for: tabPage.id, title: session.title)
        }
        if statusCode >= 400, currentHistoryEntry != nil {
            historyManager.markEntryFailed(for: tabPage.id, statusCode: statusCode)
        }
    }

    func engineSession(_: any EnginePageSession, didFailNavigationTo url: URL?, code: Int, description: String) {
        Logger.warning("Chromium navigation failed (\(code) \(description)): \(url?.absoluteString ?? "-")", category: Logger.engines)
        httpErrorCode = Self.urlErrorCode(forChromiumNetError: code)
        httpErrorURL = url ?? tabPage.url
        if currentHistoryEntry != nil {
            historyManager.markEntryFailed(for: tabPage.id, statusCode: nil)
        }
    }

    func engineSession(_: any EnginePageSession, didChangeTitle title: String) {
        guard !title.isEmpty else { return }
        tabPage.title = title
        historyManager.updateEntry(for: tabPage.id, title: title)
    }

    func engineSession(_ session: any EnginePageSession, didChangeFaviconURLs _: [URL]) {
        guard let url = session.url else { return }
        refreshEngineFavicon(for: url, clearingPrevious: false)
    }

    func engineSession(_: any EnginePageSession, didHoverLink url: URL?) {
        onHoveredLinkChanged?(url)
    }

    func engineSession(_: any EnginePageSession, requestsOpening url: URL, disposition: EngineOpenDisposition) {
        switch disposition {
        case .currentTab:
            load(url)
        case .backgroundTab:
            backingNavigationDelegate.navigationDecider.openInNewTab(url: url, activate: false)
        case .foregroundTab, .popup, .newWindow:
            backingNavigationDelegate.navigationDecider.openInNewTab(url: url, activate: true)
        }
    }

    func engineSessionRenderProcessDidTerminate(_: any EnginePageSession) {
        Logger.warning("Chromium renderer terminated for page \(tabPage.id)", category: Logger.engines)
        httpErrorCode = NSURLErrorNetworkConnectionLost
        httpErrorURL = url ?? tabPage.url
    }

    func engineSession(_: any EnginePageSession, destinationForDownloadOf _: URL, suggestedFilename: String) -> URL? {
        let folder = URL.downloadsDirectory
        let sanitized = FilenameUtilities.sanitize(suggestedFilename)
        guard let filename = try? FilenameUtilities.uniqueFilename(for: sanitized, in: folder) else { return nil }
        return folder.appending(path: filename)
    }

    // MARK: Helpers

    /// Fetches the favicon for the engine's current page through the shared favicon cache.
    private func refreshEngineFavicon(for url: URL, clearingPrevious: Bool) {
        if clearingPrevious {
            tabPage.faviconData = nil
        }
        faviconTask?.cancel()
        faviconTask = Task { [weak self, faviconCache] in
            guard let data = await faviconCache.faviconData(for: url, size: .small) else { return }
            guard let self, !Task.isCancelled, self.url?.host == url.host else { return }
            tabPage.faviconData = data
        }
    }

    /// Chromium reports network failures as `net::Error` codes; the error page speaks `NSURLError`.
    private static func urlErrorCode(forChromiumNetError code: Int) -> Int {
        switch code {
        case -105, -137: NSURLErrorCannotFindHost
        case -106: NSURLErrorNotConnectedToInternet
        case -102, -109: NSURLErrorCannotConnectToHost
        case -7, -118: NSURLErrorTimedOut
        case -100, -101: NSURLErrorNetworkConnectionLost
        case -299 ... -200: NSURLErrorServerCertificateUntrusted
        default: NSURLErrorCannotConnectToHost
        }
    }
}
