import Foundation

/// One of the four cells of a tab's pane grid: two columns by two rows.
nonisolated struct GridCell: Hashable, Sendable, CustomStringConvertible {
    /// 0 is the leading column, 1 the trailing one.
    let column: Int
    /// 0 is the top row, 1 the bottom one.
    let row: Int

    static let topLeft = GridCell(column: 0, row: 0)
    static let topRight = GridCell(column: 1, row: 0)
    static let bottomLeft = GridCell(column: 0, row: 1)
    static let bottomRight = GridCell(column: 1, row: 1)

    /// The four cells in reading order: left to right, then top to bottom.
    static let all: [GridCell] = [.topLeft, .topRight, .bottomLeft, .bottomRight]

    /// The cell a stored pane position names; `.single` names none.
    init?(_ position: PanePosition) {
        switch position {
        case .single: return nil
        case .topLeft: self = .topLeft
        case .topRight: self = .topRight
        case .bottomLeft: self = .bottomLeft
        case .bottomRight: self = .bottomRight
        }
    }

    init(column: Int, row: Int) {
        self.column = column
        self.row = row
    }

    /// The cell's place in reading order, 0 to 3.
    var readingIndex: Int {
        row * 2 + column
    }

    /// The stored pane position for this cell.
    var position: PanePosition {
        switch (column, row) {
        case (0, 0): .topLeft
        case (_, 0): .topRight
        case (0, _): .bottomLeft
        default: .bottomRight
        }
    }

    /// The neighboring cell across `edge`, if the grid has one there.
    func neighbor(across edge: PaneEdge) -> GridCell? {
        let next = switch edge {
        case .leading: GridCell(column: column - 1, row: row)
        case .trailing: GridCell(column: column + 1, row: row)
        case .top: GridCell(column: column, row: row - 1)
        case .bottom: GridCell(column: column, row: row + 1)
        }
        return Self.all.contains(next) ? next : nil
    }

    var description: String {
        switch position {
        case .topLeft: "top-left"
        case .topRight: "top-right"
        case .bottomLeft: "bottom-left"
        case .bottomRight, .single: "bottom-right"
        }
    }

    /// A cell by the name ``description`` gives it.
    init?(name: String) {
        guard let cell = Self.all.first(where: { $0.description == name.lowercased() }) else { return nil }
        self = cell
    }
}

/// A side of a pane, or of the page.
nonisolated enum PaneEdge: String, CaseIterable, Hashable, Sendable {
    case leading
    case trailing
    case top
    case bottom

    var opposite: PaneEdge {
        switch self {
        case .leading: .trailing
        case .trailing: .leading
        case .top: .bottom
        case .bottom: .top
        }
    }

    /// Leading and trailing split a pane's columns; top and bottom its rows.
    var isHorizontal: Bool {
        self == .leading || self == .trailing
    }

    /// The edge a direction word names: left, right, up, down, top, bottom, leading, trailing.
    init?(word: String) {
        switch word.lowercased() {
        case "left", "leading": self = .leading
        case "right", "trailing": self = .trailing
        case "up", "top", "above": self = .top
        case "down", "bottom", "below": self = .bottom
        default: return nil
        }
    }
}

