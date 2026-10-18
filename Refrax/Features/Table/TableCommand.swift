import Foundation

/// A command the Command Lens and menus offer, run on the window's ``IslandController``.
nonisolated enum TableCommand: Hashable, Sendable {
    /// Step to the neighboring chip (⌃⌘ arrows).
    case focus(TableDirection)
    /// Make a new island from the current chip and the chips below it.
    case newIsland
}

extension IslandController {
    /// Runs a lens or menu command on the current chip.
    func perform(_ command: TableCommand) {
        switch command {
        case let .focus(direction):
            step(direction)
        case .newIsland:
            if let tab = currentTab {
                makeIsland(from: tab.id)
            }
        }
    }
}
