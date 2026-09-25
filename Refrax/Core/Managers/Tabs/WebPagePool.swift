import Foundation
import Observation
import WebKit

/// Manages the pool of active WebPage instances with adaptive memory management.
///
/// `WebPagePool` handles the lifecycle of `WebPage` instances, providing:
/// - Lazy page creation when tabs become visible
/// - Adaptive eviction based on system memory pressure
/// - Importance-based scoring to protect valuable pages
/// - Page transfer for tab moves (preserving WebPage state)
/// - Proper cleanup with history tracking on page end
///
/// ## Memory Management Philosophy
///
/// This pool responds to actual system memory pressure:
/// - **No pressure**: Pages accumulate freely with periodic idle cleanup
/// - **Warning**: Measured eviction with cooldown (purge and wait)
/// - **Critical**: More aggressive eviction, but still protecting important pages
///
/// This prevents premature eviction when RAM is plentiful and avoids cascading
/// evictions during temporary pressure spikes (e.g., Xcode builds).
///
/// ## Page Importance
///
/// Pages are scored based on activity and user value:
/// - Media capture (camera/mic): Protected
/// - Playing audio: Protected
/// - Unsaved form data: High priority
/// - Pinned tabs: Medium-high priority
/// - Recent visibility: Higher score
/// - Time since last access: Decaying bonus
///
/// ## Multi-Window Support
///
/// The pool is shared across all windows. When clearing inactive pages,
/// it protects active tabs in ALL windows via `windowManager.allWindowStates`.
///
/// ## Usage
///
/// ```swift
/// // Get or create page
/// if let page = pagePool.page(for: tabPage) {
///     WebViewContainer(page: page)
/// }
///
/// // Transfer page during tab move (preserves WebPage and scheme handler state)
/// pagePool.transferPage(from: sourcePage, to: targetPage)
/// ```
@Observable
final class WebPagePool {
    // MARK: - Dependencies

    unowned let state: BrowserState

    /// Tab manager for creating new tabs (used by BrowserNavigationDecider).
    ///
    /// Set after initialization to break circular dependency with TabManager.
    unowned var tabManager: TabManager!

    /// Window manager for accessing all window states.
    ///
    /// Used to protect active tabs in all windows during eviction.
    /// Set after initialization.
    unowned var windowManager: WindowManager!

    /// Data store manager for per-space WKWebsiteDataStore instances.
    ///
    /// Used to get the appropriate data store for space-bound tabs.
    /// Set after initialization.
    unowned var spaceDataStoreManager: SpaceDataStoreManager!

    /// Extension manager for dispatching tab events to extensions.
    ///
    /// Provides access to the extension manager through the browser state.
    var extensionManager: ExtensionManager? {
        state.extensionManager
    }

    /// Site settings manager for per-domain permissions.
    ///
    /// Used by WKUIDelegateAdapter to check screen sharing and geolocation permissions.
    var siteSettingsManager: SiteSettingsManager {
        state.siteSettingsManager
    }

    // MARK: - Page Storage

    /// Active web pages keyed by tab page ID.
    ///
    /// Pages are created lazily when tabs become visible and evicted
    /// based on memory pressure and importance scoring.
    ///
    /// Not observed to prevent cascade invalidation when pages are added/removed.
    /// Views access pages via `existingPage(for:)` without triggering observation.
    @ObservationIgnored
    private var _activePages: [TabPage.ID: WebPage] = [:]

    /// Version counter for callers that need to observe structural changes.
    ///
    /// Incremented when pages are added or removed. Use this to observe page
    /// pool changes without triggering re-renders on every dictionary access.
    private(set) var pagesVersion: Int = 0

    /// How many times each tab page's page was replaced while the tab stayed open.
    ///
    /// ``page(for:)`` reads its entry, so a view that got a page from it shows the
    /// replacement: a tab crossing into or out of an extension's pages gets a new web view.
    private var pageReplacements: [TabPage.ID: Int] = [:]

    /// Read-only access to active pages.
    ///
    /// Does not trigger observation - use `pagesVersion` if you need reactive updates.
    var activePages: [TabPage.ID: WebPage] {
        _activePages
    }

    /// Navigation deciders keyed by tab page ID.
    ///
    /// Stored separately to allow SSL bypass approval without exposing
    /// the decider through the page.
    private var navigationDeciders: [TabPage.ID: BrowserNavigationDecider] = [:]

    // MARK: - Configuration

    /// Soft limit for pages under normal conditions.
    ///
    /// Pages beyond this are candidates for idle eviction, but not forced.
    /// This doesn't trigger immediate eviction.
    var softLimit: Int = 25

    /// Maximum time since last visibility before idle eviction (seconds).
    var idleThreshold: TimeInterval = 3_600 // 1 hour

    /// Minimum pages to keep even under critical memory pressure.
    var minimumPages: Int = 3

    // MARK: - Scoring

    private let scorer = PageImportanceScorer()

    // MARK: - Process Termination Handling

    /// Handler for web process terminations and crash recovery.
    ///
    /// Manages automatic reload after crashes, tracks crash frequency to detect
    /// problematic sites, and coordinates user notifications via toast.
    private(set) var terminationHandler = WebProcessTerminationHandler()

    // MARK: - Background Tasks

    @ObservationIgnored
    private var memoryPressureTask: Task<Void, Never>?

    @ObservationIgnored
    private var isMonitoringSetUp = false

    // MARK: - Initialization

