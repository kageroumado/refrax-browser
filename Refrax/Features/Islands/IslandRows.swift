import Foundation

/// One row of an island: a tab, or the header of a group nested in the island's group.
nonisolated enum IslandRow: Hashable, Sendable, Identifiable {
    case tab(UUID)
    /// A nested group's header, which folds and unfolds its tabs.
    case section(UUID)

    var id: UUID {
        switch self {
        case let .tab(id), let .section(id): id
        }
    }

    var tabID: UUID? {
        if case let .tab(id) = self {
            id
        } else {
            nil
        }
    }

    var sectionID: UUID? {
        if case let .section(id) = self {
            id
        } else {
            nil
        }
    }
}

/// A group nested in an island's group, shown in the island under a header of its own.
nonisolated struct IslandSection: Equatable, Sendable, Identifiable {
    let id: UUID
    var title: String
    var colorString: String?
    var iconName: String?
    /// Every tab of the group, in the tab list's order, shown or folded away.
    var tabIDs: [UUID]
    /// Folded to its header; the fold is the group's own (`TabGroup.isCollapsed`).
    var isCollapsed: Bool
}

/// Where a row let go between two rows lands: in the island's own group or one of its
/// sections, between two tabs of that group.
nonisolated struct IslandInsertion: Equatable, Sendable {
    /// The nested group the row joins; `nil` for the island's own group.
    var section: UUID?
    var after: UUID?
    var before: UUID?
}

/// An island's rows: its own tabs first, then each nested group's header and, unless the
/// group is folded, its tabs. A folded group still shows the current tab under its header,
/// so the row the window shows is never folded away.
nonisolated struct IslandRowLayout: Equatable, Sendable {
    /// The rows on the island, in order.
    let rows: [IslandRow]
    /// The tab rows shown, in order: what a step up or down moves through.
    let tabIDs: [UUID]
    /// Every tab of the island, shown or folded away, in the tab list's order.
    let allTabIDs: [UUID]
    /// The island's own tabs, outside any section.
    let ownTabIDs: [UUID]
    let sections: [IslandSection]

    init(ownTabIDs: [UUID] = [], sections: [IslandSection] = [], currentTabID: UUID? = nil) {
        var rows = ownTabIDs.map(IslandRow.tab)
        for section in sections {
            rows.append(.section(section.id))
            if section.isCollapsed {
                if let currentTabID, section.tabIDs.contains(currentTabID) {
                    rows.append(.tab(currentTabID))
                }
            } else {
                rows += section.tabIDs.map(IslandRow.tab)
            }
        }
        self.rows = rows
        self.tabIDs = rows.compactMap(\.tabID)
        self.allTabIDs = ownTabIDs + sections.flatMap(\.tabIDs)
        self.ownTabIDs = ownTabIDs
        self.sections = sections
    }

    var count: Int {
        rows.count
    }

    /// The row `tabID` is on, or `nil` while its section is folded.
    func row(of tabID: UUID) -> Int? {
        rows.firstIndex(of: .tab(tabID))
    }

    /// The nested group `tabID` belongs to; `nil` for the island's own tabs and for tabs
    /// elsewhere.
    func section(of tabID: UUID) -> IslandSection? {
        sections.first { $0.tabIDs.contains(tabID) }
    }

    func section(_ id: UUID) -> IslandSection? {
        sections.first { $0.id == id }
    }

    /// Where a row dropped before row `index` lands, counted among the rows without
    /// `moving`, the row on its way: with the tab above it when there is one (after a
    /// section's header, into that section), else among the island's own tabs.
    func insertion(at index: Int, moving: UUID? = nil) -> IslandInsertion {
        let rows = rows.filter { $0 != moving.map(IslandRow.tab) }
        let index = min(max(0, index), rows.count)
        let above = index > 0 ? rows[index - 1] : nil
        switch above {
        case nil:
            return IslandInsertion(section: nil, after: nil, before: ownTabIDs.first { $0 != moving })
        case let .section(id)?:
            let members = (section(id)?.tabIDs ?? []).filter { $0 != moving }
            // Into a folded section the row goes last, where it is out of sight with the rest.
            if section(id)?.isCollapsed == true {
                return IslandInsertion(section: id, after: members.last, before: nil)
            }
            return IslandInsertion(section: id, after: nil, before: members.first)
        case let .tab(tabID)?:
            let group = section(of: tabID)
            let members = (group?.tabIDs ?? ownTabIDs).filter { $0 != moving }
            let next = members.firstIndex(of: tabID).map { $0 + 1 }.flatMap { members.indices.contains($0) ? members[$0] : nil }
            return IslandInsertion(section: group?.id, after: tabID, before: next)
        }
    }

    /// The slot at the end of the island's own tabs, ahead of its sections.
    func endOfOwnTabs(moving: UUID? = nil) -> IslandInsertion {
        IslandInsertion(section: nil, after: ownTabIDs.last { $0 != moving }, before: nil)
    }
}
