import AppKit
import Foundation
import Observation
import SwiftData
import SwiftUI

/// Manages browser spaces (workspaces).
///
/// `SpaceManager` handles the lifecycle of spaces, including:
/// - Creating, updating, and deleting spaces
/// - Switching between spaces with lazy tab loading
/// - Persisting space metadata and state
///
/// ## Multi-Window Support
///
/// Space switching is per-window: each window tracks its own `activeSpaceID`
/// via `WindowState`. The same Space can be viewed in multiple windows
/// with different tab selections.
///
/// ## Space Loading
///
/// Tabs are loaded lazily when a space is first accessed. This allows fast
/// app launch without loading all tabs into memory upfront. When tabs are
/// loaded, they are added to `BrowserState.tabIndex` for O(1) lookup.
///
/// ## Persistence
///
/// Space data is stored directly in SwiftData via the `Space` model.
/// The actual `Space` objects are runtime containers that load tabs on demand.
@Observable
final class SpaceManager {
    // MARK: - Dependencies

    private unowned let state: BrowserState

    /// WebPage pool for cleaning up WebView sessions when deleting spaces.
    /// Set after TabManager initialization (to break circular init dependency).
    unowned var pagePool: WebPagePool!

    /// Manager for per-space WKWebsiteDataStore instances.
    let dataStoreManager = SpaceDataStoreManager()

    // MARK: - Initialization

    init(state: BrowserState) {
        self.state = state
    }
    
    // MARK: - Space CRUD
    
    /// Creates a new space with the specified properties.
    ///
    /// - Parameters:
    ///   - name: Display name for the space.
    ///   - color: Theme color for the space.
    ///   - iconName: SF Symbol name or emoji.
    ///   - description: Optional description.
    ///   - dataStoreMode: The data storage mode for the space.
    /// - Returns: The newly created Space.
    @discardableResult
    func createSpace(
        name: String,
        color: Color = .blue,
        iconName: String,
        description: String? = nil,
        dataStoreMode: DataStoreMode = .global,
    ) -> Space {
        let position = state.spaces.count
        let space = Space(
            id: UUID(),
            name: name,
            iconName: iconName,
            color: color,
            position: position,
            dataStoreMode: dataStoreMode,
        )
        space.spaceDescription = description

        state.addSpace(space)
        state.modelContext.insert(space)
        // Note: addSpace() already increments list version
        scheduleSave()

        Logger.info(
            "Space created: \(name) (dataStoreMode: \(dataStoreMode))",
            category: Logger.tabs,
        )
        return space
    }
    
    /// Updates an existing space's properties.
    ///
    /// Only non-nil parameters are applied.
    func updateSpace(
        _ space: Space,
        name: String? = nil,
        iconName: String? = nil,
        description: String? = nil,
        color: Color? = nil,
    ) {
        if let name { space.name = name }
        if let iconName { space.iconName = iconName }
        if let description { space.spaceDescription = description }
        if let color { space.color = color }

        state.incrementContentVersion()
        scheduleSave()

        Logger.info("Space updated: \(space.name)", category: Logger.tabs)
    }
    
