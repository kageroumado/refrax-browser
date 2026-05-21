import SwiftUI

// MARK: - Layout Mode Actions

extension UnifiedContentView {
    /// Handles tapping on an empty slot to open command lens for adding a new page
    func handleEmptySlotTap(at position: PanePosition) {
        // Clear reference tab mode in case it was set from a previous interaction
        windowState.isCreatingReferenceTab = false
        windowState.layoutModeTargetPosition = position
        windowState.openCommandLens()
    }

    /// Handles dropping a tab onto an empty slot
    ///
    /// Only single-page tabs can be dropped. The original tab is closed after the drop
    /// and its page is moved into the current layout. The WebPage session is transferred
    /// without reloading or creating duplicate history entries.
    func handleDrop(at position: PanePosition, items: [String]) -> Bool {
        guard let uuidString = items.first,
              let tabID = UUID(uuidString: uuidString),
              let draggedTab = tabManager.state.tab(for: tabID) else {
            return false
        }

        // Cannot drop a tab on itself
        if draggedTab.id == tab.id {
            return false
        }

        if draggedTab.isMultiPage || draggedTab.pages.count > 1 {
            return false
        }

        guard let newPage = tabManager.moveTabToLayout(draggedTab, into: tab, at: position) else {
            return false
        }

        withAnimation(conditionalSpringAnimation) {
            layoutGrid.setPage(newPage, at: position)
            frameUpdateGeneration += 1
        }

        clearDragState()

        return true
    }

    /// Removes a pane from the layout (called when using the left arrow button)
    ///
    /// The page is deleted, not moved elsewhere. Use movePaneToTabList to create a new tab instead.
    func removePane(at position: PanePosition) {
        guard layoutGrid.filledPositions.count > 1,
              let page = layoutGrid.page(at: position) else {
            return
        }

        withAnimation(conditionalSpringAnimation) {
            layoutGrid.removePage(at: position)
            tabManager.removePageFromTab(tab, page: page)
            frameUpdateGeneration += 1
        }
    }

    /// Moves a pane from the layout to the tab list as a new standalone tab
    ///
    /// The WebPage session is transferred to the new tab without reloading
    /// or creating duplicate history entries.
    func movePaneToTabList(at position: PanePosition) {
        guard layoutGrid.filledPositions.count > 1,
              let page = layoutGrid.page(at: position) else {
            return
        }

        withAnimation(conditionalSpringAnimation) {
            layoutGrid.removePage(at: position)
            workingConfig.panePositions.removeValue(forKey: page.id)
            workingConfig.expansions.removeValue(forKey: position)
            frameUpdateGeneration += 1
        }

        tabManager.movePageToNewTab(page, from: tab, makeActive: false)
    }

    /// Moves a pane to the reference pane (right sidebar)
    func moveToReferencePane(at position: PanePosition) {
        guard let page = layoutGrid.page(at: position),
              windowState.activeSpace?.referenceTabCount ?? 0 < 4 else {
            return
        }

        layoutGrid.removePage(at: position)
        workingConfig.panePositions.removeValue(forKey: page.id)
        workingConfig.expansions.removeValue(forKey: position)

        tabManager.movePageToReferencePane(page, from: tab)

        withAnimation(conditionalSpringAnimation) {
            updateCachedFrames()
        }
    }
}

// MARK: - Expand Actions

extension UnifiedContentView {
    func expandRight(from position: PanePosition) {
        guard layoutGrid.page(at: position) != nil else { return }

        withAnimation(conditionalSpringAnimation) {
            workingConfig.expansions[position] = .right
            frameUpdateGeneration += 1
        }
    }

    func expandLeft(from position: PanePosition) {
        guard layoutGrid.page(at: position) != nil else { return }

        withAnimation(conditionalSpringAnimation) {
            workingConfig.expansions[position] = .left
            frameUpdateGeneration += 1
        }
    }

    func expandDown(from position: PanePosition) {
        guard layoutGrid.page(at: position) != nil else { return }

        withAnimation(conditionalSpringAnimation) {
            workingConfig.expansions[position] = .down
            frameUpdateGeneration += 1
        }
    }

