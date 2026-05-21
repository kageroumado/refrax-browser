import Darwin
import Foundation
import WidgetKit

// MARK: - App Group Identifier

/// The app group identifier used for sharing data between Refrax and its widgets.
enum RefraxAppGroup {
    static let identifier = "group.website.refrax.browser"

    /// Returns the URL for the shared container, or nil if unavailable.
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    /// Returns the URL for the widget data file.
    static var widgetDataURL: URL? {
        containerURL?.appendingPathComponent("widget-data.json")
    }
}

// MARK: - Widget Data Models

/// Data shared with widgets, serialized to JSON in the app group container.
struct RefraxWidgetData: Codable, Sendable {
    let lastUpdated: Date
    let browserHealth: BrowserHealthData
    let currentTab: CurrentTabData?
    let topTabs: [TabSummary]
    let recentSpaces: [SpaceSummary]
}

/// Browser health statistics matching Lightboard data.
struct BrowserHealthData: Codable, Sendable {
    let totalTabCount: Int
    let spaceCount: Int
    let webContentMemoryMB: Double
    let activeProcessCount: Int
    let crashedTabCount: Int
    let suspendedTabCount: Int
    let playingAudioCount: Int
    let mediaCaptureCount: Int
}

/// Summary of the currently active tab.
struct CurrentTabData: Codable, Sendable {
    let title: String
    let url: URL
    let domain: String
    let spaceName: String
    let isPlayingAudio: Bool
    let faviconBase64: String?
}

/// Lightweight tab summary for widget display.
struct TabSummary: Codable, Sendable, Identifiable {
    let id: UUID
    let title: String
    let domain: String
    let spaceName: String
    let isPlayingAudio: Bool
    let hasCrashed: Bool
    let importanceScore: Int
    let faviconBase64: String?
}

/// Space summary for quick access widget.
struct SpaceSummary: Codable, Sendable, Identifiable {
    let id: UUID
    let name: String
    let iconName: String
    let tabCount: Int
    let colorHex: String?
}

// MARK: - Widget Data Manager

/// Manages exporting browser data to widgets via the shared app group container.
///
/// This manager collects data from Lightboard components and writes
/// it to a JSON file that widgets can read. Data is updated periodically
/// and when significant state changes occur.
///
/// ## Architecture
///
/// ```
/// ┌─────────────────────────────────────────────────────────────┐
/// │ Main App                                                     │
/// │                                                              │
/// │  TabManager ─┐                                               │
/// │  PagePool ───┼─> WidgetDataManager ─> widget-data.json ──┐  │
/// │  MemoryMon ──┘       (collects)         (app group)      │  │
/// └──────────────────────────────────────────────────────────│──┘
///                                                            │
/// ┌──────────────────────────────────────────────────────────│──┐
/// │ Widget Extension                                          │  │
/// │                                                           │  │
/// │  widget-data.json <── WidgetDataStorage.read() ──────────┘  │
/// │       │                                                      │
/// │       └─> TabHealthWidget / CurrentlyReadingWidget           │
/// └─────────────────────────────────────────────────────────────┘
/// ```

final class WidgetDataManager {
    // MARK: - Dependencies

    private unowned let browserState: BrowserState
    private unowned let tabManager: TabManager
    private unowned let pagePool: WebPagePool
    private unowned let windowManager: WindowManager

    // MARK: - Private

    /// Set to true when we've determined that widget data cannot be written
    /// (e.g., unsigned app without group container access). Prevents repeated error logging.
    private var widgetDataUnavailable = false

    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    // MARK: - Initialization

    init(
        browserState: BrowserState,
        tabManager: TabManager,
        pagePool: WebPagePool,
        windowManager: WindowManager,
    ) {
        self.browserState = browserState
        self.tabManager = tabManager
        self.pagePool = pagePool
        self.windowManager = windowManager
    }

    // MARK: - Lifecycle

    /// Performs initial widget data update.
    ///
    /// Call this during app startup. Subsequent periodic updates are handled
    /// by `ScheduledTasksManager` via `performScheduledUpdate()`.
    func performInitialUpdate() {
        guard browserState.settings.isFeatureFlagEnabled("app.widgetsEnabled", default: false) else { return }
        updateWidgetData()
    }

