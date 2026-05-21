import AppKit
import Foundation
import Observation
import SwiftData
import SwiftUI

// MARK: - Group Collapse Handler Protocol

/// Protocol for incremental layout updates during group collapse/expand.
///
/// Allows `TabGroupManager` to notify `LayoutManager` of collapse state changes
/// without triggering full layout rebuilds. The handler can update visibility
/// of descendant items in O(n) time instead of O(n log n) hierarchy rebuilds.
protocol GroupCollapseHandler: AnyObject {
    /// Gets all descendant IDs of a group.
    ///
    /// - Parameter groupID: The group to get descendants for.
    /// - Returns: Set of all descendant IDs (tabs and nested groups). Empty if group not found.
    func getAllDescendantIDs(of groupID: UUID) -> Set<UUID>

    /// Sets visibility of items without full layout rebuild.
    ///
    /// - Parameters:
    ///   - itemIDs: The items to show or hide.
    ///   - hidden: If `true`, hides items. If `false`, shows items.
    func setItemsHidden(_ itemIDs: Set<UUID>, hidden: Bool)
}

/// Manages tab groups within spaces.
///
/// `TabGroupManager` handles group lifecycle and organization:
/// - Creating, renaming, and deleting groups
/// - Moving tabs in/out of groups
/// - Group nesting (max 2 levels)
/// - Group pinning and collapsing
///
/// ## Multi-Window Support
///
/// Group operations accept a `Space`, `Space.ID`, or default to the active window's
/// space via `windowManager`. This provides flexibility for multi-window scenarios
/// while keeping common single-window usage simple.
///
/// ## Undo Support
///
/// Group deletion captures `ClosedGroupInfo` for undo/redo via the
/// system's `UndoManager`.
@Observable
final class TabGroupManager {
    // MARK: - Dependencies

    private unowned let state: BrowserState

    /// The ID of a group that should enter editing mode.
    ///
    /// Views observe this to trigger inline rename when a group is created.
    /// Automatically cleared after being consumed.
    var groupIDToEdit: UUID?

    /// Window manager for accessing the active window state.
    ///
    /// Set after initialization.
    unowned var windowManager: WindowManager!

    /// Undo/redo manager for browser-level undo operations.
    ///
    /// Set after initialization.
    unowned var undoRedoManager: UndoRedoManager!

    /// WebPage pool for cleaning up WebView sessions when deleting groups with tabs.
    ///
    /// Set after initialization.
    unowned var pagePool: WebPagePool!

    /// Handler for incremental layout updates during collapse/expand.
    ///
    /// When set, `toggleGroupCollapsed` uses this to update item visibility
    /// incrementally instead of triggering a full layout rebuild.
    weak var collapseHandler: (any GroupCollapseHandler)?

    // MARK: - Initialization
    
    init(state: BrowserState) {
        self.state = state
    }
    
    // MARK: - Window Access

    #if REFRAX_TESTS
        /// Test-only override for `activeWindowState` when no actual window exists.
        /// Set this in tests after creating a WindowState to enable active space resolution.
        var testActiveWindowState: WindowState?
    #endif

    /// Gets the active window's state.
    private var activeWindowState: WindowState? {
        #if REFRAX_TESTS
            if let testState = testActiveWindowState {
                return testState
            }
        #endif
        return windowManager.activeWindowController?.windowState
    }
    
    // MARK: - Space Resolution
    
    /// Resolves a space from ID, Space, or defaults to active space.
    ///
    /// Resolution order:
    /// 1. Explicit Space parameter
    /// 2. Look up by spaceID
    /// 3. Active window's active space
    ///
    /// - Parameters:
    ///   - space: Optional Space instance.
    ///   - spaceID: Optional Space.ID to look up.
    /// - Returns: Resolved Space.
    /// - Throws: `TabGroupError.noActiveSpace` if no space can be resolved.
    private func resolveSpace(_ space: Space? = nil, id spaceID: UUID? = nil) throws -> Space {
        // Explicit Space takes priority
        if let space { return space }
        
        // Look up by ID
        if let spaceID, let space = state.space(for: spaceID) {
            return space
        }
        
        // Default to active window's space
        if let activeSpace = activeWindowState?.activeSpace {
            return activeSpace
        }
        
        throw TabGroupError.noActiveSpace
    }
    
