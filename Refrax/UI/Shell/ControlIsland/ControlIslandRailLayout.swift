import Foundation

/// The rail's rows and the gaps between them, top to bottom.
///
/// The main section comes first in its customized order, then the additional controls
/// in theirs. A gap carries a divider line around a group and at the boundary between
/// the sections; the gap under the space picker carries the grip instead.
nonisolated struct ControlIslandRailLayout: Equatable {
    enum Element: Equatable, Identifiable {
        case row(ControlIslandItem)
        /// A 12-point gap with a divider line.
        case line(before: ControlIslandItem)
        /// A 12-point gap holding the handle that moves the rail.
        case grip

        var id: String {
            switch self {
            case let .row(item): item.rawValue
            case let .line(item): "line-\(item.rawValue)"
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
        let gripSlot = main.firstIndex(of: .spaces).map { $0 + 1 } ?? main.count
        var elements: [Element] = []
        for index in 0 ... rows.count {
            if index == gripSlot {
                elements.append(.grip)
            } else if index > 0, index < rows.count, Self.needsLine(between: rows[index - 1], and: rows[index]) {
                elements.append(.line(before: rows[index]))
            }
            if index < rows.count {
                elements.append(.row(rows[index]))
            }
        }
        self.elements = elements
    }

    private static func needsLine(between previous: ControlIslandItem, and next: ControlIslandItem) -> Bool {
        previous.isGroup || next.isGroup || (previous.section == .main && next.section == .additional)
    }
}