    /// Performs a scheduled widget data update.
    ///
    /// This method is designed to be called from `ScheduledTasksManager` on an hourly
    /// schedule. Widget data is also updated immediately via `requestUpdate()` when
    /// significant state changes occur (tab created/closed, navigation completed, etc.).
    func performScheduledUpdate() {
        guard browserState.settings.isFeatureFlagEnabled("app.widgetsEnabled", default: false) else { return }
        updateWidgetData()
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Requests an immediate widget data update.
    ///
    /// Call this when significant state changes occur, such as:
    /// - Tab created/closed
    /// - Navigation completed
    /// - Space switched
    func requestUpdate() {
        guard browserState.settings.isFeatureFlagEnabled("app.widgetsEnabled", default: false) else { return }
        updateWidgetData()
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: - Data Collection

    /// Updates widget data and writes to the shared container.
    private func updateWidgetData() {
        // Skip if we've already determined widget data can't be written
        guard !widgetDataUnavailable else { return }

        guard let containerURL = RefraxAppGroup.containerURL else {
            // App group not available - either not signed properly or running in development
            // This is expected during development without provisioning profiles
            return
        }

        // Ensure the container directory exists
        if !FileManager.default.fileExists(atPath: containerURL.path) {
            do {
                try FileManager.default.createDirectory(
                    at: containerURL,
                    withIntermediateDirectories: true,
                )
            } catch {
                // Directory creation failed - likely an unsigned app or missing entitlements.
                // Log once and disable further attempts.
                Logger.info(
                    "Widget data unavailable: group container cannot be created (app may be unsigned)",
                    category: Logger.data,
                )
                widgetDataUnavailable = true
                return
            }
        }

        let data = collectWidgetData()

        do {
            try writeWidgetData(data)
            Logger.debug("Widget data updated", category: Logger.data)
        } catch {
            // Write failed even though directory exists - might be permissions issue
            Logger.info(
                "Widget data unavailable: cannot write to group container",
                category: Logger.data,
            )
            widgetDataUnavailable = true
        }
    }

    /// Collects all data needed by widgets.
    private func collectWidgetData() -> RefraxWidgetData {
        // Collect browser health stats
        let health = collectBrowserHealth()

        // Collect current tab info
        let currentTab = collectCurrentTab()

        // Collect top tabs by importance
        let topTabs = collectTopTabs(limit: 5)

        // Collect recent spaces
        let recentSpaces = collectSpaces()

        return RefraxWidgetData(
            lastUpdated: Date(),
            browserHealth: health,
            currentTab: currentTab,
            topTabs: topTabs,
            recentSpaces: recentSpaces,
        )
    }

    /// Collects browser health statistics.
    private func collectBrowserHealth() -> BrowserHealthData {
        var totalTabCount = 0
        var crashedCount = 0
        var suspendedCount = 0
        var playingAudioCount = 0
        var mediaCaptureCount = 0

        for space in tabManager.state.spaces {
            for tab in space.tabs {
                for tabPage in tab.pages {
                    totalTabCount += 1

                    if let webPage = pagePool.existingPage(for: tabPage.id) {
                        // Check process state
                        if let observer = webPage.processStateObserver {
                            let hasCrashed = observer.lastTerminationReason?.isRecoverable == true &&
                                observer.processState == .notRunning
                            if hasCrashed {
                                crashedCount += 1
                            }
                            if observer.processState == .suspended {
                                suspendedCount += 1
                            }
                        }

                        // Check media state
                        if webPage.isPlayingAudio {
                            playingAudioCount += 1
                        }
                        if webPage.cameraCaptureState == .active ||
                            webPage.microphoneCaptureState == .active {
                            mediaCaptureCount += 1
                        }
                    }
                }
            }
        }

        // Collect memory stats
        var webContentMemory: Double = 0
        var processCount = 0

        var seenPIDs = Set<pid_t>()
        for page in pagePool.activePages.values {
            let pid = page.backingWebView._webProcessIdentifier
            if pid > 0, !seenPIDs.contains(pid) {
                seenPIDs.insert(pid)
                webContentMemory += Double(memoryForProcess(pid)) / 1_024 / 1_024
            }
        }
        processCount = seenPIDs.count

        return BrowserHealthData(
            totalTabCount: totalTabCount,
            spaceCount: tabManager.state.spaces.count,
            webContentMemoryMB: webContentMemory,
            activeProcessCount: processCount,
            crashedTabCount: crashedCount,
            suspendedTabCount: suspendedCount,
            playingAudioCount: playingAudioCount,
            mediaCaptureCount: mediaCaptureCount,
        )
    }

    /// Collects current active tab information.
    private func collectCurrentTab() -> CurrentTabData? {
        guard let windowState = windowManager.activeWindowController?.windowState,
              let spaceID = windowState.activeSpaceID,
              let tabID = windowState.activeTabID(for: spaceID),
              let tab = browserState.tab(for: tabID),
              let space = browserState.space(for: spaceID) else {
            return nil
        }

        let page = tab.activePage
        let url = page.url
        let webPage = pagePool.existingPage(for: page.id)

        return CurrentTabData(
            title: tab.displayTitle,
            url: url,
            domain: url.host ?? url.absoluteString,
            spaceName: space.name,
            isPlayingAudio: webPage?.isPlayingAudio ?? false,
            faviconBase64: page.faviconData?.base64EncodedString(),
        )
    }

    /// Collects top tabs by importance score.
    private func collectTopTabs(limit: Int) -> [TabSummary] {
        var tabSummaries: [(summary: TabSummary, score: Int)] = []

        for space in tabManager.state.spaces {
            for tab in space.tabs {
                let page = tab.activePage
                let webPage = pagePool.existingPage(for: page.id)

                // Calculate importance score
                var score = 0
                if webPage?.isPlayingAudio == true { score += 1_000 }
                if webPage?.cameraCaptureState == .active ||
                    webPage?.microphoneCaptureState == .active { score += 300 }
                if tab.isPinned { score += 300 }

                // Check for crash
                var hasCrashed = false
                if let observer = webPage?.processStateObserver {
                    hasCrashed = observer.lastTerminationReason?.isRecoverable == true &&
                        observer.processState == .notRunning
                }
                if hasCrashed { score += 500 } // Crashed tabs are important to show

                // Recency bonus
                if let lastAccessed = tab.lastAccessed {
                    let elapsed = Date().timeIntervalSince(lastAccessed)
                    if elapsed < 3_600 { // Within last hour
                        score += Int(500 * (1.0 - elapsed / 3_600))
                    }
                }

                let summary = TabSummary(
                    id: tab.id,
                    title: tab.displayTitle,
                    domain: page.url.host ?? page.url.absoluteString,
                    spaceName: space.name,
                    isPlayingAudio: webPage?.isPlayingAudio ?? false,
                    hasCrashed: hasCrashed,
                    importanceScore: score,
                    faviconBase64: page.faviconData?.base64EncodedString(),
                )

                tabSummaries.append((summary, score))
            }
        }

        // Sort by importance and take top N
        tabSummaries.sort { $0.score > $1.score }
        return tabSummaries.prefix(limit).map(\.summary)
    }

    /// Collects space summaries.
    private func collectSpaces() -> [SpaceSummary] {
        tabManager.state.spaces.map { space in
            SpaceSummary(
                id: space.id,
                name: space.name,
                iconName: space.iconName,
                tabCount: space.tabs.count,
                colorHex: space.colorHex,
            )
        }
    }

    // MARK: - Memory Reading

    /// Reads resident memory for a process.
    private func memoryForProcess(_ pid: pid_t) -> UInt64 {
        var taskInfo = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size

        let result = proc_pidinfo(
            pid,
            PROC_PIDTASKINFO,
            0,
            &taskInfo,
            Int32(size),
        )

        guard result == size else {
            return 0
        }

        return taskInfo.pti_resident_size
    }

    // MARK: - File Writing

    /// Writes widget data to the shared container.
    private func writeWidgetData(_ data: RefraxWidgetData) throws {
        guard let url = RefraxAppGroup.widgetDataURL else {
            throw WidgetDataError.containerUnavailable
        }

        let jsonData = try encoder.encode(data)
        try jsonData.write(to: url, options: .atomic)
    }
}

// MARK: - Errors

enum WidgetDataError: Error {
    case containerUnavailable
}
