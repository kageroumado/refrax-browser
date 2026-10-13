import AppKit
import Foundation

/// Menu actions on a tab as an object: its favorite, its floating placement, its selection on
/// the desk, its name and unread mark, the space and window it lives in, its duplicate, its
/// close, and Look.
///
/// Placement actions need the canvas and the area the card is laid out in, so they appear only
/// on card surfaces that pass both. The sidebar row brings its own identity, organization, and
/// window verbs, so the card verbs appear only on cards.
struct TabActions {
    let tab: Tab
    let surface: MenuSurface
    let windowState: WindowState
    let tabs: TabManager
    let bookmarks: BookmarksManager
    var canvas: TabCanvasManager?
    var area: CGRect = .zero
    /// Rename… where the surface edits the name in place; without it, a sheet asks.
    var onRename: (() -> Void)?

    func actions() -> [MenuAction] {
        let behaviors = ControlIslandTabActions(tab: tab, windowState: windowState, tabs: tabs, bookmarks: bookmarks)
        var actions: [MenuAction] = []
        if surface.isCard, tab.id != windowState.activeTabID, let canvas {
            actions.append(MenuAction("tab.look", "Look, then Return", symbol: "eye", group: .open) { canvas.lookAtFloatingTab(tab) })
        }
        if surface.isCard, let canvas {
            actions += placementActions(canvas: canvas)
            actions += selectionActions(canvas: canvas)
        }
        if surface.isCard, let bookmark = tab.linkedBookmark, behaviors.isFavorite {
            actions.append(MenuAction("tab.updateSavedAddress", "Update Saved Address", symbol: "bookmark", group: .tab) {
                bookmark.url = tab.activePage.url
                bookmarks.refreshFavoritesCache()
                tabs.state.scheduleSave()
            })
        }
        if surface.isCard {
            actions += identityActions()
        }
        actions.append(MenuAction("tab.duplicate", "Duplicate Tab", symbol: "plus.square.on.square", group: .tab) { behaviors.duplicate() })
        if surface.isCard {
            actions += spaceActions() + windowActions()
            actions.append(MenuAction("tab.close", "Close Tab", symbol: "xmark", group: .close) { tabs.requestCloseTab(tab) })
        }
        return actions
    }

    // MARK: - Name, unread, space, and window

    private func identityActions() -> [MenuAction] {
        let unread = tab.isUnread
        return [
            MenuAction("tab.rename", "Rename…", symbol: "pencil", group: .tab) {
                if let onRename {
                    onRename()
                } else {
                    TabRenameAlert.present(for: tab, tabs: tabs, in: windowState.window)
                }
            },
            MenuAction("tab.unread", unread ? "Mark as Read" : "Mark as Unread", symbol: unread ? "circlebadge" : "circlebadge.fill", group: .tab) {
                if unread {
                    tabs.markAsRead(tab)
                } else {
                    tabs.markAsUnread(tab)
                }
            },
        ]
    }

    /// Move to Space lists every other space; favorites belong to every space and stay put.
    private func spaceActions() -> [MenuAction] {
        guard !tab.isLiveFavorite, let current = tab.space else { return [] }
        let destinations = tabs.spaceManager.spaces.filter { $0.id != current.id }
        guard !destinations.isEmpty else { return [] }
        let targets = destinations.map { space in
            MenuAction("tab.moveToSpace.\(space.id)", space.name, symbol: space.isEmoji ? nil : space.iconName, group: .move) {
                tabs.moveTabs([tab], to: space)
            }
        }
        return [MenuAction("tab.moveToSpace", "Move to Space", symbol: "square.stack.3d.up", group: .move, children: targets)]
    }

    private func windowActions() -> [MenuAction] {
        var actions: [MenuAction] = []
        if !tab.isLiveFavorite, tab.space != nil {
            actions.append(MenuAction("tab.moveToNewWindow", "Move to New Window", symbol: "macwindow.badge.plus", key: .init("n", modifiers: [.command, .option]), group: .window) {
                tabs.moveTabToNewWindow(tab, from: windowState)
            })
        }
        actions.append(MenuAction("tab.reflectedWindow", "Open Reflected Window", symbol: "rectangle.inset.filled.on.rectangle", group: .window) {
            let pagePool = tabs.pagePool
            guard let page = pagePool.existingPage(for: tab.activePage) ?? pagePool.page(for: tab.activePage) else { return }
            tabs.windowManager.createReflectedWindow(for: page)
        })
        return actions
    }

