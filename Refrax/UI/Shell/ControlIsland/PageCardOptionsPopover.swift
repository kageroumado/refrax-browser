import SwiftUI

/// The page card's ⋯ popover: the page menu, then the tab's own actions under a divider.
///
/// The page menu is ``PageMenuContent`` bound to the card's page; the tab rows are
/// ``TabActions`` on the page card surface, composed in the cards' group order and drawn as
/// popover rows. Every row closes the popover before its action runs, except Rename…, which
/// turns the popover into the name field.
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
    @Environment(SiteSettingsManager.self) private var siteSettings
    @Environment(WebPagePool.self) private var pagePool
    @State private var isRenaming = false

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
            siteSettings: siteSettings,
            pagePool: pagePool,
        )
    }

    var body: some View {
        if isRenaming {
            PageCardRenameField(tab: tab, dismiss: dismiss)
        } else {
            options
        }
    }

    private var options: some View {
        let actions = actions
        return VStack(spacing: 0) {
            PageMenuContent(
                actions: actions,
                dismiss: dismiss,
                onFindOnPage: { windowState.showFindNavigator() },
                onWebpageSettings: onWebpageSettings,
                onShowCookies: onShowCookies,
            )
            Divider()
                .padding(.horizontal, PageMenuContent.Layout.popoverPadding)
            VStack(spacing: PageMenuContent.Layout.itemSpacing) {
                MenuTreeView(tree: Self.tabTree(
                    for: tab, area: area, windowState: windowState, tabs: tabs, bookmarks: bookmarks, canvas: canvas,
                    onRename: { isRenaming = true },
                ).closing(with: dismiss, except: ["tab.rename"]))
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
        onRename: (() -> Void)? = nil,
    ) -> MenuTree {
        let object = TabActions(
            tab: tab, surface: .pageCard, windowState: windowState, tabs: tabs, bookmarks: bookmarks, canvas: canvas, area: area,
            onRename: onRename,
        )
        return MenuComposer.compose(object.actions(), groupOrder: PageActionsMenu.groupOrder)
    }
}

@MainActor
private extension MenuTree {
    /// The same rows, each running `dismiss` before its action, except the rows in `kept`.
    func closing(with dismiss: @escaping () -> Void, except kept: Set<String> = []) -> MenuTree {
        MenuTree(sections: sections.map { $0.closing(with: dismiss, except: kept) })
    }
}

@MainActor
private extension MenuTree.Section {
    func closing(with dismiss: @escaping () -> Void, except kept: Set<String>) -> MenuTree.Section {
        MenuTree.Section(nodes: nodes.map { node in
            switch node {
            case let .action(action) where kept.contains(action.id):
                return .action(action)
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
                    sections: submenu.sections.map { $0.closing(with: dismiss, except: kept) },
                ))
            }
        })
    }
}

/// The options popover as the tab's name field: Return keeps the name, Escape leaves it, and
/// an empty name goes back to the page's title.
private struct PageCardRenameField: View {
    let tab: Tab
    let dismiss: () -> Void
    @Environment(TabManager.self) private var tabs
    @State private var draft = ""
    @FocusState private var isFocused: Bool

    private enum Layout {
        static let width: CGFloat = 240
        static let padding: CGFloat = 12
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rename Tab")
                .font(.headline)
            TextField("Tab Name", text: $draft, prompt: Text(tab.activePage.title))
                .textFieldStyle(.roundedBorder)
                .focused($isFocused)
                .onSubmit {
                    TabRenaming.apply(draft, to: tab, tabs: tabs)
                    dismiss()
                }
                .onExitCommand(perform: dismiss)
        }
        .padding(Layout.padding)
        .frame(width: Layout.width)
        .onAppear {
            draft = tab.displayTitle
            isFocused = true
        }
    }
}
