import AppKit
import Foundation
import WebKit

// MARK: - Navigation Event

extension WebPage {
    /// A particular state that occurs during the progression of a navigation.
    enum NavigationEvent: Hashable, Sendable {
        /// This event occurs when the page receives provisional approval to process a navigation request,
        /// but before it receives a response to that request.
        case startedProvisionalNavigation

        /// This event occurs when the page received a server redirect for a request.
        case receivedServerRedirect

        /// This event occurs when the page has started to receive content for the main frame.
        ///
        /// This happens immediately before the page starts to update the main frame.
        case committed

        /// This event occurs once the navigation is complete.
        case finished
    }

    /// A specific error that caused a navigation to fail.
    enum NavigationError: Error {
        /// An error occurred during the early navigation process.
        case failedProvisionalNavigation(any Error)

        /// The navigation could not begin because the page has been closed.
        case pageClosed

        /// The process for the web content of this page was terminated for any reason.
        case webContentProcessTerminated

        /// The URL to navigate to is invalid.
        case invalidURL
    }
}

// MARK: - Initial Load

extension WebPage {
    /// Performs the initial URL load if it hasn't happened yet.
    ///
    /// Called from the deferred `DispatchQueue.main.async` in init, and also
    /// as a safety net from `onBecameVisible`. This ensures the page loads
    /// even if the first dispatch was dropped (e.g. page created before the
    /// WebView was in a view hierarchy).
    func performInitialLoadIfNeeded() {
        guard initialLoadPending else { return }
        initialLoadPending = false
        load(tabPage.url)
    }
}

// MARK: - Visibility Lifecycle

extension WebPage {
    /// Notifies the session that its content became visible on screen.
    func onBecameVisible() {
        guard visibilityStartTime == nil else { return }
        visibilityStartTime = Date()

        // Safety net: ensure initial load started if the deferred dispatch was dropped
        performInitialLoadIfNeeded()

        if currentHistoryEntry == nil, !tabPage.url.isDeepLink {
            createHistoryEntry(for: tabPage.url, title: tabPage.title)
        }

        // Update badge count baseline to what the user is now seeing
        // This prevents false "unread" triggers when the page goes back to background
        if let tab = tabPage.tab {
            tab.lastBadgeCount = BadgeDetector.detectBadge(in: tabPage.title)
        }

        // Start domain time tracking session
        domainTimeTracker.startSession(for: tabPage.url)
    }

    /// Notifies the session that its content is no longer visible.
    func onBecameHidden() {
        recordTimeSpent()
        visibilityStartTime = nil
        saveScrollPosition()

        // End domain time tracking session
        domainTimeTracker.endCurrentSession()
    }

    /// Notifies the session that it is being terminated.
    func onSessionEnding() {
        historyDebounceTask?.cancel()
        historyDebounceTask = nil

        if let pendingURL = pendingHistoryURL {
            createHistoryEntryImmediately(for: pendingURL, title: tabPage.title)
            pendingHistoryURL = nil
        }

        let timeSpent = calculateVisibilityTime()
        visibilityStartTime = nil

        if currentHistoryEntry != nil {
            historyManager.closeEntry(for: tabPage.id, timeSpent: timeSpent)
            currentHistoryEntry = nil
        }

        // Save scroll position before the session ends (app termination, page eviction)
        saveScrollPosition()

        // End domain time tracking session
        domainTimeTracker.endCurrentSession()

        // Tear down any in-window/windowed fullscreen presentation. Without
        // this, closing a tab whose web view lives in the floating video
        // window leaves that window orphaned on screen.
        inWindowFullscreenController?.pageIsTerminating()

        // Stop all media playback to prevent orphaned audio after tab close.
        // This is a hard stop - the page is being terminated.
        backingWebView._stopAllMediaPlayback()

        // Close the WKWebView to release WebKit process resources.
        // Without this, the WKWebView remains alive with its media session active,
        // which can cause orphaned audio playback and corrupt shared WebKit state.
        backingWebView._close()

        backingWebView.removeFromSuperview()
    }
}

// MARK: - Scroll Position Persistence

