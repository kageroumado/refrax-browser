import AppKit
import Foundation
import Observation
import SwiftData
import SwiftUI
import WebKit

/// Shared mutable state container for all browser managers.
///
/// `BrowserState` holds the core data that multiple managers need to access
/// and modify. This avoids circular dependencies between managers while
/// providing a single source of truth for browser state.
///
/// ## Multi-Window Architecture
///
/// `BrowserState` holds **global** data shared across all windows:
/// - `spaces`: All loaded Space objects
/// - `tabIndex`: Fast O(1) lookup for tabs by ID
/// - `pagePool`: Reference to WebView session manager (owned by TabManager)
///
/// **Per-window** state is stored in `WindowState`:
/// - `activeSpaceID`: Which space this window shows
/// - `activeTabIDs`: Which tab is selected per space in this window
/// - `isInspectorCollapsed`: Whether the reference pane is visible
///
/// This allows multiple windows to view the same spaces with different tab and
/// reference pane selections.
///
/// ## Tab Index
///
/// The `tabIndex` dictionary provides O(1) tab lookup by ID. It is maintained
/// automatically when tabs are inserted or removed via `indexTab(_:)` and
/// `removeFromIndex(_:)`. All tab mutations should go through TabManager
/// which calls these methods.
///
/// ## Mutation Counters
///
/// Two mutation counters track changes for efficient view updates:
/// - `tabListVersion`: Incremented on structural changes (add/remove/reorder tabs, groups)
/// - `tabContentVersion`: Incremented on metadata changes (title, favicon, unread state)
///
/// Views observe these counters instead of computing expensive signatures.
///
/// ## Ownership
///
/// `TabManager` owns this instance and passes it to sub-managers during init.
/// Sub-managers hold unowned references to avoid retain cycles.
///
/// ## Thread Safety
///
/// All state access must occur on the main actor. The `@Observable` macro
/// ensures SwiftUI views update automatically when state changes.
@Observable
final class BrowserState {
    // MARK: - Core State (Global)

    /// All loaded spaces in memory. Shared across all windows.
    ///
    /// Marked @ObservationIgnored to prevent views from creating observation dependencies
    /// when iterating over spaces. Views that need to react to space list changes should
    /// observe `tabListVersion` (incremented on space add/remove) rather than the array.
    @ObservationIgnored
    private(set) var spaces: [Space] = []

    /// Global live favorite tabs visible across all spaces.
    ///
    /// Live favorite tabs are persistent tabs linked to favorited bookmarks. They appear
    /// in the favorites grid at the top of every space's sidebar and use global website
    /// data storage regardless of space settings.
    ///
    /// - Note: Live favorite tabs have `status == .liveFavorite` and are indexed in
    ///   `tabIndex` like regular tabs. Their `linkedBookmark` relationship points to the
    ///   associated `Bookmark`.
    @ObservationIgnored
    private(set) var liveFavoriteTabs: [Tab] = []

    /// Fast O(1) lookup for tabs by ID across all spaces and live favorites.
    ///
    /// Maintained via `indexTab(_:)` and `removeFromIndex(_:)`.
    /// Includes main tabs, reference tabs, and live favorite tabs.
    ///
    /// - Note: This index must be kept in sync with tab insertions/deletions.
    ///   Always use TabManager methods which handle index maintenance automatically.
    @ObservationIgnored
    private var tabIndex: [Tab.ID: Tab] = [:]
    
    // MARK: - Mutation Counters
    
    /// Version counter for structural tab list changes.
    ///
    /// Incremented when:
    /// - Tabs are created, closed, or restored
    /// - Tabs are reordered or moved between groups
    /// - Groups are created, deleted, collapsed, or nested
    /// - Spaces are switched or modified
    /// - Pin state changes (affects visual ordering)
    ///
    /// Views observing tab list structure should use:
    /// ```swift
    /// .onChange(of: tabManager.state.tabListVersion) { rebuildLayout() }
    /// ```
    private(set) var tabListVersion: UInt64 = 0
    
    /// Version counter for tab content/metadata changes.
    ///
    /// Incremented when:
    /// - Tab title or URL changes
    /// - Favicon updates
    /// - Unread state changes
    /// - Custom name changes
    ///
    /// Views observing tab content should use:
    /// ```swift
    /// .onChange(of: tabManager.state.tabContentVersion) { updateDisplay() }
    /// ```
    private(set) var tabContentVersion: UInt64 = 0

