import AppKit
import Observation

/// Coordinates all Apple system integrations in a centralized location.
///
/// This manager serves as the primary interface for Apple framework integrations,
/// providing a unified API that can be accessed through RefraxAPI for encapsulation.
///
/// ## Architecture
///
/// ```
/// ┌─────────────────────────────────────────────────────────────┐
/// │ AppleIntegrationManager                                      │
/// │   - Coordinates all Apple integrations                       │
/// │   - Provides unified API for RefraxAPI                       │
/// └─────────────────────────────────────────────────────────────┘
///          │           │           │           │
///          ▼           ▼           ▼           ▼
///    ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
///    │ Spotlight │ │Quick Note│ │ Focus    │ │ Handoff  │
///    │ Index    │ │ Manager  │ │ Filter   │ │ Manager  │
///    └──────────┘ └──────────┘ └──────────┘ └──────────┘
/// ```
///
/// ## Integrations
///
/// - **Spotlight**: Indexes tabs, bookmarks, and history for system search
/// - **Quick Note**: Creates notes from page content via system hotkey
/// - **Focus Filter**: Adapts behavior when system Focus changes (SetFocusFilterIntent)
/// - **Handoff**: Continues browsing across Apple devices (existing)
/// - **Services**: macOS Services menu integration (existing)
///
/// ## Usage
///
/// Access through AppDelegate for direct usage, or through RefraxAPI for
/// external agent access with permission checking.
@Observable
final class AppleIntegrationManager {
    // MARK: - Sub-Managers

    /// Manages Spotlight indexing for tabs, bookmarks, and history.
    let spotlightManager: SpotlightIndexManager

    /// Handles Quick Note creation from page content.
    let quickNoteManager: QuickNoteManager

    // MARK: - Dependencies

    private unowned let browserState: BrowserState
    private unowned let tabManager: TabManager
    private unowned let bookmarksManager: BookmarksManager
    private unowned let historyManager: HistoryManager
    private unowned let windowManager: WindowManager

    // MARK: - Initialization

    init(
        browserState: BrowserState,
        tabManager: TabManager,
        bookmarksManager: BookmarksManager,
        historyManager: HistoryManager,
        windowManager: WindowManager,
    ) {
        self.browserState = browserState
        self.tabManager = tabManager
        self.bookmarksManager = bookmarksManager
        self.historyManager = historyManager
        self.windowManager = windowManager

        // Initialize sub-managers
        self.spotlightManager = SpotlightIndexManager(
            browserState: browserState,
            bookmarksManager: bookmarksManager,
            historyManager: historyManager,
        )

        self.quickNoteManager = QuickNoteManager()
    }

    // MARK: - Spotlight Integration

    /// Indexes the current active tab in Spotlight.
    func indexActiveTab() {
        guard let windowState = windowManager.activeWindowController?.windowState,
              let spaceID = windowState.activeSpaceID,
              let tabID = windowState.activeTabID(for: spaceID),
              let tab = browserState.tab(for: tabID)
        else {
            return
        }

        spotlightManager.indexTab(tab)
    }

    /// Indexes all bookmarks in Spotlight.
    func indexAllBookmarks() {
        let bookmarks = bookmarksManager.allBookmarks()
        spotlightManager.indexBookmarks(bookmarks)
    }

    /// Indexes frequently visited history entries.
    func indexFrequentHistory() {
        spotlightManager.indexFrequentHistory()
    }

    /// Removes all Spotlight indexed items.
    func clearSpotlightIndex() {
        spotlightManager.removeAllIndexedItems()
    }

    // MARK: - Quick Note Integration

    /// Creates a Quick Note with the current page content.
    ///
    /// - Parameters:
    ///   - url: The URL to include in the note.
    ///   - title: The page title.
    ///   - selectedText: Optional selected text from the page.
    func createQuickNote(url: URL, title: String, selectedText: String? = nil) {
        quickNoteManager.createQuickNote(url: url, title: title, selectedText: selectedText)
    }

    /// Creates a Quick Note from the active tab.
    func createQuickNoteFromActiveTab() {
        guard let windowState = windowManager.activeWindowController?.windowState,
              let spaceID = windowState.activeSpaceID,
              let tabID = windowState.activeTabID(for: spaceID),
              let tab = browserState.tab(for: tabID)
        else {
            return
        }

        let url = tab.activePage.url
        let title = tab.displayTitle

        // Note: Selected text retrieval would require JavaScript evaluation
        // For now, create note without selected text
        quickNoteManager.createQuickNote(url: url, title: title, selectedText: nil)
    }

    // MARK: - Handoff Integration

    /// Updates Handoff activity for the given tab.
    ///
    /// This delegates to the existing HandoffManager but provides a unified
    /// interface through AppleIntegrationManager.
    func updateHandoffActivity(for tab: Tab?) {
        browserState.handoffManager.updateActivity(for: tab)
    }

    /// Invalidates the current Handoff activity.
    func invalidateHandoffActivity() {
        browserState.handoffManager.invalidateActivity()
    }

    // MARK: - Focus Mode Integration

    /// Gets the current Focus Mode status.
    ///
    /// Note: FocusModeManager integration pending - use RefraxFocusFilter for
    /// system Focus Filter integration instead.
    var isFocusModeActive: Bool {
        // FocusModeManager is defined but not yet integrated into BrowserState
        // The SetFocusFilterIntent (RefraxFocusFilter) provides system integration
        false
    }

    /// Gets the name of the current Focus Mode.
    var currentFocusModeName: String? {
        // FocusModeManager is defined but not yet integrated into BrowserState
        nil
    }

    // MARK: - Setup

    /// Performs deferred setup tasks.
    ///
    /// Call this after the main window has loaded to:
    /// - Index bookmarks in Spotlight
    /// - Index frequent history in Spotlight
    func performDeferredSetup() {
        spotlightManager.setup()
    }
}
