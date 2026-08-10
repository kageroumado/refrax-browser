import Foundation
import Observation
import WebKit

// MARK: - Tab Health Provider

/// Provides live-updating tab health snapshots for the Lightboard dashboard.
///
/// Observes tab manager, page pool, and process state changes to maintain
/// an up-to-date list of tab health snapshots. Uses debouncing to coalesce
/// rapid updates.
///
/// ## Usage
///
/// ```swift
/// @Environment(TabHealthProvider.self) var healthProvider
///
/// ForEach(healthProvider.snapshots) { snapshot in
///     TabHealthRow(snapshot: snapshot)
/// }
/// ```
@Observable
final class TabHealthProvider {
    // MARK: - Observable Properties

    /// Current snapshots for all tab pages.
    private(set) var snapshots: [TabHealthSnapshot] = []

    /// Filtered and sorted snapshots for display.
    private(set) var displaySnapshots: [TabHealthSnapshot] = []

    /// Current filter mode.
    var filter: TabHealthFilter = .all {
        didSet { updateDisplaySnapshots() }
    }

    /// Current sort mode.
    var sortMode: TabHealthSortMode = .memory {
        didSet { updateDisplaySnapshots() }
    }

    /// Optional process filter (by PID).
    var processFilter: pid_t? {
        didSet { updateDisplaySnapshots() }
    }

    // MARK: - Dependencies

    @ObservationIgnored
    private unowned let tabManager: TabManager

    @ObservationIgnored
    private unowned let pagePool: WebPagePool

    @ObservationIgnored
    private unowned let memoryMonitor: ProcessMemoryMonitor

    @ObservationIgnored
    private let importanceScorer = PageImportanceScorer()

    // MARK: - Private

    @ObservationIgnored
    private var observationTask: Task<Void, Never>?

    @ObservationIgnored
    private var memoryObservationTask: Task<Void, Never>?

    @ObservationIgnored
    private var refreshDebouncer: Task<Void, any Error>?

    @ObservationIgnored
    private let debounceInterval: Duration = .milliseconds(100)

    /// Reference count for observers. When > 0, observation is active.
    @ObservationIgnored
    private var observerCount = 0

    // MARK: - Initialization

    init(tabManager: TabManager, pagePool: WebPagePool, memoryMonitor: ProcessMemoryMonitor) {
        self.tabManager = tabManager
        self.pagePool = pagePool
        self.memoryMonitor = memoryMonitor
    }

    isolated deinit {
        observationTask?.cancel()
        memoryObservationTask?.cancel()
        refreshDebouncer?.cancel()
    }

    // MARK: - Observation Control

    /// Starts observing for changes and generating snapshots.
    ///
    /// Uses reference counting to support multiple observers. Observation
    /// begins when the first observer starts and stops when the last stops.
    func startObserving() {
        observerCount += 1
        guard observerCount == 1 else { return }

        // Initial refresh
        refresh()
        observeChanges()
    }

    /// Stops observing for the calling observer.
    ///
    /// Observation actually stops when the last observer calls this method.
    /// Snapshots are only cleared when observation fully stops.
    func stopObserving() {
        guard observerCount > 0 else { return }
        observerCount -= 1
        guard observerCount == 0 else { return }

        observationTask?.cancel()
        observationTask = nil
        memoryObservationTask?.cancel()
        memoryObservationTask = nil
        refreshDebouncer?.cancel()
        refreshDebouncer = nil
        snapshots = []
        displaySnapshots = []
    }

    /// Manually triggers a refresh.
    func refresh() {
        buildSnapshots()
        updateDisplaySnapshots()
    }

    // MARK: - Snapshot Building

    /// Builds snapshots from current state.
    private func buildSnapshots() {
        var newSnapshots: [TabHealthSnapshot] = []

        for space in tabManager.state.spaces {
            for tab in space.tabs {
                for tabPage in tab.pages {
                    let webPage = pagePool.existingPage(for: tabPage.id)
                    let snapshot = buildSnapshot(
                        tabPage: tabPage,
                        webPage: webPage,
                        spaceName: space.name,
                    )
                    newSnapshots.append(snapshot)
                }
            }
        }

        snapshots = newSnapshots
    }