/// The cells one pane covers: a rectangle of one, two, or all four cells.
nonisolated struct PaneSpan: Hashable, Sendable {
    let columns: ClosedRange<Int>
    let rows: ClosedRange<Int>

    /// The whole grid, the span of a tab's only page.
    static let whole = PaneSpan(columns: 0 ... 1, rows: 0 ... 1)

    init(columns: ClosedRange<Int>, rows: ClosedRange<Int>) {
        self.columns = columns
        self.rows = rows
    }

    init(_ cell: GridCell) {
        self.columns = cell.column ... cell.column
        self.rows = cell.row ... cell.row
    }

    /// The top-leading cell, the one a stored configuration names.
    var anchor: GridCell {
        GridCell(column: columns.lowerBound, row: rows.lowerBound)
    }

    /// Two columns wide.
    var isWide: Bool {
        columns.count == 2
    }

    /// Two rows tall.
    var isTall: Bool {
        rows.count == 2
    }

    /// The cells covered, in reading order.
    var cells: [GridCell] {
        GridCell.all.filter(contains)
    }

    func contains(_ cell: GridCell) -> Bool {
        columns.contains(cell.column) && rows.contains(cell.row)
    }

    /// Whether the span is two cells thick across `edge`, so it can be halved there.
    func canHalve(at edge: PaneEdge) -> Bool {
        edge.isHorizontal ? isWide : isTall
    }

    /// The half of the span at `edge`; nil when the span is one cell thick that way.
    func half(at edge: PaneEdge) -> PaneSpan? {
        guard canHalve(at: edge) else { return nil }
        return switch edge {
        case .leading: PaneSpan(columns: 0 ... 0, rows: rows)
        case .trailing: PaneSpan(columns: 1 ... 1, rows: rows)
        case .top: PaneSpan(columns: columns, rows: 0 ... 0)
        case .bottom: PaneSpan(columns: columns, rows: 1 ... 1)
        }
    }

    /// The span grown by one strip across `edge`; nil when `edge` is the grid's own edge.
    func extended(toward edge: PaneEdge) -> PaneSpan? {
        switch edge {
        case .leading: columns.lowerBound == 1 ? PaneSpan(columns: 0 ... 1, rows: rows) : nil
        case .trailing: columns.upperBound == 0 ? PaneSpan(columns: 0 ... 1, rows: rows) : nil
        case .top: rows.lowerBound == 1 ? PaneSpan(columns: columns, rows: 0 ... 1) : nil
        case .bottom: rows.upperBound == 0 ? PaneSpan(columns: columns, rows: 0 ... 1) : nil
        }
    }

    /// The span without its strip at `edge`; nil when the span is one cell thick that way.
    func shrunk(from edge: PaneEdge) -> PaneSpan? {
        half(at: edge.opposite)
    }
}

/// A new pane beside an existing one: `target` gives up its half at `edge` to the new page.
nonisolated struct PaneSplit: Hashable, Sendable {
    /// The page whose pane is halved.
    let target: UUID
    /// The side of that pane the new page takes.
    let edge: PaneEdge
}

/// Where a page joining a tab goes.
nonisolated enum PanePlacement: Hashable, Sendable {
    /// An empty cell while the grid is edited; a filled cell is split toward it.
    case cell(GridCell)
    /// Beside a pane, taking the half at one of its edges.
    case split(PaneSplit)
    /// The first empty cell, else the largest pane's trailing or bottom half.
    case automatic
}

