import Foundation
import Observation
import SwiftData

// Manages browsing history recording, querying, and persistence.
//
// ## Performance Optimization
//
// History saves are debounced to reduce disk I/O during rapid navigation:
// - Hot path operations (title updates, entry failures) use debounced saves
// - Cold path operations (cleanup, clear all) use immediate saves
// - Debounce delay: 1 second with utility priority for system resource management
//
// This prevents the main thread from being blocked by SwiftData saves during
// page loads when titles and entry states are updated frequently.

@Observable
final class HistoryManager {
    // MARK: - Properties

    /// SwiftData model context
    private let modelContext: ModelContext

    /// Reference to browser settings
    private let settings: BrowserSettings

    /// Frequent destinations cache for fast suggestions
    let frequentDestinations: FrequentDestinationsCache

    /// Active history entries being tracked (URL -> HistoryEntry)
    @ObservationIgnored private var activeEntries: [UUID: HistoryEntry] = [:]

    /// Last snapshot content hash for deduplication
    @ObservationIgnored private var lastSnapshotHash: String?

    /// Current browsing context ID
    var currentSpaceID: UUID?

    // MARK: - Debounced Save

    /// Debounced saver for history persistence.
    private let saver: DebouncedModelContextSaver
    
    // MARK: - Deferred Maintenance

    /// Background actor for heavy maintenance operations.
    ///
    /// Initialized lazily when deferred maintenance is performed.
    private var maintenanceActor: HistoryMaintenanceActor?

    /// Whether deferred maintenance has completed.
    private(set) var maintenanceComplete = false

    // MARK: - Background Query Actor

    /// Background actor for expensive read queries.
    ///
    /// Initialized via deferred setup to avoid blocking app launch.
    @ObservationIgnored
    private var queryActor: HistoryQueryActor?

    // MARK: - Initialization

    init(modelContext: ModelContext, settings: BrowserSettings) {
        self.modelContext = modelContext
        self.settings = settings
        self.frequentDestinations = FrequentDestinationsCache()
        self.saver = DebouncedModelContextSaver(
            modelContext: modelContext,
            debounceDelay: 2.9,
            logCategory: Logger.data,
        )

        // Heavy maintenance work is deferred to after first frame.
        // Call performDeferredMaintenance() from AppDelegate after window is shown.
    }

    /// Performs deferred maintenance operations on a background actor.
    ///
    /// This method should be called after the first frame renders to avoid
    /// blocking app launch. It performs:
    /// - Orphaned entry cleanup (closes entries from previous session)
    /// - Frequent destinations cache rebuild
    ///
    /// Safe to call multiple times - subsequent calls are no-ops.
    func performDeferredMaintenance(modelContainer: ModelContainer) async {
        guard !maintenanceComplete else { return }

        // Initialize query actor for background read operations
        queryActor = HistoryQueryActor(modelContainer: modelContainer)

        // Create maintenance actor with its own ModelContext
        let actor = HistoryMaintenanceActor(modelContainer: modelContainer)
        maintenanceActor = actor

        // Close orphaned entries on background actor
        let closedCount = await actor.closeOrphanedEntries()
        if closedCount > 0 {
            Logger.info("Closed \(closedCount) orphaned history entries from previous session", category: Logger.data)
        }

        // Fetch frequent destination data on background actor
        let destinationData = await actor.fetchRecentEntriesForFrequentDestinations()

        // Rebuild cache on main thread (FrequentDestinationsCache is not Sendable)
        frequentDestinations.rebuild(from: destinationData)
        Logger.info("Loaded \(frequentDestinations.topDestinations().count) frequent destinations", category: Logger.data)

        maintenanceComplete = true
        maintenanceActor = nil
    }

    // MARK: - Private Mode Check (internal)

    /// Checks if the current space is in private mode.
    ///
    /// This is used internally for snapshot operations where the caller
    /// doesn't have direct access to the Space object. For `recordNavigation`,
    /// callers should pass the `isPrivateSpace` parameter directly.
    ///
    /// - Note: This performs a database fetch. For hot-path operations like
    ///   navigation recording, prefer passing the privacy status directly.
    private func isCurrentSpacePrivate() -> Bool {
        guard let spaceID = currentSpaceID else { return false }
        let descriptor = FetchDescriptor<Space>(
            predicate: #Predicate { $0.id == spaceID },
        )
        guard let space = try? modelContext.fetch(descriptor).first else {
            return false
        }
        return space.dataStoreMode.isPrivate
    }

