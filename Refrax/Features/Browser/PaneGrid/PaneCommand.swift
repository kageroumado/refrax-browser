import Foundation

/// A verb on the current tab's panes, the same from the View menu, the Command Lens, a row's
/// menu, the page card, and `refrax-ctl`.
nonisolated enum PaneCommand: Hashable, Sendable {
    /// Lift the panes apart for editing.
    case edit
    /// Commit the edit and lay the panes back.
    case finishEditing
    /// Edit, or finish editing.
    case toggleEditing
    /// Open a page from the Command Lens beside the focused pane, on `edge`.
    case openBeside(PaneEdge)
    /// Give every pane but the active one a tab of its own.
    case separate

    /// What the command says in a menu or the lens.
    var title: String {
        switch self {
        case .edit: "Edit Split View"
        case .finishEditing: "Done Editing Split View"
        case .toggleEditing: "Edit Split View"
        case let .openBeside(edge):
            switch edge {
            case .leading: "Open Page on the Left"
            case .trailing: "Open Page on the Right"
            case .top: "Open Page Above"
            case .bottom: "Open Page Below"
            }
        case .separate: "Separate Panes into Tabs"
        }
    }

    var symbol: String {
        switch self {
        case .edit, .toggleEditing: "rectangle.split.2x2"
        case .finishEditing: "checkmark.rectangle"
        case let .openBeside(edge):
            switch edge {
            case .leading: "rectangle.lefthalf.inset.filled"
            case .trailing: "rectangle.righthalf.inset.filled"
            case .top: "rectangle.tophalf.inset.filled"
            case .bottom: "rectangle.bottomhalf.inset.filled"
            }
        case .separate: "rectangle.split.2x1.slash"
        }
    }
}

@MainActor
extension PaneCommand {
    /// Runs `command` on the window's current tab. ``openBeside(_:)`` sets where the next page
    /// from the lens goes and opens the lens.
    static func perform(_ command: PaneCommand, in windowState: WindowState, tabs: TabManager) {
        switch command {
        case .edit:
            windowState.enterLayoutMode()
        case .finishEditing:
            windowState.exitLayoutMode()
        case .toggleEditing:
            windowState.toggleLayoutMode()
        case let .openBeside(edge):
            guard windowState.activeTab != nil else { return }
            windowState.newPanePlacement = placement(beside: edge, in: windowState)
            windowState.openCommandLens()
        case .separate:
            guard let tab = windowState.activeTab, tab.pages.count > 1 else { return }
            windowState.exitLayoutMode(animated: false)
            tabs.separatePanes(of: tab)
        }
    }

    /// Whether `command` can run on the window's current tab now.
    static func isAvailable(_ command: PaneCommand, in windowState: WindowState) -> Bool {
        guard let tab = windowState.activeTab else { return false }
        switch command {
        case .edit: return !windowState.isInLayoutMode
        case .finishEditing: return windowState.isInLayoutMode
        case .toggleEditing: return true
        case .openBeside: return tab.pages.count < PaneGrid.capacity
        case .separate: return tab.pages.count > 1
        }
    }

    /// Where a page opened beside the focused pane on `edge` goes: that pane's half at `edge`
    /// when it is two cells thick that way, else the empty cell beyond it, else the
    /// automatic place.
    static func placement(beside edge: PaneEdge, in windowState: WindowState) -> PanePlacement {
        guard let tab = windowState.activeTab else { return .automatic }
        let grid = windowState.paneEditor.session.flatMap { $0.tabID == tab.id ? $0.grid : nil } ?? tab.paneGrid
        let focused = windowState.focusedPage.flatMap { grid.contains($0.id) ? $0.id : nil } ?? tab.activePage.id
        return placement(beside: focused, at: edge, in: grid)
    }

    /// Where a page opened beside `pageID` on `edge` goes in `grid`.
    static func placement(beside pageID: UUID, at edge: PaneEdge, in grid: PaneGrid) -> PanePlacement {
        let split = PaneSplit(target: pageID, edge: edge)
        if grid.canSplit(split) {
            return .split(split)
        }
        if let span = grid.span(of: pageID) {
            let beyond = span.cells.compactMap { $0.neighbor(across: edge) }.first { grid.page(at: $0) == nil }
            if let beyond {
                return .cell(beyond)
            }
        }
        return .automatic
    }
}
