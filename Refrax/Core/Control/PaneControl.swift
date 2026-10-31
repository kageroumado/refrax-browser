import Foundation
import RefraxProtocol

/// The pane actions of `refrax-ctl islands`: layout mode, a pane's moves, its leaving, the
/// splits, and joining a page beside a pane; and the current tab's panes for the state.
@MainActor
enum PaneControl {
    typealias ControlError = RefraxControlServer.ControlError

    /// Runs a pane action on `windowState`'s current tab; `source` is the tab `join-page` joins.
    static func perform(
        _ params: ControlRequest.IslandsParams, source: Tab?, in windowState: WindowState, tabs: TabManager, islands: IslandController,
    ) throws {
        guard let tab = windowState.activeTab else { throw ControlError.noActiveTab }
        switch params.action {
        case .editPanes:
            windowState.enterLayoutMode()
        case .donePanes:
            windowState.exitLayoutMode(animated: false)
        case .movePane:
            let pageID = try pane(params.pane, of: tab, in: windowState)
            guard let name = params.direction, let cell = GridCell(name: name) else {
                throw ControlError.invalidParams("The cell must be top-left, top-right, bottom-left, or bottom-right")
            }
            try editing(windowState) { $0.move(pageID, to: cell) }
        case .growPane, .shrinkPane:
            let pageID = try pane(params.pane, of: tab, in: windowState)
            let edge = try edge(params.direction)
            if params.action == .growPane {
                try editing(windowState) { $0.expand(pageID, toward: edge) }
            } else {
                try editing(windowState) { $0.shrink(pageID, from: edge) }
            }
        case .separatePane:
            let pageID = try pane(params.pane, of: tab, in: windowState)
            guard tab.pages.count > 1, let page = tab.pages.first(where: { $0.id == pageID }) else {
                throw ControlError.invalidParams("A tab's only pane stays with it")
            }
            tabs.movePageToNewTab(page, from: tab)
        case .splits:
            guard let column = params.x, let row = params.y else { throw ControlError.invalidParams("--to COLUMN,ROW is required") }
            if windowState.paneEditor.isEditing(tab: tab.id) {
                windowState.editLayout(animated: false) { editor in
                    editor.setSplits(column: column, row: row)
                    return true
                }
            } else {
                tab.storePaneSplits(column: column, row: row)
                tabs.scheduleSave()
            }
        case .joinPage:
            guard let source else { throw ControlError.invalidParams("--tab is required") }
            try join(source, to: tab, at: params, in: windowState, islands: islands)
        default:
            break
        }
    }

    /// The current tab's panes, their cells and frames in the window.
    static func info(in windowState: WindowState, islands: IslandController) -> CTL.PanesInfo? {
        guard let tab = windowState.activeTab else { return nil }
        let session = windowState.paneEditor.session.flatMap { $0.tabID == tab.id ? $0 : nil }
        let target = IslandController.paneTarget(of: tab, editing: session, page: islands.pageArea)
        let active = session?.activePaneID ?? tab.activePage.id
        let panes = target.grid.pageIDs.compactMap { id -> CTL.PaneInfo? in
            guard let page = tab.pages.first(where: { $0.id == id }), let span = target.grid.span(of: id) else { return nil }
            let frame = target.geometry.frame(of: span)
            return CTL.PaneInfo(
                pageID: id.uuidString, title: page.title, cells: span.cells.map(\.description), isActive: id == active,
                x: frame.minX, y: frame.minY, width: frame.width, height: frame.height,
            )
        }
        return CTL.PanesInfo(
            tabID: tab.id.uuidString,
            isEditing: session != nil,
            columnSplit: Double(target.geometry.columnSplit),
            rowSplit: Double(target.geometry.rowSplit),
            panes: panes,
            emptyCells: target.grid.emptyCells.map(\.description),
        )
    }

    /// Joins `source` to `tab` beside `--pane`, or the focused pane, on `--direction`.
    private static func join(_ source: Tab, to tab: Tab, at params: ControlRequest.IslandsParams, in windowState: WindowState, islands: IslandController) throws {
        guard islands.canJoin(source.id, with: tab.id) else {
            throw ControlError.invalidParams("The tab must be a single page and the current tab have room for another pane")
        }
        let edge = try edge(params.direction)
        let grid = windowState.paneEditor.session.flatMap { $0.tabID == tab.id ? $0.grid : nil } ?? tab.paneGrid
        let target = try params.pane.map { try pane($0, of: tab, in: windowState) }
            ?? windowState.focusedPage.flatMap { grid.contains($0.id) ? $0.id : nil } ?? tab.activePage.id
        guard let placement = PaneCommand.placement(beside: target, at: edge, in: grid) else {
            throw ControlError.invalidParams("That side of the pane has no room for another")
        }
        islands.joinPage(source.id, at: placement)
    }

    // MARK: - References

    /// A pane by its page id or a prefix of it, its index in reading order, or part of its title.
    static func pane(_ ref: String?, of tab: Tab, in windowState: WindowState) throws -> UUID {
        guard let ref else { throw ControlError.invalidParams("--pane is required") }
        let grid = windowState.paneEditor.session.flatMap { $0.tabID == tab.id ? $0.grid : nil } ?? tab.paneGrid
        let ordered = grid.pageIDs
        let needle = ref.lowercased()
        if let index = Int(ref), ordered.indices.contains(index) {
            return ordered[index]
        }
        if needle.count >= 4, let id = ordered.first(where: { $0.uuidString.lowercased().hasPrefix(needle) }) {
            return id
        }
        if let page = tab.pages.first(where: { ordered.contains($0.id) && $0.title.lowercased().contains(needle) }) {
            return page.id
        }
        throw ControlError.invalidParams("No pane of the current tab matches '\(ref)'")
    }

    private static func edge(_ word: String?) throws -> PaneEdge {
        guard let word, let edge = PaneEdge(word: word) else {
            throw ControlError.invalidParams("Direction must be left, right, up, or down")
        }
        return edge
    }

    /// Runs an edit of layout mode, which must be on.
    private static func editing(_ windowState: WindowState, _ edit: (inout PaneLayoutEditor) -> Bool) throws {
        guard windowState.isInLayoutMode else {
            throw ControlError.invalidParams("Layout mode is off; run edit-panes first")
        }
        guard windowState.editLayout(animated: false, edit) else {
            throw ControlError.invalidParams("The grid has no room for that")
        }
    }
}
