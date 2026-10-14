import Foundation

/// One space's table: rows of slabs laid side by side at preset widths, Niri style.
///
/// A row is a tab group, or the space's own row for its loose tabs, and holds the group's
/// tabs in their `position` order. Membership and order are the browser's group relation and
/// tab positions, so the layout is rebuilt from them whenever they change
/// (``init(rows:state:)``) and carries only what the model does not: each slab's width
/// preset and fill, kept in ``TableState``.
///
/// ## Coordinates
///
/// Every length is in **viewport-width units**: a full-width slab is 1, a row of three ⅓
/// slabs is 1 long. ``TableGeometry`` turns units into points for a viewport and a gap, so
/// the layout stays exact across window sizes. The table is one plane: every row starts at
/// x = 0 and rows stack downward in order.
///
/// ## Invariants
///
/// - no row is empty, and a tab appears at most once;
/// - a slab's fraction is its preset's, or 1 while it fills.
nonisolated struct TableLayout: Equatable, Sendable {
    /// Lengths closer than this are equal, absorbing the rounding of ⅓ and ⅔ sums.
    static let tolerance = 1e-9

    /// One tab on the table.
    struct Slab: Equatable, Sendable, Identifiable {
        var tabID: UUID
        var width: TableWidth
        /// The slab fills the viewport's width, keeping `width` to return to.
        var fills: Bool

        var id: UUID { tabID }

        init(tabID: UUID, width: TableWidth = .full, fills: Bool = false) {
            self.tabID = tabID
            self.width = width
            self.fills = fills
        }

        /// The slab's share of the viewport width.
        var fraction: Double {
            fills ? 1 : width.fraction
        }
    }

    /// A horizontal strip of slabs: a tab group, or the space's loose tabs.
    struct Row: Equatable, Sendable, Identifiable {
        /// The group's ID, or the space's for its loose tabs.
        var id: UUID
        var title: String
        /// The group's stored color, or `nil` for the space's own row.
        var colorString: String?
        /// A collapsed row is drawn as one band instead of its slabs.
        var isCollapsed: Bool
        var slabs: [Slab]

        init(id: UUID, title: String = "", colorString: String? = nil, isCollapsed: Bool = false, slabs: [Slab]) {
            self.id = id
            self.title = title
            self.colorString = colorString
            self.isCollapsed = isCollapsed
            self.slabs = slabs
        }

        /// The row's length in viewport widths.
        var length: Double {
            slabs.reduce(0) { $0 + $1.fraction }
        }

        /// The left edge of the slab at `index`, in viewport widths from the row's start.
        func start(of index: Int) -> Double {
            slabs[..<index].reduce(0) { $0 + $1.fraction }
        }

        /// The right edge of the slab at `index`.
        func end(of index: Int) -> Double {
            start(of: index) + slabs[index].fraction
        }

        /// The place in the row where a slab of `width` has its center nearest `center`.
        func insertionIndex(width: Double, nearCenter center: Double) -> Int {
            var best = 0
            var bestDistance = Double.infinity
            for index in 0 ... slabs.count {
                let distance = abs(start(of: index) + width / 2 - center)
                if distance < bestDistance - TableLayout.tolerance {
                    best = index
                    bestDistance = distance
                }
            }
            return best
        }
    }

    /// A slab's place on the table.
    struct Position: Hashable, Sendable {
        var row: Int
        var slab: Int
    }

    /// What ``init(rows:state:)`` builds a row from: the model's group or loose tabs.
    struct RowSource: Equatable, Sendable {
        var id: UUID
        var title: String
        var colorString: String?
        var isCollapsed: Bool
        var tabIDs: [UUID]

        init(id: UUID, title: String = "", colorString: String? = nil, isCollapsed: Bool = false, tabIDs: [UUID]) {
            self.id = id
            self.title = title
            self.colorString = colorString
            self.isCollapsed = isCollapsed
            self.tabIDs = tabIDs
        }
    }

    /// Where a slab goes when moved into a row: the row and the index in it, or a new row
    /// above or below the table.
    enum MoveTarget: Equatable, Sendable {
        case row(id: UUID, index: Int)
        case newRow(above: Bool)
    }

    /// The table from top to bottom.
    private(set) var rows: [Row]

    /// An empty table.
    init() {
        rows = []
    }

    /// The table these sources describe, with each slab's width and fill from `state`.
    /// Empty rows and repeated tabs are dropped.
    init(rows sources: [RowSource], state: TableState = TableState()) {
        var seen = Set<UUID>()
        rows = sources.compactMap { source in
            let slabs = source.tabIDs.filter { seen.insert($0).inserted }.map { tabID in
                Slab(tabID: tabID, width: state.widths[tabID] ?? .full, fills: state.fills.contains(tabID))
            }
            guard !slabs.isEmpty else { return nil }
            return Row(id: source.id, title: source.title, colorString: source.colorString, isCollapsed: source.isCollapsed, slabs: slabs)
        }
    }

    // MARK: - Reading

    var isEmpty: Bool {
        rows.isEmpty
    }

    /// Every tab on the table, row by row.
    var tabIDs: [UUID] {
        rows.flatMap { $0.slabs.map(\.tabID) }
    }

    subscript(position: Position) -> Slab {
        rows[position.row].slabs[position.slab]
    }

    /// Where `tabID` sits, or `nil` when it is not on the table.
    func position(of tabID: UUID) -> Position? {
        for (rowIndex, row) in rows.enumerated() {
            if let slabIndex = row.slabs.firstIndex(where: { $0.tabID == tabID }) {
                return Position(row: rowIndex, slab: slabIndex)
            }
        }
        return nil
    }

    /// The row holding `tabID`.
    func row(of tabID: UUID) -> Row? {
        position(of: tabID).map { rows[$0.row] }
    }

    /// The slab beside `tabID` in its row, or `nil` at the row's end.
    func neighbor(of tabID: UUID, toward direction: TableDirection) -> UUID? {
        guard let position = position(of: tabID), direction == .left || direction == .right else { return nil }
        let target = position.slab + (direction == .left ? -1 : 1)
        guard rows[position.row].slabs.indices.contains(target) else { return nil }
        return rows[position.row].slabs[target].tabID
    }

    /// The nearest expanded row above or below the one holding `tabID`; collapsed bands are
    /// stepped over. `nil` at the table's edge.
    func rowIndex(from tabID: UUID, toward direction: TableDirection) -> Int? {
        guard let position = position(of: tabID), direction == .up || direction == .down else { return nil }
        let step = direction == .up ? -1 : 1
        var index = position.row + step
        while rows.indices.contains(index) {
            if !rows[index].isCollapsed {
                return index
            }
            index += step
        }
        return nil
    }

    /// The slab in `rowIndex` whose span overlaps `tabID`'s the most, or the one whose center
    /// is nearest: the slab a move up or down lands beside.
    func slab(inRow rowIndex: Int, nearest tabID: UUID) -> UUID? {
        guard let position = position(of: tabID), rows.indices.contains(rowIndex) else { return nil }
        let source = rows[position.row]
        let start = source.start(of: position.slab)
        let end = source.end(of: position.slab)
        let row = rows[rowIndex]
        var best: (index: Int, overlap: Double, distance: Double)?
        for index in row.slabs.indices {
            let overlap = min(end, row.end(of: index)) - max(start, row.start(of: index))
            let distance = abs((row.start(of: index) + row.end(of: index)) / 2 - (start + end) / 2)
            if best == nil || overlap > best!.overlap + Self.tolerance
                || (abs(overlap - best!.overlap) <= Self.tolerance && distance < best!.distance) {
                best = (index, overlap, distance)
            }
        }
        return best.map { row.slabs[$0.index].tabID }
    }

    /// Where moving `tabID` in `direction` puts it: past its neighbor along the row, or
    /// into the neighboring expanded row at the place nearest its old horizontal center.
    /// Moving up from the top row or down from the bottom opens a new row, unless the slab
    /// is alone in its row. `nil` when the move changes nothing.
    func moveTarget(of tabID: UUID, toward direction: TableDirection) -> MoveTarget? {
        guard let position = position(of: tabID) else { return nil }
        let row = rows[position.row]
        switch direction {
        case .left, .right:
            let target = position.slab + (direction == .left ? -1 : 1)
            guard row.slabs.indices.contains(target) else { return nil }
            return .row(id: row.id, index: target)
        case .up, .down:
            let slab = row.slabs[position.slab]
            let center = row.start(of: position.slab) + slab.fraction / 2
            if let rowIndex = rowIndex(from: tabID, toward: direction) {
                let target = rows[rowIndex]
                return .row(id: target.id, index: target.insertionIndex(width: slab.fraction, nearCenter: center))
            }
            guard row.slabs.count > 1 else { return nil }
            return .newRow(above: direction == .up)
        }
    }
}

