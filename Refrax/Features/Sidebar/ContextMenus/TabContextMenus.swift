import AppKit
import SwiftUI

// MARK: - Tab Context Menu

extension SidebarContextMenus {
    /// Context menu for a single tab.
    ///
    /// ## Menu Structure (consistent ordering)
    /// 1. Identity: Rename, Get Info
    /// 2. Status: Pin, Add to Favorites, Mark as Read/Unread
    /// 3. Reload
    /// 4. Organization: Groups, Spaces, Reference Pane
    /// 5. Copy/Share
    /// 6. Other: Sort, Reflected Window
    /// 7. Destructive: Close
    struct Tab: View {
        @SwiftUI.Environment(TabManager.self) private var tabManager
        @SwiftUI.Environment(TabGroupManager.self) private var groupManager
        @SwiftUI.Environment(WebPagePool.self) private var pagePool
        @SwiftUI.Environment(BookmarksManager.self) private var bookmarksManager
        @SwiftUI.Environment(SharingCoordinator.self) private var sharingCoordinator
        @SwiftUI.Environment(WindowState.self) private var windowState
        @SwiftUI.Environment(BrowserSettings.self) private var settings

        let tab: Refrax.Tab
        var isCompactMode: Bool = false
        var onRename: (() -> Void)?
        var onGetInfo: (() -> Void)?
        var onPreview: (() -> Void)?

        private var env: Environment {
            Environment(tabManager: tabManager, windowState: windowState, bookmarksManager: bookmarksManager)
        }

        private var availableGroups: [TabGroup] {
            env.availableGroups.filter { $0.id != tab.groupID }
        }

        private var existingWebPage: WebPage? {
            if let webPage = pagePool.existingPage(for: tab.activePage) {
                return webPage
            }
            for page in tab.pages {
                if let webPage = pagePool.existingPage(for: page) {
                    return webPage
                }
            }
            return nil
        }

        var body: some View {
            // MARK: Identity

            // Rename is only available in full sidebar mode (compact has no text field)
            if !isCompactMode {
                Button {
                    onRename?()
                } label: {
                    Label("Rename Tab", systemImage: ContextMenuIcon.rename.systemName)
                }
                .accessibilityIdentifier("menu-rename-tab")
            }

            Button {
                onGetInfo?()
            } label: {
                Label("Get Info", systemImage: ContextMenuIcon.info.systemName)
            }
            .accessibilityIdentifier("menu-get-info")

            if let onPreview {
                Button(action: onPreview) {
                    Label("Preview", systemImage: "eye")
                }
            }

            Divider()

            // MARK: Status

            if tab.groupID == nil {
                Button {
                    tabManager.togglePinTab(tab)
                } label: {
                    Label(
                        tab.isPinned ? "Unpin" : "Pin",
                        systemImage: tab.isPinned ? ContextMenuIcon.unpin.systemName : ContextMenuIcon.pin.systemName,
                    )
                }
                .accessibilityIdentifier(tab.isPinned ? "menu-unpin-tab" : "menu-pin-tab")
            }

            // Navigation containment options for pinned tabs
            if tab.isPinned {
                if tab.hasNavigatedFromHome, let homeURL = tab.homeURL {
                    Button {
                        if let webPage = pagePool.existingPage(for: tab.activePage) {
                            webPage.load(homeURL)
                        }
                    } label: {
                        Label("Go to Home", systemImage: "house")
                    }
                }

                Button {
                    tab.originURL = tab.activePage.url
                } label: {
                    Label("Set Current Page as Home", systemImage: "house")
                }
            }

            Button {
                tabManager.convertTabToFavorite(tab, mode: .liveFavorite)
            } label: {
                Label("Move to Favorites", systemImage: ContextMenuIcon.favorite.systemName)
            }

            Button {
                if tab.isUnread {
                    tabManager.markAsRead(tab)
                } else {
                    tabManager.markAsUnread(tab)
                }
            } label: {
                Label(
                    tab.isUnread ? "Mark as Read" : "Mark as Unread",
                    systemImage: tab.isUnread ? ContextMenuIcon.markRead.systemName : ContextMenuIcon.markUnread.systemName,
                )
            }

            Divider()

            // MARK: Reload

            if tab.pages.count > 1 {
                Button {
                    for page in tab.pages {
                        if let webPage = pagePool.existingPage(for: page) {
                            _ = webPage.reload()
                        }
                    }
                } label: {
                    Label("Reload All Pages", systemImage: ContextMenuIcon.reload.systemName)
                }
            } else if existingWebPage != nil {
                Button {
                    _ = existingWebPage?.reload()
                } label: {
                    Label("Reload", systemImage: ContextMenuIcon.reload.systemName)
                }
            }

            Button {
                tabManager.duplicateTab(tab)
            } label: {
                Label("Duplicate Tab", systemImage: ContextMenuIcon.duplicateTab.systemName)
            }
            .accessibilityIdentifier("menu-duplicate-tab")

            Divider()

            // MARK: Organization

            // Group management
            if tab.groupID != nil {
                Button {
                    groupManager.removeTabFromGroup(tab)
                } label: {
                    Label("Remove from Group", systemImage: ContextMenuIcon.removeFromGroup.systemName)
                }
            }

            if !availableGroups.isEmpty {
                Menu {
                    ForEach(availableGroups) { group in
                        Button {
                            groupManager.moveTabToGroup(tab, group: group)
                        } label: {
                            Label(group.name, systemImage: group.iconName ?? "folder.fill")
                        }
                    }
                } label: {
                    Label("Move to Group", systemImage: ContextMenuIcon.moveToGroup.systemName)
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
                    groupManager.moveTabToGroup(tab, group: group)
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
                            tabManager.moveTabs([tab], to: space)
                        } label: {
                            Label(space.name, systemImage: space.isEmoji ? "" : space.iconName)
                        }
                    }
                } label: {
                    Label("Move to Space", systemImage: ContextMenuIcon.moveToSpace.systemName)
                }
            }

