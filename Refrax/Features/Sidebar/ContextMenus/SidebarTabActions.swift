import AppKit
import Foundation

/// Menu actions a sidebar tab row adds beside ``PageActions`` and ``TabActions``: identity and
/// status, pinned-tab navigation, organization, sorting, the reflected window, and the close
/// family.
struct SidebarTabActions {
    let tab: Tab
    let isCompactMode: Bool
    var onRename: (() -> Void)?
    var onGetInfo: (() -> Void)?
    var onPreview: (() -> Void)?
    let tabManager: TabManager
    let groupManager: TabGroupManager
    let pagePool: WebPagePool
    let windowState: WindowState
    let settings: BrowserSettings

    func actions() -> [MenuAction] {
        identity() + status() + organization() + sorting() + window() + closeFamily()
    }

    // MARK: - Identity and status

    private func identity() -> [MenuAction] {
        var actions: [MenuAction] = []
        if !isCompactMode, let onRename {
            actions.append(MenuAction("sidebar.rename", "Rename Tab", symbol: ContextMenuIcon.rename.systemName, group: .tab, isPrimary: true) { onRename() })
        }
        if let onGetInfo {
            actions.append(MenuAction("sidebar.getInfo", "Get Info", symbol: ContextMenuIcon.info.systemName, group: .tab, isPrimary: true) { onGetInfo() })
        }
        if let onPreview {
            actions.append(MenuAction("sidebar.preview", "Preview", symbol: "eye", group: .tab) { onPreview() })
        }
        return actions
    }

    private func status() -> [MenuAction] {
        var actions: [MenuAction] = []
        if tab.groupID == nil {
            let pinned = tab.isPinned
            actions.append(MenuAction(
                "sidebar.pin", pinned ? "Unpin" : "Pin",
                symbol: pinned ? ContextMenuIcon.unpin.systemName : ContextMenuIcon.pin.systemName, group: .tab,
            ) { tabManager.togglePinTab(tab) })
        }
        if tab.isPinned {
            if tab.hasNavigatedFromHome, let homeURL = tab.homeURL {
                actions.append(MenuAction("sidebar.goHome", "Go to Home", symbol: "house", group: .go) {
                    pagePool.existingPage(for: tab.activePage)?.load(homeURL)
                })
            }
            actions.append(MenuAction("sidebar.setHome", "Set Current Page as Home", symbol: "house", group: .go) {
                tab.originURL = tab.activePage.url
            })
        }
        actions.append(MenuAction("sidebar.favorite", "Move to Favorites", symbol: ContextMenuIcon.favorite.systemName, group: .tab) {
            tabManager.convertTabToFavorite(tab, mode: .liveFavorite)
        })
        let unread = tab.isUnread
        actions.append(MenuAction(
            "sidebar.unread", unread ? "Mark as Read" : "Mark as Unread",
            symbol: unread ? ContextMenuIcon.markRead.systemName : ContextMenuIcon.markUnread.systemName, group: .tab,
        ) {
            if unread {
                tabManager.markAsRead(tab)
            } else {
                tabManager.markAsUnread(tab)
            }
        })
        return actions
    }

    // MARK: - Organization

    private var availableGroups: [TabGroup] {
        (windowState.activeSpace?.groups ?? []).filter { $0.id != tab.groupID }
    }

    private var availableSpaces: [Space] {
        tabManager.state.spaces.filter { $0.id != windowState.activeSpaceID }
    }

    private func organization() -> [MenuAction] {
        var actions: [MenuAction] = []
        if tab.groupID != nil {
            actions.append(MenuAction("sidebar.removeFromGroup", "Remove from Group", symbol: ContextMenuIcon.removeFromGroup.systemName, group: .move) {
                groupManager.removeTabFromGroup(tab)
            })
        }
        let groups = availableGroups
        if !groups.isEmpty {
            let targets = groups.map { group in
                MenuAction("sidebar.moveToGroup.\(group.id)", group.name, symbol: group.isEmoji ? nil : group.iconName ?? "folder.fill", group: .move) {
                    groupManager.moveTabToGroup(tab, group: group)
                }
            }
            actions.append(MenuAction(
                "sidebar.moveToGroup", "Move to Group", symbol: ContextMenuIcon.moveToGroup.systemName, group: .move, isPrimary: true, children: targets,
            ))
        }
        actions.append(MenuAction("sidebar.newGroup", "Add to New Group…", symbol: ContextMenuIcon.addToNewGroup.systemName, group: .move) {
            do {
                let group = try groupManager.createGroup(name: "New Group", color: GroupColor.steel.rawValue, iconName: "folder.fill", startEditing: true)
                groupManager.moveTabToGroup(tab, group: group)
            } catch {
                Logger.debug("Couldn't create group: \(error)", category: Logger.tabs)
            }
        })
        let spaces = availableSpaces
        if !spaces.isEmpty {
            let targets = spaces.map { space in
                MenuAction("sidebar.moveToSpace.\(space.id)", space.name, symbol: space.isEmoji ? nil : space.iconName, group: .move) {
                    tabManager.moveTabs([tab], to: space)
                }
            }
            actions.append(MenuAction("sidebar.moveToSpace", "Move to Space", symbol: ContextMenuIcon.moveToSpace.systemName, group: .move, children: targets))
        }
        let referenceTabs = windowState.activeSpace?.referenceTabCount ?? 0
        let spaceTabs = windowState.activeSpace?.tabs.count ?? 0
        actions.append(MenuAction(
            "sidebar.moveToReferencePane", "Move to Reference Pane", symbol: ContextMenuIcon.moveToReferencePane.systemName, group: .move,
            isEnabled: referenceTabs < 4 && tab.pages.count <= 1 && spaceTabs > 1,
        ) { tabManager.moveTabToReferencePane(tab) })
        return actions
    }

