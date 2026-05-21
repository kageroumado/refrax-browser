import Foundation

/// Centralizes window state synchronization after tab mutations.
///
/// `WindowStateSync` provides helper methods for synchronizing `WindowState`
/// across all windows after tab operations. This ensures that active tab
/// selections and reference tab states remain consistent when tabs are
/// moved, closed, or modified.
///
/// ## Why Centralize?
///
/// Tab mutations can affect multiple windows simultaneously:
/// - Moving a tab to another space may invalidate window selections
/// - Closing the active tab requires selecting a new one
/// - Reference tab removals may invalidate selections in some windows
///
/// Centralizing this logic:
/// 1. Prevents bugs from inconsistent sync across different operations
/// 2. Makes it easier to reason about window state invariants
/// 3. Reduces code duplication in TabManager methods
///
/// ## Per-Window vs All-Window Sync
///
/// - **Active tab** (`syncActiveTabID`): Broadcasts to all windows showing the space,
///   since main tabs are typically selected uniformly.
/// - **Reference tab** (`setActiveReferenceTabIDInWindow`): Only updates the
///   specified window (or active window if not specified), since reference tab
///   selection is per-window by design.
/// - **Invalid selection sync** (`syncInvalid...`): Only fixes windows where the
///   selected tab no longer exists.
///
/// ## Usage
///
/// ```swift
/// let sync = WindowStateSync(windowManager: windowManager)
///
/// // After closing active tab - updates all windows
/// sync.syncActiveTabID(for: space, newTabID: nextTab?.id)
///
/// // After adding reference tab - only specified/current window
/// sync.setActiveReferenceTabIDInWindow(for: space, newTabID: newRefTab?.id, windowState: initiatingWindow)
///
/// // After removing reference tab - fix invalid selections with smart adjacent selection
/// sync.syncInvalidActiveReferenceTabIDs(for: space, closedIndex: closedRefTabIndex)
/// ```
struct WindowStateSync {
    private let windowManager: WindowManager

    #if REFRAX_TESTS
        /// Test-only: Additional window state to sync when no real window controllers exist.
        var testActiveWindowState: WindowState?
    #endif

    init(windowManager: WindowManager) {
        self.windowManager = windowManager
    }

    // MARK: - Active Tab Synchronization

    /// Syncs the active tab ID for a space across all windows.
    ///
    /// Call this after operations that may invalidate window active tabs:
    /// - Tab close
    /// - Tab move to another space
    /// - Batch tab operations
    ///
    /// - Parameters:
    ///   - space: The space whose active tab changed.
    ///   - newTabID: The new active tab ID, or nil to clear.
    func syncActiveTabID(for space: Space, newTabID: Tab.ID?) {
        for controller in windowManager.windowControllers {
            if controller.windowState.activeSpaceID == space.id {
                controller.windowState.setActiveTabID(newTabID, for: space.id)
            }
        }
    }

    /// Syncs the active tab ID for a space only in windows where the current
    /// active tab is invalid (no longer in the space).
    ///
    /// Uses smart selection to find the best replacement tab:
    /// 1. Previous active tab (the tab before switching to the now-closed one)
    /// 2. Adjacent tab in visual order (next, then previous)
    /// 3. First main tab as fallback
    ///
    /// - Parameters:
    ///   - space: The space to check.
    ///   - closedContext: Context about closed tabs for smart adjacent selection.
    func syncInvalidActiveTabIDs(for space: Space, closedContext: TabMutationPipeline.ClosedTabContext?) {
        // Only main tabs are valid for active tab selection (not reference tabs)
        let validTabIDs = Set(space.mainTabs.map(\.id))

        for controller in windowManager.windowControllers {
            guard controller.windowState.activeSpaceID == space.id else { continue }

            if let currentID = controller.windowState.activeTabID(for: space.id),
               !validTabIDs.contains(currentID) {
                let newTabID = findBestTabToActivate(
                    for: space,
                    windowState: controller.windowState,
                    closedContext: closedContext,
                )
                controller.windowState.setActiveTabID(newTabID, for: space.id, trackPrevious: false)
            }
        }

        #if REFRAX_TESTS
            // Also update test window state if set (no registered window controllers in tests)
            if let testState = testActiveWindowState,
               testState.activeSpaceID == space.id,
               let currentID = testState.activeTabID(for: space.id),
               !validTabIDs.contains(currentID) {
                let newTabID = findBestTabToActivate(
                    for: space,
                    windowState: testState,
                    closedContext: closedContext,
                )
                testState.setActiveTabID(newTabID, for: space.id, trackPrevious: false)
            }
        #endif
    }

    /// Finds the best tab to activate after the current active tab becomes invalid.
    ///
    /// Selection priority:
    /// 1. Previous active tab (if still valid)
    /// 2. Adjacent tab at the closed tab's position
    /// 3. First main tab
    private func findBestTabToActivate(
        for space: Space,
        windowState: WindowState,
        closedContext: TabMutationPipeline.ClosedTabContext?,
    ) -> Tab.ID? {
        let mainTabs = space.mainTabs
        guard !mainTabs.isEmpty else { return nil }

        // Priority 1: Previous active tab (if still valid)
        if let previousID = windowState.previousActiveTabID(for: space.id),
           mainTabs.contains(where: { $0.id == previousID }) {
            return previousID
        }

        // Priority 2: Adjacent tab at closed position
        if let context = closedContext {
            let closedIndex = context.mainTabIndex
            if closedIndex < mainTabs.count {
                // Tab at same index is now the "next" tab (items shifted up)
                return mainTabs[closedIndex].id
            } else if closedIndex > 0, closedIndex - 1 < mainTabs.count {
                // Closed tab was at the end, use previous
                return mainTabs[closedIndex - 1].id
            }
        }

        // Fallback: first main tab
        return mainTabs.first?.id
    }

