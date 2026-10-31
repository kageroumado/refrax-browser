import Foundation
import SwiftData

extension TabManager {
    // MARK: - Multi-Page Layouts

    /// Adds a new page for `url` to a tab as a pane at `placement`.
    @discardableResult
    func addPageToTab(_ tab: Tab, url: URL, at placement: PanePlacement) -> TabPage {
        let page = TabPage(url: url, title: url.host ?? "New Page")
        tab._addPage(page, at: placement)
        editLayouts(of: tab) { $0.insert(page.id, joining: tab.id, at: placement) }
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
    ///   - placement: Where the page goes among the destination's panes.
    /// - Returns: The new TabPage in the destination tab, or `nil` if the operation failed.
    @discardableResult
    func moveTabToLayout(_ sourceTab: Tab, into destinationTab: Tab, at placement: PanePlacement) -> TabPage? {
        guard sourceTab.space != nil, sourceTab.pages.count == 1, !sourceTab.isMultiPage, sourceTab.id != destinationTab.id else {
            Logger.warning("Combining requires a space-bound single-page tab", category: Logger.tabs)
            return nil
        }
        guard destinationTab.pages.count < PaneGrid.capacity else {
            Logger.warning("A tab holds at most \(PaneGrid.capacity) panes", category: Logger.tabs)
            return nil
        }

        let sourcePage = sourceTab.activePage
        let undo = TabLayoutUndo(source: sourceTab, destination: destinationTab, windows: layoutWindows(in: sourceTab.space))

        state.extensionManager?.dispatchTabClosed(sourceTab, windowClosing: false)

        let newPage = TabPage(url: sourcePage.url, title: sourcePage.title)
        newPage.copyContent(from: sourcePage)

        destinationTab._addPage(newPage, at: placement)
        editLayouts(of: destinationTab) { $0.insert(newPage.id, joining: destinationTab.id, at: placement) }

        pagePool.transferPage(from: sourcePage, to: newPage, preserveHistory: true)

        closeTabWithoutRemovingPages(sourceTab)

        registerLayoutUndo(undo, joinedPageID: newPage.id, placement: placement)

        state.incrementListVersion()
        scheduleSave()

        Logger.info("Moved tab '\(sourcePage.title)' into layout at \(placement)", category: Logger.tabs)

        return newPage
    }

    /// Removes a page from a tab.
    func removePageFromTab(_ tab: Tab, page: TabPage) {
        pagePool.removePage(for: page)
        editLayouts(of: tab) { $0.remove(page.id) }
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

        editLayouts(of: sourceTab) { $0.remove(page.id) }
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
        editLayouts(of: tab, animated: false) { $0.focus(page.id) }
        scheduleSave()
    }

    /// Splits a tab of several pages into one tab per page, each page keeping its live
    /// session; the tab keeps its active page.
    func separatePanes(of tab: Tab) {
        let others = tab.pages.filter { $0.id != tab.activePage.id }
        for page in others {
            movePageToNewTab(page, from: tab)
        }
    }

    /// Runs `edit` on every window editing `tab` in layout mode, so a page that joins or
    /// leaves the tab meanwhile joins or leaves the edit too.
    func editLayouts(of tab: Tab, animated: Bool = true, _ edit: (inout PaneLayoutEditor) -> Bool) {
        for window in layoutWindows(in: tab.space) where window.paneEditor.isEditing(tab: tab.id) {
            window.editLayout(animated: animated, edit)
        }
    }
}
