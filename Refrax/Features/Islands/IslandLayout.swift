import Foundation

/// A cell on an island's grid. Columns grow to the right, rows grow downward.
nonisolated struct IslandCell: Codable, Hashable, Sendable {
    var x: Int
    var y: Int

    func offset(_ dx: Int, _ dy: Int) -> IslandCell {
        IslandCell(x: x + dx, y: y + dy)
    }
}

/// A chip's size on the grid, in cells.
nonisolated struct IslandSpan: Codable, Hashable, Sendable {
    var width: Int
    var height: Int

    static let one = IslandSpan(width: 1, height: 1)
}

/// A chip's shape: the tab at one of three sizes on the same grid.
nonisolated enum ChipShape: String, Codable, Sendable {
    /// Favicon and title, one cell.
    case title
    /// A live preview of the page or a kept region of it, a rectangle of cells.
    case preview
}

/// Where a tab sits on its island and how it shows.
nonisolated struct ChipPlacement: Codable, Equatable, Sendable {
    var cell: IslandCell
    var shape: ChipShape = .title
    var span: IslandSpan = .one
    /// The kept region a preview chip shows, or the whole page.
    var region: FloatingPageRegion?

    init(cell: IslandCell, shape: ChipShape = .title, span: IslandSpan = .one, region: FloatingPageRegion? = nil) {
        self.cell = cell
        self.shape = shape
        self.span = span
        self.region = region
    }

    /// Every cell the chip covers.
    var cells: Set<IslandCell> {
        var result = Set<IslandCell>()
        for dx in 0 ..< max(1, span.width) {
            for dy in 0 ..< max(1, span.height) {
                result.insert(cell.offset(dx, dy))
            }
        }
        return result
    }
}

/// An island on the window: its place, whether it stays when ⌃ is up, and how its chips show.
nonisolated struct IslandPlacement: Codable, Equatable, Sendable {
    /// The island's top-left corner, normalized to the window's area (0 ... 1 on each axis).
    var x: Double
    var y: Double
    var isPinned: Bool = false
    /// Chips show favicons only, the favorites column's look.
    var iconsOnly: Bool = false

    init(x: Double, y: Double, isPinned: Bool = false, iconsOnly: Bool = false) {
        self.x = x
        self.y = y
        self.isPinned = isPinned
        self.iconsOnly = iconsOnly
    }
}

/// What the islands keep that the tab model does not: each tab's chip and each island's
/// placement. Saved on the space and synced.
nonisolated struct IslandState: Codable, Equatable, Sendable {
    var chips: [UUID: ChipPlacement] = [:]
    var islands: [UUID: IslandPlacement] = [:]

    init(chips: [UUID: ChipPlacement] = [:], islands: [UUID: IslandPlacement] = [:]) {
        self.chips = chips
        self.islands = islands
    }

    /// Forgets tabs and islands no longer present.
    mutating func prune(tabs: some Sequence<UUID>, islands islandIDs: some Sequence<UUID>) {
        let presentTabs = Set(tabs)
        let presentIslands = Set(islandIDs)
        chips = chips.filter { presentTabs.contains($0.key) }
        islands = islands.filter { presentIslands.contains($0.key) }
    }

    static func decode(_ data: Data?) -> IslandState {
        guard let data, let state = try? JSONDecoder().decode(IslandState.self, from: data) else { return IslandState() }
        return state
    }

    func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }
}