    // MARK: - Incremental Layout Update Callbacks

    /// Callback for incremental single-item removal in layout.
    ///
    /// When set, `TabMutationPipeline` invokes this after a single tab is removed,
    /// allowing `LayoutManager` to update incrementally instead of triggering a
    /// full layout rebuild.
    ///
    /// - Parameters:
    ///   - itemID: The ID of the removed item.
    ///   - context: Information about where the item was located.
    /// - Returns: `true` if the removal was handled incrementally (skip full rebuild).
    @ObservationIgnored
    var onIncrementalRemoval: ((UUID, TabMutationPipeline.RemovalContext) -> Bool)?

    /// Callback for incremental batch removal in layout.
    ///
    /// When set, `TabMutationPipeline` invokes this after multiple tabs are removed
    /// in a batch operation, allowing `LayoutManager` to update incrementally.
    ///
    /// - Parameters:
    ///   - itemIDs: The set of IDs of removed items.
    ///   - spaceID: The space where the removal occurred.
    /// - Returns: `true` if the removal was handled incrementally (skip full rebuild).
    @ObservationIgnored
    var onBatchRemoval: ((Set<UUID>, Space.ID) -> Bool)?

    /// The version counter at which the last incremental update was applied.
    ///
    /// Used by `LayoutManager.rebuildLayout()` to skip full rebuilds when the
    /// version was already handled incrementally via callbacks.
    @ObservationIgnored
    private(set) var lastIncrementallyHandledVersion: UInt64 = 0

    /// Marks the current `tabListVersion` as handled incrementally.
    ///
    /// Called by `TabMutationPipeline` after a successful incremental update
    /// callback, signaling `LayoutManager` to skip the full rebuild.
    func markIncrementallyHandled() {
        lastIncrementallyHandledVersion = tabListVersion
    }
    
    // MARK: - Dependencies

    @ObservationIgnored
    let modelContext: ModelContext
    @ObservationIgnored
    let settings: BrowserSettings
    @ObservationIgnored
    let historyManager: HistoryManager
    @ObservationIgnored
    let faviconCache: FaviconCache
    @ObservationIgnored
    let dialogState: DialogState
    @ObservationIgnored
    let siteSettingsManager: SiteSettingsManager
    @ObservationIgnored
    let settingsApplier: WebPageSettingsApplier
    @ObservationIgnored
    let siteSettingsCoordinator: SiteSettingsCoordinator
    @ObservationIgnored
    let scriptRegistry: ScriptRegistry

    /// Download manager for handling file downloads.
    ///
    /// Set by TabManager after initialization (late-bound to avoid circular dependency).
    @ObservationIgnored
    unowned var downloadManager: DownloadManager!
    
    /// WebPage pool for WebView lifecycle management.
    ///
    /// Set by TabManager after initialization.
    @ObservationIgnored
    unowned var pagePool: WebPagePool!

    /// Extension manager for browser extension support.
    ///
    /// Set by AppDelegate after initialization.
    @ObservationIgnored
    unowned var extensionManager: ExtensionManager!

    /// Space lock manager for Touch ID authentication.
    ///
    /// Manages unlock state for locked spaces. Created during initialization.
    @ObservationIgnored
    let spaceLockManager: SpaceLockManager

    /// PiP coordinator for auto-PiP on tab switch.
    ///
    /// Coordinates Picture-in-Picture behavior when switching between tabs.
    @ObservationIgnored
    let pipCoordinator: PiPCoordinator

    /// Web inspector manager for developer tools.
    ///
    /// Manages WebKit inspector instances across all tabs.
    /// Set by AppDelegate after initialization.
    @ObservationIgnored
    unowned var webInspectorManager: WebInspectorManager!

    /// Handoff manager for NSUserActivity continuity.
    ///
    /// Manages Handoff state when switching tabs or navigating.
    @ObservationIgnored
    let handoffManager: HandoffManager

    /// Domain time tracker for tracking time spent per domain.
    ///
    /// Tracks cumulative time spent on each domain in a rolling 24-hour window
    /// and enforces user-configured daily time limits.
    @ObservationIgnored
    let domainTimeTracker: DomainTimeTracker

