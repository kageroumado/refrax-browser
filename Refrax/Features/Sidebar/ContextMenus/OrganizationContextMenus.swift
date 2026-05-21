import AppKit
import SwiftUI

// MARK: - Tab Group Context Menu

extension SidebarContextMenus {
    /// Context menu for a tab group header.
    ///
    /// ## Menu Structure (consistent ordering)
    /// 1. Identity: Rename, Change Icon, Change Color
    /// 2. Status: Pin
    /// 3. Organization: Nest, Duplicate, Move to Space
    /// 4. Copy
    /// 5. Destructive: Close tabs, Delete group
    struct Group: View {
        @SwiftUI.Environment(TabManager.self) private var tabManager
        @SwiftUI.Environment(TabGroupManager.self) private var groupManager
        @SwiftUI.Environment(WindowState.self) private var windowState
        @SwiftUI.Environment(BrowserSettings.self) private var settings

        let group: TabGroup
        var onEditGroup: (() -> Void)?

        private var env: Environment {
            Environment(tabManager: tabManager, windowState: windowState, bookmarksManager: nil)
        }

        private var nestableGroups: [TabGroup] {
            env.nestableGroups(excluding: group.id)
        }

        private var tabsInGroup: [Refrax.Tab] {
            windowState.activeSpace?.tabs.filter { $0.groupID == group.id } ?? []
        }

        /// Spaces available for moving the group to (excludes current space).
        private var availableSpaces: [Space] {
            env.availableSpaces
        }

        var body: some View {
            if group.isArchive {
                archiveGroupMenu
            } else {
                regularGroupMenu
            }
        }

        // MARK: - Archive Group Menu

        @ViewBuilder
        private var archiveGroupMenu: some View {
            // Copy URLs (if there are tabs)
            if !tabsInGroup.isEmpty {
                Button {
                    let urls = tabsInGroup.map { tabManager.copyableURL(for: $0) }
                    let joined = urls.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(joined, forType: .string)
                } label: {
                    Label("Copy All URLs", systemImage: ContextMenuIcon.copyURL.systemName)
                }

                Divider()
            }

            // Empty Archive
            Button(role: .destructive) {
                if let space = group.space {
                    tabManager.archiveManager.clearArchive(
                        in: space,
                        context: tabManager.state.modelContext,
                    )
                }
            } label: {
                Label("Empty Archive", systemImage: ContextMenuIcon.clear.systemName)
            }
        }

        // MARK: - Regular Group Menu