    init(state: BrowserState) {
        self.state = state
        state.scriptChannels.pageResolver = { [weak self] webView in
            self?.activePages.values.first { $0.owns(webView) }
        }

        // Configure termination handler with settings
        terminationHandler.configure(with: state.settings)

        setupMemoryPressureHandling()
    }

    /// Completes setup after dependencies are wired.
    ///
    /// Call after setting `tabManager` and `windowManager` to set up the toast presenter
    /// and screen share audio recovery.
    func completeSetup() {
        // Connect toast presenter to route messages to the active window
        terminationHandler.toastPresenter = { [weak self] message in
            self?.windowManager.activeWindowController?.windowState.showToast(message)
        }
    }

    // MARK: - WebKit Warm-up

    /// Task for WebKit warm-up.
    @ObservationIgnored
    private var warmUpTask: Task<Void, Never>?

    /// Warms up WebKit by pre-initializing the WebKit process and GPU context.
    ///
    /// The first WKWebView creation is expensive (~100-300ms) due to:
    /// - WebKit process spawn
    /// - GPU/OpenGL context initialization
    /// - Shader compilation
    ///
    /// Call this after app launch settles (after first frame + deferred setup) to
    /// move this cost away from the first user interaction.
    ///
    /// The warm-up creates a minimal WKWebView with about:blank, waits for
    /// initialization to complete, then releases it. The WebKit process and
    /// GPU context remain warm for subsequent page creations.
    func warmUpWebKit() {
        // Skip if already warming up or if we already have pages
        guard warmUpTask == nil, activePages.isEmpty else { return }

        warmUpTask = Task(priority: .utility) { [weak self] in
            // Small delay to ensure UI is fully settled
            try? await Task.sleep(for: .milliseconds(50))

            guard !Task.isCancelled else { return }

            // Create minimal WKWebView to initialize WebKit
            let config = WKWebViewConfiguration()
            let warmUpView = WKWebView(frame: .zero, configuration: config)

            // Load about:blank to trigger full GPU initialization
            warmUpView.load(URLRequest(url: .blank))

            // Brief wait to ensure initialization completes
            try? await Task.sleep(for: .milliseconds(150))

            // View deallocates here, but WebKit process stays warm
            _ = warmUpView

            self?.warmUpTask = nil
            Logger.debug("WebKit warm-up completed", category: Logger.tabs)
        }
    }

    deinit {
        memoryPressureTask?.cancel()
        warmUpTask?.cancel()
        DispatchQueue.main.async {
            MemoryPressureMonitor.shared.stop()
        }
    }

    // MARK: - Page Access

    /// Installed engines; pages whose tab remembers a non-WebKit engine are restored onto it.
    /// Nil where no engines are available (tests).
    var engineRegistry: EngineRegistry?

    /// Gets or creates a WebPage for a tab page.
    ///
    /// Pages are created lazily. Under memory pressure, low-priority pages
    /// may be evicted to make room.
    ///
    /// - Parameter tabPage: The tab page to get/create a page for.
    /// - Returns: WebPage instance, or `nil` for deep link URLs.
    @discardableResult
    func page(for tabPage: TabPage) -> WebPage? {
        // Deep links render native views
        if tabPage.url.isDeepLink {
            return nil
        }

        // Registers observation of replacements for callers in view bodies.
        _ = pageReplacements[tabPage.id]

        // Return existing page
        if let page = activePages[tabPage.id] {
            return page
        }

        // Under pressure, try to make room first
        let monitor = MemoryPressureMonitor.shared
        if monitor.shouldConserveResources, activePageCount >= minimumPages {
            evictLowPriorityPages(count: 1)
        }

        // Create page
        let tab = tabPage.tab
        if tab == nil {
            Logger.warning("Creating page without parent tab for: \(tabPage.title)", category: Logger.tabs)
        }

        let configuration = configuration(for: tabPage)
        let (page, navigationDecider) = if let extensionContext = extensionManager?.extensionContext(for: tabPage.url) {
            buildExtensionPage(for: tabPage, configuration: configuration, context: extensionContext)
        } else {
            buildPage(for: tabPage, configuration: configuration)
        }

        _activePages[tabPage.id] = page
        navigationDeciders[tabPage.id] = navigationDecider
        pagesVersion += 1

        // Extension pages render only in WebKit, whichever engine the tab remembers.
        if page.extensionBaseURL == nil {
            restoreEngine(for: page)
        }
        return page
    }

    /// Builds a page for one of an extension's own pages, from the configuration WebKit
    /// requires for it: the owning context's, bound to that context's controller.
    ///
    /// A context always has a web view configuration once loaded into a controller, which
    /// ``ExtensionManager/extensionContext(for:)`` guarantees; the ordinary configuration is
    /// the fallback should WebKit ever return none.
    private func buildExtensionPage(
        for tabPage: TabPage,
        configuration: WebPage.Configuration,
        context: WKWebExtensionContext,
    ) -> (WebPage, BrowserNavigationDecider) {
        guard let webViewConfiguration = context.webViewConfiguration else {
            Logger.warning("Extension context has no web view configuration for \(tabPage.url.absoluteString)", category: Logger.extensions)
            return buildPage(for: tabPage, configuration: configuration)
        }
        var configuration = configuration
        configuration.webExtensionController = context.webExtensionController
        return buildPage(
            for: tabPage,
            configuration: configuration,
            webViewConfiguration: webViewConfiguration,
            extensionBaseURL: context.baseURL,
        )
    }

