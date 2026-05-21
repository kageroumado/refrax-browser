import AppKit
import Foundation
import Observation
import SwiftData
import SwiftUI
import WebKit

/// Coordinates all tab operations and browsing sessions across the application.
///
/// `TabManager` is the single entry point for all tab-related operations in Refrax.
/// It owns specialized sub-managers and provides a unified API for:
///
/// - Tab lifecycle (create, close, duplicate, restore)
/// - Tab activation and navigation
/// - Tab organization (pin, move, reorder)
/// - Tab groups (create, nest, collapse)
/// - Reference pane management
/// - Tab/page transfers between areas
/// - Multi-page layouts
/// - Cross-collection operations (tabs ↔ favorites)
/// - Batch operations with unified undo
///
/// ## Multi-Window Architecture
///
/// TabManager supports multiple windows via WindowManager. Each window has independent
/// navigation state stored in its WindowState:
///
/// ```
/// ┌─────────────────────────────────────────────────────────┐
/// │ TabManager (app-global, singleton)                      │
/// │   state.spaces: [Space]     ← shared across windows     │
/// │   state.tabIndex            ← O(1) tab lookup           │
/// │   pagePool               ← shared session cache      │
/// │   windowManager             ← access to all windows     │
/// ├─────────────────────────────────────────────────────────┤
/// │ Window A (WindowState)     │ Window B (WindowState)     │
/// │   activeSpaceID: X         │   activeSpaceID: Y         │
/// │   activeTabID: 1           │   activeTabID: 3           │
/// └─────────────────────────────────────────────────────────┘
/// ```
///
/// ## Window Access
///
/// Operations that affect window state access windows via `windowManager`:
/// ```swift
/// // Get active window
/// let windowState = windowManager.activeWindowController?.windowState
///
/// // Iterate all windows showing a space
/// for controller in windowManager.windowControllers {
///     if controller.windowState.activeSpaceID == space.id { ... }
/// }
/// ```
///
/// ## Sub-Manager Access
///
/// Sub-managers are injected into the SwiftUI environment for direct access in views:
/// ```swift
/// @Environment(WebPagePool.self) var pagePool
/// @Environment(SpaceManager.self) var spaceManager
/// @Environment(TabGroupManager.self) var groupManager
/// @Environment(ReferencePaneManager.self) var referencePaneManager
///
/// // Then use directly
/// pagePool.clearInactivePages()
/// spaceManager.createSpace(name: "Work")
/// try groupManager.createGroup(in: space, name: "Research")
/// ```
///
/// In non-view code with a TabManager reference, access via properties:
/// ```swift
/// tabManager.pagePool.existingPage(for: tabPage)
/// ```
///
/// ## Mutation Tracking
///
/// TabManager increments version counters in BrowserState after mutations:
/// - `tabListVersion`: Structural changes (add/remove/reorder)
/// - `tabContentVersion`: Metadata changes (title, favicon, unread)
///
/// Views should observe these instead of computing signatures:
/// ```swift
/// .onChange(of: tabManager.state.tabListVersion) { rebuildLayout() }
/// ```
@Observable
final class TabManager {
    // MARK: - Shared State

    /// Shared state container accessed by all managers.
    let state: BrowserState

    // MARK: - External References

    /// Window manager for accessing all browser windows.
    ///
    /// Set after initialization to avoid circular dependency.
    /// Used to iterate windows when syncing state after tab operations.
    unowned var windowManager: WindowManager!

    /// Bookmarks manager for cross-collection operations.
    ///
    /// Set after initialization. Required for favorite ↔ tab conversions.
    unowned var bookmarksManager: BookmarksManager!

    /// Undo/redo manager for browser-level undo operations.
    ///
    /// Set after initialization. Handles tab close/restore undo actions.
    unowned var undoRedoManager: UndoRedoManager!

    /// Archive manager for tab archival operations.
    ///
    /// Set after initialization. Routes tab closes through archive when enabled.
    unowned var archiveManager: TabArchiveManager!