/// One island's chips on their grid, with the rules that keep the island one connected shape:
/// every chip shares an edge with another, a new chip goes below the chip it came from, and
/// a chip that leaves lets the chips below it move up and anything cut loose slide back.
///
/// Cells are the unit; ``IslandGeometry`` turns them into points.
nonisolated struct IslandLayout: Equatable, Sendable {
    private(set) var chips: [UUID: ChipPlacement]

    init(chips: [UUID: ChipPlacement] = [:]) {
        self.chips = chips
    }

    // MARK: - Reading

    var isEmpty: Bool {
        chips.isEmpty
    }

    var tabIDs: [UUID] {
        chips.sorted { lhs, rhs in
            lhs.value.cell.y != rhs.value.cell.y ? lhs.value.cell.y < rhs.value.cell.y : lhs.value.cell.x < rhs.value.cell.x
        }.map(\.key)
    }

    subscript(tabID: UUID) -> ChipPlacement? {
        chips[tabID]
    }

    /// Every cell any chip covers, with its chip.
    var occupancy: [IslandCell: UUID] {
        var result: [IslandCell: UUID] = [:]
        for (tabID, chip) in chips {
            for cell in chip.cells {
                result[cell] = tabID
            }
        }
        return result
    }

    /// The smallest cell range holding every chip: `(minX, minY, maxX, maxY)`, or `nil`.
    var bounds: (minX: Int, minY: Int, maxX: Int, maxY: Int)? {
        let cells = occupancy.keys
        guard let minX = cells.map(\.x).min(), let maxX = cells.map(\.x).max(),
              let minY = cells.map(\.y).min(), let maxY = cells.map(\.y).max() else { return nil }
        return (minX, minY, maxX, maxY)
    }

    /// The chip at `cell`, if any.
    func tabID(at cell: IslandCell) -> UUID? {
        occupancy[cell]
    }

    /// The chip beside `tabID` in `direction`: the one sharing the most edge with it on that
    /// side, else the nearest chip across the row or column in that direction.
    func neighbor(of tabID: UUID, toward direction: TableDirection) -> UUID? {
        guard let chip = chips[tabID] else { return nil }
        let occupancy = occupancy
        let cells = chip.cells
        var counts: [UUID: Int] = [:]
        for cell in cells {
            let next: IslandCell = switch direction {
            case .left: cell.offset(-1, 0)
            case .right: cell.offset(1, 0)
            case .up: cell.offset(0, -1)
            case .down: cell.offset(0, 1)
            }
            if let other = occupancy[next], other != tabID {
                counts[other, default: 0] += 1
            }
        }
        if let best = counts.max(by: { $0.value != $1.value ? $0.value < $1.value : $0.key.uuidString > $1.key.uuidString }) {
            return best.key
        }
        // Nothing adjacent: the nearest chip along the same row or column, so a gap left by
        // a move does not end the walk.
        var nearest: (id: UUID, distance: Int)?
        for (other, placement) in chips where other != tabID {
            for cell in placement.cells {
                let distance: Int? = switch direction {
                case .left: cell.y >= chip.cell.y && cell.y < chip.cell.y + chip.span.height && cell.x < chip.cell.x ? chip.cell.x - cell.x : nil
                case .right: cell.y >= chip.cell.y && cell.y < chip.cell.y + chip.span.height && cell.x >= chip.cell.x + chip.span.width ? cell.x - chip.cell.x : nil
                case .up: cell.x >= chip.cell.x && cell.x < chip.cell.x + chip.span.width && cell.y < chip.cell.y ? chip.cell.y - cell.y : nil
                case .down: cell.x >= chip.cell.x && cell.x < chip.cell.x + chip.span.width && cell.y >= chip.cell.y + chip.span.height ? cell.y - chip.cell.y : nil
                }
                if let distance, nearest == nil || distance < nearest!.distance {
                    nearest = (other, distance)
                }
            }
        }
        return nearest?.id
    }

    /// Whether a chip with `span` at `cell` would overlap no other chip (`tabID` excluded) and
    /// share an edge with one; the first chip of an island may go anywhere.
    func canPlace(_ tabID: UUID?, at cell: IslandCell, span: IslandSpan = .one) -> Bool {
        var others = chips
        if let tabID {
            others.removeValue(forKey: tabID)
        }
        guard !others.isEmpty else { return true }
        let placement = ChipPlacement(cell: cell, span: span)
        let occupied = Set(others.values.flatMap(\.cells))
        guard placement.cells.isDisjoint(with: occupied) else { return false }
        return Self.touches(placement.cells, occupied)
    }

    /// Whether every chip reaches every other through shared edges.
    var isConnected: Bool {
        guard let start = chips.keys.first else { return true }
        var seen: Set<UUID> = [start]
        var frontier = [start]
        let occupancy = occupancy
        while let current = frontier.popLast() {
            for cell in chips[current]!.cells {
                for next in [cell.offset(1, 0), cell.offset(-1, 0), cell.offset(0, 1), cell.offset(0, -1)] {
                    if let other = occupancy[next], seen.insert(other).inserted {
                        frontier.append(other)
                    }
                }
            }
        }
        return seen.count == chips.count
    }

    /// The chip and the line of chips directly below it, as far as the column runs: the
    /// subtree a new island takes.
    func subtree(below tabID: UUID) -> [UUID] {
        guard let chip = chips[tabID] else { return [] }
        var result = [tabID]
        var cell = chip.cell.offset(0, chip.span.height)
        while let next = self.tabID(at: cell), !result.contains(next) {
            result.append(next)
            cell = cell.offset(0, chips[next]!.span.height)
        }
        return result
    }

    // MARK: - Editing

    /// Places `tabID` below `source`: in the cell under it, or the next free cell to the right
    /// along that row of children. With no source, or a source not on the island, the chip
    /// goes under the island's lowest column, or at the origin of an empty island.
    func placing(_ tabID: UUID, below source: UUID?) -> IslandLayout {
        var layout = self
        layout.chips.removeValue(forKey: tabID)
        guard !layout.chips.isEmpty else {
            layout.chips[tabID] = ChipPlacement(cell: IslandCell(x: 0, y: 0))
            return layout
        }
        let occupied = Set(layout.chips.values.flatMap(\.cells))
        if let source, let parent = layout.chips[source] {
            var cell = parent.cell.offset(0, parent.span.height)
            while occupied.contains(cell) {
                cell = cell.offset(1, 0)
            }
            layout.chips[tabID] = ChipPlacement(cell: cell)
            return layout
        }
        let bounds = layout.bounds!
        let column = bounds.minX
        layout.chips[tabID] = ChipPlacement(cell: IslandCell(x: column, y: bounds.maxY + 1))
        return layout.reconnected()
    }

    /// Moves `tabID` to `cell` when it may land there.
    func moving(_ tabID: UUID, to cell: IslandCell) -> IslandLayout {
        guard var chip = chips[tabID], canPlace(tabID, at: cell, span: chip.span) else { return self }
        var layout = self
        chip.cell = cell
        layout.chips[tabID] = chip
        return layout
    }

    /// Gives `tabID` a shape and span, keeping its cell when the chip still fits there and
    /// otherwise the nearest cell where it does.
    func reshaping(_ tabID: UUID, shape: ChipShape, span: IslandSpan, region: FloatingPageRegion? = nil) -> IslandLayout {
        guard var chip = chips[tabID] else { return self }
        var layout = self
        chip.shape = shape
        chip.span = span
        chip.region = region
        layout.chips[tabID] = chip
        if !layout.overlaps(tabID) {
            return layout
        }
        for cell in layout.freeCells(for: tabID, span: span) {
            if layout.canPlace(tabID, at: cell, span: span) {
                chip.cell = cell
                layout.chips[tabID] = chip
                return layout
            }
        }
        return self
    }

    /// Takes `tabID` off the island: the chips below it move up a row, and anything cut loose
    /// slides toward the island's center until it touches.
    func removing(_ tabID: UUID) -> IslandLayout {
        guard let chip = chips[tabID] else { return self }
        var layout = self
        layout.chips.removeValue(forKey: tabID)
        // Top first, so each chip finds the cell above it already vacated.
        let below = layout.chips
            .filter { $0.value.cell.y > chip.cell.y && $0.value.cell.x >= chip.cell.x && $0.value.cell.x < chip.cell.x + chip.span.width }
            .sorted { $0.value.cell.y < $1.value.cell.y }
        for (other, placement) in below {
            var moved = placement
            moved.cell.y -= chip.span.height
            let occupied = Set(layout.chips.filter { $0.key != other }.values.flatMap(\.cells))
            if moved.cells.isDisjoint(with: occupied) {
                layout.chips[other] = moved
            }
        }
        return layout.reconnected()
    }

    /// Adds every chip of `other` beside this island's chips, under its lowest row.
    func merging(_ other: IslandLayout) -> IslandLayout {
        var layout = self
        for tabID in other.tabIDs {
            layout = layout.placing(tabID, below: nil)
        }
        return layout
    }

    /// Every chip reaching every other, with the islands of chips that do not slid toward
    /// the largest one until they touch.
    func reconnected() -> IslandLayout {
        var layout = self
        var components = layout.components()
        guard components.count > 1 else { return layout }
        components.sort { $0.count > $1.count }
        var anchored = Set(components[0])
        for component in components.dropFirst() {
            var moved = layout
            let anchoredCells = Set(anchored.compactMap { moved.chips[$0] }.flatMap(\.cells))
            let center = Self.center(of: anchoredCells)
            var steps = 0
            while steps < 64 {
                let cells = Set(component.compactMap { moved.chips[$0] }.flatMap(\.cells))
                if Self.touches(cells, anchoredCells) {
                    break
                }
                let from = Self.center(of: cells)
                let dx = center.x == from.x ? 0 : (center.x > from.x ? 1 : -1)
                let dy = center.y == from.y ? 0 : (center.y > from.y ? 1 : -1)
                let stepX = abs(center.x - from.x) >= abs(center.y - from.y) ? dx : 0
                let stepY = stepX == 0 ? dy : 0
                guard stepX != 0 || stepY != 0 else { break }
                let shifted = Set(cells.map { $0.offset(stepX, stepY) })
                if !shifted.isDisjoint(with: anchoredCells) {
                    break
                }
                for tabID in component {
                    guard var chip = moved.chips[tabID] else { continue }
                    chip.cell = chip.cell.offset(stepX, stepY)
                    moved.chips[tabID] = chip
                }
                steps += 1
            }
            layout = moved
            anchored.formUnion(component)
        }
        return layout
    }

    // MARK: - Private

    private func overlaps(_ tabID: UUID) -> Bool {
        guard let chip = chips[tabID] else { return false }
        let others = Set(chips.filter { $0.key != tabID }.values.flatMap(\.cells))
        return !chip.cells.isDisjoint(with: others)
    }

    /// Cells near the chip's own, nearest first, for a reshaped chip to try.
    private func freeCells(for tabID: UUID, span: IslandSpan) -> [IslandCell] {
        guard let chip = chips[tabID] else { return [] }
        var cells: [IslandCell] = []
        for radius in 0 ... 6 {
            for dx in -radius ... radius {
                for dy in -radius ... radius where abs(dx) == radius || abs(dy) == radius {
                    cells.append(chip.cell.offset(dx, dy))
                }
            }
        }
        return cells
    }

    private func components() -> [[UUID]] {
        var remaining = Set(chips.keys)
        var result: [[UUID]] = []
        let occupancy = occupancy
        while let start = remaining.first {
            var component = [start]
            remaining.remove(start)
            var frontier = [start]
            while let current = frontier.popLast() {
                for cell in chips[current]!.cells {
                    for next in [cell.offset(1, 0), cell.offset(-1, 0), cell.offset(0, 1), cell.offset(0, -1)] {
                        if let other = occupancy[next], remaining.remove(other) != nil {
                            component.append(other)
                            frontier.append(other)
                        }
                    }
                }
            }
            result.append(component)
        }
        return result
    }

    private static func touches(_ cells: Set<IslandCell>, _ others: Set<IslandCell>) -> Bool {
        cells.contains { cell in
            [cell.offset(1, 0), cell.offset(-1, 0), cell.offset(0, 1), cell.offset(0, -1)].contains { others.contains($0) }
        }
    }

    private static func center(of cells: Set<IslandCell>) -> (x: Int, y: Int) {
        guard !cells.isEmpty else { return (0, 0) }
        let x = cells.map(\.x).reduce(0, +) / cells.count
        let y = cells.map(\.y).reduce(0, +) / cells.count
        return (x, y)
    }
}
