import Foundation

/// Keeps each space's table in step with its tabs: new tabs open right of the current slab,
/// closed tabs leave with their neighbor sliding in, and a space whose tabs changed while
/// the table was not watching is reconciled when it becomes current.
///
/// Writes go to ``Space/table``; saving the model context stays with the caller.
@MainActor
final class TableManager {
    /// The tabs a space's table holds, in the space's order: every non-archived tab that
    /// is not a favorite.
    static func tableTabIDs(of space: Space) -> [UUID] {
        space.mainTabs.filter { !$0.isFavorite }.map(\.id)
    }

    /// Matches `space`'s table to its tabs, writing only when something changed.
    func reconcile(_ space: Space) {
        update(space) { $0.reconciled(with: Self.tableTabIDs(of: space)) }
    }

    /// Places a newly opened tab right of the current slab; with `focus` it becomes current.
    func tabOpened(_ tabID: UUID, in space: Space, focus: Bool = true) {
        update(space) { $0.inserting(tabID, focus: focus) }
    }

    /// Takes a closed tab off its space's table.
    func tabClosed(_ tabID: UUID, in space: Space) {
        update(space) { $0.removing(tabID) }
    }

    /// Makes `tabID` the current slab of its space's table.
    func tabActivated(_ tabID: UUID, in space: Space) {
        update(space) { $0.focusing(tabID) }
    }

    private func update(_ space: Space, _ transform: (TableLayout) -> TableLayout) {
        let current = space.table
        let updated = transform(current)
        if updated != current {
            space.table = updated
        }
    }
}
