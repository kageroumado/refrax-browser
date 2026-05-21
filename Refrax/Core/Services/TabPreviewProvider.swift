import AppKit
import Observation
import OrderedCollections
import WebKit

/// Provides tab thumbnail views for both hover previews and the tab switcher.
///
/// `TabPreviewProvider` is the unified source of truth for tab thumbnails. It uses
/// `ThumbnailAdapter` to efficiently display `_WKThumbnailView` instances, which
/// leverage WebKit's optimized rendering pipeline.
///
/// ## Architecture
///
/// This provider is instantiated per-window and shared between `TabPreviewManager`
/// (hover previews) and `TabSwitcherManager` (Control+Tab thumbnails). It observes
/// tab activations via `WindowState.activeTabID` and pre-caches thumbnails for
/// recently used tabs.
///
/// ## Caching
///
/// The provider maintains a cache of the 5 most recently activated tabs. Thumbnails
/// are created asynchronously after a short delay to avoid work during navigation.
/// When a tab exits layout editing mode, its thumbnail is invalidated and recreated.
///
/// ## Usage
///
/// ```swift
/// // Get thumbnail view for a tab (creates if needed)
/// let thumbnail = previewProvider.thumbnailView(for: tabID)
///
/// // Check if a tab has a cached thumbnail
/// if let cached = previewProvider.preview(for: tabID) {
///     // Use cached thumbnail
/// }
/// ```
///
/// ## Thread Safety
///
/// All APIs must be called on the main actor. `_WKThumbnailView` requires main thread access.
@Observable @MainActor
final class TabPreviewProvider {
    // MARK: - Dependencies

    @ObservationIgnored
    private unowned let tabManager: TabManager

    @ObservationIgnored
    private weak var windowState: WindowState?

    // MARK: - Private State

    /// Cached thumbnail adapters keyed by tab ID, ordered by most recently used.
    ///
    /// Each adapter wraps one or more `_WKThumbnailView` instances depending on
    /// whether the tab has a single page or multiple pages.
    @ObservationIgnored
    private var thumbnailCache: OrderedDictionary<Tab.ID, ThumbnailAdapter> = [:]

    @ObservationIgnored
    private var activationObservationTask: Task<Void, any Error>?

    @ObservationIgnored
    private var layoutModeObservationTask: Task<Void, any Error>?

    @ObservationIgnored
    private var pendingThumbnailTasks: [Tab.ID: Task<Void, any Error>] = [:]

    // MARK: - Constants

    private enum Constants {
        /// Size for thumbnails.
        static let thumbnailSize = CGSize(width: 280, height: 175)

        /// Scale factor for thumbnail rendering (0.25 = 1/4 resolution).
        static let thumbnailScale: CGFloat = 0.25

        /// Delay before creating thumbnail after tab activation.
        /// Allows page to settle after navigation.
        static let captureDelay: Duration = .milliseconds(300)

        /// Maximum number of cached thumbnails.
        static let maxCachedThumbnails = 5
    }

    // MARK: - Initialization

    /// Creates a TabPreviewProvider for a browser window.
    ///
    /// - Parameters:
    ///   - tabManager: The tab manager for page access.
    ///   - windowState: The window state to observe for tab changes.
    init(tabManager: TabManager, windowState: WindowState) {
        self.tabManager = tabManager
        self.windowState = windowState

        startObserving()
    }

    isolated deinit {
        activationObservationTask?.cancel()
        layoutModeObservationTask?.cancel()
        for task in pendingThumbnailTasks.values {
            task.cancel()
        }
    }

    // MARK: - Public API

