import Foundation

/// Where an island sits on the window and how it shows its tabs.
nonisolated struct IslandPlacement: Codable, Equatable, Sendable {
    /// The island's top-left corner, normalized to the window's area (0 ... 1 on each axis).
    var x: Double
    var y: Double
    /// A pinned island stays on screen when the reveal key is up.
    var isPinned: Bool = false
    /// Rows show favicons only, the favorites column's look.
    var iconsOnly: Bool = false

    init(x: Double, y: Double, isPinned: Bool = false, iconsOnly: Bool = false) {
        self.x = x
        self.y = y
        self.isPinned = isPinned
        self.iconsOnly = iconsOnly
    }
}

/// What the islands keep for a space: each island's place, and the tabs taken out of their
/// islands to float as live cards. Membership and order are the tab list itself.
nonisolated struct IslandState: Codable, Equatable, Sendable {
    var islands: [UUID: IslandPlacement] = [:]
    var detached: Set<UUID> = []

    init(islands: [UUID: IslandPlacement] = [:], detached: Set<UUID> = []) {
        self.islands = islands
        self.detached = detached
    }

    /// Forgets tabs and islands no longer present.
    mutating func prune(tabs: some Sequence<UUID>, islands islandIDs: some Sequence<UUID>) {
        let presentTabs = Set(tabs)
        let presentIslands = Set(islandIDs)
        detached = detached.filter { presentTabs.contains($0) }
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
