import Foundation
import SwiftData

// MARK: - Tab Lifecycle

extension TabManager {
    /// Creates a new tab in a space.
    ///
    /// - Parameters:
    ///   - url: URL to load.
    ///   - space: Space to create tab in. If nil, uses active window's space.
    ///   - groupID: Optional group to add the tab to.
    ///   - isPinned: Whether to pin the tab.
    ///   - makeActive: Whether to activate the tab immediately.
    ///   - loadImmediately: Whether to create a session and load the URL even when `makeActive` is false.
    ///     Set to `true` for user-initiated background tabs (e.g., cmd+click).
    ///     Set to `false` for restored tabs that should load lazily when activated.
    ///     Defaults to the value of `makeActive`.
    ///   - insertionStrategy: Where to insert the new tab. Defaults to `.prepend` (top of list).
    ///     Use `.afterActive` to insert below the currently active tab.
    /// - Returns: The created Tab.
    @discardableResult
    func createTab(
        url: URL,
        in space: Space? = nil,
        groupID: UUID? = nil,
        isPinned: Bool = false,
        makeActive: Bool = true,
        loadImmediately: Bool? = nil,
        insertionStrategy: TabPositioner.InsertionStrategy = .prepend,
    ) -> Tab {
        guard let targetSpace = space ?? activeWindowState?.activeSpace else {
            preconditionFailure("Cannot create tab: no space provided and no active space available")
        }

        spaceManager.ensureLoaded(targetSpace)

        let activeTabID = activeWindowState?.activeTabID
        let insertion = insertionPosition(
            in: targetSpace,
            isPinned: isPinned,
            groupID: groupID,
            strategy: insertionStrategy,
            activeTabID: activeTabID,
        )
        let status: TabStatus = isPinned ? .pinned : .regular

        let tab = Tab(
            space: targetSpace,
            url: url,
            title: url.host ?? "New Tab",
            status: status,
            groupID: groupID,
            position: insertion.position,
        )
        tab.isUnread = !makeActive

        // Set origin URL for pinned tabs (navigation containment)
        if isPinned {
            tab.originURL = url
        }

        mutationPipeline.withMutation { effects in
            targetSpace.tabs.insert(tab, at: insertion.index)

            if let groupID, let group = targetSpace.groups.first(where: { $0.id == groupID }) {
                group._addTab(tab)
            }

            state.modelContext.insert(tab)

            // Normalize if inserting in the middle
            let needsNormalize = insertion.index < targetSpace.tabs.count - 1
            effects.tabAdded(tab, in: targetSpace, normalize: needsNormalize)
        }

        if makeActive, let windowState = activeWindowState {
            setActiveTab(tab, in: windowState)
        } else {
            let shouldLoad = loadImmediately ?? makeActive
            if shouldLoad, !tab.activePage.url.isDeepLink {
                pagePool.page(for: tab.activePage)
            }
        }

        // Notify extensions of new tab
        state.extensionManager?.dispatchTabOpened(tab)

        return tab
    }

    /// Creates a popup tab linked to an opener page.
    ///
    /// Popup tabs are inserted below the currently active tab (like cmd+click)
    /// rather than at the top of the list, providing better contextual proximity.
    @discardableResult
    func createPopupTab(
        in space: Space?,
        openerTabPageID: TabPage.ID,
        groupID: UUID?,
        url: URL,
        activate: Bool = true,
    ) -> Tab {
        let tab = createTab(
            url: url,
            in: space,
            groupID: groupID,
            makeActive: activate,
            loadImmediately: false, // WebKit handles popup navigation
            insertionStrategy: .afterActive,
        )

        tab.activePage.openerTabPageID = openerTabPageID

        return tab
    }

    // MARK: - Live Favorite Tab Operations

