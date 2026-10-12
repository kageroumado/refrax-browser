import AppKit

/// One thing a person can do from a menu: what a renderer shows, and the closure that does it.
///
/// An action carries no AppKit or SwiftUI view types, so providers build actions anywhere and
/// ``MenuComposer`` groups them off the main actor. The renderers (``NSMenuRenderer``,
/// ``MenuTreeView``) read the composed ``MenuTree``.
nonisolated struct MenuAction: Identifiable, Sendable {
    /// A key equivalent shown beside the title.
    nonisolated struct KeyEquivalent: Equatable, Sendable {
        let character: Character
        let modifiers: NSEvent.ModifierFlags

        init(_ character: Character, modifiers: NSEvent.ModifierFlags = .command) {
            self.character = character
            self.modifiers = modifiers
        }
    }

    /// The checkmark beside the title.
    nonisolated enum State: Equatable, Sendable {
        /// A plain item.
        case plain
        /// A checked item.
        case on
        /// An unchecked item that can be checked.
        case off
    }

    /// A stable identity (`"page.copyAddress"`, `"tab.close"`) for tests and accessibility.
    let id: String
    var title: String
    /// An SF Symbol name.
    var symbol: String?
    var keyEquivalent: KeyEquivalent?
    /// A disabled action keeps its row.
    var isEnabled: Bool
    var state: State
    /// A destructive action sinks to the end of its group and renders with the destructive role.
    var isDestructive: Bool
    /// The group that decides the action's section, and the submenu it folds into.
    var group: MenuGroupID
    /// The one action of its group that stays inline when the group folds.
    var isPrimary: Bool
    /// An explicit submenu (Move to Group lists groups); counts as one row.
    var children: [MenuAction]
    var execute: @MainActor () -> Void

    init(
        _ id: String,
        _ title: String,
        symbol: String? = nil,
        key: KeyEquivalent? = nil,
        group: MenuGroupID,
        isPrimary: Bool = false,
        isEnabled: Bool = true,
        state: State = .plain,
        isDestructive: Bool = false,
        children: [MenuAction] = [],
        execute: @escaping @MainActor () -> Void = {},
    ) {
        self.id = id
        self.title = title
        self.symbol = symbol
        self.keyEquivalent = key
        self.isEnabled = isEnabled
        self.state = state
        self.isDestructive = isDestructive
        self.group = group
        self.isPrimary = isPrimary
        self.children = children
        self.execute = execute
    }
}
