/// A menu laid out by hand: sections of action identities, filled from the actions a site offers.
///
/// ``MenuComposer`` groups and folds by count; a layout places every row where it was designed
/// to go. An identity with no offered action leaves no row, and a section or submenu left with
/// no rows leaves no divider. An offered action the layout neither places nor drops joins the
/// layout's ``overflow`` submenu, so an action added to a provider is never lost.
nonisolated struct MenuLayout: Sendable {
    /// One row of the layout.
    nonisolated enum Entry: Sendable {
        /// The offered action with this identity.
        case action(String)
        /// A submenu of the offered actions with these identities, in this order.
        case submenu(id: String, title: String, symbol: String?, actions: [String])
    }

    var sections: [[Entry]]
    /// Identities, or identity prefixes ending in `.`, that the surface never shows.
    var dropped: [String] = []
    /// The submenu that takes offered actions the layout does not place.
    var overflow: String?

    func tree(_ offered: [MenuAction]) -> MenuTree {
        var byID: [String: MenuAction] = [:]
        for action in offered where byID[action.id] == nil {
            byID[action.id] = action
        }
        let placed = Set(sections.flatMap { $0.flatMap(\.ids) })
        let leftover = offered.map(\.id).filter { id in
            !placed.contains(id) && !dropped.contains { $0.hasSuffix(".") ? id.hasPrefix($0) : id == $0 }
        }
        let out = sections.compactMap { entries -> MenuTree.Section? in
            let nodes = entries.compactMap { entry -> MenuTree.Node? in
                switch entry {
                case let .action(id):
                    return byID[id].map(MenuComposer.node)
                case let .submenu(id, title, symbol, ids):
                    let rows = (ids + (id == overflow ? leftover : [])).compactMap { byID[$0].map(MenuComposer.node) }
                    guard !rows.isEmpty else { return nil }
                    return .submenu(MenuTree.Submenu(id: id, title: title, symbol: symbol, sections: [MenuTree.Section(nodes: rows)]))
                }
            }
            return nodes.isEmpty ? nil : MenuTree.Section(nodes: nodes)
        }
        return MenuTree(sections: out)
    }
}

private nonisolated extension MenuLayout.Entry {
    var ids: [String] {
        switch self {
        case let .action(id): [id]
        case let .submenu(_, _, _, actions): actions
        }
    }
}
