import Foundation

// MARK: - Tab Activation

extension TabManager {
    // MARK: - Setting Active Tab

    /// Sets a tab as active in the specified window.
    ///
    /// Handles both regular/pinned tabs and live favorite tabs with unified logic.
    /// Creates session if needed, preloads adjacent tabs, and updates context.
    ///
    /// - Parameters:
    ///   - tab: Tab to activate.
    ///   - windowState: The window state to update.
    func setActiveTab(_ tab: Tab, in windowState: WindowState) {
        // Archived tabs are non-activatable - they must be restored first
        guard !tab.isArchived else {
            Logger.warning("Attempted to activate archived tab: \(tab.id)", category: Logger.tabs)
            return
        }

        // Live favorites don't have a space; regular tabs must have one
        let isLiveFavorite = tab.status == .liveFavorite
        if !isLiveFavorite {
            guard tab.space?.id != nil, state.tab(for: tab.id) != nil else {
                return
            }
        }

        if windowState.isInLayoutMode {
            windowState.exitLayoutMode()
        }

        // Capture active tab BEFORE state changes for PiP/extension callbacks
        let previousTabID = windowState.activeTabID

        // Update window state (handles both live favorites and space tabs)
        windowState.setActiveTab(tab)

        tab.updateLastAccessed()
        tab.isUnread = false
        tab.unreadFromBadge = false

        // Remove tab from archive threshold (activation resets inactivity timer)
        autoArchiveManager?.tabWasActivated(tab)

        state.incrementContentVersion()
        scheduleSave()

        // Defer non user-interactive work using a Task with utility priority
        let previousTab = if let previousTabID {
            state.tab(for: previousTabID)
        } else { Tab?.none }

        if _runSynchronously {
            performPostActivationWork(tab: tab, previousTab: previousTab)
        } else {
            Task(priority: .utility) { [weak self] in
                guard let self else { return }
                performPostActivationWork(tab: tab, previousTab: previousTab)
            }
        }
    }

    /// Performs post-activation work (PiP, extensions, handoff, context).
    private func performPostActivationWork(tab: Tab, previousTab: Tab?) {
        if let previousTab {
            state.pipCoordinator.onTabDeactivated(previousTab, in: state)
        }
        state.pipCoordinator.onTabActivated(tab, in: state)

        state.extensionManager?.dispatchTabActivated(tab, previous: previousTab)

        state.handoffManager.updateActivity(for: tab)
    }

    /// Selects the next tab in the active window.
    func selectNextTab() {
        guard let windowState = activeWindowState,
              let space = windowState.activeSpace,
              !space.mainTabs.isEmpty else { return }
        selectNextTab(in: space.mainTabs)
    }

    /// Selects the next tab in a filtered list.
    func selectNextTab(in filteredTabs: [Tab]) {
        guard !filteredTabs.isEmpty,
              let windowState = activeWindowState else {
            return
        }

        guard let current = windowState.activeTab,
              let currentIndex = filteredTabs.firstIndex(of: current) else {
            // Current tab not in list - activate first tab
            setActiveTab(filteredTabs[0], in: windowState)
            return
        }

        let nextIndex = currentIndex + 1
        if nextIndex < filteredTabs.count {
            setActiveTab(filteredTabs[nextIndex], in: windowState)
        }
    }

    /// Selects the previous tab in the active window.
    func selectPreviousTab() {
        guard let windowState = activeWindowState,
              let space = windowState.activeSpace,
              !space.mainTabs.isEmpty else { return }
        selectPreviousTab(in: space.mainTabs)
    }

    /// Selects the previous tab in a filtered list.
    func selectPreviousTab(in filteredTabs: [Tab]) {
        guard !filteredTabs.isEmpty,
              let windowState = activeWindowState else {
            return
        }

        guard let current = windowState.activeTab,
              let currentIndex = filteredTabs.firstIndex(of: current) else {
            // Current tab not in list - activate first tab
            setActiveTab(filteredTabs[0], in: windowState)
            return
        }

        let previousIndex = currentIndex - 1
        if previousIndex >= 0 {
            setActiveTab(filteredTabs[previousIndex], in: windowState)
        }
    }
}
