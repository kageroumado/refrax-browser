import CoreGraphics
import Foundation

/// What a point on the layout-mode surface is over.
nonisolated enum PaneEditingRegion: Hashable, Sendable {
    /// A bar between panes: dragging it resizes.
    case divider(PaneDivider.Axis)
    /// A pane: dragging it moves it.
    case pane(UUID)
    /// A cell no pane covers: a page can open or be dropped there.
    case emptyCell(GridCell)
    /// The margins around the panes.
    case surface
}

/// The layout-mode surface's plain decisions: what a point is over, what each pane can do
/// toward each side, and how much of its control cluster fits.
nonisolated enum PaneEditingSurface {
    /// How far across a gap a resize takes hold: the gap and a little of each pane's edge.
    static let dividerReach: CGFloat = 28

    /// What `point` is over: a divider's bar first (it reaches a little over the panes'
    /// edges), then a pane, then an empty cell, else the surface.
    static func region(at point: CGPoint, in grid: PaneGrid, geometry: PaneGridGeometry) -> PaneEditingRegion {
        if let divider = geometry.dividers(for: grid).first(where: { $0.grabFrame(reach: dividerReach).contains(point) }) {
            return .divider(divider.axis)
        }
        for id in grid.pageIDs {
            if let span = grid.span(of: id), geometry.frame(of: span).contains(point) {
                return .pane(id)
            }
        }
        if let cell = grid.emptyCells.first(where: { geometry.frame(of: $0).contains(point) }) {
            return .emptyCell(cell)
        }
        return .surface
    }

    /// How a pane's controls fit in a pane of `size`.
    nonisolated enum ControlStyle: Equatable, Sendable {
        /// Title, a pad of side arrows, and the Open as Its Own Tab and Close Pane buttons.
        case full
        /// The pad of side arrows and a menu with the rest.
        case compact
    }

    static let fullControlsMinimum = CGSize(width: 300, height: 240)

    static func controlStyle(for size: CGSize) -> ControlStyle {
        size.width >= fullControlsMinimum.width && size.height >= fullControlsMinimum.height ? .full : .compact
    }
}

/// What one pane can do in layout mode, worked out from the edit's grid.
nonisolated struct PaneEditingVerbs: Equatable, Sendable {
    nonisolated enum Verb: Hashable, Sendable {
        /// Grow over the empty cells across an edge.
        case grow(PaneEdge)
        /// Give up the half at an edge, which stands empty.
        case shrink(PaneEdge)
        /// Leave the tab as a tab of its own, in the tab's island.
        case openAsTab
        /// Close the page.
        case close
    }

    /// Each side's one verb: a pane one cell thick toward a side can only grow there, one two
    /// cells thick can only give up its half there.
    let sides: [PaneEdge: Verb]
    /// The last pane stays.
    let canLeave: Bool

    init(pageID: UUID, grid: PaneGrid) {
        var sides: [PaneEdge: Verb] = [:]
        for edge in PaneEdge.allCases {
            if grid.expanding(pageID, toward: edge) != nil {
                sides[edge] = .grow(edge)
            } else if grid.shrinking(pageID, from: edge) != nil {
                sides[edge] = .shrink(edge)
            }
        }
        self.sides = sides
        self.canLeave = grid.count > 1
    }

    static func title(of verb: Verb) -> String {
        switch verb {
        case let .grow(edge): "Fill \(name(of: edge))"
        case let .shrink(edge): "Free the \(name(of: edge)) Half"
        case .openAsTab: "Open as Its Own Tab"
        case .close: "Close Pane"
        }
    }

    /// Growing points out across the side, freeing points back in from it.
    static func symbol(of verb: Verb) -> String {
        switch verb {
        case let .grow(edge): arrow(toward: edge)
        case let .shrink(edge): arrow(toward: edge.opposite)
        case .openAsTab: "rectangle.portrait.and.arrow.right"
        case .close: "xmark"
        }
    }

    static func arrow(toward edge: PaneEdge) -> String {
        switch edge {
        case .leading: "arrow.left"
        case .trailing: "arrow.right"
        case .top: "arrow.up"
        case .bottom: "arrow.down"
        }
    }

    private static func name(of edge: PaneEdge) -> String {
        switch edge {
        case .leading: "Left"
        case .trailing: "Right"
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }
}
