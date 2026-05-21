import Foundation
import Observation
import SwiftData
import WebKit

/// Evaluates and executes user-defined auto-archive rules.
///
/// `TabAutoArchiveManager` processes rules created by users to automatically archive tabs
/// based on criteria like inactivity duration or tab count limits. Rules are evaluated
/// hourly via ``ScheduledTasksManager``.
///
/// ## Rule Evaluation
///
/// Rules are evaluated in priority order (highest first) against all non-exempt tabs.
/// A tab is exempt if any of these conditions apply:
///
/// - Tab is pinned
/// - Tab is currently active in any window
/// - Tab is already archived
/// - Tab has active media playback
/// - Tab has active camera/microphone capture
/// - Tab has unsaved form data
///
/// ## Inactivity Rules
///
/// Inactivity rules archive tabs that haven't been accessed within a specified number
/// of days. The `lastAccessed` timestamp on each tab is compared against the rule's
/// `inactivityDays` threshold.
///
/// ## Tab Count Rules
///
/// Tab count rules enforce a maximum number of active tabs. When exceeded, the oldest
/// tabs (by `lastAccessed`) are archived until the count is within the limit.
///
/// ## Integration
///
/// The manager is called by ``ScheduledTasksManager`` on the hourly schedule:
///
/// ```swift
/// scheduledTasksManager.registerTask { @MainActor in
///     await autoArchiveManager.executeRules(context: modelContext)
/// }
/// ```
@Observable
final class TabAutoArchiveManager {
    // MARK: - Dependencies

    private unowned let state: BrowserState
    private unowned let settings: BrowserSettings
    private unowned let archiveManager: TabArchiveManager

    /// WebPage pool for checking page state (media, forms).
    unowned var pagePool: WebPagePool!

    /// Window manager for checking active tabs across windows.
    unowned var windowManager: WindowManager!

    /// Task that observes settings changes.
    private var settingsObservationTask: Task<Void, Never>?

    // MARK: - Archive Threshold Tracking

    /// Tabs that would be archived on next rule execution.
    ///
    /// Updated when rules execute or when a tab is activated.
    /// Use ``isAtArchiveThreshold(_:)`` for O(1) lookup.
    private(set) var tabsAtArchiveThreshold: Set<Tab.ID> = []

    // MARK: - Initialization

    /// Creates an auto-archive manager.
    ///
    /// - Parameters:
    ///   - state: The browser state containing spaces and tabs.
    ///   - settings: Browser settings for checking if rules are enabled.
    ///   - archiveManager: The archive manager for archiving tabs.
    init(
        state: BrowserState,
        settings: BrowserSettings,
        archiveManager: TabArchiveManager,
    ) {
        self.state = state
        self.settings = settings
        self.archiveManager = archiveManager
    }

    isolated deinit {
        settingsObservationTask?.cancel()
    }

    // MARK: - Archive Threshold API

    /// Checks if a tab is at the archive threshold (would be archived on next rule execution).
    ///
    /// O(1) lookup against the pre-computed threshold set.
    ///
    /// - Parameter tab: The tab to check.
    /// - Returns: `true` if the tab would be archived soon.
    func isAtArchiveThreshold(_ tab: Tab) -> Bool {
        tabsAtArchiveThreshold.contains(tab.id)
    }

    /// Removes a tab from the threshold set when it's activated.
    ///
    /// Called from `TabManager.setActiveTab()`. Activating a tab updates its
    /// `lastAccessed` timestamp, removing it from archive eligibility.
    ///
    /// - Parameter tab: The tab that was activated.
    func tabWasActivated(_ tab: Tab) {
        guard tabsAtArchiveThreshold.contains(tab.id) else { return }
        tabsAtArchiveThreshold.remove(tab.id)
    }