    /// Resolves a space with fallback to an entity's spaceID.
    ///
    /// Used when operating on a group or tab that knows its own space.
    ///
    /// - Parameters:
    ///   - space: Optional explicit Space.
    ///   - spaceID: Optional Space.ID to look up.
    ///   - entitySpace: Fallback space from the entity being operated on.
    /// - Returns: Resolved Space, or nil if none found.
    private func resolveSpaceWithFallback(
        _ space: Space?,
        id spaceID: UUID?,
        entitySpace: Space?,
    ) -> Space? {
        if let space { return space }
        if let spaceID, let resolved = state.space(for: spaceID) { return resolved }
        if let entitySpace { return entitySpace }
        return activeWindowState?.activeSpace
    }
    
    // MARK: - Group CRUD
    
    /// Creates a new tab group.
    ///
    /// - Parameters:
    ///   - space: Space to create the group in (defaults to active space).
    ///   - spaceID: Alternative: Space ID to look up.
    ///   - name: Display name for the group.
    ///   - color: GroupColor raw value (e.g., `GroupColor.steel.rawValue`).
    ///   - iconName: Optional SF Symbol name.
    ///   - parentGroupID: Parent group for nesting (nil for root).
    ///   - isPinned: Whether the group is pinned.
    ///   - startEditing: If true, the group will enter inline rename mode after creation.
    /// - Returns: The created TabGroup.
    /// - Throws: `TabGroupError` if nesting is invalid or no space available.
    @discardableResult
    func createGroup(
        in space: Space? = nil,
        spaceID: UUID? = nil,
        name: String,
        color: String = GroupColor.steel.rawValue,
        iconName: String? = nil,
        parentGroupID: UUID? = nil,
        isPinned: Bool = false,
        startEditing: Bool = false,
    ) throws -> TabGroup {
        let targetSpace = try resolveSpace(space, id: spaceID)

        // Validate nesting depth
        if let parentID = parentGroupID {
            guard let parentGroup = targetSpace.groups.first(where: { $0.id == parentID }) else {
                throw TabGroupError.parentGroupNotFound
            }
            guard parentGroup.parentGroupID == nil else {
                throw TabGroupError.nestingTooDeep
            }
        }

        // Calculate position - prepend at top of list (like tabs)
        let position: Int
        if isPinned {
            // For pinned groups, insert before first pinned item or use root multiplier
            let minPinnedTab = targetSpace.tabs.lazy.filter(\.isPinned).map(\.position).min()
            let minPinnedGroup = targetSpace.groups.lazy.filter(\.isPinned).map(\.position).min()
            let minPinned = [minPinnedTab, minPinnedGroup].compactMap(\.self).min()
            if let minPinned {
                position = minPinned / 2
            } else {
                position = TabPositioner.rootMultiplier
            }
        } else {
            // For unpinned groups, insert at top of unpinned section
            let minUnpinnedTab = targetSpace.tabs.lazy.filter { !$0.isPinned && !$0.isReferenceTab }.map(\.position).min()
            let minUnpinnedGroup = targetSpace.groups.lazy.filter { !$0.isPinned }.map(\.position).min()
            let minUnpinned = [minUnpinnedTab, minUnpinnedGroup].compactMap(\.self).min()
            if let minUnpinned {
                position = minUnpinned / 2
            } else {
                position = TabPositioner.rootMultiplier
            }
        }

        let group = TabGroup(
            space: targetSpace,
            name: name,
            color: color,
            iconName: iconName,
            parentGroupID: parentGroupID,
            position: position,
            isPinned: isPinned,
        )

        targetSpace.groups.append(group)
        state.modelContext.insert(group)
        state.incrementListVersion()
        scheduleSave()

        if startEditing {
            groupIDToEdit = group.id
        }

        return group
    }
    