    // MARK: - Configuration
    
    /// WebPage configuration for creating new sessions.
    @ObservationIgnored
    var webPageConfiguration: WebPage.Configuration
    
    // MARK: - WebPage Access

    /// Gets an existing WebPage for a tab page ID.
    ///
    /// Convenience accessor that delegates to the page pool.
    /// Does not create pages - use `pagePool.page(for:)` for that.
    ///
    /// - Parameter pageID: The tab page ID to look up.
    /// - Returns: Existing WebPage, or `nil` if none exists.
    func webPage(for pageID: TabPage.ID) -> WebPage? {
        pagePool.existingPage(for: pageID)
    }
    
    // MARK: - UI State
    
    /// Auto-fill state for credential management.
    @ObservationIgnored
    let autoFillState: AutoFillState
    
    /// Auto-fill manager instance.
    @ObservationIgnored
    let autoFillManager: AutoFillManager
    
    /// Whether content blocking rules are compiled and ready.
    @ObservationIgnored
    private(set) var isContentBlockingReady = false

    /// Whether the bundled `refrax-ctl` helper needs an administrator-privileged
    /// install or update (`/usr/local/bin` isn't user-writable and the installed
    /// binary is missing or stale).
    ///
    /// Set at launch and on control-mode changes after the silent install
    /// attempt; drives the sidebar install button and the Settings row.
    /// Cleared after a successful authorized install.
    var cliHelperNeedsPrivilegedInstall = false
    
    // MARK: - Persistence

    /// Debounced saver for tab state persistence.
    @ObservationIgnored
    private let saver: DebouncedModelContextSaver

    /// Schedules a debounced save operation.
    ///
    /// This is the single entry point for all debounced saves across managers.
    /// Cancels any pending save and schedules a new one after the debounce delay.
    /// Multiple rapid calls will only result in a single save after the delay.
    ///
    /// - Note: All managers (TabManager, SpaceManager, TabGroupManager) should call
    ///   this method instead of implementing their own save scheduling.
    func scheduleSave() {
        saver.scheduleSave()
    }

    /// Saves immediately without debouncing.
    ///
    /// Use sparingly - prefer `scheduleSave()` for most operations.
    /// This cancels any pending debounced save and saves immediately.
    func saveImmediately() async {
        await saver.saveImmediately()
    }

    /// Saves immediately without debouncing, synchronously.
    ///
    /// For contexts that cannot await — app termination in particular, where a
    /// debounced save scheduled now would never fire before the process exits.
    func saveImmediatelySync() {
        saver.saveImmediatelySync()
    }
    
    // MARK: - Space Lookup
    
    /// Finds a space by ID.
    func space(for id: Space.ID) -> Space? {
        spaces.first { $0.id == id }
    }
    
    /// Gets groups for a specific space.
    func groups(in space: Space) -> [TabGroup] {
        space.groups
    }
    
    /// Gets tabs for a specific space.
    func tabs(in space: Space) -> [Tab] {
        space.tabs
    }
    
    /// Gets reference tabs for a specific space.
    func referenceTabs(in space: Space) -> [Tab] {
        space.referenceTabs
    }
    
    // MARK: - Tab Lookup

    /// Finds a tab by ID using O(1) index lookup.
    ///
    /// - Parameter id: The tab's unique identifier.
    /// - Returns: The tab if found in the index, nil otherwise.
    ///
    /// - Note: This searches all tabs including space tabs, reference tabs, and live favorites.
    func tab(for id: Tab.ID) -> Tab? {
        tabIndex[id]
    }

    /// Finds a reference tab by ID using O(1) index lookup.
    ///
    /// - Parameters:
    ///   - id: The reference tab's unique identifier.
    ///   - spaceID: Optional space to filter by. If provided, only returns the tab
    ///              if it belongs to that space.
    /// - Returns: The reference tab if found, nil otherwise.
    ///
    /// - Note: Reference tabs are indexed alongside main tabs. This method
    ///   verifies the tab is actually a reference tab before returning.
    func referenceTab(for id: Tab.ID, spaceID: Space.ID? = nil) -> Tab? {
        guard let tab = tabIndex[id], tab.isReferenceTab else { return nil }
        if let spaceID { return tab.space?.id == spaceID ? tab : nil }
        return tab
    }