    /// Creates a global live favorite tab for a bookmark.
    ///
    /// Live favorite tabs are stored in `BrowserState.liveFavoriteTabs` and appear
    /// in the favorites grid across all spaces. They use global website data storage.
    ///
    /// - Parameters:
    ///   - bookmark: The bookmark to create a tab for.
    ///   - loadImmediately: Whether to create a WebPage and start loading immediately.
    ///     Set to `true` (default) for user-initiated actions.
    ///     Set to `false` for restore/launch to avoid blocking with GPU initialization.
    /// - Returns: The created live favorite tab.
    @discardableResult
    func createLiveFavoriteTab(for bookmark: Bookmark, loadImmediately: Bool = true) -> Tab {
        let tab = Tab(
            space: nil, // Live tabs don't belong to a space
            url: bookmark.url,
            title: bookmark.title,
            status: .liveFavorite,
            linkedBookmark: bookmark,
            position: state.liveFavoriteTabs.count,
        )

        // Copy favicon data from bookmark to tab page
        tab.activePage.faviconData = bookmark.faviconData
        tab.activePage.largeFaviconData = bookmark.largeFaviconData

        state.addLiveFavoriteTab(tab)
        state.modelContext.insert(tab)
        scheduleSave()

        if loadImmediately {
            // Create WebPage and start loading for user-initiated actions
            _ = pagePool.page(for: tab.activePage)
        }
        // Otherwise, WebPage is created lazily when the live favorite is activated
        // (see setActiveLiveFavoriteTab) to avoid GPU initialization during launch
        return tab
    }

    /// Closes a live favorite tab.
    ///
    /// Removes the tab from BrowserState and cleans up its session.
    ///
    /// - Parameter tab: The live favorite tab to close.
    func closeLiveFavoriteTab(_ tab: Tab) {
        guard tab.status == .liveFavorite else {
            Logger.warning("Attempted to close non-live-favorite tab as live favorite", category: Logger.tabs)
            return
        }

        pagePool.removePages(for: tab)
        state.removeLiveFavoriteTab(tab)
        state.modelContext.delete(tab)
        scheduleSave()
    }

    /// Closes a tab.
    ///
    /// Removes sessions, updates groups, handles undo registration,
    /// and activates an adjacent tab if needed.
    ///
    /// When archive is enabled and `bypassArchive` is false, the tab is moved
    /// to the archive instead of being permanently deleted. Archived tabs can
    /// be restored later.
    ///
    /// - Parameters:
    ///   - tab: Tab to close.
    ///   - registerUndo: Whether to register an undo action. Set to false for conversions
    ///     where the tab content is preserved elsewhere (e.g., converting to live favorite).
    ///   - bypassArchive: If true, permanently deletes the tab even when archive is enabled.
    ///     Use for "Delete Immediately" actions or when clearing the archive.
    func closeTab(_ tab: Tab, registerUndo: Bool = true, bypassArchive: Bool = false) {
        // Route through archive if enabled and not bypassing
        if state.settings.archiveEnabled, !bypassArchive, !tab.isArchived {
            // Capture state before archive modifies the tab
            guard let space = tab.space else { return }
            let mainTabIndex = space.mainTabs.firstIndex(of: tab) ?? 0
            let isReferenceTab = tab.isReferenceTab

            do {
                try archiveManager.archive(tab)

                // Trigger window state sync so active tab selection updates
                // Now that mainTabs/referenceTabs exclude archived tabs, the sync
                // will detect the archived tab as invalid and select a replacement
                mutationPipeline.withMutation { effects in
                    effects.didChangeList = true
                    if isReferenceTab {
                        effects.spaceIDsToSyncActiveRefTab.insert(space.id)
                    } else {
                        effects.spaceIDsToSyncActiveTab.insert(space.id)
                        effects.closedTabContexts[space.id] = TabMutationPipeline.ClosedTabContext(
                            tabID: tab.id,
                            mainTabIndex: mainTabIndex,
                        )
                    }
                }
                return
            } catch {
                // If archive fails, fall through to permanent close
                Logger.debug("Archive failed, closing permanently: \(error)", category: Logger.tabs)
            }
        }

        guard let space = tab.space,
              let index = space.tabs.firstIndex(of: tab) else {
            return
        }

        // Notify extensions before closing
        state.extensionManager?.dispatchTabClosed(tab, windowClosing: false)

        // Clear PiP state if this tab was the PiP source
        state.pipCoordinator.onTabClosed(tab.id)

        // Get index in mainTabs for proper adjacency fallback
        let mainTabIndex = space.mainTabs.firstIndex(of: tab) ?? 0

        let closedInfo = ClosedTabInfo(tab: tab)

        // Capture page IDs before closing, defer orphan cleanup
        let closingPageIDs = Set(tab.pages.map(\.id))
        if !closingPageIDs.isEmpty {
            DispatchQueue.main.async {
                self.orphanPopupChildrenDeferred(closingPageIDs: closingPageIDs)
            }
        }

        pagePool.removePages(for: tab)

        mutationPipeline.withMutation { effects in
            // Capture removal context before modifying state
            let wasPinned = tab.isPinned
            let wasInGroupID = tab.groupID

            if let groupID = tab.groupID,
               let group = space.groups.first(where: { $0.id == groupID }) {
                group._removeTab(tab)
            }

            space.tabs.remove(at: index)
            state.modelContext.delete(tab)
            // Pass mainTabIndex for smart adjacent tab selection in the pipeline
            effects.tabRemoved(tab, from: space, mainTabIndex: mainTabIndex)

            // Populate incremental removal tracking
            effects.removedItemID = tab.id
            effects.removalContext = TabMutationPipeline.RemovalContext(
                spaceID: space.id,
                wasPinned: wasPinned,
                wasInGroupID: wasInGroupID,
            )
        }

        if registerUndo {
            undoRedoManager.registerCloseTab(closedInfo)
        }
    }