    /// Builds a snapshot for a single tab page.
    private func buildSnapshot(
        tabPage: TabPage,
        webPage: WebPage?,
        spaceName: String,
    ) -> TabHealthSnapshot {
        // Determine process state
        let processState: TabProcessState
        let hasCrashed: Bool
        let lastTerminationReason: _WKProcessTerminationReason?

        if let observer = webPage?.processStateObserver {
            hasCrashed = observer.lastTerminationReason?.isRecoverable == true &&
                observer.processState == .notRunning
            lastTerminationReason = observer.lastTerminationReason
            processState = TabProcessState.from(
                webProcessState: observer.processState,
                hasCrashed: hasCrashed,
            )
        } else {
            hasCrashed = false
            lastTerminationReason = nil
            processState = .notRunning
        }

        // Determine if this page belongs to the active tab (any page in split-view counts)
        let activeTabID = tabManager.windowManager.activeWindowController?
            .windowState.activeTabID
        let isActive = tabPage.tab?.id == activeTabID

        // Calculate importance factors
        let factors = buildImportanceFactors(
            tabPage: tabPage,
            webPage: webPage,
            isActive: isActive,
        )
        let importanceScore = factors.reduce(0) { $0 + $1.points }

        // Get memory info from process monitor
        let processSnapshot = memoryMonitor.processSnapshot(for: tabPage.id)
        let processPID = webPage?.backingWebView._webProcessIdentifier ?? 0
        let processMemory = processSnapshot?.physicalFootprint ?? 0
        let estimatedTabMemory = processSnapshot?.estimatedPerTabMemory ?? 0
        let tabsInProcess = processSnapshot?.tabPageIDs.count ?? 0
        let processName = processPID > 0 ? memoryMonitor.processName(for: processPID) : ""

        return TabHealthSnapshot(
            id: tabPage.id,
            tabPage: tabPage,
            webPage: webPage,
            spaceName: spaceName,
            processState: processState,
            lastTerminationReason: lastTerminationReason,
            hasCrashed: hasCrashed,
            isPlayingAudio: webPage?.isPlayingAudio ?? false,
            cameraCaptureState: webPage?.cameraCaptureState ?? .none,
            microphoneCaptureState: webPage?.microphoneCaptureState ?? .none,
            hasUnsavedFormData: webPage?.hasUnsavedFormData ?? false,
            mediaPlaybackState: webPage?.cachedPlaybackState ?? .none,
            processPID: processPID,
            processMemoryBytes: processMemory,
            estimatedTabMemoryBytes: estimatedTabMemory,
            tabsInProcess: tabsInProcess,
            processName: processName,
            processCPUPercent: processSnapshot?.cpuPercent,
            isActiveTab: isActive,
            importanceScore: importanceScore,
            importanceFactors: factors,
            lastVisibleAt: tabPage.tab?.lastAccessed,
            createdAt: tabPage.createdAt,
        )
    }

    /// Builds importance factors for a tab.
    private func buildImportanceFactors(
        tabPage: TabPage,
        webPage: WebPage?,
        isActive: Bool,
    ) -> [ImportanceFactor] {
        var factors: [ImportanceFactor] = []

        let tab = tabPage.tab

        // Active tab
        if isActive {
            factors.append(ImportanceFactor(
                name: "Active Tab",
                points: PageImportanceScorer.Weight.isActive,
                icon: "star.fill",
            ))
        }

        // Playing audio
        if webPage?.isPlayingAudio == true {
            factors.append(ImportanceFactor(
                name: "Playing Audio",
                points: PageImportanceScorer.Weight.playingMedia,
                icon: "speaker.wave.2.fill",
            ))
        }

        // Media capture
        if webPage?.cameraCaptureState == .active ||
            webPage?.microphoneCaptureState == .active {
            factors.append(ImportanceFactor(
                name: "Camera/Mic Active",
                points: PageImportanceScorer.Weight.mediaCapture,
                icon: "video.fill",
            ))
        }

        // Fullscreen
        if webPage?.fullscreenState == .inFullscreen {
            factors.append(ImportanceFactor(
                name: "Fullscreen",
                points: PageImportanceScorer.Weight.fullscreen,
                icon: "arrow.up.left.and.arrow.down.right",
            ))
        }

        // Form data
        if webPage?.hasUnsavedFormData == true {
            factors.append(ImportanceFactor(
                name: "Unsaved Form",
                points: PageImportanceScorer.Weight.hasFormData,
                icon: "doc.text.fill",
            ))
        }

        // Pinned
        if tab?.isPinned == true {
            factors.append(ImportanceFactor(
                name: "Pinned",
                points: PageImportanceScorer.Weight.pinned,
                icon: "pin.fill",
            ))
        }

        // Reference tab
        if tab?.isReferenceTab == true {
            factors.append(ImportanceFactor(
                name: "Reference Tab",
                points: PageImportanceScorer.Weight.referenceTab,
                icon: "doc.on.doc.fill",
            ))
        }

        // Recent visibility
        if let lastVisible = tab?.lastAccessed,
           Date().timeIntervalSince(lastVisible) < importanceScorer.recentVisibilityThreshold {
            factors.append(ImportanceFactor(
                name: "Recently Viewed",
                points: PageImportanceScorer.Weight.recentlyVisible,
                icon: "clock.fill",
            ))
        }

        // Recency bonus
        if let lastVisible = tab?.lastAccessed {
            let elapsed = Date().timeIntervalSince(lastVisible)
            if elapsed < importanceScorer.recencyDecayPeriod {
                let fraction = 1.0 - (elapsed / importanceScorer.recencyDecayPeriod)
                let bonus = Int(Double(PageImportanceScorer.Weight.maxRecencyBonus) * fraction)
                if bonus > 0 {
                    factors.append(ImportanceFactor(
                        name: "Recency",
                        points: bonus,
                        icon: "clock.arrow.circlepath",
                    ))
                }
            }
        }

        return factors
    }

