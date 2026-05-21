import Foundation

/// Commands that can be executed against the browser.
///
/// Commands represent state-changing operations. Each command specifies
/// the required permissions and returns a typed result.
public enum APICommand: Sendable {
    // MARK: - Tab Commands

    /// Opens a new tab with the specified URL.
    ///
    /// - Parameters:
    ///   - url: The URL to open.
    ///   - spaceID: Target space (uses active space if nil).
    ///   - activate: Whether to activate the new tab. Defaults to `true`.
    ///   - groupID: Optional group to add the tab to.
    case openTab(url: URL, spaceID: UUID?, activate: Bool, groupID: UUID?)

    /// Closes a tab.
    ///
    /// - Parameter id: The tab to close.
    case closeTab(id: UUID)

    /// Closes multiple tabs.
    ///
    /// - Parameter ids: The tabs to close.
    case closeTabs(ids: [UUID])

    /// Navigates a tab to a new URL.
    ///
    /// - Parameters:
    ///   - tabID: The tab to navigate.
    ///   - url: The destination URL.
    case navigate(tabID: UUID, to: URL)

    /// Reloads a tab.
    ///
    /// - Parameters:
    ///   - tabID: The tab to reload.
    ///   - fromOrigin: If true, bypasses cache.
    case reload(tabID: UUID, fromOrigin: Bool)

    /// Goes back in navigation history.
    ///
    /// - Parameter tabID: The tab to navigate.
    case goBack(tabID: UUID)

    /// Goes forward in navigation history.
    ///
    /// - Parameter tabID: The tab to navigate.
    case goForward(tabID: UUID)

    /// Activates (focuses) a tab.
    ///
    /// - Parameter id: The tab to activate.
    case activateTab(id: UUID)

    /// Pins or unpins a tab.
    ///
    /// - Parameters:
    ///   - id: The tab to modify.
    ///   - isPinned: New pin state.
    case setTabPinned(id: UUID, isPinned: Bool)

    /// Moves a tab to a different position.
    ///
    /// - Parameters:
    ///   - id: The tab to move.
    ///   - toIndex: New position index.
    case moveTab(id: UUID, toIndex: Int)

    /// Moves a tab to a different space.
    ///
    /// - Parameters:
    ///   - id: The tab to move.
    ///   - spaceID: Target space.
    case moveTabToSpace(id: UUID, spaceID: UUID)

    /// Duplicates a tab.
    ///
    /// - Parameters:
    ///   - id: The tab to duplicate.
    ///   - activate: Whether to activate the duplicate.
    case duplicateTab(id: UUID, activate: Bool)

    // MARK: - Space Commands

    /// Creates a new space.
    ///
    /// - Parameters:
    ///   - name: Display name.
    ///   - colorHex: Theme color (hex format).
    ///   - iconName: SF Symbol name or emoji.
    ///   - dataStoreMode: Data storage mode ("global", "separate", or "private").
    case createSpace(name: String, colorHex: String?, iconName: String?, dataStoreMode: String?)

    /// Deletes a space.
    ///
    /// - Parameters:
    ///   - id: The space to delete.
    ///   - closeTabs: If true, closes all tabs. If false, moves them.
    case deleteSpace(id: UUID, closeTabs: Bool)

    /// Updates space properties.
    ///
    /// - Parameters:
    ///   - id: The space to update.
    ///   - name: New name (nil to keep current).
    ///   - colorHex: New color (nil to keep current).
    ///   - iconName: New icon (nil to keep current).
    case updateSpace(id: UUID, name: String?, colorHex: String?, iconName: String?)

    /// Switches to a different space.
    ///
    /// - Parameter id: The space to switch to.
    case switchToSpace(id: UUID)

    // MARK: - Group Commands

    /// Creates a tab group.
    ///
    /// - Parameters:
    ///   - spaceID: The space to create the group in.
    ///   - name: Group name.
    ///   - colorHex: Group color (hex format).
    ///   - tabIDs: Initial tabs to add to the group.
    case createGroup(spaceID: UUID, name: String, colorHex: String?, tabIDs: [UUID])

    /// Deletes a tab group.
    ///
    /// - Parameters:
    ///   - id: The group to delete.
    ///   - closeTabs: If true, closes all tabs in the group.
    case deleteGroup(id: UUID, closeTabs: Bool)

    /// Updates group properties.
    ///
    /// - Parameters:
    ///   - id: The group to update.
    ///   - name: New name (nil to keep current).
    ///   - colorHex: New color (nil to keep current).
    ///   - isCollapsed: New collapsed state (nil to keep current).
    case updateGroup(id: UUID, name: String?, colorHex: String?, isCollapsed: Bool?)

    /// Adds tabs to a group.
    ///
    /// - Parameters:
    ///   - groupID: The target group.
    ///   - tabIDs: Tabs to add.
    case addTabsToGroup(groupID: UUID, tabIDs: [UUID])

    /// Removes tabs from a group.
    ///
    /// - Parameter tabIDs: Tabs to remove from their groups.
    case removeTabsFromGroup(tabIDs: [UUID])
}

// MARK: - Permission Requirements

public extension APICommand {
    /// Permission requirements for executing this command.
    var permissionRequirements: PermissionRequirements {
        switch self {
        case .openTab, .closeTab, .closeTabs, .navigate, .reload, .goBack, .goForward,
             .activateTab, .setTabPinned, .moveTab, .duplicateTab:
            .tabsWrite
        case .moveTabToSpace:
            PermissionRequirements(scopes: [.tabsWrite, .spacesWrite])
        case .createSpace, .deleteSpace, .updateSpace, .switchToSpace:
            .spacesWrite
        case .createGroup, .deleteGroup, .updateGroup, .addTabsToGroup, .removeTabsFromGroup:
            PermissionRequirements(scopes: [.tabsWrite])
        }
    }
}

// MARK: - Command Result

/// Result of executing an API command.
public enum CommandResult: Sendable {
    /// Command completed successfully with no specific return value.
    case success

    /// Tab was created or duplicated.
    case tab(TabInfo)

    /// Space was created.
    case space(SpaceInfo)

    /// Group was created.
    case group(TabGroupInfo)

    /// Multiple tabs were affected.
    case tabs([TabInfo])
}