            Button {
                tabManager.moveTabToReferencePane(tab)
            } label: {
                Label("Move to Reference Pane", systemImage: ContextMenuIcon.moveToReferencePane.systemName)
            }
            .disabled(
                windowState.activeSpace?.referenceTabCount ?? 0 >= 4 ||
                    tab.pages.count > 1 ||
                    (windowState.activeSpace?.tabs.count ?? 0) <= 1,
            )

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

            // MARK: Other

            if let space = tab.space {
                SortByMenu(space: space)
                Divider()
            }

            Button {
                // Load page if needed, then create reflected window
                guard let webPage = existingWebPage ?? pagePool.page(for: tab.activePage) else {
                    return
                }
                tabManager.windowManager.createReflectedWindow(for: webPage)
            } label: {
                Label("Open Reflected Window", systemImage: ContextMenuIcon.reflectedWindow.systemName)
            }
            Divider()

            // MARK: Destructive

            if settings.archiveEnabled {
                Button {
                    tabManager.requestCloseTab(tab)
                } label: {
                    Label("Archive Tab", systemImage: ContextMenuIcon.archive.systemName)
                }
                .keyboardShortcut("w", modifiers: .command)
                .accessibilityIdentifier("menu-archive-tab")

                Button(role: .destructive) {
                    tabManager.requestCloseTab(tab, bypassArchive: true)
                } label: {
                    Label("Delete Immediately", systemImage: ContextMenuIcon.deleteImmediately.systemName)
                }
                .accessibilityIdentifier("menu-delete-tab")

                Divider()

                closeOtherTabsMenu(bypassArchive: false)
                closeOtherTabsMenu(bypassArchive: true)
            } else {
                Button {
                    tabManager.requestCloseTab(tab)
                } label: {
                    Label("Close Tab", systemImage: ContextMenuIcon.close.systemName)
                }
                .keyboardShortcut("w", modifiers: .command)
                .accessibilityIdentifier("menu-close-tab")

                Divider()

                closeOtherTabsMenu(bypassArchive: false)
            }
        }

        // MARK: - Close Other Tabs Helpers

        /// Returns main tabs (non-archived, non-reference) sorted by position.
        /// Note: space.mainTabs is already sorted by position.
        private var sortedMainTabs: [Refrax.Tab] {
            tab.space?.mainTabs ?? []
        }

        /// Index of this tab in sortedMainTabs.
        private var tabIndex: Int? {
            sortedMainTabs.firstIndex(where: { $0.id == tab.id })
        }

        /// Tabs above this tab in the list.
        private var tabsAbove: [Refrax.Tab] {
            guard let index = tabIndex, index > 0 else { return [] }
            return Array(sortedMainTabs[..<index])
        }

        /// Tabs below this tab in the list.
        private var tabsBelow: [Refrax.Tab] {
            guard let index = tabIndex, index < sortedMainTabs.count - 1 else { return [] }
            return Array(sortedMainTabs[(index + 1)...])
        }

        /// Other tabs (all except this one).
        private var otherTabs: [Refrax.Tab] {
            sortedMainTabs.filter { $0.id != tab.id }
        }

        @ViewBuilder
        private func closeOtherTabsMenu(bypassArchive: Bool) -> some View {
            let archiveMode = settings.archiveEnabled && !bypassArchive

            // Close Other Tabs
            if !otherTabs.isEmpty {
                Button(role: bypassArchive ? .destructive : nil) {
                    tabManager.requestCloseTabs(otherTabs, bypassArchive: bypassArchive)
                } label: {
                    if archiveMode {
                        Label("Archive Other Tabs", systemImage: ContextMenuIcon.archive.systemName)
                    } else if bypassArchive {
                        Label("Delete Other Tabs Immediately", systemImage: ContextMenuIcon.deleteImmediately.systemName)
                    } else {
                        Label("Close Other Tabs", systemImage: ContextMenuIcon.close.systemName)
                    }
                }
            }

            // Close Tabs Above
            if !tabsAbove.isEmpty {
                Button(role: bypassArchive ? .destructive : nil) {
                    tabManager.requestCloseTabs(tabsAbove, bypassArchive: bypassArchive)
                } label: {
                    if archiveMode {
                        Label("Archive All Tabs Above", systemImage: ContextMenuIcon.archive.systemName)
                    } else if bypassArchive {
                        Label("Delete All Tabs Above Immediately", systemImage: ContextMenuIcon.deleteImmediately.systemName)
                    } else {
                        Label("Close All Tabs Above", systemImage: ContextMenuIcon.close.systemName)
                    }
                }
            }

            // Close Tabs Below
            if !tabsBelow.isEmpty {
                Button(role: bypassArchive ? .destructive : nil) {
                    tabManager.requestCloseTabs(tabsBelow, bypassArchive: bypassArchive)
                } label: {
                    if archiveMode {
                        Label("Archive All Tabs Below", systemImage: ContextMenuIcon.archive.systemName)
                    } else if bypassArchive {
                        Label("Delete All Tabs Below Immediately", systemImage: ContextMenuIcon.deleteImmediately.systemName)
                    } else {
                        Label("Close All Tabs Below", systemImage: ContextMenuIcon.close.systemName)
                    }
                }
            }
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
