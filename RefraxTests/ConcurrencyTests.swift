import Foundation
import SwiftData
import Testing
@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for concurrency and race condition handling.
    @Tag static var concurrency: Self

    /// Tests for tab index synchronization.
    @Tag static var tabIndex: Self
}

// MARK: - Concurrency Test Environment

/// Minimal test environment for concurrency tests.
///
/// Uses the full app dependency graph by leveraging `WebPagePool.page(for:)` to create
/// WebPage instances with all required dependencies properly wired.
@MainActor
struct ConcurrencyTestEnvironment {
    let container: ModelContainer
    let modelContext: ModelContext
    let browserState: BrowserState
    let settings: BrowserSettings
    let pagePool: WebPagePool
    let tabManager: TabManager
    let windowManager: WindowManager
    let webInspectorManager: WebInspectorManager
    let spaceDataStoreManager: SpaceDataStoreManager
    let downloadManager: DownloadManager

    init() throws {
        let schema = Schema(versionedSchema: SchemaV1.self)
        let config = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        self.container = try ModelContainer(for: schema, configurations: [config])
        self.modelContext = container.mainContext

        self.settings = BrowserSettings.fetchOrCreate(in: modelContext)
        let historyManager = HistoryManager(modelContext: modelContext, settings: settings)
        let faviconCache = FaviconCache(modelContainer: container)

        let dialogState = DialogState()
        let autoFillState = AutoFillState()
        let siteSettingsManager = SiteSettingsManager(modelContext: modelContext)
        let passwordsManager = PasswordsManager()

        let autoFillManager = AutoFillManager(
            settings: settings,
            passwordsManager: passwordsManager,
            siteSettingsManager: siteSettingsManager,
            autoFillState: autoFillState,
        )
        _ = autoFillManager // Unused - BrowserState creates its own

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

        // Create page pool
        self.pagePool = WebPagePool(state: browserState)
        browserState.pagePool = pagePool

        // Create download manager
        self.downloadManager = DownloadManager(modelContext: modelContext)
        browserState.downloadManager = downloadManager

        // Create web inspector manager
        self.webInspectorManager = WebInspectorManager()
        browserState.webInspectorManager = webInspectorManager

        // Create supporting managers for TabManager
        let spaceManager = SpaceManager(state: browserState)
        let groupManager = TabGroupManager(state: browserState)
        let undoRedoManager = UndoRedoManager()
        self.spaceDataStoreManager = SpaceDataStoreManager()
        self.windowManager = WindowManager(modelContainer: container)
        let referencePaneManager = ReferencePaneManager(
            state: browserState,
            pagePool: pagePool,
            windowManager: windowManager,
            undoRedoManager: undoRedoManager,
        )

        // Wire up cross-references
        pagePool.spaceDataStoreManager = spaceDataStoreManager
        spaceManager.pagePool = pagePool
        groupManager.pagePool = pagePool

        // Create tab manager
        self.tabManager = TabManager(
            state: browserState,
            pagePool: pagePool,
            spaceManager: spaceManager,
            groupManager: groupManager,
            referencePaneManager: referencePaneManager,
        )
        pagePool.tabManager = tabManager
        pagePool.windowManager = windowManager
    }

    /// Creates a test TabPage and returns the WebPage created for it.
    ///
    /// Uses `pagePool.page(for:)` to ensure all dependencies are properly wired.
    func makeWebPage(url: URL = URL(string: "https://example.com")!) -> WebPage {
        let space = Space(name: "Test", iconName: "star")
        modelContext.insert(space)
        browserState.addSpace(space)

        let tab = Tab(space: space, url: url)
        modelContext.insert(tab)
        space.tabs.append(tab)
        browserState.indexTab(tab)

        let tabPage = tab.activePage

        // Use pagePool to create the WebPage with all dependencies properly wired
        guard let webPage = pagePool.page(for: tabPage) else {
            fatalError("Failed to create WebPage for test tab")
        }
        return webPage
    }
}

// MARK: - Navigation Generation Tests

