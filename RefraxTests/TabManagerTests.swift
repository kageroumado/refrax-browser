import Foundation
import SwiftData
import SwiftUI
import Testing
import WebKit
@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for TabManager operations.
    @Tag static var tabManager: Self
}

typealias Tab = Refrax.Tab

// MARK: - TabManager Test Environment

/// Test environment for TabManager tests.
///
/// Creates the required dependencies for testing TabManager operations
/// without requiring the full app infrastructure.
@MainActor
struct TabManagerTestEnvironment {
    let container: ModelContainer
    let modelContext: ModelContext
    let browserState: BrowserState
    let settings: BrowserSettings
    let pagePool: WebPagePool
    let spaceManager: SpaceManager
    let groupManager: TabGroupManager
    let referencePaneManager: ReferencePaneManager
    let undoRedoManager: UndoRedoManager
    let tabManager: TabManager
    let windowManager: WindowManager

    // These must be stored to keep strong references (like AppDelegate does)
    let historyManager: HistoryManager
    let downloadManager: DownloadManager
    let extensionManager: ExtensionManager
    let customSearchEngineManager: CustomSearchEngineManager
    let bookmarksManager: BookmarksManager
    let faviconCache: FaviconCache
    let siteSettingsManager: SiteSettingsManager
    let contentScriptManager: ContentScriptManager
    let archiveManager: TabArchiveManager
    let activationObserver: AppActivationObserver
    let webInspectorManager: WebInspectorManager

    /// Alias for the model container, used by history query actor initialization.
    var modelContainer: ModelContainer {
        container
    }

    init() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        self.container = try ModelContainer(for: schema, configurations: [config])
        self.modelContext = container.mainContext

        // Create minimal dependencies
        self.settings = BrowserSettings.fetchOrCreate(in: modelContext)

        self.historyManager = HistoryManager(modelContext: modelContext, settings: settings)
        self.faviconCache = FaviconCache(modelContainer: container)
        let dialogState = DialogState()
        let autoFillState = AutoFillState()
        self.siteSettingsManager = SiteSettingsManager(modelContext: modelContext)
        let passwordsManager = PasswordsManager()

        self.browserState = BrowserState(
            modelContext: modelContext,
            settings: settings,
            historyManager: historyManager,
            faviconCache: faviconCache,
            dialogState: dialogState,
            autoFillState: autoFillState,
            siteSettingsManager: siteSettingsManager,
            passwordsManager: passwordsManager,
        )

        self.pagePool = WebPagePool(state: browserState)
        self.spaceManager = SpaceManager(state: browserState)
        spaceManager.pagePool = pagePool

        // Create window manager first (needed by other managers)
        self.windowManager = WindowManager(modelContainer: container)

        // Create undo manager
        self.undoRedoManager = UndoRedoManager()

        self.groupManager = TabGroupManager(state: browserState)
        groupManager.windowManager = windowManager
        groupManager.undoRedoManager = undoRedoManager
        groupManager.pagePool = pagePool

        self.referencePaneManager = ReferencePaneManager(
            state: browserState,
            pagePool: pagePool,
            windowManager: windowManager,
            undoRedoManager: undoRedoManager,
        )

        self.tabManager = TabManager(
            state: browserState,
            pagePool: pagePool,
            spaceManager: spaceManager,
            groupManager: groupManager,
            referencePaneManager: referencePaneManager,
        )

        // Create managers that are implicitly unwrapped on BrowserState
        self.downloadManager = DownloadManager(modelContext: modelContext)
        self.extensionManager = ExtensionManager(state: browserState)
        self.customSearchEngineManager = CustomSearchEngineManager(modelContext: modelContext)
        self.webInspectorManager = WebInspectorManager()

        // Wire up circular dependencies
        browserState.webInspectorManager = webInspectorManager
        tabManager.windowManager = windowManager
        tabManager.undoRedoManager = undoRedoManager
        windowManager.tabManager = tabManager
        undoRedoManager.tabManager = tabManager
        undoRedoManager.tabGroupManager = groupManager
        undoRedoManager.spaceManager = spaceManager
        pagePool.tabManager = tabManager
        pagePool.windowManager = windowManager
        pagePool.spaceDataStoreManager = spaceManager.dataStoreManager
        pagePool.completeSetup()
        browserState.pagePool = pagePool
        browserState.downloadManager = downloadManager
        browserState.extensionManager = extensionManager

