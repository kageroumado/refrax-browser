import AppKit
import Foundation

// MARK: - Tab Organization

extension TabManager {
    /// Moves a tab to a new position.
    func moveTab(_ tab: Tab, to index: Int) {
        guard let space = tab.space,
              let currentIndex = space.tabs.firstIndex(of: tab),
              index != currentIndex,
              index >= 0, index < space.tabs.count else {
            return
        }

        space.tabs.remove(at: currentIndex)
        space.tabs.insert(tab, at: index)
        normalizePositions(in: space)
        state.incrementListVersion()
        scheduleSave()

        // Notify extensions of tab move (within same window)
        state.extensionManager?.dispatchTabMoved(tab, fromIndex: currentIndex, oldWindow: nil)
    }

    /// Toggles a tab's pinned state.
    func togglePinTab(_ tab: Tab) {
        guard let space = tab.space,
              let currentIndex = space.tabs.firstIndex(of: tab) else {
            return
        }

        if tab.groupID != nil {
            Logger.warning("Cannot pin tab in group", category: Logger.tabs)
            return
        }

        tab.isPinned.toggle()
        space.tabs.remove(at: currentIndex)

        if tab.isPinned {
            // Capture origin URL for navigation containment
            tab.originURL = tab.activePage.url
            let pinnedCount = space.tabs.count(where: { $0.isPinned })
            space.tabs.insert(tab, at: pinnedCount)
        } else {
            // Clear origin URL when unpinning
            tab.originURL = nil
            let firstUnpinned = space.tabs.prefix(while: { $0.isPinned }).count
            space.tabs.insert(tab, at: firstUnpinned)
        }

        normalizePositions(in: space)
        state.incrementListVersion()
        scheduleSave()

        // Notify extensions of pinned state change
        state.extensionManager?.dispatchPinnedChanged(tab)

        Logger.info("Tab pin toggled: \(tab.isPinned)", category: Logger.tabs)
    }

    /// Sets a custom name for a tab.
    ///
    /// - Parameters:
    ///   - name: The new custom name. Empty strings are rejected.
    ///   - tab: The tab to rename.
    /// - Returns: `true` if the name was set, `false` if rejected.
    @discardableResult
    func setCustomName(_ name: String, for tab: Tab) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !trimmed.isEmpty else {
            Logger.warning("Custom name rejected: empty string", category: Logger.tabs)
            return false
        }

        let truncated = String(trimmed.prefix(Self.maxCustomNameLength))
        tab.customName = truncated

        state.incrementContentVersion()
        scheduleSave()