    /// Replaces `page` with a new page for `url` when `url` needs a web view bound to a
    /// different extension, or to none.
    ///
    /// The replacement happens on the next main-queue turn, after the caller has unwound
    /// from `page`'s load or navigation callback. The tab keeps its identity and history
    /// records; the old web view's back-forward list does not carry over.
    ///
    /// - Parameters:
    ///   - page: The page about to load `url`.
    ///   - url: The URL to load.
    /// - Returns: `true` when `page` is being replaced and must not load `url` itself.
    func replaceIfExtensionBoundaryCrossed(_ page: WebPage, toLoad url: URL) -> Bool {
        let targetBaseURL = extensionManager?.extensionContext(for: url)?.baseURL
        guard !ExtensionPageRouting.canNavigate(from: page.extensionBaseURL, to: targetBaseURL) else {
            return false
        }
        let tabPage = page.tabPage
        Logger.info("Moving tab page \(tabPage.id) to a new web view for \(url.absoluteString)", category: Logger.extensions)
        DispatchQueue.main.async { [weak self, weak page] in
            guard let self, let page, _activePages[tabPage.id] === page else { return }
            tabPage.url = url
            removePage(for: tabPage)
            pageReplacements[tabPage.id, default: 0] += 1
            self.page(for: tabPage)
        }
        return true
    }

    /// Moves a page whose tab remembers another engine onto it before WebKit loads anything.
    ///
    /// When that engine is no longer installed, or fails to start, the page loads in WebKit.
    private func restoreEngine(for page: WebPage) {
        guard let rawID = page.tabPage.engineID, let engineRegistry else { return }
        let id = EngineID(rawValue: rawID)
        guard id != .systemWebKit, engineRegistry.descriptor(for: id) != nil else { return }
        page.initialLoadPending = false
        Task { [weak page] in
            guard let page else { return }
            do {
                try await page.switchEngine(to: id, registry: engineRegistry)
            } catch {
                Logger.error("Restoring \(id) for page \(page.tabPage.id) failed: \(error)", category: Logger.engines)
                page.load(page.tabPage.url)
            }
        }
    }

    /// Creates a popup page using the provided WebKit configuration.
    ///
    /// - Parameters:
    ///   - opener: The page requesting the popup.
    ///   - configuration: The WebKit configuration supplied by WebKit.
    ///   - navigationAction: The navigation action associated with the popup.
    ///   - windowFeatures: The popup window features.
    /// - Returns: The created WebPage, or nil if creation fails.
    func createPopupPage(
        opener: WebPage,
        configuration: WKWebViewConfiguration,
        navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures,
    ) -> WebPage? {
        let url = navigationAction.request.url ?? .blank

        let request = PopupRequest(
            openerURL: opener.tabPage.url,
            popupURL: url,
            windowFeatures: windowFeatures,
            openerTabPageID: opener.tabPage.id,
        )
        let relationship = PopupClassifier.classify(request)

        let openerTab = opener.tabPage.tab
        guard let targetSpace = openerTab?.space
            ?? tabManager.activeWindowState?.activeSpace
            ?? state.spaces.first else {
            Logger.warning("Cannot create popup: no target space", category: Logger.navigation)
            return nil
        }

        // WebKit clones the opener's configuration, which is bound to the opener's extension,
        // if any. A popup that leaves the extension opens as an ordinary tab instead; web
        // content cannot open an extension's pages.
        if !url.isBlank {
            let targetBaseURL = extensionManager?.extensionContext(for: url)?.baseURL
            if !ExtensionPageRouting.canNavigate(from: opener.extensionBaseURL, to: targetBaseURL) {
                if opener.extensionBaseURL != nil, targetBaseURL == nil {
                    tabManager.createTab(
                        url: url,
                        in: targetSpace,
                        groupID: relationship == .linked ? openerTab?.groupID : nil,
                        makeActive: true,
                        loadImmediately: true,
                        insertionStrategy: .afterActive,
                    )
                }
                return nil
            }
        }

        let newTab = tabManager.createPopupTab(
            in: targetSpace,
            openerTabPageID: opener.tabPage.id,
            groupID: relationship == .linked ? openerTab?.groupID : nil,
            url: url,
            activate: true,
        )

        let newTabPage = newTab.activePage
        var configurationForPopup = self.configuration(for: newTabPage)
        if opener.extensionBaseURL != nil {
            configurationForPopup.webExtensionController = opener.configuration.webExtensionController
        }

        // Ensure popup uses the correct data store based on space settings.
        // This is critical for proper isolation in private/separate-store spaces.
        // WebKit provides a data store in the configuration, but we may need to
        // override it if the popup's space uses a different data store.
        // An extension's pages keep the data store of the extension's controller.
        let expectedDataStore = configurationForPopup.websiteDataStore
        if opener.extensionBaseURL == nil, configuration.websiteDataStore !== expectedDataStore {
            Logger.info(
                "Overriding popup data store for space isolation",
                category: Logger.navigation,
            )
            configuration.websiteDataStore = expectedDataStore
        }

        let (page, navigationDecider) = buildPage(
            for: newTabPage,
            configuration: configurationForPopup,
            webViewConfiguration: configuration,
            extensionBaseURL: opener.extensionBaseURL,
            loadsTabURL: false,
        )

        page.openerPageID = opener.tabPage.id

        _activePages[newTabPage.id] = page
        navigationDeciders[newTabPage.id] = navigationDecider
        pagesVersion += 1

        Logger.info("Created popup page for: \(url.absoluteString)", category: Logger.navigation)

        return page
    }

