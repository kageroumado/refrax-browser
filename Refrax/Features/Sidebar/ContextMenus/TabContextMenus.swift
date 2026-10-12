import AppKit
import SwiftUI

// MARK: - Tab Context Menu

extension SidebarContextMenus {
    /// Context menu for a single tab: ``SidebarTabActions``, ``PageActions`` and ``TabActions``
    /// composed by ``MenuComposer`` and rendered by ``MenuTreeView``.
    struct Tab: View {
        @SwiftUI.Environment(TabManager.self) private var tabManager
        @SwiftUI.Environment(TabGroupManager.self) private var groupManager
        @SwiftUI.Environment(WebPagePool.self) private var pagePool
        @SwiftUI.Environment(BookmarksManager.self) private var bookmarksManager
        @SwiftUI.Environment(SharingCoordinator.self) private var sharingCoordinator
        @SwiftUI.Environment(ReaderModeManager.self) private var readerModeManager
        @SwiftUI.Environment(WindowState.self) private var windowState
        @SwiftUI.Environment(BrowserSettings.self) private var settings

        let tab: Refrax.Tab
        var isCompactMode: Bool = false
        var onRename: (() -> Void)?
        var onGetInfo: (() -> Void)?
        var onPreview: (() -> Void)?

        var body: some View {
            MenuTreeView(tree: Self.tree(
                for: tab, isCompactMode: isCompactMode, onRename: onRename, onGetInfo: onGetInfo, onPreview: onPreview,
                tabManager: tabManager, groupManager: groupManager, pagePool: pagePool, bookmarksManager: bookmarksManager,
                sharingCoordinator: sharingCoordinator, readerModeManager: readerModeManager, windowState: windowState, settings: settings,
            ))
        }

        /// The row's menu. Groups come out by rank: the tab, navigation, reload, organization,
        /// copy, share, sort, window, close.
        static func tree(
            for tab: Refrax.Tab,
            isCompactMode: Bool,
            onRename: (() -> Void)? = nil,
            onGetInfo: (() -> Void)? = nil,
            onPreview: (() -> Void)? = nil,
            tabManager: TabManager,
            groupManager: TabGroupManager,
            pagePool: WebPagePool,
            bookmarksManager: BookmarksManager,
            sharingCoordinator: SharingCoordinator,
            readerModeManager: ReaderModeManager,
            windowState: WindowState,
            settings: BrowserSettings,
        ) -> MenuTree {
            let surface: MenuSurface = isCompactMode ? .compactRow : .sidebarRow
            let sidebar = SidebarTabActions(
                tab: tab, isCompactMode: isCompactMode, onRename: onRename, onGetInfo: onGetInfo, onPreview: onPreview,
                tabManager: tabManager, groupManager: groupManager, pagePool: pagePool, windowState: windowState, settings: settings,
            )
            let page = PageActions(
                tab: tab, surface: surface, windowState: windowState, tabs: tabManager, readerMode: readerModeManager, sharing: sharingCoordinator,
            )
            let object = TabActions(tab: tab, surface: surface, windowState: windowState, tabs: tabManager, bookmarks: bookmarksManager)
            return MenuComposer.compose(sidebar.actions() + page.actions() + object.actions())
        }
    }
}

// MARK: - Archived Tab Context Menu

extension SidebarContextMenus {
    /// Context menu for an archived tab.
    ///
    /// Archived tabs have limited options: view info, copy URL, restore, or delete.
    ///
    /// ## Menu Structure
    /// 1. Get Info
    /// 2. Copy URL, Copy as Markdown
    /// 3. Restore, Delete
    struct ArchivedTab: View {
        @SwiftUI.Environment(TabManager.self) private var tabManager
        @SwiftUI.Environment(SharingCoordinator.self) private var sharingCoordinator

        let tab: Refrax.Tab
        var onGetInfo: (() -> Void)?

