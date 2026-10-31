import Foundation

/// The direction a stored pane grows over its neighboring cell.
nonisolated enum ExpansionDirection: String, Codable, Equatable, Sendable {
    case right
    case left
    case down
    case up
}

/// The stored layout of a tab of several pages, read and written through ``PaneGrid``.
///
/// - `panePositions`: each page's cell (the top-leading one of its pane).
/// - `expansions`: the pane at a cell that also covers its neighbor in one direction.
/// - `horizontalDivider`, `verticalDivider`: where the columns and the rows divide, as a
///   share (0–1) of the page's width and height, so they follow the window's size.
/// - `activePaneID`: the pane that last had focus.
nonisolated struct LayoutConfiguration: Codable, Equatable, Sendable {
    /// Maps TabPage.id to its position in the layout
    var panePositions: [UUID: PanePosition]

    /// Currently focused pane
    var activePaneID: UUID?

    /// Where the columns divide: the share of the width left of the line between them.
    var horizontalDivider: Double = 0.5
    /// Where the rows divide: the share of the height above the line between them.
    var verticalDivider: Double = 0.5

    /// Panes that cover their neighboring cell, by the pane's own cell.
    var expansions: [PanePosition: ExpansionDirection] = [:]
}
