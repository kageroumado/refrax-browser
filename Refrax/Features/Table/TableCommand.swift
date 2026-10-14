import Foundation

/// A table command the Command Lens offers, run on the window's ``TableController``.
nonisolated enum TableCommand: Hashable, Sendable {
    /// Focus the neighboring tab (⌃⌘ arrows).
    case focus(TableDirection)
    /// Move the current slab on the table (⌃⌘⇧ arrows).
    case moveSlab(TableDirection)
    /// Cycle the current slab's width (⌃⌘R).
    case cycleWidth
    /// Fill the width with the current slab, or return it to its preset (⌃⌘⇧F).
    case toggleFill
    /// Give the current slab a preset width.
    case setWidth(TableWidth)
}

extension TableController {
    /// Runs a lens command on the current slab.
    func perform(_ command: TableCommand) {
        switch command {
        case let .focus(direction):
            step(direction)
        case let .moveSlab(direction):
            moveFocusedSlab(direction)
        case .cycleWidth:
            cycleWidth()
        case .toggleFill:
            toggleFill()
        case let .setWidth(width):
            if let tab = currentTab {
                setWidth(width, of: tab)
            }
        }
    }
}