        Logger.info("Tab renamed to: \(truncated)", category: Logger.tabs)
        return true
    }

    /// Clears a tab's custom name.
    func clearCustomName(_ tab: Tab) {
        tab.customName = nil
        state.incrementContentVersion()
        scheduleSave()
    }

    /// Marks a tab as read.
    func markAsRead(_ tab: Tab) {
        tab.isUnread = false
        tab.unreadFromBadge = false
        state.incrementContentVersion()
        scheduleSave()
    }

    /// Marks a tab as unread.
    ///
    /// Sets `unreadFromBadge` to `false` so the unread status won't be automatically
    /// cleared when a badge counter disappears from the page title.
    func markAsUnread(_ tab: Tab) {
        tab.isUnread = true
        tab.unreadFromBadge = false
        state.incrementContentVersion()
        scheduleSave()
    }

    /// Copies a tab's URL to the pasteboard.
    func copyURLToPasteboard(for tab: Tab) {
        let url = tab.activePage.url.absoluteString
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
    }

    // MARK: - Batch Operations

    /// Closes all tabs in the active space.
    func closeAllTabs() {
        guard let space = activeWindowState?.activeSpace else { return }
        closeTabsInBatch(space.tabs, undoActionName: "Close All Tabs")
    }

    /// Closes all tabs in the active space except the specified one.
    func closeOtherTabsInSpace(except tab: Tab) {
        guard let space = tab.space else { return }
        let tabsToClose = space.tabs.filter { $0.id != tab.id }
        closeTabsInBatch(tabsToClose, undoActionName: "Close Other Tabs")
    }

    /// Closes tabs except the specified tab in the list.
    func closeOtherTabs(except tab: Tab, in items: [TabListItem]) {
        let tabsToClose = items.compactMap(\.tab).filter { $0.id != tab.id }
        closeTabsInBatch(tabsToClose, undoActionName: "Close Other Tabs")
    }

    /// Closes tabs above the specified tab in the list.
    func closeTabsAbove(_ tab: Tab, in items: [TabListItem]) {
        guard let index = items.firstIndex(where: { $0.tab?.id == tab.id }) else { return }
        let tabsToClose = items[..<index].compactMap(\.tab)
        closeTabsInBatch(tabsToClose, undoActionName: "Close Tabs Above")
    }

    /// Closes tabs below the specified tab in the list.
    func closeTabsBelow(_ tab: Tab, in items: [TabListItem]) {
        guard let index = items.firstIndex(where: { $0.tab?.id == tab.id }) else { return }
        let tabsToClose = items[(index + 1)...].compactMap(\.tab)
        closeTabsInBatch(tabsToClose, undoActionName: "Close Tabs Below")
    }

    /// Closes all tabs in the given list items.
    func closeAllTabs(in items: [TabListItem]) {
        let tabsToClose = items.compactMap(\.tab)
        closeTabsInBatch(tabsToClose, undoActionName: "Close All Tabs")
    }

    /// Closes the specified tabs.
    ///
    /// Used for closing multiple selected tabs at once.
    ///
    /// - Parameters:
    ///   - tabs: The tabs to close.
    ///   - bypassArchive: If true, permanently deletes the tabs even when archive is enabled.
    func closeTabs(_ tabs: [Tab], bypassArchive: Bool = false) {
        guard !tabs.isEmpty else { return }
        closeTabsInBatch(tabs, undoActionName: "Close \(tabs.count) Tabs", bypassArchive: bypassArchive)
    }

    // MARK: - Request Batch Close (with Confirmation)

    /// Requests to close all tabs except the specified one, with confirmation if needed.
    func requestCloseOtherTabs(except tab: Tab, in items: [TabListItem]) {
        let tabsToClose = items.compactMap(\.tab).filter { $0.id != tab.id }
        requestCloseTabs(tabsToClose)
    }

    /// Requests to close tabs above the specified tab, with confirmation if needed.
    func requestCloseTabsAbove(_ tab: Tab, in items: [TabListItem]) {
        guard let index = items.firstIndex(where: { $0.tab?.id == tab.id }) else { return }
        let tabsToClose = items[..<index].compactMap(\.tab)
        requestCloseTabs(tabsToClose)
    }

    /// Requests to close tabs below the specified tab, with confirmation if needed.
    func requestCloseTabsBelow(_ tab: Tab, in items: [TabListItem]) {
        guard let index = items.firstIndex(where: { $0.tab?.id == tab.id }) else { return }
        let tabsToClose = items[(index + 1)...].compactMap(\.tab)
        requestCloseTabs(tabsToClose)
    }

    /// Requests to close all tabs in the given list items, with confirmation if needed.
    func requestCloseAllTabs(in items: [TabListItem]) {
        let tabsToClose = items.compactMap(\.tab)
        requestCloseTabs(tabsToClose)
    }

    /// Moves multiple tabs to a different space.
    ///
    /// Tabs are removed from their current space and added to the target space.
    /// Group memberships are cleared when moving between spaces.
    /// If the active tab in a window is moved, the window's selection is updated.
    ///
    /// - Parameters:
    ///   - tabs: The tabs to move.
    ///   - space: The destination space.
    func moveTabs(_ tabs: [Tab], to space: Space) {
        guard !tabs.isEmpty else { return }

        spaceManager.ensureLoaded(space)

        mutationPipeline.withMutation { effects in
            var affectedSourceSpaceIDs: Set<Space.ID> = []
            // Build per-space group indexes for O(1) lookups
            var groupIndexBySpace: [Space.ID: [UUID: TabGroup]] = [:]

            for tab in tabs {
                guard let sourceSpace = tab.space,
                      let index = sourceSpace.tabs.firstIndex(of: tab) else {
                    continue
                }

                affectedSourceSpaceIDs.insert(sourceSpace.id)

                sourceSpace.tabs.remove(at: index)

                if let groupID = tab.groupID {
                    // Lazily build group index for this space
                    if groupIndexBySpace[sourceSpace.id] == nil {
                        groupIndexBySpace[sourceSpace.id] = Dictionary(
                            uniqueKeysWithValues: sourceSpace.groups.map { ($0.id, $0) },
                        )
                    }
                    if let group = groupIndexBySpace[sourceSpace.id]?[groupID] {
                        group._removeTab(tab)
                    }
                }
                tab.groupID = nil

                // Calculate proper hierarchical position for the target space
                let insertion = positioner.insertionPosition(for: space, isPinned: false)

                tab.space = space
                tab.isPinned = false
                tab.position = insertion.position

                space.tabs.insert(tab, at: insertion.index)
            }

            // Mark affected spaces for normalization and active tab sync
            for sourceSpaceID in affectedSourceSpaceIDs {
                effects.spaceIDsToNormalize.insert(sourceSpaceID)
                effects.spaceIDsToSyncActiveTab.insert(sourceSpaceID)
            }
            effects.spaceIDsToNormalize.insert(space.id)
            effects.didChangeList = true
        }

        Logger.info("Moved \(tabs.count) tabs to space: \(space.name)", category: Logger.tabs)
    }

    /// Converts a multi-page tab to single page, removing secondary pages.
    func convertToSinglePage(_ tab: Tab) {
        guard tab.isMultiPage else { return }

        let pagesToRemove = tab.pages.filter { $0.id != tab.activePage.id }
        for page in pagesToRemove {
            removePageFromTab(tab, page: page)
        }

        state.incrementListVersion()
    }

    // MARK: - Search & Filter

    /// Returns tabs matching a search query in the active space.
    ///
    /// Matches against the tab's title, display URL, and custom name.
    /// Returns all tabs when the query is empty.
    ///
    /// - Parameter query: The search query to match against.
    /// - Returns: Tabs matching the query.
    func tabs(matching query: String) -> [Tab] {
        guard let space = activeWindowState?.activeSpace, !query.isEmpty else {
            return activeWindowState?.activeSpace?.tabs ?? []
        }

        return space.tabs.filter { tab in
            tab.activePage.title.localizedCaseInsensitiveContains(query) ||
                tab.displayURL.localizedCaseInsensitiveContains(query) ||
                (tab.customName?.localizedCaseInsensitiveContains(query) ?? false)
        }
    }

    /// Pinned tabs in the active space, sorted by position.
    var pinnedTabs: [Tab] {
        activeWindowState?.activeSpace?.tabs
            .filter(\.isPinned)
            .sorted { $0.position < $1.position } ?? []
    }

    /// Unpinned tabs in the active space, sorted by position.
    var unpinnedTabs: [Tab] {
        activeWindowState?.activeSpace?.tabs
            .filter { !$0.isPinned }
            .sorted { $0.position < $1.position } ?? []
    }
}