    /// Duplicates a space including all its tabs and groups.
    ///
    /// Creates a new space with the same properties (name + " Copy", icon, color,
    /// description) and duplicates all tabs and groups, preserving tab-group relationships.
    ///
    /// - Parameter space: Space to duplicate.
    /// - Returns: The newly created duplicate Space.
    @discardableResult
    func duplicateSpace(_ space: Space) -> Space {
        // Create new space with same properties
        let duplicatedSpace = Space(
            id: UUID(),
            name: space.name + " Copy",
            iconName: space.iconName,
            color: space.color,
            position: state.spaces.count,
            dataStoreMode: space.dataStoreMode,
        )
        duplicatedSpace.spaceDescription = space.spaceDescription

        state.addSpace(duplicatedSpace)
        state.modelContext.insert(duplicatedSpace)

        // Map original group IDs to duplicated groups for tab-group relationship preservation
        var groupIDMap: [UUID: TabGroup] = [:]

        // Duplicate groups first (sorted by position to maintain order)
        for originalGroup in space.groups.sorted(by: { $0.position < $1.position }) {
            let duplicatedGroup = TabGroup(
                space: duplicatedSpace,
                name: originalGroup.name,
                color: originalGroup.colorString,
                iconName: originalGroup.iconName,
                parentGroupID: nil, // Will be set in second pass for nested groups
                position: originalGroup.position,
                isPinned: originalGroup.isPinned,
            )
            duplicatedGroup.isCollapsed = originalGroup.isCollapsed

            duplicatedSpace.groups.append(duplicatedGroup)
            state.modelContext.insert(duplicatedGroup)
            groupIDMap[originalGroup.id] = duplicatedGroup
        }

        // Second pass: fix nested group relationships
        for originalGroup in space.groups {
            if let parentID = originalGroup.parentGroupID,
               let duplicatedGroup = groupIDMap[originalGroup.id],
               let duplicatedParent = groupIDMap[parentID] {
                duplicatedGroup.parentGroupID = duplicatedParent.id
            }
        }

        // Duplicate tabs (sorted by position to maintain order)
        for originalTab in space.tabs.sorted(by: { $0.position < $1.position }) {
            let duplicatedTab = Tab(
                space: duplicatedSpace,
                url: originalTab.activePage.url,
                title: originalTab.activePage.title,
                status: originalTab.status,
                groupID: nil, // Will be set after creation
                position: originalTab.position,
            )
            duplicatedTab.customName = originalTab.customName
            duplicatedTab.activePage.faviconData = originalTab.activePage.faviconData
            duplicatedTab.activePage.largeFaviconData = originalTab.activePage.largeFaviconData
            duplicatedTab.isReferenceTab = originalTab.isReferenceTab
            duplicatedTab.isUnread = true

            // Preserve group relationship
            if let originalGroupID = originalTab.groupID,
               let duplicatedGroup = groupIDMap[originalGroupID] {
                duplicatedTab.groupID = duplicatedGroup.id
                duplicatedTab.group = duplicatedGroup
                duplicatedGroup._addTab(duplicatedTab)
            }

            duplicatedSpace.tabs.append(duplicatedTab)
            state.indexTab(duplicatedTab)
            state.modelContext.insert(duplicatedTab)
        }

        scheduleSave()

        Logger.info(
            "Space duplicated: '\(space.name)' -> '\(duplicatedSpace.name)' (\(duplicatedSpace.tabs.count) tabs, \(duplicatedSpace.groups.count) groups)",
            category: Logger.tabs,
        )
        return duplicatedSpace
    }

    /// Deletes a space and handles its tabs.
    ///
    /// - Parameters:
    ///   - space: Space to delete.
    ///   - closeTabs: If true, deletes all tabs. If false, moves them to another space
    ///     (or deletes them if no other space exists).
    ///   - windowState: Window to switch to another space if this was active.
    func deleteSpace(
        _ space: Space,
        closeTabs: Bool = true,
        windowState: WindowState? = nil,
    ) {
        guard let index = state.spaces.firstIndex(where: { $0.id == space.id }) else {
            return
        }

        // Capture these before removing the space
        let spaceID = space.id
        let dataStoreMode = space.dataStoreMode

        if closeTabs {
            // Tabs will be cascade-deleted with the space, but we need to clean up WebPages
            for tab in space.tabs {
                pagePool.removePages(for: tab)
            }
        } else {
            // Move tabs to another space to avoid orphaning
            let targetSpace = state.spaces.first { $0.id != spaceID }
            if let targetSpace {
                let tabsToMove = Array(space.tabs)
                for tab in tabsToMove {
                    tab.space = targetSpace
                    tab.position = targetSpace.tabs.count
                }
                Logger.info("Moved \(tabsToMove.count) tabs to space '\(targetSpace.name)'", category: Logger.tabs)
            } else {
                // No other space exists - tabs will be cascade-deleted
                for tab in space.tabs {
                    pagePool.removePages(for: tab)
                }
                Logger.warning("No target space available - tabs will be cascade-deleted", category: Logger.tabs)
            }
        }

        state.removeSpace(at: index)
        state.modelContext.delete(space)
        scheduleSave()

        // Switch to another space if we deleted this window's active space
        if let windowState, windowState.activeSpaceID == spaceID,
           let firstSpace = state.spaces.first {
            // Use sync version since we're switching to an unlocked space
            switchToSpaceSync(firstSpace, for: windowState)
        }

        Logger.info("Space deleted: \(space.name)", category: Logger.tabs)

        // Clean up data store after all WebViews are released
        switch dataStoreMode {
        case .global:
            break // Nothing to clean up
        case .separate:
            Task {
                await dataStoreManager.removeDataStore(forSpaceID: spaceID)
            }
        case .private:
            dataStoreManager.removePrivateDataStore(forSpaceID: spaceID)
        }
    }
    
