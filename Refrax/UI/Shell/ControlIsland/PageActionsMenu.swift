import AppKit
import SwiftUI

/// Page actions shared by the control panel and spatial tabs.
struct PageActionsMenu: NSViewRepresentable {
    let tab: Tab
    let area: CGRect
    @Environment(WindowState.self) private var windowState
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(TabManager.self) private var tabs
    @Environment(BookmarksManager.self) private var bookmarks
    @Environment(ReaderModeManager.self) private var readerMode
    @Environment(SharingCoordinator.self) private var sharing
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
        var items: [any MenuItemConvertible] = [
            MenuItem("Copy Address", systemImage: "link") { actions.copyLink() },
            MenuItem("Copy as Markdown Link", systemImage: "text.quote") { actions.copyMarkdownLink() },
            MenuItem("Share…", systemImage: "square.and.arrow.up") {
                sharing.shareURL(URL(string: tabs.copyableURL(for: tab)) ?? tab.activePage.url, title: tab.activePage.title)
            },
        ]
        if tab.id == windowState.activeTabID, let page {
            items.append(MenuItem("Find on Page…", systemImage: "magnifyingglass", keyEquivalent: "f") { windowState.showFindNavigator() })
            items.append(MenuItem(readerMode.isReaderActive(for: tab.id) ? "Leave Reader" : "Reader", systemImage: "text.page") {
                Task(name: "Toggle reader from page card") {
                    if await readerMode.toggleReader(for: page) == .tooLong { windowState.showToast("This page is too long for Reader") }
                }
            })
        }
        if let bookmark = tab.linkedBookmark, actions.isFavorite {
            items.append(MenuItem("Update Saved Address", systemImage: "bookmark") {
                bookmark.url = tab.activePage.url
                bookmarks.refreshFavoritesCache()
                tabs.state.scheduleSave()
            })
        }
        if tab.id != windowState.activeTabID {
            items.append(MenuItem("Look", systemImage: "eye") { canvas.lookAtFloatingTab(tab) })
        }
        items.append(MenuDivider())
        items.append(MenuItem(placement.isCompact ? "Show as Preview" : "Show as Compact Tab", systemImage: "rectangle.expand.vertical") {
            var next = placement
            next.setCompact(!next.isCompact, in: area)
            canvas.updateFloatingPlacement(next, for: tab)
            if tab.id == windowState.activeTabID { canvas.toggleFloatingTabs() }
        })
        items.append(MenuItem(placement.isPinned ? "Hide Preview" : "Keep Visible", systemImage: "pin") {
            var next = placement
            next.isPinned.toggle()
            if next.isPinned { next.isCompact = false }
            canvas.updateFloatingPlacement(next, for: tab)
        })
        items.append(MenuItem(placement.region == nil ? "Keep Part Visible… (Experimental)" : "Adjust Region…", systemImage: "crop") {
            canvas.beginRegionSelection(for: tab)
        })
        if placement.region != nil {
            items.append(SubMenu("Preview Zoom") {
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
            })
        }
        if !tab.isLiveFavorite, tab.space?.id == windowState.activeSpaceID {
            items.append(MenuItem(canvas.selectedFloatingTabIDs.contains(tab.id) ? "Deselect for Group" : "Select for Group") {
                if canvas.selectedFloatingTabIDs.contains(tab.id) { canvas.selectedFloatingTabIDs.remove(tab.id) }
                else { canvas.selectedFloatingTabIDs.insert(tab.id) }
            })
            if canvas.selectedFloatingTabIDs.count > 1 {
                items.append(MenuItem("Group Selected Tabs") { canvas.groupFloatingSelection() })
            }
        }
        if placement.isPinned, tab.space?.dataStoreMode != .private {
            items.append(MenuItem(placement.showsInEverySpace == true ? "Show in This Space" : "Show in Every Space") {
                var next = placement
                next.showsInEverySpace = placement.showsInEverySpace != true
                canvas.updateFloatingPlacement(next, for: tab)
            })
        }
        items.append(MenuDivider())
        items.append(MenuItem("Duplicate Tab", systemImage: "plus.square.on.square") { actions.duplicate() })
        items.append(MenuItem("Close Tab", systemImage: "xmark") { tabs.requestCloseTab(tab) })
        return items.asNSMenu()
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

    required init?(coder: NSCoder) { nil }

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