extension WebPage {
    /// Saves the current scroll position to the TabPage model for restoration.
    ///
    /// Called when the page becomes hidden or the session is ending. The position
    /// is persisted via SwiftData and restored when the page is loaded again.
    func saveScrollPosition() {
        // Only save for non-blank pages with actual content
        guard !tabPage.url.isBlank else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await backingWebView.callAsyncJavaScript(
                    JavaScriptSnippets.visibleViewport,
                    contentWorld: .page,
                )
                if let dict = result as? [String: Any],
                   let scrollY = dict["scrollY"] as? Double,
                   scrollY > 0 {
                    tabPage.scrollPositionY = scrollY
                }
            } catch {
                // Silently ignore - page may have navigated away or closed
            }
        }
    }

    /// Restores the saved scroll position after page load.
    ///
    /// Called from `handleNavigationFinished()` when `shouldRestoreScrollPosition` is true.
    /// Clears the saved position and flag after restoration to prevent re-applying
    /// on subsequent navigations.
    ///
    /// Uses WebKit's native `setContentOffset` API for reliable scroll restoration.
    func restoreScrollPosition() async {
        guard shouldRestoreScrollPosition,
              let scrollY = tabPage.scrollPositionY,
              scrollY > 0 else {
            shouldRestoreScrollPosition = false
            return
        }

        // Clear the flag and saved position to prevent re-restoration
        shouldRestoreScrollPosition = false
        tabPage.scrollPositionY = nil

        // Use native API for restoration - more reliable than JavaScript
        backingWebView.setContentOffset(x: nil, y: scrollY, animated: false)
    }
}

// MARK: - Loading

