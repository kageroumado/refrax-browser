import Foundation
import SwiftUI

/// Manages offline storage of webpage content for bookmarks.
///
/// Uses macOS Web Archive format (`.webarchive`) to save complete webpage snapshots
/// for offline viewing. Storage is manual-only—users explicitly choose what to preserve.
///
/// ## Storage Location
///
/// Files are stored in:
/// ```
/// ~/Library/Application Support/website.refrax.browser/OfflineContent/
/// ├── <bookmark-uuid-1>.webarchive
/// ├── <bookmark-uuid-2>.webarchive
/// └── ...
/// ```
///
/// ## Architecture
///
/// ```
/// User triggers "Save Offline"
///         │
///         ▼
///   OfflineContentManager.saveOffline(webPage:for:)
///         │
///         ├── WebPage.exportAsWebArchive()
///         │
///         ▼
///   Store in Application Support
///         │
///         ├── Update Bookmark.offlineStatus
///         ├── Update Bookmark.offlineDataPath
///         ├── Update Bookmark.offlineSavedAt
///         └── Update Bookmark.offlineFileSize
/// ```
@Observable
final class OfflineContentManager {
    // MARK: - Constants

    private enum Constants {
        /// Default maximum storage in bytes (500 MB).
        static let defaultMaxStorageBytes: Int64 = 500_000_000
        /// Warning threshold as a fraction of max storage.
        static let warningThreshold: Double = 0.8
    }

    // MARK: - Properties

    /// Total bytes used by offline content.
    private(set) var totalStorageUsed: Int64 = 0

    /// Maximum allowed storage in bytes.
    var maxStorageBytes: Int64 {
        didSet {
            UserDefaults.standard.set(maxStorageBytes, forKey: "offlineStorageLimit")
        }
    }

    /// Whether storage is approaching the limit.
    var isNearLimit: Bool {
        Double(totalStorageUsed) > Double(maxStorageBytes) * Constants.warningThreshold
    }

    /// Whether storage limit has been exceeded.
    var isOverLimit: Bool {
        totalStorageUsed >= maxStorageBytes
    }

    /// The offline content storage directory.
    nonisolated static let storageDirectory: URL = {
        let directory = Directories.appStorage.appendingPathComponent("OfflineContent", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }()

    // MARK: - Initialization

    init() {
        self.maxStorageBytes = Int64(UserDefaults.standard.integer(forKey: "offlineStorageLimit"))
        if maxStorageBytes == 0 {
            self.maxStorageBytes = Constants.defaultMaxStorageBytes
        }
        calculateStorageUsed()
    }

    // MARK: - Save Offline

    /// Saves a webpage for offline viewing.
    ///
    /// - Parameters:
    ///   - webPage: The WebPage to capture.
    ///   - bookmark: The bookmark to associate with the offline content.
    /// - Throws: Error if web archive creation or file writing fails.
    func saveOffline(webPage: WebPage, for bookmark: Bookmark) async throws {
        // Check storage limit
        guard !isOverLimit else {
            throw OfflineError.storageLimitExceeded
        }

        // Update status to saving
        bookmark.offlineStatus = .downloadingHTML

        do {
            // Generate web archive data
            let archiveData = try await webPage.exportAsWebArchive()

            // Generate filename
            let filename = "\(bookmark.id.uuidString).webarchive"
            let fileURL = Self.storageDirectory.appendingPathComponent(filename)

            // Calculate net storage change (accounting for existing file if updating)
            let existingFileSize = bookmark.offlineFileSize ?? 0
            let netIncrease = Int64(archiveData.count) - existingFileSize
            let newTotal = totalStorageUsed + netIncrease

            // Check if this would exceed limit
            guard newTotal <= maxStorageBytes else {
                bookmark.offlineStatus = .failed
                throw OfflineError.storageLimitExceeded
            }

            // Delete existing file if present
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try? FileManager.default.removeItem(at: fileURL)
            }

            try archiveData.write(to: fileURL)

            // Update bookmark metadata
            bookmark.offlineStatus = .availableHTML
            bookmark.offlineDataPath = filename
            bookmark.offlineSavedAt = Date()
            bookmark.offlineFileSize = Int64(archiveData.count)

            // Update storage tracking
            calculateStorageUsed()

            Logger.info(
                "Saved offline content for '\(bookmark.title)' (\(formattedSize(Int64(archiveData.count))))",
                category: Logger.storage,
            )
        } catch {
            bookmark.offlineStatus = .failed
            Logger.error("Failed to save offline content: \(error)", category: Logger.storage)
            throw error
        }
    }

    // MARK: - Save from Tab

