import AppKit
import Foundation

/// The menu of a tab row on an island: the page's actions and the tab's, with what a row can
/// do within its islands; or, for several chosen rows, what they can do together. Composed
/// in the cards' group order, so New Island with This Tab sits right under the page's
/// essentials on every surface.
@MainActor
struct IslandRowMenu {
    let tab: Tab
    let island: Island
    let islands: IslandController
    let windowState: WindowState
    let tabs: TabManager
    let bookmarks: BookmarksManager
    let canvas: TabCanvasManager
    let sharing: SharingCoordinator
    let area: CGRect
    /// Rename… edits the row's title in place.
    var onRename: (() -> Void)?

    func tree() -> MenuTree {
        let chosen = islands.actionTabs(for: tab.id)
        if chosen.count > 1 {
            return MenuComposer.compose(selectionActions(chosen), groupOrder: PageActionsMenu.groupOrder)
        }
        let page = PageActions(tab: tab, windowState: windowState, tabs: tabs, sharing: sharing)
        let object = TabActions(
            tab: tab, surface: .floatingCard, windowState: windowState, tabs: tabs, bookmarks: bookmarks, canvas: canvas, area: area,
            onRename: onRename,
        )
        return MenuComposer.compose(page.actions() + object.actions() + islandActions() + paneActions(), groupOrder: PageActionsMenu.groupOrder)
    }

    /// What a row can do within its island: float, move, leave, close around it. New Island
    /// with This Tab comes with the tab's own actions (``TabActions/tableActions()``).
    func islandActions() -> [MenuAction] {
        let tabID = tab.id
        let islands = islands
        var actions = [
            MenuAction("island.float", "Open as Card", symbol: "rectangle.on.rectangle", group: .move) { [area] in
                islands.detach(tabID, at: CGPoint(x: area.midX, y: area.midY))
            },
        ]
        let others = islands.islands.filter { $0.id != island.id }
        if !others.isEmpty {
            actions.append(MenuAction("island.moveTo", "Move to Island", symbol: "arrow.right.square", group: .move, children: others.map { other in
                MenuAction("island.moveTo.\(other.id)", other.title, symbol: "circle.fill", group: .move) {
                    islands.moveTab(tabID, toEndOf: other.id)
                }
            }))
        }
        if !island.isDefault {
            actions.append(MenuAction("island.leave", "Remove from Island", symbol: "minus.square", group: .move) { islands.removeFromIsland(tabID) })
        }
        if tabs.state.settings.archiveEnabled {
            let tab = tab
            actions.append(MenuAction("island.archive", "Archive Tab", symbol: "archivebox", group: .close) { islands.archive([tab]) })
        }
        actions.append(MenuAction("island.closeOthers", "Close Other Tabs in Island", symbol: "xmark.rectangle", group: .close) { islands.closeOthers(than: tabID) })
        actions.append(MenuAction("island.closeAbove", "Close Tabs Above", symbol: "arrow.up.to.line", group: .close) { islands.close(below: false, of: tabID) })
        actions.append(MenuAction("island.closeBelow", "Close Tabs Below", symbol: "arrow.down.to.line", group: .close) { islands.close(below: true, of: tabID) })
        return actions
    }

    /// What several chosen rows can do together, a new island first.
    func selectionActions(_ chosen: [Tab]) -> [MenuAction] {
        let n = chosen.count
        let islands = islands
        var actions = [
            MenuAction("island.selection.new", "New Island from \(n) Tabs", symbol: "plus.rectangle.on.rectangle", group: .island) {
                islands.makeIsland(from: chosen.map(\.id))
            },
        ]
        if let current = tab.space {
            let tabs = tabs
            let windowState = windowState
            let targets = tabs.spaceManager.spaces.filter { $0.id != current.id }.map { space in
                MenuAction("island.selection.space.\(space.id)", space.name, symbol: space.isEmoji ? nil : space.iconName, group: .move) {
                    Task(name: "Move tabs to space") { await tabs.moveTabsUnlocking(chosen, to: space, confirmingIn: windowState) }
                }
            }
            if !targets.isEmpty {
                actions.append(MenuAction("island.selection.space", "Move \(n) Tabs to Space", symbol: "square.stack.3d.up", group: .move, children: targets))
            }
        }
        if tabs.state.settings.archiveEnabled {
            actions.append(MenuAction("island.selection.archive", "Archive \(n) Tabs", symbol: "archivebox", group: .close) { islands.archive(chosen) })
        }
        let tabs = tabs
        actions.append(MenuAction("island.selection.close", "Close \(n) Tabs", symbol: "xmark", group: .close, isDestructive: true) {
            tabs.requestCloseTabs(chosen)
        })
        return actions
    }
}