/// What the table keeps that the tab model does not: each slab's width preset and whether it
/// fills the viewport. Saved on the space and synced.
nonisolated struct TableState: Codable, Equatable, Sendable {
    var widths: [UUID: TableWidth] = [:]
    var fills: Set<UUID> = []

    init(widths: [UUID: TableWidth] = [:], fills: Set<UUID> = []) {
        self.widths = widths
        self.fills = fills
    }

    func width(of tabID: UUID) -> TableWidth {
        widths[tabID] ?? .full
    }

    /// Gives `tabID` a preset width and ends its fill.
    mutating func setWidth(_ width: TableWidth, of tabID: UUID) {
        widths[tabID] = width
        fills.remove(tabID)
    }

    /// Advances `tabID`'s preset (⅓ → ½ → ⅔ → 1 → ⅓); a filling slab returns to its preset
    /// instead.
    mutating func cycleWidth(of tabID: UUID) {
        if fills.remove(tabID) == nil {
            widths[tabID] = width(of: tabID).next
        }
    }

    /// Makes `tabID` fill the viewport's width, or returns it to its preset.
    mutating func toggleFill(of tabID: UUID) {
        if fills.remove(tabID) == nil {
            fills.insert(tabID)
        }
    }

    /// Forgets tabs no longer on the table.
    mutating func prune(keeping tabIDs: some Sequence<UUID>) {
        let present = Set(tabIDs)
        widths = widths.filter { present.contains($0.key) }
        fills = fills.filter { present.contains($0) }
    }

    static func decode(_ data: Data?) -> TableState {
        guard let data, let state = try? JSONDecoder().decode(TableState.self, from: data) else { return TableState() }
        return state
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }
}