    // MARK: - History Recording

    /// Record a new navigation event.
    ///
    /// - Parameters:
    ///   - url: The URL being navigated to.
    ///   - title: Optional page title.
    ///   - tabID: The tab's unique identifier.
    ///   - spaceID: Optional space ID for grouping.
    ///   - isPrivateSpace: Whether the space is private. Pass `true` to skip recording.
    ///                     Callers should pass `space?.dataStoreMode.isPrivate ?? false`.
    ///   - parentEntry: Optional parent entry for navigation chains.
    /// - Returns: The created history entry, or `nil` if recording was skipped.
    @discardableResult
    func recordNavigation(
        url: URL,
        title: String? = nil,
        tabID: UUID,
        spaceID: UUID? = nil,
        isPrivateSpace: Bool = false,
        parentEntry: HistoryEntry? = nil,
    ) -> HistoryEntry? {
        // Don't record in private spaces
        if isPrivateSpace {
            Logger.debug("Skipping history recording in private space", category: Logger.data)
            return nil
        }

        let normalizedURL = normalizeURL(url)
        
        // Create new history entry
        let entry = HistoryEntry(
            url: normalizedURL,
            title: title,
            parent: parentEntry,
            spaceID: spaceID,
            tabID: tabID,
        )
        
        modelContext.insert(entry)
        activeEntries[tabID] = entry

        // Update frequent destinations cache
        frequentDestinations.recordVisit(url: normalizedURL, title: title)

        return entry
    }
    
    /// Update an existing history entry (e.g., title change)
    func updateEntry(
        for tabID: UUID,
        title: String? = nil,
    ) {
        guard let entry = activeEntries[tabID] else { return }

        if let title {
            entry.updateTitle(title)
        }

        // Hot path: use debounced save since title updates happen frequently
        scheduleSave()
    }

    /// Mark an existing history entry as failed to load.
    ///
    /// - Parameters:
    ///   - tabID: The tab ID whose entry should be marked as failed.
    ///   - statusCode: Optional HTTP status code or pseudo-code for the error.
    func markEntryFailed(for tabID: UUID, statusCode: Int? = nil) {
        guard let entry = activeEntries[tabID] else { return }

        entry.markFailed(statusCode: statusCode)
        // Hot path: use debounced save since failures may occur during rapid navigation
        scheduleSave()
    }
    
    /// Mark a history entry as closed and record time spent
    func closeEntry(for tabID: UUID, timeSpent: TimeInterval) {
        guard let entry = activeEntries[tabID] else { return }

        entry.markClosed(timeSpent: timeSpent)
        activeEntries.removeValue(forKey: tabID)

        // Hot path: use debounced save since tab closes can happen rapidly
        scheduleSave()
    }
    
    /// Track time spent on an active entry
    func addTimeSpent(for tabID: UUID, duration: TimeInterval) {
        guard let entry = activeEntries[tabID] else { return }
        entry.addTimeSpent(duration)
    }

    /// Update the last seen timestamp for an active entry.
    ///
    /// Called periodically while a tab is visible to provide crash recovery.
    /// If the app terminates unexpectedly, this timestamp is used as the
    /// effective close time instead of extending to current moment.
    func updateLastSeen(for tabID: UUID) {
        guard let entry = activeEntries[tabID] else { return }
        entry.updateLastSeen()
    }
    
    /// Normalizes a URL for consistent history storage.
    ///
    /// Normalization includes:
    /// - Removing `www.` prefix from host
    /// - Removing trailing slash from path
    /// - Normalizing search engine queries (keeping only essential parameters)
    private func normalizeURL(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }

        // Remove www. prefix from host
        if let host = components.host, host.hasPrefix("www.") {
            components.host = String(host.dropFirst(4))
        }

        // Remove trailing slash from path if it's just "/"
        if components.path == "/" {
            components.path = ""
        }

        // Normalize search engine queries
        if let host = components.host, let queryItems = components.queryItems {
            components.queryItems = normalizeSearchQueryItems(
                queryItems,
                forHost: host,
            )
        }

