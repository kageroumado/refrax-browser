import AppKit
import Observation
import OrderedCollections
import SwiftUI

/// Manages the Control+Tab switcher for quick tab navigation.
///
/// `TabSwitcherManager` maintains a list of recently used tabs and coordinates
/// the tab switcher overlay UI. It tracks the last 5 activated tabs, ordered by
/// most recently used first.
///
/// ## Architecture
///
/// This manager is instantiated per-window and injected via `RefraxEnvironment`.
/// It observes tab activations through `WindowState` and maintains a bounded
/// history of recently used tabs.
///
/// Thumbnail caching is delegated to `TabPreviewProvider`, which is shared
/// with `TabPreviewManager` for hover previews.
///
/// ## Usage Flow
///
/// 1. User presses Control+Tab → `show()` called, selects previous tab
/// 2. While Control held, Tab/Shift+Tab cycles selection
/// 3. User releases Control → `dismiss()` activates selected tab
@Observable
final class TabSwitcherManager {
    // MARK: - Dependencies

    @ObservationIgnored
    private unowned let tabManager: TabManager

    @ObservationIgnored
    private unowned let windowState: WindowState

    @ObservationIgnored
    private unowned let previewProvider: TabPreviewProvider

    // MARK: - Public State

    /// Whether the tab switcher overlay is currently visible.
    private(set) var isActive: Bool = false

    /// The currently selected index in the switcher (0-based).
    private(set) var selectedIndex: Int = 0

    // MARK: - Private State

    /// IDs of recently used tabs, ordered by most recently used first.
    /// Maximum of 5 entries.
    private var recentlyUsedTabIDs: [Tab.ID] = []

    /// Task for observing tab activation changes.
    @ObservationIgnored
    private var observationTask: Task<Void, Never>?

    // MARK: - Constants

    private enum Constants {
        static let maxRecentTabs = 5
        static let minimumTabsForSwitcher = 2
    }

    // MARK: - Initialization

    /// Creates a TabSwitcherManager for a browser window.
    ///
    /// - Parameters:
    ///   - tabManager: The tab manager for session access.
    ///   - windowState: The window state to observe for tab changes.
    ///   - previewProvider: The shared provider for thumbnail caching.
    init(tabManager: TabManager, windowState: WindowState, previewProvider: TabPreviewProvider) {
        self.tabManager = tabManager
        self.windowState = windowState
        self.previewProvider = previewProvider

        startObserving()
    }

    isolated deinit {
        observationTask?.cancel()
    }

    // MARK: - Public API

    /// The tabs available for switching, filtered to only existing tabs.
    ///
    /// Returns tabs in most-recently-used order. Tabs that no longer exist
    /// are automatically filtered out.
    var recentTabs: [Tab] {
        recentlyUsedTabIDs.compactMap { id in
            tabManager.state.tab(for: id)
        }
    }

    /// Whether the tab switcher can be shown.
    ///
    /// Requires at least 2 tabs to make switching meaningful.
    var canShowSwitcher: Bool {
        recentTabs.count >= Constants.minimumTabsForSwitcher
    }

    /// Returns the cached preview for a tab.
    ///
    /// This delegates to the shared `TabPreviewProvider`.
    ///
    /// - Parameter tab: The tab to get a preview for.
    /// - Returns: The thumbnail adapter, or `nil` if not cached.
    func preview(for tab: Tab) -> ThumbnailAdapter? {
        previewProvider.preview(for: tab.id)
    }

    /// Shows the tab switcher and selects the previous tab.
    ///
    /// Called when Control+Tab is first pressed. The second most recent tab
    /// is selected by default (index 1), allowing quick switching to the
    /// previous tab.
    func show() {
        guard canShowSwitcher else { return }

        cleanupStaleEntries()

        isActive = true
        selectedIndex = min(1, recentTabs.count - 1)
    }

    /// Selects the next tab in the switcher (wraps around).
    ///
    /// Called when Tab is pressed while Control is held.
    func selectNext() {
        guard isActive, !recentTabs.isEmpty else { return }

        selectedIndex = (selectedIndex + 1) % recentTabs.count
    }

    /// Selects the previous tab in the switcher (wraps around).
    ///
    /// Called when Shift+Tab is pressed while Control is held.
    func selectPrevious() {
        guard isActive, !recentTabs.isEmpty else { return }

        selectedIndex = (selectedIndex - 1 + recentTabs.count) % recentTabs.count
    }

    /// Dismisses the switcher and activates the selected tab.
    ///
    /// Called when Control key is released. If the selected tab is already
    /// the active tab, no navigation occurs.
    func dismiss() {
        guard isActive else { return }

        let tabs = recentTabs
        if selectedIndex < tabs.count {
            let selectedTab = tabs[selectedIndex]

            if selectedTab.id != windowState.activeTabID {
                tabManager.setActiveTab(selectedTab, in: windowState)
            }
        }

        isActive = false
        selectedIndex = 0
    }

    /// Cancels the switcher without activating a tab.
    ///
    /// Called when Escape is pressed while the switcher is visible.
    func cancel() {
        isActive = false
        selectedIndex = 0
    }

    // MARK: - Private Methods

    /// Starts observing tab activation changes.
    private func startObserving() {
        let getActiveTabID = { [weak windowState] in windowState?.activeTabID }

        let tabChanges = Observations {
            getActiveTabID()
        }

        observationTask = Task { @MainActor [weak self] in
            for await activeTabID in tabChanges {
                guard let self, let activeTabID else { continue }
                recordTabActivation(activeTabID)
            }
        }
    }

    /// Records a tab activation in the recently used list.
    ///
    /// Moves the tab to the front if already present, otherwise inserts it.
    /// Trims the list to the maximum size.
    private func recordTabActivation(_ tabID: Tab.ID) {
        recentlyUsedTabIDs.removeAll { $0 == tabID }
        recentlyUsedTabIDs.insert(tabID, at: 0)

        if recentlyUsedTabIDs.count > Constants.maxRecentTabs {
            recentlyUsedTabIDs.removeLast(recentlyUsedTabIDs.count - Constants.maxRecentTabs)
        }
    }

    /// Removes entries for tabs that no longer exist.
    private func cleanupStaleEntries() {
        recentlyUsedTabIDs.removeAll { id in
            tabManager.state.tab(for: id) == nil
        }

        // Also cleanup the provider's stale entries
        previewProvider.cleanupStaleEntries()
    }
}