        // Create BookmarksManager (needs tabManager, so created after)
        self.bookmarksManager = BookmarksManager(
            modelContext: modelContext,
            tabManager: tabManager,
            historyManager: historyManager,
            faviconCache: faviconCache,
        )
        tabManager.bookmarksManager = bookmarksManager
        // Enable synchronous refreshes for deterministic test behavior
        bookmarksManager._useSynchronousRefreshes = true

        self.contentScriptManager = ContentScriptManager(state: browserState)

        // Create archive manager
        self.activationObserver = AppActivationObserver()
        self.archiveManager = TabArchiveManager(state: browserState, settings: settings)
        archiveManager.pagePool = pagePool
        archiveManager.activationObserver = activationObserver
        tabManager.archiveManager = archiveManager

        // Run async operations synchronously to avoid race conditions during teardown
        tabManager._runSynchronously = true

        // Disable archive by default for tests (preserves existing test behavior)
        settings.archiveEnabled = false
    }

    /// Creates a default space for testing.
    @discardableResult
    func makeSpace(name: String = "Test Space") -> Space {
        let space = spaceManager.createSpace(name: name, iconName: "star")
        spaceManager.ensureLoaded(space)
        return space
    }

    /// Creates a WindowState for testing.
    func makeWindowState() -> WindowState {
        WindowState(settings: settings, browserState: browserState)
    }

    /// Creates a WindowState and associates it with the window manager for testing.
    ///
    /// Also sets `tabManager.testActiveWindowState` and `groupManager.testActiveWindowState`
    /// so that methods like `selectNextTab()` and `createGroup()` without explicit space
    /// can find the active window state without an actual window controller.
    func makeActiveWindowState(with space: Space? = nil) -> WindowState {
        let windowState = makeWindowState()
        if let space {
            spaceManager.switchToSpaceSync(space, for: windowState)
        }
        #if REFRAX_TESTS
            tabManager.testActiveWindowState = windowState
            groupManager.testActiveWindowState = windowState
            referencePaneManager.testActiveWindowState = windowState
        #endif
        return windowState
    }

    /// Creates a tab and explicitly sets it as active in the given window state.
    ///
    /// Use this instead of relying on `createTab(makeActive: true)` in tests,
    /// since there's no actual window for `TabManager.activeWindowState` to find.
    @discardableResult
    func createActiveTab(
        url: URL,
        in space: Space,
        for windowState: WindowState,
        groupID: UUID? = nil,
        isPinned: Bool = false,
        loadImmediately: Bool = false,
    ) -> Refrax.Tab {
        let tab = tabManager.createTab(
            url: url,
            in: space,
            groupID: groupID,
            isPinned: isPinned,
            makeActive: false,
            loadImmediately: loadImmediately,
        )
        tabManager.setActiveTab(tab, in: windowState)
        return tab
    }
}

// MARK: - TabManager Create Tests

