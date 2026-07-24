import SwiftData
import SwiftUI

/// A preview modifier that provides the complete Refrax environment for previews.
///
/// Use this modifier with the `#Preview` macro's `traits` parameter to ensure
/// all previews receive the required environment dependencies:
///
/// ```swift
/// #Preview(traits: .modifier(RefraxPreviewModifier())) {
///     MyView()
/// }
/// ```
///
/// The shared context is cached by Xcode, improving preview performance
/// when multiple previews use the same environment.
struct RefraxPreviewModifier: PreviewModifier {
    static func makeSharedContext() throws -> RefraxEnvironment {
        // MARK: - Foundation Layer

        let schema = Schema([
            Tab.self,
            TabPage.self,
            Space.self,
            TabGroup.self,
            HistoryEntry.self,
            TabSnapshot.self,
            TabSnapshotItem.self,
            BrowsingContext.self,
            SavedFilter.self,
            Bookmark.self,
            BookmarkFolder.self,
            BrowserSettings.self,
            CachedFavicon.self,
            SiteSettings.self,
            PrivacyProtectionSettings.self,
            CustomRedirect.self,
            AppRedirectRule.self,
            AppShortcut.self,
            DomainTimeEntry.self,
            DomainTimeLimit.self,
            CustomSearchEngine.self,
        ])

        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            allowsSave: true,
        )

        let modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        let modelContext = modelContainer.mainContext

        // MARK: - Settings & Simple State

        let settings = BrowserSettings.fetchOrCreate(in: modelContext)
        let dialogState = DialogState()
        let autoFillState = AutoFillState()
        let passwordsManager = PasswordsManager()
        let modifierKeysState = ModifierKeysState()

        // MARK: - Core Managers

        let faviconCache = FaviconCache(modelContainer: modelContainer)
        let siteSettingsManager = SiteSettingsManager(modelContext: modelContext)
        let historyManager = HistoryManager(modelContext: modelContext, settings: settings)
        let downloadManager = DownloadManager(modelContext: modelContext)
        let webInspectorManager = WebInspectorManager()
        let sharingCoordinator = SharingCoordinator()

        // MARK: - Browser State (Central Dependency)

        let browserState = BrowserState(
            modelContext: modelContext,
            settings: settings,
            historyManager: historyManager,
            faviconCache: faviconCache,
            dialogState: dialogState,
            autoFillState: autoFillState,
            siteSettingsManager: siteSettingsManager,
            passwordsManager: passwordsManager,
        )

        // MARK: - Tab Infrastructure

        let spaceManager = SpaceManager(state: browserState)
        let pagePool = WebPagePool(state: browserState)
        let groupManager = TabGroupManager(state: browserState)
        let windowManager = WindowManager(modelContainer: modelContainer)
        let undoRedoManager = UndoRedoManager()

        let referencePaneManager = ReferencePaneManager(
            state: browserState,
            pagePool: pagePool,
            windowManager: windowManager,
            undoRedoManager: undoRedoManager,
        )

        let archiveManager = TabArchiveManager(state: browserState, settings: settings)
        let autoArchiveManager = TabAutoArchiveManager(
            state: browserState,
            settings: settings,
            archiveManager: archiveManager,
        )

        let tabManager = TabManager(
            state: browserState,
            pagePool: pagePool,
            spaceManager: spaceManager,
            groupManager: groupManager,
            referencePaneManager: referencePaneManager,
        )

        // MARK: - Dependent Managers

        let bookmarksManager = BookmarksManager(
            modelContext: modelContext,
            tabManager: tabManager,
            historyManager: historyManager,
            faviconCache: faviconCache,
        )

        let extensionManager = ExtensionManager(state: browserState)
        let readerModeManager = ReaderModeManager(state: browserState)
        let historyActivityManager = HistoryActivityManager()

        let windowState = WindowState(settings: settings, browserState: browserState)

        let tabPreviewProvider = TabPreviewProvider(
            tabManager: tabManager,
            windowState: windowState,
        )
        let tabPreviewManager = TabPreviewManager(
            previewProvider: tabPreviewProvider,
            browserSettings: settings,
        )

        let agentChatManager = AgentChatManager(settings: settings)
        let customSearchEngineManager = CustomSearchEngineManager(modelContext: modelContext)

        let commandLensManager = CommandLensManager(
            tabManager: tabManager,
            historyManager: historyManager,
            windowState: windowState,
            browserSettings: settings,
            siteSettingsManager: siteSettingsManager,
            downloadManager: downloadManager,
            referencePaneManager: referencePaneManager,
            agentChatManager: agentChatManager,
            extensionManager: extensionManager,
            customSearchEngineManager: customSearchEngineManager,
        )

        let tabSwitcherManager = TabSwitcherManager(
            tabManager: tabManager,
            windowState: windowState,
            previewProvider: tabPreviewProvider,
        )

        let sidebarManagers = SidebarManagers(
            tabManager: tabManager,
            bookmarksManager: bookmarksManager,
            windowState: windowState,
            groupManager: groupManager,
            undoRedoManager: undoRedoManager,
            settings: settings,
        )
        
        browserState.downloadManager = downloadManager
        browserState.pagePool = pagePool
        browserState.extensionManager = extensionManager
        browserState.webPageConfiguration.webExtensionController = extensionManager.defaultController
        