extension WebPage {
    private func makeRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        settingsApplier.applyRequestHeaders(to: &request)
        return request
    }

    /// Starts a new navigation, returning the generation for validation.
    ///
    /// Call this at the start of any load operation to:
    /// 1. Cancel the previous load task
    /// 2. Increment the generation counter
    ///
    /// Capture the returned generation and compare against `navigationGeneration`
    /// before processing events to detect stale callbacks.
    private func startNewNavigation() -> UInt64 {
        loadTask?.cancel()
        navigationGeneration &+= 1
        // Clear error state when starting a new navigation
        httpErrorCode = nil
        httpErrorURL = nil
        crashError = nil
        return navigationGeneration
    }

    /// Loads content from the specified URL.
    @discardableResult
    func load(_ url: URL) -> some AsyncSequence<NavigationEvent, any Error> {
        let generation = startNewNavigation()
        updateAutoFillURL(url)

        // WKWebView requires loadFileURL for local file:// URLs (security restriction)
        if url.isFileURL {
            let readAccessURL = url.deletingLastPathComponent()

            loadTask = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await _ in toNavigationSequence({
                        $0.loadFileURL(url, allowingReadAccessTo: readAccessURL)
                    }) {}
                } catch is CancellationError {
                    Logger.debug("Load cancelled: \(url.absoluteString)", category: Logger.navigation)
                } catch {
                    guard generation == navigationGeneration else { return }
                    Logger.error("Load failed for \(url.absoluteString): \(error)", category: Logger.navigation)
                    handleNavigationFailed(error: error)
                }
            }

            return toNavigationSequence { $0.loadFileURL(url, allowingReadAccessTo: readAccessURL) }
        }

        let request = makeRequest(for: url)

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await _ in toNavigationSequence({ $0.load(request) }) {
                    // Events handled by navigationObservationTask
                }
            } catch is CancellationError {
                Logger.debug("Load cancelled: \(url.absoluteString)", category: Logger.navigation)
            } catch {
                // Only process failure if this navigation is still current
                guard generation == navigationGeneration else { return }
                Logger.error("Load failed for \(url.absoluteString): \(error)", category: Logger.navigation)
                handleNavigationFailed(error: error)
            }
        }

        return toNavigationSequence { $0.load(request) }
    }

    /// Loads the web content at the specified URL (optional version).
    @discardableResult
    func load(_ url: URL?) -> AsyncThrowingStream<NavigationEvent, any Error> {
        guard let url else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NavigationError.invalidURL)
            }
        }

        if url.isFileURL {
            let readAccessURL = url.deletingLastPathComponent()
            return toNavigationSequence { $0.loadFileURL(url, allowingReadAccessTo: readAccessURL) }
        }

        let request = makeRequest(for: url)
        return toNavigationSequence { $0.load(request) }
    }

    /// Loads content from the specified URL request.
    @discardableResult
    func load(_ request: URLRequest) -> some AsyncSequence<NavigationEvent, any Error> {
        let generation = startNewNavigation()

        var request = request
        settingsApplier.applyRequestHeaders(to: &request)

        if let url = request.url {
            updateAutoFillURL(url)
        }

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await _ in toNavigationSequence({ $0.load(request) }) {}
            } catch is CancellationError {
                Logger.debug("Load request cancelled", category: Logger.navigation)
            } catch {
                // Only process failure if this navigation is still current
                guard generation == navigationGeneration else { return }
                Logger.error("Load request failed: \(error)", category: Logger.navigation)
                handleNavigationFailed(error: error)
            }
        }

        return toNavigationSequence { $0.load(request) }
    }

    /// Loads the contents of the specified HTML string.
    @discardableResult
    func load(html: String, baseURL: URL = .blank) -> some AsyncSequence<NavigationEvent, any Error> {
        toNavigationSequence { $0.loadHTMLString(html, baseURL: baseURL) }
    }

    /// Loads the content of the specified data object.
    @discardableResult
    func load(
        _ data: Data,
        mimeType: String,
        characterEncoding: String.Encoding,
        baseURL: URL,
    ) -> some AsyncSequence<NavigationEvent, any Error> {
        let cfEncoding = CFStringConvertNSStringEncodingToEncoding(characterEncoding.rawValue)
        guard cfEncoding != kCFStringEncodingInvalidId,
              let convertedEncoding = CFStringConvertEncodingToIANACharSetName(cfEncoding) as? String else {
            preconditionFailure("\(characterEncoding) is not a valid character encoding")
        }

        return toNavigationSequence {
            $0.load(data, mimeType: mimeType, characterEncodingName: convertedEncoding, baseURL: baseURL)
        }
    }

    /// Navigates to an item from the back-forward list.
    @discardableResult
    func load(_ item: BackForwardList.Item) -> some AsyncSequence<NavigationEvent, any Error> {
        toNavigationSequence { $0.go(to: item.wrapped) }
    }

    /// Navigates to a back/forward list item.
    func loadBackForwardItem(_ item: BackForwardList.Item) {
        let generation = startNewNavigation()
        updateAutoFillURL(item.url)

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await _ in load(item) {}
            } catch is CancellationError {
                Logger.debug("Back/forward navigation cancelled", category: Logger.navigation)
            } catch {
                guard generation == navigationGeneration else { return }
                Logger.error("Back/forward navigation failed: \(error)", category: Logger.navigation)
                handleNavigationFailed(error: error)
            }
        }
    }
}

// MARK: - Error Page Loading