@Suite("TabManager Create Operations", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerCreateTests {
    @Test("Create tab in space with correct position")
    func createTabInSpace() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab = try env.createActiveTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            for: windowState,
        )

        #expect(tab.space?.id == space.id, "Tab should belong to space")
        #expect(space.tabs.contains(where: { $0.id == tab.id }), "Space should contain tab")
        #expect(env.browserState.tab(for: tab.id) != nil, "Tab should be indexed")
        #expect(windowState.activeTabID == tab.id, "Tab should be active")
    }

    @Test("Create tab sets unread flag when not active")
    func createTabUnreadWhenNotActive() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create first tab as active
        let activeTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://active.com")),
            in: space,
            makeActive: true,
        )

        // Create second tab in background
        let backgroundTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://background.com")),
            in: space,
            makeActive: false,
        )

        #expect(!activeTab.isUnread, "Active tab should not be unread")
        #expect(backgroundTab.isUnread, "Background tab should be unread")
    }

    @Test("Create pinned tab goes to pinned section")
    func createPinnedTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create normal tabs first
        let normalTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://normal.com")),
            in: space,
            isPinned: false,
            makeActive: false,
        )

        // Create pinned tab
        let pinnedTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://pinned.com")),
            in: space,
            isPinned: true,
            makeActive: false,
        )

        #expect(pinnedTab.isPinned, "Tab should be pinned")
        #expect(pinnedTab.status == .pinned, "Tab status should be pinned")
        #expect(!normalTab.isPinned, "Normal tab should not be pinned")

        // Pinned tabs should come before normal tabs in position
        #expect(pinnedTab.position < normalTab.position, "Pinned tab should have lower position than normal tab")
    }

    @Test("Create popup tab tracks opener page")
    func createPopupTabTracksOpener() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let opener = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        let popup = try env.tabManager.createPopupTab(
            in: space,
            openerTabPageID: opener.activePage.id,
            groupID: nil,
            url: #require(URL(string: "https://accounts.google.com")),
            activate: true,
        )

        #expect(popup.activePage.openerTabPageID == opener.activePage.id)
    }

    @Test("Create tab in group")
    func createTabInGroup() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create a group
        let group = try env.groupManager.createGroup(in: space, name: "Test Group")

        // Create tab in the group
        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://grouped.com")),
            in: space,
            groupID: group.id,
            makeActive: false,
        )

        #expect(tab.groupID == group.id, "Tab should have group ID")
        #expect(group.tabs.contains(where: { $0.id == tab.id }), "Group should contain tab")
    }

    @Test("Create tab with loadImmediately=true loads in background")
    func createTabLoadImmediately() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create first tab active
        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://active.com")),
            in: space,
            makeActive: true,
        )

        // Create background tab with immediate load
        let backgroundTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://background.com")),
            in: space,
            makeActive: false,
            loadImmediately: true,
        )

        // Page should be created even though tab is not active
        let page = env.pagePool.existingPage(for: backgroundTab.activePage)
        #expect(page != nil, "Page should be created for background tab with loadImmediately=true")
    }

    @Test("Create tab with loadImmediately=false does not load")
    func createTabNoLoad() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        // Create first tab active
        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://active.com")),
            in: space,
            makeActive: true,
        )

        // Create background tab without immediate load
        let backgroundTab = try env.tabManager.createTab(
            url: #require(URL(string: "https://lazy.com")),
            in: space,
            makeActive: false,
            loadImmediately: false,
        )

        // Page should NOT be created
        let page = env.pagePool.existingPage(for: backgroundTab.activePage)
        #expect(page == nil, "Page should not be created for lazy-loaded tab")
    }

    @Test("Create multiple tabs assigns descending positions (prepend behavior)")
    func createMultipleTabsSequentialPositions() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab1 = try env.tabManager.createTab(
            url: #require(URL(string: "https://one.com")),
            in: space,
            makeActive: false,
        )
        let tab2 = try env.tabManager.createTab(
            url: #require(URL(string: "https://two.com")),
            in: space,
            makeActive: false,
        )
        let tab3 = try env.tabManager.createTab(
            url: #require(URL(string: "https://three.com")),
            in: space,
            makeActive: false,
        )

        // Tabs are prepended, so newer tabs have lower positions
        #expect(tab1.position > tab2.position, "Tab 1 should have higher position than tab 2")
        #expect(tab2.position > tab3.position, "Tab 2 should have higher position than tab 3")
    }

    @Test("Create tab increments list version")
    func createTabIncrementsListVersion() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let initialVersion = env.browserState.tabListVersion

        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: false,
        )

        #expect(env.browserState.tabListVersion > initialVersion, "List version should increment")
    }
}

// MARK: - TabManager Close Tests