    func expandUp(from position: PanePosition) {
        guard layoutGrid.page(at: position) != nil else { return }

        withAnimation(conditionalSpringAnimation) {
            workingConfig.expansions[position] = .up
            frameUpdateGeneration += 1
        }
    }
}

// MARK: - Collapse Actions

extension UnifiedContentView {
    func collapseRight(at position: PanePosition) {
        withAnimation(conditionalSpringAnimation) {
            workingConfig.expansions.removeValue(forKey: position)
            frameUpdateGeneration += 1
        }
    }

    func collapseLeft(at position: PanePosition) {
        withAnimation(conditionalSpringAnimation) {
            workingConfig.expansions.removeValue(forKey: position)
            frameUpdateGeneration += 1
        }
    }

    func collapseDown(at position: PanePosition) {
        withAnimation(conditionalSpringAnimation) {
            workingConfig.expansions.removeValue(forKey: position)
            frameUpdateGeneration += 1
        }
    }

    func collapseUp(at position: PanePosition) {
        withAnimation(conditionalSpringAnimation) {
            workingConfig.expansions.removeValue(forKey: position)
            frameUpdateGeneration += 1
        }
    }
}

// MARK: - Can Expand Checks

extension UnifiedContentView {
    func canExpandRight(from position: PanePosition) -> Bool {
        guard windowState.isInLayoutMode,
              workingConfig.expansions[position] == nil else {
            return false
        }

        switch position {
        case .topLeft:
            return !layoutGrid.filledPositions.contains(.topRight) && !workingConfig.isCovered(.topRight)
        case .bottomLeft:
            return !layoutGrid.filledPositions.contains(.bottomRight) && !workingConfig.isCovered(.bottomRight)
        default:
            return false
        }
    }

    func canExpandLeft(from position: PanePosition) -> Bool {
        guard windowState.isInLayoutMode,
              workingConfig.expansions[position] == nil else {
            return false
        }

        switch position {
        case .topRight:
            return !layoutGrid.filledPositions.contains(.topLeft) && !workingConfig.isCovered(.topLeft)
        case .bottomRight:
            return !layoutGrid.filledPositions.contains(.bottomLeft) && !workingConfig.isCovered(.bottomLeft)
        default:
            return false
        }
    }

    func canExpandDown(from position: PanePosition) -> Bool {
        guard windowState.isInLayoutMode,
              workingConfig.expansions[position] == nil else {
            return false
        }

        switch position {
        case .topLeft:
            return !layoutGrid.filledPositions.contains(.bottomLeft) && !workingConfig.isCovered(.bottomLeft)
        case .topRight:
            return !layoutGrid.filledPositions.contains(.bottomRight) && !workingConfig.isCovered(.bottomRight)
        default:
            return false
        }
    }

    func canExpandUp(from position: PanePosition) -> Bool {
        guard windowState.isInLayoutMode,
              workingConfig.expansions[position] == nil else {
            return false
        }

        switch position {
        case .bottomLeft:
            return !layoutGrid.filledPositions.contains(.topLeft) && !workingConfig.isCovered(.topLeft)
        case .bottomRight:
            return !layoutGrid.filledPositions.contains(.topRight) && !workingConfig.isCovered(.topRight)
        default:
            return false
        }
    }
}

// MARK: - Can Collapse Checks

extension UnifiedContentView {
    func canCollapseRight(at position: PanePosition) -> Bool {
        windowState.isInLayoutMode && workingConfig.expansions[position] == .right
    }

    func canCollapseLeft(at position: PanePosition) -> Bool {
        windowState.isInLayoutMode && workingConfig.expansions[position] == .left
    }

    func canCollapseDown(at position: PanePosition) -> Bool {
        windowState.isInLayoutMode && workingConfig.expansions[position] == .down
    }

    func canCollapseUp(at position: PanePosition) -> Bool {
        windowState.isInLayoutMode && workingConfig.expansions[position] == .up
    }
}