    // MARK: - Space Switching

    /// Switches a window to a different space.
    ///
    /// Lazily loads the target space's tabs if not already loaded.
    /// Previous space remains in memory but sessions may be evicted.
    ///
    /// For locked spaces, this method prompts for Touch ID/password authentication.
    /// If authentication fails or is cancelled, the switch is aborted.
    ///
    /// - Parameters:
    ///   - space: Space to switch to.
    ///   - windowState: Window state to update.
    ///   - restoreActiveTab: Whether to restore the last active tab. Set to false for
    ///     new windows that should start without a tab selected.
    func switchToSpace(_ space: Space, for windowState: WindowState, restoreActiveTab: Bool = true) async {
        if state.spaceLockManager.requiresAuth(for: space) {
            let result = await state.spaceLockManager.authenticate(for: space)

            switch result {
            case .success:
                break
            case .failed:
                Logger.info("Space switch blocked: authentication failed", category: Logger.tabs)
                return
            case .cancelled:
                Logger.info("Space switch blocked: authentication cancelled", category: Logger.tabs)
                return
            case let .unavailable(reason):
                Logger.warning("Space switch blocked: \(reason)", category: Logger.tabs)
                return
            }
        }

        // Exit layout mode when switching spaces
        if windowState.isInLayoutMode {
            windowState.exitLayoutMode()
        }

        // Persist pending model changes before switching
        scheduleSave()

        // Load tabs if needed
        if !space.isLoaded {
            loadSpaceTabs(for: space)
        }

        // Update window's active space
        windowState.setActiveSpace(space, restoreActiveTab: restoreActiveTab)

        // Record activity for auto-lock timing
        state.spaceLockManager.recordActivity()

        state.incrementListVersion()
    }

    /// Switches a window to a different space (synchronous, non-locked spaces only).
    ///
    /// Use this for internal space switches where authentication is not expected
    /// or has already been verified.
    ///
    /// - Parameters:
    ///   - space: Space to switch to (must not be locked or must already be unlocked).
    ///   - windowState: Window state to update.
    ///   - restoreActiveTab: Whether to restore the last active tab.
    func switchToSpaceSync(_ space: Space, for windowState: WindowState, restoreActiveTab: Bool = true) {
        // Exit layout mode when switching spaces
        if windowState.isInLayoutMode {
            windowState.exitLayoutMode()
        }

        // Persist pending model changes before switching
        scheduleSave()

        // Load tabs if needed
        if !space.isLoaded {
            loadSpaceTabs(for: space)
        }

        // Update window's active space
        windowState.setActiveSpace(space, restoreActiveTab: restoreActiveTab)

        state.incrementListVersion()
    }

    /// Switches a window to a space by ID.
    func switchToSpace(id: UUID, for windowState: WindowState, restoreActiveTab: Bool = true) async {
        guard let space = state.space(for: id) else {
            Logger.error("Cannot switch to space: not found", category: Logger.tabs)
            return
        }
        await switchToSpace(space, for: windowState, restoreActiveTab: restoreActiveTab)
    }

    /// Switches to a space by ID (synchronous, for non-locked spaces).
    func switchToSpaceSync(id: UUID, for windowState: WindowState, restoreActiveTab: Bool = true) {
        guard let space = state.space(for: id) else {
            Logger.error("Cannot switch to space: not found", category: Logger.tabs)
            return
        }
        switchToSpaceSync(space, for: windowState, restoreActiveTab: restoreActiveTab)
    }
    
    /// Ensures a space is loaded (for use by other managers).
    func ensureLoaded(_ space: Space) {
        if !space.isLoaded {
            loadSpaceTabs(for: space)
        }
    }
    
    // MARK: - Default Space