    /// Requests to close a tab, prompting for confirmation if needed.
    ///
    /// Shows confirmation if the tab has active media playback or camera/microphone usage.
    /// Pages with `beforeunload` handlers may show a native "Leave site?" dialog.
    ///
    /// - Parameters:
    ///   - tab: Tab to close.
    ///   - bypassArchive: If true, permanently deletes the tab even when archive is enabled.
    func requestCloseTab(_ tab: Tab, bypassArchive: Bool = false) {
        requestCloseTabs([tab], bypassArchive: bypassArchive)
    }

    /// Requests to close multiple tabs, prompting for confirmation if any require it.
    ///
    /// Shows a confirmation dialog if any tabs have active media playback or
    /// camera/microphone usage. After user confirmation, each tab's `beforeunload`
    /// handler is invoked via WebKit's `_tryClose()` - pages may prevent closing
    /// if they have unsaved form data.
    ///
    /// - Parameters:
    ///   - tabs: Tabs to close.
    ///   - bypassArchive: If true, permanently deletes the tabs even when archive is enabled.
    func requestCloseTabs(_ tabs: [Tab], bypassArchive: Bool = false) {
        guard !tabs.isEmpty else { return }

        var reasons: [TabCloseReason] = []

        for tab in tabs {
            var tabReasons: [TabCloseReason.Reason] = []

            for page in tab.pages {
                guard let session = pagePool.existingPage(for: page) else {
                    continue
                }

                if session.audioState == .playing, !tabReasons.contains(.playingMedia) {
                    tabReasons.append(.playingMedia)
                }

                if session.isMicrophoneActive, !tabReasons.contains(.usingMicrophone) {
                    tabReasons.append(.usingMicrophone)
                }
                if session.isCameraActive, !tabReasons.contains(.usingCamera) {
                    tabReasons.append(.usingCamera)
                }
            }

            if !tabReasons.isEmpty {
                reasons.append(TabCloseReason(tab: tab, reasons: tabReasons))
            }
        }

        if reasons.isEmpty {
            closeTabsWithBeforeUnload(tabs, bypassArchive: bypassArchive)
            return
        }

        let tabsRequiringConfirmation = reasons.map(\.tab)
        pendingCloseConfirmation = CloseConfirmation(
            tabs: tabsRequiringConfirmation,
            reasons: reasons,
            allTabsToClose: tabs,
            bypassArchive: bypassArchive,
        )
    }

