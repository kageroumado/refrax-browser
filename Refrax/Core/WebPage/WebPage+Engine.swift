import AppKit
import WebKit

// MARK: - Engine Switching

extension WebPage {
    /// The engine currently rendering this page.
    var activeEngineID: EngineID {
        enginePage?.engine.id ?? .systemWebKit
    }

    /// Moves the page's content to another engine and loads the current URL there.
    ///
    /// The tab, its history entries, and the chrome stay put; only the content
    /// view and the source of page state change. WebKit's view is kept, paused,
    /// while another engine renders the page, so switching back reuses it.
    func switchEngine(to id: EngineID, registry: EngineRegistry) async throws {
        guard id != activeEngineID else { return }
        let currentURL = url ?? tabPage.url

        if id == .systemWebKit {
            let zoom = enginePage == nil ? nil : engineState.zoom
            tearDownEnginePage()
            if let zoom { backingWebView.pageZoom = zoom }
            load(currentURL)
        } else {
            let host = try await registry.host(for: id)
            let page = try host.makePage(EnginePageSpec(
                id: EnginePageID(),
                profile: EngineProfileSpec(space: tabPage.tab?.space),
                initialURL: currentURL.isBlank ? nil : currentURL,
                opener: nil,
            ))
            tearDownEnginePage()
            backingWebView.stopLoading()
            await backingWebView.pauseAllMediaPlayback()
            httpErrorCode = nil
            httpErrorURL = nil
            crashError = nil
            engineState.reset(to: PageSnapshot(url: currentURL, title: tabPage.title))
            enginePage = page
            observe(page)
            page.perform(.setZoom(factor: backingWebView.pageZoom))
        }
        Logger.info("Page \(tabPage.id) now renders with \(id): \(currentURL.absoluteString)", category: Logger.engines)
    }

    /// Closes the engine page, if any. Called when the page ends or returns to WebKit.
    func tearDownEnginePage() {
        for task in engineTasks {
            task.cancel()
        }
        engineTasks.removeAll()
        enginePage?.close()
        enginePage = nil
    }

    /// Consumes a page's event and request streams for as long as it lives.
    private func observe(_ page: any EnginePage) {
        let events = Task { [weak self] in
            for await event in page.events {
                guard let self, !Task.isCancelled else { return }
                engineState.apply(event)
                handleEngineEvent(event)
            }
        }
        let requests = Task { [weak self] in
            for await request in page.requests {
                guard let self, !Task.isCancelled else {
                    request.reply(.cancel)
                    return
                }
                request.reply(answer(request.kind))
            }
        }
        engineTasks = [events, requests]
    }
}

// MARK: - Event Effects

extension WebPage {
    /// Side effects of engine events on the rest of Refrax. State itself lives in `engineState`.
    private func handleEngineEvent(_ event: PageEvent) {
        switch event {
        case let .navigationCommitted(url, isBackForward):
            engineDidCommit(url, isBackForward: isBackForward)

        case let .titleChanged(title) where !title.isEmpty:
            tabPage.title = title
            historyManager.updateEntry(for: tabPage.id, title: title)

        case let .navigationFinished(_, statusCode):
            if let statusCode, statusCode >= 400, currentHistoryEntry != nil {
                historyManager.markEntryFailed(for: tabPage.id, statusCode: statusCode)
            }

        case let .navigationFailed(failure) where failure.isProvisional && failure.kind != .cancelled:
            Logger.warning("\(activeEngineID) navigation failed (\(failure.engineCode) \(failure.description))", category: Logger.engines)
            httpErrorCode = failure.urlErrorCode
            httpErrorURL = failure.url ?? tabPage.url
            if currentHistoryEntry != nil {
                historyManager.markEntryFailed(for: tabPage.id, statusCode: nil)
            }

        case .faviconsChanged:
            if let url = engineState.url {
                refreshEngineFavicon(for: url, clearingPrevious: false)
            }

        case let .hoveredLinkChanged(url):
            onHoveredLinkChanged?(url)

        case let .fullscreenChanged(state):
            followEngineFullscreen(state)

        case let .rendererHealthChanged(.terminated(reason)):
            Logger.warning("\(activeEngineID) renderer terminated (\(reason.rawValue)) for page \(tabPage.id)", category: Logger.engines)
            httpErrorCode = NSURLErrorNetworkConnectionLost
            httpErrorURL = engineState.url ?? tabPage.url

        default:
            break
        }
    }

    private func engineDidCommit(_ url: URL, isBackForward: Bool) {
        let urlChanged = lastCommittedURL != url
        let previousHost = lastCommittedURL?.host

        tabPage.url = url
        if !engineState.title.isEmpty {
            tabPage.title = engineState.title
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

    /// Element fullscreen in an engine view fills the view, so the window follows the page.
    private func followEngineFullscreen(_ state: PageFullscreen) {
        guard let window = enginePage?.view.window else { return }
        let wantsFullscreen = state == .entering || state == .active
        if window.styleMask.contains(.fullScreen) != wantsFullscreen {
            window.toggleFullScreen(nil)
        }
    }

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
}

// MARK: - Requests

extension WebPage {
    /// Answers a decision the engine is waiting on.
    ///
    /// Permission and dialog requests are denied: the permission broker and dialog
    /// presenter are WebKit-only until they speak the contract.
    private func answer(_ request: PageRequestKind) -> PageRequestAnswer {
        switch request {
        case let .openURL(url, disposition, _):
            let decider = backingNavigationDelegate.navigationDecider
            switch disposition {
            case .currentTab:
                load(url)
            case .backgroundTab:
                decider.openInNewTab(url: url, activate: false)
            case .foregroundTab, .popup, .newWindow:
                decider.openInNewTab(url: url, activate: true)
            }
            return .handled

        case let .download(_, suggestedFilename, _):
            let folder = URL.downloadsDirectory
            let sanitized = FilenameUtilities.sanitize(suggestedFilename)
            guard let filename = try? FilenameUtilities.uniqueFilename(for: sanitized, in: folder) else { return .cancel }
            return .saveTo(url: folder.appending(path: filename))

        case .permission:
            return .deny

        case .javaScriptDialog:
            return .cancel
        }
    }
}

// MARK: - Profiles

extension EngineProfileSpec {
    /// The storage partition matching a space's data store, so a space's pages
    /// share storage with each other and never with another isolated space.
    init(space: Space?) {
        switch (space?.dataStoreMode, space?.id) {
        case let (.separate?, id?):
            self = .isolated(id: id)
        case let (.private?, id?):
            self = .ephemeral(id: id)
        default:
            self = .shared
        }
    }
}