    // MARK: - Active Reference Tab Synchronization

    /// Sets the active reference tab ID for a specific window state.
    ///
    /// Active reference tab is per-window, so operations like adding or selecting
    /// a reference tab should only affect the window where the action occurred.
    ///
    /// - Parameters:
    ///   - windowState: The specific window state to update.
    ///   - newTabID: The new active reference tab ID, or nil to clear.
    func setActiveReferenceTabID(for windowState: WindowState, newTabID: Tab.ID?) {
        windowState.activeReferenceTabID = newTabID
    }

    /// Sets the active reference tab ID for a specific window or the active window.
    ///
    /// Use this when an operation that affects reference tab selection is triggered
    /// by the user (e.g., adding a reference tab, selecting one).
    ///
    /// - Parameters:
    ///   - space: The space to verify (for validation only).
    ///   - newTabID: The new active reference tab ID, or nil to clear.
    ///   - windowState: The specific window to update. If nil, uses the active window.
    func setActiveReferenceTabIDInWindow(for space: Space, newTabID: Tab.ID?, windowState: WindowState? = nil) {
        if let windowState {
            guard windowState.activeSpaceID == space.id else { return }
            windowState.activeReferenceTabID = newTabID
        } else {
            guard let activeController = windowManager.activeWindowController,
                  activeController.windowState.activeSpaceID == space.id else { return }
            activeController.windowState.activeReferenceTabID = newTabID
        }
    }

    /// Syncs the active reference tab ID only in windows where the current
    /// selection is invalid (reference tab no longer exists in space).
    ///
    /// Uses smart selection to find the best replacement:
    /// 1. Adjacent tab at the closed tab's position
    /// 2. Last remaining reference tab
    /// 3. nil if no reference tabs remain
    ///
    /// - Parameters:
    ///   - space: The space to check.
    ///   - closedIndex: The position of the closed reference tab (for adjacent selection).
    func syncInvalidActiveReferenceTabIDs(for space: Space, closedIndex: Int?) {
        let referenceTabs = space.referenceTabs
        let validRefTabIDs = Set(referenceTabs.map(\.id))

        for controller in windowManager.windowControllers {
            guard controller.windowState.activeSpaceID == space.id else { continue }

            if let currentID = controller.windowState.activeReferenceTabID,
               !validRefTabIDs.contains(currentID) {
                let newTabID = findBestReferenceTabToActivate(
                    referenceTabs: referenceTabs,
                    closedIndex: closedIndex,
                )
                controller.windowState.activeReferenceTabID = newTabID
            }
        }
    }

    /// Finds the best reference tab to activate after the current one becomes invalid.
    ///
    /// Selection priority:
    /// 1. Adjacent tab at the closed tab's position
    /// 2. Last remaining reference tab
    /// 3. nil if no reference tabs remain
    private func findBestReferenceTabToActivate(
        referenceTabs: [Tab],
        closedIndex: Int?,
    ) -> Tab.ID? {
        guard !referenceTabs.isEmpty else { return nil }

        // Priority 1: Adjacent tab at closed position
        if let closedIndex {
            if closedIndex < referenceTabs.count {
                // Tab at same index is now the "next" tab (items shifted up)
                return referenceTabs[closedIndex].id
            } else if closedIndex > 0, closedIndex - 1 < referenceTabs.count {
                // Closed tab was at the end, use previous
                return referenceTabs[closedIndex - 1].id
            }
        }

        // Fallback: last reference tab (most recently added)
        return referenceTabs.last?.id
    }

    // MARK: - Batch Synchronization

    /// Syncs state for multiple affected spaces.
    ///
    /// Use after batch operations that affect tabs across multiple spaces.
    /// Uses first-tab fallback since batch operations don't have single-tab context.
    ///
    /// - Parameter spaceIDs: The IDs of affected spaces.
    /// - Parameter browserState: The browser state to look up spaces.
    func syncInvalidSelectionsForSpaces(
        _ spaceIDs: Set<Space.ID>,
        browserState: BrowserState,
    ) {
        for spaceID in spaceIDs {
            guard let space = browserState.space(for: spaceID) else { continue }

            // Pass nil for closed context - batch operations use previous tab or first fallback
            syncInvalidActiveTabIDs(for: space, closedContext: nil)
            // Pass nil for closedIndex - batch operations use last-tab fallback
            syncInvalidActiveReferenceTabIDs(for: space, closedIndex: nil)
        }
    }

    // MARK: - Window Lookup

    /// Finds the first window state showing a specific space.
    ///
    /// - Parameter space: The space to find.
    /// - Returns: The first matching window state, or nil.
    func findWindowState(for space: Space) -> WindowState? {
        #if REFRAX_TESTS
            // Check test window state first (no registered window controllers in tests)
            if let testState = testActiveWindowState,
               testState.activeSpaceID == space.id {
                return testState
            }
        #endif

        for controller in windowManager.windowControllers {
            if controller.windowState.activeSpaceID == space.id {
                return controller.windowState
            }
        }
        return nil
    }

    /// Gets all window states showing a specific space.
    ///
    /// - Parameter space: The space to find.
    /// - Returns: All matching window states.
    func allWindowStates(for space: Space) -> [WindowState] {
        windowManager.windowControllers
            .filter { $0.windowState.activeSpaceID == space.id }
            .map(\.windowState)
    }
}