    /// Auto-archive manager for threshold tracking.
    ///
    /// Set after initialization. Used to notify when tabs are activated
    /// (removing them from the archive threshold).
    unowned var autoArchiveManager: TabAutoArchiveManager!

    /// When true, runs async operations synchronously. Used by tests to avoid
    /// race conditions during test teardown.
    var _runSynchronously = false

    // MARK: - Sub-Managers

    /// Manages WebPage lifecycle.
    ///
    /// Injected at initialization. Accessible via `@Environment(WebPagePool.self)`.
    unowned let pagePool: WebPagePool

    /// Manages space CRUD and switching.
    ///
    /// Injected at initialization. Accessible via `@Environment(SpaceManager.self)`.
    unowned let spaceManager: SpaceManager

    /// Manages tab group operations.
    ///
    /// Injected at initialization. Accessible via `@Environment(TabGroupManager.self)`.
    unowned let groupManager: TabGroupManager

    /// Manages reference pane operations.
    ///
    /// Injected at initialization. Accessible via `@Environment(ReferencePaneManager.self)`.
    unowned let referencePaneManager: ReferencePaneManager

    /// Evaluates URL routing rules for navigation decisions.
    ///
    /// Lazily initialized on first access.
    var ruleEngine: RuleEngine {
        if let cached = _ruleEngine {
            return cached
        }

        let engine = RuleEngine(modelContext: state.modelContext)
        _ruleEngine = engine
        return engine
    }
    private var _ruleEngine: RuleEngine?

    /// Handles position arithmetic and normalization.
    let positioner = TabPositioner()

    // MARK: - UI State

    /// The ID of the tab or group currently in rename mode.
    ///
    /// Used to coordinate rename state across all tab and group views.
    /// When set, the corresponding view shows a text field; all others exit edit mode.
    /// Set to nil when rename is committed or cancelled.
    var renamingItemID: UUID?

    /// ID of the archived tab currently showing its restore confirmation popover.
    /// Set when clicking an archived tab; cleared when popover is dismissed.
    var showingRestorePopoverForTabID: UUID?

    /// Window state synchronization helper.
    ///
    /// Creates a new instance on each access. This is intentional as `WindowStateSync`
    /// is a lightweight struct that just holds a reference to `windowManager`.
    var windowSync: WindowStateSync {
        var sync = WindowStateSync(windowManager: windowManager)
        #if REFRAX_TESTS
            sync.testActiveWindowState = testActiveWindowState
        #endif
        return sync
    }

    /// Mutation pipeline for consistent invariant maintenance.
    ///
    /// Creates a new instance on each access. This is intentional as `TabMutationPipeline`
    /// is a lightweight struct that coordinates state updates without holding mutable state.
    var mutationPipeline: TabMutationPipeline {
        TabMutationPipeline(state: state, windowSync: windowSync, positioner: positioner)
    }

    // MARK: - Constants

    /// Maximum number of tabs allowed in the reference pane.
    static let maxReferenceTabs = 4

    /// Maximum length for custom tab names.
    static let maxCustomNameLength = 20

    // MARK: - Close Confirmation

    /// State for the close confirmation dialog.
    var pendingCloseConfirmation: CloseConfirmation?

    /// Information about a pending tab close that requires user confirmation.
    struct CloseConfirmation: Identifiable {
        let id = UUID()

        /// Tabs that require confirmation before closing.
        let tabs: [Tab]

        /// Details about why each tab requires confirmation.
        let reasons: [TabCloseReason]

        /// All tabs to close if confirmed (includes tabs without warnings).
        let allTabsToClose: [Tab]

        /// Whether to bypass archive and permanently delete tabs.
        let bypassArchive: Bool

        /// Whether this is a batch close operation.
        var isBatch: Bool {
            allTabsToClose.count > 1
        }

        /// Title for the confirmation dialog.
        var title: String {
            isBatch ? "Close \(allTabsToClose.count) Tabs?" : "Close Tab?"
        }

        init(
            tabs: [Tab],
            reasons: [TabCloseReason],
            allTabsToClose: [Tab],
            bypassArchive: Bool = false,
        ) {
            self.tabs = tabs
            self.reasons = reasons
            self.allTabsToClose = allTabsToClose
            self.bypassArchive = bypassArchive
        }
    }

