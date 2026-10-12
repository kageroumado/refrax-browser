/// The rows of one menu, as ``MenuComposer`` produces them and both renderers read them:
/// sections of inline actions and folded groups, with a divider between sections.
nonisolated struct MenuTree: Sendable {
    /// One row.
    nonisolated enum Node: Sendable {
        case action(MenuAction)
        case submenu(Submenu)
    }

    /// A submenu row: a folded group, or an action with children.
    nonisolated struct Submenu: Sendable {
        let id: String
        let title: String
        let symbol: String?
        let sections: [Section]

        var rowCount: Int { sections.reduce(0) { $0 + $1.nodes.count } }
    }

    /// The rows between two dividers.
    nonisolated struct Section: Sendable {
        var nodes: [Node]
    }

    var sections: [Section]

    static let empty = MenuTree(sections: [])

    /// Top-level rows; dividers are half-height and do not count.
    var rowCount: Int { sections.reduce(0) { $0 + $1.nodes.count } }

    /// Top-level action and submenu identities, in order.
    var ids: [String] {
        sections.flatMap { $0.nodes.map { $0.id } }
    }

    /// One line per row, `"——"` between sections, a submenu as `"Title ▸ (n)"` followed by its rows
    /// indented two spaces: the menu as a person reads it, for test fixtures.
    var outline: [String] {
        Self.outline(sections, indent: "")
    }

    private static func outline(_ sections: [Section], indent: String) -> [String] {
        var lines: [String] = []
        for (index, section) in sections.enumerated() {
            if index > 0 { lines.append("\(indent)——") }
            for node in section.nodes {
                switch node {
                case let .action(action):
                    lines.append(indent + action.title)
                case let .submenu(submenu):
                    lines.append("\(indent)\(submenu.title) ▸ (\(submenu.rowCount))")
                    lines += outline(submenu.sections, indent: indent + "  ")
                }
            }
        }
        return lines
    }
}

nonisolated extension MenuTree.Node {
    var id: String {
        switch self {
        case let .action(action): action.id
        case let .submenu(submenu): submenu.id
        }
    }

    var title: String {
        switch self {
        case let .action(action): action.title
        case let .submenu(submenu): submenu.title
        }
    }
}