    /// Finds a live favorite tab by its linked bookmark ID.
    ///
    /// - Parameter bookmarkID: The bookmark ID the live tab is linked to.
    /// - Returns: The live favorite tab if found, nil otherwise.
    func liveFavoriteTab(for bookmarkID: UUID) -> Tab? {
        liveFavoriteTabs.first { $0.linkedBookmark?.id == bookmarkID }
    }
    
    // MARK: - Initialization
    
    /// Task for observing settings changes.
    @ObservationIgnored
    private var settingsObservationTask: Task<Void, Never>?

    init(
        modelContext: ModelContext,
        settings: BrowserSettings,
        historyManager: HistoryManager,
        faviconCache: FaviconCache,
        dialogState: DialogState,
        autoFillState: AutoFillState,
        siteSettingsManager: SiteSettingsManager,
        passwordsManager: PasswordsManager,
    ) {
        self.modelContext = modelContext
        self.saver = DebouncedModelContextSaver(
            modelContext: modelContext,
            debounceDelay: 1.3,
            logCategory: Logger.tabs,
        )
        self.settings = settings
        self.historyManager = historyManager
        self.faviconCache = faviconCache
        self.dialogState = dialogState
        self.autoFillState = autoFillState
        self.autoFillManager = AutoFillManager(
            settings: settings,
            passwordsManager: passwordsManager,
            siteSettingsManager: siteSettingsManager,
            autoFillState: autoFillState,
        )
        self.siteSettingsManager = siteSettingsManager
        self.spaceLockManager = SpaceLockManager(settings: settings)
        self.pipCoordinator = PiPCoordinator(settings: settings)
        self.handoffManager = HandoffManager()
        self.domainTimeTracker = DomainTimeTracker()

        let deviceSensorAuthorization = WebPage.DeviceSensorAuthorization(
            decisionHandler: PermissionDecisionResolver.makeDeviceSensorDecisionHandler(
                siteSettingsManager: siteSettingsManager,
            ),
        )
        self.settingsApplier = WebPageSettingsApplier(
            settings: settings,
            deviceSensorAuthorization: deviceSensorAuthorization,
            siteSettingsManager: siteSettingsManager,
        )
        self.siteSettingsCoordinator = SiteSettingsCoordinator(
            siteSettingsManager: siteSettingsManager,
            browserSettings: settings,
        )
        self.scriptRegistry = ScriptRegistry()

        // Basic WebPage configuration (scripts loaded async later)
        var config = WebPage.Configuration()
        config.websiteDataStore = .default()
        settingsApplier.apply(to: &config)
        self.webPageConfiguration = config

        // Start observing settings changes
        startSettingsObservation()
    }

    isolated deinit {
        settingsObservationTask?.cancel()
    }

    // MARK: - Settings Observation

    /// Starts observing BrowserSettings changes to update webPageConfiguration.
    ///
    /// Observed settings are applied to new pages only—existing pages retain their
    /// configuration until reloaded or recreated.
    private func startSettingsObservation() {
        let settings = settings
        let settingsChanges = Observations {
            settings.enableJavaScript
            settings.featureFlagOverridesJSON
        }

        settingsObservationTask = Task { [weak self] in
            for await _ in settingsChanges {
                guard let self else { break }
                settingsApplier.apply(to: &webPageConfiguration)
                Logger.info("Browser settings updated for new pages", category: Logger.data)
            }
        }
    }
    
    // MARK: - Tab Index Management

    /// Adds a tab to the index for O(1) lookup.
    ///
    /// Called automatically by TabManager when creating tabs.
    /// Safe to call multiple times for the same tab (updates existing entry).
    ///
    /// - Parameter tab: The tab to index.
    func indexTab(_ tab: Tab) {
        tabIndex[tab.id] = tab
    }
    
    /// Removes a tab from the index.
    ///
    /// Called automatically by TabManager when closing tabs.
    /// Safe to call for tabs not in the index (no-op).
    ///
    /// - Parameter tab: The tab to remove from the index.
    func removeFromIndex(_ tab: Tab) {
        tabIndex.removeValue(forKey: tab.id)
    }
    
