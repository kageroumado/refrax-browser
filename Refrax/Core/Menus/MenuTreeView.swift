import AppKit
import SwiftUI

/// Renders a ``MenuTree`` as SwiftUI rows: the content of a `Menu` or `.contextMenu`, or, under
/// ``PageMenuRowButtonStyle`` and `.menuStyle(.button)`, the rows of a popover.
///
/// Row identity is positional because every tree is rebuilt when its menu opens.
struct MenuTreeView: View {
    let tree: MenuTree

    var body: some View {
        ForEach(Array(tree.sections.enumerated()), id: \.offset) { index, section in
            if index > 0 {
                Divider()
            }
            ForEach(Array(section.nodes.enumerated()), id: \.offset) { _, node in
                MenuNodeView(node: node)
            }
        }
    }
}

private struct MenuNodeView: View {
    let node: MenuTree.Node

    var body: some View {
        switch node {
        case let .submenu(submenu):
            Menu {
                MenuTreeView(tree: MenuTree(sections: submenu.sections))
            } label: {
                MenuRowLabel(title: submenu.title, symbol: submenu.symbol)
            }
            .accessibilityIdentifier("menu-\(submenu.id)")
        case let .action(action):
            actionRow(action)
                .disabled(!action.isEnabled)
                .modifier(MenuKeyShortcut(key: action.keyEquivalent))
                .accessibilityIdentifier("menu-\(action.id)")
        }
    }

    @ViewBuilder
    private func actionRow(_ action: MenuAction) -> some View {
        switch action.state {
        case .plain:
            Button(role: action.isDestructive ? .destructive : nil, action: action.execute) {
                MenuRowLabel(title: action.title, symbol: action.symbol)
            }
        case .on, .off:
            Toggle(isOn: Binding(get: { action.state == .on }, set: { _ in action.execute() })) {
                MenuRowLabel(title: action.title, symbol: action.symbol)
            }
        }
    }
}

private struct MenuRowLabel: View {
    let title: String
    let symbol: String?

    var body: some View {
        if let symbol {
            Label(title, systemImage: symbol)
        } else {
            Text(title)
        }
    }
}

private struct MenuKeyShortcut: ViewModifier {
    let key: MenuAction.KeyEquivalent?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(SwiftUI.KeyEquivalent(key.character), modifiers: key.modifiers.eventModifiers)
        } else {
            content
        }
    }
}

private extension NSEvent.ModifierFlags {
    var eventModifiers: SwiftUI.EventModifiers {
        var modifiers: SwiftUI.EventModifiers = []
        if contains(.command) {
            modifiers.insert(.command)
        }
        if contains(.shift) {
            modifiers.insert(.shift)
        }
        if contains(.option) {
            modifiers.insert(.option)
        }
        if contains(.control) {
            modifiers.insert(.control)
        }
        return modifiers
    }
}