    /// Returns existing page without creating one.
    ///
    /// - Parameter tabPage: The tab page to look up.
    /// - Returns: Existing page, or `nil` if none.
    func existingPage(for tabPage: TabPage) -> WebPage? {
        activePages[tabPage.id]
    }

    /// Returns existing page by ID without creating one.
    ///
    /// - Parameter id: The tab page ID to look up.
    /// - Returns: Existing page, or `nil` if none.
    func existingPage(for id: UUID) -> WebPage? {
        activePages[id]
    }

    // MARK: - Page Transfer

    /// Extracts a page from the pool without destroying it.
    ///
    /// Use this to temporarily hold onto a WebPage while its associated TabPage
    /// is being replaced (e.g., when converting a tab to a live favorite).
    /// The page is removed from the pool but not terminated.
    ///
    /// - Parameter tabPage: The tab page whose page to extract.
    /// - Returns: The extracted page, or `nil` if none existed.
    func extractPage(for tabPage: TabPage) -> WebPage? {
        guard let page = _activePages.removeValue(forKey: tabPage.id) else {
            return nil
        }
        navigationDeciders.removeValue(forKey: tabPage.id)
        pagesVersion += 1
        // Note: Don't call onSessionEnding - we're preserving the page
        return page
    }

    /// Associates an existing page with a new TabPage.
    ///
    /// Use this after extracting a page to re-associate it with a different
    /// TabPage (e.g., after creating a new live favorite tab).
    ///
    /// - Parameters:
    ///   - page: The page to associate.
    ///   - tabPage: The new tab page to associate with.
    func associatePage(_ page: WebPage, with tabPage: TabPage) {
        // Transfer termination history
        terminationHandler.transferHistory(from: page.tabPage.id, to: tabPage.id)

        // Update the page's internal TabPage reference
        page.transferTo(tabPage, preserveHistory: true)

        // Add to pool under new ID
        _activePages[tabPage.id] = page
        pagesVersion += 1

        Logger.debug("Associated page with new TabPage: \(tabPage.title)", category: Logger.tabs)
    }

    /// Transfers an existing page to manage a new `TabPage`.
    ///
    /// This is the preferred transfer method as it preserves the entire page,
    /// including the scheme handler's callback reference to the page's `DeepLinkFlag`.
    /// The page is re-keyed in the pool under the new page's ID.
    ///
    /// - Parameters:
    ///   - sourceTabPage: The current tab page whose page to transfer.
    ///   - destinationTabPage: The new tab page the page should manage.
    ///   - preserveHistory: If `true`, keeps the history entry open. Use for UI reorganization
    ///     (e.g., moving to a layout pane) where navigation hasn't changed.
    /// - Returns: The transferred page, or `nil` if no page existed.
    @discardableResult
    func transferPage(
        from sourceTabPage: TabPage,
        to destinationTabPage: TabPage,
        preserveHistory: Bool = false,
    ) -> WebPage? {
        guard let page = _activePages.removeValue(forKey: sourceTabPage.id) else {
            return nil
        }
        navigationDeciders.removeValue(forKey: sourceTabPage.id)

        // Transfer termination history to new page ID
        terminationHandler.transferHistory(from: sourceTabPage.id, to: destinationTabPage.id)

        // Transfer the page to the new TabPage (updates internal state)
        page.transferTo(destinationTabPage, preserveHistory: preserveHistory)

        // Re-key in the pool under the new page's ID
        _activePages[destinationTabPage.id] = page
        pagesVersion += 1

        Logger.debug("Transferred page from \(sourceTabPage.title) to \(destinationTabPage.title)", category: Logger.tabs)

        return page
    }

    // MARK: - Page Removal

    /// Removes and terminates a specific page.
    ///
    /// The page receives `onSessionEnding()` to close its history entry.
    /// Crash history is also cleared for the removed page.
    ///
    /// - Parameter tabPage: The tab page whose page to remove.
    func removePage(for tabPage: TabPage) {
        guard let page = _activePages.removeValue(forKey: tabPage.id) else {
            return
        }
        navigationDeciders.removeValue(forKey: tabPage.id)
        terminationHandler.clearHistory(for: tabPage.id)
        page.onSessionEnding()
        pagesVersion += 1
        Logger.debug("Removed page for: \(tabPage.title)", category: Logger.tabs)
    }

    /// Removes and terminates all pages for a tab.
    ///
    /// Handles multi-page tabs where each page has its own WebPage.
    ///
    /// - Parameter tab: The tab whose pages to remove.
    func removePages(for tab: Tab) {
        for page in tab.pages {
            removePage(for: page)
        }
    }

    // MARK: - SSL Bypass

    /// Approves an SSL certificate bypass for a specific tab.
    ///
    /// This method is called when a user chooses to proceed despite a certificate
    /// error. The bypass is single-use and validated by URL.
    ///
    /// - Parameters:
    ///   - url: The HTTPS URL for which to approve bypass.
    ///   - tabPage: The tab page whose navigation decider should be updated.
    /// - Returns: `true` if the bypass was successfully approved.
    @discardableResult
    func approveSSLBypass(for url: URL, tabPage: TabPage) async -> Bool {
        guard let decider = navigationDeciders[tabPage.id] else {
            Logger.warning("Cannot approve SSL bypass: no decider for tab", category: Logger.navigation)
            return false
        }

        await decider.approveSSLBypass(for: url)
        return true
    }

    // MARK: - Process Termination Handling

