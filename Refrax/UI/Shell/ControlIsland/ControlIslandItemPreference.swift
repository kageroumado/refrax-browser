import Foundation

/// Visibility follows each item's identity as its position changes.
nonisolated struct ControlIslandItemPreference: Codable, Equatable, Identifiable {
    let item: ControlIslandItem
    var isVisible: Bool

    var id: ControlIslandItem { item }
}
