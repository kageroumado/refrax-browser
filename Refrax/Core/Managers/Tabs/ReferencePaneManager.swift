import Foundation
import SwiftData

/// Manages the reference pane and its tabs.
///
/// `ReferencePaneManager` centralizes all reference pane operations:
/// - Adding and removing reference tabs
/// - Moving tabs/pages between main area and reference pane
/// - Reference pane mode changes (hidden/docked/floating)
/// - Active reference tab per window synchronization
///
/// ## Architecture
///
/// Reference tabs are stored in `Space.referenceTabs` and are shared across
/// all windows showing that space. However, the *active* reference tab
/// is per-window (stored in `WindowState.activeReferenceTabID`).
///
/// ## Relationship to Other Managers
///
/// This manager is instantiated at the app delegate level alongside other
/// managers. It receives references to shared dependencies (state, pagePool,
/// windowManager, undoRedoManager) and is injected into the SwiftUI environment
/// for direct access via `@Environment(ReferencePaneManager.self)`.
///
/// ## Usage
///
/// ```swift
/// // Add a reference tab
/// let tab = referencePaneManager.addReferenceTab(url: url, in: space)
///
/// // Move main tab to reference pane
/// referencePaneManager.moveTabToReferencePane(tab)
///
/// // Set active reference tab
/// referencePaneManager.setActiveReferenceTab(tab)
/// ```
@Observable
final class ReferencePaneManager {
    // MARK: - Dependencies

    private unowned let state: BrowserState
    private unowned let pagePool: WebPagePool
    private unowned let windowManager: WindowManager
    private unowned let undoRedoManager: UndoRedoManager

    #if REFRAX_TESTS
        /// Test-only: The active window state to use when no real window controllers exist.
        var testActiveWindowState: WindowState?
    #endif

    /// Window state synchronization helper.
    private var windowSync: WindowStateSync {
        var sync = WindowStateSync(windowManager: windowManager)
        #if REFRAX_TESTS
            sync.testActiveWindowState = testActiveWindowState
        #endif
        return sync
    }

    // MARK: - Constants

    /// Maximum number of tabs allowed in the reference pane.
    static let maxReferenceTabs = 4

    // MARK: - Initialization

    init(
        state: BrowserState,
        pagePool: WebPagePool,
        windowManager: WindowManager,
        undoRedoManager: UndoRedoManager,
    ) {
        self.state = state
        self.pagePool = pagePool
        self.windowManager = windowManager
        self.undoRedoManager = undoRedoManager
    }

    // MARK: - Reference Tab Lifecycle

    /// Adds a tab to the reference pane.
    ///
    /// - Parameters:
    ///   - url: URL to load.
    ///   - title: Tab title.
    ///   - space: Space to add to.
    ///   - windowState: The window to activate the tab in. If nil, uses the active window.
    /// - Returns: The created Tab, or nil if limit reached.
    @discardableResult
    func addReferenceTab(url: URL, title: String = "New Tab", in space: Space, windowState: WindowState? = nil) -> Tab? {
        guard space.referenceTabs.count < Self.maxReferenceTabs else {
            Logger.warning("Reference pane limit reached", category: Logger.tabs)
            return nil
        }

        let tab = Tab(
            space: space,
            url: url,
            title: title,
            isReferenceTab: true,
            position: space.referenceTabs.count,
        )

        space.tabs.append(tab)
        state.indexTab(tab)
        state.modelContext.insert(tab)

        // Only set active in the specified/current window (per-window selection)
        let targetWindowState = windowState ?? windowManager.activeWindowController?.windowState
        windowSync.setActiveReferenceTabIDInWindow(for: space, newTabID: tab.id, windowState: targetWindowState)

        // When the reference pane window is open, claim ownership for the new tab's WebPage.
        // Without this, WebViewContainer's ownership check fails because isWindowKey checks
        // the main window (not the ref pane window), causing portal mode to be triggered.
        if let targetWindowState, targetWindowState.hasReferencePaneWindow,
           let webPage = pagePool.page(for: tab.activePage) {
            webPage.claimOwnership(for: targetWindowState)
        }

        state.incrementListVersion()
        state.scheduleSave()

        Logger.info("Reference tab added: \(title)", category: Logger.tabs)
        return tab
    }

