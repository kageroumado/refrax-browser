import AppKit

// MARK: - Moving a Card

extension TabCanvasManager {
    /// Moves `tab`'s card by `translation` from where it was when the move began, inside `area`.
    func moveFloatingCard(_ tab: Tab, by translation: CGSize, in area: CGRect) {
        if floatingMoveOrigins.isEmpty {
            floatingMoveOrigins = [tab.id: floatingPlacement(for: tab).frame(in: area).origin]
            beginFloatingManipulation()
        }
        guard let origin = floatingMoveOrigins[tab.id] else { return }
        var placement = floatingPlacement(for: tab)
        placement.move(to: CGPoint(x: origin.x + translation.width, y: origin.y + translation.height), in: area)
        updateFloatingPlacement(placement, for: tab)
    }

    func endFloatingMove() {
        floatingMoveOrigins = [:]
        endFloatingManipulation()
    }

    /// Follows a drag on a card's header: the card moves, and the window side under the
    /// pointer becomes the dock target.
    func dragFloatingCard(_ tab: Tab, translation: CGSize, pointer: CGPoint, in area: CGRect) {
        floatingDragPointer = pointer
        moveFloatingCard(tab, by: translation, in: area)
        updateDockTarget(at: pointer, dragging: [tab], in: area)
    }

    /// Releases a card: onto an island it rejoins it as a row, onto a window side it docks,
    /// otherwise it stays where it was dropped.
    func endFloatingCardDrag(_ tab: Tab) {
        let pointer = floatingDragPointer
        floatingDragPointer = nil
        if let pointer, islandDrop?(tab, pointer) == true {
            endFloatingMove()
            return
        }
        if dockDraggedCard(tab) {
            return
        }
        endFloatingMove()
        confirmFloatingPlacement()
    }

    // MARK: Hit Regions

    /// Everywhere the floating layer takes the pointer: its cards and the docked columns.
    func floatingHitRegions(in bounds: CGRect) -> [CGRect] {
        visibleFloatingTabs.filter { $0.id != windowState.activeTabID }.map { floatingHitFrame(for: $0, in: bounds) }
            + dockHitRegions(in: bounds)
    }
}