        var body: some View {
            // MARK: Info

            Button {
                onGetInfo?()
            } label: {
                Label("Get Info", systemImage: ContextMenuIcon.info.systemName)
            }

            Divider()

            // MARK: Copy/Share

            Button {
                let url = tabManager.copyableURL(for: tab)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url, forType: .string)
            } label: {
                Label("Copy URL", systemImage: ContextMenuIcon.copyURL.systemName)
            }

            Button {
                let url = tabManager.copyableURL(for: tab)
                let title = tab.displayTitle
                let markdown = "[\(title)](\(url))"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdown, forType: .string)
            } label: {
                Label("Copy URL as Markdown", systemImage: ContextMenuIcon.copyURL.systemName)
            }

            Button {
                let cleanURL = URL(string: tabManager.copyableURL(for: tab)) ?? tab.activePage.url
                sharingCoordinator.shareURL(cleanURL, title: tab.displayTitle)
            } label: {
                Label("Share...", systemImage: ContextMenuIcon.share.systemName)
            }

            Divider()

            // MARK: Archive Actions

            Button {
                do {
                    try tabManager.archiveManager.restoreTab(tab)
                } catch {
                    Logger.debug("Failed to restore tab: \(error)", category: Logger.tabs)
                }
            } label: {
                Label("Restore", systemImage: "trash.slash")
            }

            Button(role: .destructive) {
                tabManager.archiveManager.deleteArchivedTab(
                    tab,
                    in: tabManager.state.modelContext,
                )
            } label: {
                Label("Delete Permanently", systemImage: ContextMenuIcon.delete.systemName)
            }
        }
    }
}

// MARK: - Multi-Tab Context Menu

extension SidebarContextMenus {
    /// Context menu for multiple selected tabs.
    struct MultiTab: View {
        @SwiftUI.Environment(TabManager.self) private var tabManager
        @SwiftUI.Environment(TabGroupManager.self) private var groupManager
        @SwiftUI.Environment(WebPagePool.self) private var pagePool
        @SwiftUI.Environment(WindowState.self) private var windowState
        @SwiftUI.Environment(BrowserSettings.self) private var settings

        let selectedTabs: [Refrax.Tab]
        var onOperationComplete: (() -> Void)?

        private var env: Environment {
            Environment(tabManager: tabManager, windowState: windowState, bookmarksManager: nil)
        }

        private var allTabsUngrouped: Bool {
            selectedTabs.allSatisfy { $0.groupID == nil }
        }

        private var allTabsPinned: Bool {
            selectedTabs.allSatisfy(\.isPinned)
        }

        private var allTabsUnpinned: Bool {
            selectedTabs.allSatisfy { !$0.isPinned && $0.groupID == nil }
        }

        private var hasGroupedTabs: Bool {
            selectedTabs.contains { $0.groupID != nil }
        }

        /// Tabs that are currently playing audio.
        private var tabsPlayingAudio: [Refrax.Tab] {
            selectedTabs.filter { tab in
                if let webPage = pagePool.existingPage(for: tab.activePage) {
                    return webPage.isPlayingAudio
                }
                return false
            }
        }