        tabManager.bookmarksManager = bookmarksManager
        tabManager.undoRedoManager = undoRedoManager
        tabManager.windowManager = windowManager
        tabManager.archiveManager = archiveManager
        tabManager.autoArchiveManager = autoArchiveManager

        archiveManager.pagePool = pagePool
        autoArchiveManager.pagePool = pagePool
        autoArchiveManager.windowManager = windowManager
        
        groupManager.windowManager = windowManager
        groupManager.undoRedoManager = undoRedoManager
        groupManager.pagePool = pagePool
        
        spaceManager.pagePool = pagePool
        
        windowManager.tabManager = tabManager
        windowManager.bookmarksManager = bookmarksManager
        windowManager.historyManager = historyManager

        extensionManager.dataStoreManager = spaceManager.dataStoreManager
        
        undoRedoManager.tabManager = tabManager
        undoRedoManager.tabGroupManager = groupManager
        undoRedoManager.spaceManager = spaceManager

        pagePool.tabManager = tabManager
        pagePool.windowManager = windowManager
        pagePool.spaceDataStoreManager = spaceManager.dataStoreManager
        pagePool.completeSetup()

        // MARK: - Calendar, Clipboard & Reminders

        let calendarManager = CalendarManager(settings: settings)
        let clipboardMonitor = ClipboardMonitor(settings: settings)
        let pageReminderManager = PageReminderManager()
        let favoritePreviewManager = FavoritePreviewManager(
            tabManager: tabManager,
            windowManager: windowManager,
        )
        let cookieInspectorManager = CookieInspectorManager(
            spaceDataStoreManager: spaceManager.dataStoreManager,
        )
        let translationManager = TranslationManager()
        let offlineContentManager = OfflineContentManager()
        let processMemoryMonitor = ProcessMemoryMonitor(pagePool: pagePool)
        let tabHealthProvider = TabHealthProvider(tabManager: tabManager, pagePool: pagePool, memoryMonitor: processMemoryMonitor)

        // MARK: - Assemble Environment

        return RefraxEnvironment(
            modelContainer: modelContainer,
            browserState: browserState,
            windowState: windowState,
            historyManager: historyManager,
            historyActivityManager: historyActivityManager,
            settings: settings,
            siteSettingsManager: siteSettingsManager,
            autoFillState: autoFillState,
            tabManager: tabManager,
            pagePool: pagePool,
            spaceManager: spaceManager,
            groupManager: groupManager,
            referencePaneManager: referencePaneManager,
            archiveManager: archiveManager,
            autoArchiveManager: autoArchiveManager,
            windowManager: windowManager,
            bookmarksManager: bookmarksManager,
            extensionManager: extensionManager,
            dialogState: dialogState,
            tabPreviewProvider: tabPreviewProvider,
            tabPreviewManager: tabPreviewManager,
            downloadManager: downloadManager,
            webInspectorManager: webInspectorManager,
            sharingCoordinator: sharingCoordinator,
            passwordsManager: passwordsManager,
            commandLensManager: commandLensManager,
            modifierKeysState: modifierKeysState,
            tabSwitcherManager: tabSwitcherManager,
            sidebarManagers: sidebarManagers,
            cellEnvironment: SidebarCellEnvironment(
                layoutManager: sidebarManagers.layoutManager,
                dragCoordinator: sidebarManagers.dragCoordinator,
                selectionManager: sidebarManagers.selectionManager,
                tabManager: tabManager,
                windowState: windowState,
                browserState: browserState,
                dependencyContainer: sidebarManagers.dependencyContainer,
                geometryState: sidebarManagers.geometryState,
                modifierKeysState: modifierKeysState,
                tabPreviewManager: tabPreviewManager,
                pagePool: pagePool,
                historyManager: historyManager,
                groupManager: groupManager,
                filterManager: sidebarManagers.filterManager,
                settings: settings,
                mediaControlsManager: sidebarManagers.mediaControlsManager,
                autoArchiveManager: autoArchiveManager,
                windowManager: windowManager,
            ),
            readerModeManager: readerModeManager,
            undoRedoManager: undoRedoManager,
            calendarManager: calendarManager,
            clipboardMonitor: clipboardMonitor,
            screenshotCoordinator: ScreenshotCoordinator(),
            recordingCoordinator: RecordingCoordinator(),
            pageReminderManager: pageReminderManager,
            favoritePreviewManager: favoritePreviewManager,
            cookieInspectorManager: cookieInspectorManager,
            translationManager: translationManager,
            offlineContentManager: offlineContentManager,
            tabHealthProvider: tabHealthProvider,
            processMemoryMonitor: processMemoryMonitor,
            agentChatManager: agentChatManager,
            visualFeedbackManager: VisualFeedbackManager(),
            thoughtStreamStore: ThoughtStreamStore(),
            humanInterventionManager: HumanInterventionManager(),
            customSearchEngineManager: customSearchEngineManager,
            appUpdateManager: AppUpdateManager(settings: settings),
            guidedTourManager: GuidedTourManager(),
        )
    }

    func body(content: Content, context: RefraxEnvironment) -> some View {
        content.modifier(RefraxEnvironmentModifier(environment: context))
    }
}
