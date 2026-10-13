import AppKit

/// Menu actions on a group of the floating layer, for its options popover and its header's
/// right-click: the group itself, where it goes, copies of it, and its end.
struct FloatingGroupActions {
    static let groupFamily = MenuGroupID(id: "group", title: "Group", symbol: "folder", rank: 0)
    static let groupOrder: [MenuGroupID] = [groupFamily, .move, .copy, .close]

    let group: TabGroup
    let canvas: TabCanvasManager
    let windowState: WindowState
    let tabs: TabManager
    /// Starts editing the name in the header.
    var onRename: () -> Void
    /// Opens the color and icon editor.
    var onEditAppearance: () -> Void

    private var groupManager: TabGroupManager {
        canvas.groupManager
    }

    func tree() -> MenuTree {
        MenuComposer.compose(actions(), groupOrder: Self.groupOrder)
    }

    func actions() -> [MenuAction] {
        let members = canvas.allTabs(in: group)
        var actions: [MenuAction] = [
            MenuAction("group.rename", "Rename…", symbol: "pencil", group: Self.groupFamily) { onRename() },
            MenuAction("group.appearance", "Color & Icon…", symbol: "paintpalette", group: Self.groupFamily) { onEditAppearance() },
            MenuAction(
                "group.fold", group.isCollapsed ? "Unfold" : "Fold",
                symbol: group.isCollapsed ? "chevron.down" : "chevron.right", group: Self.groupFamily,
            ) { canvas.toggleFold(group) },
        ]
        if let current = windowState.activeTab, current.group?.id != group.id, !current.isLiveFavorite,
           current.space?.id == group.space?.id {
            actions.append(MenuAction("group.addCurrent", "Add Current Page", symbol: "plus.rectangle.on.folder", group: .move) {
                canvas.addToFloatingGroup([current], group: group)
            })
        }
        let spaces = canvas.otherSpaces
        if !spaces.isEmpty {
            let destinations = spaces.map { space in
                MenuAction("group.moveToSpace.\(space.id.uuidString)", space.name, group: .move) {
                    groupManager.moveGroupToSpace(group, to: space)
                }
            }
            actions.append(MenuAction("group.moveToSpace", "Move to Space", symbol: "rectangle.portrait.and.arrow.right", group: .move, children: destinations))
        }
        actions.append(MenuAction("group.openAsSpace", "Open as Space", symbol: "square.stack", group: .move) {
            guard let space = try? groupManager.convertGroupToSpace(group) else { return }
            tabs.spaceManager.switchToSpaceSync(space, for: windowState)
        })
        actions.append(MenuAction("group.duplicate", "Duplicate", symbol: "plus.square.on.square", group: .copy) {
            groupManager.duplicateGroup(group)
        })
        actions.append(MenuAction("group.copyAddresses", "Copy Addresses", symbol: "link", group: .copy, isEnabled: !members.isEmpty) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(members.map { tabs.copyableURL(for: $0) }.joined(separator: "\n"), forType: .string)
        })
        actions.append(MenuAction("group.ungroup", "Ungroup", symbol: "folder.badge.minus", group: .close) {
            groupManager.deleteGroup(group)
        })
        actions.append(MenuAction("group.close", "Close Group", symbol: "xmark", group: .close, isDestructive: true) {
            tabs.requestCloseTabs(members)
            if canvas.allTabs(in: group).isEmpty {
                groupManager.deleteGroup(group)
            }
        })
        return actions
    }
}

@MainActor
extension MenuTree {
    /// The same rows, each running `dismiss` before its action.
    func runningFirst(_ dismiss: @escaping () -> Void) -> MenuTree {
        MenuTree(sections: sections.map { section in
            MenuTree.Section(nodes: section.nodes.map { $0.runningFirst(dismiss) })
        })
    }
}

@MainActor
private extension MenuTree.Node {
    func runningFirst(_ dismiss: @escaping () -> Void) -> MenuTree.Node {
        switch self {
        case var .action(action):
            let execute = action.execute
            action.execute = {
                dismiss()
                execute()
            }
            return .action(action)
        case let .submenu(submenu):
            return .submenu(MenuTree.Submenu(
                id: submenu.id, title: submenu.title, symbol: submenu.symbol,
                sections: submenu.sections.map { MenuTree.Section(nodes: $0.nodes.map { $0.runningFirst(dismiss) }) },
            ))
        }
    }
}