    /// Deletes a group.
    ///
    /// Registers with the active window's undo manager for undo support.
    ///
    /// - Parameters:
    ///   - group: Group to delete.
    ///   - space: Space containing the group (defaults to group's space or active space).
    ///   - spaceID: Alternative: Space ID to look up.
    ///   - deleteContainedTabs: If true, deletes all tabs. If false, ungroups them.
    func deleteGroup(
        _ group: TabGroup,
        in space: Space? = nil,
        spaceID: UUID? = nil,
        deleteContainedTabs: Bool = false,
    ) {
        guard let targetSpace = resolveSpaceWithFallback(space, id: spaceID, entitySpace: group.space) else {
            Logger.error("Cannot delete group: no space available", category: Logger.tabs)
            return
        }
        
        guard let index = targetSpace.groups.firstIndex(where: { $0.id == group.id }) else {
            return
        }
        
        // Capture for undo (sorted by position to preserve order on restore)
        let tabsInGroup = targetSpace.tabs.filter { $0.groupID == group.id }.sorted { $0.position < $1.position }
        let closedInfo = ClosedGroupInfo(group: group, tabs: tabsInGroup)
        
        // Handle nested groups first (pass resolved space directly)
        let nestedGroups = targetSpace.groups.filter { $0.parentGroupID == group.id }
        for nestedGroup in nestedGroups {
            deleteGroup(nestedGroup, in: targetSpace, deleteContainedTabs: deleteContainedTabs)
        }
        
        if deleteContainedTabs {
            for tab in tabsInGroup {
                pagePool.removePages(for: tab)
                state.removeFromIndex(tab)
                targetSpace.tabs.removeAll { $0.id == tab.id }
                state.modelContext.delete(tab)
            }
        } else {
            // Ungroup tabs
            for tab in tabsInGroup {
                tab.groupID = nil
                tab.group = nil
            }
        }
        
        targetSpace.groups.remove(at: index)
        state.modelContext.delete(group)

        // Register undo with UndoRedoManager
        undoRedoManager.registerDeleteGroup(closedInfo)

        state.incrementListVersion()
        scheduleSave()

        Logger.info("Group deleted: \(group.name)", category: Logger.tabs)
    }
    
    /// Restores a deleted group from `ClosedGroupInfo`.
    func restoreGroup(_ info: ClosedGroupInfo) {
        guard let space = state.space(for: info.spaceID) else {
            Logger.error("Cannot restore group: space not found", category: Logger.tabs)
            return
        }

        let group = TabGroup(
            space: space,
            name: info.name,
            color: info.colorString,
            iconName: info.iconName,
            parentGroupID: info.parentGroupID,
            position: info.position,
            isPinned: info.isPinned,
        )

        space.groups.append(group)
        state.modelContext.insert(group)
        
        // Restore tabs
        for tabInfo in info.tabs {
            let status: TabStatus = tabInfo.isPinned ? .pinned : .regular
            let tab = Tab(
                space: space,
                url: tabInfo.url,
                title: tabInfo.title,
                status: status,
                position: tabInfo.position,
            )
            tab.customName = tabInfo.customName
            tab.activePage.faviconData = tabInfo.faviconData

            // Set group relationship after init (Tab.init clears groupID for pinned tabs)
            tab.groupID = group.id
            tab.group = group

            space.tabs.append(tab)
            state.indexTab(tab)
            state.modelContext.insert(tab)
        }
        
        state.incrementListVersion()
        scheduleSave()
        Logger.info("Group restored: \(info.name)", category: Logger.tabs)
    }
    
    /// Renames a group.
    func renameGroup(_ group: TabGroup, to newName: String) {
        group.name = newName
        state.incrementContentVersion()
        scheduleSave()
        Logger.info("Group renamed to: \(newName)", category: Logger.tabs)
    }
    
    /// Updates a group's color.
    func updateGroupColor(_ group: TabGroup, to newColor: String) {
        group.colorString = newColor
        state.incrementContentVersion()
        scheduleSave()
    }

    /// Updates a group's icon.
    ///
    /// - Parameters:
    ///   - group: Group to update.
    ///   - newIconName: SF Symbol name or emoji string. Pass nil to use default folder icon.
    func updateGroupIcon(_ group: TabGroup, to newIconName: String?) {
        group.iconName = newIconName
        state.incrementContentVersion()
        scheduleSave()
        Logger.info("Group icon updated: \(group.name) -> \(newIconName ?? "default")", category: Logger.tabs)
    }
    
    // MARK: - Tab Membership
    