    /// Region placement (Keep Part Visible, Adjust Region, Preview Zoom) stays behind its flag.
    private var regionsEnabled: Bool {
        tabs.state.settings.floatingTabRegionsEnabled
    }

    private func placementActions(canvas: TabCanvasManager) -> [MenuAction] {
        let placement = canvas.floatingPlacement(for: tab)
        var actions: [MenuAction] = [
            MenuAction("tab.keepVisible", placement.isPinned ? "Hide Preview" : "Keep Visible", symbol: "pin", group: .preview, isPrimary: true) {
                var next = placement
                next.isPinned.toggle()
                if next.isPinned {
                    next.isCompact = false
                }
                canvas.updateFloatingPlacement(next, for: tab)
            },
        ]
        if surface == .pageCard {
            let title = placement.isCompact ? "Show as Preview" : "Show as Compact Tab"
            actions.append(MenuAction("tab.compact", title, symbol: "rectangle.expand.vertical", group: .preview) {
                var next = placement
                next.setCompact(!next.isCompact, in: area)
                canvas.updateFloatingPlacement(next, for: tab)
                if tab.id == windowState.activeTabID {
                    canvas.toggleFloatingTabs()
                }
            })
        }
        guard regionsEnabled else { return actions }
        let regionTitle = placement.region == nil ? "Keep Part Visible… (Experimental)" : "Adjust Region…"
        actions.append(MenuAction("tab.region", regionTitle, symbol: "crop", group: .preview) { canvas.beginRegionSelection(for: tab) })
        if placement.region != nil {
            let zoomLevels = [0.5, 0.75, 1.0, 1.25, 1.5].map { scale in
                MenuAction("tab.zoom.\(Int(scale * 100))", "\(Int(scale * 100))%", group: .preview) {
                    var next = placement
                    next.region?.scale = scale
                    canvas.updateFloatingPlacement(next, for: tab)
                }
            }
            let wholePage = MenuAction("tab.zoom.wholePage", "Show Whole Page", group: .preview) {
                var next = placement
                next.region = nil
                canvas.updateFloatingPlacement(next, for: tab)
            }
            actions.append(MenuAction("tab.zoom", "Preview Zoom", symbol: "plus.magnifyingglass", group: .preview, children: zoomLevels + [wholePage]))
        }
        return actions
    }

    private func selectionActions(canvas: TabCanvasManager) -> [MenuAction] {
        var actions: [MenuAction] = []
        if !tab.isLiveFavorite, tab.space?.id == windowState.activeSpaceID {
            let isSelected = canvas.selectedFloatingTabIDs.contains(tab.id)
            actions.append(MenuAction("tab.select", isSelected ? "Deselect for Group" : "Select for Group", symbol: "checkmark.circle", group: .move) {
                if isSelected {
                    canvas.selectedFloatingTabIDs.remove(tab.id)
                } else {
                    canvas.selectedFloatingTabIDs.insert(tab.id)
                }
            })
            if canvas.selectedFloatingTabIDs.count > 1 {
                actions.append(MenuAction("tab.groupSelection", "Group Selected Tabs", symbol: "rectangle.3.group", group: .move) { canvas.groupFloatingSelection() })
            }
        }
        let placement = canvas.floatingPlacement(for: tab)
        if placement.isPinned, tab.space?.dataStoreMode != .private {
            let everywhere = placement.showsInEverySpace == true
            actions.append(MenuAction("tab.everySpace", everywhere ? "Show in This Space" : "Show in Every Space", symbol: "square.on.square", group: .move) {
                var next = placement
                next.showsInEverySpace = !everywhere
                canvas.updateFloatingPlacement(next, for: tab)
            })
        }
        return actions
    }
}