    /// Reason why a tab requires close confirmation.
    struct TabCloseReason: Identifiable {
        let id = UUID()
        let tab: Tab
        let reasons: [Reason]

        enum Reason: Equatable {
            case playingMedia
            case usingMicrophone
            case usingCamera

            var description: String {
                switch self {
                case .playingMedia: "is playing media"
                case .usingMicrophone: "is using your microphone"
                case .usingCamera: "is using your camera"
                }
            }

            var icon: String {
                switch self {
                case .playingMedia: "speaker.wave.2.fill"
                case .usingMicrophone: "mic.fill"
                case .usingCamera: "video.fill"
                }
            }
        }
    }

    // MARK: - SSL Bypass

    /// Approves an SSL certificate bypass for the specified URL.
    ///
    /// This queues a one-time bypass that will be validated by the navigation
    /// decider when the URL is loaded. The bypass is URL-specific and will be
    /// cleared after use to prevent unintended bypasses on redirects.
    ///
    /// This method is async to ensure the bypass is registered before navigation
    /// proceeds, preventing race conditions between bypass approval and certificate
    /// challenge handling.
    ///
    /// - Parameter url: The HTTPS URL for which to approve the bypass.
    func approveSSLBypass(for url: URL) async {
        guard let tabPage = activeWindowState?.activePage else {
            Logger.warning("Cannot approve SSL bypass: no active tab page", category: Logger.navigation)
            return
        }

        await pagePool.approveSSLBypass(for: url, tabPage: tabPage)
    }

    // MARK: - Computed Properties

    /// Number of tabs in the active space of the active window.
    var tabCount: Int {
        activeWindowState?.activeSpace?.tabCount ?? 0
    }

    /// Whether there are any tabs in the active space.
    var hasTabs: Bool {
        tabCount > 0
    }

    /// Whether multiple spaces exist.
    var hasMultipleSpaces: Bool {
        spaceManager.spaceCount > 1
    }

    // MARK: - Internal Helpers

    #if REFRAX_TESTS
        /// Test-only override for `activeWindowState` when no actual window exists.
        /// Set this in tests after creating a WindowState to enable navigation tests.
        var testActiveWindowState: WindowState?
    #endif

    /// Gets the WindowState for the active (key or main) window.
    var activeWindowState: WindowState? {
        #if REFRAX_TESTS
            if let testState = testActiveWindowState {
                return testState
            }
        #endif
        return windowManager.activeWindowController?.windowState
    }

    // MARK: - Initialization

    /// Creates a TabManager with all dependencies.
    ///
    /// All sub-managers (pagePool, spaceManager, groupManager, referencePaneManager)
    /// are created externally and passed in. This enables proper dependency injection
    /// and allows them to be accessed directly via `@Environment`.
    ///
    /// - Important: Set `windowManager` and `bookmarksManager` after init.
    init(
        state: BrowserState,
        pagePool: WebPagePool,
        spaceManager: SpaceManager,
        groupManager: TabGroupManager,
        referencePaneManager: ReferencePaneManager,
    ) {
        self.state = state
        self.pagePool = pagePool
        self.spaceManager = spaceManager
        self.groupManager = groupManager
        self.referencePaneManager = referencePaneManager

        Logger.info("TabManager initialized", category: Logger.tabs)
    }
}

// MARK: - Internal Helpers

extension TabManager {
    /// Returns the insertion position and array index for a new tab.
    ///
    /// - Parameters:
    ///   - space: The space to insert into.
    ///   - isPinned: Whether the tab will be pinned.
    ///   - groupID: Optional group to insert into.
    ///   - strategy: The insertion strategy to use. Defaults to `.prepend`.
    ///   - activeTabID: The active tab ID (used for `.afterActive` strategy).
    /// - Returns: A tuple containing the hierarchical position value and the array index.
    func insertionPosition(
        in space: Space,
        isPinned: Bool,
        groupID: UUID? = nil,
        strategy: TabPositioner.InsertionStrategy = .prepend,
        activeTabID: UUID? = nil,
    ) -> (position: Int, index: Int) {
        positioner.insertionPosition(
            for: space,
            isPinned: isPinned,
            groupID: groupID,
            strategy: strategy,
            activeTabID: activeTabID,
        )
    }

