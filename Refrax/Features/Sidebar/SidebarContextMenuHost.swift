import AppKit
import SwiftUI

// MARK: - Menu Action Context

/// Context object passed to menu item actions.
final class MenuActionContext: NSObject {
    let tabManager: TabManager
    let tab: Tab?
    let items: [TabListItem]

    init(tabManager: TabManager, tab: Tab? = nil, items: [TabListItem] = []) {
        self.tabManager = tabManager
        self.tab = tab
        self.items = items
    }
}

/// Context for sort actions.
final class SortActionContext: NSObject {
    let tabManager: TabManager
    let space: Space
    let criterion: TabSortCriterion

    init(tabManager: TabManager, space: Space, criterion: TabSortCriterion) {
        self.tabManager = tabManager
        self.space = space
        self.criterion = criterion
    }
}

// MARK: - Menu Actions

/// Target for sidebar context menu actions.
///
/// Provides action implementations for the empty-area context menu.
/// Uses instance methods since NSMenuItem requires a target instance.
@objc
final class SidebarMenuActions: NSObject {
    static let shared = SidebarMenuActions()

    @objc
    func newTab(_ sender: NSMenuItem) {
        guard let windowState = sender.representedObject as? WindowState else { return }
        MainActor.assumeIsolated {
            windowState.openCommandLens()
        }
    }

    @objc
    func selectAllTabs(_ sender: NSMenuItem) {
        guard let selectionManager = sender.representedObject as? Sidebar.TabSelectionManager else { return }
        MainActor.assumeIsolated {
            selectionManager.selectAll()
        }
    }

    @objc
    func clearSelection(_ sender: NSMenuItem) {
        guard let selectionManager = sender.representedObject as? Sidebar.TabSelectionManager else { return }
        MainActor.assumeIsolated {
            selectionManager.clearSelection()
        }
    }

    @objc
    func closeAllTabs(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? MenuActionContext else { return }
        MainActor.assumeIsolated {
            context.tabManager.requestCloseAllTabs(in: context.items)
        }
    }

    @objc
    func archiveAllTabs(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? MenuActionContext else { return }
        MainActor.assumeIsolated {
            let tabsToClose = context.items.compactMap(\.tab)
            context.tabManager.requestCloseTabs(tabsToClose, bypassArchive: false)
        }
    }

    @objc
    func deleteAllTabsImmediately(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? MenuActionContext else { return }
        MainActor.assumeIsolated {
            let tabsToClose = context.items.compactMap(\.tab)
            context.tabManager.requestCloseTabs(tabsToClose, bypassArchive: true)
        }
    }

    @objc
    func clearFilters(_ sender: NSMenuItem) {
        guard let filterManager = sender.representedObject as? Sidebar.FilterManager else { return }
        MainActor.assumeIsolated {
            filterManager.clearFilters()
        }
    }

    @objc
    func sortTabs(_ sender: NSMenuItem) {
        guard let context = sender.representedObject as? SortActionContext else { return }
        MainActor.assumeIsolated {
            context.tabManager.sortTabs(by: context.criterion, in: context.space)
        }
    }

    @objc
    func collapseAllGroups(_ sender: NSMenuItem) {
        guard let groupManager = sender.representedObject as? TabGroupManager else { return }
        MainActor.assumeIsolated {
            groupManager.collapseAllGroups()
        }
    }

    @objc
    func expandAllGroups(_ sender: NSMenuItem) {
        guard let groupManager = sender.representedObject as? TabGroupManager else { return }
        MainActor.assumeIsolated {
            groupManager.expandAllGroups()
        }
    }

    @objc
    func removeAllGroups(_ sender: NSMenuItem) {
        guard let groupManager = sender.representedObject as? TabGroupManager else { return }
        MainActor.assumeIsolated {
            groupManager.removeAllGroups()
        }
    }

    @objc
    func newGroup(_ sender: NSMenuItem) {
        guard let groupManager = sender.representedObject as? TabGroupManager else { return }
        MainActor.assumeIsolated {
            do {
                _ = try groupManager.createGroup(
                    name: "New Group",
                    color: GroupColor.steel.rawValue,
                    iconName: "folder.fill",
                )
            } catch {
                Logger.debug("Couldn't create group: \(error)", category: Logger.tabs)
            }
        }
    }

    @objc
    func reopenClosedTab(_ sender: NSMenuItem) {
        guard let tabManager = sender.representedObject as? TabManager else { return }
        MainActor.assumeIsolated {
            tabManager.reopenLastClosedTab()
        }
    }

    @objc
    func showWindowBackground(_ sender: NSMenuItem) {
        guard let container = sender.representedObject as? Sidebar.DependencyContainer else { return }
        MainActor.assumeIsolated {
            container.showWindowBackgroundPopover = true
        }
    }
}
