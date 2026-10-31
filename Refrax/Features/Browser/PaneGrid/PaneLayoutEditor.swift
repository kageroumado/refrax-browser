import CoreGraphics
import Foundation

/// Layout mode: one tab's pane grid lifted apart for editing, and the edit's way back onto the
/// tab.
///
/// The edit lives here, keyed by the tab it began on, never in a view: the commit writes to
/// that tab whatever tab the window shows by then. Its rules:
/// - Entering edits the tab's grid as stored (complete, every cell covered).
/// - Edits may leave cells empty; they stay empty while the mode lasts.
/// - Leaving, by Done or because the window shows another tab, commits: pages that left the
///   tab meanwhile drop out, pages that joined go in, empty cells are filled.
/// - A page joining the edited tab while the mode lasts goes into the edit, so the commit
///   keeps it where it was dropped.
nonisolated struct PaneLayoutEditor: Equatable, Sendable {
    /// One tab's grid while it is edited.
    nonisolated struct Session: Equatable, Sendable {
        let tabID: UUID
        var grid: PaneGrid
        var columnSplit: Double
        var rowSplit: Double
        var activePaneID: UUID?

        /// The geometry the panes take while edited, in a page of `size`.
        func geometry(in size: CGSize) -> PaneGridGeometry {
            PaneGridGeometry(size: size, columnSplit: columnSplit, rowSplit: rowSplit, metrics: .editing)
        }
    }

    private(set) var session: Session?

    var isEditing: Bool {
        session != nil
    }

    func isEditing(tab tabID: UUID) -> Bool {
        session?.tabID == tabID
    }

    // MARK: - Entering and leaving

    /// Begins editing `tabID`, whose pages are `pageIDs` laid out by `configuration`.
    ///
    /// - Returns: false while another edit is under way; that one is committed first.
    @discardableResult
    mutating func enter(tabID: UUID, configuration: LayoutConfiguration?, pageIDs: [UUID], activePageID: UUID?) -> Bool {
        guard session == nil, !pageIDs.isEmpty else { return false }
        session = Session(
            tabID: tabID,
            grid: PaneGrid(configuration: configuration, pageIDs: pageIDs),
            columnSplit: configuration?.horizontalDivider ?? 0.5,
            rowSplit: configuration?.verticalDivider ?? 0.5,
            activePaneID: activePageID,
        )
        return true
    }

    /// Ends the edit and returns what to write to its tab, whose pages are now `pageIDs`.
    ///
    /// - Returns: nil when nothing was being edited.
    mutating func exit(pageIDs: [UUID]) -> PaneLayoutCommit? {
        guard let session else { return nil }
        self.session = nil
        return Self.commit(session, pageIDs: pageIDs)
    }

    /// Ends the edit without writing it: its tab is gone.
    mutating func discard() {
        session = nil
    }

    /// The edit's tab as it would be stored now.
    static func commit(_ session: Session, pageIDs: [UUID]) -> PaneLayoutCommit {
        let grid = session.grid.reconciled(with: pageIDs).filled()
        let active = session.activePaneID.flatMap { grid.contains($0) ? $0 : nil } ?? grid.pageIDs.first
        return PaneLayoutCommit(
            tabID: session.tabID,
            configuration: grid.configuration(columnSplit: session.columnSplit, rowSplit: session.rowSplit, activePaneID: active),
            positions: grid.positions,
            activePaneID: active,
        )
    }

    // MARK: - Editing

    /// Moves `pageID` onto `cell`, trading places with the page there.
    @discardableResult
    mutating func move(_ pageID: UUID, to cell: GridCell) -> Bool {
        apply { $0.moving(pageID, to: cell) }
    }

    /// Grows `pageID` over the empty strip across `edge`.
    @discardableResult
    mutating func expand(_ pageID: UUID, toward edge: PaneEdge) -> Bool {
        apply { $0.expanding(pageID, toward: edge) }
    }

    /// Gives up `pageID`'s strip at `edge`, which stands empty.
    @discardableResult
    mutating func shrink(_ pageID: UUID, from edge: PaneEdge) -> Bool {
        apply { $0.shrinking(pageID, from: edge) }
    }

    /// Takes `pageID` off the grid, its cells left empty; the last pane stays.
    @discardableResult
    mutating func remove(_ pageID: UUID) -> Bool {
        guard let grid = session?.grid, grid.contains(pageID), grid.count > 1 else { return false }
        return apply { $0.removing(pageID) }
    }

    /// Puts `pageID`, which just joined `tabID`, at `placement` when `tabID` is the tab being
    /// edited.
    @discardableResult
    mutating func insert(_ pageID: UUID, joining tabID: UUID, at placement: PanePlacement) -> Bool {
        guard session?.tabID == tabID else { return false }
        return apply { $0.inserting(pageID, at: placement) ?? $0.inserting(pageID, at: .automatic) }
    }

    /// Sets where the columns and rows divide.
    mutating func setSplits(column: Double? = nil, row: Double? = nil) {
        guard var session else { return }
        if let column {
            session.columnSplit = PaneSplitRatio.clamped(column)
        }
        if let row {
            session.rowSplit = PaneSplitRatio.clamped(row)
        }
        self.session = session
    }

    /// Records the pane last used.
    mutating func focus(_ pageID: UUID) {
        guard session?.grid.contains(pageID) == true else { return }
        session?.activePaneID = pageID
    }

    private mutating func apply(_ edit: (PaneGrid) -> PaneGrid?) -> Bool {
        guard var session, let grid = edit(session.grid), grid != session.grid else { return false }
        session.grid = grid
        self.session = session
        return true
    }
}

/// What an edit writes to its tab.
nonisolated struct PaneLayoutCommit: Equatable, Sendable {
    let tabID: UUID
    /// Nil when one page remains.
    let configuration: LayoutConfiguration?
    /// Each page's stored position.
    let positions: [UUID: PanePosition]
    let activePaneID: UUID?
}