    func closeTabsInBatch(_ tabs: [Tab], undoActionName: String, bypassArchive: Bool = false) {
        guard !tabs.isEmpty else { return }

        // Separate tabs that should be archived vs permanently closed
        var tabsToArchive: [Tab] = []
        var tabsToClose: [Tab] = []

        for tab in tabs {
            if state.settings.archiveEnabled, !bypassArchive, !tab.isArchived {
                tabsToArchive.append(tab)
            } else {
                tabsToClose.append(tab)
            }
        }

        // Archive applicable tabs
        if !tabsToArchive.isEmpty {
            archiveManager.archiveBatch(tabsToArchive)
        }

        // Permanently close remaining tabs
        guard !tabsToClose.isEmpty else { return }

        // Notify extensions before closing each tab
        for tab in tabsToClose {
            state.extensionManager?.dispatchTabClosed(tab, windowClosing: false)
        }

        // Capture page IDs before closing, defer orphan cleanup
        let closingPageIDs = Set(tabsToClose.flatMap { $0.pages.map(\.id) })
        if !closingPageIDs.isEmpty {
            DispatchQueue.main.async {
                self.orphanPopupChildrenDeferred(closingPageIDs: closingPageIDs)
            }
        }

        var closedInfos: [ClosedTabInfo] = []

        mutationPipeline.withMutation { effects in
            // Build per-space group indexes for O(1) lookups
            var groupIndexBySpace: [Space.ID: [UUID: TabGroup]] = [:]

            // Track removed IDs by space for incremental update
            var removedIDsBySpace: [Space.ID: Set<UUID>] = [:]

            for tab in tabsToClose {
                guard let space = tab.space,
                      let index = space.tabs.firstIndex(of: tab) else {
                    continue
                }

                let closedInfo = ClosedTabInfo(tab: tab)
                closedInfos.append(closedInfo)

                // Track for incremental update
                removedIDsBySpace[space.id, default: []].insert(tab.id)

                pagePool.removePages(for: tab)

                if let groupID = tab.groupID {
                    // Lazily build group index for this space
                    if groupIndexBySpace[space.id] == nil {
                        groupIndexBySpace[space.id] = Dictionary(
                            uniqueKeysWithValues: space.groups.map { ($0.id, $0) },
                        )
                    }
                    if let group = groupIndexBySpace[space.id]?[groupID] {
                        group._removeTab(tab)
                    }
                }

                space.tabs.remove(at: index)
                state.modelContext.delete(tab)

                // For batch closes, pass mainTabIndex 0 since we don't have meaningful
                // adjacent selection - the sync will use previous tab or first fallback
                effects.tabsToRemoveFromIndex.append(tab)
                effects.didChangeList = true
                effects.spaceIDsToSyncActiveTab.insert(space.id)
            }

            // Populate incremental removal tracking
            // For single-space batch (common case), enable incremental update
            if removedIDsBySpace.count == 1,
               let (spaceID, removedIDs) = removedIDsBySpace.first {
                effects.batchRemovedIDs = removedIDs
                effects.removalContext = TabMutationPipeline.RemovalContext(
                    spaceID: spaceID,
                    wasPinned: false, // Mixed in batch, but doesn't affect removal
                    wasInGroupID: nil,
                )
            }
        }

        // Register batch undo with UndoRedoManager
        if !closedInfos.isEmpty {
            undoRedoManager.registerCloseTabsBatch(closedInfos, actionName: undoActionName)
        }
    }

    func closeTabsWithBeforeUnload(_ tabs: [Tab], bypassArchive: Bool = false) {
        guard !tabs.isEmpty else { return }

        var closedTabs: [Tab] = []

        for tab in tabs {
            var canClose = true
            for page in tab.pages {
                guard let session = pagePool.existingPage(for: page) else {
                    continue
                }
                if !session.tryClose() {
                    canClose = false
                    break
                }
            }

            if canClose {
                closedTabs.append(tab)
            }
        }

        if closedTabs.count == 1 {
            closeTab(closedTabs[0], bypassArchive: bypassArchive)
        } else if closedTabs.count > 1 {
            closeTabs(closedTabs, bypassArchive: bypassArchive)
        }
    }

