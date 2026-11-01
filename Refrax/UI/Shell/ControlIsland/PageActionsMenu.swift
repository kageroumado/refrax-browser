import AppKit
import SwiftUI

/// The ⋯ menu of a floating card on the desk or in Recent: page actions and tab actions,
/// composed and shown as a native menu so the card's hover and "menu is up" state hold while
/// it tracks. The page card beside the rail opens ``PageCardOptionsPopover`` instead.
struct PageActionsMenu: NSViewRepresentable {
    /// Group order of a selection's menu on the islands.
    static let groupOrder: [MenuGroupID] = [.copy, .share, .read, .open, .island, .preview, .move, .tab, .window, .close]

    /// The cards' menus in the island rows' skeleton (``IslandRowMenu/layout``): where the page
    /// shows, what to copy, the tab's own verbs, Close Tab, arranging, then the rare rest.
    /// Placement beyond Keep Visible folds into Preview.
    static let cardLayout = MenuLayout(
        sections: [
            [
                .action("tab.look"), .action("tab.keepVisible"),
                .submenu(
                    id: "group.preview", title: MenuGroupID.preview.title, symbol: MenuGroupID.preview.symbol,
                    actions: FloatingCardShape.allCases.map { "tab.shape.\($0.rawValue)" }
                        + ["tab.dock.leading", "tab.dock.trailing", "tab.undock", "tab.region", "tab.zoom"],
                ),
            ],
            [.action("page.copyAddress"), .action("page.copyMarkdownLink"), .action("page.share"), .action("page.find")],
            [.action("tab.rename"), .action("tab.duplicate"), .action("tab.favorite"), .action("tab.unfavorite"), .action("tab.mute")],
            [.action("tab.close")],
            [.action("tab.island.new"), .action("tab.moveToSpace"), .action("tab.moveToNewWindow")],
            [
                .submenu(id: "more", title: "More", symbol: "ellipsis.circle", actions: [
                    "tab.unread", "tab.muteOthers", "tab.goHome", "tab.setHome", "tab.reflectedWindow",
                ]),
            ],
        ],
        overflow: "more",
    )

    let tab: Tab
    let surface: MenuSurface
    let area: CGRect
    @Environment(WindowState.self) private var windowState
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(TabManager.self) private var tabs
    @Environment(BookmarksManager.self) private var bookmarks
    @Environment(SharingCoordinator.self) private var sharing
    @Environment(\.appearsActive) private var appearsActive

    func makeNSView(context _: Context) -> PageActionsButton {
        PageActionsButton()
    }

    func updateNSView(_ button: PageActionsButton, context _: Context) {
        button.makeTree = {
            Self.tree(
                for: tab, surface: surface, area: area, windowState: windowState, tabs: tabs,
                bookmarks: bookmarks, canvas: canvas, sharing: sharing,
            )
        }
        button.infoState = windowState.controlIsland.tabInfo
        button.onClose = { canvas.menuTabID = nil }
        button.onOpen = { canvas.menuTabID = tab.id }
        button.contentTintColor = appearsActive ? .labelColor : .secondaryLabelColor
        button.setAccessibilityLabel("Actions for \(tab.displayTitle)")
    }

    static func dismantleNSView(_ button: PageActionsButton, coordinator _: ()) {
        button.cancelPresentation()
    }

    /// The menu for `tab` on `surface`, composed from ``PageActions`` and ``TabActions``.
    static func tree(
        for tab: Tab,
        surface: MenuSurface,
        area: CGRect,
        windowState: WindowState,
        tabs: TabManager,
        bookmarks: BookmarksManager,
        canvas: TabCanvasManager,
        sharing: SharingCoordinator,
    ) -> MenuTree {
        let page = PageActions(tab: tab, windowState: windowState, tabs: tabs, sharing: sharing)
        // A card on screen edits its own title; a row in Recent has none to edit.
        let editsInPlace = canvas.visibleFloatingTabs.contains { $0.id == tab.id }
        let object = TabActions(
            tab: tab, surface: surface, windowState: windowState, tabs: tabs, bookmarks: bookmarks, canvas: canvas, area: area,
            onRename: editsInPlace ? { canvas.renamingTabID = tab.id } : nil,
        )
        return cardLayout.tree(page.actions() + object.actions())
    }
}

/// The ⋯ button: pops its tree up below itself and keeps the card's presented state in step
/// with the menu's tracking.
final class PageActionsButton: NSButton, NSMenuDelegate {
    var makeTree: () -> MenuTree = { .empty }
    var onClose: () -> Void = {}
    var onOpen: () -> Void = {}
    weak var infoState: ControlIslandTabInfoState?
    private let presenter = MenuPresenter()

    init() {
        super.init(frame: .zero)
        isBordered = false
        image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More tab actions")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        imagePosition = .imageOnly
        focusRingType = .none
        setAccessibilityLabel("More tab actions")
        toolTip = "More tab actions"
        target = self
        action = #selector(presentMenu(_:))
    }

    required init?(coder _: NSCoder) {
        nil
    }

    var isPresentingMenu: Bool {
        presenter.presentedMenu != nil
    }

    @objc
    private func presentMenu(_: Any?) {
        presenter.present(makeTree(), at: .zero, in: self, delegate: self)
    }

    func cancelPresentation() {
        presenter.cancel()
        infoState?.isMenuPresented = false
    }

    func menuWillOpen(_: NSMenu) {
        infoState?.isMenuPresented = true
        onOpen()
    }

    func menuDidClose(_: NSMenu) {
        infoState?.isHovered = false
        infoState?.isMenuPresented = false
        onClose()
    }
}