    /// Closes a reference tab.
    ///
    /// - Parameter tab: The reference tab to close.
    func closeReferenceTab(_ tab: Tab) {
        guard tab.isReferenceTab,
              let space = tab.space else {
            return
        }

        let closedIndex = tab.position
        let closedInfo = ClosedTabInfo(tab: tab)

        pagePool.removePages(for: tab)
        removeReferenceTabInternal(tab, from: space, closedIndex: closedIndex)

        undoRedoManager.registerCloseReferenceTab(closedInfo)

        state.incrementListVersion()
        state.scheduleSave()
    }

    /// Restores a closed reference tab from undo info.
    ///
    /// - Parameter info: Information about the closed reference tab to restore.
    func restoreReferenceTab(_ info: ClosedTabInfo) {
        guard let space = state.spaces.first(where: { $0.id == info.spaceID }) else {
            Logger.error("Cannot restore reference tab: space not found", category: Logger.tabs)
            return
        }

        guard space.referenceTabs.count < Self.maxReferenceTabs else {
            Logger.warning("Cannot restore reference tab: limit reached", category: Logger.tabs)
            return
        }

        let tab = Tab(
            space: space,
            url: info.url,
            title: info.title,
            isReferenceTab: true,
            position: space.referenceTabs.count,
        )
        tab.customName = info.customName
        tab.activePage.faviconData = info.faviconData
        state.indexTab(tab)
        state.modelContext.insert(tab)

        // Only set active in the current window (per-window selection)
        // Undo operations typically restore to the active window which triggered the undo
        windowSync.setActiveReferenceTabIDInWindow(for: space, newTabID: tab.id)

        state.incrementListVersion()
        state.scheduleSave()

        Logger.info("Reference tab restored: \(info.title)", category: Logger.tabs)
    }

    // MARK: - Active Reference Tab

    /// Sets the active reference tab in the specified or active window.
    ///
    /// Active reference tab is per-window, so this only updates the window
    /// where the action was triggered.
    ///
    /// - Parameters:
    ///   - tab: The reference tab to activate.
    ///   - windowState: The window to activate the tab in. If nil, uses the active window.
    func setActiveReferenceTab(_ tab: Tab, in windowState: WindowState) {
        guard let space = tab.space,
              space.referenceTabs.contains(where: { $0.id == tab.id }) else {
            return
        }

        // Only set active in the specified/current window (per-window selection)
        windowSync.setActiveReferenceTabIDInWindow(for: space, newTabID: tab.id, windowState: windowState)
        tab.updateLastAccessed()

        for page in tab.pages where !page.url.isDeepLink {
            pagePool.page(for: page)
        }

        state.incrementContentVersion()
    }

    // MARK: - Tab Transfer (Main ↔ Reference)

