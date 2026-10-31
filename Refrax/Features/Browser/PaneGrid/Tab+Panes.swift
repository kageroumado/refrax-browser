import Foundation

extension Tab {
    /// The tab's pages on the pane grid as stored, every cell covered.
    var paneGrid: PaneGrid {
        PaneGrid(configuration: layoutConfiguration, pageIDs: pages.map(\.id))
    }

    /// Stores `grid` as the tab's layout, completed, keeping the tab's split ratios.
    func storePaneGrid(_ grid: PaneGrid, activePaneID: UUID? = nil) {
        let complete = grid.reconciled(with: pages.map(\.id)).filled()
        let current = layoutConfiguration
        let configuration = complete.configuration(
            columnSplit: current?.horizontalDivider ?? 0.5,
            rowSplit: current?.verticalDivider ?? 0.5,
            activePaneID: activePaneID ?? current?.activePaneID,
        )
        store(configuration, positions: complete.positions)
    }

    /// Writes an edit committed from layout mode.
    func applyPaneLayout(_ commit: PaneLayoutCommit) {
        store(commit.configuration, positions: commit.positions)
    }

    /// Writes the split ratios alone.
    func storePaneSplits(column: Double, row: Double) {
        guard var configuration = layoutConfiguration else { return }
        configuration.horizontalDivider = PaneSplitRatio.clamped(column)
        configuration.verticalDivider = PaneSplitRatio.clamped(row)
        if configuration != layoutConfiguration {
            layoutConfiguration = configuration
        }
    }

    private func store(_ configuration: LayoutConfiguration?, positions: [UUID: PanePosition]) {
        if layoutConfiguration != configuration {
            layoutConfiguration = configuration
        }
        for page in pages {
            let position = positions[page.id] ?? .single
            if page.position != position {
                page.position = position
            }
        }
    }
}
