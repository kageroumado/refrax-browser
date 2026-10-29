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
    func setActiveTab(_ tab: Tab, in windowState: WindowState, preservingVisit: Bool = false) {
        // Archived tabs are non-activatable - they must be restored first
        guard !tab.isArchived else {
            Logger.warning("Attempted to activate archived tab: \(tab.id)", category: Logger.tabs)
            return
        }

        // Live favorites don't have a space; regular tabs must have one
        let isLiveFavorite = tab.status == .favorite
        if !isLiveFavorite {
            guard tab.space?.id != nil, state.tab(for: tab.id) != nil else {
                return
            }
        }

        if !preservingVisit, !windowState.pageVisit.isTransformingIdentity {
            windowState.pageVisit.end()
        }

        if windowState.isInLayoutMode {
            windowState.exitLayoutMode()
        }

        // Capture active tab BEFORE state changes for PiP/extension callbacks
        let previousTabID = windowState.activeTabID

        // Favorite previews are anchored to the outgoing active tab
        favoritePreviewManager?.handleActiveTabChange()

        // Full-page activation takes the live surface from its floating preview.
        if let page = pagePool.existingPage(for: tab.activePage), page.isInFloatingPreview {
            page.claimOwnership(for: windowState)
        }

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
        } else {
            Tab?.none
        }

        if let previousTab, previousTab.id != tab.id {
            state.pipCoordinator.onTabDeactivated(previousTab, in: state)
        }
        state.pipCoordinator.onTabActivated(tab, in: state)

        if _runSynchronously {
            performPostActivationWork(tab: tab, previousTab: previousTab)
        } else {
            Task(priority: .utility) { [weak self] in
                guard let self else { return }
                performPostActivationWork(tab: tab, previousTab: previousTab)
            }
        }
    }

    /// Updates extensions and system handoff after activation.
    private func performPostActivationWork(tab: Tab, previousTab: Tab?) {
        state.extensionManager?.dispatchTabActivated(tab, previous: previousTab)

        state.handoffManager.updateActivity(for: tab)
    }
}