    /// Routes a change in a page's renderer health to the watchdog, whichever engine reported it.
    ///
    /// Coordinates crash recovery, hung-renderer termination, and user notification.
    func handleRendererHealth(for pageID: TabPage.ID, health: RendererHealth) {
        guard let page = activePages[pageID] else {
            Logger.warning("Renderer health change for unknown page: \(pageID)", category: Logger.tabs)
            return
        }
        switch health {
        case let .terminated(reason):
            terminationHandler.handleTermination(for: page, reason: reason)
            if reason == .exceededMemoryLimit {
                MemoryPressureMonitor.shared.recordEviction()
            }
        case .unresponsive:
            terminationHandler.handleUnresponsive(for: page)
        case .running:
            terminationHandler.handleResponsive(for: page)
        case .suspended:
            break
        }
    }

    /// Handles WebKit closing a web view (e.g., tryClose timeout or window.close()).
    ///
    /// Called from `WKUIDelegate.webViewDidClose` when WebKit decides to close a page.
    /// This can happen when:
    /// - JavaScript calls `window.close()` on a page it opened
    /// - WebKit's `_tryClose()` IPC times out because the web process is unresponsive
    ///
    /// For the timeout case, the normal tab close flow was blocked, so we force-close
    /// the tab to ensure the UI stays in sync with WebKit's state.
    ///
    /// - Parameter pageID: The tab page ID whose web view was closed.
    func handleWebViewClosed(for pageID: TabPage.ID) {
        guard let page = activePages[pageID] else {
            Logger.debug("WebView closed for unknown page: \(pageID)", category: Logger.tabs)
            return
        }

        guard let tabPage = page.tabPage as TabPage?,
              let tab = tabPage.tab else {
            Logger.warning("WebView closed but no parent tab found", category: Logger.tabs)
            return
        }

        let openerID = page.openerPageID ?? tabPage.openerTabPageID

        Logger.info("WebView force-closed: \(tabPage.title)", category: Logger.tabs)

        // Force-close the tab through TabManager
        tabManager.closeTab(tab)

        if let openerID,
           let openerPage = activePages[openerID],
           let openerTab = openerPage.tabPage.tab,
           let openerSpace = openerTab.space,
           let windowState = tabManager.windowSync.findWindowState(for: openerSpace) ?? tabManager.activeWindowState {
            tabManager.setActiveTab(openerTab, in: windowState)
        }
    }

    /// Clears problematic state for a page after manual user reload.
    ///
    /// Call this when the user manually reloads a page to give it another chance.
    ///
    /// - Parameter pageID: The tab page ID to clear.
    func clearProblematicState(for pageID: TabPage.ID) {
        terminationHandler.clearProblematicState(for: pageID)
    }

    /// Whether a page is in problematic state (exceeded crash threshold).
    ///
    /// - Parameter pageID: The tab page ID to check.
    /// - Returns: `true` if the page has crashed too many times recently.
    func isProblematic(_ pageID: TabPage.ID) -> Bool {
        terminationHandler.isProblematic(pageID)
    }

    /// Connects a toast presenter for crash recovery notifications.
    ///
    /// - Parameter presenter: Closure that displays a toast message.
    func setToastPresenter(_ presenter: @escaping (String) -> Void) {
        terminationHandler.toastPresenter = presenter
    }

    // MARK: - Page Cleanup

    /// Terminates all active pages.
    ///
    /// Call during app termination to close all history entries properly.
    func removeAllPages() {
        let count = _activePages.count
        for page in _activePages.values {
            page.onSessionEnding()
        }
        _activePages.removeAll()
        navigationDeciders.removeAll()
        pagesVersion += 1
        Logger.info("Removed all \(count) pages", category: Logger.tabs)
    }

    // MARK: - Adaptive Memory Management

    /// Evicts low-priority pages based on importance scoring.
    ///
    /// Pages are scored by activity level and user value. Protected pages
    /// (media capture, audio playback) are never evicted.
    ///
    /// - Parameter count: Maximum number of pages to evict.
    /// - Returns: Number of pages actually evicted.
    @discardableResult
    func evictLowPriorityPages(count: Int) -> Int {
        guard count > 0, activePageCount > minimumPages else { return 0 }

        // Score all pages (synchronous - uses cached state)
        let scoredPages = scorer.scoreAll(pages: activePages.values)

        // Filter out protected pages and sort by score (lowest first)
        let evictable = scoredPages
            .filter { !$0.isProtected }
            .sorted { $0.score < $1.score }

        // Calculate how many we can actually evict
        let maxToEvict = min(count, activePageCount - minimumPages)
        let toEvict = evictable.prefix(maxToEvict)

        // Perform eviction
        var evictedCount = 0
        for scored in toEvict {
            let page = scored.page
            page.onSessionEnding()
            _activePages.removeValue(forKey: page.tabPage.id)
            navigationDeciders.removeValue(forKey: page.tabPage.id)
            evictedCount += 1

            Logger.info(
                "Evicted '\(page.tabPage.title)' (score: \(scored.score), factors: \(scored.factors))",
                category: Logger.tabs,
            )
        }

        if evictedCount > 0 {
            pagesVersion += 1
            MemoryPressureMonitor.shared.recordEviction()
        }

        return evictedCount
    }