extension WebPage {
    /// Loads an error page for an unreachable URL with proper history handling.
    ///
    /// This method uses WebKit's `_loadAlternateHTMLString:baseURL:forUnreachableURL:`
    /// to display a minimal HTML page while recording the failed URL in the back-forward
    /// list. This enables:
    ///
    /// - **Proper history**: The failed URL appears in back/forward navigation
    /// - **Correct reload**: Calling `reload()` retries the original URL
    /// - **URL display**: The address bar can show the failed URL
    ///
    /// The SwiftUI layer observes `httpErrorCode` and `httpErrorURL` to overlay
    /// a native `ErrorPageView` on top of the minimal HTML content.
    ///
    /// - Parameters:
    ///   - code: The HTTP status code of the error (e.g., 404, 500).
    ///   - failedURL: The URL that failed to load.
    func loadAlternateHTMLForError(code: Int, failedURL: URL) {
        // Set error state for SwiftUI observation. Both properties are set
        // immediately so the view layer can show the error page without waiting
        // for WebKit's internal _unreachableURL to be set asynchronously.
        httpErrorCode = code
        httpErrorURL = failedURL

        // Load minimal HTML with the failed URL recorded in WebKit's history.
        // The HTML is intentionally minimal since the SwiftUI ErrorPageView overlays it.
        // Using about:blank as baseURL since we don't need relative resource resolution.
        let minimalHTML = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><title>Error</title></head>
        <body style="background: transparent;"></body>
        </html>
        """

        backingWebView._loadAlternateHTMLString(
            minimalHTML,
            baseURL: URL(string: "about:blank"),
            forUnreachableURL: failedURL,
        )

        Logger.info(
            "Loaded error page for HTTP \(code): \(failedURL.absoluteString)",
            category: Logger.navigation,
        )
    }
}

// MARK: - Navigation

extension WebPage {
    /// Navigates backward in the page history.
    func goBack() {
        guard let backItem = backForwardList.backList.last else { return }
        clearDeepLinkIfNeeded()
        isBackForwardNavigation = true
        loadBackForwardItem(backItem)
    }

    /// Navigates forward in the page history.
    func goForward() {
        guard let forwardItem = backForwardList.forwardList.first else { return }
        isBackForwardNavigation = true
        loadBackForwardItem(forwardItem)
    }

    /// Reloads the current page.
    ///
    /// When showing an HTTP error page (via `_loadAlternateHTMLString`), WebKit's reload
    /// automatically retries the `_unreachableURL` rather than the error page content.
    @discardableResult
    func reload(fromOrigin: Bool = false) -> some AsyncSequence<NavigationEvent, any Error> {
        let generation = startNewNavigation()

        if fromOrigin, let host = url?.host {
            Task {
                await faviconCache.clearFavicon(forHost: host)
            }
            tabPage.faviconData = nil
        }

        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await _ in toNavigationSequence({ fromOrigin ? $0.reloadFromOrigin() : $0.reload() }) {}
            } catch is CancellationError {
                Logger.debug("Reload cancelled", category: Logger.navigation)
            } catch {
                guard generation == navigationGeneration else { return }
                Logger.error("Reload failed: \(error)", category: Logger.navigation)
                handleNavigationFailed(error: error)
            }
        }

        return toNavigationSequence { fromOrigin ? $0.reloadFromOrigin() : $0.reload() }
    }

    /// Reloads the current page bypassing content blockers.
    func reloadWithoutContentBlockers() {
        let generation = startNewNavigation()

        loadTask = Task { [weak self] in
            guard let self else { return }
            // Verify navigation is still current before reloading
            guard generation == navigationGeneration else { return }
            _ = backingWebView._reloadWithoutContentBlockers()
            Logger.debug("Reloading without content blockers", category: Logger.navigation)
        }
    }
}

// MARK: - Content Blocker Bypass

extension WebPage {
    /// Reloads the page without content blockers if we haven't already bypassed for this host.
    func reloadWithoutContentBlockersIfNeeded(for url: URL) {
        guard let host = url.host else { return }
        guard lastContentBlockerBypassHost != host else { return }
        lastContentBlockerBypassHost = host
        reloadWithoutContentBlockers()
    }

    /// Clears any recorded content blocker bypass for the host.
    func clearContentBlockerBypass(for url: URL) {
        guard let host = url.host else { return }
        if lastContentBlockerBypassHost == host {
            lastContentBlockerBypassHost = nil
        }
    }

    /// Stops loading the current page.
    ///
    /// When stopping a provisional navigation on a page with no prior committed
    /// content (e.g., fresh tab navigating to an unreachable host), displays an
    /// error page so the user isn't left staring at a blank page.
    func stopLoading() {
        let wasLoading = backingWebView.isLoading
        let hasErrorPage = httpErrorCode != nil
        let hasCommittedContent = lastCommittedURL != nil

        loadTask?.cancel()
        loadTask = nil
        backingWebView.stopLoading()

        // Show error page only when there's no committed content to fall back to.
        // If the user was on page A and navigating to page B, stopping just keeps
        // page A visible. But if this is a fresh tab with no prior page, stopping
        // would leave a blank page — show the error page instead.
        if wasLoading, !hasErrorPage, !hasCommittedContent {
            let failedURL = backingWebView.url ?? tabPage.url
            if !failedURL.isBlank {
                loadAlternateHTMLForError(code: NSURLErrorCancelled, failedURL: failedURL)
            }
        }
    }
}

// MARK: - WebView Lifecycle

extension WebPage {
    /// Attempts to close the web view gracefully.
    @discardableResult
    func tryClose() -> Bool {
        backingWebView._tryClose()
    }

    /// Whether the web view has been closed.
    var isClosed: Bool {
        backingWebView._isClosed()
    }

    /// Closes the web view immediately and releases resources.
    func closeWebView() {
        backingWebView._close()
    }
}

// MARK: - Session Transfer

extension WebPage {
    /// Transfers this session to manage a different `TabPage`.
    ///
    /// - Parameters:
    ///   - newTabPage: The new TabPage this session should manage.
    ///   - preserveHistory: If `true`, keeps the current history entry open instead of closing it.
    ///     Use this for UI reorganization (e.g., moving to a layout pane) where navigation hasn't changed.
    /// - Returns: The old TabPage ID.
    @discardableResult
    func transferTo(_ newTabPage: TabPage, preserveHistory: Bool = false) -> TabPage.ID {
        let oldID = tabPage.id

        let timeSpent = calculateVisibilityTime()
        visibilityStartTime = nil

        historyDebounceTask?.cancel()
        historyDebounceTask = nil

        if !preserveHistory {
            if let pendingURL = pendingHistoryURL {
                createHistoryEntryImmediately(for: pendingURL, title: tabPage.title)
                pendingHistoryURL = nil
            }

            if currentHistoryEntry != nil {
                historyManager.closeEntry(for: tabPage.id, timeSpent: timeSpent)
                currentHistoryEntry = nil
            }
        }

        tabPage = newTabPage

        if let url {
            newTabPage.url = url
            lastCommittedURL = url
        }
        newTabPage.title = title

        autoFillManager.attach(to: backingWebView, url: newTabPage.url)

        historyDelegateAdapter?.updateTabID(newTabPage.id)

        return oldID
    }
}

// MARK: - Navigation Event Handling

extension WebPage {
    // Adds a navigation event to all active streams.
    //
    // - Important: This method must be called on MainActor as it mutates the
    //   `scopedNavigations` and `indefiniteNavigations` dictionaries.
    
    func addNavigationEvent(_ event: Result<NavigationEvent, any Error>, for cocoaNavigation: WKNavigation?) {
        if let cocoaNavigation {
            scopedNavigations[ObjectIdentifier(cocoaNavigation)]?.yield(with: event)

            if case .success(.finished) = event {
                scopedNavigations[ObjectIdentifier(cocoaNavigation)]?.finish()
            }
        } else {
            for continuation in scopedNavigations.values {
                continuation.yield(with: event)
            }
        }

        // Only propagate SUCCESS events to indefinite streams.
        // Errors are navigation-specific and should only terminate scoped streams.
        // Propagating errors to indefinite streams would terminate the observation task,
        // preventing it from receiving events from subsequent navigations.
        if case let .success(navEvent) = event {
            for continuation in indefiniteNavigations.values {
                continuation.yield(navEvent)
            }
        }
    }
}

// MARK: - Navigation Observation

extension WebPage {
    func startNavigationObservation() {
        navigationObservationTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await event in navigations {
                    await handleNavigationEvent(event)
                }
            } catch is CancellationError {
                // Expected on deinit
            } catch {
                Logger.error("Navigation observation ended with error: \(error)", category: Logger.navigation)
            }
        }
    }

    private func handleNavigationEvent(_ event: NavigationEvent) async {
        switch event {
        case .startedProvisionalNavigation:
            handleNavigationStarted()

        case .receivedServerRedirect:
            handleServerRedirect()

        case .committed:
            handleNavigationCommitted()

        case .finished:
            await handleNavigationFinished()

        @unknown default:
            Logger.warning("Unknown navigation event received", category: Logger.navigation)
        }
    }

    private func handleNavigationStarted() {
        historyDebounceTask?.cancel()
        pendingHistoryURL = nil
    }

    private func handleServerRedirect() {
        historyDebounceTask?.cancel()
        pendingHistoryURL = nil
    }

    private func handleNavigationCommitted() {
        guard let currentItem = backForwardList.currentItem else { return }

        let newURL = currentItem.url
        let urlChanged = lastCommittedURL != newURL
        let previousHost = lastCommittedURL?.host

        let wasBackForward = isBackForwardNavigation
        isBackForwardNavigation = false

        tabPage.url = newURL
        if let title = currentItem.title, !title.isEmpty {
            tabPage.title = title
        }

        if !newURL.isDeepLink {
            deepLinkFlag.deepLinkURL = nil
        }

        updateAutoFillURL(newURL)
        lastCommittedURL = newURL

        if let siteSettingsCoordinator {
            siteSettingsCoordinator.apply(to: self, for: newURL)
        }

        // Create history entries on navigation regardless of visibility.
        // Time tracking is gated separately by HistoryActivityManager.
        if urlChanged, !wasBackForward {
            handleURLChangeForHistory(to: newURL)
        }

        scheduleFaviconExtraction(previousHost: previousHost)
    }

    private func handleNavigationFinished() async {
        if !title.isEmpty {
            tabPage.title = title
            historyManager.updateEntry(for: tabPage.id, title: title)

            // Check for notification badge patterns in title
            if let tab = tabPage.tab, let url {
                siteSettingsCoordinator?.checkBadgeAndMarkUnread(
                    title: title,
                    tab: tab,
                    url: url,
                    isPageVisible: visibilityStartTime != nil,
                )
            }
        } else if let url, url.isFileURL {
            // For local files without <title> (markdown, JSON, plain text, etc.),
            // use the filename as the tab title
            tabPage.title = url.lastPathComponent
        }

        // For local files, set an SF Symbol favicon based on file type
        if let url, url.isFileURL {
            setLocalFileFavicon(for: url)
        }

        // Restore scroll position if this is the initial load after restoration
        await restoreScrollPosition()

        // Detect if this site supports search
        detectSearchEngineIfNeeded()

        resetLocalState()
    }

    // MARK: - Local File Favicon

    /// Sets an SF Symbol favicon for local file URLs based on file type.
    private func setLocalFileFavicon(for url: URL) {
        let symbolName = Self.sfSymbolForFileURL(url)

        Task.detached(priority: .utility) { [weak self] in
            guard let pngData = Self.renderLocalFileFavicon(symbolName: symbolName) else { return }
            await MainActor.run { [weak self] in
                self?.tabPage.faviconData = pngData
            }
        }
    }

    /// Renders an SF Symbol into PNG data for use as a local file favicon.
    private nonisolated static func renderLocalFileFavicon(symbolName: String) -> Data? {
        let size: CGFloat = 64
        let config = NSImage.SymbolConfiguration(pointSize: size * 0.55, weight: .medium)
            .applying(.init(paletteColors: [.secondaryLabelColor]))
        guard let symbolImage = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        else { return nil }

        let symbolSize = symbolImage.size
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
            let origin = NSPoint(
                x: (rect.width - symbolSize.width) / 2,
                y: (rect.height - symbolSize.height) / 2,
            )
            symbolImage.draw(in: NSRect(origin: origin, size: symbolSize))
            return true
        }

        guard let tiffData = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else { return nil }

        return pngData
    }

    /// Returns an appropriate SF Symbol name for a local file URL.
    private static func sfSymbolForFileURL(_ url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "pdf":
            return "doc.richtext"
        case "html", "htm", "xhtml", "webarchive":
            return "globe"
        case "json":
            return "curlybraces"
        case "xml", "plist":
            return "chevron.left.forwardslash.chevron.right"
        case "md", "markdown", "txt", "rtf", "text":
            return "doc.plaintext"
        case "csv", "tsv":
            return "tablecells"
        case "png", "jpg", "jpeg", "gif", "webp", "bmp", "tiff", "tif", "ico", "heic":
            return "photo"
        case "svg":
            return "square.on.circle"
        default:
            return "doc"
        }
    }
}

// MARK: - History Management

extension WebPage {
    func handleURLChangeForHistory(to newURL: URL) {
        if newURL.isDeepLink {
            closeCurrentHistoryEntry()
            // Clear the reference after closing to prevent stale state
            currentHistoryEntry = nil
            return
        }

        closeCurrentHistoryEntry()
        // Capture as parent before clearing - this is intentional since
        // the entry was closed in the history manager, but we want to
        // establish the parent relationship for the new entry
        parentHistoryEntry = currentHistoryEntry
        currentHistoryEntry = nil

        scheduleHistoryEntry(for: newURL)
    }

    private func scheduleHistoryEntry(for url: URL) {
        historyDebounceTask?.cancel()
        pendingHistoryURL = url

        historyDebounceTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await Task.sleep(for: Self.historyDebounceInterval)

                guard let pendingURL = pendingHistoryURL else { return }
                createHistoryEntry(for: pendingURL, title: tabPage.title)
                pendingHistoryURL = nil
            } catch is CancellationError {
                // Debounce cancelled
            } catch {
                Logger.error("History debounce failed: \(error)", category: Logger.data)
            }
        }
    }

    private func createHistoryEntry(for url: URL, title: String?) {
        createHistoryEntryImmediately(for: url, title: title)
    }

    private func createHistoryEntryImmediately(for url: URL, title: String?) {
        let space = tabPage.tab?.space
        currentHistoryEntry = historyManager.recordNavigation(
            url: url,
            title: title,
            tabID: tabPage.id,
            spaceID: space?.id,
            isPrivateSpace: space?.dataStoreMode.isPrivate ?? false,
            parentEntry: parentHistoryEntry,
        )
    }

    private func closeCurrentHistoryEntry() {
        guard currentHistoryEntry != nil else { return }

        let timeSpent = calculateVisibilityTime()
        historyManager.closeEntry(for: tabPage.id, timeSpent: timeSpent)

        if visibilityStartTime != nil {
            visibilityStartTime = Date()
        }
    }

    private func recordTimeSpent() {
        guard currentHistoryEntry != nil else { return }
        let timeSpent = calculateVisibilityTime()
        historyManager.addTimeSpent(for: tabPage.id, duration: timeSpent)
    }

    private func calculateVisibilityTime() -> TimeInterval {
        guard let startTime = visibilityStartTime else { return 0 }
        return Date().timeIntervalSince(startTime)
    }

    private func handleNavigationFailed(error: any Error) {
        // Extract the underlying error for provisional failures
        let underlying: any Error
        let isProvisional: Bool

        if let navError = error as? NavigationError,
           case let .failedProvisionalNavigation(wrapped) = navError {
            underlying = wrapped
            isProvisional = true
        } else {
            underlying = error
            isProvisional = false
        }

        // Show error page for provisional navigation failures
        // (committed navigations already have web content to display)
        if isProvisional {
            let nsError = underlying as NSError
            // Don't show error page for cancellations
            if !(nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) {
                let failedURL = (nsError.userInfo[NSURLErrorFailingURLErrorKey] as? URL) ?? tabPage.url
                loadAlternateHTMLForError(code: nsError.code, failedURL: failedURL)
            }
        }

        // Update history with failure status
        guard currentHistoryEntry != nil else { return }

        let statusCode: Int? = if let urlError = underlying as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost: 0
            case .timedOut: 408
            case .cannotFindHost, .dnsLookupFailed: 404
            case .cannotConnectToHost: 503
            case .secureConnectionFailed, .serverCertificateUntrusted: 495
            default: nil
            }
        } else {
            nil
        }

        historyManager.markEntryFailed(for: tabPage.id, statusCode: statusCode)
    }
}

// MARK: - Favicon Loading

extension WebPage {
    private func scheduleFaviconExtraction(previousHost: String? = nil) {
        faviconTask?.cancel()
        iconLoadingDelegateAdapter.resetForNavigation()

        // Capture navigation generation to detect stale callbacks
        let capturedGeneration = navigationGeneration

        faviconTask = Task { [weak self] in
            guard let self else { return }

            guard let url, let host = url.host else { return }

            // Clear stale favicon if domain changed
            let domainChanged = previousHost != nil && previousHost != host
            if domainChanged {
                tabPage.faviconData = nil
            }

            // Check cache - the IconLoadingDelegateAdapter will handle
            // fetching from WebKit's native icon loading when pages load
            if let cachedData = await faviconCache.cachedFaviconData(forHost: host, size: .small) {
                // Validate navigation hasn't changed before updating
                guard capturedGeneration == navigationGeneration else { return }
                tabPage.faviconData = cachedData
            }
        }
    }
}

// MARK: - Page State

extension WebPage {
    private func resetLocalState() {
        hasUnsavedFormData = false

        if isMediaSuspended {
            isMediaSuspended = false
            backingWebView._resumeAllMediaPlayback()
        }
    }
}

// MARK: - Helpers

extension WebPage {
    private func clearDeepLinkIfNeeded() {
        if deepLinkFlag.isShowingDeepLink {
            deepLinkFlag.deepLinkURL = nil
        }
    }

    private func updateAutoFillURL(_ url: URL) {
        autoFillManager.updateURL(url)
    }

    func createIndefiniteNavigationSequence() -> AsyncThrowingStream<NavigationEvent, any Error> {
        let id = UUID()

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: NavigationEvent.self, throwing: (any Error).self)
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async {
                self.indefiniteNavigations[id] = nil
            }
        }

        indefiniteNavigations[id] = continuation
        return stream
    }

    private func toNavigationSequence(
        _ load: (WKWebView) -> WKNavigation?,
    ) -> AsyncThrowingStream<NavigationEvent, any Error> {
        guard let navigation = load(backingWebView) else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: NavigationError.pageClosed)
            }
        }

        let (stream, continuation) = AsyncThrowingStream.makeStream(of: NavigationEvent.self, throwing: (any Error).self)
        continuation.onTermination = { [weak self] termination in
            guard let self else { return }
            DispatchQueue.main.async {
                if case .cancelled = termination {
                    self.stopLoading()
                }
                self.scopedNavigations[ObjectIdentifier(navigation)] = nil
                self.scopedStreams[ObjectIdentifier(navigation)] = nil
            }
        }

        scopedNavigations[ObjectIdentifier(navigation)] = continuation
        scopedStreams[ObjectIdentifier(navigation)] = stream
        return stream
    }
}

// MARK: - Search Engine Detection

extension WebPage {
    /// Checks if the current page's URL matches a search engine pattern.
    ///
    /// Performs two types of detection:
    /// 1. URL pattern: Checks URL query parameters for search keys
    /// 2. OpenSearch: Looks for `<link rel="search">` and parses the descriptor
    func detectSearchEngineIfNeeded() {
        guard let url else { return }

        // URL pattern detection (synchronous)
        if let detected = SearchEngineDetectionService.detectFromURL(url) {
            notifySearchEngineDetected(detected)
        }

        // OpenSearch detection (async - fire and forget)
        let generation = navigationGeneration
        Task { [weak self] in
            guard let self else { return }
            guard generation == navigationGeneration else { return }
            await detectOpenSearchDescriptor(generation: generation)
        }
    }

    /// Evaluates JavaScript to find OpenSearch link tags and fetches the descriptor.
    private func detectOpenSearchDescriptor(generation: UInt64) async {
        do {
            let js = """
            (function() {
                var link = document.querySelector('link[rel="search"][type="application/opensearchdescription+xml"]');
                return link ? link.href : null;
            })()
            """

            guard let href = try await backingWebView.evaluateJavaScriptWithoutUserGesture(js) as? String,
                  let descriptorURL = URL(string: href)
            else {
                return
            }

            // Verify navigation hasn't changed before making a network request
            guard generation == navigationGeneration else { return }

            let (data, _) = try await URLSession.shared.data(from: descriptorURL)

            guard generation == navigationGeneration,
                  let currentURL = url
            else { return }

            if let detected = SearchEngineDetectionService.parseOpenSearchDescription(data, sourceURL: currentURL) {
                notifySearchEngineDetected(detected)
            }
        } catch {
            // Silently ignore - not all pages have OpenSearch descriptors
        }
    }

    /// Notifies the window state about a detected search engine.
    private func notifySearchEngineDetected(_ detected: DetectedSearchEngine) {
        guard let windowState = backingUIDelegate.pagePool?.windowManager.activeWindowController?.windowState
        else { return }

        // Skip if dismissed this session
        if windowState.dismissedSearchEngineDomains.contains(detected.domain) { return }

        // Skip if the user opted out for this domain
        let searchEngineManager = NSApplication.shared.typedDelegate.customSearchEngineManager
        if searchEngineManager.isDetectionIgnored(forDomain: detected.domain) { return }

        windowState.pendingSearchEngineDetection = detected
    }
}
