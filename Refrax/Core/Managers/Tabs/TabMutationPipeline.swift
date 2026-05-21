import Foundation

/// Coordinates tab mutations and ensures consistency invariants.
///
/// `TabMutationPipeline` wraps tab mutation operations to ensure:
/// - Index updates happen after mutations
/// - Version counters are incremented appropriately
/// - Save scheduling is unified
/// - Window state is synchronized
/// - Position normalization happens when needed
///
/// ## Why a Pipeline?
///
/// Tab operations often need to:
/// 1. Modify tab/space state
/// 2. Update the tab index
/// 3. Sync window state selections
/// 4. Normalize positions (sometimes)
/// 5. Increment version counters
/// 6. Schedule a save
///
/// Forgetting any of these steps causes bugs. The pipeline ensures
/// all invariants are maintained by collecting effects and applying
/// them consistently after the mutation.
///
/// ## Usage
///
/// ```swift
/// let pipeline = TabMutationPipeline(state: state, windowSync: sync, positioner: positioner)
///
/// pipeline.withMutation { effects in
///     // Perform mutation
///     space.tabs.remove(at: index)
///
///     // Declare effects
///     effects.didChangeList = true
///     effects.spacesToNormalize.insert(space)
///     effects.spacesToSyncActiveTab.insert(space)
/// }
/// ```
struct TabMutationPipeline {
    private let state: BrowserState
    private let windowSync: WindowStateSync
    private let positioner: TabPositioner

    init(state: BrowserState, windowSync: WindowStateSync, positioner: TabPositioner) {
        self.state = state
        self.windowSync = windowSync
        self.positioner = positioner
    }

    /// Effects declared during a mutation.
    ///
    /// Mutations declare which effects they caused, and the pipeline
    /// applies them consistently after the mutation completes.
    final class MutationEffects {
        /// Whether the tab list structure changed (add/remove/reorder).
        var didChangeList = false

        /// Whether tab content/metadata changed (title, favicon, etc.).
        var didChangeContent = false

        /// Whether to schedule a save.
        var shouldSave = true

        /// Space IDs that need position normalization.
        var spaceIDsToNormalize: Set<Space.ID> = []

        /// Space IDs that need active tab synchronization.
        var spaceIDsToSyncActiveTab: Set<Space.ID> = []

        /// Space IDs that need active reference tab synchronization.
        var spaceIDsToSyncActiveRefTab: Set<Space.ID> = []

        /// Tabs that were added and need indexing.
        var tabsToIndex: [Tab] = []

        /// Tabs that were removed and need unindexing.
        var tabsToRemoveFromIndex: [Tab] = []

        /// Context about closed tabs for smart active tab selection.
        ///
        /// When a tab is closed, we store its ID and position so the sync logic
        /// can select the best replacement (previous tab → adjacent → first).
        var closedTabContexts: [Space.ID: ClosedTabContext] = [:]

        // MARK: - Incremental Removal Tracking

        /// ID of a single item removed (for incremental layout updates).
        ///
        /// When set, LayoutManager can perform an incremental removal instead of
        /// a full rebuild. Used by single-tab close operations.
        var removedItemID: UUID?

        /// IDs of items removed in a batch operation.
        ///
        /// When set, LayoutManager can perform batch incremental removal.
        /// Used by multi-tab close operations (e.g., "Close Other Tabs").
        var batchRemovedIDs: Set<UUID>?

        /// Context about a removal operation for incremental layout updates.
        ///
        /// Provides information needed by LayoutManager to efficiently update
        /// only the affected portions of the layout hierarchy.
        var removalContext: RemovalContext?
    }

    /// Context about a removal operation for incremental layout updates.
    ///
    /// Contains the information LayoutManager needs to perform targeted updates
    /// instead of full hierarchy rebuilds when items are removed.
    struct RemovalContext {
        /// The space where the removal occurred.
        let spaceID: Space.ID

        /// Whether the removed item was pinned.
        ///
        /// Affects which collection in the layout needs updating.
        let wasPinned: Bool

        /// The group ID the item belonged to before removal, if any.
        ///
        /// Affects group hierarchy updates and descendant tracking.
        let wasInGroupID: TabGroup.ID?
    }

    /// Context about a closed tab for smart active tab selection.
    struct ClosedTabContext {
        /// The ID of the closed tab.
        let tabID: Tab.ID

        /// The index of the closed tab in mainTabs before removal.
        let mainTabIndex: Int
    }