    /// Updates the threshold set based on current rules and tab states.
    ///
    /// Called after rule execution and when settings change. Computes which tabs
    /// would be archived if rules were executed now.
    ///
    /// - Parameter context: The model context for fetching rules.
    func updateThresholdSet(context: ModelContext) {
        guard settings.autoArchiveRulesEnabled else {
            tabsAtArchiveThreshold.removeAll()
            return
        }

        let rules = fetchEnabledRules(context: context)
        guard !rules.isEmpty else {
            tabsAtArchiveThreshold.removeAll()
            return
        }

        let activeTabIDs = collectActiveTabIDs()
        var atThreshold: Set<Tab.ID> = []

        for space in state.spaces {
            let archiveGroup = archiveManager.findArchiveGroup(in: space)

            for rule in rules where rule.applies(to: space) {
                switch rule.ruleType {
                case .inactivity:
                    let cutoff = Date().addingTimeInterval(
                        -TimeInterval((rule.inactivityDays ?? 3) * 86_400),
                    )

                    for tab in space.tabs {
                        // Skip archive group tabs
                        guard tab.groupID != archiveGroup?.id else { continue }

                        // Check domain pattern
                        guard matchesDomainPattern(tab.activePage.url, pattern: rule.domainPattern) else {
                            continue
                        }

                        // Check exemptions
                        guard !isExempt(tab, activeTabIDs: activeTabIDs) else { continue }

                        // Check inactivity
                        guard let lastAccessed = tab.lastAccessed else {
                            atThreshold.insert(tab.id)
                            continue
                        }
                        if lastAccessed < cutoff {
                            atThreshold.insert(tab.id)
                        }
                    }

                case .tabCountLimit:
                    // Tab count rules don't have a meaningful "threshold" concept
                    // They're evaluated as a batch based on count, not individual tab state
                    break
                }
            }
        }

        tabsAtArchiveThreshold = atThreshold
    }

    /// Starts observing settings changes to rebuild the threshold set.
    ///
    /// Call this once after all dependencies are wired up.
    /// Uses the `Observations {}` async sequence pattern for cleaner lifecycle management.
    func startObservingSettings() {
        // Cancel any existing observation
        settingsObservationTask?.cancel()

        let settingsChanges = Observations {
            self.settings.autoArchiveRulesEnabled
        }

        settingsObservationTask = Task { [weak self] in
            for await _ in settingsChanges {
                guard let self else { return }
                // modelContext not available here - defer to next rule execution
                // Just clear the set if rules are disabled
                if !settings.autoArchiveRulesEnabled {
                    tabsAtArchiveThreshold.removeAll()
                }
            }
        }
    }

    // MARK: - Rule Execution

    /// Executes all enabled auto-archive rules.
    ///
    /// Called by ScheduledTasksManager on the hourly schedule. Evaluates rules
    /// against all tabs and archives those that match.
    ///
    /// - Parameter context: The model context for fetching rules.
    func executeRules(context: ModelContext) async {
        guard settings.autoArchiveRulesEnabled else { return }

        let rules = fetchEnabledRules(context: context)
        guard !rules.isEmpty else { return }

        // Collect active tab IDs across all windows
        let activeTabIDs = collectActiveTabIDs()

        var archivedCount = 0

        for space in state.spaces {
            let archiveGroup = archiveManager.findArchiveGroup(in: space)

            for rule in rules where rule.applies(to: space) {
                switch rule.ruleType {
                case .inactivity:
                    let inactiveTabs = findInactiveTabs(
                        in: space,
                        days: rule.inactivityDays ?? 3,
                        domainPattern: rule.domainPattern,
                        excludingArchiveGroup: archiveGroup,
                        activeTabIDs: activeTabIDs,
                    )
                    for tab in inactiveTabs where archiveOrClose(tab, context: context) {
                        archivedCount += 1
                    }

                case .tabCountLimit:
                    archivedCount += enforceTabCountLimit(
                        in: space,
                        limit: rule.maxTabCount ?? 50,
                        domainPattern: rule.domainPattern,
                        excludingArchiveGroup: archiveGroup,
                        activeTabIDs: activeTabIDs,
                        context: context,
                    )
                }
            }
        }

        if archivedCount > 0 {
            Logger.info(
                "Auto-archived \(archivedCount) tabs",
                category: Logger.tabs,
            )
        }

        // Update the threshold set after rule execution
        updateThresholdSet(context: context)
    }

    // MARK: - Rule Fetching

    /// Fetches all enabled rules sorted by priority (highest first).
    private func fetchEnabledRules(context: ModelContext) -> [ArchiveRule] {
        let descriptor = FetchDescriptor<ArchiveRule>(
            predicate: #Predicate { $0.isEnabled },
            sortBy: [SortDescriptor(\.priority, order: .reverse)],
        )

        do {
            return try context.fetch(descriptor)
        } catch {
            Logger.error(
                "Failed to fetch archive rules: \(error)",
                category: Logger.tabs,
            )
            return []
        }
    }

    // MARK: - Tab Finding

    /// Finds tabs inactive for the specified number of days.
    private func findInactiveTabs(
        in space: Space,
        days: Int,
        domainPattern: String?,
        excludingArchiveGroup archiveGroup: TabGroup?,
        activeTabIDs: Set<UUID>,
    ) -> [Tab] {
        let cutoff = Date().addingTimeInterval(-TimeInterval(days * 86_400))

        return space.tabs.filter { tab in
            // Exclude archive group tabs
            guard tab.groupID != archiveGroup?.id else { return false }

            // Check inactivity - tabs never accessed are considered inactive
            guard let lastAccessed = tab.lastAccessed else { return true }
            guard lastAccessed < cutoff else { return false }

            // Check domain pattern
            guard matchesDomainPattern(tab.activePage.url, pattern: domainPattern) else {
                return false
            }

            // Check exemptions
            guard !isExempt(tab, activeTabIDs: activeTabIDs) else { return false }

            return true
        }
    }