    /// Moves a tab to a group.
    ///
    /// - Parameters:
    ///   - tab: Tab to move.
    ///   - group: Target group (nil to ungroup).
    ///   - space: Space containing the tab (defaults to tab's space or active space).
    ///   - spaceID: Alternative: Space ID to look up.
    ///   - skipReordering: If true, does not modify `tab.position`. Useful when caller
    ///     handles position management externally (e.g., drag-and-drop reordering).
    func moveTabToGroup(
        _ tab: Tab,
        group: TabGroup?,
        in space: Space? = nil,
        spaceID: UUID? = nil,
        skipReordering: Bool = false,
    ) {
        guard let targetSpace = resolveSpaceWithFallback(space, id: spaceID, entitySpace: tab.space) else {
            Logger.error("Cannot move tab to group: no space available", category: Logger.tabs)
            return
        }

        // Remove from current group
        if let currentGroupID = tab.groupID,
           let currentGroup = targetSpace.groups.first(where: { $0.id == currentGroupID }) {
            currentGroup._removeTab(tab)
        }
        tab.groupID = nil
        tab.group = nil

        // Add to new group
        if let group {
            tab.groupID = group.id
            tab.group = group
            group._addTab(tab)
            if !skipReordering {
                tab.position = group.position + 1
            }
            Logger.info("Tab '\(tab.activePage.title)' moved to group '\(group.name)'", category: Logger.tabs)
        } else {
            Logger.info("Tab '\(tab.activePage.title)' removed from group", category: Logger.tabs)
        }

        state.incrementListVersion()
        scheduleSave()
    }

    /// Removes a tab from its group.
    ///
    /// - Parameters:
    ///   - tab: Tab to ungroup.
    ///   - space: Space containing the tab (defaults to tab's space or active space).
    ///   - spaceID: Alternative: Space ID to look up.
    ///   - skipReordering: If true, does not modify `tab.position`. Useful when caller
    ///     handles position management externally.
    func removeTabFromGroup(
        _ tab: Tab,
        in space: Space? = nil,
        spaceID: UUID? = nil,
        skipReordering: Bool = false,
    ) {
        moveTabToGroup(tab, group: nil, in: space, spaceID: spaceID, skipReordering: skipReordering)
    }
    
    // MARK: - Group State
    
    /// Toggles a group's collapsed state.
    ///
    /// When a `collapseHandler` is set and the group is in the active space,
    /// updates item visibility incrementally instead of triggering a full
    /// layout rebuild. This reduces collapse/expand from O(n log n) to O(n).
    ///
    /// The visibility change is wrapped in animation so items fade in/out
    /// smoothly during collapse/expand transitions.
    func toggleGroupCollapsed(_ group: TabGroup) {
        let willCollapse = !group.isCollapsed

        // Try incremental update via collapse handler
        var handledIncrementally = false
        if let handler = collapseHandler {
            let descendants = handler.getAllDescendantIDs(of: group.id)
            if !descendants.isEmpty {
                // Animate the visibility change for smooth collapse/expand.
                // group.isCollapsed must be set inside withAnimation so that
                // views keyed on it (badge, squircle, container bg) animate too.
                withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                    group.isCollapsed = willCollapse
                    handler.setItemsHidden(descendants, hidden: willCollapse)
                }
                handledIncrementally = true
            }
        }

        // Fallback if no incremental handler (e.g. no descendants)
        if !handledIncrementally {
            group.isCollapsed = willCollapse
        }

        state.incrementListVersion()

        // Mark as handled if we used incremental update
        if handledIncrementally {
            state.markIncrementallyHandled()
        }