        return components.url ?? url
    }

    /// Normalizes query parameters for search engines.
    ///
    /// Removes tracking parameters while preserving the essential search query.
    private func normalizeSearchQueryItems(
        _ queryItems: [URLQueryItem],
        forHost host: String,
    ) -> [URLQueryItem]? {
        // Search engines that use 'q' parameter
        let usesQParam = host.contains("duckduckgo.com")
            || host.contains("google.com")
            || host.contains("google.co")
            || host.contains("bing.com")
            || host.contains("search.brave.com")
            || host.contains("kagi.com")

        if usesQParam {
            if let searchQuery = queryItems.first(where: { $0.name == "q" }) {
                return [searchQuery]
            }
        }

        // Yahoo uses 'p' parameter
        if host.contains("yahoo.com") {
            if let searchQuery = queryItems.first(where: { $0.name == "p" }) {
                return [searchQuery]
            }
        }

        // For other sites, keep all query items
        return queryItems.isEmpty ? nil : queryItems
    }
    
    // MARK: - Querying (Async - Background Actor)

    /// Search history by query string.
    ///
    /// Uses the indexed `searchableText` field for efficient database-level
    /// filtering. Runs on background actor to avoid blocking main thread.
    func search(query: String, limit: Int = 50) async -> [HistoryEntryData] {
        guard let queryActor else { return [] }
        return await queryActor.search(query: query, limit: limit)
    }

    /// Get history entries within a date range.
    ///
    /// Runs on background actor to avoid blocking main thread.
    func entries(from startDate: Date, to endDate: Date) async -> [HistoryEntryData] {
        guard let queryActor else { return [] }
        return await queryActor.entries(from: startDate, to: endDate)
    }

    /// Get most visited URLs (grouped by URL, sorted by visit count).
    ///
    /// Fetches entries from the last 90 days and groups by URL to count visits.
    /// Runs on background actor as this is an expensive aggregation.
    ///
    /// - Parameter limit: Maximum number of results to return.
    /// - Returns: Array of most recent entries for each URL, ordered by visit frequency.
    func mostVisited(limit: Int = 20) async -> [HistoryEntryData] {
        guard let queryActor else { return [] }
        return await queryActor.mostVisited(limit: limit)
    }

    /// Get entries for a specific domain.
    ///
    /// Runs on background actor to avoid blocking main thread.
    func entries(forDomain domain: String) async -> [HistoryEntryData] {
        guard let queryActor else { return [] }
        return await queryActor.entries(forDomain: domain)
    }

    // MARK: - Querying (Sync - Main Thread)

    /// Get the active history entry for a tab.
    ///
    /// This is a fast in-memory lookup, runs on main thread.
    func activeEntry(for tabID: UUID) -> HistoryEntry? {
        activeEntries[tabID]
    }

    /// Get history entries within a date range (synchronous, main thread).
    ///
    /// Returns full `HistoryEntry` objects including parent relationships.
    /// Used by `HistoryGraphView` which needs parent information for arrow drawing.
    ///
    /// - Note: For most use cases, prefer the async `entries(from:to:)` which returns
    /// `HistoryEntryData` and runs on a background actor.
    func entriesSync(from startDate: Date, to endDate: Date) -> [HistoryEntry] {
        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { entry in
                entry.visitedAt >= startDate && entry.visitedAt <= endDate
            },
            sortBy: [SortDescriptor(\.visitedAt, order: .reverse)],
        )

        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Logger.error("Failed to fetch history entries: \(error)", category: Logger.data)
            return []
        }
    }

    // MARK: - Tab Snapshots

    /// Create a snapshot of current tabs.
    ///
    /// This method creates a point-in-time capture of all open tabs for crash recovery.
    /// Snapshots are deduplicated using content hashing - if the tab state hasn't changed
    /// since the last snapshot, no new record is created.
    ///
    /// Typically called by ``ScheduledTasksManager`` on its hourly schedule for
    /// background crash recovery, or explicitly by user actions.
    func createSnapshot(tabs: [Tab], activeTab: Tab?) {
        // Don't create snapshots in private spaces
        if isCurrentSpacePrivate() {
            Logger.debug("Skipping snapshot in private space", category: Logger.data)
            return
        }

        let items = makeSnapshotItems(from: tabs)
        let snapshot = TabSnapshot(
            spaceID: currentSpaceID,
            items: items,
            activeTabID: activeTab?.id,
        )

        // Check if snapshot is different from last one
        if let lastHash = lastSnapshotHash, lastHash == snapshot.contentHash {
            Logger.debug("Skipping duplicate snapshot", category: Logger.data)
            return
        }

        modelContext.insert(snapshot)
        lastSnapshotHash = snapshot.contentHash

        // Periodic operation: use immediate save (happens every 15 minutes)
        saveImmediately()
        Logger.info("Created tab snapshot with \(items.count) tabs", category: Logger.data)
    }

    /// Create a manual snapshot, bypassing deduplication.
    ///
    /// Use this for user-triggered "Save Snapshot Now" actions where the user
    /// explicitly wants to capture the current state regardless of whether
    /// it matches the last automatic snapshot.
    ///
    /// - Parameters:
    ///   - tabs: The tabs to snapshot.
    ///   - activeTab: The currently active tab.
    /// - Returns: `true` if the snapshot was created, `false` if skipped (e.g., private space).
    @discardableResult
    func createManualSnapshot(tabs: [Tab], activeTab: Tab?) -> Bool {
        // Don't create snapshots in private spaces
        if isCurrentSpacePrivate() {
            Logger.debug("Skipping manual snapshot in private space", category: Logger.data)
            return false
        }

        let items = makeSnapshotItems(from: tabs)
        let snapshot = TabSnapshot(
            spaceID: currentSpaceID,
            items: items,
            activeTabID: activeTab?.id,
        )

        // Manual snapshots bypass deduplication check
        modelContext.insert(snapshot)
        lastSnapshotHash = snapshot.contentHash

        saveImmediately()
        Logger.info("Created manual tab snapshot with \(items.count) tabs", category: Logger.data)
        return true
    }

    /// Creates snapshot items from tabs, capturing favicon data within size limit.
    private func makeSnapshotItems(from tabs: [Tab]) -> [TabSnapshotItem] {
        tabs.map { tab in
            // Capture favicon data if available and within size limit (10KB)
            let faviconData: Data? = {
                guard let data = tab.activePage.faviconData else { return nil }
                return data.count <= 10_240 ? data : nil
            }()

            return TabSnapshotItem(
                tabID: tab.id,
                url: tab.activePage.url,
                title: tab.activePage.title,
                position: tab.position,
                isPinned: tab.isPinned,
                groupID: tab.groupID,
                customName: tab.customName,
                faviconData: faviconData,
            )
        }
    }

    /// Get the most recent snapshot
    func latestSnapshot() -> TabSnapshot? {
        let descriptor = FetchDescriptor<TabSnapshot>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)],
        )
        
        do {
            let snapshots = try modelContext.fetch(descriptor)
            return snapshots.first
        } catch {
            Logger.error("Failed to fetch latest snapshot: \(error)", category: Logger.data)
            return nil
        }
    }
    
    /// Get all snapshots within a date range
    func snapshots(from startDate: Date, to endDate: Date) -> [TabSnapshot] {
        let descriptor = FetchDescriptor<TabSnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.createdAt >= startDate &&
                    snapshot.createdAt <= endDate
            },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)],
        )
        
        do {
            return try modelContext.fetch(descriptor)
        } catch {
            Logger.error("Failed to fetch snapshots: \(error)", category: Logger.data)
            return []
        }
    }
    
    // MARK: - Cleanup

    /// Delete history entries older than the specified date
    func deleteEntriesBefore(date: Date) {
        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { entry in
                entry.visitedAt < date
            },
        )

        do {
            let oldEntries = try modelContext.fetch(descriptor)
            for entry in oldEntries {
                modelContext.delete(entry)
            }
            // User-triggered cleanup: use immediate save
            saveImmediately()

            Logger.info("Deleted \(oldEntries.count) old history entries", category: Logger.data)
        } catch {
            Logger.error("Failed to delete old entries: \(error)", category: Logger.data)
        }
    }

    /// Delete all history entries for a specific domain
    ///
    /// - Parameter domain: The domain to delete history for (e.g., "example.com")
    func deleteEntries(forDomain domain: String) {
        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { entry in
                entry.domain == domain
            },
        )

        do {
            let entries = try modelContext.fetch(descriptor)
            for entry in entries {
                modelContext.delete(entry)
            }
            // User-triggered cleanup: use immediate save
            saveImmediately()

            // Clear from active entries
            activeEntries = activeEntries.filter { $0.value.domain != domain }

            Logger.info("Deleted \(entries.count) entries for domain: \(domain)", category: Logger.data)
        } catch {
            Logger.error("Failed to delete entries for domain \(domain): \(error)", category: Logger.data)
        }
    }

    /// Delete all history entries for multiple domains
    ///
    /// - Parameter domains: Set of domains to delete history for
    func deleteEntries(forDomains domains: Set<String>) {
        for domain in domains {
            deleteEntries(forDomain: domain)
        }
    }

    /// Delete a specific history entry by ID.
    ///
    /// - Parameter id: The UUID of the history entry to delete.
    func deleteEntry(_ id: UUID) {
        let descriptor = FetchDescriptor<HistoryEntry>(
            predicate: #Predicate { entry in
                entry.id == id
            },
        )

        do {
            if let entry = try modelContext.fetch(descriptor).first {
                modelContext.delete(entry)
                scheduleSave()
                Logger.info("Deleted history entry: \(entry.url.absoluteString)", category: Logger.data)
            }
        } catch {
            Logger.error("Failed to delete history entry: \(error)", category: Logger.data)
        }
    }

    /// Get all unique domains in history from the last year.
    ///
    /// Limits the query to recent history for performance. Uses the domain index
    /// for efficient scanning. Runs on background actor.
    ///
    /// - Returns: Sorted array of unique domain names
    func allDomains() async -> [String] {
        guard let queryActor else { return [] }
        return await queryActor.allDomains()
    }

    /// Delete all history
    func clearAllHistory() {
        let entryDescriptor = FetchDescriptor<HistoryEntry>()
        let snapshotDescriptor = FetchDescriptor<TabSnapshot>()

        do {
            let entries = try modelContext.fetch(entryDescriptor)
            let snapshots = try modelContext.fetch(snapshotDescriptor)

            for entry in entries {
                modelContext.delete(entry)
            }

            for snapshot in snapshots {
                modelContext.delete(snapshot)
            }

            // Critical user-triggered operation: use immediate save
            saveImmediately()

            activeEntries.removeAll()
            frequentDestinations.clear()
            lastSnapshotHash = nil

            Logger.info("Cleared all browsing history", category: Logger.data)
        } catch {
            Logger.error("Failed to clear history: \(error)", category: Logger.data)
        }
    }
    
    /// Delete snapshots older than the specified date
    func deleteSnapshotsBefore(date: Date) {
        let descriptor = FetchDescriptor<TabSnapshot>(
            predicate: #Predicate { snapshot in
                snapshot.createdAt < date
            },
        )

        do {
            let oldSnapshots = try modelContext.fetch(descriptor)
            for snapshot in oldSnapshots {
                modelContext.delete(snapshot)
            }
            // Maintenance cleanup: use immediate save
            saveImmediately()

            Logger.info("Deleted \(oldSnapshots.count) old snapshots", category: Logger.data)
        } catch {
            Logger.error("Failed to delete old snapshots: \(error)", category: Logger.data)
        }
    }
    
    // MARK: - Statistics (Async - Background Actor)

    /// Get total time spent on a domain for a specific date.
    ///
    /// Runs on background actor for expensive queries.
    ///
    /// - Parameters:
    ///   - domain: The domain to calculate time for (e.g., "developer.apple.com").
    ///   - date: The date to calculate time for (uses day granularity).
    /// - Returns: Total time spent in seconds, or 0 if no entries found.
    func timeSpent(on domain: String, for date: Date) async -> TimeInterval {
        guard let queryActor else { return 0 }
        return await queryActor.timeSpent(on: domain, for: date)
    }

    /// Get total number of history entries.
    ///
    /// Fast count query, runs on main thread.
    func totalEntryCount() -> Int {
        let descriptor = FetchDescriptor<HistoryEntry>()

        do {
            return try modelContext.fetchCount(descriptor)
        } catch {
            Logger.error("Failed to count history entries: \(error)", category: Logger.data)
            return 0
        }
    }

    /// Get total time spent browsing.
    ///
    /// Uses paginated fetching on background actor.
    func totalTimeSpent() async -> TimeInterval {
        guard let queryActor else { return 0 }
        return await queryActor.totalTimeSpent()
    }

    // MARK: - Persistence

    /// Schedules a debounced save with utility priority.
    ///
    /// Multiple calls within the debounce window are coalesced into a single
    /// save operation. This is critical for performance during rapid navigation
    /// when titles and entry states are updated frequently.
    private func scheduleSave() {
        saver.scheduleSave()
    }

    /// Performs an immediate save, cancelling any pending debounced save.
    ///
    /// Use for critical operations where data loss is unacceptable:
    /// - App termination
    /// - Clear all history
    /// - Explicit user-triggered operations
    private func saveImmediately() {
        saver.saveImmediatelySync()
    }
}
