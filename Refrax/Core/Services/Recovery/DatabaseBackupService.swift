import Foundation

/// Periodic database backups for recovery safety.
///
/// Creates daily backups of the SwiftData store file, maintaining a rolling
/// window of recent backups. Designed to be called from `ScheduledTasksManager`
/// as part of deferred maintenance.
///
/// Backup directory: `Directories.appStorage/"Backups"/`
nonisolated enum DatabaseBackupService: Sendable {
    /// Root directory for all database backups.
    static let backupsDirectory: URL = Directories.appStorage
        .appendingPathComponent("Backups", isDirectory: true)

    /// Maximum number of backups to retain.
    private static let maxBackupCount = 3

    /// Maximum age of backups before pruning, in days.
    private static let maxRetentionDays = 7

    // MARK: - Scheduled Backup

    /// Creates a backup if none exists from today.
    ///
    /// Skips the backup if a directory matching today's date prefix already exists
    /// in the backups directory. This makes it safe to call repeatedly from the
    /// scheduled task manager without creating redundant copies.
    ///
    /// - Parameter storeURL: Path to the `.store` file.
    static func performScheduledBackup(storeURL: URL) {
        let fm = FileManager.default

        guard fm.fileExists(atPath: storeURL.path) else {
            Logger.debug("Skipping backup: store file does not exist", category: Logger.storage)
            return
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let todayPrefix = formatter.string(from: Date.now)

        let existing = (try? fm.contentsOfDirectory(atPath: backupsDirectory.path)) ?? []
        let alreadyBackedUp = existing.contains { $0.hasPrefix(todayPrefix) }

        if alreadyBackedUp {
            Logger.debug("Skipping backup: already backed up today", category: Logger.storage)
            return
        }

        do {
            try DatabaseRecoveryService.backup(storeURL: storeURL)
        } catch {
            Logger.error("Scheduled backup failed: \(error.localizedDescription)", category: Logger.storage)
        }
    }

    // MARK: - Pruning

    /// Removes backups older than the retention period, keeping at most the configured maximum.
    ///
    /// Pruning strategy:
    /// 1. Remove any backup older than 7 days
    /// 2. If more than 3 backups remain, remove the oldest until 3 remain
    static func pruneOldBackups() {
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles],
        ) else {
            return
        }

        let cutoff = Calendar.current.date(
            byAdding: .day,
            value: -maxRetentionDays,
            to: Date.now,
        ) ?? Date.distantPast

        var remaining: [(url: URL, date: Date)] = []

        for entry in entries {
            let date = backupDate(from: entry) ?? Date.distantPast

            if date < cutoff {
                removeBackup(at: entry)
            } else {
                remaining.append((entry, date))
            }
        }

        if remaining.count > maxBackupCount {
            remaining.sort { $0.date < $1.date }
            let toRemove = remaining.count - maxBackupCount
            for i in 0 ..< toRemove {
                removeBackup(at: remaining[i].url)
            }
        }
    }

    // MARK: - Query

    /// Lists available backups sorted by date, newest first.
    ///
    /// - Returns: Array of backup URLs with their associated dates.
    static func availableBackups() -> [(url: URL, date: Date)] {
        let fm = FileManager.default

        guard let entries = try? fm.contentsOfDirectory(
            at: backupsDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles],
        ) else {
            return []
        }

        var backups: [(url: URL, date: Date)] = []
        for entry in entries {
            if let date = backupDate(from: entry) {
                backups.append((entry, date))
            }
        }

        backups.sort { $0.date > $1.date }
        return backups
    }

    // MARK: - Private Helpers

    /// Extracts the date from a backup directory name (format: `yyyy-MM-dd_HHmmss`).
    private static func backupDate(from url: URL) -> Date? {
        let name = url.lastPathComponent
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        return formatter.date(from: name)
    }

    /// Removes a backup directory, logging any errors.
    private static func removeBackup(at url: URL) {
        do {
            try FileManager.default.removeItem(at: url)
            Logger.info("Pruned old backup: \(url.lastPathComponent)", category: Logger.storage)
        } catch {
            Logger.error(
                "Failed to prune backup \(url.lastPathComponent): \(error.localizedDescription)",
                category: Logger.storage,
            )
        }
    }
}