    func closeTabWithoutRemovingPages(_ tab: Tab) {
        guard let space = tab.space,
              let index = space.tabs.firstIndex(of: tab) else {
            return
        }

        // Capture state before removal for incremental tracking
        let wasPinned = tab.isPinned
        let wasInGroupID = tab.groupID

        // Get index in mainTabs for proper adjacency fallback
        let mainTabIndex = space.mainTabs.firstIndex(of: tab) ?? 0

        mutationPipeline.withMutation { effects in
            if let groupID = tab.groupID,
               let group = space.groups.first(where: { $0.id == groupID }) {
                group._removeTab(tab)
            }

            space.tabs.remove(at: index)
            state.modelContext.delete(tab)
            effects.tabRemoved(tab, from: space, mainTabIndex: mainTabIndex)

            // Populate incremental removal tracking for LayoutManager
            effects.removedItemID = tab.id
            effects.removalContext = TabMutationPipeline.RemovalContext(
                spaceID: space.id,
                wasPinned: wasPinned,
                wasInGroupID: wasInGroupID,
            )
        }
    }

    func nextAvailablePosition(in tab: Tab) -> PanePosition {
        let used: Set<PanePosition>
        if let config = tab.layoutConfiguration {
            used = Set(config.panePositions.values)
        } else if tab.pages.count == 1 {
            return .topRight
        } else {
            used = Set(tab.pages.compactMap(\.position))
        }

        let order: [PanePosition] = [.topLeft, .topRight, .bottomLeft, .bottomRight]
        return order.first { !used.contains($0) } ?? .topRight
    }

    func setupLayoutIfNeeded(for tab: Tab, newPage: TabPage, position: PanePosition) {
        guard tab.pages.count == 2 else { return }

        guard let firstPage = tab.pages.first(where: { $0.id != newPage.id }),
              firstPage.position == nil || firstPage.position == .single else {
            return
        }

        let firstPosition: PanePosition = position == .topLeft ? .topRight : .topLeft
        firstPage.position = firstPosition

        var config = tab.layoutConfiguration ?? LayoutConfiguration(panePositions: [:])
        config.panePositions[firstPage.id] = firstPosition
        config.panePositions[newPage.id] = position
        tab.layoutConfiguration = config
    }

    func collectTabsRecursively(from groupID: UUID, in space: Space, into tabs: inout [Tab]) {
        let groupTabs = space.tabs.filter { $0.groupID == groupID }
        tabs.append(contentsOf: groupTabs)

        let nestedGroups = space.groups.filter { $0.parentGroupID == groupID }
        for nested in nestedGroups {
            collectTabsRecursively(from: nested.id, in: space, into: &tabs)
        }
    }

    func updatePinStateForCollection(_ tab: Tab, collection: SidebarCollection) {
        if collection == .pinned, !tab.isPinned {
            // Capture origin URL for navigation containment
            tab.originURL = tab.activePage.url
            tab.isPinned = true
        } else if collection == .normal, tab.isPinned {
            // Clear origin URL when unpinning
            tab.originURL = nil
            tab.isPinned = false
        }
    }

    func updateGroupMembership(for tab: Tab, newGroupID: UUID?) {
        guard newGroupID != tab.groupID else { return }

        if tab.groupID != nil {
            groupManager.removeTabFromGroup(tab, skipReordering: true)
        }

        if let newGroupID,
           let space = tab.space,
           let newGroup = space.groups.first(where: { $0.id == newGroupID }) {
            groupManager.moveTabToGroup(tab, group: newGroup, skipReordering: true)
        }
    }

    func updateGroupPinState(_ group: TabGroup, for collection: SidebarCollection) {
        if collection == .pinned, !group.isPinned {
            setGroupPinStateRecursively(group, isPinned: true)
        } else if collection == .normal, group.isPinned {
            setGroupPinStateRecursively(group, isPinned: false)
        }
    }