    // MARK: - Sorting and windows

    private func sorting() -> [MenuAction] {
        guard let space = tab.space else { return [] }
        let criteria = TabSortCriterion.Category.allCases.flatMap { category in
            category.criteria.map { criterion in
                MenuAction("sidebar.sort.\(criterion)", criterion.displayName, symbol: criterion.iconName, group: .sort(category.displayName)) {
                    tabManager.sortTabs(by: criterion, in: space)
                }
            }
        }
        return [MenuAction("sidebar.sort", "Sort Tabs", symbol: ContextMenuIcon.sort.systemName, group: .sort, children: criteria)]
    }

    private func window() -> [MenuAction] {
        [MenuAction("sidebar.reflectedWindow", "Open Reflected Window", symbol: ContextMenuIcon.reflectedWindow.systemName, group: .window) {
            guard let page = pagePool.existingPage(for: tab.activePage) ?? pagePool.page(for: tab.activePage) else { return }
            tabManager.windowManager.createReflectedWindow(for: page)
        }]
    }

    // MARK: - Close family

    private var mainTabs: [Tab] {
        tab.space?.mainTabs ?? []
    }
    private var tabsAbove: [Tab] {
        guard let index = mainTabs.firstIndex(where: { $0.id == tab.id }) else { return [] }
        return Array(mainTabs[..<index])
    }

    private var tabsBelow: [Tab] {
        guard let index = mainTabs.firstIndex(where: { $0.id == tab.id }) else { return [] }
        return Array(mainTabs[(index + 1)...])
    }

    private var otherTabs: [Tab] {
        mainTabs.filter { $0.id != tab.id }
    }

    private func closeFamily() -> [MenuAction] {
        var actions: [MenuAction] = []
        if settings.archiveEnabled {
            actions.append(MenuAction("sidebar.archive", "Archive Tab", symbol: ContextMenuIcon.archive.systemName, key: .init("w"), group: .close, isPrimary: true) {
                tabManager.requestCloseTab(tab)
            })
            actions.append(MenuAction("sidebar.delete", "Delete Immediately", symbol: ContextMenuIcon.deleteImmediately.systemName, group: .close, isDestructive: true) {
                tabManager.requestCloseTab(tab, bypassArchive: true)
            })
            actions += closeOthers(bypassArchive: false) + closeOthers(bypassArchive: true)
        } else {
            actions.append(MenuAction("sidebar.close", "Close Tab", symbol: ContextMenuIcon.close.systemName, key: .init("w"), group: .close, isPrimary: true) {
                tabManager.requestCloseTab(tab)
            })
            actions += closeOthers(bypassArchive: false)
        }
        return actions
    }

    private func closeOthers(bypassArchive: Bool) -> [MenuAction] {
        let archiving = settings.archiveEnabled && !bypassArchive
        let verb = archiving ? "Archive" : bypassArchive ? "Delete" : "Close"
        let suffix = bypassArchive ? " Immediately" : ""
        let symbol = archiving ? ContextMenuIcon.archive.systemName
            : bypassArchive ? ContextMenuIcon.deleteImmediately.systemName : ContextMenuIcon.close.systemName
        let variant = bypassArchive ? "delete" : "close"
        let targets: [(id: String, title: String, tabs: [Tab])] = [
            ("sidebar.\(variant)Others", "\(verb) Other Tabs\(suffix)", otherTabs),
            ("sidebar.\(variant)Above", "\(verb) All Tabs Above\(suffix)", tabsAbove),
            ("sidebar.\(variant)Below", "\(verb) All Tabs Below\(suffix)", tabsBelow),
        ]
        return targets.filter { !$0.tabs.isEmpty }.map { target in
            MenuAction(target.id, target.title, symbol: symbol, group: .close, isDestructive: bypassArchive) {
                tabManager.requestCloseTabs(target.tabs, bypassArchive: bypassArchive)
            }
        }
    }
}