        @ViewBuilder
        private var regularGroupMenu: some View {
            // MARK: Identity

            Button {
                onEditGroup?()
            } label: {
                Label("Edit Group...", systemImage: ContextMenuIcon.edit.systemName)
            }

            Divider()

            // MARK: Status

            Button {
                groupManager.toggleGroupPinned(group)
            } label: {
                Label(
                    group.isPinned ? "Unpin" : "Pin",
                    systemImage: group.isPinned ? ContextMenuIcon.unpin.systemName : ContextMenuIcon.pin.systemName,
                )
            }

            // Nesting
            if group.isRoot {
                if !nestableGroups.isEmpty {
                    Menu {
                        ForEach(nestableGroups) { parentGroup in
                            Button {
                                do {
                                    try groupManager.nestGroup(group, in: parentGroup)
                                } catch {
                                    Logger.debug("Couldn't nest group: \(error)", category: Logger.tabs)
                                }
                            } label: {
                                Label(parentGroup.name, systemImage: parentGroup.iconName ?? "folder.fill")
                            }
                        }
                    } label: {
                        Label("Nest in Group", systemImage: ContextMenuIcon.nestInGroup.systemName)
                    }
                }
            } else {
                Button {
                    groupManager.unnestGroup(group)
                } label: {
                    Label("Unnest Group", systemImage: ContextMenuIcon.unnestGroup.systemName)
                }
            }

            Divider()

            // MARK: Organization

            Button("Duplicate Group") {
                groupManager.duplicateGroup(group)
            }

            Button("Convert to Space") {
                do {
                    _ = try groupManager.convertGroupToSpace(group)
                } catch {
                    Logger.debug("Failed to convert group to space: \(error)", category: Logger.tabs)
                }
            }

            // Move to space
            if !availableSpaces.isEmpty {
                Menu {
                    ForEach(availableSpaces) { space in
                        Button {
                            groupManager.moveGroupToSpace(group, to: space)
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

            if !tabsInGroup.isEmpty {
                Button {
                    let urls = tabsInGroup.map { tabManager.copyableURL(for: $0) }
                    let joined = urls.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(joined, forType: .string)
                } label: {
                    Label("Copy URLs", systemImage: ContextMenuIcon.copyURL.systemName)
                }

                Button {
                    var lines: [String] = []
                    lines.append("## \(group.displayNameWithIcon)")
                    for tab in tabsInGroup {
                        let url = tabManager.copyableURL(for: tab)
                        lines.append("- [\(tab.displayTitle)](\(url))")
                    }
                    let markdown = lines.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                } label: {
                    Label("Copy URLs as Markdown", systemImage: ContextMenuIcon.copyURL.systemName)
                }

                Divider()
            }

            // MARK: Destructive

            if !tabsInGroup.isEmpty {
                if settings.archiveEnabled {
                    Button {
                        tabManager.requestCloseTabs(tabsInGroup)
                    } label: {
                        Label("Archive All Tabs in Group", systemImage: ContextMenuIcon.archive.systemName)
                    }

                    Button(role: .destructive) {
                        tabManager.requestCloseTabs(tabsInGroup, bypassArchive: true)
                    } label: {
                        Label("Delete All Tabs Immediately", systemImage: ContextMenuIcon.deleteImmediately.systemName)
                    }
                } else {
                    Button {
                        tabManager.requestCloseTabs(tabsInGroup)
                    } label: {
                        Label("Close All Tabs in Group", systemImage: ContextMenuIcon.close.systemName)
                    }
                }
            }

            Button {
                groupManager.deleteGroup(group)
            } label: {
                Label("Delete Group", systemImage: ContextMenuIcon.delete.systemName)
            }
            .keyboardShortcut(.delete, modifiers: [])
        }
    }
}

// MARK: - Space Context Menu

extension SidebarContextMenus {
    /// Context menu for a space in the sidebar.
    ///
    /// ## Menu Structure (consistent ordering)
    /// 1. Identity: Rename, Change Icon, Edit
    /// 2. Organization: Duplicate
    /// 3. Copy
    /// 4. Destructive: Delete/Clear
    /// 5. Space Management: New Space, Manage All
    ///
    /// ## Space Parameter
    ///
    /// When `space` is provided, the menu operates on that specific space.
    /// This enables right-click context menus on non-active spaces.
    /// When `space` is nil, falls back to `windowState.activeSpace`.
    struct SpaceMenu: View {
        @SwiftUI.Environment(TabManager.self) private var tabManager
        @SwiftUI.Environment(SpaceManager.self) private var spaceManager
        @SwiftUI.Environment(BrowserState.self) private var browserState
        @SwiftUI.Environment(WindowState.self) private var windowState

        /// The space this menu operates on. If nil, uses the active space.
        var space: Refrax.Space?

        var onQuickEdit: (() -> Void)?
        var onEdit: (() -> Void)?
        var onDelete: (() -> Void)?
        var onNewSpace: (() -> Void)?
        var onManageSpaces: (() -> Void)?

        /// The effective space for menu operations.
        private var currentSpace: Refrax.Space? { space ?? windowState.activeSpace }

        private var isSpaceUnlocked: Bool {
            guard let space = currentSpace else { return true }
            return browserState.spaceLockManager.unlockedSpaceIDs.contains(space.id)
        }

        /// Whether the space is locked and requires authentication.
        private var isSpaceLocked: Bool {
            guard let space = currentSpace else { return false }
            return space.isLockEnabled && !isSpaceUnlocked
        }

        /// Tabs in the target space (for copy/delete operations).
        private var tabsInSpace: [Refrax.Tab] {
            guard let space = currentSpace else { return [] }
            return browserState.tabs(in: space)
        }

        /// Groups in the target space (for markdown export).
        private var groupsInSpace: [TabGroup] {
            guard let space = currentSpace else { return [] }
            return browserState.groups(in: space)
        }

        var body: some View {
            if let space = currentSpace {
                if isSpaceLocked {
                    // Locked space: only show unlock option
                    lockedSpaceMenu(space)
                } else {
                    // Unlocked space: full menu
                    unlockedSpaceMenu(space)
                }
            }

            // MARK: Space Management (always available)

            Button {
                onNewSpace?()
            } label: {
                Label("New Space...", systemImage: ContextMenuIcon.newSpace.systemName)
            }

            Button {
                onManageSpaces?()
            } label: {
                Label("Manage All Spaces...", systemImage: "rectangle.stack")
            }
        }

        // MARK: - Locked Space Menu

        @ViewBuilder
        private func lockedSpaceMenu(_ space: Refrax.Space) -> some View {
            Button {
                Task {
                    _ = await browserState.spaceLockManager.authenticate(for: space)
                }
            } label: {
                Label("Unlock '\(space.name)'...", systemImage: "lock.open.fill")
            }

            Divider()
        }

        // MARK: - Unlocked Space Menu

        @ViewBuilder
        private func unlockedSpaceMenu(_ space: Refrax.Space) -> some View {
            // MARK: Identity

            Button {
                onQuickEdit?()
            } label: {
                Label("Quick Edit '\(space.name)'...", systemImage: ContextMenuIcon.edit.systemName)
            }

            Button {
                onEdit?()
            } label: {
                Label("Edit '\(space.name)'...", systemImage: "slider.horizontal.3")
            }

            Divider()

            // MARK: Organization

            Button("Duplicate Space") {
                spaceManager.duplicateSpace(space)
            }

            // Convert to group (only if there are other spaces to convert into)
            if tabManager.hasMultipleSpaces {
                let hasDataIsolation = !space.dataStoreMode.isGlobal

                Menu {
                    if hasDataIsolation {
                        Text("Warning: This space has \(space.dataStoreMode.displayName.lowercased()) data storage. Tabs will lose their isolated cookies and data when converted.")
                            .font(.caption)

                        Divider()
                    }

                    ForEach(tabManager.state.spaces.filter { $0.id != space.id }) { targetSpace in
                        Button(targetSpace.name) {
                            do {
                                _ = try tabManager.groupManager.convertSpaceToGroup(space, in: targetSpace)
                            } catch {
                                Logger.debug("Failed to convert space to group: \(error)", category: Logger.tabs)
                            }
                        }
                    }
                } label: {
                    if hasDataIsolation {
                        Label("Convert to Group in... (Warning)", systemImage: "folder.fill.badge.plus")
                    } else {
                        Label("Convert to Group in...", systemImage: "folder.fill.badge.plus")
                    }
                }
            }

            Divider()

            // MARK: Security

            if space.isLockEnabled {
                // Disabling lock requires authentication
                Button {
                    Task {
                        let result = await browserState.spaceLockManager
                            .authenticateToModifyLockSettings(for: space)
                        if case .success = result {
                            space.isLockEnabled = false
                            browserState.spaceLockManager.lock(space: space)
                        }
                    }
                } label: {
                    Label("Disable Lock...", systemImage: ContextMenuIcon.lock.systemName)
                }

                Button {
                    browserState.spaceLockManager.lock(space: space)
                } label: {
                    Label("Lock Now", systemImage: ContextMenuIcon.lock.systemName)
                }
            } else {
                // Enabling lock doesn't require authentication
                Button {
                    space.isLockEnabled = true
                } label: {
                    Label("Enable Lock", systemImage: ContextMenuIcon.lock.systemName)
                }
            }

            Divider()

            // MARK: Copy

            if !tabsInSpace.isEmpty {
                Button {
                    let urls = tabsInSpace.map { tabManager.copyableURL(for: $0) }
                    let joined = urls.joined(separator: "\n")
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(joined, forType: .string)
                } label: {
                    Label("Copy URLs", systemImage: ContextMenuIcon.copyURL.systemName)
                }

                Button {
                    let markdown = formatSpaceAsMarkdown(space)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(markdown, forType: .string)
                } label: {
                    Label("Copy URLs as Markdown", systemImage: ContextMenuIcon.copyURL.systemName)
                }

                Divider()
            }

            // MARK: Destructive

            if tabManager.hasMultipleSpaces {
                Button {
                    onDelete?()
                } label: {
                    Label("Delete '\(space.name)'...", systemImage: ContextMenuIcon.delete.systemName)
                }
            } else {
                Button(role: .destructive) {
                    onDelete?()
                } label: {
                    Label("Clear '\(space.name)'...", systemImage: ContextMenuIcon.clear.systemName)
                }
            }

            Divider()
        }

        /// Formats a space's tabs and groups as a nicely structured Markdown document.
        private func formatSpaceAsMarkdown(_ space: Refrax.Space) -> String {
            var lines: [String] = []
            lines.append("# \(space.displayNameWithIcon)")
            lines.append("")

            // Get tabs organized by group
            let ungroupedTabs = tabsInSpace.filter { $0.groupID == nil && !$0.isPinned }
            let pinnedTabs = tabsInSpace.filter(\.isPinned)
            let groups = groupsInSpace.sorted { $0.position < $1.position }

            // Pinned tabs
            if !pinnedTabs.isEmpty {
                lines.append("## Pinned")
                for tab in pinnedTabs.sorted(by: { $0.position < $1.position }) {
                    let url = tabManager.copyableURL(for: tab)
                    lines.append("- [\(tab.displayTitle)](\(url))")
                }
                lines.append("")
            }

            // Groups
            for group in groups {
                let tabsInGroup = tabsInSpace.filter { $0.groupID == group.id }
                    .sorted { $0.position < $1.position }
                if !tabsInGroup.isEmpty {
                    lines.append("## \(group.displayNameWithIcon)")
                    for tab in tabsInGroup {
                        let url = tabManager.copyableURL(for: tab)
                        lines.append("- [\(tab.displayTitle)](\(url))")
                    }
                    lines.append("")
                }
            }

            // Ungrouped tabs
            if !ungroupedTabs.isEmpty {
                if !groups.isEmpty || !pinnedTabs.isEmpty {
                    lines.append("## Other")
                }
                for tab in ungroupedTabs.sorted(by: { $0.position < $1.position }) {
                    let url = tabManager.copyableURL(for: tab)
                    lines.append("- [\(tab.displayTitle)](\(url))")
                }
            }

            return lines.joined(separator: "\n")
        }
    }
}
