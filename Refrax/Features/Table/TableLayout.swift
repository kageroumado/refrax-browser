import Foundation

/// A slab's width as a preset share of the window's width.
nonisolated enum TableWidth: String, Codable, CaseIterable, Sendable {
    case third
    case half
    case twoThirds
    case full

    /// The share of the viewport width a slab of this preset takes.
    var fraction: Double {
        switch self {
        case .third: 1.0 / 3.0
        case .half: 0.5
        case .twoThirds: 2.0 / 3.0
        case .full: 1
        }
    }

    /// The next preset in the cycle ⅓ → ½ → ⅔ → 1 → ⅓.
    var next: Self {
        switch self {
        case .third: .half
        case .half: .twoThirds
        case .twoThirds: .full
        case .full: .third
        }
    }
}

/// A direction on the table: left and right along a row, up and down between rows.
nonisolated enum TableDirection: String, Codable, CaseIterable, Sendable {
    case left
    case right
    case up
    case down

    var opposite: Self {
        switch self {
        case .left: .right
        case .right: .left
        case .up: .down
        case .down: .up
        }
    }

    /// The step one discrete wheel notch takes, or `nil` for an event with no movement.
    ///
    /// Deltas follow `NSEvent.scrollingDeltaX/Y`: a positive vertical delta moves to the
    /// previous row, a positive horizontal delta to the previous slab. With ⇧ held a vertical
    /// notch steps along the row, so a mouse with one wheel reaches both axes.
    static func wheelStep(deltaX: Double, deltaY: Double, shift: Bool) -> Self? {
        if deltaX != 0, abs(deltaX) >= abs(deltaY) {
            return deltaX > 0 ? .left : .right
        }
        guard deltaY != 0 else { return nil }
        if shift {
            return deltaY > 0 ? .left : .right
        }
        return deltaY > 0 ? .up : .down
    }
}

