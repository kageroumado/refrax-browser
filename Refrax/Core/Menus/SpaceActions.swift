import AppKit
import Foundation

extension MenuGroupID {
    /// Edit, Duplicate.
    static let space = MenuGroupID(id: "space", title: "Space", symbol: "square.on.square", rank: 0)
    /// Lock Now, Enable Lock, Disable Lock, Unlock.
    static let lock = MenuGroupID(id: "lock", title: "Lock", symbol: "lock", rank: 35)
    /// New Space, Manage Spaces.
    static let spaces = MenuGroupID(id: "spaces", title: "Spaces", symbol: "square.stack", rank: 1_000)
}

/// Menu actions on a space as the island's space picker shows it: edit and duplicate it, lock
/// it, turn it into a group of another space, copy its addresses, and clear or delete it; then
/// New Space and Manage Spaces. A locked space offers only Unlock.
///
/// Edit, New Space, Manage Spaces, and the delete confirmation are sheets the site presents,
/// so it passes them in.
struct SpaceActions {
    /// The space the menu opened on; nil for the picker's empty track.
    let space: Space?
    let tabs: TabManager
    var onEdit: (Space) -> Void = { _ in }
    var onRemove: (Space) -> Void = { _ in }
    var onNewSpace: () -> Void = {}
    var onManageSpaces: () -> Void = {}

    /// Group order: the space, the lock, organization, copy, removal, then the spaces as a whole.
    static let groupOrder: [MenuGroupID] = [.space, .lock, .move, .copy, .close, .spaces]

    private var lockManager: SpaceLockManager {
        tabs.state.spaceLockManager
    }

    func actions() -> [MenuAction] {
        var actions: [MenuAction] = []
        if let space {
            if lockManager.requiresAuth(for: space) {
                actions.append(MenuAction("space.unlock", "Unlock…", symbol: "lock.open", group: .lock) {
                    Task(name: "Unlock space from the picker") { _ = await lockManager.authenticate(for: space) }
                })
            } else {
                actions += identityActions(space) + lockActions(space) + organizeActions(space) + copyActions(space) + removalActions(space)
            }
        }
        actions.append(MenuAction("space.new", "New Space…", symbol: "plus.square.on.square", key: .init("n", modifiers: [.command, .control]), group: .spaces) {
            onNewSpace()
        })
        actions.append(MenuAction("space.manage", "Manage Spaces…", symbol: "rectangle.stack", group: .spaces) { onManageSpaces() })
        return actions
    }

    private func identityActions(_ space: Space) -> [MenuAction] {
        [
            MenuAction("space.edit", "Edit…", symbol: "slider.horizontal.3", group: .space) { onEdit(space) },
            MenuAction("space.duplicate", "Duplicate", symbol: "plus.square.on.square", group: .space) {
                tabs.spaceManager.duplicateSpace(space)
            },
        ]
    }

    private func lockActions(_ space: Space) -> [MenuAction] {
        guard space.isLockEnabled else {
            return [MenuAction("space.enableLock", "Enable Lock", symbol: "lock", group: .lock) {
                space.isLockEnabled = true
                tabs.state.scheduleSave()
            }]
        }
        return [
            MenuAction("space.lockNow", "Lock Now", symbol: "lock.fill", group: .lock) { lockManager.lock(space: space) },
            MenuAction("space.disableLock", "Disable Lock…", symbol: "lock.open", group: .lock) {
                Task(name: "Disable space lock from the picker") {
                    guard case .success = await lockManager.authenticateToModifyLockSettings(for: space) else { return }
                    space.isLockEnabled = false
                    lockManager.lock(space: space)
                    tabs.state.scheduleSave()
                }
            },
        ]
    }

    /// Convert to Group lists the spaces that can take the tabs; a space with its own data
    /// says that its tabs lose it, and a locked target asks to be unlocked first.
    private func organizeActions(_ space: Space) -> [MenuAction] {
        let targets = tabs.spaceManager.spaces.filter { $0.id != space.id }
        guard !targets.isEmpty else { return [] }
        let losesData = !space.dataStoreMode.isGlobal
        let children = targets.map { target in
            let isLocked = lockManager.requiresAuth(for: target)
            return MenuAction("space.convert.\(target.id)", target.name, symbol: isLocked ? "lock" : target.isEmoji ? nil : target.iconName, group: .move) {
                Task(name: "Convert space to group") {
                    guard await tabs.unlock([space, target]) else { return }
                    do {
                        _ = try tabs.groupManager.convertSpaceToGroup(space, in: target)
                    } catch {
                        Logger.debug("Couldn't convert space to group: \(error)", category: Logger.tabs)
                    }
                }
            }
        }
        let title = losesData ? "Convert to Group (Tabs Lose \(space.dataStoreMode.displayName) Data)" : "Convert to Group"
        return [MenuAction("space.convertToGroup", title, symbol: "folder.badge.plus", group: .move, children: children)]
    }

    private func copyActions(_ space: Space) -> [MenuAction] {
        let spaceTabs = tabs.state.tabs(in: space)
        guard !spaceTabs.isEmpty else { return [] }
        return [
            MenuAction("space.copyAddresses", "Copy Addresses", symbol: "link", group: .copy, isPrimary: true) {
                Self.copy(spaceTabs.map { tabs.copyableURL(for: $0) }.joined(separator: "\n"))
            },
            MenuAction("space.copyMarkdown", "Copy as Markdown List", symbol: "text.quote", group: .copy) {
                Self.copy(Self.markdown(for: space, tabs: tabs))
            },
        ]
    }

    /// The last space is cleared rather than deleted, since a browser always keeps one.
    private func removalActions(_ space: Space) -> [MenuAction] {
        let title = tabs.hasMultipleSpaces ? "Delete Space…" : "Clear Space…"
        return [MenuAction("space.remove", title, symbol: "trash", group: .close, isDestructive: true) { onRemove(space) }]
    }

    private static func copy(_ string: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
    }

    /// The space as a Markdown document: a heading, then each group and the rest, each a list
    /// of links.
    static func markdown(for space: Space, tabs: TabManager) -> String {
        let spaceTabs = tabs.state.tabs(in: space)
        func links(_ list: [Tab]) -> [String] {
            list.sorted { $0.position < $1.position }.map { "- [\($0.displayTitle)](\(tabs.copyableURL(for: $0)))" }
        }
        var lines = ["# \(space.displayNameWithIcon)", ""]
        let groups = tabs.state.groups(in: space).sorted { $0.position < $1.position }
        for group in groups {
            let members = spaceTabs.filter { $0.groupID == group.id }
            if !members.isEmpty {
                lines += ["## \(group.displayNameWithIcon)"] + links(members) + [""]
            }
        }
        let others = spaceTabs.filter { $0.groupID == nil }
        if !others.isEmpty {
            if !groups.isEmpty {
                lines.append("## Other")
            }
            lines += links(others)
        }
        return lines.joined(separator: "\n")
    }
}