    /// Clears all inactive pages to free memory.
    ///
    /// Protects active tabs across ALL windows, not just the key window.
    /// Each window's active tab and active reference tab are preserved.
    /// Also cleans up associated navigation deciders and termination history.
    ///
    /// - Parameter protectedTabs: Optional tabs to protect from eviction.
    ///   If nil, automatically protects active tabs in all windows.
    func clearInactivePages(protecting protectedTabs: [Tab]? = nil) {
        var protectedPageIDs: Set<UUID> = []

        if let protectedTabs {
            for tab in protectedTabs {
                protectedPageIDs.formUnion(tab.pages.map(\.id))
            }
        } else {
            for windowState in windowManager.allWindowStates {
                if let activeTab = windowState.activeTab {
                    protectedPageIDs.formUnion(activeTab.pages.map(\.id))
                }

                if let activeRefTab = windowState.activeReferenceTab {
                    protectedPageIDs.formUnion(activeRefTab.pages.map(\.id))
                }
            }
        }

        let hadInactive = _activePages.count > protectedPageIDs.count
        for (pageID, page) in _activePages where !protectedPageIDs.contains(pageID) {
            page.onSessionEnding()
            navigationDeciders.removeValue(forKey: pageID)
            terminationHandler.clearHistory(for: pageID)
        }

        _activePages = _activePages.filter { protectedPageIDs.contains($0.key) }
        if hadInactive {
            pagesVersion += 1
        }
        Logger.info("Cleared inactive pages, kept \(protectedPageIDs.count) protected pages", category: Logger.tabs)
    }

    /// Handles memory warning by aggressively clearing low-priority pages.
    func handleMemoryWarning() {
        // Try scored eviction first (synchronous)
        let evicted = evictLowPriorityPages(count: 5)

        if evicted == 0 {
            // Fallback to clearing inactive if scoring didn't help
            clearInactivePages()
        }

        Logger.fault("Handled memory warning - evicted \(evicted) pages", category: Logger.tabs)
    }

    // MARK: - Private Setup

    /// Sets up memory pressure monitoring and response.
    private func setupMemoryPressureHandling() {
        guard !isMonitoringSetUp else { return }
        isMonitoringSetUp = true

        let monitor = MemoryPressureMonitor.shared
        monitor.start()

        let pressureLevelChanges = Observations { MemoryPressureMonitor.shared.pressureLevel }
        memoryPressureTask = Task { [weak self] in
            for await pressureLevel in pressureLevelChanges {
                guard let self, !Task.isCancelled else { break }
                handlePressureChange(pressureLevel)
            }
        }
    }

    /// Responds to memory pressure level changes.
    private func handlePressureChange(_ level: MemoryPressureMonitor.PressureLevel) {
        let monitor = MemoryPressureMonitor.shared

        // Skip if in cooldown (purge and wait strategy)
        guard !monitor.isInEvictionCooldown else {
            Logger.debug("Skipping eviction - in cooldown", category: Logger.tabs)
            return
        }

        // Skip if too few pages - eviction has minimal benefit
        guard activePageCount >= MemoryPressureMonitor.minimumPagesForEviction else {
            Logger.debug(
                "Skipping eviction - only \(activePageCount) pages (minimum: \(MemoryPressureMonitor.minimumPagesForEviction))",
                category: Logger.tabs,
            )
            return
        }

        let evictionCount = monitor.suggestedEvictionCount
        guard evictionCount > 0 else { return }

        // Get minimum age threshold for current pressure level
        guard let minimumAge = monitor.minimumEvictableAge else { return }

        Logger.info(
            "Memory pressure \(level): attempting to evict \(evictionCount) pages older than \(minimumAge / 3_600)h",
            category: Logger.tabs,
        )

        let evicted = evictPagesForPressure(count: evictionCount, minimumAge: minimumAge)

        Logger.info(
            "Evicted \(evicted)/\(evictionCount) pages (remaining: \(activePageCount))",
            category: Logger.tabs,
        )
    }

    /// Evicts pages that meet both age and importance criteria.
    ///
    /// Only considers pages that haven't been accessed within `minimumAge` seconds.
    /// This prevents evicting recently opened tabs during temporary memory pressure.
    ///
    /// - Parameters:
    ///   - count: Maximum number of pages to evict.
    ///   - minimumAge: Minimum time since last access for a page to be evictable.
    /// - Returns: Number of pages actually evicted.
    @discardableResult
    private func evictPagesForPressure(count: Int, minimumAge: TimeInterval) -> Int {
        guard count > 0, activePageCount > minimumPages else { return 0 }

        let now = Date()

        // Filter to pages that are old enough to evict
        let eligiblePages = activePages.values.filter { page in
            guard let tab = page.tabPage.tab,
                  let lastAccessed = tab.lastAccessed else {
                // Never-accessed pages are eligible
                return true
            }
            return now.timeIntervalSince(lastAccessed) >= minimumAge
        }

        guard !eligiblePages.isEmpty else {
            Logger.debug(
                "No pages old enough to evict (minimum age: \(minimumAge / 3_600)h)",
                category: Logger.tabs,
            )
            return 0
        }

        // Score eligible pages
        let scoredPages = scorer.scoreAll(pages: eligiblePages)

        // Filter out protected pages and sort by score (lowest first)
        let evictable = scoredPages
            .filter { !$0.isProtected }
            .sorted { $0.score < $1.score }

        // Calculate how many we can actually evict
        let maxToEvict = min(count, activePageCount - minimumPages)
        let toEvict = evictable.prefix(maxToEvict)

        // Perform eviction
        var evictedCount = 0
        for scored in toEvict {
            let page = scored.page
            page.onSessionEnding()
            _activePages.removeValue(forKey: page.tabPage.id)
            navigationDeciders.removeValue(forKey: page.tabPage.id)
            evictedCount += 1

            Logger.info(
                "Evicted '\(page.tabPage.title)' (score: \(scored.score), factors: \(scored.factors))",
                category: Logger.tabs,
            )
        }

        if evictedCount > 0 {
            pagesVersion += 1
            MemoryPressureMonitor.shared.recordEviction()
        }

        return evictedCount
    }