@Suite("Navigation Generation Counter", .tags(.concurrency))
@MainActor
struct NavigationGenerationTests {
    @Test("Navigation generation starts at zero before async load")
    func generationStartsAtZero() throws {
        let env = try ConcurrencyTestEnvironment()
        let webPage = env.makeWebPage()

        // After init, generation is 0 - the initial load is dispatched via
        // DispatchQueue.main.async, so it hasn't incremented yet
        #expect(webPage.navigationGeneration == 0, "Generation should be 0 before async load starts")
    }

    @Test("Navigation generation increments on each load")
    func generationIncrementsOnLoad() throws {
        let env = try ConcurrencyTestEnvironment()
        let webPage = env.makeWebPage()

        let initialGeneration = webPage.navigationGeneration

        // Trigger a new load
        _ = try webPage.load(#require(URL(string: "https://apple.com")))

        #expect(
            webPage.navigationGeneration == initialGeneration + 1,
            "Generation should increment after load",
        )

        // Trigger another load
        _ = try webPage.load(#require(URL(string: "https://google.com")))

        #expect(
            webPage.navigationGeneration == initialGeneration + 2,
            "Generation should increment again after second load",
        )
    }

    @Test("Reload increments navigation generation")
    func reloadIncrementsGeneration() throws {
        let env = try ConcurrencyTestEnvironment()
        let webPage = env.makeWebPage()

        let initialGeneration = webPage.navigationGeneration

        // Trigger reload
        _ = webPage.reload()

        #expect(
            webPage.navigationGeneration == initialGeneration + 1,
            "Generation should increment after reload",
        )
    }

    @Test("Load with URLRequest increments generation")
    func loadRequestIncrementsGeneration() throws {
        let env = try ConcurrencyTestEnvironment()
        let webPage = env.makeWebPage()

        let initialGeneration = webPage.navigationGeneration

        // Trigger load with URLRequest
        let request = try URLRequest(url: #require(URL(string: "https://apple.com")))
        _ = webPage.load(request)

        #expect(
            webPage.navigationGeneration == initialGeneration + 1,
            "Generation should increment after load with URLRequest",
        )
    }

    @Test("Reload without content blockers increments generation")
    func reloadWithoutBlockersIncrementsGeneration() throws {
        let env = try ConcurrencyTestEnvironment()
        let webPage = env.makeWebPage()

        let initialGeneration = webPage.navigationGeneration

        // Trigger reload without content blockers
        webPage.reloadWithoutContentBlockers()

        #expect(
            webPage.navigationGeneration == initialGeneration + 1,
            "Generation should increment after reloadWithoutContentBlockers",
        )
    }
}

// MARK: - Tab Index Synchronization Tests

