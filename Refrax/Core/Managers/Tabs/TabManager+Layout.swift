import Foundation
import SwiftData

// MARK: - Reference Pane

extension TabManager {
    /// Adds a tab to the reference pane.
    ///
    /// - Parameters:
    ///   - url: URL to load.
    ///   - title: Tab title.
    ///   - space: Space to add to. If nil, uses active window's space.
    ///   - windowState: The window to activate the tab in. If nil, uses the active window.
    /// - Returns: The created Tab, or nil if limit reached.
    @discardableResult
    func addReferenceTab(url: URL, title: String = "New Tab", in space: Space? = nil, windowState: WindowState? = nil) -> Tab? {
        guard let targetSpace = space ?? activeWindowState?.activeSpace else {
            return nil
        }
        return referencePaneManager.addReferenceTab(url: url, title: title, in: targetSpace, windowState: windowState)
    }

    /// Closes a reference tab.
    func closeReferenceTab(_ tab: Tab) {
        referencePaneManager.closeReferenceTab(tab)
    }

    /// Duplicates a reference tab.
    ///
    /// Creates a new reference tab with the same URL and title as the original.
    /// Returns nil if the reference tab limit is reached.
    @discardableResult
    func duplicateReferenceTab(_ tab: Tab) -> Tab? {
        guard tab.isReferenceTab, let space = tab.space else { return nil }
        return addReferenceTab(
            url: tab.activePage.url,
            title: tab.displayTitle,
            in: space,
        )
    }

    /// Sets the active reference tab in a specific window.
    ///
    /// - Parameters:
    ///   - tab: The reference tab to activate.
    ///   - windowState: The window to activate the tab in. If nil, uses the active window.
    func setActiveReferenceTab(_ tab: Tab, in windowState: WindowState) {
        referencePaneManager.setActiveReferenceTab(tab, in: windowState)
    }

    // MARK: - Tab Transfer (Main ↔ Reference)

    /// Moves a tab to the reference pane, preserving the same Tab object.
    ///
    /// The tab is removed from `space.tabs` and added to `space.referenceTabs`.
    /// Session state is preserved by keeping the same Tab instance.
    ///
    /// - Parameters:
    ///   - tab: The tab to move.
    ///   - windowState: The window to activate the tab in. If nil, uses the active window.
    func moveTabToReferencePane(_ tab: Tab, in windowState: WindowState? = nil) {
        referencePaneManager.moveTabToReferencePane(tab, in: windowState)
    }

    /// Moves a reference tab to the main area, preserving the same Tab object.
    ///
    /// The tab is removed from `space.referenceTabs` and added to `space.tabs`.
    /// Session state is preserved by keeping the same Tab instance.
    /// Window state is synchronized to update active reference tab selections.
    func moveReferenceTabToMainArea(_ referenceTab: Tab, makeActive: Bool = true) {
        guard let space = referenceTab.space else { return }

        // Calculate insertion index based on current active tab
        let insertionIndex: Int = if let windowState = windowSync.findWindowState(for: space),
                                     let activeTabID = windowState.activeTabID(for: space.id),
                                     let activeIndex = space.tabs.firstIndex(where: { $0.id == activeTabID }) {
            activeIndex + 1
        } else {
            space.tabs.count
        }

        let moved = referencePaneManager.moveReferenceTabToMainArea(
            referenceTab,
            insertionIndex: insertionIndex,
        ) { [self] space in
            positioner.normalize(space: space, force: true)
        }

        if moved, makeActive,
           let windowState = windowSync.findWindowState(for: space) ?? activeWindowState {
            setActiveTab(referenceTab, in: windowState)
        }
    }

    /// Moves a page from a split-view tab to the reference pane.
    func movePageToReferencePane(_ page: TabPage, from tab: Tab) {
        guard let space = tab.space else { return }

        // Single-page tab: move the whole tab
        guard tab.pages.count > 1 else {
            moveTabToReferencePane(tab)
            return
        }

        guard tab.pages.contains(where: { $0.id == page.id }),
              space.referenceTabs.count < Self.maxReferenceTabs else {
            return
        }

        // Remove page from source tab
        tab._removePage(page)

        if tab.activePage.id == page.id, let first = tab.pages.first {
            tab._setActivePage(first)
        }

        // Create new reference tab that will contain this page
        let referenceTab = Tab(space: space, isReferenceTab: true)
        referenceTab.position = space.referenceTabs.count

        // Move the existing page to the new tab (no need to create a new TabPage)
        page.position = .single
        referenceTab.pages = [page]

        space.tabs.append(referenceTab)
        state.indexTab(referenceTab)
        state.modelContext.insert(referenceTab)
        // No need to delete page - it's just moved to a new parent

        // Only set active in the current window (per-window selection)
        windowSync.setActiveReferenceTabIDInWindow(for: space, newTabID: referenceTab.id)

        state.incrementListVersion()
        scheduleSave()

        Logger.info("Moved page to reference pane: \(page.title)", category: Logger.tabs)
    }

