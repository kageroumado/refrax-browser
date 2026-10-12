import AppKit
import SwiftUI

/// Page actions shared by the control panel and spatial tabs, ordered by ``PageActionsMenuPlan``.
struct PageActionsMenu: NSViewRepresentable {
    let tab: Tab
    let area: CGRect
    let host: PageActionsMenuPlan.Host
    @Environment(WindowState.self) private var windowState
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(TabManager.self) private var tabs
    @Environment(BookmarksManager.self) private var bookmarks
    @Environment(ReaderModeManager.self) private var readerMode
    @Environment(SharingCoordinator.self) private var sharing
    @Environment(BrowserSettings.self) private var settings
    @Environment(\.appearsActive) private var appearsActive

    func makeNSView(context _: Context) -> PageActionsButton {
        PageActionsButton(frame: .zero, pullsDown: true)
    }

    func updateNSView(_ button: PageActionsButton, context _: Context) {
        button.makeMenu = menu
        button.infoState = windowState.controlIsland.tabInfo
        button.onClose = { canvas.menuTabID = nil }
        button.onOpen = { canvas.menuTabID = tab.id }
        button.contentTintColor = appearsActive ? .labelColor : .secondaryLabelColor
        button.setAccessibilityLabel("Actions for \(tab.displayTitle)")
    }

    static func dismantleNSView(_ button: PageActionsButton, coordinator _: ()) {
        button.cancelPresentation()
    }

    private func menu() -> NSMenu {
        let actions = ControlIslandTabActions(tab: tab, windowState: windowState, tabs: tabs, bookmarks: bookmarks)
        let placement = canvas.floatingPlacement(for: tab)
        let page = tabs.pagePool.existingPage(for: tab.activePage)
        let context = PageActionsMenuPlan.Context(
            host: host,
            isCurrentPage: tab.id == windowState.activeTabID,
            hasPage: page != nil,
            isReaderActive: readerMode.isReaderActive(for: tab.id),
            canUpdateSavedAddress: tab.linkedBookmark != nil && actions.isFavorite,
            isCompact: placement.isCompact,
            isPinned: placement.isPinned,
            hasRegion: placement.region != nil,
            regionsEnabled: settings.floatingTabRegionsEnabled,
            canGroup: !tab.isLiveFavorite && tab.space?.id == windowState.activeSpaceID,
            isSelectedForGroup: canvas.selectedFloatingTabIDs.contains(tab.id),
            selectionCount: canvas.selectedFloatingTabIDs.count,
            canShowInEverySpace: placement.isPinned && tab.space?.dataStoreMode != .private,
            showsInEverySpace: placement.showsInEverySpace == true,
        )
        let items = PageActionsMenuPlan.entries(for: context).map { entry in
            item(for: entry, title: PageActionsMenuPlan.title(of: entry, in: context), actions: actions, placement: placement, page: page)
        }
        return items.asNSMenu()
    }

