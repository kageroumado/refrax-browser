import AppKit
import SwiftUI

// MARK: - Empty Area Context Menu (AppKit)

extension SidebarContextMenus {
    /// Creates a context menu with standard sidebar actions for empty areas.
    ///
    /// This is used by `SidebarEmptyAreaContextMenu` for AppKit-based right-click handling.
    ///
    /// Keep in sync with `NewTabView.emptyAreaContextMenu` which provides the SwiftUI
    /// version of this menu for the new tab button row.
    static func buildEmptyAreaMenu(dependencies: Sidebar.DependencyContainer) -> NSMenu {
        let menu = NSMenu()
        let actionHandler = SidebarMenuActions.shared

        // Extract dependencies for clarity
        let tabManager = dependencies.tabManager
        let windowState = dependencies.windowState
        let layoutManager = dependencies.layoutManager
        let filterManager = dependencies.filterManager
        let selectionManager = dependencies.selectionManager
        let groupManager = dependencies.groupManager
        let undoRedoManager = dependencies.undoRedoManager
        let settings = dependencies.settings

        // New Tab
        let newTabItem = NSMenuItem(title: "Command Lens", action: #selector(SidebarMenuActions.newTab), keyEquivalent: "t")
        newTabItem.keyEquivalentModifierMask = .command
        newTabItem.target = actionHandler
        newTabItem.representedObject = windowState
        newTabItem.image = ContextMenuIcon.newTab.nsImage
        menu.addItem(newTabItem)

        // Reopen closed tab
        if !undoRedoManager.recentlyClosedTabs.isEmpty {
            let reopenItem = NSMenuItem(
                title: "Reopen Closed Tab",
                action: #selector(SidebarMenuActions.reopenClosedTab),
                keyEquivalent: "t",
            )
            reopenItem.keyEquivalentModifierMask = [.command, .shift]
            reopenItem.target = actionHandler
            reopenItem.representedObject = tabManager
            reopenItem.image = ContextMenuIcon.reopenClosedTab.nsImage
            menu.addItem(reopenItem)
        }

        menu.addItem(.separator())

        // New Group
        let newGroupItem = NSMenuItem(
            title: "New Group",
            action: #selector(SidebarMenuActions.newGroup),
            keyEquivalent: "",
        )
        newGroupItem.target = actionHandler
        newGroupItem.representedObject = groupManager
        newGroupItem.image = ContextMenuIcon.newGroup.nsImage
        menu.addItem(newGroupItem)

        menu.addItem(.separator())

        // Selection
        let selectAllItem = NSMenuItem(
            title: "Select All Tabs",
            action: #selector(SidebarMenuActions.selectAllTabs),
            keyEquivalent: "",
        )
        selectAllItem.target = actionHandler
        selectAllItem.representedObject = selectionManager
        selectAllItem.image = ContextMenuIcon.selectAll.nsImage
        menu.addItem(selectAllItem)

        if selectionManager.hasSelection {
            let clearSelectionItem = NSMenuItem(
                title: "Clear Selection",
                action: #selector(SidebarMenuActions.clearSelection),
                keyEquivalent: "",
            )
            clearSelectionItem.target = actionHandler
            clearSelectionItem.representedObject = selectionManager
            clearSelectionItem.image = ContextMenuIcon.clearSelection.nsImage
            menu.addItem(clearSelectionItem)
        }

        if !layoutManager.pinnedItems.isEmpty || !layoutManager.normalItems.isEmpty {
            menu.addItem(.separator())

            if settings.archiveEnabled {
                // Archive All Tabs
                let archiveAllItem = NSMenuItem(
                    title: "Archive All Tabs",
                    action: #selector(SidebarMenuActions.archiveAllTabs),
                    keyEquivalent: "",
                )
                archiveAllItem.target = actionHandler
                archiveAllItem.representedObject = MenuActionContext(
                    tabManager: tabManager,
                    items: layoutManager.normalItems,
                )
                archiveAllItem.image = ContextMenuIcon.archive.nsImage
                menu.addItem(archiveAllItem)

                // Delete All Tabs Immediately
                let deleteAllItem = NSMenuItem(
                    title: "Delete All Tabs Immediately",
                    action: #selector(SidebarMenuActions.deleteAllTabsImmediately),
                    keyEquivalent: "",
                )
                deleteAllItem.target = actionHandler
                deleteAllItem.representedObject = MenuActionContext(
                    tabManager: tabManager,
                    items: layoutManager.normalItems,
                )
                deleteAllItem.image = ContextMenuIcon.deleteImmediately.nsImage
                menu.addItem(deleteAllItem)
            } else {
                // Close All Tabs (no archive)
                let closeAllItem = NSMenuItem(
                    title: "Close All Tabs",
                    action: #selector(SidebarMenuActions.closeAllTabs),
                    keyEquivalent: "",
                )
                closeAllItem.target = actionHandler
                closeAllItem.representedObject = MenuActionContext(
                    tabManager: tabManager,
                    items: layoutManager.normalItems,
                )
                closeAllItem.image = ContextMenuIcon.close.nsImage
                menu.addItem(closeAllItem)
            }
        }

        if let space = windowState.activeSpace, !windowState.activeSpaceTabs.isEmpty {
            menu.addItem(.separator())
            addSortMenu(to: menu, tabManager: tabManager, space: space, actionHandler: actionHandler)
        }

        // Window Background
        menu.addItem(.separator())

        let windowBgItem = NSMenuItem(
            title: "Window Background…",
            action: #selector(SidebarMenuActions.showWindowBackground),
            keyEquivalent: "",
        )
        windowBgItem.target = actionHandler
        windowBgItem.representedObject = dependencies
        windowBgItem.image = NSImage(systemSymbolName: "paintbrush.fill", accessibilityDescription: nil)
        menu.addItem(windowBgItem)

        if filterManager.hasActiveFilter {
            menu.addItem(.separator())
            let clearFiltersItem = NSMenuItem(
                title: "Clear Filters",
                action: #selector(SidebarMenuActions.clearFilters),
                keyEquivalent: "",
            )
            clearFiltersItem.target = actionHandler
            clearFiltersItem.representedObject = filterManager
            clearFiltersItem.image = NSImage(systemSymbolName: "xmark.circle", accessibilityDescription: nil)
            menu.addItem(clearFiltersItem)
        }

        // Collapse/Expand all groups
        let allGroups = groupManager.groups()
        if !allGroups.isEmpty {
            let hasExpandedGroups = allGroups.contains { !$0.isCollapsed }
            let hasCollapsedGroups = allGroups.contains { $0.isCollapsed }

            if hasExpandedGroups || hasCollapsedGroups {
                menu.addItem(.separator())

                if hasExpandedGroups {
                    let collapseAllItem = NSMenuItem(
                        title: "Collapse All Folders",
                        action: #selector(SidebarMenuActions.collapseAllGroups),
                        keyEquivalent: "",
                    )
                    collapseAllItem.target = actionHandler
                    collapseAllItem.representedObject = groupManager
                    collapseAllItem.image = ContextMenuIcon.collapseAll.nsImage
                    menu.addItem(collapseAllItem)
                }

                if hasCollapsedGroups {
                    let expandAllItem = NSMenuItem(
                        title: "Expand All Folders",
                        action: #selector(SidebarMenuActions.expandAllGroups),
                        keyEquivalent: "",
                    )
                    expandAllItem.target = actionHandler
                    expandAllItem.representedObject = groupManager
                    expandAllItem.image = ContextMenuIcon.expandAll.nsImage
                    menu.addItem(expandAllItem)
                }
            }

            // Remove all groups
            let removeAllGroupsItem = NSMenuItem(
                title: "Remove All Groups",
                action: #selector(SidebarMenuActions.removeAllGroups),
                keyEquivalent: "",
            )
            removeAllGroupsItem.target = actionHandler
            removeAllGroupsItem.representedObject = groupManager
            removeAllGroupsItem.image = ContextMenuIcon.removeAllGroups.nsImage
            menu.addItem(removeAllGroupsItem)
        }

        return menu
    }

    private static func addSortMenu(
        to menu: NSMenu,
        tabManager: TabManager,
        space: Refrax.Space,
        actionHandler: SidebarMenuActions,
    ) {
        let sortMenu = NSMenu(title: "Sort Tabs")

        for category in TabSortCriterion.Category.allCases {
            if !sortMenu.items.isEmpty {
                sortMenu.addItem(.separator())
            }

            for criterion in category.criteria {
                let item = NSMenuItem(
                    title: criterion.displayName,
                    action: #selector(SidebarMenuActions.sortTabs),
                    keyEquivalent: "",
                )
                item.image = NSImage(systemSymbolName: criterion.iconName, accessibilityDescription: nil)
                item.target = actionHandler
                item.representedObject = SortActionContext(
                    tabManager: tabManager,
                    space: space,
                    criterion: criterion,
                )
                sortMenu.addItem(item)
            }
        }

        let sortMenuItem = NSMenuItem(title: "Sort Tabs", action: nil, keyEquivalent: "")
        sortMenuItem.submenu = sortMenu
        sortMenuItem.image = ContextMenuIcon.sort.nsImage
        menu.addItem(sortMenuItem)
    }
}

// MARK: - Shared Building Blocks

extension SidebarContextMenus {
    /// Sort by submenu for tabs in a space.
    struct SortByMenu: View {
        @SwiftUI.Environment(TabManager.self) private var tabManager

        let space: Refrax.Space

        var body: some View {
            Menu {
                ForEach(TabSortCriterion.Category.allCases, id: \.self) { category in
                    Section {
                        ForEach(category.criteria, id: \.self) { criterion in
                            Button {
                                tabManager.sortTabs(by: criterion, in: space)
                            } label: {
                                Label(criterion.displayName, systemImage: criterion.iconName)
                            }
                        }
                    }
                }
            } label: {
                Label("Sort Tabs", systemImage: ContextMenuIcon.sort.systemName)
            }
        }
    }
}