    /// Executes a mutation with automatic invariant maintenance.
    ///
    /// The mutation closure receives a `MutationEffects` instance to declare
    /// what changed. After the closure returns, the pipeline applies all
    /// necessary updates based on the declared effects.
    ///
    /// - Parameter mutation: Closure that performs the mutation and declares effects.
    func withMutation(_ mutation: (MutationEffects) -> Void) {
        let effects = MutationEffects()
        mutation(effects)
        applyEffects(effects)
    }

    /// Executes a throwing mutation with automatic invariant maintenance.
    ///
    /// If the mutation throws, effects are not applied.
    ///
    /// - Parameter mutation: Closure that performs the mutation and declares effects.
    /// - Throws: Any error thrown by the mutation.
    func withThrowingMutation(_ mutation: (MutationEffects) throws -> Void) throws {
        let effects = MutationEffects()
        try mutation(effects)
        applyEffects(effects)
    }

    /// Applies the declared effects after a mutation.
    private func applyEffects(_ effects: MutationEffects) {
        for tab in effects.tabsToIndex {
            state.indexTab(tab)
        }

        for tab in effects.tabsToRemoveFromIndex {
            state.removeFromIndex(tab)
        }

        for spaceID in effects.spaceIDsToNormalize {
            if let space = state.space(for: spaceID) {
                positioner.normalize(space: space, force: true)
            }
        }

        for spaceID in effects.spaceIDsToSyncActiveTab {
            if let space = state.space(for: spaceID) {
                let closedContext = effects.closedTabContexts[spaceID]
                windowSync.syncInvalidActiveTabIDs(for: space, closedContext: closedContext)
            }
        }

        for spaceID in effects.spaceIDsToSyncActiveRefTab {
            if let space = state.space(for: spaceID) {
                // Pass nil for closedIndex - batch operations use last-tab fallback
                windowSync.syncInvalidActiveReferenceTabIDs(for: space, closedIndex: nil)
            }
        }

        // Try incremental layout updates before incrementing version
        var handledIncrementally = false

        if effects.didChangeList {
            // Single item removal - try incremental update
            if let removedID = effects.removedItemID,
               let context = effects.removalContext,
               let handler = state.onIncrementalRemoval {
                handledIncrementally = handler(removedID, context)
            }
            // Batch removal - try incremental batch update
            else if let batchIDs = effects.batchRemovedIDs,
                    let context = effects.removalContext,
                    let handler = state.onBatchRemoval {
                handledIncrementally = handler(batchIDs, context.spaceID)
            }

            state.incrementListVersion()

            if handledIncrementally {
                state.markIncrementallyHandled()
            }
        }

        if effects.didChangeContent {
            state.incrementContentVersion()
        }

        if effects.shouldSave {
            state.scheduleSave()
        }
    }
}

// MARK: - Convenience Extensions

extension TabMutationPipeline.MutationEffects {
    /// Marks a structural change to a space.
    ///
    /// Sets `didChangeList`, adds the space to normalize, and syncs active tabs.
    func structuralChange(in space: Space, normalize: Bool = true) {
        didChangeList = true
        if normalize {
            spaceIDsToNormalize.insert(space.id)
        }
        spaceIDsToSyncActiveTab.insert(space.id)
    }

    /// Marks that a tab was added.
    func tabAdded(_ tab: Tab, in space: Space, normalize: Bool = false) {
        tabsToIndex.append(tab)
        didChangeList = true
        if normalize {
            spaceIDsToNormalize.insert(space.id)
        }
    }

    /// Marks that a tab was removed.
    ///
    /// - Parameters:
    ///   - tab: The tab being removed.
    ///   - space: The space the tab was in.
    ///   - mainTabIndex: The index of the tab in `space.mainTabs` before removal.
    ///     Used for smart adjacent tab selection when the active tab is closed.
    ///
    /// - Note: Does not trigger normalization by default. Position gaps from removal
    ///   are acceptable; normalization happens lazily when needed.
    func tabRemoved(_ tab: Tab, from space: Space, mainTabIndex: Int) {
        tabsToRemoveFromIndex.append(tab)
        didChangeList = true
        spaceIDsToSyncActiveTab.insert(space.id)
        closedTabContexts[space.id] = TabMutationPipeline.ClosedTabContext(
            tabID: tab.id,
            mainTabIndex: mainTabIndex,
        )
    }

    /// Marks that tabs were moved to a different space.
    func tabsMoved(from sourceSpace: Space, to targetSpace: Space) {
        didChangeList = true
        spaceIDsToNormalize.insert(sourceSpace.id)
        spaceIDsToNormalize.insert(targetSpace.id)
        spaceIDsToSyncActiveTab.insert(sourceSpace.id)
    }

    /// Marks a reference tab change.
    func referenceTabChanged(in space: Space) {
        didChangeList = true
        spaceIDsToSyncActiveRefTab.insert(space.id)
    }
}