    // MARK: - Display Snapshots

    /// Updates the filtered and sorted display snapshots.
    private func updateDisplaySnapshots() {
        var result = snapshots

        // Apply process filter
        if let processFilter {
            result = result.filter { $0.processPID == processFilter }
        }

        // Apply filter
        switch filter {
        case .all:
            break
        case .running:
            result = result.filter {
                $0.processState == .running || $0.processState == .background
            }
        case .crashed:
            result = result.filter(\.hasCrashed)
        case .playingMedia:
            result = result.filter { $0.isPlayingAudio || $0.hasActiveMediaCapture }
        case .suspended:
            result = result.filter { $0.processState == .suspended }
        }

        // Apply sort
        switch sortMode {
        case .memory:
            result.sort { $0.estimatedTabMemoryBytes > $1.estimatedTabMemoryBytes }
        case .process:
            result.sort {
                if $0.processMemoryBytes != $1.processMemoryBytes {
                    return $0.processMemoryBytes > $1.processMemoryBytes
                }
                return $0.estimatedTabMemoryBytes > $1.estimatedTabMemoryBytes
            }
        case .importance:
            result.sort { $0.importanceScore > $1.importanceScore }
        case .state:
            result.sort { $0.processState.sortPriority > $1.processState.sortPriority }
        case .recent:
            result.sort { ($0.lastVisibleAt ?? .distantPast) > ($1.lastVisibleAt ?? .distantPast) }
        case .space:
            result.sort { $0.spaceName < $1.spaceName }
        }

        displaySnapshots = result
    }

    // MARK: - Observation

    /// Sets up observation for state changes using reactive observation.
    ///
    /// Uses `Observations {}` to react to `tabListVersion` changes
    /// instead of polling. This is more efficient as it only triggers when
    /// the underlying data actually changes. A second observation watches
    /// `ProcessMemoryMonitor.lastUpdated` to refresh memory values live.
    private func observeChanges() {
        let tabListChanges = Observations {
            self.tabManager.state.tabListVersion
        }

        observationTask = Task { [weak self] in
            for await _ in tabListChanges {
                guard let self else { return }
                scheduleRefresh()
            }
        }

        let memoryChanges = Observations {
            self.memoryMonitor.lastUpdated
        }

        memoryObservationTask = Task { [weak self] in
            for await _ in memoryChanges {
                guard let self else { return }
                scheduleRefresh()
            }
        }
    }

    /// Schedules a debounced refresh.
    private func scheduleRefresh() {
        refreshDebouncer?.cancel()
        refreshDebouncer = Task { [weak self] in
            try await Task.sleep(for: self?.debounceInterval ?? .milliseconds(100))
            self?.refresh()
        }
    }
}

// MARK: - Computed Properties

extension TabHealthProvider {
    /// Total number of tabs.
    var totalTabCount: Int {
        snapshots.count
    }

    /// Number of crashed tabs.
    var crashedTabCount: Int {
        snapshots.count(where: \.hasCrashed)
    }

    /// Number of suspended tabs.
    var suspendedTabCount: Int {
        snapshots.count(where: { $0.processState == .suspended })
    }

    /// Available processes for filtering, with their PIDs and tab counts.
    var availableProcesses: [(name: String, pid: pid_t, tabCount: Int)] {
        var seen: [pid_t: (name: String, count: Int)] = [:]
        for snapshot in snapshots where snapshot.processPID > 0 {
            if let existing = seen[snapshot.processPID] {
                seen[snapshot.processPID] = (existing.name, existing.count + 1)
            } else {
                seen[snapshot.processPID] = (snapshot.processName, 1)
            }
        }
        return seen.map { (name: $0.value.name, pid: $0.key, tabCount: $0.value.count) }
            .sorted { $0.name < $1.name }
    }

    /// Whether any tabs can be suspended.
    var hasInactiveTabs: Bool {
        snapshots.contains { snapshot in
            snapshot.processState == .running &&
                !snapshot.isPlayingAudio &&
                !snapshot.hasActiveMediaCapture &&
                !snapshot.hasUnsavedFormData
        }
    }
}

// MARK: - Lookup

extension TabHealthProvider {
    /// Finds a snapshot by ID.
    func snapshot(for id: UUID) -> TabHealthSnapshot? {
        snapshots.first { $0.id == id }
    }
}

// MARK: - Filter & Sort Types

/// Filter modes for the tab health dashboard.
enum TabHealthFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case running = "Running"
    case crashed = "Crashed"
    case playingMedia = "Playing Media"
    case suspended = "Suspended"

    var id: String { rawValue }
}

/// Sort modes for the tab health dashboard.
enum TabHealthSortMode: String, CaseIterable, Identifiable {
    case memory = "Memory"
    case process = "Process"
    case importance = "Importance"
    case state = "State"
    case recent = "Recent"
    case space = "Space"

    var id: String { rawValue }
}