    /// Confirms the pending tab close after user acknowledged warnings.
    ///
    /// Clears `pendingCloseConfirmation` and attempts to close all tabs.
    /// Each tab's `beforeunload` handler is invoked - if the page prevents
    /// closing, that tab will remain open.
    func confirmCloseTabs() {
        guard let confirmation = pendingCloseConfirmation else { return }
        pendingCloseConfirmation = nil
        closeTabsWithBeforeUnload(confirmation.allTabsToClose, bypassArchive: confirmation.bypassArchive)
    }

    /// Cancels the pending tab close.
    ///
    /// Clears `pendingCloseConfirmation` without closing any tabs.
    func cancelCloseTabs() {
        pendingCloseConfirmation = nil
    }

    /// Restores a closed tab from undo info.
    ///
    /// Called by UndoRedoManager when undoing a tab close or reopening
    /// a recently closed tab.
    ///
    /// - Parameter info: Information about the closed tab to restore.
    func restoreTab(_ info: ClosedTabInfo) {
        guard let space = state.spaces.first(where: { $0.id == info.spaceID }) else {
            Logger.error("Cannot restore tab: space not found", category: Logger.tabs)
            return
        }

        let status: TabStatus = info.isPinned ? .pinned : .regular
        let tab = Tab(
            space: space,
            url: info.url,
            title: info.title,
            status: status,
            groupID: info.groupID,
            position: info.position,
        )
        tab.customName = info.customName
        tab.activePage.faviconData = info.faviconData

        let insertIndex = min(info.position, space.tabs.count)
        space.tabs.insert(tab, at: insertIndex)
        state.indexTab(tab)
        normalizePositions(in: space)

        if let groupID = info.groupID,
           let group = space.groups.first(where: { $0.id == groupID }) {
            group._addTab(tab)
        }

        state.modelContext.insert(tab)

        state.incrementListVersion()
        scheduleSave()

        if let windowState = activeWindowState {
            setActiveTab(tab, in: windowState)
        }

        Logger.info("Tab restored: \(info.title)", category: Logger.tabs)
    }

    /// Reopens the last closed tab.
    ///
    /// Delegates to UndoRedoManager which tracks recently closed tabs.
    func reopenLastClosedTab() {
        undoRedoManager.reopenLastClosedTab()
    }

    /// Restores a closed reference tab from undo info.
    ///
    /// Called by UndoRedoManager when undoing a reference tab close.
    ///
    /// - Parameter info: Information about the closed reference tab to restore.
    func restoreReferenceTab(_ info: ClosedTabInfo) {
        referencePaneManager.restoreReferenceTab(info)
    }

    /// Duplicates a tab.
    ///
    /// Archived tabs cannot be duplicated. Use ``TabArchiveManager/restoreTab(_:)`` instead.
    ///
    /// - Returns: The duplicated tab, or the original tab if duplication failed.
    @discardableResult
    func duplicateTab(_ tab: Tab) -> Tab {
        // Archived tabs cannot be duplicated
        guard !tab.isArchived else {
            Logger.debug("Cannot duplicate archived tab", category: Logger.tabs)
            return tab
        }

        guard let space = tab.space,
              let originalIndex = space.tabs.firstIndex(of: tab) else {
            return tab
        }

        let duplicated = Tab(
            space: space,
            url: tab.activePage.url,
            title: tab.activePage.title,
            status: tab.status,
            groupID: tab.groupID,
            position: originalIndex + 1,
        )
        duplicated.activePage.faviconData = tab.activePage.faviconData
        duplicated.activePage.largeFaviconData = tab.activePage.largeFaviconData
        duplicated.isUnread = true

        space.tabs.insert(duplicated, at: originalIndex + 1)
        state.indexTab(duplicated)
        normalizePositions(in: space)

        if let groupID = tab.groupID,
           let group = space.groups.first(where: { $0.id == groupID }) {
            group._addTab(duplicated)
        }

        state.modelContext.insert(duplicated)
        state.incrementListVersion()
        scheduleSave()

        Logger.info("Tab duplicated: \(tab.activePage.title)", category: Logger.tabs)
        return duplicated
    }

    // MARK: - Preview Pages

