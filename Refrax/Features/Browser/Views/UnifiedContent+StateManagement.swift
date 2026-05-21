import SwiftUI

// MARK: - State Management

extension UnifiedContentView {
    func initializeState() {
        if let config = tab.layoutConfiguration {
            workingConfig = config
        }

        loadLayoutState()
    }

    /// Loads layout state when entering layout editing mode
    ///
    /// **Visual Result:** Populates the 2×2 grid with existing panes from tab.layoutConfiguration,
    /// or creates a fresh grid with just the primary page if no layout exists.
    ///
    /// **UI Appearance:**
    /// - Existing layouts: All panes restored to their saved positions
    /// - New layouts: Primary page placed in top-left, other slots empty
    /// - Expansions and dividers restored from saved configuration
    ///
    /// **Performance:** Only called on mode entry, not during editing
    func loadLayoutState() {
        if windowState.isInLayoutMode {
            layoutGrid = LayoutGrid()

            if let config = tab.layoutConfiguration {
                workingConfig = config

                for page in tab.pages {
                    if let position = config.panePositions[page.id] {
                        if !config.isCovered(position) {
                            layoutGrid.setPage(page, at: position)
                        }
                    }
                }
            } else {
                workingConfig = LayoutConfiguration(panePositions: [:])
                layoutGrid.setPage(tab.activePage, at: .topLeft)
            }
        }

        if let activeID = tab.layoutConfiguration?.activePaneID {
            focusedPageID = activeID
        } else {
            focusedPageID = tab.activePage.id
        }
    }

    func focusPage(_ page: TabPage) {
        guard focusedPageID != page.id else { return }
        focusedPageID = page.id
        tabManager.setActivePage(in: tab, page: page)
    }

    /// Syncs any new pages from layoutConfiguration into layoutGrid.
    ///
    /// Called when layoutConfiguration changes while in layout mode (e.g., when
    /// command lens creates a new page). Ensures the view's layoutGrid state
    /// stays in sync with the data model.
    func syncNewPagesToLayoutGrid() {
        guard windowState.isInLayoutMode,
              let config = tab.layoutConfiguration else {
            return
        }

        // Find pages in config that aren't in layoutGrid
        var addedAny = false
        for (pageID, position) in config.panePositions {
            if layoutGrid.page(at: position) == nil,
               let page = tab.pages.first(where: { $0.id == pageID }) {
                withAnimation(conditionalSpringAnimation) {
                    layoutGrid.setPage(page, at: position)
                    workingConfig.panePositions[pageID] = position
                    frameUpdateGeneration += 1
                }
                addedAny = true
            }
        }

        if addedAny {
            Logger.info("Synced new pages to layout grid", category: Logger.tabs)
        }
    }

    /// Saves the current layout state and exits layout editing mode
    ///
    /// **Visual Result:** Transitions from 2×2 grid editing mode back to normal multi-pane view.
    /// All pane positions, expansions, and divider positions are persisted to the tab.
    ///
    /// **State Changes:**
    /// - Builds panePositions dictionary from layoutGrid
    /// - Cleans up stale expansions that no longer apply
    /// - Saves expansions and divider ratios
    /// - Clears layout if only 1 pane remains
    /// - Notifies TabManager to persist to SwiftData
    ///
    /// **Optimization:** If the layout hasn't meaningfully changed, preserves the existing
    /// configuration to avoid unnecessary divider resets.
    ///
    /// **Edge Cases:**
    /// - Single pane: Clears layoutConfiguration entirely
    /// - Stale expansions: Removed if they cover filled positions or originate from empty positions
    func saveAndExitLayoutMode() {
        // Capture original config for comparison
        let originalConfig = tab.layoutConfiguration

        // Build pane positions from current layout grid
        var newPanePositions: [UUID: PanePosition] = [:]
        for page in tab.pages {
            if let position = layoutGrid.position(for: page) {
                newPanePositions[page.id] = position
            }
        }

        let filledPositions = Set(newPanePositions.values)

        // Build new config with current divider positions
        var newConfig = workingConfig
        newConfig.panePositions = newPanePositions

        // Clean up stale expansions in the new config
        var validExpansions: [PanePosition: ExpansionDirection] = [:]
        for (position, direction) in newConfig.expansions {
            guard filledPositions.contains(position) else { continue }

            let coveredPosition: PanePosition? = switch (position, direction) {
            case (.topLeft, .right): .topRight
            case (.topLeft, .down): .bottomLeft
            case (.topRight, .left): .topLeft
            case (.topRight, .down): .bottomRight
            case (.bottomLeft, .right): .bottomRight
            case (.bottomLeft, .up): .topLeft
            case (.bottomRight, .left): .bottomLeft
            case (.bottomRight, .up): .topRight
            default: nil
            }

            if let covered = coveredPosition, !filledPositions.contains(covered) {
                validExpansions[position] = direction
            }
        }
        newConfig.expansions = validExpansions

        // Validate and set activePaneID
        if let focusedID = focusedPageID,
           newConfig.panePositions.keys.contains(focusedID) {
            newConfig.activePaneID = focusedID
        } else if let firstPageID = newConfig.panePositions.keys.first {
            newConfig.activePaneID = firstPageID
            focusedPageID = firstPageID
        } else {
            newConfig.activePaneID = nil
        }

        let pageCount = newConfig.panePositions.count

        if pageCount <= 1 {
            tab.layoutConfiguration = nil
            if pageCount == 1, let page = tab.pages.first {
                page.position = .single
            }
        } else {
            // Update each page's position property to match the layout
            for (pageID, position) in newConfig.panePositions {
                if let page = tab.pages.first(where: { $0.id == pageID }) {
                    page.position = position
                }
            }

            // Check if layout actually changed to avoid unnecessary updates
            // This preserves divider positions when no structural changes were made
            let structureChanged = originalConfig == nil ||
                originalConfig?.panePositions != newConfig.panePositions ||
                originalConfig?.expansions != newConfig.expansions

            if structureChanged {
                tab.layoutConfiguration = newConfig
            } else {
                // Structure unchanged - only update dividers and active pane if they changed
                if var existingConfig = tab.layoutConfiguration {
                    var needsUpdate = false

                    if existingConfig.horizontalDivider != newConfig.horizontalDivider {
                        existingConfig.horizontalDivider = newConfig.horizontalDivider
                        needsUpdate = true
                    }
                    if existingConfig.verticalDivider != newConfig.verticalDivider {
                        existingConfig.verticalDivider = newConfig.verticalDivider
                        needsUpdate = true
                    }
                    if existingConfig.activePaneID != newConfig.activePaneID {
                        existingConfig.activePaneID = newConfig.activePaneID
                        needsUpdate = true
                    }

                    if needsUpdate {
                        tab.layoutConfiguration = existingConfig
                    }
                }
            }
        }

        // Sync workingConfig to reflect saved state
        workingConfig = newConfig
    }
}