    /// Rebuilds the entire tab index from all spaces and live favorites.
    ///
    /// Call this after bulk operations like restoring from persistence
    /// or when the index may have become stale.
    func rebuildTabIndex() {
        tabIndex.removeAll()
        for space in spaces {
            for tab in space.tabs {
                tabIndex[tab.id] = tab
            }
            for tab in space.referenceTabs {
                tabIndex[tab.id] = tab
            }
        }
        for tab in liveFavoriteTabs {
            tabIndex[tab.id] = tab
        }
    }

    #if DEBUG
        /// Verifies the tab index is synchronized with the actual tab data.
        ///
        /// This is a debug-only method that checks for common desync issues:
        /// - Tabs in spaces that aren't in the index (missing indexTab call)
        /// - Tabs in the index that don't exist in any space (missing removeFromIndex call)
        ///
        /// Call this periodically during development or after bulk operations
        /// to catch synchronization bugs early.
        ///
        /// - Returns: A list of desync issues found, or empty if the index is valid.
        func verifyTabIndex() -> [String] {
            var issues: [String] = []

            // Build the expected set of tabs from all sources
            var expectedTabs: Set<Tab.ID> = []
            for space in spaces {
                for tab in space.tabs {
                    expectedTabs.insert(tab.id)
                }
                for tab in space.referenceTabs {
                    expectedTabs.insert(tab.id)
                }
            }
            for tab in liveFavoriteTabs {
                expectedTabs.insert(tab.id)
            }

            // Check for tabs in spaces but not in index
            for tabID in expectedTabs where tabIndex[tabID] == nil {
                issues.append("Tab \(tabID) is in a space but not in tabIndex")
            }

            // Check for tabs in index but not in spaces
            let indexedIDs = Set(tabIndex.keys)
            for tabID in indexedIDs where !expectedTabs.contains(tabID) {
                issues.append("Tab \(tabID) is in tabIndex but not in any space")
            }

            if !issues.isEmpty {
                Logger.warning("Tab index desync detected: \(issues.count) issues", category: Logger.data)
            }

            return issues
        }

        /// Asserts the tab index is synchronized, failing in debug builds if not.
        ///
        /// Call this after operations that should maintain index consistency
        /// to catch bugs during development.
        func assertTabIndexSynchronized(file: StaticString = #file, line: UInt = #line) {
            let issues = verifyTabIndex()
            assert(issues.isEmpty, "Tab index desync: \(issues.joined(separator: "; "))", file: file, line: line)
        }
    #endif

    // MARK: - Mutation Counter Management
    
    /// Increments the tab list version counter.
    ///
    /// Call after any structural change to the tab list:
    /// - Tab create/close/restore
    /// - Tab reorder or group membership change
    /// - Group create/delete/collapse/nest
    /// - Space switch
    /// - Pin state change
    func incrementListVersion() {
        tabListVersion &+= 1
    }
    
    /// Increments the tab content version counter.
    ///
    /// Call after any metadata change:
    /// - Title or URL update
    /// - Favicon update
    /// - Unread state change
    /// - Custom name change
    func incrementContentVersion() {
        tabContentVersion &+= 1
    }
    
    // MARK: - State Mutation (internal)
    
    /// Sets the spaces array. Call only from SpaceManager.
    ///
    /// Also rebuilds the tab index to ensure consistency.
    func setSpaces(_ newSpaces: [Space]) {
        spaces = newSpaces
        rebuildTabIndex()
        incrementListVersion()
    }

    /// Adds a space. Call only from SpaceManager.
    func addSpace(_ space: Space) {
        spaces.append(space)
        // Index any existing tabs in the new space
        for tab in space.tabs {
            indexTab(tab)
        }
        for tab in space.referenceTabs {
            indexTab(tab)
        }
        incrementListVersion()
    }
    
    /// Removes a space at index. Call only from SpaceManager.
    ///
    /// Also removes all tabs in that space from the index.
    func removeSpace(at index: Int) {
        let space = spaces[index]
        // Remove tabs from index before removing space
        for tab in space.tabs {
            removeFromIndex(tab)
        }
        for tab in space.referenceTabs {
            removeFromIndex(tab)
        }
        spaces.remove(at: index)
        incrementListVersion()
    }

