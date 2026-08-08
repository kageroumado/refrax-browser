import AppKit
import CloudKit
import CoreSpotlight
import SwiftData
import SwiftUI

// MARK: - AppDelegate

/// Refrax browser application delegate.
///
/// ## Initialization Phases
///
/// The app uses a three-phase initialization pattern to minimize time-to-first-frame:
///
/// ### Phase 1: Object Construction (`init`)
///
/// Creates all manager instances and wires dependencies. This phase:
/// - Performs no I/O except ModelContainer creation (unavoidable)
/// - Instantiates ~50 lightweight manager objects (constructors only allocate)
/// - Wires late-bound dependencies between managers
/// - Fires off async setup tasks that don't block the main thread
///
/// ### Phase 2: UI Setup (`applicationDidFinishLaunching`)
///
/// Sets up the user interface and system integrations:
/// - Menu bar construction
/// - URL scheme handler registration
/// - macOS Services menu registration
/// - Method swizzling for WebKit integration
/// - Window creation/restoration (deferred to allow first frame)
///
/// ### Phase 3: Deferred Maintenance (`startDeferredMaintenance`)
///
/// Heavy operations that run after the first frame renders:
/// - SwiftData cache warming
/// - WebKit GPU context initialization
/// - History maintenance on background actor
/// - Scheduled task registration (hourly cleanup, etc.)
/// - Spotlight indexing setup
///
/// ## Architecture
///
/// The app follows a manager-based architecture where observable managers are shared
/// across all windows via SwiftUI environment injection:
///
/// **Core State:**
/// - ``BrowserState``: Central state container for tabs, spaces, and browsing data
/// - ``BrowserSettings``: User preferences (persisted via SwiftData)
/// - ``WindowManager``: Coordinates window lifecycle and restoration
///
/// **Tab Management:**
/// - ``TabManager``: Tab CRUD, activation, and cross-window coordination
/// - ``SpaceManager``: Space isolation, data stores, and Focus mode integration
/// - ``WebPagePool``: Lazy WKWebView creation and process management
///
/// **Data Services:**
/// - ``HistoryManager``: Browsing history with SwiftData persistence
/// - ``BookmarksManager``: Bookmarks, favorites, and Reading List
/// - ``DownloadManager``: HTTP and BitTorrent downloads with pause/resume
///
/// Each window maintains its own ``WindowState`` for UI-specific state (sidebar width,
/// inspector visibility) while sharing the same underlying data through the managers.
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Storage

    /// The storage mode determined at launch.
    let storageMode: StorageMode
    
    let modelContainer: ModelContainer

    // MARK: - Dependencies

    // State
    let browserState: BrowserState
    let modifierKeysState: ModifierKeysState
    let autoFillState: AutoFillState
    let dialogState: DialogState
    let settings: BrowserSettings
    
    // Tab managers
    let tabManager: TabManager
    let pagePool: WebPagePool
    let spaceManager: SpaceManager
    let groupManager: TabGroupManager
    let referencePaneManager: ReferencePaneManager
    let archiveManager: TabArchiveManager
    let autoArchiveManager: TabAutoArchiveManager

    // Observers and schedulers
    let activationObserver: AppActivationObserver
    let systemSleepObserver: SystemSleepObserver
    let scheduledTasksManager: ScheduledTasksManager

    // Other managers
    let windowManager: WindowManager
    let menuBarManager: MenuBarManager
    let historyManager: HistoryManager
    let historyMaintenanceService: HistoryMaintenanceService
    let historyActivityManager: HistoryActivityManager
    let bookmarksManager: BookmarksManager
    let siteSettingsManager: SiteSettingsManager
    let downloadManager: DownloadManager
    let passwordsManager: PasswordsManager
    let undoRedoManager: UndoRedoManager
    let extensionManager: ExtensionManager
    let readerModeManager: ReaderModeManager
    let autoConsentManager: AutoConsentManager
    let contentScriptManager: ContentScriptManager
    let keyboardShortcutsManager: KeyboardShortcutsManager
    let processAudioTapManager: ProcessAudioTapManager
    let tabHealthProvider: TabHealthProvider
    let processMemoryMonitor: ProcessMemoryMonitor
    let calendarManager: CalendarManager
    let clipboardMonitor: ClipboardMonitor
    let pageReminderManager: PageReminderManager
    let favoritePreviewManager: FavoritePreviewManager
    let cookieInspectorManager: CookieInspectorManager
    let userStyleManager: UserStyleManager
    let userScriptManager: UserScriptManager
    let userScriptStorageManager: UserScriptStorageManager
    let translationManager: TranslationManager
    let offlineContentManager: OfflineContentManager
    let servicesProvider: ServicesProvider
    let webInspectorManager: WebInspectorManager
    let agentChatManager: AgentChatManager
    let visualFeedbackManager: VisualFeedbackManager
    let thoughtStreamStore: ThoughtStreamStore
    let humanInterventionManager: HumanInterventionManager
    let customSearchEngineManager: CustomSearchEngineManager

    // Control interface
    let controlServer: RefraxControlServer
    let controlAccessManager: ControlAccessManager
    let controlHost: RefraxControlHost

    // Apple system integrations
    let appleIntegrationManager: AppleIntegrationManager
    let widgetDataManager: WidgetDataManager

    // Services
    let faviconCache: FaviconCache
    let sharingCoordinator: SharingCoordinator

    // Feedback & Updates
    let feedbackManager: FeedbackManager
    let appUpdateManager: AppUpdateManager

    // iCloud Sync
    /// Separate container for sync metadata (CloudKit system fields, history tokens).
    private(set) var syncContainer: ModelContainer?

    /// Orchestrates iCloud sync. Nil if iCloud is unavailable or sync is disabled.
    private(set) var syncCoordinator: SyncCoordinator?

    /// Handles iCloud account change UI (sign-out/switch sheets).
    let syncAccountChangeHandler = SyncAccountChangeHandler()
    
    /// Initialized lazily to reduce launch times.
    lazy var settingsWindowController = SettingsWindowController(
        environment: SettingsEnvironment(
            modelContainer: modelContainer,
            settings: settings,
            browserState: browserState,
            historyManager: historyManager,
            autoFillState: autoFillState,
            siteSettingsManager: siteSettingsManager,
            extensionManager: extensionManager,
            bookmarksManager: bookmarksManager,
            tabManager: tabManager,
            calendarManager: calendarManager,
            cookieInspectorManager: cookieInspectorManager,
            scheduledTasksManager: scheduledTasksManager,
            archiveManager: archiveManager,
            autoArchiveManager: autoArchiveManager,
            downloadManager: downloadManager,
            customSearchEngineManager: customSearchEngineManager,
            passwordsManager: passwordsManager,
        ),
    )

    /// Dedicated History window controller.
    lazy var historyWindowController = HistoryWindowController(
        historyManager: historyManager,
        tabManager: tabManager,
        windowManager: windowManager,
        modelContainer: modelContainer,
    )

    /// Dedicated Bookmarks window controller.
    lazy var bookmarksWindowController = BookmarksWindowController(
        bookmarksManager: bookmarksManager,
        tabManager: tabManager,
        windowManager: windowManager,
        modelContainer: modelContainer,
    )

    /// Dedicated Downloads window controller.
    lazy var downloadsWindowController = DownloadsWindowController(
        downloadManager: downloadManager,
        modelContainer: modelContainer,
    )

    /// Dedicated Passwords window controller.
    lazy var passwordsWindowController = PasswordsWindowController(
        passwordsManager: passwordsManager,
    )

    /// Dedicated Feedback window controller.
    lazy var feedbackWindowController = FeedbackWindowController(
        feedbackManager: feedbackManager,
    )

    /// Acknowledgements window controller.
    lazy var acknowledgementsWindowController = AcknowledgementsWindowController()

    /// About window controller.
    lazy var aboutWindowController = AboutWindowController()

    /// License Agreement window controller.
    lazy var licenseAgreementWindowController = LicenseAgreementWindowController()

    /// Onboarding window controller, active only during first-launch flow.
    private var onboardingWindowController: OnboardingWindowController?

    // MARK: - Initialization

    /// Creates the application delegate and all manager instances.
    ///
    /// This initializer follows a strict pattern to minimize launch time:
    ///
    /// 1. **Database setup** - ModelContainer creation (only unavoidable I/O)
    /// 2. **Manager instantiation** - Lightweight constructors, no side effects
    /// 3. **Dependency wiring** - Late-bound references between managers
    /// 4. **Async setup** - Fire-and-forget tasks for content blocking, extensions
    ///
    /// Heavy operations like WebKit initialization, history maintenance, and
    /// Spotlight indexing are deferred to ``startDeferredMaintenance()``.
    ///
    /// - Parameter arguments: Parsed command-line arguments from ``CommandLine.Arguments``.
    init(arguments: CommandLine.Arguments) {
        self.storageMode = StorageConfiguration.resolveMode(from: arguments)

        let schema = Schema(versionedSchema: SchemaV1.self)

        let modelConfiguration = StorageConfiguration.createModelConfiguration(
            schema: schema,
            mode: storageMode,
        )

        let preMigrationSnapshot = DatabaseRecoveryService.snapshotSchema(storeURL: modelConfiguration.url)

        do {
            self.modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: RefraxMigrationPlan.self,
                configurations: [modelConfiguration],
            )
        } catch {
            Self.handleDatabaseLoadFailure(error: error, storeURL: modelConfiguration.url)
        }

        DatabaseRecoveryService.logMigrationChanges(preMigration: preMigrationSnapshot, schema: schema)

        // Sync metadata store (separate from main app data)
        do {
            let syncSchema = Schema([SyncRecord.self, SyncState.self])
            let syncConfig = ModelConfiguration(
                "SyncMetadata",
                schema: syncSchema,
                url: Directories.appStorage.appendingPathComponent("sync.store"),
                allowsSave: true,
                cloudKitDatabase: .none
            )
            self.syncContainer = try ModelContainer(for: syncSchema, configurations: [syncConfig])
        } catch {
            Logger.error("Failed to create sync metadata store: \(error)", category: Logger.storage)
            self.syncContainer = nil
        }

        self.settings = BrowserSettings.fetchOrCreate(in: modelContainer.mainContext)

        // Restore activation status after a full reset (Tier 4).
        // The reset writes activation info to a separate UserDefaults suite before
        // wiping the main suite and database. On relaunch, we restore it here.
        let restoreSuite = UserDefaults(suiteName: "website.refrax.browser.activation-restore")
        if let restored = restoreSuite?.object(forKey: "isActivated") as? Bool, restored {
            settings.isActivated = true
            settings.activationCode = restoreSuite?.string(forKey: "activationCode")
            restoreSuite?.removePersistentDomain(forName: "website.refrax.browser.activation-restore")
            restoreSuite?.synchronize()
            Logger.info("Restored activation status after full reset", category: Logger.storage)
        }

        self.siteSettingsManager = SiteSettingsManager(modelContext: modelContainer.mainContext)
        self.autoFillState = AutoFillState()
        self.dialogState = DialogState()
        self.faviconCache = FaviconCache(modelContainer: modelContainer)
        self.historyManager = HistoryManager(modelContext: modelContainer.mainContext, settings: settings)
        self.customSearchEngineManager = CustomSearchEngineManager(modelContext: modelContainer.mainContext)
        settings.customSearchEngineManager = customSearchEngineManager
        self.historyMaintenanceService = HistoryMaintenanceService(
            historyManager: historyManager,
            modelContainer: modelContainer,
            settings: settings,
        )
        self.historyActivityManager = HistoryActivityManager()
        self.passwordsManager = PasswordsManager()
        self.sharingCoordinator = SharingCoordinator()
        self.feedbackManager = FeedbackManager(settings: settings)
        self.appUpdateManager = AppUpdateManager(settings: settings)
        self.modifierKeysState = ModifierKeysState()
        self.downloadManager = DownloadManager(modelContext: modelContainer.mainContext)

        // Apply custom download directory from settings
        if let customPath = settings.customDownloadDirectory {
            downloadManager.downloadDirectory = URL(fileURLWithPath: customPath)
        }

        // Apply aria2 settings
        downloadManager.applySettings(from: settings)

        self.browserState = BrowserState(
            modelContext: modelContainer.mainContext,
            settings: settings,
            historyManager: historyManager,
            faviconCache: faviconCache,
            dialogState: dialogState,
            autoFillState: autoFillState,
            siteSettingsManager: siteSettingsManager,
            passwordsManager: passwordsManager,
        )

        self.windowManager = WindowManager(modelContainer: modelContainer)
        self.spaceManager = SpaceManager(state: browserState)
        self.pagePool = WebPagePool(state: browserState)
        self.groupManager = TabGroupManager(state: browserState)
        self.readerModeManager = ReaderModeManager(state: browserState)
        self.undoRedoManager = UndoRedoManager()
        self.contentScriptManager = ContentScriptManager(state: browserState)
        self.autoConsentManager = AutoConsentManager(state: browserState)
        self.extensionManager = ExtensionManager(state: browserState)
        self.keyboardShortcutsManager = KeyboardShortcutsManager(windowManager: windowManager)
        
        self.menuBarManager = MenuBarManager(
            windowManager: windowManager,
            undoRedoManager: undoRedoManager,
        )
        
        self.referencePaneManager = ReferencePaneManager(
            state: browserState,
            pagePool: pagePool,
            windowManager: windowManager,
            undoRedoManager: undoRedoManager,
        )

        self.activationObserver = AppActivationObserver()
        self.systemSleepObserver = SystemSleepObserver()
        self.archiveManager = TabArchiveManager(state: browserState, settings: settings)
        self.autoArchiveManager = TabAutoArchiveManager(
            state: browserState,
            settings: settings,
            archiveManager: archiveManager,
        )
        self.scheduledTasksManager = ScheduledTasksManager(activationObserver: activationObserver)

        self.tabManager = TabManager(
            state: browserState,
            pagePool: pagePool,
            spaceManager: spaceManager,
            groupManager: groupManager,
            referencePaneManager: referencePaneManager,
        )

        self.bookmarksManager = BookmarksManager(
            modelContext: modelContainer.mainContext,
            tabManager: tabManager,
            historyManager: historyManager,
            faviconCache: faviconCache,
        )
        
        self.processAudioTapManager = ProcessAudioTapManager(tabManager: tabManager)
        self.processMemoryMonitor = ProcessMemoryMonitor(pagePool: pagePool)
        self.tabHealthProvider = TabHealthProvider(tabManager: tabManager, pagePool: pagePool, memoryMonitor: processMemoryMonitor)
        self.calendarManager = CalendarManager(settings: settings)
        self.clipboardMonitor = ClipboardMonitor(settings: settings)
        self.pageReminderManager = PageReminderManager()
        self.favoritePreviewManager = FavoritePreviewManager(
            tabManager: tabManager,
            windowManager: windowManager,
        )
        self.cookieInspectorManager = CookieInspectorManager(
            spaceDataStoreManager: spaceManager.dataStoreManager,
        )
        self.userStyleManager = UserStyleManager(modelContext: modelContainer.mainContext)
        self.userScriptStorageManager = UserScriptStorageManager(modelContainer: modelContainer)
        self.userScriptManager = UserScriptManager(modelContext: modelContainer.mainContext)
        self.translationManager = TranslationManager()
        self.offlineContentManager = OfflineContentManager()
        self.webInspectorManager = WebInspectorManager()
        self.agentChatManager = AgentChatManager(settings: settings)
        self.visualFeedbackManager = VisualFeedbackManager()
        self.humanInterventionManager = HumanInterventionManager()
        self.thoughtStreamStore = ThoughtStreamStore()
        agentChatManager.thoughtStreamStore = thoughtStreamStore
        self.servicesProvider = ServicesProvider(
            tabManager: tabManager,
            bookmarksManager: bookmarksManager,
            downloadManager: downloadManager,
            windowManager: windowManager,
            settings: settings,
        )

        self.appleIntegrationManager = AppleIntegrationManager(
            browserState: browserState,
            tabManager: tabManager,
            bookmarksManager: bookmarksManager,
            historyManager: historyManager,
            windowManager: windowManager,
        )

        self.widgetDataManager = WidgetDataManager(
            browserState: browserState,
            tabManager: tabManager,
            pagePool: pagePool,
            windowManager: windowManager,
        )

        // Wire up late-bound dependencies
        browserState.downloadManager = downloadManager
        browserState.pagePool = pagePool
        browserState.extensionManager = extensionManager
        browserState.webInspectorManager = webInspectorManager
        browserState.webPageConfiguration.webExtensionController = extensionManager.defaultController
        
        tabManager.bookmarksManager = bookmarksManager
        tabManager.undoRedoManager = undoRedoManager
        tabManager.windowManager = windowManager

        bookmarksManager.offlineContentManager = offlineContentManager
        tabManager.archiveManager = archiveManager
        tabManager.autoArchiveManager = autoArchiveManager

        feedbackManager.browserState = browserState
        feedbackManager.extensionManager = extensionManager

        archiveManager.pagePool = pagePool
        archiveManager.activationObserver = activationObserver

        historyActivityManager.activationObserver = activationObserver
        historyActivityManager.systemSleepObserver = systemSleepObserver

        browserState.spaceLockManager.activationObserver = activationObserver
        browserState.spaceLockManager.systemSleepObserver = systemSleepObserver

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
        extensionManager.activationObserver = activationObserver
        
        undoRedoManager.tabManager = tabManager
        undoRedoManager.tabGroupManager = groupManager
        undoRedoManager.spaceManager = spaceManager

        pagePool.tabManager = tabManager
        pagePool.windowManager = windowManager
        pagePool.spaceDataStoreManager = spaceManager.dataStoreManager
        pagePool.completeSetup()

        self.controlServer = RefraxControlServer(
            windowManager: windowManager,
            tabManager: tabManager,
            spaceManager: spaceManager,
            pagePool: pagePool,
            browserState: browserState,
            referencePaneManager: referencePaneManager,
            groupManager: groupManager,
            undoRedoManager: undoRedoManager,
            bookmarksManager: bookmarksManager,
            historyManager: historyManager,
            siteSettingsManager: siteSettingsManager,
            webInspectorManager: webInspectorManager,
            visualFeedbackManager: visualFeedbackManager,
            browserSettings: settings,
            humanInterventionManager: humanInterventionManager,
        )
        self.controlAccessManager = ControlAccessManager(settings: settings)
        self.controlHost = RefraxControlHost(server: controlServer, accessManager: controlAccessManager)

        // Configure user style manager with dependencies
        userStyleManager.configure(
            scriptRegistry: browserState.scriptRegistry,
            userContentController: browserState.webPageConfiguration.userContentController,
        )

        // Configure user script manager with dependencies
        userScriptManager.configure(
            scriptRegistry: browserState.scriptRegistry,
            userContentController: browserState.webPageConfiguration.userContentController,
            storageManager: userScriptStorageManager,
        )

        // Install frame content extraction for cross-origin iframe support.
        // Must be installed before any web pages are created so the script
        // is injected into all frames from the start.
        FrameContentExtractor.shared.install(on: browserState.webPageConfiguration.userContentController)

        super.init()

        // Tiered setup pattern: Fire-and-forget tasks at appropriate priorities.
        // This allows the first frame to render without waiting for any setup.

        // Configure Claude Direct tool system (fast — just 3 actor hops)
        Task {
            await self.agentChatManager.configureToolSystem(
                controlServer: self.controlServer,
                windowManager: self.windowManager,
                userStyleManager: self.userStyleManager,
                pagePool: self.pagePool,
            ) { [weak windowManager] in
                guard let windowState = windowManager?.activeWindowController?.windowState else { return nil }
                return BrowserContextProvider.extractContext(from: windowState)
            }
        }

        // Tier 1: Fast setups (~5ms total) - reader mode and auto consent
        Task(priority: .userInitiated) {
            async let reader: Void = self.readerModeManager.setup()
            async let consent: Void = self.autoConsentManager.setup()
            _ = await (reader, consent)
        }

        // Tier 2: Content blocking (50-200ms) - needed before first navigation
        Task(priority: .userInitiated) {
            await self.contentScriptManager.setup()
        }

        // Tier 3: Extensions (variable, potentially slow) - not needed immediately
        Task(priority: .utility) {
            await self.extensionManager.setup()
        }
    }

    // MARK: - Lifecycle

    /// Called after the application has finished launching.
    ///
    /// This is Phase 2 of initialization. The run loop is now active, and we can:
    /// - Set up the menu bar and register URL handlers
    /// - Install method swizzles for WebKit integration
    /// - Start observers for app activation and system sleep
    /// - Begin window restoration or create the first window
    ///
    /// Window content loading and heavy maintenance are deferred to Phase 3
    /// via ``startDeferredMaintenance()`` to allow the first frame to render.
    func applicationDidFinishLaunching(_: Notification) {
        CrashMonitor.markLaunched()
        logStorageMode()
        setupMenuBar()
        registerURLHandler()
        registerServices()
        setupSwizzling()
        startUtilitySetup()
        historyActivityManager.start()
        browserState.spaceLockManager.start()
        runLegacyAgentCredentialMigration()

        // Clean up any stale aria2 daemon from a previous crash
        Task(priority: .utility) {
            await Aria2Daemon().cleanupStaleDaemon()
        }

        #if DEBUG
            // Debug builds skip onboarding so fresh launches (--in-memory
            // especially) land directly in a browsing window.
            browserState.settings.hasCompletedOnboarding = true
            browserState.settings.isActivated = true
        #endif

        if !browserState.settings.hasCompletedOnboarding {
            // Migration for existing alpha testers: if they have browsing data
            // but no onboarding flag (pre-onboarding install), skip onboarding.
            // Only run this once — don't re-trigger after a debug reset.
            if !browserState.settings.hasRunOnboardingMigration {
                browserState.settings.hasRunOnboardingMigration = true

                let context = modelContainer.mainContext
                var descriptor = FetchDescriptor<TabPage>()
                descriptor.fetchLimit = 1
                let hasExistingData = (try? context.fetchCount(descriptor)) ?? 0 > 0

                if hasExistingData {
                    browserState.settings.hasCompletedOnboarding = true
                    browserState.settings.isActivated = true
                }
            }

            if !browserState.settings.hasCompletedOnboarding {
                showOnboarding()
                return
            }
        }

        // UI Test mode: Skip normal initialization and create test data
        if UITestSetup.isUITestMode {
            setupForUITests()
            return
        }

        // Check if windows were restored by AppKit (RefraxWindowRestoration)
        // If so, didDecodeRestorableState already applied sidebar/inspector/colors
        let isFirstLaunch = !windowManager.hasWindows
        if isFirstLaunch {
            prepareForFirstLaunch()
        } else {
            prepareForRestoration()
        }
    }
    
    /// Shows the onboarding window for first-launch activation.
    ///
    /// The main browser window is not created until onboarding completes.
    private func showOnboarding() {
        let controller = OnboardingWindowController()
        controller.showWindow(
            settings: browserState.settings,
            bookmarksManager: bookmarksManager,
            historyManager: historyManager,
            passwordsManager: passwordsManager,
            modelContainer: modelContainer
        )
        controller.onCompleted = { [weak self] in
            guard let self else { return }
            browserState.settings.hasCompletedOnboarding = true
            onboardingWindowController?.closeWindow()
            onboardingWindowController = nil

            prepareForFirstLaunch()
        }
        onboardingWindowController = controller
    }

    /// Handles first launch when no windows exist to restore.
    ///
    /// Uses a placeholder pattern to show UI immediately:
    /// 1. Create a temporary in-memory space (no database access)
    /// 2. Show the window with the temporary space (first frame renders)
    /// 3. Asynchronously load persisted data and replace the temporary space
    ///
    /// This avoids blocking the first frame on potentially slow database queries.
    private func prepareForFirstLaunch() {
        let tempSpace = tabManager.createTemporarySpace()
        let controller = windowManager.createWindowWithoutInitialization()
        tabManager.initializeWindow(controller.windowState, with: tempSpace)

        DispatchQueue.main.async { [self] in
            // Guard against window being closed before restoration completes
            guard windowManager.windowControllers.contains(where: { $0 === controller }) else {
                return
            }

            // Replace temporary space with persisted one
            tabManager.state.clearSpaces()
            let restoredSpace = tabManager.restoreFromPersistence()

            // Re-initialize window with persisted space
            controller.windowState.activeSpaceID = restoredSpace.id
            controller.finalizeInitialization()

            // Perform deferred history maintenance after first frame
            startDeferredMaintenance()
        }
    }
    
    /// Handles app launch when AppKit has restored windows.
    ///
    /// Window chrome (colors, sidebar width, inspector state) was already applied
    /// by `didDecodeRestorableState` during window restoration. This method:
    /// 1. Defers to the next run loop iteration (allows first frame to render)
    /// 2. Loads tab data from the database
    /// 3. Finalizes window initialization
    private func prepareForRestoration() {
        DispatchQueue.main.async { [self] in
            tabManager.restoreFromPersistence()

            for controller in windowManager.windowControllers {
                controller.finalizeInitialization()
            }

            // Perform deferred history maintenance after first frame
            startDeferredMaintenance()
        }
    }

    /// Starts deferred maintenance tasks that shouldn't block app launch.
    ///
    /// Called after the first frame renders to perform heavy operations:
    /// - History maintenance (orphan cleanup, frequent destinations)
    /// - Bookmarks favorites cache loading
    /// - Downloads history loading
    /// - WebKit warm-up (GPU/process initialization)
    /// - Scheduled tasks (archive expiration)
    private func startDeferredMaintenance() {
        // Load deferred SwiftData caches
        bookmarksManager.performDeferredSetup()
        downloadManager.performDeferredSetup()
        userStyleManager.performDeferredSetup()

        // Initialize background actors for off-main-thread persistence
        browserState.domainTimeTracker.initializeBackgroundActor(modelContainer: modelContainer)

        // Warm up WebKit to pre-initialize GPU context
        // This moves the ~100-300ms first-WKWebView cost away from user interaction
        pagePool.warmUpWebKit()

        // History maintenance on background actor
        Task {
            await historyManager.performDeferredMaintenance(modelContainer: modelContainer)
        }

        // Start scheduled tasks for archive expiration and auto-archive rules
        let archiveManager = archiveManager
        let autoArchiveManager = autoArchiveManager
        let modelContext = modelContainer.mainContext
        scheduledTasksManager.registerTask { @MainActor in
            archiveManager.clearExpiredTabs(context: modelContext)
        }
        scheduledTasksManager.registerTask { @MainActor in
            await autoArchiveManager.executeRules(context: modelContext)
        }
        let domainTimeTracker = browserState.domainTimeTracker
        scheduledTasksManager.registerTask { @MainActor in
            domainTimeTracker.pruneOldEntries()
        }
        let historyMaintenanceService = historyMaintenanceService
        scheduledTasksManager.registerTask { @MainActor in
            await historyMaintenanceService.performMaintenanceIfNeeded()
        }
        let contentBlockingManager = contentScriptManager.contentBlockingManager
        scheduledTasksManager.registerTask { @MainActor in
            await contentBlockingManager.checkAndUpdateIfNeeded()
        }
        let extensionUpdateChecker = extensionManager.updateChecker
        scheduledTasksManager.registerTask { @MainActor in
            await extensionUpdateChecker.checkAllIfNeeded()
        }
        let widgetDataManager = widgetDataManager
        scheduledTasksManager.registerTask { @MainActor in
            widgetDataManager.performScheduledUpdate()
        }
        let pagePool = pagePool
        scheduledTasksManager.registerTask { @MainActor in
            pagePool.evictIdlePages()
        }
        // Log rotation
        scheduledTasksManager.registerTask { @MainActor in
            await PersistentLogWriter.shared.pruneOldLogs()
        }

        // Post-update detection (shows notification if app was just updated)
        appUpdateManager.detectPostUpdate()

        // App update checking
        let appUpdateManager = appUpdateManager
        scheduledTasksManager.registerTask { @MainActor in
            await appUpdateManager.checkForUpdates()
        }

        // Database backup
        let storeURL = modelContainer.configurations.first.flatMap(\.url) ?? Directories.appStorage.appendingPathComponent("default.store")
        scheduledTasksManager.registerTask { @MainActor in
            DatabaseBackupService.performScheduledBackup(storeURL: storeURL)
            DatabaseBackupService.pruneOldBackups()
        }

        // Crash detection — auto-submit crash report if previous session crashed
        if CrashMonitor.didCrashPreviously() {
            let crashReports = CrashMonitor.collectCrashReports()
            CrashMonitor.clearSentinel()

            if !crashReports.isEmpty {
                Logger.warning(
                    "Previous session terminated abnormally — sending crash report (\(crashReports.count) report(s))",
                    category: Logger.system
                )
                Task.detached(priority: .utility) { [appUpdateManager] in
                    await FeedbackSubmissionService.submitAutomaticCrashReport(crashReports: crashReports)
                    CrashMonitor.markReportsSent(crashReports)
                    await MainActor.run {
                        appUpdateManager.crashReportSent = true
                    }
                }
            }
        }

        scheduledTasksManager.start()

        // Initialize iCloud sync if enabled and available
        if settings.iCloudSyncEnabled, let syncContainer {
            Task {
                do {
                    let status = try await CKContainer(
                        identifier: "iCloud.website.refrax.browser"
                    ).accountStatus()
                    if status == .available {
                        self.syncCoordinator = SyncCoordinator(
                            mainContainer: self.modelContainer,
                            syncContainer: syncContainer
                        )
                    }
                } catch {
                    Logger.error("Failed to initialize sync: \(error)", category: Logger.storage)
                }
            }
        }

        // Start observing settings changes for archive threshold tracking
        autoArchiveManager.startObservingSettings()

        // Apple system integrations (Spotlight indexing)
        appleIntegrationManager.performDeferredSetup()

        // Widget data: initial update, then scheduled hourly
        widgetDataManager.performInitialUpdate()

        // Control server: wire authorization prompt and start if enabled
        controlAccessManager.onAuthorizationPrompt = { identity in
            ControlAccessPrompt.prompt(for: identity)
        }
        controlAccessManager.autoAllowRefraxCTL()
        if settings.controlAccessMode != .off {
            Task { await controlHost.start() }
            CLISkillInstaller.install()
            refreshCLIHelperInstall()
        }
        TelemetryService.sendHeartbeatIfNeeded(settings: settings)

        observeControlAccessMode()
    }

    /// Returns `false` to keep the app running when all windows close.
    ///
    /// Refrax follows the Safari/Chrome pattern where closing all windows doesn't
    /// quit the app. Users can reopen windows via Dock click or Cmd+N.
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        false
    }

    /// Handles Dock icon click when no windows are visible.
    ///
    /// Minimized windows count as not visible here, so surface an existing
    /// window (deminiaturizing if needed) before falling back to creating a
    /// new one — otherwise a Dock click with a minimized window would create
    /// a duplicate instead of restoring it.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag, browserState.settings.hasCompletedOnboarding else { return true }

        let controller = windowManager.activeWindowController ?? windowManager.windowControllers.first
        if let window = controller?.window {
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            window.makeKeyAndOrderFront(nil)
        } else {
            windowManager.createWindow()
        }
        return true
    }

    /// Called when the app is about to lose focus.
    ///
    /// Security-sensitive cleanup:
    /// - Clears generated passwords from memory (limits exposure window)
    /// - Invalidates Handoff activity (re-advertised lazily on tab interaction)
    func applicationWillResignActive(_: Notification) {
        GeneratedPasswordStore.shared.clearAll()
        browserState.handoffManager.invalidateActivity()
    }

    /// Called just before the app terminates.
    ///
    /// Performs final cleanup:
    /// - Persists the active window's geometry for future new windows
    /// - Schedules a save of each window's active space
    /// - Marks a clean shutdown for crash detection
    /// - Gracefully stops the control server and the aria2 daemon
    func applicationWillTerminate(_: Notification) {
        // Quitting skips per-window close notifications, so capture the active
        // window's geometry here for new windows created after the next launch
        if let controller = windowManager.activeWindowController,
           let window = controller.window,
           !window.styleMask.contains(.fullScreen) {
            WindowGeometryStore.save(
                SavedWindowGeometry(
                    frame: window.frame,
                    sidebarWidth: controller.windowState.sidebarThickness,
                    isSidebarCollapsed: controller.windowState.isSidebarCollapsed,
                    inspectorWidth: controller.windowState.referencePaneDockedWidth,
                ),
                screen: window.screen,
            )
        }

        for controller in windowManager.windowControllers {
            if let space = controller.windowState.activeSpace {
                spaceManager.saveSpaceState(space, windowState: controller.windowState)
            }
        }

        CrashMonitor.markCleanShutdown()

        Task { await controlHost.stop() }

        Task {
            await Aria2DownloadCoordinator.shared.stopDaemon()
        }
    }

    /// Enables secure coding for window state restoration.
    ///
    /// Required for modern AppKit state restoration. All restored objects must
    /// conform to `NSSecureCoding`.
    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }

    // MARK: - Control Access Mode Observation

    /// Observes control access mode changes to start/stop the socket server at runtime.
    private func observeControlAccessMode() {
        let modeChanges = Observations { self.settings.controlAccessModeRaw }
        Task { @MainActor [weak self] in
            for await _ in modeChanges {
                guard let self else { return }
                let mode = settings.controlAccessMode
                if mode == .off {
                    await controlHost.stop()
                } else {
                    await controlHost.start()
                    CLISkillInstaller.install()
                    refreshCLIHelperInstall()
                }
            }
        }
    }

    /// Silently installs or updates the `refrax-ctl` helper when `/usr/local/bin`
    /// is user-writable, and surfaces the sidebar/Settings install affordance
    /// when administrator privileges would be required. Never prompts on its own.
    private func refreshCLIHelperInstall() {
        Task { [browserState] in
            let status = await RefraxControlHost.ensureCLIHelperInstalled()
            browserState.cliHelperNeedsPrivilegedInstall = status.needsInstall
        }
    }

    // MARK: - Legacy Agent Credential Migration

    /// Removes OAuth tokens stored by releases that supported Sign in with Claude.
    ///
    /// The OAuth path has been removed; the Anthropic API is now reached only
    /// through user-supplied API keys. This runs once per install to evict the
    /// three legacy keychain accounts (`anthropic-oauth-access`,
    /// `anthropic-oauth-refresh`, `anthropic-oauth-expiry`).
    private func runLegacyAgentCredentialMigration() {
        let migrationKey = "website.refrax.migration.removedClaudeOAuth"
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: migrationKey) else { return }

        ClaudeCredentialStore.deleteLegacyOAuthCredentials()
        defaults.set(true, forKey: migrationKey)
    }

    // MARK: - URL Handling

    private func registerURLHandler() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL),
        )
    }

    private func registerServices() {
        servicesProvider.register()
    }

    @objc
    private func handleGetURLEvent(_ event: NSAppleEventDescriptor, replyEvent _: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            return
        }

        // Handle magnet: links specially
        if url.scheme == "magnet" {
            handleMagnetURL(url)
            return
        }

        // Detect source app before Refrax activates
        let sourceApp = ExternalURLHandler.detectSourceApp()
        windowManager.openExternalURL(url, sourceAppBundleID: sourceApp)
    }

    // MARK: - BitTorrent Handling

    /// Handles a magnet: URL.
    private func handleMagnetURL(_ url: URL) {
        guard settings.enableBitTorrent else {
            showBitTorrentDisabledAlert(for: "magnet link")
            return
        }

        Task {
            do {
                try await downloadManager.startMagnetDownload(magnetURL: url)
                Logger.info("Started magnet download: \(url.absoluteString.prefix(100))", category: Logger.downloads)
            } catch {
                Logger.error("Failed to start magnet download: \(error)", category: Logger.downloads)
                showDownloadErrorAlert(error)
            }
        }
    }

    /// Handles a .torrent file.
    private func handleTorrentFile(_ fileURL: URL) {
        guard settings.enableBitTorrent else {
            showBitTorrentDisabledAlert(for: "torrent file")
            return
        }

        Task {
            do {
                try await downloadManager.startTorrentDownload(torrentFile: fileURL)
                Logger.info("Started torrent download: \(fileURL.lastPathComponent)", category: Logger.downloads)
            } catch {
                Logger.error("Failed to start torrent download: \(error)", category: Logger.downloads)
                showDownloadErrorAlert(error)
            }
        }
    }

    /// Shows an alert when BitTorrent is not enabled.
    private func showBitTorrentDisabledAlert(for type: String) {
        let alert = NSAlert()
        alert.messageText = "BitTorrent Not Enabled"
        alert.informativeText = "To open this \(type), enable BitTorrent in Settings > General > Advanced Downloads."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Cancel")

        if alert.runModal() == .alertFirstButtonReturn {
            settingsWindowController.showWindow()
        }
    }

    /// Shows an error alert for download failures.
    @MainActor
    private func showDownloadErrorAlert(_ error: any Error) {
        let alert = NSAlert()
        alert.messageText = "Download Failed"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - Document Opening

    func application(_: NSApplication, openFile filename: String) -> Bool {
        let fileURL = URL(fileURLWithPath: filename)

        // Handle .torrent files specially
        if fileURL.pathExtension.lowercased() == "torrent" {
            handleTorrentFile(fileURL)
            return true
        }

        // File opens are typically from Finder, detect source
        let sourceApp = ExternalURLHandler.detectSourceApp()
        windowManager.openExternalURL(fileURL, sourceAppBundleID: sourceApp)
        return true
    }

    func application(_: NSApplication, openFiles filenames: [String]) {
        // Detect source app once for all files
        let sourceApp = ExternalURLHandler.detectSourceApp()
        for filename in filenames {
            let fileURL = URL(fileURLWithPath: filename)

            // Handle .torrent files specially
            if fileURL.pathExtension.lowercased() == "torrent" {
                handleTorrentFile(fileURL)
                continue
            }

            windowManager.openExternalURL(fileURL, sourceAppBundleID: sourceApp)
        }
    }

    func application(_: NSApplication, open urls: [URL]) {
        guard browserState.settings.hasCompletedOnboarding else { return }

        // Detect source app once for all URLs
        let sourceApp = ExternalURLHandler.detectSourceApp()
        for url in urls {
            windowManager.openExternalURL(url, sourceAppBundleID: sourceApp)
        }
    }

    // MARK: - Dock Menu

    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        menuBarManager.createDockMenu()
    }

    // MARK: - Handoff & Spotlight Continuation

    func application(_: NSApplication, continue userActivity: NSUserActivity, restorationHandler _: @escaping ([any NSUserActivityRestoring]) -> Void) -> Bool {
        // Handle Spotlight search results
        if userActivity.activityType == CSSearchableItemActionType {
            return handleSpotlightContinuation(userActivity)
        }

        // Handle Handoff from other devices
        guard let url = HandoffManager.extractURL(from: userActivity) else {
            return false
        }

        windowManager.openURL(url)
        Logger.info("Handoff: opened URL from another device: \(url.absoluteString)", category: Logger.tabs)
        return true
    }

    private func handleSpotlightContinuation(_ userActivity: NSUserActivity) -> Bool {
        // Handle tab result - switch to existing tab
        if let tabID = SpotlightIndexManager.extractTabID(from: userActivity),
           let tab = browserState.tab(for: tabID) {
            if let windowState = windowManager.activeWindowController?.windowState {
                tabManager.setActiveTab(tab, in: windowState)
            }
            NSApp.activate(ignoringOtherApps: true)
            Logger.info("Spotlight: switched to tab \(tab.displayTitle)", category: Logger.tabs)
            return true
        }

        // Handle bookmark result - open bookmark URL
        if let bookmarkID = SpotlightIndexManager.extractBookmarkID(from: userActivity),
           let bookmark = bookmarksManager.bookmark(for: bookmarkID) {
            let url = bookmark.url
            windowManager.openURL(url)
            NSApp.activate(ignoringOtherApps: true)
            Logger.info("Spotlight: opened bookmark \(bookmark.title)", category: Logger.tabs)
            return true
        }

        // Handle history result - open URL from activity
        if SpotlightIndexManager.isHistoryEntry(from: userActivity),
           let url = userActivity.webpageURL {
            windowManager.openURL(url)
            NSApp.activate(ignoringOtherApps: true)
            Logger.info("Spotlight: opened history entry \(url.absoluteString)", category: Logger.tabs)
            return true
        }

        return false
    }
    
    // MARK: - Memory Warning

    /// Responds to system memory pressure.
    ///
    /// Aggressively frees resources:
    /// - Suspends inactive tabs and releases their WKWebViews
    /// - Clears generated passwords (security + memory)
    func applicationDidReceiveMemoryWarning(_: Notification) {
        tabManager.handleMemoryWarning()
        GeneratedPasswordStore.shared.clearAll()
    }
    
    // MARK: - Setup

    private func setupMenuBar() {
        menuBarManager.setupMenuBar()
    }
    
    private func setupSwizzling() {
        // Install swizzle for macOS autofill detection
        WKWebView.installAutoFillSwizzle()

        // Disable toolbar context menu (interferes with webpage context menus)
        ToolbarContextMenuSwizzle.install()

        // Forward clicks on empty toolbar areas to underlying content
        ToolbarMouseDownSwizzle.install()

        // Make all popovers arrowless globally
        NSPopover.installArrowlessSwizzle()

        // Allow Web Inspector to extend to top of window (ignore safe area)
        InspectorSafeAreaSwizzle.install()

        // Fix SwiftUI context menu memory leak
        SwiftUIContextMenuLeakFix.install()
    }
    
    private func startUtilitySetup() {
        Task(priority: .utility) {
            await PasswordQuirksManager.shared.prefetch()
        }

        // Load missing favicons for favorites in the background
        // (function dispatches its own detached utility task internally)
        bookmarksManager.loadFaviconsForFavorites()
    }

    /// Sets up the app for UI testing with test data.
    private func setupForUITests() {
        let config = UITestSetup.parseConfiguration()

        // Create a test space
        let space = tabManager.createTemporarySpace()

        // Create test data if specified
        if config.hasTestData {
            UITestSetup.createTestData(
                in: space,
                config: config,
                modelContext: modelContainer.mainContext,
                bookmarksManager: bookmarksManager,
            )
        }

        #if DEBUG
            UITestSetup.debugLog("setupForUITests: space has \(space.tabs.count) tabs\n")
            for tab in space.tabs {
                UITestSetup.debugLog("  tab: '\(tab.displayTitle)' pos=\(tab.position)\n")
            }
        #endif

        // Create and show window
        let controller = windowManager.createWindowWithoutInitialization()
        tabManager.initializeWindow(controller.windowState, with: space)
        controller.finalizeInitialization()

        // Set active tab to first tab if available
        if let firstTab = space.tabs.first {
            tabManager.setActiveTab(firstTab, in: controller.windowState)
        }
    }

    // MARK: - Logging

    private func logStorageMode() {
        switch storageMode {
        case .memory:
            Logger.debug("Storage: in-memory (data will not persist)", category: Logger.data)
        case .disk:
            let url = StorageConfiguration.defaultStoreURL()
            Logger.debug("Storage: disk (\(url.path))", category: Logger.data)
        }
    }

    // MARK: - Database Recovery

    /// Handles database load failures by presenting a recovery dialog.
    ///
    /// Called when the ModelContainer fails to initialize, typically due to schema
    /// changes during development. Offers the user the option to clear all data
    /// and relaunch, or quit the application.
    private static func handleDatabaseLoadFailure(error: any Error, storeURL: URL) -> Never {
        // Attempt granular recovery first
        let diagnosis = DatabaseRecoveryService.diagnose(
            storeURL: storeURL,
            expectedSchema: DatabaseRecoveryService.modelCategories.map {
                (tableName: $0.tableName, columns: [])
            },
        )

        if !diagnosis.incompatibleModels.isEmpty {
            // Show recovery UI with selective reset options
            let recoveryView = DatabaseRecoveryView(
                diagnosis: diagnosis,
                onRecover: { tableNames in
                    do {
                        try DatabaseRecoveryService.backup(storeURL: storeURL)
                        try DatabaseRecoveryService.resetModels(tableNames, storeURL: storeURL)
                    } catch {
                        Logger.error("Recovery failed: \(error)", category: Logger.system)
                    }
                    relaunch()
                },
                onResetAll: {
                    let dataDirectory = storeURL.deletingLastPathComponent()
                    try? FileManager.default.removeItem(at: dataDirectory)
                    relaunch()
                },
                onQuit: {
                    exit(1)
                },
            )

            let hostingController = NSHostingController(rootView: recoveryView)
            let window = NSWindow(contentViewController: hostingController)
            window.title = "Database Recovery"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 500, height: 450))
            window.center()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NSApp.run()
            exit(0)
        }

        // Fallback: full wipe dialog for total corruption
        let dataDirectory = storeURL.deletingLastPathComponent()
        let alert = NSAlert()
        alert.messageText = "Database Failed to Load"
        alert.informativeText = """
        Refrax couldn't load its database. This usually happens after updates \
        that change the data format.
        
        Error:
        \(error.localizedDescription)
        
        You can remove all data to start fresh, or quit to investigate manually.
        """
        alert.alertStyle = .critical
        alert.addButton(withTitle: "Remove All Data and Relaunch")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()

        if response == .alertFirstButtonReturn {
            try? FileManager.default.removeItem(at: dataDirectory)
            relaunch()
        }
        exit(1)
    }

    private static func relaunch() -> Never {
        relaunchApp()
    }

    /// Relaunches the app by spawning a new instance and exiting.
    ///
    /// Used by full reset (Settings > Storage) and database recovery.
    static func relaunchApp() -> Never {
        let bundlePath = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", bundlePath]
        try? task.run()
        exit(0)
    }
}

extension NSApplication {
    // swiftlint:disable:next force_cast
    var typedDelegate: AppDelegate {
        delegate as! AppDelegate
    }
}