    /// Enforces a tab count limit, archiving oldest tabs when exceeded.
    ///
    /// - Returns: Number of tabs archived or closed.
    private func enforceTabCountLimit(
        in space: Space,
        limit: Int,
        domainPattern: String?,
        excludingArchiveGroup archiveGroup: TabGroup?,
        activeTabIDs: Set<UUID>,
        context: ModelContext,
    ) -> Int {
        // Filter to eligible tabs (matching domain pattern, not exempt)
        let eligibleTabs = space.tabs.filter { tab in
            // Exclude archive group
            guard tab.groupID != archiveGroup?.id else { return false }

            // Check domain pattern
            guard matchesDomainPattern(tab.activePage.url, pattern: domainPattern) else {
                return false
            }

            // Check exemptions
            guard !isExempt(tab, activeTabIDs: activeTabIDs) else { return false }

            return true
        }

        guard eligibleTabs.count > limit else { return 0 }

        let excess = eligibleTabs.count - limit

        // Sort by last accessed (oldest first, never-accessed treated as oldest)
        let oldestTabs = eligibleTabs
            .sorted { ($0.lastAccessed ?? .distantPast) < ($1.lastAccessed ?? .distantPast) }
            .prefix(excess)

        var archivedCount = 0
        for tab in oldestTabs {
            if archiveOrClose(tab, context: context) {
                archivedCount += 1
            }
        }

        return archivedCount
    }

    // MARK: - Exemption Checks

    /// Checks if a tab is exempt from auto-archiving.
    private func isExempt(_ tab: Tab, activeTabIDs: Set<UUID>) -> Bool {
        if tab.isPinned { return true }
        if tab.isArchived { return true }
        if tab.isLiveFavorite { return true }
        if activeTabIDs.contains(tab.id) { return true }

        guard let page = pagePool?.existingPage(for: tab.activePage) else {
            return false
        }

        return page.isPlayingAudio
            || page.cameraCaptureState == .active
            || page.microphoneCaptureState == .active
            || page.hasUnsavedFormData
    }

    /// Collects IDs of all active tabs across all windows.
    private func collectActiveTabIDs() -> Set<UUID> {
        guard let windowManager else { return [] }

        return Set(
            windowManager.allWindowStates.flatMap { state in
                [state.activeTab?.id, state.activeReferenceTab?.id].compactMap(\.self)
            },
        )
    }

    // MARK: - Domain Matching

    /// Checks if a URL matches a domain pattern.
    ///
    /// - Parameters:
    ///   - url: The URL to check.
    ///   - pattern: The pattern to match. `nil` matches all URLs.
    /// - Returns: `true` if the URL matches the pattern.
    private func matchesDomainPattern(_ url: URL?, pattern: String?) -> Bool {
        // Nil pattern matches all
        guard let pattern else { return true }

        // Need a registrable domain to match
        guard let domain = url?.registrableDomain?.lowercased() else { return false }

        let lowercasedPattern = pattern.lowercased()

        // Wildcard subdomain matching: *.example.com
        if lowercasedPattern.hasPrefix("*.") {
            let suffix = String(lowercasedPattern.dropFirst(2))
            // Match exact domain or any subdomain
            return domain == suffix || domain.hasSuffix(".\(suffix)")
        }

        // Exact match
        return domain == lowercasedPattern
    }

    // MARK: - Archive Action

    /// Archives or closes a tab depending on archive settings.
    ///
    /// When archive is enabled, tabs are archived. When disabled, tabs are
    /// permanently deleted.
    ///
    /// - Parameters:
    ///   - tab: The tab to archive or close.
    ///   - context: The model context for deletion when archive is disabled.
    /// - Returns: `true` if the tab was successfully archived or closed.
    @discardableResult
    private func archiveOrClose(_ tab: Tab, context: ModelContext) -> Bool {
        if settings.archiveEnabled {
            do {
                try archiveManager.archive(tab)
                return true
            } catch {
                Logger.debug(
                    "Failed to auto-archive tab: \(error)",
                    category: Logger.tabs,
                )
                return false
            }
        } else {
            // Archive disabled - permanently close the tab
            let title = tab.activePage.title
            context.delete(tab)
            state.incrementListVersion()
            Logger.debug(
                "Auto-closed tab (archive disabled): \(title)",
                category: Logger.tabs,
            )
            return true
        }
    }
}
