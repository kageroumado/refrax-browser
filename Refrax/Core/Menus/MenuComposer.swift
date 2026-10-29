/// Groups a list of actions into a ``MenuTree``.
///
/// A group of up to ``inlineLimit`` actions is one section. A larger group folds into one
/// submenu titled with the group's title and symbol; its primary action stays inline directly
/// above the submenu row. Consecutive one-row groups share a section. Groups come out in the
/// order the site passes, then by ``MenuGroupID/rank``; inside a group, declaration order, with
/// destructive actions last. One primary per group: the first marked wins.
///
/// When the top level still exceeds ``maximumRows``, the largest inline group folds first (an
/// all-disabled group before any other, ties to the group closest to the bottom), then promoted
/// primaries are demoted into their submenus from the bottom up, the close group last. Groups
/// never merge and never reorder.
nonisolated enum MenuComposer {
    static let inlineLimit = 3
    static let maximumRows = 16
    /// Consecutive single-action groups share one section, up to this many rows, so a run of
    /// singletons still reads in small groups rather than one undivided list.
    static let sharedSingletonLimit = 3

    /// Composes `actions` into a tree. Groups listed in `groupOrder` come first, in that order;
    /// the rest follow by rank.
    static func compose(_ actions: [MenuAction], groupOrder: [MenuGroupID] = []) -> MenuTree {
        var groups: [MenuGroupID] = []
        var members: [MenuGroupID: [MenuAction]] = [:]
        for action in actions {
            if members[action.group] == nil {
                groups.append(action.group)
            }
            members[action.group, default: []].append(action)
        }
        let positioned = groups.enumerated().map { index, group -> (key: (Int, Int, Int), group: MenuGroupID) in
            if let listed = groupOrder.firstIndex(of: group) {
                return ((0, listed, index), group)
            }
            return ((1, group.rank, index), group)
        }
        var sections = positioned
            .sorted { $0.key < $1.key }
            .map { Section(group: $0.group, actions: ordered(members[$0.group] ?? [])) }
        for index in sections.indices {
            sections[index].folded = sections[index].actions.count > inlineLimit
        }
        while rowCount(sections) > maximumRows, let index = nextFold(sections) {
            sections[index].folded = true
        }
        while rowCount(sections) > maximumRows, let index = nextDemotion(sections) {
            sections[index].demoted = true
        }
        return tree(sections)
    }

    private nonisolated struct Section {
        let group: MenuGroupID
        var actions: [MenuAction]
        var folded = false
        var demoted = false

        var primary: MenuAction? {
            folded && !demoted ? actions.first(where: \.isPrimary) : nil
        }
        var rows: Int {
            folded ? (primary == nil ? 1 : 2) : actions.count
        }
        /// Nothing in the section can be clicked, so it is the first to fold under height pressure.
        var isInert: Bool {
            actions.allSatisfy { !$0.isEnabled }
        }
    }

    private static func ordered(_ actions: [MenuAction]) -> [MenuAction] {
        var seenPrimary = false
        let single = actions.map { action in
            var action = action
            if action.isPrimary {
                action.isPrimary = !seenPrimary
                seenPrimary = true
            }
            return action
        }
        return single.filter { !$0.isDestructive } + single.filter(\.isDestructive)
    }

    private static func rowCount(_ sections: [Section]) -> Int {
        sections.reduce(0) { $0 + $1.rows }
    }

    private static func nextFold(_ sections: [Section]) -> Int? {
        sections.indices
            .filter { !sections[$0].folded && sections[$0].actions.count > 1 }
            .max { lhs, rhs in
                (sections[lhs].isInert ? 1 : 0, sections[lhs].actions.count, lhs)
                    < (sections[rhs].isInert ? 1 : 0, sections[rhs].actions.count, rhs)
            }
    }

    private static func nextDemotion(_ sections: [Section]) -> Int? {
        let promoted = sections.indices.filter { sections[$0].primary != nil }
        return promoted.last { sections[$0].group != .close } ?? promoted.last
    }

    private static func tree(_ sections: [Section]) -> MenuTree {
        var out: [MenuTree.Section] = []
        var previousWasSingleton = false
        for section in sections {
            let body: [MenuTree.Node]
            if section.folded {
                let primary = section.primary
                let rest = section.actions.filter { $0.id != primary?.id }
                let submenu = MenuTree.Submenu(
                    id: "group.\(section.group.id)",
                    title: section.group.title,
                    symbol: section.group.symbol,
                    sections: [MenuTree.Section(nodes: rest.map(node))],
                )
                body = (primary.map { [node($0)] } ?? []) + [.submenu(submenu)]
            } else {
                body = section.actions.map(node)
            }
            let singleton = body.count == 1
            if singleton, previousWasSingleton, !out.isEmpty, out[out.count - 1].nodes.count < sharedSingletonLimit {
                out[out.count - 1].nodes += body
            } else {
                out.append(MenuTree.Section(nodes: body))
            }
            previousWasSingleton = singleton
        }
        return MenuTree(sections: out)
    }

    /// An action with children is a submenu whose rows keep declaration order, sectioned by
    /// consecutive group.
    private static func node(_ action: MenuAction) -> MenuTree.Node {
        guard !action.children.isEmpty else { return .action(action) }
        var sections: [MenuTree.Section] = []
        var previousGroup: MenuGroupID?
        for child in action.children {
            if child.group == previousGroup, !sections.isEmpty {
                sections[sections.count - 1].nodes.append(node(child))
            } else {
                sections.append(MenuTree.Section(nodes: [node(child)]))
            }
            previousGroup = child.group
        }
        return .submenu(MenuTree.Submenu(id: action.id, title: action.title, symbol: action.symbol, sections: sections))
    }
}
