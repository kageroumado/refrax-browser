import AppKit
import Foundation

/// Menu actions on a tab as an object: its favorite, its floating placement, its selection on
/// the desk, its duplicate, its close, and Look.
///
/// Placement actions need the canvas and the area the card is laid out in, so they appear only
/// on card surfaces that pass both.
struct TabActions {
    let tab: Tab
    let surface: MenuSurface
    let windowState: WindowState
    let tabs: TabManager
    let bookmarks: BookmarksManager
    var canvas: TabCanvasManager?
    var area: CGRect = .zero

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
        actions.append(MenuAction("tab.duplicate", "Duplicate Tab", symbol: "plus.square.on.square", group: .tab) { behaviors.duplicate() })
        if surface.isCard {
            actions.append(MenuAction("tab.close", "Close Tab", symbol: "xmark", group: .close) { tabs.requestCloseTab(tab) })
        }
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
