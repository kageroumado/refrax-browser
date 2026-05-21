import Foundation
import SwiftData

/// Service for automatic history maintenance and cleanup.
///
/// All heavy maintenance operations run on a background `HistoryMaintenanceActor`
/// to avoid blocking the main thread.
///
/// Respects user settings from ``BrowserSettings`` for automatic cleanup:
/// - ``BrowserSettings/automaticHistoryCleanup``: Whether to enable automatic deletion
/// - ``BrowserSettings/historyRetentionDays``: How long to retain history
///
/// ## Scheduling
///
/// This service is designed to be registered with ``ScheduledTasksManager``, which
/// runs hourly. The service internally tracks when maintenance last ran and only
/// performs expensive operations if 24 hours have passed.
///
/// ```swift
/// scheduledTasksManager.registerTask { @MainActor in
///     await historyMaintenanceService.performMaintenanceIfNeeded()
/// }
/// ```
final class HistoryMaintenanceService {
    // MARK: - Properties

    private let historyManager: HistoryManager
    private let modelContainer: ModelContainer
    private let settings: BrowserSettings

    /// Timestamp of the last maintenance run.
    ///
    /// Used to ensure expensive maintenance only runs once per day,
    /// even though ScheduledTasksManager calls us hourly.
    private var lastMaintenanceRun: Date?

    // MARK: - Configuration

    struct Configuration {
        /// Maximum age of snapshots before deletion (in days)
        var snapshotRetentionDays: Int = 90

        /// Maximum number of snapshots to keep
        var maxSnapshotCount: Int = 1_000

        /// How often to run maintenance (in seconds)
        var maintenanceInterval: TimeInterval = 86_400 // 24 hours

        /// Whether to optimize database after cleanup
        var optimizeAfterCleanup: Bool = true
    }

    private var configuration: Configuration

    // MARK: - Initialization

    init(
        historyManager: HistoryManager,
        modelContainer: ModelContainer,
        settings: BrowserSettings,
        configuration: Configuration = Configuration(),
    ) {
        self.historyManager = historyManager
        self.modelContainer = modelContainer
        self.settings = settings
        self.configuration = configuration
    }
    
    // MARK: - Maintenance

    /// Performs maintenance if enough time has passed since the last run.
    ///
    /// This method is designed to be called by ``ScheduledTasksManager`` on its
    /// hourly schedule. It internally checks if 24 hours have elapsed before
    /// performing expensive operations.
    ///
    /// Safe to call frequently - early exits if maintenance was performed recently.
    func performMaintenanceIfNeeded() async {
        // Check if 24 hours have passed since last maintenance
        if let lastRun = lastMaintenanceRun {
            let elapsed = Date().timeIntervalSince(lastRun)
            guard elapsed >= configuration.maintenanceInterval else {
                Logger.debug("Skipping history maintenance - only \(Int(elapsed / 3_600))h since last run", category: Logger.data)
                return
            }
        }

        await performMaintenance()
    }

    /// Perform maintenance tasks on background actor.
    ///
    /// Creates a fresh `HistoryMaintenanceActor` for this maintenance pass,
    /// runs all heavy SwiftData operations there, then updates the main thread
    /// cache with the results.
    private func performMaintenance() async {
        lastMaintenanceRun = Date()
        Logger.info("Starting history maintenance", category: Logger.data)

        // Create a background actor for this maintenance pass
        let actor = HistoryMaintenanceActor(modelContainer: modelContainer)

        // Clean old entries (if automatic cleanup enabled)
        if settings.automaticHistoryCleanup {
            let retentionDays = settings.historyRetentionDays
            if retentionDays > 0 {
                let deletedCount = await actor.cleanOldEntries(retentionDays: retentionDays)
                if deletedCount > 0 {
                    Logger.info("Cleaned \(deletedCount) history entries older than \(retentionDays) days", category: Logger.data)
                }
            }
        }

        // Clean old snapshots (use settings or fallback to configuration)
        let retentionDays = settings.snapshotRetentionDays > 0 ? settings.snapshotRetentionDays : configuration.snapshotRetentionDays
        let deletedSnapshots = await actor.cleanOldSnapshots(retentionDays: retentionDays)
        if deletedSnapshots > 0 {
            Logger.info("Cleaned \(deletedSnapshots) old snapshots", category: Logger.data)
        }

        // Trim excess snapshots (use settings or fallback to configuration)
        let maxCount = settings.maxSnapshotCount > 0 ? settings.maxSnapshotCount : configuration.maxSnapshotCount
        let trimmedSnapshots = await actor.trimExcessSnapshots(maxCount: maxCount)
        if trimmedSnapshots > 0 {
            Logger.info("Trimmed \(trimmedSnapshots) excess snapshots", category: Logger.data)
        }

        // Rebuild frequent destinations cache
        let destinationData = await actor.fetchRecentEntriesForFrequentDestinations()
        await MainActor.run {
            historyManager.frequentDestinations.rebuild(from: destinationData)
        }

        Logger.info("History maintenance completed", category: Logger.data)
    }
    
    // MARK: - Manual Cleanup
    
    /// Manually clean history older than specified days
    func cleanHistory(olderThan days: Int) {
        guard let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -days,
            to: Date(),
        ) else { return }
        
        historyManager.deleteEntriesBefore(date: cutoffDate)
        Logger.info("Manually cleaned history older than \(days) days", category: Logger.data)
    }
    
    /// Manually clean snapshots older than specified days
    func cleanSnapshots(olderThan days: Int) {
        guard let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -days,
            to: Date(),
        ) else { return }
        
        historyManager.deleteSnapshotsBefore(date: cutoffDate)
        Logger.info("Manually cleaned snapshots older than \(days) days", category: Logger.data)
    }
    
    // MARK: - Configuration

    /// Update maintenance configuration
    func updateConfiguration(_ configuration: Configuration) {
        self.configuration = configuration
    }
}

// MARK: - Statistics

extension HistoryMaintenanceService {
    /// Get maintenance statistics
    struct Statistics {
        let totalEntries: Int
        let totalSnapshots: Int
        let oldestEntry: Date?
        let newestEntry: Date?
        let totalTimeSpent: TimeInterval
        let databaseSize: Int64? // in bytes, if available
    }
    
    func getStatistics() async -> Statistics {
        // This would need to query the database for various metrics
        await Statistics(
            totalEntries: historyManager.totalEntryCount(),
            totalSnapshots: 0, // Implement snapshot count
            oldestEntry: nil,
            newestEntry: nil,
            totalTimeSpent: historyManager.totalTimeSpent(),
            databaseSize: nil,
        )
    }
}

// MARK: - Export/Import (Future Feature)

extension HistoryMaintenanceService {
    /// Export history to JSON
    func exportHistory(to _: URL) async throws {
        // Future implementation for exporting history
        Logger.info("History export not yet implemented", category: Logger.data)
    }
    
    /// Import history from JSON
    func importHistory(from _: URL) async throws {
        // Future implementation for importing history
        Logger.info("History import not yet implemented", category: Logger.data)
    }
}