    func findEffectiveTargetIndex(
        for group: TabGroup,
        localTarget: Int,
        items: [TabListItem],
        layoutManager: Sidebar.LayoutManager,
    ) -> Int {
        var effectiveIndex = localTarget
        let descendants = layoutManager.getAllDescendantIDs(of: group.id)

        while effectiveIndex < items.count,
              descendants.contains(items[effectiveIndex].id) {
            effectiveIndex += 1
        }

        return min(effectiveIndex, items.count - 1)
    }

    func calculateNewPosition(
        for itemID: UUID,
        targetItem: TabListItem,
        targetMetadata: Sidebar.LayoutManager.ItemMetadata,
        items: [TabListItem],
        layoutManager: Sidebar.LayoutManager,
        movingDown: Bool,
    ) -> Int {
        let siblings = items.compactMap { item -> (id: UUID, position: Int)? in
            guard item.id != itemID,
                  let metadata = layoutManager.metadata[item.id],
                  metadata.parentGroupID == targetMetadata.parentGroupID,
                  metadata.nestingLevel == targetMetadata.nestingLevel else {
                return nil
            }
            return (item.id, item.position)
        }.sorted { $0.position < $1.position }

        guard let targetSiblingIndex = siblings.firstIndex(where: { $0.id == targetItem.id }) else {
            return targetItem.position
        }

        let multiplier = multiplier(forLevel: targetMetadata.nestingLevel)

        if movingDown {
            if targetSiblingIndex >= siblings.count - 1 {
                return siblings[targetSiblingIndex].position + multiplier
            } else {
                let targetPos = siblings[targetSiblingIndex].position
                let nextPos = siblings[targetSiblingIndex + 1].position
                return nextPos - targetPos > 1 ? (targetPos + nextPos) / 2 : targetPos + 1
            }
        } else {
            if targetSiblingIndex == 0 {
                return max(1, siblings[0].position - multiplier)
            } else {
                let prevPos = siblings[targetSiblingIndex - 1].position
                let targetPos = siblings[targetSiblingIndex].position
                return targetPos - prevPos > 1 ? (prevPos + targetPos) / 2 : targetPos - 1
            }
        }
    }

    func multiplier(forLevel level: Int) -> Int {
        positioner.multiplier(forLevel: level)
    }

    /// Recursively sets the pinned state for a group and all its contents.
    ///
    /// Updates the group's `isPinned` state along with all tabs directly in the group
    /// and all nested groups (and their tabs) recursively.
    ///
    /// - Parameters:
    ///   - group: The group to update.
    ///   - isPinned: The new pinned state.
    func setGroupPinStateRecursively(_ group: TabGroup, isPinned: Bool) {
        guard let space = group.space else { return }

        group.isPinned = isPinned

        for tab in space.tabs where tab.groupID == group.id {
            tab.isPinned = isPinned
        }

        for nestedGroup in space.groups where nestedGroup.parentGroupID == group.id {
            setGroupPinStateRecursively(nestedGroup, isPinned: isPinned)
        }
    }

    // MARK: - Popup Relationship Management

    /// Deferred cleanup of popup opener references.
    ///
    /// This iterates all spaces and tabs to clear `openerTabPageID` references
    /// to any of the closing page IDs. Deferring this work via Task allows
    /// the immediate tab close operation to complete quickly.
    ///
    /// - Parameter closingPageIDs: The IDs of pages being closed.
    func orphanPopupChildrenDeferred(closingPageIDs: Set<TabPage.ID>) {
        var orphanedCount = 0

        for space in state.spaces {
            for childTab in space.tabs {
                for page in childTab.pages {
                    if let openerID = page.openerTabPageID, closingPageIDs.contains(openerID) {
                        page.openerTabPageID = nil
                        orphanedCount += 1
                    }
                }
            }
        }

        if orphanedCount > 0 {
            Logger.debug("Orphaned \(orphanedCount) popup page(s)", category: Logger.tabs)
        }
    }
}