@Suite("TabManager Close Operations", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerCloseTests {
    @Test("Close tab removes from space")
    func closeTabRemovesFromSpace() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )
        let tabID = tab.id

        #expect(space.tabs.contains(where: { $0.id == tabID }), "Tab should exist in space")

        env.tabManager.closeTab(tab)

        #expect(!space.tabs.contains(where: { $0.id == tabID }), "Tab should be removed from space")
        #expect(env.browserState.tab(for: tabID) == nil, "Tab should be removed from index")
    }

    @Test("Close tab removes from group")
    func closeTabRemovesFromGroup() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Test Group")

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://grouped.com")),
            in: space,
            groupID: group.id,
            makeActive: true,
        )
        let tabID = tab.id

        #expect(group.tabs.contains(where: { $0.id == tabID }), "Group should contain tab")

        env.tabManager.closeTab(tab)

        #expect(!group.tabs.contains(where: { $0.id == tabID }), "Group should not contain closed tab")
    }

    @Test("Close active tab activates adjacent tab")
    func closeActiveTabActivatesAdjacent() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab1 = try env.createActiveTab(
            url: #require(URL(string: "https://one.com")),
            in: space,
            for: windowState,
        )

        let tab2 = try env.createActiveTab(
            url: #require(URL(string: "https://two.com")),
            in: space,
            for: windowState,
        )

        #expect(windowState.activeTabID == tab2.id, "Tab 2 should be active")

        env.tabManager.closeTab(tab2)

        // Tab 1 should now be active (MRU or adjacent)
        #expect(windowState.activeTabID == tab1.id, "Tab 1 should become active after closing tab 2")
    }

    @Test("Close non-active tab does not change active tab")
    func closeNonActiveTabKeepsActive() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab1 = try env.createActiveTab(
            url: #require(URL(string: "https://one.com")),
            in: space,
            for: windowState,
        )

        let tab2 = try env.tabManager.createTab(
            url: #require(URL(string: "https://two.com")),
            in: space,
            makeActive: false,
        )

        #expect(windowState.activeTabID == tab1.id, "Tab 1 should be active")

        env.tabManager.closeTab(tab2)

        #expect(windowState.activeTabID == tab1.id, "Tab 1 should still be active")
    }

    @Test("Close tab registers with undo manager")
    func closeTabRegistersUndo() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        let initialClosedCount = env.undoRedoManager.recentlyClosedTabs.count

        env.tabManager.closeTab(tab)

        #expect(
            env.undoRedoManager.recentlyClosedTabs.count > initialClosedCount,
            "Recently closed tabs should increase",
        )
    }

    @Test("Close last tab in space leaves space empty")
    func closeLastTabLeavesSpaceEmpty() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        env.tabManager.closeTab(tab)

        #expect(space.tabs.isEmpty, "Space should be empty")
        #expect(windowState.activeTabID == nil, "No active tab should exist")
    }

    @Test("Close tab increments list version")
    func closeTabIncrementsListVersion() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        let versionBeforeClose = env.browserState.tabListVersion

        env.tabManager.closeTab(tab)

        #expect(env.browserState.tabListVersion > versionBeforeClose, "List version should increment on close")
    }
}

// MARK: - TabManager Batch Close Tests

@Suite("TabManager Batch Close", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerBatchCloseTests {
    @Test("Batch close removes all tabs")
    func batchCloseRemovesAllTabs() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab1 = try env.tabManager.createTab(
            url: #require(URL(string: "https://one.com")),
            in: space,
            makeActive: false,
        )
        let tab2 = try env.tabManager.createTab(
            url: #require(URL(string: "https://two.com")),
            in: space,
            makeActive: false,
        )
        let tab3 = try env.tabManager.createTab(
            url: #require(URL(string: "https://three.com")),
            in: space,
            makeActive: true,
        )

        let tabIDs = [tab1.id, tab2.id, tab3.id]

        env.tabManager.closeTabs([tab1, tab2, tab3])

        for tabID in tabIDs {
            #expect(env.browserState.tab(for: tabID) == nil, "Tab should be removed")
        }
        #expect(space.tabs.isEmpty, "Space should be empty")
    }

    @Test("Batch close activates remaining tab when active is closed")
    func batchCloseActivatesRemaining() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let survivor = try env.tabManager.createTab(
            url: #require(URL(string: "https://survivor.com")),
            in: space,
            makeActive: false,
        )
        let tab2 = try env.tabManager.createTab(
            url: #require(URL(string: "https://two.com")),
            in: space,
            makeActive: false,
        )
        let activeTab = try env.createActiveTab(
            url: #require(URL(string: "https://active.com")),
            in: space,
            for: windowState,
        )

        #expect(windowState.activeTabID == activeTab.id)

        // Close the active tab and one other, leaving survivor
        env.tabManager.closeTabs([tab2, activeTab])

        #expect(windowState.activeTabID == survivor.id, "Survivor should become active")
    }

    @Test("Batch close with active tab not included keeps active")
    func batchCloseKeepsActiveWhenNotIncluded() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        let windowState = env.makeActiveWindowState(with: space)

        let activeTab = try env.createActiveTab(
            url: #require(URL(string: "https://active.com")),
            in: space,
            for: windowState,
        )
        let tab2 = try env.tabManager.createTab(
            url: #require(URL(string: "https://two.com")),
            in: space,
            makeActive: false,
        )
        let tab3 = try env.tabManager.createTab(
            url: #require(URL(string: "https://three.com")),
            in: space,
            makeActive: false,
        )

        // Close tabs that are not active
        env.tabManager.closeTabs([tab2, tab3])

        #expect(windowState.activeTabID == activeTab.id, "Active tab should remain active")
    }

    @Test("Batch close registers single undo action")
    func batchCloseRegistersSingleUndo() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let tab1 = try env.tabManager.createTab(
            url: #require(URL(string: "https://one.com")),
            in: space,
            makeActive: false,
        )
        let tab2 = try env.tabManager.createTab(
            url: #require(URL(string: "https://two.com")),
            in: space,
            makeActive: false,
        )
        let tab3 = try env.tabManager.createTab(
            url: #require(URL(string: "https://three.com")),
            in: space,
            makeActive: true,
        )

        let initialClosedCount = env.undoRedoManager.recentlyClosedTabs.count

        env.tabManager.closeTabs([tab1, tab2, tab3])

        // Should register as a batch (multiple tabs in one entry)
        #expect(
            env.undoRedoManager.recentlyClosedTabs.count == initialClosedCount + 3,
            "Should register all closed tabs",
        )
    }
}