    /// Creates a preview page for link preview popover.
    ///
    /// This creates a transient TabPage stored in ``Tab/previewPage``, allowing
    /// the preview to use the full WebPage pipeline (content blocking, site
    /// settings, etc.) while remaining convertible to a real tab.
    ///
    /// - Important: We intentionally do NOT set `tabPage.tab = tab` because
    ///   SwiftData's inverse relationship would automatically add the preview
    ///   page to `tab.pages`, breaking `activePage` and `visiblePages`.
    ///   The preview page accesses its parent tab via the reverse lookup
    ///   through `tab.previewPage` when needed.
    ///
    /// - Parameters:
    ///   - url: The URL to preview.
    ///   - tab: The parent tab that owns this preview.
    /// - Returns: The created WebPage for display in the preview popover.
    func createPreviewPage(for url: URL, in tab: Tab) -> WebPage? {
        // Clear any existing preview page first
        clearPreviewPage(for: tab)

        // Create a TabPage WITHOUT setting the tab relationship.
        // Setting tabPage.tab = tab would trigger SwiftData's inverse relationship,
        // automatically adding the preview page to tab.pages and corrupting activePage.
        let tabPage = TabPage(url: url, title: url.host ?? "Preview", layoutPosition: .single)

        // Store in the transient previewPage property instead
        tab.previewPage = tabPage

        // Create the WebPage through the normal pipeline
        return pagePool.page(for: tabPage)
    }

    /// Clears a tab's preview page and its associated WebPage.
    ///
    /// - Parameter tab: The tab whose preview should be cleared.
    func clearPreviewPage(for tab: Tab) {
        guard let previewPage = tab.previewPage else { return }
        pagePool.removePage(for: previewPage)
        tab.previewPage = nil
    }

    /// Converts a preview page into a real tab.
    ///
    /// Preserves the existing TabPage and its WebPage session, avoiding the need
    /// to reload the page. The preview's WKWebView is reused in the new tab.
    ///
    /// - Parameters:
    ///   - tab: The tab containing the preview.
    ///   - makeActive: Whether to activate the new tab.
    /// - Returns: The newly created tab, or nil if no preview exists.
    @discardableResult
    func convertPreviewToTab(from tab: Tab, makeActive: Bool = true) -> Tab? {
        guard let previewPage = tab.previewPage,
              let targetSpace = tab.space ?? activeWindowState?.activeSpace else {
            return nil
        }

        // Detach preview page from the source tab (don't remove WebPage from pool)
        tab.previewPage = nil

        // Pinned/live favorite tabs have stale position and group info — use prepend
        let isContained = tab.isPinned || tab.isLiveFavorite
        let groupID: UUID? = isContained ? nil : tab.groupID
        let strategy: TabPositioner.InsertionStrategy = isContained ? .prepend : .afterActive

        // Calculate insertion position
        let activeTabID = activeWindowState?.activeTabID
        let insertion = insertionPosition(
            in: targetSpace,
            isPinned: false,
            groupID: groupID,
            strategy: strategy,
            activeTabID: activeTabID,
        )

        // Create a new tab that will own the existing TabPage
        let newTab = Tab(
            space: targetSpace,
            url: previewPage.url,
            title: previewPage.title,
            status: .regular,
            groupID: groupID,
            position: insertion.position,
        )

        // Replace the auto-created primary page with the preview page.
        // This preserves the TabPage ID, so the WebPage in pagePool stays connected.
        let autoCreatedPage = newTab.pages.first
        newTab.pages = [previewPage]
        previewPage.position = .single

        mutationPipeline.withMutation { effects in
            targetSpace.tabs.insert(newTab, at: insertion.index)

            state.modelContext.insert(newTab)

            // Delete the auto-created page that we replaced
            if let autoCreatedPage {
                state.modelContext.delete(autoCreatedPage)
            }

            let needsNormalize = insertion.index < targetSpace.tabs.count - 1
            effects.tabAdded(newTab, in: targetSpace, normalize: needsNormalize)
        }

        if makeActive, let windowState = activeWindowState {
            setActiveTab(newTab, in: windowState)
        }

        // Notify extensions of new tab
        state.extensionManager?.dispatchTabOpened(newTab)

        Logger.info("Converted preview to tab: \(previewPage.title)", category: Logger.tabs)

        return newTab
    }
}
