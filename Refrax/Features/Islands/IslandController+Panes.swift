import CoreGraphics
import Foundation

extension IslandController {
    /// A single page can join a tab with room for another pane.
    func canJoin(_ tabID: UUID, with otherID: UUID) -> Bool {
        guard tabID != otherID, let source = tab(for: tabID), let target = tab(for: otherID) else { return false }
        return source.pages.count == 1 && !source.isMultiPage && target.pages.count < PaneGrid.capacity
    }

    /// The panes a page dropped on `tab` meets, and where they stand in `page` (the page's
    /// frame in the layer): the edit's while the window edits that tab, else the tab's own.
    static func paneTarget(of tab: Tab, editing session: PaneLayoutEditor.Session?, page: CGRect) -> (grid: PaneGrid, geometry: PaneGridGeometry) {
        if let session, session.tabID == tab.id {
            let geometry = PaneGridGeometry(bounds: page, columnSplit: session.columnSplit, rowSplit: session.rowSplit, metrics: .editing)
            return (session.grid, geometry)
        }
        let configuration = tab.layoutConfiguration
        let geometry = PaneGridGeometry(
            bounds: page, columnSplit: configuration?.horizontalDivider ?? 0.5, rowSplit: configuration?.verticalDivider ?? 0.5, metrics: .page,
        )
        return (tab.paneGrid, geometry)
    }

    /// Where a page dropped at `point` (in the layer) joins `tab`.
    static func panePlacement(at point: CGPoint, joining tab: Tab, editing session: PaneLayoutEditor.Session?, page: CGRect) -> PanePlacement? {
        guard page.contains(point) else { return nil }
        let target = paneTarget(of: tab, editing: session, page: page)
        return PaneDrop.placement(at: point, in: target.grid, geometry: target.geometry)
    }

    /// The frame, in the layer, a page joining `tab` at `placement` will have.
    static func dropFrame(of placement: PanePlacement, joining tab: Tab, editing session: PaneLayoutEditor.Session?, page: CGRect) -> CGRect? {
        let target = paneTarget(of: tab, editing: session, page: page)
        return PaneDrop.frame(of: placement, joining: UUID(), in: target.grid, geometry: target.geometry)
    }
}
