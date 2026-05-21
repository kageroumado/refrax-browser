import SwiftData
import SwiftUI

/// A container for all environment dependencies used by Settings views.
///
/// This struct aggregates all the managers and state objects that settings views
/// need access to via SwiftUI's environment system. It follows the same pattern
/// as ``RefraxEnvironment`` but with a focused subset of dependencies.
struct SettingsEnvironment {
    let modelContainer: ModelContainer
    let settings: BrowserSettings
    let browserState: BrowserState
    let historyManager: HistoryManager
    let autoFillState: AutoFillState
    let siteSettingsManager: SiteSettingsManager
    let extensionManager: ExtensionManager
    let bookmarksManager: BookmarksManager
    let tabManager: TabManager
    let calendarManager: CalendarManager
    let cookieInspectorManager: CookieInspectorManager
    let scheduledTasksManager: ScheduledTasksManager
    let archiveManager: TabArchiveManager
    let autoArchiveManager: TabAutoArchiveManager
    let downloadManager: DownloadManager
    let customSearchEngineManager: CustomSearchEngineManager
    let passwordsManager: PasswordsManager
}

/// A view modifier that injects all Settings environment dependencies.
struct SettingsEnvironmentModifier: ViewModifier {
    let environment: SettingsEnvironment

    func body(content: Content) -> some View {
        content
            .modelContainer(environment.modelContainer)
            .environment(environment.settings)
            .environment(environment.browserState)
            .environment(environment.historyManager)
            .environment(environment.autoFillState)
            .environment(environment.siteSettingsManager)
            .environment(environment.extensionManager)
            .environment(environment.bookmarksManager)
            .environment(environment.tabManager)
            .environment(environment.calendarManager)
            .environment(environment.cookieInspectorManager)
            .environment(environment.scheduledTasksManager)
            .environment(environment.archiveManager)
            .environment(environment.autoArchiveManager)
            .environment(environment.downloadManager)
            .environment(environment.customSearchEngineManager)
            .environment(environment.passwordsManager)
            .preferredColorScheme(environment.settings.theme.colorScheme)
            .tint(environment.settings.customAccentColor?.color)
    }
}

extension View {
    /// Applies all Settings environment dependencies to a view hierarchy.
    func settingsEnvironment(_ environment: SettingsEnvironment) -> some View {
        modifier(SettingsEnvironmentModifier(environment: environment))
    }
}