    private func item(
        for entry: PageActionsMenuPlan.Entry, title: String, actions: ControlIslandTabActions, placement: FloatingTabPlacement, page: WebPage?,
    ) -> any MenuItemConvertible {
        switch entry {
        case .copyAddress:
            MenuItem(title, systemImage: "link") { actions.copyLink() }
        case .copyMarkdownLink:
            MenuItem(title, systemImage: "text.quote") { actions.copyMarkdownLink() }
        case .share:
            MenuItem(title, systemImage: "square.and.arrow.up") {
                sharing.shareURL(URL(string: tabs.copyableURL(for: tab)) ?? tab.activePage.url, title: tab.activePage.title)
            }
        case .findOnPage:
            MenuItem(title, systemImage: "magnifyingglass", keyEquivalent: "f") { windowState.showFindNavigator() }
        case .reader:
            MenuItem(title, systemImage: "text.page") {
                guard let page else { return }
                Task(name: "Toggle reader from page card") {
                    if await readerMode.toggleReader(for: page) == .tooLong {
                        windowState.showToast("This page is too long for Reader")
                    }
                }
            }
        case .updateSavedAddress:
            MenuItem(title, systemImage: "bookmark") {
                guard let bookmark = tab.linkedBookmark else { return }
                bookmark.url = tab.activePage.url
                bookmarks.refreshFavoritesCache()
                tabs.state.scheduleSave()
            }
        case .look:
            MenuItem(title, systemImage: "eye") { canvas.lookAtFloatingTab(tab) }
        case .divider:
            MenuDivider()
        case .keepVisible:
            MenuItem(title, systemImage: "pin") {
                var next = placement
                next.isPinned.toggle()
                if next.isPinned {
                    next.isCompact = false
                }
                canvas.updateFloatingPlacement(next, for: tab)
            }
        case .presentation:
            MenuItem(title, systemImage: placement.isCompact ? "rectangle.expand.vertical" : "rectangle.compress.vertical") {
                var next = placement
                next.setCompact(!next.isCompact, in: area)
                canvas.updateFloatingPlacement(next, for: tab)
                if tab.id == windowState.activeTabID {
                    canvas.toggleFloatingTabs()
                }
            }
        case .region:
            MenuItem(title, systemImage: "crop") { canvas.beginRegionSelection(for: tab) }
        case .previewZoom:
            SubMenu(title) {
                for scale in [0.5, 0.75, 1.0, 1.25, 1.5] {
                    MenuItem("\(Int(scale * 100))%") {
                        var next = placement
                        next.region?.scale = scale
                        canvas.updateFloatingPlacement(next, for: tab)
                    }
                }
                MenuItem("Show Whole Page") {
                    var next = placement
                    next.region = nil
                    canvas.updateFloatingPlacement(next, for: tab)
                }
            }
        case .selectForGroup:
            MenuItem(title) {
                if canvas.selectedFloatingTabIDs.contains(tab.id) {
                    canvas.selectedFloatingTabIDs.remove(tab.id)
                } else {
                    canvas.selectedFloatingTabIDs.insert(tab.id)
                }
            }
        case .groupSelectedTabs:
            MenuItem(title) { canvas.groupFloatingSelection() }
        case .showInEverySpace:
            MenuItem(title) {
                var next = placement
                next.showsInEverySpace = placement.showsInEverySpace != true
                canvas.updateFloatingPlacement(next, for: tab)
            }
        case .duplicateTab:
            MenuItem(title, systemImage: "plus.square.on.square") { actions.duplicate() }
        case .closeTab:
            MenuItem(title, systemImage: "xmark") { tabs.requestCloseTab(tab) }
        }
    }
}

final class PageActionsButton: NSPopUpButton, NSMenuDelegate {
    override init(frame buttonFrame: NSRect, pullsDown flag: Bool) {
        super.init(frame: buttonFrame, pullsDown: flag)
        isBordered = false
        addItem(withTitle: "")
        let icon = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "More tab actions")?
            .withSymbolConfiguration(.init(pointSize: 13, weight: .semibold))
        item(at: 0)?.image = icon
        imagePosition = .imageOnly
        focusRingType = .none
        setAccessibilityLabel("More tab actions")
        toolTip = "More tab actions"
        (cell as? NSPopUpButtonCell)?.arrowPosition = .noArrow
        menu?.autoenablesItems = false
        menu?.delegate = self
    }

    required init?(coder _: NSCoder) {
        nil
    }

    var makeMenu: () -> NSMenu = { NSMenu() }
    var onClose: () -> Void = {}
    var onOpen: () -> Void = {}
    weak var infoState: ControlIslandTabInfoState?
    func menuNeedsUpdate(_ menu: NSMenu) {
        let icon = item(at: 0)?.image
        menu.removeAllItems()
        let titleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        titleItem.image = icon
        menu.addItem(titleItem)
        let actions = makeMenu()
        for item in actions.items {
            actions.removeItem(item)
            menu.addItem(item)
        }
    }

    func cancelPresentation() {
        menu?.cancelTracking()
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