    // MARK: - Scheduled Idle Eviction

    /// Evicts pages that have been idle longer than threshold.
    ///
    /// This method is designed to be called from `ScheduledTasksManager` on an hourly
    /// schedule. It only runs when over the soft limit and not under memory pressure,
    /// evicting truly idle low-value pages to keep the pool healthy.
    ///
    /// Idle eviction is conservative—it only removes pages that haven't been visible
    /// for over an hour and have low importance scores.
    func evictIdlePages() {
        // Only run when over soft limit and not under pressure
        let monitor = MemoryPressureMonitor.shared
        if activePageCount <= softLimit || monitor.pressureLevel != .normal {
            return
        }

        let now = Date()
        var idlePages: [WebPage] = []

        for page in activePages.values {
            guard let tab = page.tabPage.tab else { continue }

            // Never-accessed tabs are always considered idle
            guard let lastVisible = tab.lastAccessed else {
                idlePages.append(page)
                continue
            }
            if now.timeIntervalSince(lastVisible) > idleThreshold {
                idlePages.append(page)
            }
        }

        guard !idlePages.isEmpty else { return }

        // Score and evict only truly low-value idle pages (synchronous)
        let scored = scorer.scoreAll(pages: idlePages)
        let toEvict = scored
            .filter { !$0.isProtected && $0.score < 200 } // Truly low value
            .sorted { $0.score < $1.score }
            .prefix(2) // Max 2 per cycle

        var evictedAny = false
        for scored in toEvict {
            let page = scored.page
            page.onSessionEnding()
            _activePages.removeValue(forKey: page.tabPage.id)
            navigationDeciders.removeValue(forKey: page.tabPage.id)
            evictedAny = true

            Logger.debug(
                "Idle eviction: '\(page.tabPage.title)' (score: \(scored.score))",
                category: Logger.tabs,
            )
        }
        if evictedAny {
            pagesVersion += 1
        }
    }

    // MARK: - Private Helpers

    /// Estimates the expected frame size for a new webView based on the window layout.
    ///
    /// Uses the NSSplitView structure to determine the content area size, then adjusts
    /// for multi-page layouts based on the tab's layout configuration. The estimate is
    /// intentionally slightly larger than the actual pane size because:
    /// - WebKit reflowing to a slightly smaller frame (what actually happens) is cheap
    /// - The exact frame is set by the adapter within the same run loop
    private func estimateExpectedFrame(for tabPage: TabPage) -> CGRect {
        let fallback = CGRect(x: 0, y: 0, width: 1_024, height: 768)

        guard let windowController = windowManager?.activeWindowController,
              let splitVC = windowController.contentViewController as? RefraxSplitViewController,
              splitVC.splitViewItems.count > 1 else {
            return fallback
        }

        // Get the main content area frame (splitViewItems[1] is the content, [0] is sidebar)
        let contentFrame = splitVC.splitViewItems[1].viewController.view.frame
        guard contentFrame.width > 0, contentFrame.height > 0 else {
            return fallback
        }

        // Calculate leading padding based on sidebar state
        // This mirrors MainContentView.leadingPadding logic
        let windowState = windowController.windowState
        let leadingPadding: CGFloat = if windowState.effectiveSidebarMode == .compact, windowState.isSidebarCollapsed {
            // Compact mode with collapsed sidebar
            55
        } else if windowState.isSidebarCollapsed {
            // Regular collapsed sidebar
            0
        } else {
            // Expanded sidebar
            8
        }

        // Available content width after padding
        let availableWidth = contentFrame.width - leadingPadding
        let availableHeight = contentFrame.height

        let tab = tabPage.tab
        let pageCount = tab?.pages.count ?? 1

        if pageCount <= 1 {
            return CGRect(x: 0, y: 0, width: availableWidth, height: availableHeight)
        }

        guard let config = tab?.layoutConfiguration else {
            return CGRect(x: 0, y: 0, width: availableWidth, height: availableHeight)
        }

        let hDivider = CGFloat(config.horizontalDivider)
        let vDivider = CGFloat(config.verticalDivider)

        switch config.layoutType {
        case .single:
            return CGRect(x: 0, y: 0, width: availableWidth, height: availableHeight)

        case .split:
            // Determine if horizontal or vertical split from pane positions
            let positions = Set(config.panePositions.values)
            let isHorizontalSplit = (positions.contains(.topLeft) && positions.contains(.topRight))
                || (positions.contains(.bottomLeft) && positions.contains(.bottomRight))
                || (positions.contains(.topLeft) && positions.contains(.bottomRight))
                || (positions.contains(.topRight) && positions.contains(.bottomLeft))
            if isHorizontalSplit {
                return CGRect(x: 0, y: 0, width: availableWidth * hDivider, height: availableHeight)
            } else {
                return CGRect(x: 0, y: 0, width: availableWidth, height: availableHeight * vDivider)
            }

        case .triple:
            return CGRect(x: 0, y: 0, width: availableWidth * hDivider, height: availableHeight * vDivider)

        case .quad:
            return CGRect(x: 0, y: 0, width: availableWidth * hDivider, height: availableHeight * vDivider)
        }
    }

