import SwiftData
import SwiftUI

/// A container for all environment dependencies used by Refrax views.
///
/// This struct aggregates all the managers and state objects that views
/// need access to via SwiftUI's environment system.
struct RefraxEnvironment {
    let modelContainer: ModelContainer
    let browserState: BrowserState
    let windowState: WindowState
    let historyManager: HistoryManager
    let historyActivityManager: HistoryActivityManager
    let settings: BrowserSettings
    let siteSettingsManager: SiteSettingsManager
    let autoFillState: AutoFillState

    // Tab-related managers (accessible via @Environment)
    let tabManager: TabManager
    let pagePool: WebPagePool
    let spaceManager: SpaceManager
    let groupManager: TabGroupManager
    let archiveManager: TabArchiveManager
    let autoArchiveManager: TabAutoArchiveManager
    let windowManager: WindowManager

    let bookmarksManager: BookmarksManager
    let extensionManager: ExtensionManager
    let dialogState: DialogState
    let tabPreviewProvider: TabPreviewProvider
    let downloadManager: DownloadManager
    let shelfManager: ShelfManager
    let webInspectorManager: WebInspectorManager
    let sharingCoordinator: SharingCoordinator
    let passwordsManager: PasswordsManager
    let commandLensManager: CommandLensManager
    let modifierKeysState: ModifierKeysState
    let tabSwitcherManager: TabSwitcherManager
    let tabCanvasManager: TabCanvasManager
    let mediaControlsManager: MediaControlsManager
    let undoRedoManager: UndoRedoManager
    let clipboardMonitor: ClipboardMonitor
    let screenshotCoordinator: ScreenshotCoordinator
    let recordingCoordinator: RecordingCoordinator
    let pageReminderManager: PageReminderManager
    let favoritePreviewManager: FavoritePreviewManager
    let cookieInspectorManager: CookieInspectorManager
    let translationManager: TranslationManager
    let offlineContentManager: OfflineContentManager
    let tabHealthProvider: TabHealthProvider
    let processMemoryMonitor: ProcessMemoryMonitor
    let visualFeedbackManager: VisualFeedbackManager
    let humanInterventionManager: HumanInterventionManager
    let customSearchEngineManager: CustomSearchEngineManager
    let appUpdateManager: AppUpdateManager
    let floatingTourManager: FloatingTourManager
    let engineRegistry: EngineRegistry
}

/// A view modifier that injects all Refrax environment dependencies.
struct RefraxEnvironmentModifier: ViewModifier {
    let environment: RefraxEnvironment

    func body(content: Content) -> some View {
        content
            .modelContainer(environment.modelContainer)
            .environment(environment.browserState)
            .environment(environment.windowState)
            .environment(environment.historyManager)
            .environment(environment.historyActivityManager)
            .environment(environment.settings)
            .environment(environment.siteSettingsManager)
            .environment(environment.autoFillState)
            .environment(environment.tabManager)
            .environment(environment.pagePool)
            .environment(environment.spaceManager)
            .environment(environment.groupManager)
            .environment(environment.archiveManager)
            .environment(environment.autoArchiveManager)
            .environment(environment.windowManager)
            .environment(environment.bookmarksManager)
            .environment(environment.extensionManager)
            .environment(environment.dialogState)
            .environment(environment.tabPreviewProvider)
            .environment(environment.downloadManager)
            .environment(environment.shelfManager)
            .environment(environment.webInspectorManager)
            .environment(environment.sharingCoordinator)
            .environment(environment.passwordsManager)
            .environment(environment.commandLensManager)
            .environment(environment.modifierKeysState)
            .environment(environment.tabSwitcherManager)
            .environment(environment.tabCanvasManager)
            .environment(environment.mediaControlsManager)
            .environment(environment.undoRedoManager)
            .environment(environment.clipboardMonitor)
            .environment(environment.screenshotCoordinator)
            .environment(environment.recordingCoordinator)
            .environment(environment.pageReminderManager)
            .environment(environment.favoritePreviewManager)
            .environment(environment.cookieInspectorManager)
            .environment(environment.translationManager)
            .environment(environment.offlineContentManager)
            .environment(environment.tabHealthProvider)
            .environment(environment.processMemoryMonitor)
            .environment(environment.visualFeedbackManager)
            .environment(environment.humanInterventionManager)
            .environment(environment.customSearchEngineManager)
            .environment(environment.appUpdateManager)
            .environment(environment.floatingTourManager)
            .environment(environment.engineRegistry)
            .preferredColorScheme(environment.settings.theme.colorScheme)
            .tint(environment.settings.customAccentColor?.color)
    }
}

extension View {
    /// Applies all Refrax environment dependencies to a view hierarchy.
    func refraxEnvironment(_ environment: RefraxEnvironment) -> some View {
        modifier(RefraxEnvironmentModifier(environment: environment))
    }
}