    /// Moves a main tab to the reference pane.
    ///
    /// The tab's `isReferenceTab` flag is set to true. Session state is preserved
    /// by keeping the same Tab instance. If the moved tab was active, a new main
    /// tab is selected automatically via window state sync.
    ///
    /// - Parameters:
    ///   - tab: The main tab to move.
    ///   - windowState: The window to activate the reference tab in. If nil, uses the active window.
    /// - Returns: True if the move succeeded.
    @discardableResult
    func moveTabToReferencePane(
        _ tab: Tab,
        in windowState: WindowState? = nil,
    ) -> Bool {
        guard let space = tab.space,
              space.mainTabs.count > 1,
              tab.pages.count == 1,
              space.referenceTabs.count < Self.maxReferenceTabs,
              let index = space.tabs.firstIndex(of: tab) else {
            Logger.warning("Cannot move tab to reference pane", category: Logger.tabs)
            return false
        }

        // Get index in mainTabs before modification for proper adjacency fallback
        let mainTabIndex = space.mainTabs.firstIndex(of: tab) ?? 0
        let closedContext = TabMutationPipeline.ClosedTabContext(
            tabID: tab.id,
            mainTabIndex: mainTabIndex,
        )

        // Determine target window state for ownership and active tab tracking
        let targetWindowState = windowState ?? windowManager.activeWindowController?.windowState

        // IMPORTANT: Claim ownership BEFORE modifying the tab state.
        // Tab is @Observable, so setting isReferenceTab triggers immediate SwiftUI updates.
        // If we claim ownership after the state change, the old WebViewContainer will
        // see isOwner=false (ownership not yet updated) and incorrectly enter portal mode.
        if let targetWindowState, targetWindowState.hasReferencePaneWindow,
           let webPage = pagePool.existingPage(for: tab.activePage) {
            webPage.claimOwnership(for: targetWindowState)
        }

        // Move tab within array and mark as reference
        space.tabs.remove(at: index)
        tab.isReferenceTab = true
        // Note: tabs.remove already invalidates cache via count change, but invalidate
        // explicitly for the isReferenceTab change
        space.invalidateTabCaches()
        tab.position = space.referenceTabs.count
        space.tabs.append(tab)

        // Set as active reference tab in the specified/current window
        windowSync.setActiveReferenceTabIDInWindow(for: space, newTabID: tab.id, windowState: targetWindowState)

        // Sync active main tab if the moved tab was active (now invalid for main selection)
        windowSync.syncInvalidActiveTabIDs(for: space, closedContext: closedContext)

        state.incrementListVersion()
        state.scheduleSave()

        Logger.info("Moved tab to reference pane: \(tab.activePage.title)", category: Logger.tabs)
        return true
    }

    /// Moves a reference tab to the main area.
    ///
    /// The tab's `isReferenceTab` flag is set to false. Since all tabs are in
    /// `space.tabs`, this effectively moves it from `referenceTabs` view to
    /// `mainTabs` view.
    ///
    /// - Parameters:
    ///   - referenceTab: The reference tab to move.
    ///   - insertionIndex: Index in main tabs to insert at.
    ///   - normalizePositions: Closure to normalize positions after insertion.
    /// - Returns: True if the move succeeded.
    @discardableResult
    func moveReferenceTabToMainArea(
        _ referenceTab: Tab,
        insertionIndex: Int,
        normalizePositions: (Space) -> Void,
    ) -> Bool {
        guard let space = referenceTab.space,
              referenceTab.isReferenceTab else {
            return false
        }

        // Capture position before changing isReferenceTab (for smart adjacent selection)
        let closedIndex = referenceTab.position

        // Convert to main tab
        referenceTab.isReferenceTab = false
        referenceTab.position = insertionIndex

        // Invalidate cache after changing isReferenceTab
        space.invalidateTabCaches()

        // Sync reference tab selection - use smart adjacent selection
        windowSync.syncInvalidActiveReferenceTabIDs(for: space, closedIndex: closedIndex)

        // Renumber remaining reference tabs
        for (index, refTab) in space.referenceTabs.enumerated() {
            refTab.position = index
        }

        normalizePositions(space)

        state.incrementListVersion()
        state.scheduleSave()

        Logger.info("Moved reference tab to main: \(referenceTab.activePage.title)", category: Logger.tabs)
        return true
    }

    // MARK: - Private Helpers

    /// Removes a reference tab from a space (internal implementation).
    ///
    /// - Parameters:
    ///   - tab: The reference tab to remove.
    ///   - space: The space containing the tab.
    ///   - closedIndex: The position of the tab being removed (for smart adjacent selection).
    private func removeReferenceTabInternal(_ tab: Tab, from space: Space, closedIndex: Int) {
        state.removeFromIndex(tab)

        // Remove from the tabs relationship
        space.tabs.removeAll { $0.id == tab.id }

        // Invalidate cache - count-based staleness can miss when add+remove returns to same count
        space.invalidateTabCaches()

        // Sync reference tab selection - use smart adjacent selection
        windowSync.syncInvalidActiveReferenceTabIDs(for: space, closedIndex: closedIndex)

        // Renumber remaining reference tabs
        for (index, refTab) in space.referenceTabs.enumerated() {
            refTab.position = index
        }

        state.modelContext.delete(tab)
    }
}
