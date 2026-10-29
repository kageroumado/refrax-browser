import Foundation

/// A tab's group, neighbors, card placement, and selection before an island edit.
struct IslandTabLocation {
    let tabID: UUID
    let spaceID: UUID
    let groupID: UUID?
    let previousID: UUID?
    let nextID: UUID?
    let isDetached: Bool
    let placement: FloatingTabPlacement?
    let activeTabID: UUID?
}
