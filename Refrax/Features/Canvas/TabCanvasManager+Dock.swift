import AppKit
import SwiftUI

/// The side a dragged card would dock to, and the card.
nonisolated struct FloatingDockTarget: Equatable, Sendable {
    let edge: FloatingDockEdge
    let tabID: Tab.ID
}

/// A beam from where a page was to where docking or undocking took it, in the layer's coordinates.
nonisolated struct FloatingDockBeam: Identifiable, Equatable, Sendable {
    let id: Int
    let source: CGRect
    let destination: CGRect
}

// MARK: - Pages Docked to the Window's Sides

extension TabCanvasManager {
    /// The dock and undock motion: the v3 Unfold timing, or none under Reduce Motion so the dock snaps.
    static var dockAnimation: Animation? {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? nil : .snappy(duration: 0.28)
    }

    /// The rail, while the island shows it; a column on its side starts past it.
    var dockRail: CGRect? {
        guard showsFloatingControls else { return nil }
        let rail = windowState.controlIsland.railFrame
        return rail.isEmpty ? nil : rail
    }

    /// The page docked to `edge` in this window's space. The current page fills the window, so
    /// it never shows docked.
    func dockedTab(on edge: FloatingDockEdge) -> Tab? {
        guard windowState.usesFloatingTabs, !windowState.isSpaceLocked else { return nil }
        return floatingTabs.first { $0.id != windowState.activeTabID && storedFloatingPlacement(for: $0)?.dock == edge }
    }

    /// The docked columns, with `target`'s column in place of what is docked on its side while
    /// a card is dragged there.
    func dockColumns(in bounds: CGRect, previewing target: FloatingDockTarget? = nil) -> FloatingDockLayout.Columns {
        func fraction(_ edge: FloatingDockEdge) -> Double? {
            if let target, target.edge == edge {
                return floatingTabs.first { $0.id == target.tabID }.map { floatingPlacement(for: $0).dockWidthFraction }
                    ?? FloatingDockLayout.defaultFraction
            }
            return dockedTab(on: edge).map { floatingPlacement(for: $0).dockWidthFraction }
        }
        return FloatingDockLayout.columns(leading: fraction(.leading), trailing: fraction(.trailing), in: bounds, rail: dockRail)
    }

    /// The docked page whose column holds `point`.
    func dockedTab(at point: CGPoint, in bounds: CGRect) -> Tab? {
        let columns = dockColumns(in: bounds)
        return FloatingDockEdge.allCases.first { columns[$0]?.contains(point) == true }.flatMap(dockedTab(on:))
    }

    /// The current page's area beside the docked columns.
    func dockedPageFrame(in bounds: CGRect) -> CGRect {
        FloatingDockLayout.pageFrame(beside: dockColumns(in: bounds), in: bounds)
    }

    /// The docked columns and their seams, where the layer takes the pointer.
    func dockHitRegions(in bounds: CGRect) -> [CGRect] {
        let columns = dockColumns(in: bounds)
        return FloatingDockEdge.allCases.flatMap { edge in
            columns[edge].map { [$0, FloatingDockLayout.seamFrame(beside: $0, edge: edge)] } ?? []
        }
    }

    // MARK: Docking

    /// Docks `tab` to `edge`. The current page leaves the window for the column and the most
    /// recent other page takes its place; a page already on that side returns to its floating
    /// frame. A beam runs from `source`, or from where the page shows now, to the column.
    func dock(_ tab: Tab, to edge: FloatingDockEdge, from source: CGRect? = nil) {
        let bounds = floatingArea
        let isCurrentPage = tab.id == windowState.activeTabID
        var replacement: Tab?
        if isCurrentPage {
            replacement = pageReplacingDocked(tab)
            guard replacement != nil else {
                windowState.showToast("Open a second page to dock this one beside it.")
                return
            }
        }
        let source = source ?? shownFrame(of: tab, in: bounds)
        withAnimation(Self.dockAnimation) {
            if let previous = dockedTab(on: edge), previous.id != tab.id {
                undock(previous)
            }
            var placement = storedFloatingPlacement(for: tab) ?? startingPlacement(for: tab, in: bounds)
            placement.dock = edge
            updateFloatingPlacement(placement, for: tab)
            selectedFloatingTabIDs.remove(tab.id)
            if let replacement {
                tabManager.setActiveTab(replacement, in: windowState)
            }
        }
        if let column = dockColumns(in: bounds)[edge] {
            beam(from: source, to: column)
        }
    }

    /// Returns `tab` from its column to its last floating frame, with a beam to it.
    func undock(_ tab: Tab) {
        guard let placement = storedFloatingPlacement(for: tab), let edge = placement.dock else { return }
        let bounds = floatingArea
        let column = dockedTab(on: edge)?.id == tab.id ? dockColumns(in: bounds)[edge] : nil
        var next = placement
        next.dock = nil
        withAnimation(Self.dockAnimation) {
            updateFloatingPlacement(next, for: tab)
        }
        if let column {
            beam(from: column, to: floatingFrame(for: tab, in: bounds))
        }
    }

    /// Docks the current page to `edge`.
    func dockCurrentPage(to edge: FloatingDockEdge) {
        guard let tab = windowState.activeTab else { return }
        onUseFloatingTabs?()
        dock(tab, to: edge)
    }