// MARK: - TabManager Duplicate Tests

@Suite("TabManager Duplicate Operations", .tags(.tabManager), .serialized)
@MainActor
struct TabManagerDuplicateTests {
    @Test("Duplicate tab creates new tab with same URL")
    func duplicateTabCreatesNewTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let original = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com/page")),
            in: space,
            makeActive: true,
        )

        let duplicate = env.tabManager.duplicateTab(original)

        #expect(duplicate.id != original.id, "Duplicate should have different ID")
        #expect(duplicate.activePage.url == original.activePage.url, "URL should match")
        #expect(duplicate.space?.id == original.space?.id, "Same space")
    }

    @Test("Duplicate tab preserves favicon")
    func duplicateTabPreservesFavicon() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let original = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )

        // Set favicon data
        let faviconData = Data([0x89, 0x50, 0x4E, 0x47]) // PNG header
        original.activePage.faviconData = faviconData

        let duplicate = env.tabManager.duplicateTab(original)

        #expect(duplicate.activePage.faviconData == faviconData, "Favicon should be copied")
    }

    @Test("Duplicate tab is marked unread")
    func duplicateTabIsUnread() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let original = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            makeActive: true,
        )
        #expect(!original.isUnread, "Original should not be unread")

        let duplicate = env.tabManager.duplicateTab(original)

        #expect(duplicate.isUnread, "Duplicate should be marked unread")
    }

    @Test("Duplicate tab preserves group membership")
    func duplicateTabPreservesGroup() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let group = try env.groupManager.createGroup(in: space, name: "Test Group")

        let original = try env.tabManager.createTab(
            url: #require(URL(string: "https://example.com")),
            in: space,
            groupID: group.id,
            makeActive: true,
        )

        let duplicate = env.tabManager.duplicateTab(original)

        #expect(duplicate.groupID == group.id, "Duplicate should be in same group")
        #expect(group.tabs.contains(where: { $0.id == duplicate.id }), "Group should contain duplicate")
    }

    @Test("Duplicate tab is inserted after original")
    func duplicateTabInsertedAfterOriginal() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://one.com")),
            in: space,
            makeActive: false,
        )
        let original = try env.tabManager.createTab(
            url: #require(URL(string: "https://original.com")),
            in: space,
            makeActive: true,
        )
        _ = try env.tabManager.createTab(
            url: #require(URL(string: "https://three.com")),
            in: space,
            makeActive: false,
        )

        let duplicate = env.tabManager.duplicateTab(original)

        // Find indices
        let originalIndex = try #require(space.tabs.firstIndex(where: { $0.id == original.id }))
        let duplicateIndex = try #require(space.tabs.firstIndex(where: { $0.id == duplicate.id }))

        #expect(duplicateIndex == originalIndex + 1, "Duplicate should be right after original")
    }

    @Test("Duplicate pinned tab preserves pinned status")
    func duplicatePinnedTab() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()
        _ = env.makeActiveWindowState(with: space)

        let pinned = try env.tabManager.createTab(
            url: #require(URL(string: "https://pinned.com")),
            in: space,
            isPinned: true,
            makeActive: true,
        )

        let duplicate = env.tabManager.duplicateTab(pinned)

        #expect(duplicate.isPinned, "Duplicate should be pinned")
        #expect(duplicate.status == .pinned, "Duplicate status should be pinned")
    }
}
