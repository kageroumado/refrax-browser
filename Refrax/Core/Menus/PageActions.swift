import AppKit
import Foundation

/// Menu actions on a tab's active page: copy, share, find, reload.
struct PageActions {
    let tab: Tab
    let windowState: WindowState
    let tabs: TabManager
    let sharing: SharingCoordinator

    func actions() -> [MenuAction] {
        let behaviors = ControlIslandTabActions(tab: tab, windowState: windowState, tabs: tabs, bookmarks: tabs.bookmarksManager)
        var actions: [MenuAction] = [
            MenuAction("page.copyAddress", "Copy Address", symbol: "link", group: .copy, isPrimary: true) { behaviors.copyLink() },
            MenuAction("page.copyMarkdownLink", "Copy as Markdown Link", symbol: "text.quote", group: .copy) { behaviors.copyMarkdownLink() },
            MenuAction("page.share", "Share…", symbol: "square.and.arrow.up", group: .share) {
                sharing.shareURL(URL(string: tabs.copyableURL(for: tab)) ?? tab.activePage.url, title: tab.activePage.title)
            },
        ]
        if tab.id == windowState.activeTabID, tabs.pagePool.existingPage(for: tab.activePage) != nil {
            actions.append(MenuAction("page.find", "Find on Page…", symbol: "magnifyingglass", key: .init("f"), group: .read) {
                windowState.showFindNavigator()
            })
        }
        return actions
    }
}
