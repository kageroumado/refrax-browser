import Foundation
import SwiftData

extension TabManager {
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
        guard sourceTab.space != nil, sourceTab.pages.count == 1, !sourceTab.isMultiPage else {
            Logger.warning("Combining requires a space-bound single-page tab", category: Logger.tabs)
            return nil
        }

        let sourcePage = sourceTab.activePage
        let undo = TabLayoutUndo(source: sourceTab, destination: destinationTab, windows: layoutWindows(in: sourceTab.space))

        state.extensionManager?.dispatchTabClosed(sourceTab, windowClosing: false)

        let newPage = TabPage(
            url: sourcePage.url,
            title: sourcePage.title,
            layoutPosition: position,
        )
        newPage.copyContent(from: sourcePage)

        destinationTab._addPage(newPage, at: position)

        pagePool.transferPage(from: sourcePage, to: newPage, preserveHistory: true)

        closeTabWithoutRemovingPages(sourceTab)

        registerLayoutUndo(undo, joinedPageID: newPage.id, position: position)

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
        newTab.activePage.copyContent(from: page)

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
