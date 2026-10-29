import Foundation
import Observation

/// Shares the rail's saved arrangement across browser windows.
@Observable
final class ControlIslandConfiguration {
    static let shared = ControlIslandConfiguration(defaults: .standard)
    static let storageKey = "controlIsland.items"
    static let avoidanceKey = "controlIsland.avoidsPageControls"
    static let restKey = "controlIsland.restsWhenIdle"
    static let tintKey = "controlIsland.tintsWithSpaceColor"
    static let edgeHidingKey = "controlIsland.hidesAtEdge"
    static let fileIslandEdgeHidingKey = "fileIsland.hidesAtEdge"

    private(set) var items: [ControlIslandItemPreference]
    private(set) var avoidsPageControls: Bool
    /// The glass clears and the glyphs recede while the pointer is far away or still.
    private(set) var restsWhenIdle: Bool
    /// The glass carries the active space's color.
    private(set) var tintsWithSpaceColor: Bool
    /// Snapped to the window's left or right edge, the rail slides past it and returns when the
    /// pointer reaches that edge, as the Dock hides.
    private(set) var hidesAtEdge: Bool
    /// Snapped to the window's left or right edge, the File Island slides past it while nothing
    /// on it needs attention, and returns when the pointer reaches that edge or a file arrives.
    private(set) var fileIslandHidesAtEdge: Bool
    @ObservationIgnored private let defaults: UserDefaults?

    static var defaultItems: [ControlIslandItemPreference] {
        ControlIslandItem.defaultOrder.map { .init(item: $0, isVisible: $0.isDefault) }
    }

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        self.avoidsPageControls = defaults?.object(forKey: Self.avoidanceKey) as? Bool ?? true
        self.restsWhenIdle = defaults?.object(forKey: Self.restKey) as? Bool ?? true
        self.tintsWithSpaceColor = defaults?.object(forKey: Self.tintKey) as? Bool ?? true
        self.hidesAtEdge = defaults?.object(forKey: Self.edgeHidingKey) as? Bool ?? false
        self.fileIslandHidesAtEdge = defaults?.object(forKey: Self.fileIslandEdgeHidingKey) as? Bool ?? true
        let records = defaults?.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([StoredItem].self, from: $0) } ?? []
        let known = records.compactMap { record in
            ControlIslandItem(rawValue: record.id).map { ControlIslandItemPreference(item: $0, isVisible: record.isVisible) }
        }
        self.items = Self.normalized(known)
        // A saved arrangement that names a control the rail does not have is rewritten without it.
        if known.count != records.count {
            saveItems()
        }
    }

    var visibleItems: [ControlIslandItem] {
        items.filter(\.isVisible).map(\.item)
    }

    func apply(
        _ items: [ControlIslandItemPreference],
        avoidsPageControls: Bool = true,
        restsWhenIdle: Bool = true,
        tintsWithSpaceColor: Bool = true,
        hidesAtEdge: Bool = false,
    ) {
        self.items = Self.normalized(items)
        self.avoidsPageControls = avoidsPageControls
        self.restsWhenIdle = restsWhenIdle
        self.tintsWithSpaceColor = tintsWithSpaceColor
        defaults?.set(avoidsPageControls, forKey: Self.avoidanceKey)
        defaults?.set(restsWhenIdle, forKey: Self.restKey)
        defaults?.set(tintsWithSpaceColor, forKey: Self.tintKey)
        setHidesAtEdge(hidesAtEdge)
        saveItems()
    }

    func setHidesAtEdge(_ hides: Bool) {
        hidesAtEdge = hides
        defaults?.set(hides, forKey: Self.edgeHidingKey)
    }

    func setFileIslandHidesAtEdge(_ hides: Bool) {
        fileIslandHidesAtEdge = hides
        defaults?.set(hides, forKey: Self.fileIslandEdgeHidingKey)
    }

    private func saveItems() {
        let records = items.map { StoredItem(id: $0.item.rawValue, isVisible: $0.isVisible) }
        guard let data = try? JSONEncoder().encode(records) else { return }
        defaults?.set(data, forKey: Self.storageKey)
    }

    private static func normalized(_ items: [ControlIslandItemPreference]) -> [ControlIslandItemPreference] {
        var seen = Set<ControlIslandItem>()
        let unique = items.filter { seen.insert($0.item).inserted }
        return unique + defaultItems.filter { !seen.contains($0.item) }
    }

    private struct StoredItem: Codable {
        let id: String
        let isVisible: Bool
    }
}
