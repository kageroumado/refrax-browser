import Foundation
import Observation

/// Shares the rail's saved arrangement across browser windows.
@Observable
final class ControlIslandConfiguration {
    static let shared = ControlIslandConfiguration(defaults: .standard)
    static let storageKey = "controlIsland.items"
    static let dragTargetKey = "controlIsland.optionDragTarget"
    static let avoidanceKey = "controlIsland.avoidsPageControls"
    static let restKey = "controlIsland.restsWhenIdle"
    static let tintKey = "controlIsland.tintsWithSpaceColor"

    private(set) var items: [ControlIslandItemPreference]
    private(set) var optionDragTarget: ControlIslandDragTarget
    private(set) var avoidsPageControls: Bool
    /// The glass clears and the glyphs recede while the pointer is far away or still.
    private(set) var restsWhenIdle: Bool
    /// The glass carries the active space's color, as the sidebar does.
    private(set) var tintsWithSpaceColor: Bool
    @ObservationIgnored private let defaults: UserDefaults?

    static var defaultItems: [ControlIslandItemPreference] {
        ControlIslandItem.allCases.map { .init(item: $0, isVisible: $0.isDefault) }
    }

    init(defaults: UserDefaults?) {
        self.defaults = defaults
        avoidsPageControls = defaults?.object(forKey: Self.avoidanceKey) as? Bool ?? true
        restsWhenIdle = defaults?.object(forKey: Self.restKey) as? Bool ?? true
        tintsWithSpaceColor = defaults?.object(forKey: Self.tintKey) as? Bool ?? true
        optionDragTarget = defaults?.string(forKey: Self.dragTargetKey)
            .flatMap(ControlIslandDragTarget.init(rawValue:)) ?? .panel
        let records = defaults?.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([StoredItem].self, from: $0) } ?? []
        items = Self.normalized(records.compactMap { record in
            ControlIslandItem(rawValue: record.id).map { .init(item: $0, isVisible: record.isVisible) }
        })
    }

    var visibleItems: [ControlIslandItem] {
        items.filter(\.isVisible).map(\.item)
    }

    func apply(_ items: [ControlIslandItemPreference], optionDragTarget: ControlIslandDragTarget = .panel, avoidsPageControls: Bool = true,
               restsWhenIdle: Bool = true, tintsWithSpaceColor: Bool = true) {
        self.items = Self.normalized(items)
        self.optionDragTarget = optionDragTarget
        self.avoidsPageControls = avoidsPageControls
        self.restsWhenIdle = restsWhenIdle
        self.tintsWithSpaceColor = tintsWithSpaceColor
        defaults?.set(avoidsPageControls, forKey: Self.avoidanceKey)
        defaults?.set(restsWhenIdle, forKey: Self.restKey)
        defaults?.set(tintsWithSpaceColor, forKey: Self.tintKey)
        defaults?.set(optionDragTarget.rawValue, forKey: Self.dragTargetKey)
        let records = self.items.map { StoredItem(id: $0.item.rawValue, isVisible: $0.isVisible) }
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
