import Foundation

/// A table command the Command Lens offers, run on the window's ``TableController``.
nonisolated enum TableCommand: Hashable, Sendable {
    /// Focus the next slab or row (⌃⌘ arrows).
    case focus(TableDirection)
    /// Move the current slab along its row or into the next row (⌃⌘⇧ arrows).
    case moveSlab(TableDirection)
    /// Cycle the current slab's width (⌃⌘R).
    case cycleWidth
    /// Fill the width with the current slab, or return it to its preset (⌃⌘⇧F).
    case toggleFill
    /// Give the current slab a preset width.
    case setWidth(TableWidth)
    /// Move the current slab into a row of its own.
    case moveToNewRow
    /// Go to a row, counted from 0.
    case goToRow(Int)

    /// The row number in `query` after the word "row", counted from 1 as people say it.
    static func rowNumber(in query: String) -> Int? {
        guard let range = query.range(of: #"row\s*(\d+)"#, options: [.regularExpression, .caseInsensitive]) else { return nil }
        return Int(query[range].filter(\.isNumber))
    }
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
        case .moveToNewRow:
            if let tab = currentTab {
                moveToNewRow(tab)
            }
        case let .goToRow(index):
            goToRow(index)
        }
    }
}
