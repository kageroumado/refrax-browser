import SwiftUI

/// The page card's ⋯ popover: the page menu, then the tab's own actions under a divider.
///
/// The page menu is ``PageMenuContent`` bound to the card's page; the tab rows are
/// ``TabActions`` on the page card surface, composed in the cards' group order and drawn as
/// popover rows. Every row closes the popover before its action runs.
struct PageCardOptionsPopover: View {
    let tab: Tab
    let area: CGRect
    let dismiss: () -> Void
    let onWebpageSettings: () -> Void
    let onShowCookies: () -> Void
    @Environment(WindowState.self) private var windowState
    @Environment(TabManager.self) private var tabs
    @Environment(BookmarksManager.self) private var bookmarks
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(SharingCoordinator.self) private var sharing
    @Environment(ScreenshotCoordinator.self) private var screenshots
    @Environment(RecordingCoordinator.self) private var recording
    @Environment(DownloadManager.self) private var downloads
    @Environment(ExtensionManager.self) private var extensions
    @Environment(ReaderModeManager.self) private var readerMode
    @Environment(SiteSettingsManager.self) private var siteSettings
    @Environment(WebPagePool.self) private var pagePool

    private var actions: PageMenuActions {
        PageMenuActions(
            webPage: pagePool.existingPage(for: tab.activePage),
            url: tab.activePage.url,
            windowState: windowState,
            sharing: sharing,
            screenshots: screenshots,
            recording: recording,
            downloads: downloads,
            extensions: extensions,
            readerMode: readerMode,
            siteSettings: siteSettings,
            pagePool: pagePool,
        )
    }

    var body: some View {
        let actions = actions
        VStack(spacing: 0) {
            PageMenuContent(
                actions: actions,
                isReaderAvailable: readerMode.cachedAvailability(for: tab.activePage.url),
                dismiss: dismiss,
                onFindOnPage: { windowState.showFindNavigator() },
                onReaderMode: {
                    Task(name: "Toggle Reader from the page card") { await actions.toggleReader() }
                },
                onWebpageSettings: onWebpageSettings,
                onShowCookies: onShowCookies,
            )
            Divider()
                .padding(.horizontal, PageMenuContent.Layout.popoverPadding)
            VStack(spacing: PageMenuContent.Layout.itemSpacing) {
                MenuTreeView(tree: Self.tabTree(
                    for: tab, area: area, windowState: windowState, tabs: tabs, bookmarks: bookmarks, canvas: canvas,
                ).closing(with: dismiss))
            }
            .buttonStyle(.pageMenuRow)
            .menuStyle(.button)
            .padding(PageMenuContent.Layout.popoverPadding)
            .frame(width: PageMenuContent.Layout.width)
        }
    }

    /// The tab's actions as the popover lists them.
    static func tabTree(
        for tab: Tab,
        area: CGRect,
        windowState: WindowState,
        tabs: TabManager,
        bookmarks: BookmarksManager,
        canvas: TabCanvasManager,
    ) -> MenuTree {
        let object = TabActions(tab: tab, surface: .pageCard, windowState: windowState, tabs: tabs, bookmarks: bookmarks, canvas: canvas, area: area)
        return MenuComposer.compose(object.actions(), groupOrder: PageActionsMenu.groupOrder)
    }
}

@MainActor
private extension MenuTree {
    /// The same rows, each running `dismiss` before its action.
    func closing(with dismiss: @escaping () -> Void) -> MenuTree {
        MenuTree(sections: sections.map { $0.closing(with: dismiss) })
    }
}

@MainActor
private extension MenuTree.Section {
    func closing(with dismiss: @escaping () -> Void) -> MenuTree.Section {
        MenuTree.Section(nodes: nodes.map { node in
            switch node {
            case var .action(action):
                let execute = action.execute
                action.execute = {
                    dismiss()
                    execute()
                }
                return .action(action)
            case let .submenu(submenu):
                return .submenu(MenuTree.Submenu(
                    id: submenu.id, title: submenu.title, symbol: submenu.symbol,
                    sections: submenu.sections.map { $0.closing(with: dismiss) },
                ))
            }
        })
    }
}