    /// Returns the thumbnail view for a tab, creating one if needed.
    ///
    /// If a thumbnail exists in the cache, it's returned immediately. Otherwise,
    /// a new thumbnail adapter is created synchronously if the tab has loaded WebPage(s).
    /// For multi-page tabs, returns an adapter that composites multiple thumbnail views.
    /// If the tab has no loaded WebPage, returns an empty placeholder view.
    ///
    /// - Parameters:
    ///   - tabID: The ID of the tab to get a thumbnail for.
    ///   - useCache: Whether to use/update the cache. Pass `false` for one-off previews
    ///               like hover that shouldn't evict MRU entries. Defaults to `true`.
    /// - Returns: The thumbnail adapter view.
    func thumbnailView(for tabID: Tab.ID, useCache: Bool = true) -> ThumbnailAdapter {
        if useCache, let cached = thumbnailCache[tabID] {
            return cached
        }

        // Create synchronously if tab exists
        guard let tab = tabManager.state.tab(for: tabID) else {
            // Return placeholder for deleted tabs
            return makePlaceholderAdapter()
        }

        if useCache {
            return createAndCacheThumbnail(for: tab)
        } else {
            return createThumbnail(for: tab)
        }
    }

    /// Returns the cached thumbnail for a tab, or nil if not cached.
    ///
    /// Unlike `thumbnailView(for:)`, this does not create a new thumbnail.
    func preview(for tabID: Tab.ID) -> ThumbnailAdapter? {
        thumbnailCache[tabID]
    }

    /// Removes entries for tabs that no longer exist.
    func cleanupStaleEntries() {
        thumbnailCache.removeAll { key, _ in
            tabManager.state.tab(for: key) == nil
        }

        // Cancel pending tasks for stale tabs
        for (tabID, task) in pendingThumbnailTasks {
            if tabManager.state.tab(for: tabID) == nil {
                task.cancel()
                pendingThumbnailTasks.removeValue(forKey: tabID)
            }
        }
    }

    // MARK: - Private Methods (Observation)

    /// Starts observing tab activation and layout mode changes.
    private func startObserving() {
        startActivationObservation()
        startLayoutModeObservation()
    }

    /// Observes tab activations to pre-cache thumbnails.
    private func startActivationObservation() {
        let getActiveTabID = { [weak windowState] in windowState?.activeTabID }

        let tabChanges = Observations {
            getActiveTabID()
        }

        activationObservationTask = Task { [weak self] in
            for await activeTabID in tabChanges {
                guard let self, let activeTabID else { continue }
                recordTabActivation(activeTabID)
            }
        }
    }

    /// Observes layout mode changes to update thumbnails when layout editing ends.
    private func startLayoutModeObservation() {
        let getLayoutMode = { [weak windowState] in windowState?.isInLayoutMode }
        let getActiveTabID = { [weak windowState] in windowState?.activeTabID }

        let layoutModeChanges = Observations {
            getLayoutMode()
        }

        layoutModeObservationTask = Task { [weak self] in
            var wasInLayoutMode = false

            for await isInLayoutMode in layoutModeChanges {
                guard let self, let isInLayoutMode else { continue }

                // When exiting layout mode, recreate thumbnail for active tab
                if wasInLayoutMode, !isInLayoutMode {
                    if let activeTabID = getActiveTabID() {
                        invalidateThumbnail(for: activeTabID)
                    }
                }

                wasInLayoutMode = isInLayoutMode
            }
        }
    }

    /// Invalidates and recreates the thumbnail for a tab.
    ///
    /// Called when the tab's layout configuration changes.
    private func invalidateThumbnail(for tabID: Tab.ID) {
        // Remove existing cached thumbnail
        thumbnailCache.removeValue(forKey: tabID)

        // Schedule recreation
        scheduleThumbnailCreation(for: tabID)
    }

    /// Records a tab activation and schedules thumbnail creation.
    private func recordTabActivation(_ tabID: Tab.ID) {
        // Move to front of cache if already present
        if let existing = thumbnailCache.removeValue(forKey: tabID) {
            thumbnailCache.updateValue(existing, forKey: tabID, insertingAt: 0)
        }

        // Trim cache to max size
        while thumbnailCache.count > Constants.maxCachedThumbnails {
            thumbnailCache.removeLast()
        }

        scheduleThumbnailCreation(for: tabID)
    }

