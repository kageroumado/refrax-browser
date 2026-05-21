import Foundation
import SwiftData

// MARK: - Import/Export

extension BookmarksManager {
    // MARK: - Export

    /// Export all bookmarks to an HTML file.
    ///
    /// - Returns: Export result with URL and count
    /// - Throws: Export errors
    func exportToHTMLFile() async throws -> BookmarkExporter.ExportResult {
        let exporter = BookmarkExporter(modelContainer: _modelContext.container)
        return try await exporter.exportToHTML()
    }

    /// Export all bookmarks to a JSON file.
    ///
    /// - Returns: Export result with URL and count
    /// - Throws: Export errors
    func exportToJSONFile() async throws -> BookmarkExporter.ExportResult {
        let exporter = BookmarkExporter(modelContainer: _modelContext.container)
        return try await exporter.exportToJSON()
    }

    /// Get total bookmark count for export summary.
    ///
    /// - Returns: Number of bookmarks that would be exported
    func totalBookmarkCount() throws -> Int {
        let exporter = BookmarkExporter(modelContainer: _modelContext.container)
        return try exporter.countBookmarks()
    }

    // MARK: - Import

    /// Import bookmarks from an HTML file using the HTMLBookmarkImporter.
    ///
    /// This method parses the HTML file and returns the folder hierarchy for preview.
    /// Use `commitImport(_:)` to actually save the bookmarks after user confirmation.
    ///
    /// - Parameter url: URL of HTML bookmarks file
    /// - Returns: Array of imported folders for preview
    /// - Throws: Import parsing errors
    func parseBookmarksFile(from url: URL) async throws -> [ImportedFolder] {
        let importer = HTMLBookmarkImporter()
        return try await importer.importBookmarks(from: url)
    }

    /// Commit imported folders to the database.
    ///
    /// This method creates actual BookmarkFolder and Bookmark entities from
    /// the imported data, handling folder conflicts by merging.
    ///
    /// - Parameter folders: Imported folder hierarchy from `parseBookmarksFile`
    /// - Returns: Import result with counts and any failures
    func commitImport(_ folders: [ImportedFolder]) -> ImportResult {
        var bookmarksImported = 0
        var foldersCreated = 0
        var duplicatesSkipped = 0
        var failedBookmarks: [ImportResult.FailedBookmark] = []

        for importedFolder in folders {
            let result = importFolder(importedFolder, parent: nil)
            bookmarksImported += result.bookmarksImported
            foldersCreated += result.foldersCreated
            duplicatesSkipped += result.duplicatesSkipped
            failedBookmarks.append(contentsOf: result.failedBookmarks)
        }

        scheduleSave()

        Logger.info(
            "Import complete: \(bookmarksImported) bookmarks, \(foldersCreated) folders, \(duplicatesSkipped) duplicates skipped",
            category: Logger.data,
        )

        return ImportResult(
            bookmarksImported: bookmarksImported,
            foldersCreated: foldersCreated,
            duplicatesSkipped: duplicatesSkipped,
            failedBookmarks: failedBookmarks,
        )
    }

    /// Find folders that would conflict (merge) during import.
    ///
    /// - Parameter importedFolders: Folders to check
    /// - Returns: Names of existing folders that would be merged
    func findConflictingFolders(_ importedFolders: [ImportedFolder]) -> [String] {
        var conflicts: [String] = []
        let existingFolderNames = Set(rootFolders().map { $0.name.lowercased() })

        // Pre-lowercase folder names to avoid repeated lowercasing in the loop
        let lowercasedImportedNames = importedFolders.map { ($0, $0.name.lowercased()) }

        for (folder, lowercasedName) in lowercasedImportedNames {
            if existingFolderNames.contains(lowercasedName) {
                conflicts.append(folder.name)
            }
            // Check subfolders recursively
            conflicts.append(contentsOf: findNestedConflicts(folder, existingNames: existingFolderNames))
        }

        return conflicts
    }

    // MARK: - Private Import Helpers

    private func importFolder(_ imported: ImportedFolder, parent: BookmarkFolder?) -> ImportResult {
        var bookmarksImported = 0
        var foldersCreated = 0
        var duplicatesSkipped = 0
        var failedBookmarks: [ImportResult.FailedBookmark] = []

        // Find or create folder
        let folder: BookmarkFolder
        if let existing = findExistingFolder(name: imported.name, parent: parent) {
            folder = existing
        } else {
            do {
                folder = try createFolder(name: imported.name, parent: parent)
                foldersCreated += 1
            } catch {
                Logger.warning("Failed to create folder '\(imported.name)': \(error)", category: Logger.data)
                // Skip this folder's contents
                return ImportResult(
                    bookmarksImported: 0,
                    foldersCreated: 0,
                    duplicatesSkipped: 0,
                    failedBookmarks: imported.bookmarks.map {
                        ImportResult.FailedBookmark(bookmark: $0, reason: "Parent folder creation failed")
                    },
                )
            }
        }

        // Import bookmarks into folder
        // Pre-lowercase existing URLs once for the set
        let existingURLs = Set(folder.bookmarks.map { $0.url.absoluteString.lowercased() })
        // Pre-lowercase imported bookmark URLs to avoid repeated lowercasing in the loop
        let bookmarksWithLowercasedURLs = imported.bookmarks.map { ($0, $0.url.absoluteString.lowercased()) }

        for (bookmark, lowercasedURL) in bookmarksWithLowercasedURLs {
            if existingURLs.contains(lowercasedURL) {
                duplicatesSkipped += 1
                continue
            }

            createBookmark(
                url: bookmark.url,
                title: bookmark.title,
                folder: folder,
            )
            bookmarksImported += 1
        }

        // Import subfolders recursively
        for subfolder in imported.subfolders {
            let result = importFolder(subfolder, parent: folder)
            bookmarksImported += result.bookmarksImported
            foldersCreated += result.foldersCreated
            duplicatesSkipped += result.duplicatesSkipped
            failedBookmarks.append(contentsOf: result.failedBookmarks)
        }

        return ImportResult(
            bookmarksImported: bookmarksImported,
            foldersCreated: foldersCreated,
            duplicatesSkipped: duplicatesSkipped,
            failedBookmarks: failedBookmarks,
        )
    }

    private func findExistingFolder(name: String, parent: BookmarkFolder?) -> BookmarkFolder? {
        let candidates = if let parent {
            parent.childFolders
        } else {
            rootFolders()
        }

        // Pre-lowercase the search name once instead of in every comparison
        let lowercasedName = name.lowercased()
        return candidates.first { $0.name.lowercased() == lowercasedName }
    }

    private func findNestedConflicts(_ folder: ImportedFolder, existingNames: Set<String>) -> [String] {
        var conflicts: [String] = []
        // Pre-lowercase subfolder names to avoid repeated lowercasing in the loop
        let subfoldersWithLowercasedNames = folder.subfolders.map { ($0, $0.name.lowercased()) }

        for (subfolder, lowercasedName) in subfoldersWithLowercasedNames {
            if existingNames.contains(lowercasedName) {
                conflicts.append(subfolder.name)
            }
            conflicts.append(contentsOf: findNestedConflicts(subfolder, existingNames: existingNames))
        }
        return conflicts
    }
}