/// One space's table: rows of tabs laid side by side at preset widths, Niri style.
///
/// ## Coordinates
///
/// Every length here is in **viewport-width units**: a full-width slab is 1, a row of three
/// ⅓ slabs is 1 long, and a row's resting offset is the row coordinate of the viewport's left
/// edge in the same units. Storing units keeps the layout exact across window resizes;
/// ``TableCamera`` turns them into points for a viewport size. Rows are one viewport tall.
///
/// ## Invariants
///
/// Every operation returns a layout that keeps them:
/// - no row is empty, and a tab appears at most once;
/// - the focused row and each row's remembered slab are valid indices when the table has
///   slabs;
/// - each row's offset is between 0 and `length − 1`, and 0 for a row shorter than the
///   viewport (left-aligned);
/// - each row's remembered slab is whole at the row's offset, so focus at rest is always a
///   slab fully in view.
nonisolated struct TableLayout: Codable, Equatable, Sendable {
    /// Lengths closer than this are equal, absorbing the rounding of ⅓ and ⅔ sums.
    static let tolerance = 1e-9

    /// One tab on the table.
    struct Slab: Codable, Equatable, Sendable {
        var tabID: UUID
        var width: TableWidth
        /// The slab fills the viewport's width, keeping `width` to return to.
        var fills: Bool = false

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

    /// A horizontal strip of slabs with its own resting offset and remembered slab.
    struct Row: Codable, Equatable, Sendable, Identifiable {
        /// Stable across edits, so a view can follow a row while rows above it come and go.
        var id: UUID
        var slabs: [Slab]
        /// The row coordinate of the viewport's left edge at rest, in viewport widths.
        var offset: Double = 0
        /// The slab focus returns to when this row becomes current.
        var focusedSlab: Int = 0

        init(id: UUID = UUID(), slabs: [Slab], offset: Double = 0, focusedSlab: Int = 0) {
            self.id = id
            self.slabs = slabs
            self.offset = offset
            self.focusedSlab = focusedSlab
        }

        /// The row's length in viewport widths.
        var length: Double {
            slabs.reduce(0) { $0 + $1.fraction }
        }

        /// The largest resting offset: 0 for a row no longer than the viewport, rounding included.
        var maxOffset: Double {
            length - 1 > TableLayout.tolerance ? length - 1 : 0
        }

        /// The left edge of the slab at `index`, in viewport widths from the row's start.
        func start(of index: Int) -> Double {
            slabs[..<index].reduce(0) { $0 + $1.fraction }
        }

        /// The right edge of the slab at `index`.
        func end(of index: Int) -> Double {
            start(of: index) + slabs[index].fraction
        }

        /// `offset` held between 0 and ``maxOffset``.
        func clamped(_ offset: Double) -> Double {
            min(max(offset, 0), maxOffset)
        }

        /// Whether the slab at `index` lies entirely inside a viewport at `offset`.
        func isWhole(_ index: Int, at offset: Double) -> Bool {
            start(of: index) >= offset - TableLayout.tolerance
                && end(of: index) <= offset + 1 + TableLayout.tolerance
        }

        /// The offset nearest `offset` that shows the slab at `index` whole: the view moves
        /// only as far as it must.
        func offset(revealing index: Int, from offset: Double) -> Double {
            let start = start(of: index)
            let end = end(of: index)
            var result = offset
            if start < result - TableLayout.tolerance {
                result = start
            } else if end > result + 1 + TableLayout.tolerance {
                result = end - 1
            }
            return clamped(result)
        }

        /// The row with its offset clamped and its remembered slab valid and whole.
        func normalized() -> Row {
            var row = self
            row.focusedSlab = min(max(row.focusedSlab, 0), max(row.slabs.count - 1, 0))
            row.offset = row.clamped(row.offset)
            if !row.slabs.isEmpty {
                row.offset = row.offset(revealing: row.focusedSlab, from: row.offset)
            }
            return row
        }

        /// Removes the slab at `index`. Focus moves to the neighbor that slides into the gap:
        /// the slab on the right, or the one on the left at the row's end. Slabs that stay on
        /// screen keep their place unless the focused one must move to stay whole.
        mutating func removeSlab(at index: Int) {
            let width = slabs[index].fraction
            slabs.remove(at: index)
            guard !slabs.isEmpty else {
                focusedSlab = 0
                offset = 0
                return
            }
            if index < focusedSlab {
                focusedSlab -= 1
                offset -= width
            } else if index == focusedSlab, index == slabs.count {
                focusedSlab = index - 1
            }
            self = normalized()
        }
    }

    /// A slab's place on the table.
    struct Position: Codable, Hashable, Sendable {
        var row: Int
        var slab: Int
    }

    /// The table from top to bottom.
    private(set) var rows: [Row]
    /// The current row; its ``Row/focusedSlab`` is the current slab.
    private(set) var focusedRow: Int

    /// An empty table.
    init() {
        self.rows = []
        self.focusedRow = 0
    }

    /// A table with these rows, normalized to the invariants.
    init(rows: [Row], focusedRow: Int = 0) {
        self.rows = rows
        self.focusedRow = focusedRow
        self = normalized()
    }

    /// A first table: one row of these tabs in order, full width, focused on the first.
    init(tabIDs: [UUID]) {
        self = TableLayout().reconciled(with: tabIDs)
    }

    // MARK: - Reading

    var isEmpty: Bool {
        rows.isEmpty
    }

    /// The current slab's position, or `nil` for an empty table.
    var focus: Position? {
        guard rows.indices.contains(focusedRow) else { return nil }
        return Position(row: focusedRow, slab: rows[focusedRow].focusedSlab)
    }

    /// The current slab's tab.
    var focusedTabID: UUID? {
        focus.map { self[$0].tabID }
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

    // MARK: - Editing

    /// Opens `tabID` right of the current slab in the current row, Niri's place for a new
    /// window. With `focus` the new slab becomes current and the view moves the least that
    /// shows it whole; otherwise the view stays where it is.
    func inserting(_ tabID: UUID, width: TableWidth = .full, focus: Bool = true) -> TableLayout {
        var layout = removing(tabID)
        let slab = Slab(tabID: tabID, width: width)
        guard layout.rows.indices.contains(layout.focusedRow) else {
            layout.rows = [Row(slabs: [slab])]
            layout.focusedRow = 0
            return layout
        }
        var row = layout.rows[layout.focusedRow]
        let index = row.focusedSlab + 1
        row.slabs.insert(slab, at: index)
        if focus {
            row.focusedSlab = index
            row.offset = row.offset(revealing: index, from: row.offset)
        }
        layout.rows[layout.focusedRow] = row.normalized()
        return layout
    }

    /// Takes `tabID` off the table. The neighbor that slides into the gap becomes the row's
    /// slab; a row left empty closes, and the row below moves up into its place.
    func removing(_ tabID: UUID) -> TableLayout {
        guard let position = position(of: tabID) else { return self }
        var layout = self
        layout.rows[position.row].removeSlab(at: position.slab)
        if layout.rows[position.row].slabs.isEmpty {
            layout.removeRow(at: position.row)
        }
        return layout
    }

    /// Moves focus to the next slab or row in `direction`. Along a row the view moves the
    /// least that shows the new slab whole; between rows the new row's remembered slab
    /// becomes current. At the table's edge the layout is unchanged.
    func movingFocus(_ direction: TableDirection) -> TableLayout {
        guard let focus else { return self }
        var layout = self
        switch direction {
        case .left, .right:
            let target = focus.slab + (direction == .left ? -1 : 1)
            guard rows[focus.row].slabs.indices.contains(target) else { return self }
            layout.rows[focus.row].focusedSlab = target
            layout.rows[focus.row] = layout.rows[focus.row].normalized()
        case .up, .down:
            let target = focus.row + (direction == .up ? -1 : 1)
            guard rows.indices.contains(target) else { return self }
            layout.focusedRow = target
        }
        return layout
    }

    /// Makes `tabID` current, revealing it with the least movement. Unchanged when the tab
    /// is not on the table.
    func focusing(_ tabID: UUID) -> TableLayout {
        guard let position = position(of: tabID) else { return self }
        var layout = self
        layout.focusedRow = position.row
        layout.rows[position.row].focusedSlab = position.slab
        layout.rows[position.row] = layout.rows[position.row].normalized()
        return layout
    }

    /// Moves the current slab in `direction`: past its neighbor along the row, or into the
    /// neighboring row, landing at the place nearest its old horizontal center. Moving up
    /// from the top row or down from the bottom one opens a new row for the slab, unless it
    /// is alone in its row.
    func movingFocusedSlab(_ direction: TableDirection) -> TableLayout {
        guard let focus else { return self }
        switch direction {
        case .left, .right:
            return swappingFocusedSlab(toward: direction == .left ? -1 : 1, at: focus)
        case .up, .down:
            return movingFocusedSlab(toRow: focus.row + (direction == .up ? -1 : 1), from: focus)
        }
    }

    /// Advances the current slab's width preset (⅓ → ½ → ⅔ → 1 → ⅓); a filling slab
    /// returns to its preset instead. The slab's left edge stays put unless the slab must
    /// move to stay whole.
    func cyclingWidth() -> TableLayout {
        updatingFocusedSlab { slab in
            slab.width = slab.fills ? slab.width : slab.width.next
            slab.fills = false
        }
    }

    /// Makes the current slab fill the viewport's width, or returns it to its preset.
    func togglingFill() -> TableLayout {
        updatingFocusedSlab { $0.fills.toggle() }
    }

    /// Matches the table to the space's tabs, favorites excluded by the caller: tabs no
    /// longer present leave, and new ones append to the current row in the given order
    /// without taking focus.
    func reconciled(with tabIDs: [UUID]) -> TableLayout {
        let present = Set(tabIDs)
        var layout = self
        for tabID in self.tabIDs where !present.contains(tabID) {
            layout = layout.removing(tabID)
        }
        var placed = Set(layout.tabIDs)
        for tabID in tabIDs where !placed.contains(tabID) {
            placed.insert(tabID)
            if layout.rows.indices.contains(layout.focusedRow) {
                layout.rows[layout.focusedRow].slabs.append(Slab(tabID: tabID))
            } else {
                layout.rows = [Row(slabs: [Slab(tabID: tabID)])]
                layout.focusedRow = 0
            }
        }
        return layout.normalized()
    }

    /// Settles the view at `rest`, the target ``TableCamera`` resolves when motion ends.
    func resting(at rest: TableRest) -> TableLayout {
        guard rows.indices.contains(rest.row) else { return self }
        var layout = self
        layout.focusedRow = rest.row
        layout.rows[rest.row].offset = rest.offset
        layout.rows[rest.row].focusedSlab = rest.focusedSlab
        layout.rows[rest.row] = layout.rows[rest.row].normalized()
        return layout
    }

    /// The layout with every invariant restored: empty rows and repeated tabs dropped,
    /// indices and offsets clamped, each row's remembered slab whole.
    func normalized() -> TableLayout {
        var seen = Set<UUID>()
        var layout = self
        layout.rows = rows.compactMap { row in
            var row = row
            row.slabs = row.slabs.filter { seen.insert($0.tabID).inserted }
            return row.slabs.isEmpty ? nil : row.normalized()
        }
        layout.focusedRow = min(max(focusedRow, 0), max(layout.rows.count - 1, 0))
        return layout
    }

    // MARK: - Private

    private mutating func removeRow(at index: Int) {
        rows.remove(at: index)
        if index < focusedRow || (index == focusedRow && index == rows.count) {
            focusedRow = max(focusedRow - 1, 0)
        }
        if rows.isEmpty {
            focusedRow = 0
        }
    }

    private func updatingFocusedSlab(_ update: (inout Slab) -> Void) -> TableLayout {
        guard let focus else { return self }
        var layout = self
        update(&layout.rows[focus.row].slabs[focus.slab])
        layout.rows[focus.row] = layout.rows[focus.row].normalized()
        return layout
    }

    private func swappingFocusedSlab(toward step: Int, at focus: Position) -> TableLayout {
        let target = focus.slab + step
        guard rows[focus.row].slabs.indices.contains(target) else { return self }
        var layout = self
        layout.rows[focus.row].slabs.swapAt(focus.slab, target)
        layout.rows[focus.row].focusedSlab = target
        layout.rows[focus.row] = layout.rows[focus.row].normalized()
        return layout
    }

    private func movingFocusedSlab(toRow targetRow: Int, from focus: Position) -> TableLayout {
        let source = rows[focus.row]
        let slab = source.slabs[focus.slab]
        let screenLeft = source.start(of: focus.slab) - source.offset
        let screenCenter = screenLeft + slab.fraction / 2

        var layout = self
        if rows.indices.contains(targetRow) {
            layout.rows[focus.row].removeSlab(at: focus.slab)
            let target = layout.rows[targetRow]
            let index = Self.insertionIndex(in: target, width: slab.fraction, nearCenter: screenCenter + target.offset)
            var row = target
            row.slabs.insert(slab, at: index)
            row.focusedSlab = index
            row.offset = row.clamped(row.start(of: index) - screenLeft)
            layout.rows[targetRow] = row.normalized()
            layout.focusedRow = targetRow
            if layout.rows[focus.row].slabs.isEmpty {
                layout.removeRow(at: focus.row)
            }
            return layout
        }

        guard source.slabs.count > 1 else { return self }
        layout.rows[focus.row].removeSlab(at: focus.slab)
        let row = Row(slabs: [slab])
        if targetRow < 0 {
            layout.rows.insert(row, at: 0)
            layout.focusedRow = 0
        } else {
            layout.rows.append(row)
            layout.focusedRow = layout.rows.count - 1
        }
        return layout
    }

    /// The place in `row` where a slab of `width` has its center nearest `center`.
    private static func insertionIndex(in row: Row, width: Double, nearCenter center: Double) -> Int {
        var best = 0
        var bestDistance = Double.infinity
        for index in 0 ... row.slabs.count {
            let distance = abs(row.start(of: index) + width / 2 - center)
            if distance < bestDistance - tolerance {
                best = index
                bestDistance = distance
            }
        }
        return best
    }
}

/// Where the view comes to rest: a row, its offset in viewport widths, and its current slab.
nonisolated struct TableRest: Equatable, Sendable {
    var row: Int
    var offset: Double
    var focusedSlab: Int
}