#if DEBUG
    @Suite("Tab Index Synchronization", .tags(.tabIndex), .serialized)
    @MainActor
    struct TabIndexSyncTests {
        @Test("Empty state has no index issues")
        func emptyStateHasNoIssues() throws {
            let env = try ConcurrencyTestEnvironment()

            let issues = env.browserState.verifyTabIndex()

            #expect(issues.isEmpty, "Empty state should have no index issues")
        }

        @Test("Indexed tabs are verified correctly")
        func indexedTabsVerifyCorrectly() throws {
            let env = try ConcurrencyTestEnvironment()

            // Create a space and add it to state
            let space = Space(name: "Test", iconName: "star")
            env.modelContext.insert(space)
            env.browserState.addSpace(space)

            // Create a tab
            let tab = try Tab(space: space, url: #require(URL(string: "https://example.com")))
            env.modelContext.insert(tab)
            space.tabs.append(tab)
            env.browserState.indexTab(tab)

            let issues = env.browserState.verifyTabIndex()

            #expect(issues.isEmpty, "Properly indexed tab should have no issues")
            #expect(env.browserState.tab(for: tab.id) === tab, "Tab should be retrievable by ID")
        }

        @Test("Missing index entry detected")
        func missingIndexEntryDetected() throws {
            let env = try ConcurrencyTestEnvironment()

            // Create a space and add it to state
            let space = Space(name: "Test", iconName: "star")
            env.modelContext.insert(space)
            env.browserState.addSpace(space)

            // Create a tab in the space but DON'T add to index
            let tab = try Tab(space: space, url: #require(URL(string: "https://example.com")))
            env.modelContext.insert(tab)
            space.tabs.append(tab)
            // Deliberately not calling browserState.indexTab(tab)

            let issues = env.browserState.verifyTabIndex()

            #expect(issues.count == 1, "Should detect one missing index entry")
            #expect(issues.first?.contains("not in tabIndex") == true)
        }

        @Test("Stale index entry detected")
        func staleIndexEntryDetected() throws {
            let env = try ConcurrencyTestEnvironment()

            // Create a space and add it to state
            let space = Space(name: "Test", iconName: "star")
            env.modelContext.insert(space)
            env.browserState.addSpace(space)

            // Create and index a tab
            let tab = try Tab(space: space, url: #require(URL(string: "https://example.com")))
            env.modelContext.insert(tab)
            space.tabs.append(tab)
            env.browserState.indexTab(tab)

            // Remove tab from space but leave in index (simulating desync)
            space.tabs.removeAll { $0.id == tab.id }
            // Deliberately not calling browserState.removeFromIndex(tab)

            let issues = env.browserState.verifyTabIndex()

            #expect(issues.count == 1, "Should detect one stale index entry")
            #expect(issues.first?.contains("not in any space") == true)
        }

        @Test("Rebuild index fixes desync")
        func rebuildIndexFixesDesync() throws {
            let env = try ConcurrencyTestEnvironment()

            // Create a space and add it to state
            let space = Space(name: "Test", iconName: "star")
            env.modelContext.insert(space)
            env.browserState.addSpace(space)

            // Create a tab but don't index it (simulating desync)
            let tab = try Tab(space: space, url: #require(URL(string: "https://example.com")))
            env.modelContext.insert(tab)
            space.tabs.append(tab)

            // Verify desync exists
            let issuesBefore = env.browserState.verifyTabIndex()
            #expect(!issuesBefore.isEmpty, "Should have desync before rebuild")

            // Rebuild index
            env.browserState.rebuildTabIndex()

            // Verify desync is fixed
            let issuesAfter = env.browserState.verifyTabIndex()
            #expect(issuesAfter.isEmpty, "Should have no issues after rebuild")
            #expect(env.browserState.tab(for: tab.id) === tab, "Tab should be retrievable after rebuild")
        }
    }
#endif

// MARK: - Navigation Stream Tests

@Suite("Navigation Stream Caching", .tags(.concurrency))
@MainActor
struct NavigationStreamTests {
    @Test("Navigations property returns cached stream")
    func navigationsReturnsCachedStream() throws {
        let env = try ConcurrencyTestEnvironment()
        let webPage = env.makeWebPage()

        // Access navigations multiple times
        _ = webPage.navigations
        _ = webPage.navigations
        _ = webPage.navigations

        // With caching, we should have at most 2 streams:
        // 1 from startNavigationObservation() in init
        // 1 from cached stream (returned for all subsequent accesses)
        // Without caching, we'd have 4+ entries.
        #expect(
            webPage.indefiniteNavigations.count <= 2,
            "Cached streams should not accumulate: found \(webPage.indefiniteNavigations.count) streams",
        )
    }

    @Test("CreateIndefiniteNavigationSequence creates new stream each time")
    func createSequenceCreatesNewStreams() throws {
        let env = try ConcurrencyTestEnvironment()
        let webPage = env.makeWebPage()

        let initialCount = webPage.indefiniteNavigations.count

        // Create new streams directly (bypassing cache)
        _ = webPage.createIndefiniteNavigationSequence()
        _ = webPage.createIndefiniteNavigationSequence()

        #expect(
            webPage.indefiniteNavigations.count == initialCount + 2,
            "Each createIndefiniteNavigationSequence call should add a stream",
        )
    }
}
