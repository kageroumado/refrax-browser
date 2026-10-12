import AppKit
import SwiftUI

/// Page actions shared by the control panel and spatial tabs.
struct PageActionsMenu: View {
    let tab: Tab
    let area: CGRect
    @Environment(WindowState.self) private var windowState
    @Environment(TabCanvasManager.self) private var canvas
    @Environment(TabManager.self) private var tabs
    @Environment(BookmarksManager.self) private var bookmarks

    var body: some View {
        ControlIslandTabMenuButton(state: windowState.controlIsland.tabInfo, makeMenu: menu, onClose: { canvas.menuTabID = nil }, onOpen: { canvas.menuTabID = tab.id })
            .frame(width: 28, height: 28)
            .accessibilityLabel("Actions for \(tab.displayTitle)")
    }

    private func menu() -> NSMenu {
        let actions = ControlIslandTabActions(tab: tab, windowState: windowState, tabs: tabs, bookmarks: bookmarks)
        let placement = canvas.floatingPlacement(for: tab)
        var items: [any MenuItemConvertible] = [
            MenuItem(actions.isFavorite ? "Remove Favorite" : "Favorite", systemImage: actions.isFavorite ? "star.slash" : "star") {
                actions.toggleFavorite()
            },
            MenuItem("Copy Address", systemImage: "link") { actions.copyLink() },
        ]
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
        items.append(MenuItem("Reload", systemImage: "arrow.clockwise") { _ = tabs.pagePool.existingPage(for: tab.activePage)?.reload() })
        items.append(MenuItem("Duplicate Tab", systemImage: "plus.square.on.square") { actions.duplicate() })
        items.append(MenuItem("Close Tab", systemImage: "xmark") { tabs.requestCloseTab(tab) })
        return items.asNSMenu()
    }
}