    /// Clears all spaces. Used when replacing temporary spaces with persisted ones.
    ///
    /// Also clears the tab index.
    func clearSpaces() {
        tabIndex.removeAll()
        spaces.removeAll()
        incrementListVersion()
    }

    /// Marks content blocking as ready.
    func setContentBlockingReady(_ ready: Bool) {
        isContentBlockingReady = ready
    }

    // MARK: - Live Favorite Tab Management

    /// Adds a live favorite tab.
    ///
    /// Called by TabManager when creating a new live favorite tab from a bookmark.
    ///
    /// - Parameter tab: The live favorite tab to add. Must have `status == .liveFavorite`.
    func addLiveFavoriteTab(_ tab: Tab) {
        liveFavoriteTabs.append(tab)
        indexTab(tab)
        incrementListVersion()
    }

    /// Removes a live favorite tab.
    ///
    /// Called by TabManager when removing a bookmark from favorites.
    ///
    /// - Parameter tab: The live favorite tab to remove.
    func removeLiveFavoriteTab(_ tab: Tab) {
        liveFavoriteTabs.removeAll { $0.id == tab.id }
        removeFromIndex(tab)
        incrementListVersion()
    }

    /// Moves a live favorite tab to a space, converting it to a regular or pinned tab.
    ///
    /// Unlike `removeLiveFavoriteTab`, this preserves the tab in the index since it's
    /// being moved to a space rather than deleted.
    ///
    /// - Parameters:
    ///   - tab: The live favorite tab to convert.
    ///   - space: The target space.
    ///   - isPinned: Whether the tab should be pinned in the space.
    func convertLiveFavoriteToSpaceTab(_ tab: Tab, in space: Space, isPinned: Bool) {
        liveFavoriteTabs.removeAll { $0.id == tab.id }
        tab.space = space
        tab.status = isPinned ? .pinned : .regular
        // Set origin URL for navigation containment when becoming pinned
        // Use the bookmark's URL (the original home) or current URL as fallback
        tab.originURL = isPinned ? (tab.linkedBookmark?.url ?? tab.activePage.url) : nil
        tab.isPinned = isPinned
        incrementListVersion()
    }

    /// Sets all live favorite tabs. Used during initialization.
    ///
    /// - Parameter tabs: The live favorite tabs to set.
    func setLiveFavoriteTabs(_ tabs: [Tab]) {
        liveFavoriteTabs = tabs
        for tab in tabs {
            indexTab(tab)
        }
        incrementListVersion()
    }
}

// MARK: - Closed Tab Info

/// Information captured when closing a tab for undo support.
struct ClosedTabInfo: Identifiable, Equatable {
    let id: UUID
    let url: URL
    let title: String
    let faviconData: Data?
    let customName: String?
    let isPinned: Bool
    let isReferenceTab: Bool
    let groupID: UUID?
    let position: Int
    let spaceID: UUID
    let closedAt: Date

    init(tab: Tab) {
        self.id = UUID()
        self.url = tab.activePage.url
        self.title = tab.activePage.title
        self.faviconData = tab.activePage.faviconData
        self.customName = tab.customName
        self.isPinned = tab.isPinned
        self.isReferenceTab = tab.isReferenceTab
        self.groupID = tab.groupID
        self.position = tab.position
        self.spaceID = tab.space?.id ?? UUID()
        self.closedAt = Date()
    }
}

// MARK: - Closed Group Info

/// Information captured when deleting a group for undo support.
struct ClosedGroupInfo: Identifiable, Equatable {
    let id: UUID
    let name: String
    let colorString: String
    let iconName: String?
    let isPinned: Bool
    let position: Int
    let spaceID: UUID
    let parentGroupID: UUID?
    let tabs: [ClosedTabInfo]
    let closedAt: Date
    
    init(group: TabGroup, tabs: [Tab]) {
        self.id = UUID()
        self.name = group.name
        self.colorString = group.colorString
        self.iconName = group.iconName
        self.isPinned = group.isPinned
        self.position = group.position
        self.spaceID = group.space?.id ?? UUID()
        self.parentGroupID = group.parentGroupID
        self.tabs = tabs.map { ClosedTabInfo(tab: $0) }
        self.closedAt = Date()
    }
}
