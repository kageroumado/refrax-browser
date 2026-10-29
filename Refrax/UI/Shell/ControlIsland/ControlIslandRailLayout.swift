import Foundation

/// The rail's rows and the gaps between them, top to bottom.
///
/// The main section comes first in its customized order, then the additional controls
/// in theirs. A gap carries a divider line around a group and at the boundary between
/// the sections, except between the space picker and the favorites, which share a plain
/// gap. The grip closes the rail in a full control row.
nonisolated struct ControlIslandRailLayout: Equatable {
    enum Element: Equatable, Identifiable {
        case row(ControlIslandItem)
        /// A gap of ``ControlIslandPlacement/sectionGap`` with a divider line.
        case line(before: ControlIslandItem)
        /// A gap of ``ControlIslandPlacement/sectionGap`` between groups.
        case gap(before: ControlIslandItem)
        /// The handle that moves the rail, centered in its final control row.
        case grip

        var id: String {
            switch self {
            case let .row(item): item.rawValue
            case let .line(item): "line-\(item.rawValue)"
            case let .gap(item): "gap-\(item.rawValue)"
            case .grip: "grip"
            }
        }
    }

    let elements: [Element]

    var rows: [ControlIslandItem] {
        elements.compactMap { element in
            if case let .row(item) = element {
                item
            } else {
                nil
            }
        }
    }

    init(visibleItems: [ControlIslandItem]) {
        let main = visibleItems.filter { $0.section == .main }
        let additional = visibleItems.filter { $0.section == .additional }
        let rows = main + additional
        var elements: [Element] = []
        for (index, row) in rows.enumerated() {
            if index > 0 {
                let previous = rows[index - 1]
                if previous == .spaces, row == .favoriteTabs {
                    elements.append(.gap(before: row))
                } else if Self.needsLine(between: previous, and: row) {
                    elements.append(.line(before: row))
                }
            }
            elements.append(.row(row))
        }
        elements.append(.grip)
        self.elements = elements
    }

    private static func needsLine(between previous: ControlIslandItem, and next: ControlIslandItem) -> Bool {
        previous.isGroup || next.isGroup || (previous.section == .main && next.section == .additional)
    }
}
