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
    ///
    /// - Throws: ``EngineError/webKitOnlyPage`` for an extension page, which only WebKit can render.
    func switchEngine(to id: EngineID, registry: EngineRegistry) async throws {
        guard id != activeEngineID else { return }
        guard extensionBaseURL == nil else { throw EngineError.webKitOnlyPage }
        let currentURL = url ?? tabPage.url

        if id == .systemWebKit {
            let zoom = enginePage == nil ? nil : state.zoom
            tearDownEnginePage()
            if let zoom {
                backingWebView.pageZoom = zoom
            }
            state.reset(to: WebKitPageObserver.snapshot(of: backingWebView))
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
            state.reset(to: PageSnapshot(url: currentURL, title: tabPage.title))
            enginePage = page
            observe(page)
            page.perform(.setZoom(factor: backingWebView.pageZoom))
        }
        tabPage.engineID = id == .systemWebKit ? nil : id.rawValue
        Logger.info("Page \(tabPage.id) now renders with \(id): \(currentURL.absoluteString)", category: Logger.engines)
    }

    /// Closes the engine page, if any. Called when the page ends or returns to WebKit.
    func tearDownEnginePage() {
        for task in engineTasks {
            task.cancel()
        }
        engineTasks.removeAll()
        // The engine's transfers end with its page.
        for downloadID in engineDownloads.values {
            backingNavigationDelegate.downloadManager?.failEngineDownload(downloadID, reason: "The page closed")
        }
        engineDownloads.removeAll()
        enginePage?.close()
        enginePage = nil
    }

    /// Applies an event from the built-in WebKit view. Ignored while another engine renders
    /// the page: the paused web view's late events must not overwrite that engine's state.
    func receiveWebKitEvent(_ event: PageEvent) {
        guard enginePage == nil else { return }
        state.apply(event)
        applyCommonEffects(event)
    }

    /// Effects every engine's events have alike.
    ///
    /// - Renderer health goes to the pool's watchdog.
    /// - A committed navigation dismisses the questions the previous document asked.
    private func applyCommonEffects(_ event: PageEvent) {
        switch event {
        case let .rendererHealthChanged(health):
            backingNavigationDelegate.pagePool?.handleRendererHealth(for: tabPage.id, health: health)
        case .navigationCommitted:
            prompts.dismissAll()
        default:
            break
        }
    }

    /// Whether the site at `host` may use `kind`: its site setting, or the user's answer.
    func decidePermission(_ kind: PermissionKind, host: String) async -> Bool {
        guard let siteSettingsManager = backingNavigationDelegate.pagePool?.siteSettingsManager else { return false }
        return await PagePermissions(siteSettingsManager: siteSettingsManager).decide(kind, host: host, prompts: prompts)
    }

    /// Terminates the process rendering this page (watchdog action for a hung renderer).
    ///
    /// Returns false when the engine can't terminate its renderer on request.
    @discardableResult
    func terminateRenderer() -> Bool {
        guard let enginePage else {
            backingWebView._killWebContentProcess()
            return true
        }
        guard enginePage.engine.capabilities.contains(.rendererControl) else { return false }
        enginePage.perform(.terminateRenderer)
        return true
    }

    /// Consumes a page's event and request streams for as long as it lives.
    private func observe(_ page: any EnginePage) {
        let events = Task { [weak self] in
            for await event in page.events {
                guard let self, !Task.isCancelled else { return }
                state.apply(event)
                applyCommonEffects(event)
                handleEngineEvent(event)
            }
        }
        let requests = Task { [weak self] in
            for await request in page.requests {
                guard let self, !Task.isCancelled else {
                    request.reply(.cancel)
                    return
                }
                // Answered concurrently: a dialog waiting on the user must not hold up a download.
                Task.immediate(name: "Answer page request") { [weak self] in
                    guard let self else {
                        request.reply(.cancel)
                        return
                    }
                    await request.reply(answer(request.kind))
                }
            }
        }
        let messages = Task { [weak self] in
            for await delivery in page.messages {
                guard let self, !Task.isCancelled, let router = backingNavigationDelegate.pagePool?.state.scriptChannels else {
                    delivery.reply(.error(message: "The page closed"))
                    continue
                }
                router.dispatch(delivery.message, from: self, reply: delivery.reply)
            }
        }
        engineTasks = [events, requests, messages]
    }
}

// MARK: - Event Effects

extension WebPage {
    /// Side effects of engine events on the rest of Refrax. State itself lives in `state`.
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
            if let url = state.url {
                refreshEngineFavicon(for: url, clearingPrevious: false)
            }

        case let .hoveredLinkChanged(url):
            onHoveredLinkChanged?(url)

        case let .downloadProgressed(id, receivedBytes, totalBytes):
            if let downloadID = engineDownloads[id] {
                backingNavigationDelegate.downloadManager?.updateEngineDownload(downloadID, receivedBytes: receivedBytes, totalBytes: totalBytes)
            }