    /// Default space configuration.
    enum DefaultSpaceConfig {
        static let name = "Space 1"
        static let iconName = "moon.stars.fill"
        static let color = Color.blue
    }

    /// Creates a default space object without persistence.
    ///
    /// Use this for temporary spaces (e.g., first-frame rendering before DB load)
    /// or as the base for persisted default spaces.
    ///
    /// - Parameter addToState: Whether to add the space to BrowserState. Default true.
    /// - Returns: A new default space.
    func makeDefaultSpace(addToState: Bool = true) -> Space {
        let space = Space(
            id: UUID(),
            name: DefaultSpaceConfig.name,
            iconName: DefaultSpaceConfig.iconName,
            color: DefaultSpaceConfig.color,
            position: 0,
        )
        if addToState {
            state.addSpace(space)
        }
        return space
    }

    // MARK: - Restoration

    /// Restores spaces from SwiftData on app launch.
    ///
    /// Loads spaces directly from SwiftData. Does NOT activate any space - that's
    /// the caller's responsibility after creating/restoring windows.
    ///
    /// - Returns: The default space to activate (first space or newly created).
    @discardableResult
    func restoreFromPersistence() -> Space {
        let descriptor = FetchDescriptor<Space>(
            sortBy: [SortDescriptor(\.position)],
        )

        do {
            let spaces = try state.modelContext.fetch(descriptor)

            if spaces.isEmpty {
                // First launch - create and persist default space
                let defaultSpace = createDefaultSpace()
                Logger.info("Created default space", category: Logger.tabs)
                return defaultSpace
            } else if let firstSpace = spaces.first {
                state.setSpaces(spaces)
                Logger.info("Restored \(state.spaces.count) spaces", category: Logger.tabs)
                return firstSpace
            } else {
                // spaces was non-empty but first is nil (should be impossible)
                let defaultSpace = createDefaultSpace()
                Logger.warning("Spaces array inconsistent, created default", category: Logger.tabs)
                return defaultSpace
            }
        } catch {
            Logger.error("Failed to restore spaces: \(error)", category: Logger.tabs)
            return createDefaultSpace()
        }
    }

    /// Creates and persists a default space.
    private func createDefaultSpace() -> Space {
        createSpace(
            name: DefaultSpaceConfig.name,
            color: DefaultSpaceConfig.color,
            iconName: DefaultSpaceConfig.iconName,
        )
    }

    // MARK: - Private
    
    /// Loads tabs for a space from SwiftData.
    ///
    /// With the Space @Model, tabs are linked via the `space` relationship.
    /// This method ensures tabs are fetched and indexed for O(1) lookup.
    private func loadSpaceTabs(for space: Space) {
        let spaceID = space.id

        // Fetch tabs and groups belonging to this space
        let tabDescriptor = FetchDescriptor<Tab>(
            predicate: #Predicate { $0.space?.id == spaceID },
            sortBy: [SortDescriptor(\.position)],
        )

        let groupDescriptor = FetchDescriptor<TabGroup>(
            predicate: #Predicate { $0.space?.id == spaceID },
            sortBy: [SortDescriptor(\.position)],
        )

        do {
            // Fetch to ensure tabs/groups are loaded into context
            _ = try state.modelContext.fetch(tabDescriptor)
            _ = try state.modelContext.fetch(groupDescriptor)

            space.isLoaded = true

            // Index all tabs for O(1) lookup
            for tab in space.tabs {
                state.indexTab(tab)
            }

            // Note: active tab is tracked per-window in WindowState
            // Note: active reference tab is per-window only
            // WindowState.setActiveSpace() handles restoration

            Logger.info("Loaded \(space.mainTabs.count) tabs, \(space.referenceTabs.count) ref tabs for: \(space.name)", category: Logger.tabs)
        } catch {
            Logger.error("Failed to load tabs for space: \(error)", category: Logger.tabs)
        }
    }

    /// Schedules a debounced save operation.
    ///
    /// Delegates to `BrowserState.scheduleSave()` for centralized save management.
    private func scheduleSave() {
        state.scheduleSave()
    }
    
    // MARK: - Queries
    
    /// Number of spaces.
    var spaceCount: Int {
        state.spaces.count
    }
    
    /// All spaces.
    var spaces: [Space] {
        state.spaces
    }
}