    /// Builds a WebPage and navigation decider for a tab page.
    private func buildPage(
        for tabPage: TabPage,
        configuration: WebPage.Configuration,
        webViewConfiguration: WKWebViewConfiguration? = nil,
        extensionBaseURL: URL? = nil,
        loadsTabURL: Bool = true,
    ) -> (WebPage, BrowserNavigationDecider) {
        let tab = tabPage.tab

        let dialogPresenter = BrowserDialogPresenter(
            dialogState: state.dialogState,
        )

        let navigationDecider = BrowserNavigationDecider(
            tabManager: tabManager,
            downloadManager: state.downloadManager,
            tabPage: tabPage,
            tab: tab,
            settings: state.settings,
            siteSettingsCoordinator: state.siteSettingsCoordinator,
            dialogPresenter: dialogPresenter,
        )

        let dependencies = WebPage.Dependencies(
            historyManager: state.historyManager,
            autoFillManager: state.autoFillManager,
            faviconCache: state.faviconCache,
            settingsApplier: state.settingsApplier,
            siteSettingsCoordinator: state.siteSettingsCoordinator,
            domainTimeTracker: state.domainTimeTracker,
            downloadManager: state.downloadManager,
            webInspectorManager: state.webInspectorManager,
            pagePool: self,
            navigationDecider: navigationDecider,
            dialogPresenter: dialogPresenter,
        )

        let expectedFrame = estimateExpectedFrame(for: tabPage)

        let page = WebPage(
            tabPage: tabPage,
            configuration: configuration,
            webViewConfiguration: webViewConfiguration,
            extensionBaseURL: extensionBaseURL,
            loadsTabURL: loadsTabURL,
            expectedFrame: expectedFrame,
            dependencies: dependencies,
        )

        // Install link preview manager for Shift+Click support
        if state.settings.shiftClickLinkPreviewEnabled {
            page.webKitView.linkPreviewManager = LinkPreviewManager(webView: page.webKitView)
        }

        return (page, navigationDecider)
    }

    /// Returns the appropriate WebPage configuration for a tab page.
    ///
    /// Live favorite tabs always use the global data store to maintain consistent
    /// sessions across spaces. Space-bound tabs use the space's data store if
    /// the space has `usesSeparateDataStore` enabled, and the matching extension controller.
    private func configuration(for tabPage: TabPage) -> WebPage.Configuration {
        var config = state.webPageConfiguration
        let url = tabPage.url
        let policy = state.siteSettingsCoordinator.autoPlayPolicy(for: url)
        config.mediaTypesRequiringUserActionForPlayback = policy.requiredUserActionMediaTypes
        if let tab = tabPage.tab {
            config.websiteDataStore = state.settingsApplier.dataStore(
                for: tab,
                spaceProvider: state.space(for:),
                spaceDataStoreManager: spaceDataStoreManager,
            )
            // Extensions run with the same isolation as the data store: a private space
            // gets only private-mode extensions, a separate space its own extension storage.
            if let extensionManager {
                config.webExtensionController = extensionManager.controller(for: tab)
            }
        } else {
            Logger.warning("Applying default data store: TabPage has no parent Tab", category: Logger.tabs)
            config.websiteDataStore = state.settingsApplier.defaultDataStore()
        }
        return config
    }

    // MARK: - Statistics

    /// Number of active pages.
    var activePageCount: Int {
        activePages.count
    }

    // MARK: - Diagnostics

    /// Returns diagnostic information about pool state.
    func diagnostics() -> PoolDiagnostics {
        let scored = scorer.scoreAll(pages: activePages.values)
        let monitor = MemoryPressureMonitor.shared

        return PoolDiagnostics(
            activeCount: activePageCount,
            softLimit: softLimit,
            minimumPages: minimumPages,
            pressureLevel: monitor.pressureLevel,
            isLowPowerMode: monitor.isLowPowerModeEnabled,
            thermalState: monitor.thermalState,
            scoredPages: scored.map { ($0.page.tabPage.title, $0.score, $0.factors) },
        )
    }

    /// Diagnostic information about pool state.
    struct PoolDiagnostics: CustomStringConvertible {
        let activeCount: Int
        let softLimit: Int
        let minimumPages: Int
        let pressureLevel: MemoryPressureMonitor.PressureLevel
        let isLowPowerMode: Bool
        let thermalState: ProcessInfo.ThermalState
        let scoredPages: [(title: String, score: Int, factors: [String])]

        var description: String {
            var lines = [
                "WebPagePool Diagnostics:",
                "  Active: \(activeCount) (soft: \(softLimit), min: \(minimumPages))",
                "  Pressure: \(pressureLevel), LowPower: \(isLowPowerMode), Thermal: \(thermalState)",
                "  Pages by score:",
            ]

            for (title, score, factors) in scoredPages.sorted(by: { $0.score > $1.score }) {
                let truncated = String(title.prefix(30))
                lines.append("    [\(score)] \(truncated): \(factors.joined(separator: ", "))")
            }

            return lines.joined(separator: "\n")
        }
    }
}

// MARK: - Calm Page

extension WebPagePool {
    /// Applies or removes the "Calm This Page" animation freeze on every live
    /// page whose host matches `host`. Persistence lives in
    /// `SiteSettingsManager.toggleCalmPage(for:)`; navigations re-apply via
    /// `SiteSettingsCoordinator`.
    func applyCalm(_ calmed: Bool, toHost host: String) {
        let script = calmed ? CalmPageScript.applyScript : CalmPageScript.removeScript
        for webPage in activePages.values where webPage.url?.host?.lowercased() == host.lowercased() {
            Task { _ = try? await webPage.evaluateJavaScript(script) }
        }
    }
}