    /// Saves a bookmark's content offline, loading the page if necessary.
    ///
    /// This is the high-level API for views to trigger an offline save. It handles:
    /// 1. Using an existing WebPage if one matches the bookmark URL
    /// 2. Opening a new tab and waiting for load if no matching page exists
    /// 3. Error handling and logging
    ///
    /// - Parameters:
    ///   - bookmark: The bookmark to save offline.
    ///   - activePageID: The currently active page ID (to check for URL match).
    ///   - tabManager: TabManager for accessing pages and creating tabs.
    func saveBookmarkOffline(
        _ bookmark: Bookmark,
        activePageID: TabPage.ID?,
        tabManager: TabManager,
    ) {
        // Check if the active page matches the bookmark URL
        if let activePageID,
           let webPage = tabManager.state.webPage(for: activePageID),
           webPage.url == bookmark.url {
            // Save from active page
            Task {
                do {
                    try await saveOffline(webPage: webPage, for: bookmark)
                } catch {
                    Logger.error("Failed to save offline: \(error)", category: Logger.storage)
                }
            }
            return
        }

        // Page not currently active - open it first and save after load
        let tab = tabManager.createTab(url: bookmark.url, makeActive: true)
        Task {
            // Wait for the page to finish loading
            let pageID = tab.activePage.id

            // Poll for page to be ready (up to 30 seconds)
            var attempts = 0
            while attempts < 60 {
                if let webPage = tabManager.state.webPage(for: pageID),
                   !webPage.isLoading {
                    do {
                        try await saveOffline(webPage: webPage, for: bookmark)
                    } catch {
                        Logger.error("Failed to save offline: \(error)", category: Logger.storage)
                    }
                    return
                }
                try? await Task.sleep(for: .milliseconds(500))
                attempts += 1
            }

            // Timed out waiting for page load
            bookmark.offlineStatus = .failed
            Logger.error("Timed out waiting for page to load for offline save", category: Logger.storage)
        }
    }

    // MARK: - Load Offline

    /// Gets the file URL for a bookmark's offline content.
    ///
    /// - Parameter bookmark: The bookmark to get offline content for.
    /// - Returns: The file URL, or nil if not available.
    func offlineContentURL(for bookmark: Bookmark) -> URL? {
        guard let path = bookmark.offlineDataPath else { return nil }
        let fileURL = Self.storageDirectory.appendingPathComponent(path)

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            // File missing, update status
            bookmark.offlineStatus = .notSaved
            bookmark.offlineDataPath = nil
            bookmark.offlineSavedAt = nil
            bookmark.offlineFileSize = nil
            return nil
        }

        return fileURL
    }

    /// Checks if offline content is available for a bookmark.
    ///
    /// - Parameter bookmark: The bookmark to check.
    /// - Returns: True if offline content exists and is accessible.
    func hasOfflineContent(for bookmark: Bookmark) -> Bool {
        offlineContentURL(for: bookmark) != nil
    }

    // MARK: - Delete Offline

    /// Deletes offline content for a bookmark.
    ///
    /// - Parameter bookmark: The bookmark whose offline content should be deleted.
    func deleteOfflineContent(for bookmark: Bookmark) {
        guard let path = bookmark.offlineDataPath else { return }
        let fileURL = Self.storageDirectory.appendingPathComponent(path)

        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                try FileManager.default.removeItem(at: fileURL)
            }
        } catch {
            Logger.error("Failed to delete offline content: \(error)", category: Logger.storage)
        }

        bookmark.offlineStatus = .notSaved
        bookmark.offlineDataPath = nil
        bookmark.offlineSavedAt = nil
        bookmark.offlineFileSize = nil

        calculateStorageUsed()
    }

    /// Deletes offline content for multiple bookmarks.
    ///
    /// - Parameter bookmarks: The bookmarks whose offline content should be deleted.
    func deleteOfflineContent(for bookmarks: [Bookmark]) {
        for bookmark in bookmarks {
            deleteOfflineContent(for: bookmark)
        }
    }

    // MARK: - Storage Management

    /// Recalculates the total storage used by offline content.
    func calculateStorageUsed() {
        let enumerator = FileManager.default.enumerator(
            at: Self.storageDirectory,
            includingPropertiesForKeys: [.fileSizeKey],
        )

        var total: Int64 = 0
        while let fileURL = enumerator?.nextObject() as? URL {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                total += Int64(size)
            }
        }
        totalStorageUsed = total
    }

    /// Cleans up orphaned offline content files that have no associated bookmark.
    ///
    /// - Parameter bookmarks: All bookmarks to check against.
    /// - Returns: Number of orphaned files deleted.
    @discardableResult
    func cleanupOrphanedContent(bookmarks: [Bookmark]) -> Int {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: Self.storageDirectory,
            includingPropertiesForKeys: nil,
        ) else { return 0 }

        let validPaths = Set(bookmarks.compactMap(\.offlineDataPath))
        var deletedCount = 0

        for fileURL in files {
            let filename = fileURL.lastPathComponent
            if !validPaths.contains(filename) {
                try? fm.removeItem(at: fileURL)
                deletedCount += 1
            }
        }

        if deletedCount > 0 {
            calculateStorageUsed()
            Logger.info("Cleaned up \(deletedCount) orphaned offline content files", category: Logger.storage)
        }

        return deletedCount
    }

    // MARK: - Formatting

    /// Formats a byte count for display.
    var formattedStorageUsed: String {
        formattedSize(totalStorageUsed)
    }

    /// Formats the storage limit for display.
    var formattedStorageLimit: String {
        formattedSize(maxStorageBytes)
    }

    /// Formats a byte count for display.
    private func formattedSize(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    // MARK: - Errors

    enum OfflineError: LocalizedError {
        case storageLimitExceeded
        case fileNotFound
        case saveFailed(any Error)

        var errorDescription: String? {
            switch self {
            case .storageLimitExceeded:
                "Offline storage limit exceeded. Delete some offline content to free up space."
            case .fileNotFound:
                "Offline content file not found."
            case let .saveFailed(error):
                "Failed to save offline content: \(error.localizedDescription)"
            }
        }
    }
}