    /// Moves a reference tab into an existing tab as a split-view page.
    ///
    /// Window state is synchronized to update active reference tab selections.
    func moveReferenceTabToPage(_ referenceTab: Tab, into targetTab: Tab, at position: PanePosition? = nil) {
        guard let space = referenceTab.space,
              referenceTab.isReferenceTab,
              space.referenceTabs.contains(where: { $0.id == referenceTab.id }),
              targetTab.pages.count < 4 else {
            return
        }

        // Capture position before removal (for smart adjacent selection)
        let closedIndex = referenceTab.position
        let targetPosition = position ?? nextAvailablePosition(in: targetTab)
        let sourcePage = referenceTab.activePage

        // Remove from tabs relationship
        space.tabs.removeAll { $0.id == referenceTab.id }
        state.removeFromIndex(referenceTab)

        // Sync reference tab selection - use smart adjacent selection
        windowSync.syncInvalidActiveReferenceTabIDs(for: space, closedIndex: closedIndex)

        // Renumber remaining reference tabs
        for (index, refTab) in space.referenceTabs.enumerated() {
            refTab.position = index
        }

        sourcePage.position = targetPosition
        targetTab._addPage(sourcePage, at: targetPosition)
        setupLayoutIfNeeded(for: targetTab, newPage: sourcePage, position: targetPosition)

        state.modelContext.delete(referenceTab)

        targetTab._setActivePage(sourcePage)
        state.incrementListVersion()
        scheduleSave()

        Logger.info("Moved reference tab into split view: \(sourcePage.title)", category: Logger.tabs)
    }

    // MARK: - Multi-Page Layouts

    /// Adds a page to a tab at the specified position.
    @discardableResult
    func addPageToTab(_ tab: Tab, url: URL, at position: PanePosition) -> TabPage {
        let page = TabPage(url: url, title: url.host ?? "New Page", layoutPosition: position)
        tab._addPage(page, at: position)
        state.incrementListVersion()
        scheduleSave()
        return page
    }

    /// Moves a single-page tab into a layout pane of another tab.
    ///
    /// This transfers the WebPage session to the new TabPage without reloading
    /// or closing the history entry, then closes the source tab.
    ///
    /// - Parameters:
    ///   - sourceTab: The single-page tab to move. Must have exactly one page.
    ///   - destinationTab: The tab to add the page to.
    ///   - position: The layout position for the new page.
    /// - Returns: The new TabPage in the destination tab, or `nil` if the operation failed.
    @discardableResult
    func moveTabToLayout(_ sourceTab: Tab, into destinationTab: Tab, at position: PanePosition) -> TabPage? {
        guard sourceTab.pages.count == 1, !sourceTab.isMultiPage else {
            Logger.warning("Cannot move multi-page tab into layout", category: Logger.tabs)
            return nil
        }

        let sourcePage = sourceTab.activePage

        let newPage = TabPage(
            url: sourcePage.url,
            title: sourcePage.title,
            layoutPosition: position,
        )
        newPage.faviconData = sourcePage.faviconData
        newPage.largeFaviconData = sourcePage.largeFaviconData

        destinationTab._addPage(newPage, at: position)

        pagePool.transferPage(from: sourcePage, to: newPage, preserveHistory: true)

        closeTabWithoutRemovingPages(sourceTab)

        state.incrementListVersion()
        scheduleSave()

        Logger.info("Moved tab '\(sourcePage.title)' into layout at \(position)", category: Logger.tabs)

        return newPage
    }

    /// Removes a page from a tab.
    func removePageFromTab(_ tab: Tab, page: TabPage) {
        pagePool.removePage(for: page)
        tab._removePage(page)
        state.incrementListVersion()
        scheduleSave()
    }

    /// Moves a page from a layout tab to a new standalone tab.
    ///
    /// This transfers the WebPage session to the new tab without reloading
    /// or closing the history entry.
    ///
    /// - Parameters:
    ///   - page: The page to move.
    ///   - sourceTab: The tab containing the page.
    ///   - makeActive: Whether to activate the new tab.
    /// - Returns: The new Tab, or `nil` if the operation failed.
    @discardableResult
    func movePageToNewTab(_ page: TabPage, from sourceTab: Tab, makeActive: Bool = false) -> Tab? {
        guard sourceTab.pages.count > 1,
              sourceTab.pages.contains(where: { $0.id == page.id }),
              let space = sourceTab.space else {
            return nil
        }

        sourceTab._removePage(page)

        if sourceTab.activePage.id == page.id, let first = sourceTab.pages.first {
            sourceTab._setActivePage(first)
        }

        let newTab = Tab(space: space, url: page.url, title: page.title, position: space.tabs.count)
        newTab.activePage.faviconData = page.faviconData
        newTab.activePage.largeFaviconData = page.largeFaviconData

        pagePool.transferPage(from: page, to: newTab.activePage, preserveHistory: true)

        state.indexTab(newTab)
        state.modelContext.insert(newTab)
        state.modelContext.delete(page)

        if makeActive, let windowState = windowSync.findWindowState(for: space) {
            setActiveTab(newTab, in: windowState)
        }

        state.incrementListVersion()
        scheduleSave()

        Logger.info("Moved page '\(page.title)' to new tab", category: Logger.tabs)

        return newTab
    }

    /// Sets the active page in a multi-page tab.
    func setActivePage(in tab: Tab, page: TabPage) {
        tab._setActivePage(page)
        scheduleSave()
    }
}