/// A tab's pages laid out on a two-by-two grid: which cells each page covers.
///
/// The stored form is ``LayoutConfiguration``: a pane position per page, the one expansion
/// a pane may have, and the two split ratios. A grid read from it always covers every cell
/// (``filled()``); while layout mode edits it, cells may stand empty until the edit is
/// committed.
nonisolated struct PaneGrid: Equatable, Sendable {
    /// Four cells hold at most four pages.
    static let capacity = 4

    private(set) var spans: [UUID: PaneSpan]

    init(spans: [UUID: PaneSpan] = [:]) {
        self.spans = spans
    }

    /// The grid a stored configuration describes for `pageIDs`, every cell covered.
    ///
    /// A page keeps its stored cell; a page without one, or whose cell another page took,
    /// takes the first free cell in reading order. Stored expansions apply next, then the
    /// cells still empty are filled (``filled()``). A lone page covers the whole grid.
    init(configuration: LayoutConfiguration?, pageIDs: [UUID]) {
        self.init()
        let ids = Array(pageIDs.prefix(Self.capacity))
        guard ids.count > 1 else {
            if let only = ids.first {
                spans[only] = .whole
            }
            return
        }
        for id in ids {
            if let position = configuration?.panePositions[id], let cell = GridCell(position), page(at: cell) == nil {
                spans[id] = PaneSpan(cell)
            }
        }
        for id in ids where spans[id] == nil {
            if let cell = emptyCells.first {
                spans[id] = PaneSpan(cell)
            }
        }
        let expansions = (configuration?.expansions ?? [:]).sorted { $0.key.sortOrder < $1.key.sortOrder }
        for (position, direction) in expansions {
            guard let cell = GridCell(position), let id = page(at: cell), let span = spans[id], span == PaneSpan(cell) else { continue }
            _ = extend(id, toward: PaneEdge(direction))
        }
        self = filled()
    }

    /// `pageIDs` in the order a stored layout is read in: by stored cell in reading order,
    /// pages without one last, ties by id. A tab's pages come in no fixed order, and the
    /// order decides which of two pages stored in one cell keeps it and where an unplaced
    /// page goes, so a damaged layout reads the same on every launch.
    static func loadOrder(_ pageIDs: [UUID], configuration: LayoutConfiguration?) -> [UUID] {
        func rank(_ id: UUID) -> Int {
            configuration?.panePositions[id].flatMap(GridCell.init)?.readingIndex ?? GridCell.all.count
        }
        return pageIDs.sorted { lhs, rhs in
            let left = rank(lhs)
            let right = rank(rhs)
            return left != right ? left < right : lhs.uuidString < rhs.uuidString
        }
    }

    // MARK: - Reading

    /// The pages in reading order of their top-leading cells.
    var pageIDs: [UUID] {
        spans.sorted { $0.value.anchor.readingIndex < $1.value.anchor.readingIndex }.map(\.key)
    }

    var count: Int {
        spans.count
    }

    var isEmpty: Bool {
        spans.isEmpty
    }

    func span(of pageID: UUID) -> PaneSpan? {
        spans[pageID]
    }

    func contains(_ pageID: UUID) -> Bool {
        spans[pageID] != nil
    }

    /// The page covering `cell`, if any.
    func page(at cell: GridCell) -> UUID? {
        spans.first { $0.value.contains(cell) }?.key
    }

    /// Cells no page covers, in reading order.
    var emptyCells: [GridCell] {
        GridCell.all.filter { page(at: $0) == nil }
    }

    /// Whether every cell is covered.
    var isComplete: Bool {
        emptyCells.isEmpty
    }

    /// Whether another page fits.
    var hasRoom: Bool {
        count < Self.capacity
    }

    /// Where ``PanePlacement/automatic`` splits when no cell is empty: the largest pane,
    /// first in reading order among equals, at its trailing half when it is wide, else its
    /// bottom half.
    var automaticSplit: PaneSplit? {
        guard hasRoom else { return nil }
        let candidates = pageIDs.compactMap { id in spans[id].map { (id, $0) } }.filter { $0.1.isWide || $0.1.isTall }
        guard let largest = candidates.max(by: { $0.1.cells.count < $1.1.cells.count }) else { return nil }
        let first = candidates.first { $0.1.cells.count == largest.1.cells.count } ?? largest
        return PaneSplit(target: first.0, edge: first.1.isWide ? .trailing : .bottom)
    }

    /// Whether `split` names a pane of this grid that is two cells thick across its edge.
    func canSplit(_ split: PaneSplit) -> Bool {
        hasRoom && spans[split.target]?.canHalve(at: split.edge) == true
    }

    // MARK: - Completing

    /// The grid with every empty cell covered by growing a neighboring pane into it.
    ///
    /// Each empty cell, in reading order, goes to the first pane that can grow over it
    /// without covering another page: the pane above, below, before, then after it. Growing
    /// takes a whole strip, so a wide pane above two empty cells grows over both.
    func filled() -> PaneGrid {
        var grid = self
        guard !grid.isEmpty else { return grid }
        var progressed = true
        while progressed, !grid.isComplete {
            progressed = false
            for cell in grid.emptyCells {
                if grid.growNeighbor(into: cell) {
                    progressed = true
                    break
                }
            }
        }
        return grid
    }

    private mutating func growNeighbor(into cell: GridCell) -> Bool {
        for edge in [PaneEdge.top, .bottom, .leading, .trailing] {
            guard let neighbor = cell.neighbor(across: edge), let id = page(at: neighbor) else { continue }
            if extend(id, toward: edge.opposite) {
                return true
            }
        }
        return false
    }

    /// Grows `pageID` by one strip across `edge` when that strip is empty.
    private mutating func extend(_ pageID: UUID, toward edge: PaneEdge) -> Bool {
        guard let span = spans[pageID], let grown = span.extended(toward: edge) else { return false }
        let added = grown.cells.filter { !span.contains($0) }
        guard added.allSatisfy({ page(at: $0) == nil }) else { return false }
        spans[pageID] = grown
        return true
    }

    // MARK: - Editing

    /// The grid with `pageID` added at `placement`; nil when the grid is full, the page is
    /// already in it, or the placement names no pane that can be split.
    func inserting(_ pageID: UUID, at placement: PanePlacement) -> PaneGrid? {
        guard spans[pageID] == nil, hasRoom else { return nil }
        if isEmpty {
            return PaneGrid(spans: [pageID: .whole])
        }
        switch placement {
        case let .cell(cell):
            guard let occupant = page(at: cell) else {
                var grid = self
                grid.spans[pageID] = PaneSpan(cell)
                return grid
            }
            guard let span = spans[occupant], let edge = Self.edge(of: span, toward: cell) else { return nil }
            return inserting(pageID, at: .split(PaneSplit(target: occupant, edge: edge)))
        case let .split(split):
            guard canSplit(split), let span = spans[split.target],
                  let kept = span.half(at: split.edge.opposite), let given = span.half(at: split.edge) else { return nil }
            var grid = self
            grid.spans[split.target] = kept
            grid.spans[pageID] = given
            return grid
        case .automatic:
            if let cell = emptyCells.first {
                return inserting(pageID, at: .cell(cell))
            }
            guard let split = automaticSplit else { return nil }
            return inserting(pageID, at: .split(split))
        }
    }

    /// The side of `span` that `cell` lies at. A pane both wide and tall splits along the axis
    /// on which `cell` leaves its anchor, so the cell below the anchor stacks and the cell
    /// beside it sits side by side; across columns first when it leaves on both or neither.
    private static func edge(of span: PaneSpan, toward cell: GridCell) -> PaneEdge? {
        if span.isWide, span.isTall, cell.column == span.anchor.column, cell.row != span.anchor.row {
            return .bottom
        }
        if span.isWide {
            return cell.column == 0 ? .leading : .trailing
        }
        if span.isTall {
            return cell.row == 0 ? .top : .bottom
        }
        return nil
    }

    /// The grid with `pageID` moved onto `cell`: it trades places with the page there, or
    /// covers that cell alone when it was empty. Nil when the page already covers `cell`.
    func moving(_ pageID: UUID, to cell: GridCell) -> PaneGrid? {
        guard let span = spans[pageID], !span.contains(cell) else { return nil }
        var grid = self
        if let other = page(at: cell), let otherSpan = spans[other] {
            grid.spans[other] = span
            grid.spans[pageID] = otherSpan
        } else {
            grid.spans[pageID] = PaneSpan(cell)
        }
        return grid
    }

    /// The grid with `pageID` grown over the empty strip across `edge`; nil when that strip
    /// is the grid's edge or holds another page.
    func expanding(_ pageID: UUID, toward edge: PaneEdge) -> PaneGrid? {
        var grid = self
        return grid.extend(pageID, toward: edge) ? grid : nil
    }

    /// The grid with `pageID` given up its strip at `edge`, which stands empty; nil when the
    /// pane is one cell thick that way.
    func shrinking(_ pageID: UUID, from edge: PaneEdge) -> PaneGrid? {
        guard let shrunk = spans[pageID]?.shrunk(from: edge) else { return nil }
        var grid = self
        grid.spans[pageID] = shrunk
        return grid
    }

    /// The grid without `pageID`; its cells stand empty.
    func removing(_ pageID: UUID) -> PaneGrid {
        var grid = self
        grid.spans.removeValue(forKey: pageID)
        return grid
    }

    /// The grid holding only `pageIDs`: other pages leave, missing ones join automatically.
    func reconciled(with pageIDs: [UUID]) -> PaneGrid {
        let kept = Set(pageIDs)
        var grid = PaneGrid(spans: spans.filter { kept.contains($0.key) })
        for id in pageIDs where !grid.contains(id) {
            if let next = grid.inserting(id, at: .automatic) {
                grid = next
            }
        }
        return grid
    }

    // MARK: - Storing

    /// The stored form of a complete grid; nil for one page or none, which need no layout.
    func configuration(columnSplit: Double, rowSplit: Double, activePaneID: UUID?) -> LayoutConfiguration? {
        guard count > 1 else { return nil }
        var config = LayoutConfiguration(panePositions: [:])
        for (id, span) in spans {
            config.panePositions[id] = span.anchor.position
            if span.isWide, !span.isTall {
                config.expansions[span.anchor.position] = .right
            } else if span.isTall, !span.isWide {
                config.expansions[span.anchor.position] = .down
            }
        }
        config.horizontalDivider = columnSplit
        config.verticalDivider = rowSplit
        config.activePaneID = activePaneID.flatMap { contains($0) ? $0 : nil } ?? pageIDs.first
        return config
    }

    /// The pane position stored on each page: its top-leading cell, `.single` for a lone page.
    var positions: [UUID: PanePosition] {
        spans.mapValues { count > 1 ? $0.anchor.position : .single }
    }
}

extension PaneEdge {
    /// The edge a stored expansion grows across.
    nonisolated init(_ direction: ExpansionDirection) {
        switch direction {
        case .left: self = .leading
        case .right: self = .trailing
        case .up: self = .top
        case .down: self = .bottom
        }
    }
}