    /// Undocks the page on `edge`.
    func undockPage(on edge: FloatingDockEdge) {
        dockedTab(on: edge).map(undock)
    }

    /// A docked page that becomes the current page leaves its column to fill the window; a beam
    /// runs from the column to the page card.
    func releaseDockForCurrentPage() {
        guard let tab = windowState.activeTab, var placement = storedFloatingPlacement(for: tab), let edge = placement.dock else { return }
        let bounds = floatingArea
        let opposite = dockedTab(on: edge.opposite).map { floatingPlacement(for: $0).dockWidthFraction }
        let column = edge == .leading
            ? FloatingDockLayout.columns(leading: placement.dockWidthFraction, trailing: opposite, in: bounds, rail: dockRail).leading
            : FloatingDockLayout.columns(leading: opposite, trailing: placement.dockWidthFraction, in: bounds, rail: dockRail).trailing
        placement.dock = nil
        withAnimation(Self.dockAnimation) {
            updateFloatingPlacement(placement, for: tab)
        }
        if let column {
            beam(from: column, to: pageCardFrame)
        }
    }

    /// Sets the width of the column on `edge` from its seam dragged to `x`.
    func resizeDock(on edge: FloatingDockEdge, seamAt x: CGFloat, in bounds: CGRect) {
        guard let tab = dockedTab(on: edge) else { return }
        let opposite = dockedTab(on: edge.opposite).map { floatingPlacement(for: $0).dockWidthFraction }
        var placement = floatingPlacement(for: tab)
        placement.dockFraction = FloatingDockLayout.fraction(forSeamAt: x, edge: edge, opposite: opposite, in: bounds, rail: dockRail)
        updateFloatingPlacement(placement, for: tab)
    }

    // MARK: Dragging a Card to a Side

    /// Marks the side a lone card docks to while its pointer is at `pointer`.
    func updateDockTarget(at pointer: CGPoint, dragging tabs: [Tab], in area: CGRect) {
        var target: FloatingDockTarget?
        if windowState.usesFloatingTabs, tabs.count == 1, let tab = tabs.first, tab.id != windowState.activeTabID,
           let edge = FloatingDockLayout.snapEdge(at: pointer, in: area, rail: dockRail) {
            target = FloatingDockTarget(edge: edge, tabID: tab.id)
            floatingDropGroupID = nil
        }
        if dockTarget != target {
            dockTarget = target
        }
    }

    /// Docks a card let go over a side's silhouette, keeping the frame it was dragged from as
    /// its floating frame. Returns whether the card docked.
    func dockDraggedCard(_ tab: Tab) -> Bool {
        guard let target = dockTarget, target.tabID == tab.id else {
            dockTarget = nil
            return false
        }
        dockTarget = nil
        let area = floatingArea
        let source = floatingFrame(for: tab, in: area)
        if let origin = floatingMoveOrigins[tab.id] {
            var placement = floatingPlacement(for: tab)
            placement.move(to: origin, in: area)
            updateFloatingPlacement(placement, for: tab)
        }
        endFloatingMove()
        floatingDropGroupID = nil
        dock(tab, to: target.edge, from: source)
        return true
    }

    // MARK: Beams

    func finishDockBeam(_ id: Int) {
        dockBeams.removeAll { $0.id == id }
    }

    private func beam(from source: CGRect, to destination: CGRect) {
        guard !source.isEmpty, !destination.isEmpty else { return }
        dockBeamRevision += 1
        dockBeams.append(FloatingDockBeam(id: dockBeamRevision, source: source, destination: destination))
    }

    // MARK: Helpers

    /// Where `tab` shows now: its column, the page card for the current page, or its card.
    private func shownFrame(of tab: Tab, in bounds: CGRect) -> CGRect {
        if let edge = storedFloatingPlacement(for: tab)?.dock, dockedTab(on: edge)?.id == tab.id, let column = dockColumns(in: bounds)[edge] {
            return column
        }
        if tab.id == windowState.activeTabID {
            return pageCardFrame
        }
        return floatingFrame(for: tab, in: bounds)
    }

    /// The control that stands for the current page: its card beside the rail, else the rail.
    private var pageCardFrame: CGRect {
        windowState.addressBarFrame.isEmpty ? dockRail ?? .zero : windowState.addressBarFrame
    }

    /// A floating frame for a page that has none, so undocking has somewhere to return it.
    private func startingPlacement(for tab: Tab, in bounds: CGRect) -> FloatingTabPlacement {
        let occupied = floatingTabs.filter { $0.id != tab.id }.compactMap { storedFloatingPlacement(for: $0) }
        return FloatingTabPlacement.freeStartingSlot(nearest: nil, avoiding: occupied, in: bounds, isCompact: false)
            ?? floatingPlacement(for: tab)
    }

    /// The page that fills the window once the current page docks: the most recently used page
    /// of this space that is neither docked nor archived.
    private func pageReplacingDocked(_ tab: Tab) -> Tab? {
        windowState.activeSpaceTabs
            .filter { $0.id != tab.id && !$0.isArchived && storedFloatingPlacement(for: $0)?.isDocked != true }
            .max { ($0.lastAccessed ?? .distantPast) < ($1.lastAccessed ?? .distantPast) }
    }
}
