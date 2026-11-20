import Foundation

/// A tab's group, neighbors, pin, card placement, and selection before an island edit.
struct IslandTabLocation {
    let tabID: UUID
    let spaceID: UUID
    let groupID: UUID?
    let previousID: UUID?
    let nextID: UUID?
    /// The pinned tab's home address; `nil` for a tab that was not pinned.
    let home: URL?
    let isDetached: Bool
    let placement: FloatingTabPlacement?
    let activeTabID: UUID?
}