        var body: some View {
            Text("\(selectedTabs.count) Tabs Selected")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            // MARK: Status

            if allTabsUngrouped {
                if allTabsPinned {
                    Button {
                        for tab in selectedTabs {
                            tabManager.togglePinTab(tab)
                        }
                        onOperationComplete?()
                    } label: {
                        Label("Unpin All", systemImage: ContextMenuIcon.unpin.systemName)
                    }
                } else if allTabsUnpinned {
                    Button {
                        for tab in selectedTabs {
                            tabManager.togglePinTab(tab)
                        }
                        onOperationComplete?()
                    } label: {
                        Label("Pin All", systemImage: ContextMenuIcon.pin.systemName)
                    }
                }
            }

            Divider()

            // MARK: Reload

            Button {
                for tab in selectedTabs {
                    if let webPage = pagePool.existingPage(for: tab.activePage) {
                        _ = webPage.reload()
                    }
                }
            } label: {
                Label("Reload All", systemImage: ContextMenuIcon.reload.systemName)
            }

            // Mute all (only if >1 tab is playing audio)
            if tabsPlayingAudio.count > 1 {
                Button {
                    for tab in tabsPlayingAudio {
                        if let webPage = pagePool.existingPage(for: tab.activePage) {
                            webPage.setAudioMuted(true)
                        }
                    }
                } label: {
                    Label("Mute All (\(tabsPlayingAudio.count))", systemImage: "speaker.slash")
                }
            }

            Divider()

            // MARK: Organization

            if hasGroupedTabs {
                Button {
                    for tab in selectedTabs where tab.groupID != nil {
                        groupManager.removeTabFromGroup(tab)
                    }
                    onOperationComplete?()
                } label: {
                    Label("Remove All from Groups", systemImage: ContextMenuIcon.removeFromGroup.systemName)
                }
            }

            if !env.availableGroups.isEmpty {
                Menu {
                    ForEach(env.availableGroups) { group in
                        Button {
                            for tab in selectedTabs {
                                groupManager.moveTabToGroup(tab, group: group)
                            }
                            onOperationComplete?()
                        } label: {
                            Label(group.name, systemImage: group.iconName ?? "folder.fill")
                        }
                    }
                } label: {
                    Label("Add to Group", systemImage: ContextMenuIcon.moveToGroup.systemName)
                }
            }

            Button {
                do {
                    let group = try groupManager.createGroup(
                        name: "New Group",
                        color: GroupColor.steel.rawValue,
                        iconName: "folder.fill",
                        startEditing: true,
                    )
                    for tab in selectedTabs {
                        groupManager.moveTabToGroup(tab, group: group)
                    }
                    onOperationComplete?()
                } catch {
                    Logger.debug("Couldn't create group: \(error)", category: Logger.tabs)
                }
            } label: {
                Label("Add to New Group...", systemImage: ContextMenuIcon.addToNewGroup.systemName)
            }

            // Move to space
            if !env.availableSpaces.isEmpty {
                Menu {
                    ForEach(env.availableSpaces, id: \.id) { space in
                        Button {
                            tabManager.moveTabs(selectedTabs, to: space)
                            onOperationComplete?()
                        } label: {
                            Label(space.name, systemImage: space.isEmoji ? "" : space.iconName)
                        }
                    }
                } label: {
                    Label("Move to Space", systemImage: ContextMenuIcon.moveToSpace.systemName)
                }
            }

            Divider()

            // MARK: Copy

            Button {
                let urls = selectedTabs.map { tabManager.copyableURL(for: $0) }
                let joined = urls.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(joined, forType: .string)
            } label: {
                Label("Copy URLs", systemImage: ContextMenuIcon.copyURL.systemName)
            }

            Button {
                let lines = selectedTabs.map { tab in
                    let url = tabManager.copyableURL(for: tab)
                    return "- [\(tab.displayTitle)](\(url))"
                }
                let markdown = lines.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(markdown, forType: .string)
            } label: {
                Label("Copy URLs as Markdown", systemImage: ContextMenuIcon.copyURL.systemName)
            }

            Divider()

            // MARK: Destructive

            if settings.archiveEnabled {
                Button {
                    tabManager.requestCloseTabs(selectedTabs)
                    onOperationComplete?()
                } label: {
                    Label("Archive \(selectedTabs.count) Tabs", systemImage: ContextMenuIcon.archive.systemName)
                }

                Button(role: .destructive) {
                    tabManager.requestCloseTabs(selectedTabs, bypassArchive: true)
                    onOperationComplete?()
                } label: {
                    Label("Delete \(selectedTabs.count) Immediately", systemImage: ContextMenuIcon.deleteImmediately.systemName)
                }
            } else {
                Button {
                    tabManager.requestCloseTabs(selectedTabs)
                    onOperationComplete?()
                } label: {
                    Label("Close \(selectedTabs.count) Tabs", systemImage: ContextMenuIcon.close.systemName)
                }
            }
        }
    }
}