        scheduleSave()
    }

    /// Collapses all groups in a space.
    ///
    /// - Parameters:
    ///   - space: Space containing the groups (defaults to active space).
    ///   - spaceID: Alternative: Space ID to look up.
    func collapseAllGroups(in space: Space? = nil, spaceID: UUID? = nil) {
        let allGroups = groups(in: space, spaceID: spaceID)
        guard !allGroups.isEmpty else { return }

        for group in allGroups where !group.isCollapsed {
            group.isCollapsed = true
        }
        state.incrementListVersion()
        scheduleSave()
    }

    /// Expands all groups in a space.
    ///
    /// - Parameters:
    ///   - space: Space containing the groups (defaults to active space).
    ///   - spaceID: Alternative: Space ID to look up.
    func expandAllGroups(in space: Space? = nil, spaceID: UUID? = nil) {
        let allGroups = groups(in: space, spaceID: spaceID)
        guard !allGroups.isEmpty else { return }

        for group in allGroups where group.isCollapsed {
            group.isCollapsed = false
        }
        state.incrementListVersion()
        scheduleSave()
    }

    /// Removes all groups in a space, ungrouping any tabs within them.
    ///
    /// Tabs inside groups are preserved and become ungrouped (not deleted).
    /// All groups including nested ones are removed in a single operation.
    ///
    /// - Parameters:
    ///   - space: Space to remove groups from (defaults to active space).
    ///   - spaceID: Alternative: Space ID to look up.
    func removeAllGroups(in space: Space? = nil, spaceID: UUID? = nil) {
        let allGroups = groups(in: space, spaceID: spaceID)
        guard !allGroups.isEmpty else { return }

        // Delete root-level groups only; deleteGroup handles nested groups recursively
        let rootGroups = allGroups.filter { $0.parentGroupID == nil }
        for group in rootGroups {
            deleteGroup(group, in: space, spaceID: spaceID, deleteContainedTabs: false)
        }

        Logger.info("Removed all \(allGroups.count) groups", category: Logger.tabs)
    }

    /// Toggles a group's pinned state.
    ///
    /// Also pins/unpins all tabs in the group and nested groups.
    /// Archive groups cannot be pinned.
    ///
    /// - Parameters:
    ///   - group: Group to pin/unpin.
    ///   - space: Space containing the group (defaults to group's space or active space).
    ///   - spaceID: Alternative: Space ID to look up.
    func toggleGroupPinned(_ group: TabGroup, in space: Space? = nil, spaceID: UUID? = nil) {
        // Archive groups cannot be pinned
        guard !group.isArchive else {
            Logger.debug("Cannot pin archive group", category: Logger.tabs)
            return
        }

        guard let targetSpace = resolveSpaceWithFallback(space, id: spaceID, entitySpace: group.space) else {
            Logger.error("Cannot toggle group pinned: no space available", category: Logger.tabs)
            return
        }

        group.isPinned.toggle()
        
        // Pin/unpin all tabs in group
        let groupTabs = targetSpace.tabs.filter { $0.groupID == group.id }
        for tab in groupTabs {
            tab.isPinned = group.isPinned
        }
        
        // Handle nested groups
        let nestedGroups = targetSpace.groups.filter { $0.parentGroupID == group.id }
        for nestedGroup in nestedGroups {
            nestedGroup.isPinned = group.isPinned
            let nestedTabs = targetSpace.tabs.filter { $0.groupID == nestedGroup.id }
            for tab in nestedTabs {
                tab.isPinned = group.isPinned
            }
        }
        
        // Reposition
        if group.isPinned {
            let maxPinned = targetSpace.tabs.lazy.filter(\.isPinned).map(\.position).max() ?? -1
            group.position = maxPinned + 1
        } else {
            let minUnpinned = targetSpace.tabs.lazy.filter { !$0.isPinned }.map(\.position).min() ?? 0
            group.position = minUnpinned
        }
        
        state.incrementListVersion()
        scheduleSave()
        Logger.info("Group '\(group.name)' \(group.isPinned ? "pinned" : "unpinned")", category: Logger.tabs)
    }
    
    // MARK: - Group Nesting
    
    /// Nests a group within another group.
    ///
    /// Archive groups cannot be nested or contain nested groups.
    ///
    /// - Throws: `TabGroupError` if nesting would exceed 2 levels or involves archive groups.
    func nestGroup(_ childGroup: TabGroup, in parentGroup: TabGroup) throws {
        guard !childGroup.isArchive else {
            throw TabGroupError.invalidOperation(reason: "Archive groups cannot be nested")
        }
        guard !parentGroup.isArchive else {
            throw TabGroupError.invalidOperation(reason: "Cannot nest groups inside archive")
        }
        guard childGroup.parentGroupID == nil else {
            throw TabGroupError.alreadyNested
        }
        guard parentGroup.parentGroupID == nil else {
            throw TabGroupError.nestingTooDeep
        }
        guard childGroup.space?.id == parentGroup.space?.id else {
            throw TabGroupError.differentSpaces
        }

        childGroup.parentGroupID = parentGroup.id
        childGroup.position = parentGroup.position + 1
        
        state.incrementListVersion()
        scheduleSave()
        Logger.info("Group '\(childGroup.name)' nested in '\(parentGroup.name)'", category: Logger.tabs)
    }
    
    /// Removes nesting from a group (makes it root-level).
    func unnestGroup(_ group: TabGroup) {
        guard group.parentGroupID != nil else { return }
        group.parentGroupID = nil
        state.incrementListVersion()
        scheduleSave()
        Logger.info("Group '\(group.name)' unnested", category: Logger.tabs)
    }

    // MARK: - Group Movement and Duplication

    /// Moves a group and all its tabs to a different space.
    ///
    /// - Parameters:
    ///   - group: Group to move.
    ///   - targetSpace: Destination space.
    func moveGroupToSpace(_ group: TabGroup, to targetSpace: Space) {
        guard let sourceSpace = group.space, sourceSpace.id != targetSpace.id else {
            Logger.warning("Cannot move group to the same space", category: Logger.tabs)
            return
        }

        // Get all tabs in the group before modifying
        let tabsToMove = sourceSpace.tabs.filter { $0.groupID == group.id }.sorted { $0.position < $1.position }

        // Handle nested groups - move child groups first
        let nestedGroups = sourceSpace.groups.filter { $0.parentGroupID == group.id }
        for nestedGroup in nestedGroups {
            moveGroupToSpace(nestedGroup, to: targetSpace)
        }

        // Remove group from source space
        sourceSpace.groups.removeAll { $0.id == group.id }

        // Calculate new position in target space
        let existingPositions = (targetSpace.tabs.map(\.position) + targetSpace.groups.map(\.position))
        let maxPosition = existingPositions.max() ?? 0
        group.position = maxPosition + TabPositioner.rootMultiplier

        // Move group to target space
        group.space = targetSpace
        group.parentGroupID = nil // Clear nesting when moving between spaces
        targetSpace.groups.append(group)

        // Move all tabs in the group to the target space
        var tabOffset = 1
        for tab in tabsToMove {
            sourceSpace.tabs.removeAll { $0.id == tab.id }
            tab.space = targetSpace
            tab.position = group.position + tabOffset
            targetSpace.tabs.append(tab)
            tabOffset += 1
        }

        state.incrementListVersion()
        scheduleSave()

        Logger.info("Group '\(group.name)' moved to space '\(targetSpace.name)' with \(tabsToMove.count) tabs", category: Logger.tabs)
    }

    /// Duplicates a group and all its tabs within the same space.
    ///
    /// Creates a new group with the same properties (name + " Copy", color, icon)
    /// and duplicates all tabs in the group.
    ///
    /// - Parameter group: Group to duplicate.
    /// - Returns: The newly created duplicate group.
    @discardableResult
    func duplicateGroup(_ group: TabGroup) -> TabGroup? {
        guard let space = group.space else {
            Logger.error("Cannot duplicate group: no space available", category: Logger.tabs)
            return nil
        }

        // Calculate position right after the original group and its tabs
        let tabsInGroup = space.tabs.filter { $0.groupID == group.id }.sorted { $0.position < $1.position }
        let lastTabPosition = tabsInGroup.last?.position ?? group.position
        let newGroupPosition = lastTabPosition + TabPositioner.rootMultiplier

        // Create duplicated group
        let duplicatedGroup = TabGroup(
            space: space,
            name: group.name + " Copy",
            color: group.colorString,
            iconName: group.iconName,
            parentGroupID: group.parentGroupID,
            position: newGroupPosition,
            isPinned: group.isPinned,
        )
        duplicatedGroup.isCollapsed = group.isCollapsed

        space.groups.append(duplicatedGroup)
        state.modelContext.insert(duplicatedGroup)

        // Duplicate all tabs in the group
        var tabOffset = 1
        for originalTab in tabsInGroup {
            let duplicatedTab = Tab(
                space: space,
                url: originalTab.activePage.url,
                title: originalTab.activePage.title,
                status: originalTab.status,
                groupID: duplicatedGroup.id,
                position: newGroupPosition + tabOffset,
            )
            duplicatedTab.customName = originalTab.customName
            duplicatedTab.activePage.faviconData = originalTab.activePage.faviconData
            duplicatedTab.activePage.largeFaviconData = originalTab.activePage.largeFaviconData
            duplicatedTab.group = duplicatedGroup
            duplicatedTab.isUnread = true

            duplicatedGroup._addTab(duplicatedTab)
            space.tabs.append(duplicatedTab)
            state.indexTab(duplicatedTab)
            state.modelContext.insert(duplicatedTab)
            tabOffset += 1
        }

        state.incrementListVersion()
        scheduleSave()

        Logger.info("Group '\(group.name)' duplicated with \(tabsInGroup.count) tabs", category: Logger.tabs)
        return duplicatedGroup
    }

    // MARK: - Queries
    
    /// Gets tabs in a specific group.
    ///
    /// - Parameters:
    ///   - group: The group to get tabs from.
    ///   - space: Space containing the group (defaults to group's space or active space).
    ///   - spaceID: Alternative: Space ID to look up.
    /// - Returns: Sorted array of tabs in the group.
    func tabs(in group: TabGroup, space: Space? = nil, spaceID: UUID? = nil) -> [Tab] {
        guard let targetSpace = resolveSpaceWithFallback(space, id: spaceID, entitySpace: group.space) else {
            return []
        }
        
        return targetSpace.tabs
            .filter { $0.groupID == group.id }
            .sorted { $0.position < $1.position }
    }
    
    /// Number of groups in a space.
    ///
    /// - Parameters:
    ///   - space: Space to count groups in (defaults to active space).
    ///   - spaceID: Alternative: Space ID to look up.
    /// - Returns: Number of groups in the space.
    func groupCount(in space: Space? = nil, spaceID: UUID? = nil) -> Int {
        if let space {
            return space.groups.count
        } else if let spaceID, let resolved = state.space(for: spaceID) {
            return resolved.groups.count
        } else if let activeSpace = activeWindowState?.activeSpace {
            return activeSpace.groups.count
        }
        return 0
    }
    
    /// Gets all groups in a space.
    ///
    /// - Parameters:
    ///   - space: Space to get groups from (defaults to active space).
    ///   - spaceID: Alternative: Space ID to look up.
    /// - Returns: Array of groups in the space.
    func groups(in space: Space? = nil, spaceID: UUID? = nil) -> [TabGroup] {
        if let space {
            return space.groups
        } else if let spaceID, let resolved = state.space(for: spaceID) {
            return resolved.groups
        } else if let activeSpace = activeWindowState?.activeSpace {
            return activeSpace.groups
        }
        return []
    }
    
    // MARK: - Group ↔ Space Conversion

    /// Converts a tab group to a new space.
    ///
    /// Creates a new space with the group's name and color, moves all tabs from the
    /// group to the new space, then deletes the original group.
    ///
    /// Archive groups cannot be converted to spaces.
    ///
    /// - Parameter group: The group to convert to a space.
    /// - Returns: The newly created space.
    /// - Throws: `TabGroupError` if the group's space cannot be resolved or is an archive.
    @discardableResult
    func convertGroupToSpace(_ group: TabGroup) throws -> Space {
        guard !group.isArchive else {
            throw TabGroupError.invalidOperation(reason: "Archive groups cannot be converted to spaces")
        }
        guard let sourceSpace = group.space else {
            throw TabGroupError.noActiveSpace
        }

        // Capture state for undo before modifying
        let conversionInfo = ConvertedGroupToSpaceInfo(
            originalGroupID: group.id,
            groupName: group.name,
            groupColorHex: group.colorString,
            groupIconName: group.iconName,
            position: group.position,
            isPinned: group.isPinned,
            isCollapsed: group.isCollapsed,
            sourceSpaceID: sourceSpace.id,
            tabInfos: sourceSpace.tabs.filter { $0.groupID == group.id }.map { tab in
                ConvertedTabInfo(
                    tabID: tab.id,
                    position: tab.position,
                    groupID: tab.groupID,
                    isPinned: tab.isPinned,
                    isReferenceTab: tab.isReferenceTab,
                )
            },
        )

        // Get tabs in the group
        let tabsInGroup = sourceSpace.tabs
            .filter { $0.groupID == group.id }
            .sorted { $0.position < $1.position }

        // Create new space with group's properties
        let newSpace = Space(
            id: UUID(),
            name: group.name,
            iconName: group.iconName ?? "folder.fill",
            color: Color.resolveStoredColor(group.colorString),
            position: state.spaces.count,
        )

        state.addSpace(newSpace)
        state.modelContext.insert(newSpace)

        // Move tabs to new space
        for (index, tab) in tabsInGroup.enumerated() {
            tab.space = newSpace
            tab.groupID = nil
            tab.group = nil
            tab.position = index
            newSpace.tabs.append(tab)
        }

        // Remove tabs from source space (relationship already updated above)
        for tab in tabsInGroup {
            if let idx = sourceSpace.tabs.firstIndex(where: { $0.id == tab.id }) {
                sourceSpace.tabs.remove(at: idx)
            }
        }

        // Delete the original group
        if let idx = sourceSpace.groups.firstIndex(where: { $0.id == group.id }) {
            sourceSpace.groups.remove(at: idx)
        }
        state.modelContext.delete(group)

        state.incrementListVersion()
        scheduleSave()

        // Register undo
        undoRedoManager.registerGroupToSpaceConversion(conversionInfo, resultSpaceID: newSpace.id)

        Logger.info(
            "Converted group '\(group.name)' to space with \(tabsInGroup.count) tabs",
            category: Logger.tabs,
        )

        return newSpace
    }

    /// Converts a space to a tab group in the target space.
    ///
    /// Creates a new group with the space's name and color, moves all tabs from the
    /// space to the group, then optionally deletes the original space.
    ///
    /// - Parameters:
    ///   - space: The space to convert to a group.
    ///   - targetSpace: The space where the new group will be created.
    ///   - deleteOriginal: Whether to delete the original space after conversion. Default true.
    /// - Returns: The newly created group.
    @discardableResult
    func convertSpaceToGroup(
        _ space: Space,
        in targetSpace: Space,
        deleteOriginal: Bool = true,
    ) throws -> TabGroup {
        guard space.id != targetSpace.id else {
            throw TabGroupError.invalidOperation(reason: "Cannot convert space to group in itself")
        }

        // Capture state for undo before modifying
        let mainTabs = space.tabs.filter { !$0.isReferenceTab }
        let referenceTabs = space.tabs.filter(\.isReferenceTab)

        let conversionInfo = ConvertedSpaceInfo(
            originalSpaceID: space.id,
            spaceName: space.name,
            spaceIconName: space.iconName,
            spaceColor: space.color,
            dataStoreMode: space.dataStoreMode,
            position: space.position,
            tabInfos: mainTabs.map { tab in
                ConvertedTabInfo(
                    tabID: tab.id,
                    position: tab.position,
                    groupID: tab.groupID,
                    isPinned: tab.isPinned,
                    isReferenceTab: false,
                )
            },
            referenceTabInfos: referenceTabs.map { tab in
                ConvertedTabInfo(
                    tabID: tab.id,
                    position: tab.position,
                    groupID: nil,
                    isPinned: false,
                    isReferenceTab: true,
                )
            },
            targetSpaceID: targetSpace.id,
        )

        // Get tabs from the space
        let tabsToMove = space.tabs.sorted { $0.position < $1.position }

        // Create new group with space's properties
        let group = TabGroup(
            space: targetSpace,
            name: space.name,
            color: space.colorHex,
            iconName: space.isEmoji ? nil : space.iconName,
            position: targetSpace.tabs.count + targetSpace.groups.count,
        )

        targetSpace.groups.append(group)
        state.modelContext.insert(group)

        // Move tabs to target space and assign to group
        let basePosition = targetSpace.tabs.count
        for (index, tab) in tabsToMove.enumerated() {
            tab.space = targetSpace
            tab.groupID = group.id
            tab.group = group
            tab.position = basePosition + index
            targetSpace.tabs.append(tab)
            group._addTab(tab)
        }

        // Clear source space's tabs (relationship already updated)
        space.tabs.removeAll()

        // Optionally delete the original space
        if deleteOriginal {
            if let idx = state.spaces.firstIndex(where: { $0.id == space.id }) {
                state.removeSpace(at: idx)
            }
            state.modelContext.delete(space)
        }

        state.incrementListVersion()
        scheduleSave()

        // Register undo
        undoRedoManager.registerSpaceToGroupConversion(conversionInfo, resultGroupID: group.id)

        Logger.info(
            "Converted space '\(space.name)' to group with \(tabsToMove.count) tabs",
            category: Logger.tabs,
        )

        return group
    }

    // MARK: - Private

    /// Schedules a debounced save operation.
    ///
    /// Delegates to `BrowserState.scheduleSave()` for centralized save management.
    private func scheduleSave() {
        state.scheduleSave()
    }
}

// MARK: - Errors

/// Errors that can occur during group operations.
enum TabGroupError: Error, LocalizedError, Equatable {
    case noActiveSpace
    case parentGroupNotFound
    case nestingTooDeep
    case alreadyNested
    case differentSpaces
    case invalidOperation(reason: String)
    
    var errorDescription: String? {
        switch self {
        case .noActiveSpace:
            "No active space"
        case .parentGroupNotFound:
            "Parent group not found"
        case .nestingTooDeep:
            "Cannot nest groups more than 2 levels deep"
        case .alreadyNested:
            "Group is already nested"
        case .differentSpaces:
            "Cannot nest groups from different spaces"
        case let .invalidOperation(reason):
            reason
        }
    }
}