        case let .downloadFinished(id):
            if let downloadID = engineDownloads.removeValue(forKey: id) {
                backingNavigationDelegate.downloadManager?.finishEngineDownload(downloadID)
            }

        case let .downloadFailed(id, reason):
            if let downloadID = engineDownloads.removeValue(forKey: id) {
                backingNavigationDelegate.downloadManager?.failEngineDownload(downloadID, reason: reason)
            }

        case let .fullscreenChanged(state):
            followEngineFullscreen(state)

        case let .notificationShown(notification):
            webNotifications?.show(notification, from: self)

        case let .notificationClosed(id):
            webNotifications?.withdrawEngineNotification(id, from: self)

        default:
            break
        }
    }

    private func engineDidCommit(_ url: URL, isBackForward: Bool) {
        let urlChanged = lastCommittedURL != url
        let previousHost = lastCommittedURL?.host

        tabPage.url = url
        if !state.title.isEmpty {
            tabPage.title = state.title
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
    private func answer(_ request: PageRequestKind) async -> PageRequestAnswer {
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

        case let .download(id, url, suggestedFilename, mimeType, totalBytes):
            // The engine writes the file (only it holds the session); Refrax picks the place,
            // shows progress, and quarantines it when done.
            guard let downloadManager = backingNavigationDelegate.downloadManager else { return .cancel }
            let space = tabPage.tab?.space
            let engine = enginePage
            guard let adopted = downloadManager.adoptEngineDownload(
                sourceURL: url,
                suggestedFilename: suggestedFilename,
                mimeType: mimeType,
                totalBytes: totalBytes,
                originatingURL: self.url,
                originatingTitle: title,
                customDownloadPath: space?.customDownloadPath,
                spaceID: space?.id,
                spaceName: space?.name,
                colorTag: space?.downloadColorTag,
                cancel: { [weak engine] in engine?.perform(.cancelDownload(id: id)) },
            ) else { return .cancel }
            engineDownloads[id] = adopted.id
            return .saveTo(url: adopted.destination)

        case let .permission(.notifications, origin):
            return await requestEngineNotificationPermission(for: origin) ? .allow : .deny

        case let .permission(kind, origin):
            return await decidePermission(kind, host: origin.host() ?? "") ? .allow : .deny

        case let .javaScriptDialog(dialog):
            let origin = dialog.origin?.host() ?? ""
            let question: PageQuestion = switch dialog.kind {
            case .alert: .alert(message: dialog.message, origin: origin)
            case .confirm: .confirm(message: dialog.message, origin: origin)
            case .prompt: .prompt(message: dialog.message, defaultText: dialog.defaultText, origin: origin)
            case .beforeUnload: .leavePage(origin: origin)
            }
            return switch await prompts.ask(question) {
            case .accept, .acceptAndRemember: .confirm(text: nil)
            case let .text(text): .confirm(text: text)
            case .decline, .declineAndRemember: .cancel
            }
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

// MARK: - Engine-Neutral Access

extension WebPage {
    /// The view showing this page's content, whichever engine renders it.
    var contentView: NSView {
        enginePage?.view ?? backingWebView
    }

    /// The built-in WebKit view, for WebKit-only features (link previews, thumbnails,
    /// the extension host, agent perception). Callers check ``activeEngineID`` first:
    /// while another engine renders the page this view is paused and shows stale content.
    var webKitView: WebPageWebView {
        backingWebView
    }

    /// Whether `webView` is this page's WebKit view.
    func owns(_ webView: WKWebView) -> Bool {
        backingWebView === webView
    }

    /// Renders the visible page into an image.
    func snapshot(of rect: CGRect? = nil) async throws -> NSImage {
        if let enginePage {
            let image = try await enginePage.snapshot(of: rect)
            return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
        let configuration = WKSnapshotConfiguration()
        if let rect {
            configuration.rect = rect
        }
        return try await backingWebView.takeSnapshot(configuration: configuration)
    }

    /// Waits until the page's latest changes are on screen.
    func waitForPresentationUpdate() async {
        guard enginePage == nil else { return }
        await backingWebView.waitForPresentationUpdate()
    }

    /// The process rendering the page's content, when the engine exposes it.
    var contentProcessIdentifier: pid_t? {
        guard enginePage == nil else { return nil }
        let pid = backingWebView._webProcessIdentifier
        return pid > 0 ? pid : nil
    }

    /// The GPU process compositing the page, when the engine exposes it.
    var gpuProcessIdentifier: pid_t? {
        guard enginePage == nil else { return nil }
        let pid = backingWebView._gpuProcessIdentifier
        return pid > 0 ? pid : nil
    }

    /// The page's detected language, when the engine reports one.
    var pageLanguage: String? {
        enginePage == nil ? backingWebView._pageLanguage : nil
    }
}

private extension WKWebView {
    /// WebKit's detected page language (private, read through KVC).
    var _pageLanguage: String? {
        value(forKey: "_pageLanguage") as? String
    }
}