    /// Schedules thumbnail creation after a delay.
    private func scheduleThumbnailCreation(for tabID: Tab.ID) {
        // Cancel any existing pending task for this tab
        pendingThumbnailTasks[tabID]?.cancel()

        pendingThumbnailTasks[tabID] = Task { [weak self] in
            do {
                try await Task.sleep(for: Constants.captureDelay)

                guard let self, !Task.isCancelled else { return }

                addThumbnail(for: tabID)
                pendingThumbnailTasks.removeValue(forKey: tabID)
            } catch {
                // Task was cancelled
            }
        }
    }

    /// Creates and caches a thumbnail for the given tab.
    private func addThumbnail(for tabID: Tab.ID) {
        guard let tab = tabManager.state.tab(for: tabID)
        else { return }

        createAndCacheThumbnail(for: tab)
    }

    // MARK: - Private Methods (Thumbnail Creation)

    /// Creates a placeholder adapter for tabs without loaded WebPage.
    private func makePlaceholderAdapter() -> ThumbnailAdapter {
        ThumbnailAdapter(frame: NSRect(origin: .zero, size: Constants.thumbnailSize))
    }

    /// Creates a thumbnail adapter without caching.
    ///
    /// For single-page tabs, creates an adapter with one `_WKThumbnailView`.
    /// For multi-page tabs, creates an adapter compositing multiple thumbnail views.
    private func createThumbnail(for tab: Tab) -> ThumbnailAdapter {
        let adapter = ThumbnailAdapter(frame: NSRect(origin: .zero, size: Constants.thumbnailSize))

        if tab.isMultiPage, let config = tab.layoutConfiguration {
            // Multi-page tab: create thumbnail for each page
            var thumbnailViews: [(view: _WKThumbnailView, position: PanePosition)] = []

            for page in tab.sortedPages {
                guard let webPage = tabManager.pagePool.existingPage(for: page),
                      let position = config.panePositions[page.id]
                else { continue }

                let thumbnailView = makeThumbnailView(for: webPage)
                thumbnailViews.append((thumbnailView, position))
            }

            if !thumbnailViews.isEmpty {
                adapter.configure(with: thumbnailViews, configuration: config)
            }
        } else {
            // Single-page tab
            if let webPage = tabManager.pagePool.existingPage(for: tab.activePage) {
                let thumbnailView = makeThumbnailView(for: webPage)
                adapter.configure(with: thumbnailView)
            }
        }

        return adapter
    }

    /// Creates a thumbnail adapter and adds it to the cache.
    @discardableResult
    private func createAndCacheThumbnail(for tab: Tab) -> ThumbnailAdapter {
        let adapter = createThumbnail(for: tab)

        // Insert at front, maintaining order
        thumbnailCache.updateValue(adapter, forKey: tab.id, insertingAt: 0)

        // Trim cache
        while thumbnailCache.count > Constants.maxCachedThumbnails {
            thumbnailCache.removeLast()
        }

        return adapter
    }

    /// Creates a configured `_WKThumbnailView` for a web page.
    private func makeThumbnailView(for webPage: WebPage) -> _WKThumbnailView {
        let thumbnailView = _WKThumbnailView(frame: .zero, from: webPage.backingWebView)

        thumbnailView.scale = Constants.thumbnailScale
        thumbnailView.maximumSnapshotSize = Constants.thumbnailSize
        // Use snapshot-only mode for caching. With exclusivelyUsesSnapshot = false,
        // the view reparents WKWebView's live layers which disconnect quickly, causing
        // gray views. Snapshot mode captures a static CGImage that persists.
        thumbnailView.exclusivelyUsesSnapshot = true
        thumbnailView.shouldKeepSnapshotWhenRemovedFromSuperview = true

        return thumbnailView
    }
}
