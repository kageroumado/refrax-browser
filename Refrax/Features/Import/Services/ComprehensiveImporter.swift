import Foundation
import SwiftData

/// Service that orchestrates comprehensive data import from external browsers.
///
/// This service handles the async import pipeline for all supported data types:
/// - Bookmarks (with folder hierarchy and duplicate detection)
/// - History (with date range filtering)
/// - Passwords (with conflict detection)
/// - Extensions (scan only, not imported)
///
/// ## Thread Safety
///
/// The importer runs on MainActor, coordinating between MainActor-isolated managers
/// (BookmarksManager, PasswordsManager) and background work. Heavy I/O operations
/// are delegated to async importers, and SwiftData operations run on `ImportDataActor`.
///
/// ## Usage
///
/// ```swift
/// let importer = ComprehensiveImporter(
///     browser: .chrome,
///     profile: chromeProfile,
///     options: importOptions,
///     bookmarksManager: bookmarksManager,
///     passwordsManager: passwordsManager,
///     modelContainer: modelContext.container
/// )
///
/// let result = try await importer.performImport { progress, message in
///     // Update UI with progress
/// }
/// ```
final class ComprehensiveImporter: Sendable {
    // MARK: - Types

    /// Reports progress during import.
    /// - Parameters:
    ///   - progress: Value from 0.0 to 1.0 indicating overall progress.
    ///   - message: Human-readable status message.
    typealias ProgressReporter = @MainActor @Sendable (Double, String) -> Void

    /// Result of the comprehensive import operation.
    struct Result: Sendable {
        /// The comprehensive result with all statistics.
        let result: ComprehensiveImportResult

        /// Credential conflicts requiring user resolution.
        let pendingConflicts: [PasswordsManager.CredentialConflict]

        /// Error that occurred during import, if any.
        let error: ImportError?

        /// Whether conflicts need resolution before completing.
        var hasConflicts: Bool { !pendingConflicts.isEmpty }
    }

    // MARK: - Dependencies

    private let browser: ThirdPartyBrowser?
    private let profile: BrowserProfile?
    private let htmlFileURL: URL?
    private let safariExport: SafariExportContents?
    private let options: ImportOptions
    private let bookmarksManager: BookmarksManager
    private let passwordsManager: PasswordsManager
    private let modelContainer: ModelContainer

    // MARK: - Initialization

    /// Creates a comprehensive importer for a browser profile.
    ///
    /// - Parameters:
    ///   - browser: The source browser to import from.
    ///   - profile: The browser profile to import from.
    ///   - options: Import options specifying what data types to import.
    ///   - bookmarksManager: Manager for creating bookmarks.
    ///   - passwordsManager: Manager for importing credentials.
    ///   - modelContainer: SwiftData container for history import.
    init(
        browser: ThirdPartyBrowser,
        profile: BrowserProfile,
        options: ImportOptions,
        bookmarksManager: BookmarksManager,
        passwordsManager: PasswordsManager,
        modelContainer: ModelContainer,
    ) {
        self.browser = browser
        self.profile = profile
        self.htmlFileURL = nil
        self.safariExport = nil
        self.options = options
        self.bookmarksManager = bookmarksManager
        self.passwordsManager = passwordsManager
        self.modelContainer = modelContainer
    }

    /// Creates a comprehensive importer for an HTML bookmark file.
    ///
    /// - Parameters:
    ///   - htmlFileURL: URL of the HTML bookmark file to import.
    ///   - bookmarksManager: Manager for creating bookmarks.
    ///   - passwordsManager: Manager for importing credentials (unused for HTML).
    ///   - modelContainer: SwiftData container (unused for HTML).
    init(
        htmlFileURL: URL,
        bookmarksManager: BookmarksManager,
        passwordsManager: PasswordsManager,
        modelContainer: ModelContainer,
    ) {
        self.browser = .htmlFile
        self.profile = nil
        self.htmlFileURL = htmlFileURL
        self.safariExport = nil
        self.options = .bookmarksOnly
        self.bookmarksManager = bookmarksManager
        self.passwordsManager = passwordsManager
        self.modelContainer = modelContainer
    }

    /// Creates a comprehensive importer for a Safari export zip.
    ///
    /// Uses pre-extracted files from Safari's File > Export Browsing Data.
    /// Each data type is imported from its respective file within the export.
    ///
    /// - Parameters:
    ///   - safariExport: The parsed Safari export contents.
    ///   - options: Import options specifying what data types to import.
    ///   - bookmarksManager: Manager for creating bookmarks.
    ///   - passwordsManager: Manager for importing credentials.
    ///   - modelContainer: SwiftData container for history import.
    init(
        safariExport: SafariExportContents,
        options: ImportOptions,
        bookmarksManager: BookmarksManager,
        passwordsManager: PasswordsManager,
        modelContainer: ModelContainer,
    ) {
        self.browser = .safari
        self.profile = nil
        self.htmlFileURL = nil
        self.safariExport = safariExport
        self.options = options
        self.bookmarksManager = bookmarksManager
        self.passwordsManager = passwordsManager
        self.modelContainer = modelContainer
    }

    // MARK: - Import Execution

    /// Performs the comprehensive import operation.
    ///
    /// This method orchestrates all selected import types in sequence,
    /// reporting progress through the callback.
    ///
    /// - Parameter progressReporter: Callback for progress updates on main actor.
    /// - Returns: The result containing statistics, conflicts, and any errors.
    func performImport(
        progressReporter: ProgressReporter,
    ) async -> Result {
        progressReporter(0, "Preparing import...")

        var comprehensiveResult = ComprehensiveImportResult()
        var pendingConflicts: [PasswordsManager.CredentialConflict] = []
        var importError: ImportError?

        // Create import actor with its own ModelContext for thread-safe SwiftData access.
        let importActor = ImportDataActor(modelContainer: modelContainer)

        let totalSteps = countSelectedImportTypes()
        var completedSteps = 0

        do {
            // Import bookmarks
            if options.importBookmarks {
                progressReporter(
                    Double(completedSteps) / Double(totalSteps),
                    "Importing bookmarks...",
                )
                let bookmarkStats = try await importBookmarks(
                    importActor: importActor,
                    progressReporter: progressReporter,
                    totalSteps: totalSteps,
                    completedSteps: completedSteps,
                )
                comprehensiveResult.bookmarksImported = bookmarkStats.bookmarksImported
                comprehensiveResult.foldersCreated = bookmarkStats.foldersCreated
                comprehensiveResult.bookmarkDuplicatesSkipped = bookmarkStats.duplicatesSkipped
                comprehensiveResult.failedBookmarks = bookmarkStats.failedBookmarks
                completedSteps += 1
                progressReporter(Double(completedSteps) / Double(totalSteps), "Bookmarks imported")
            }

            // Import history
            if options.importHistory {
                progressReporter(
                    Double(completedSteps) / Double(totalSteps),
                    "Importing history...",
                )
                let historyCount = await importHistory(importActor: importActor)
                comprehensiveResult.historyEntriesImported = historyCount
                completedSteps += 1
                progressReporter(Double(completedSteps) / Double(totalSteps), "History imported")
            }

            // Import passwords
            if options.importPasswords {
                progressReporter(
                    Double(completedSteps) / Double(totalSteps),
                    "Importing passwords...",
                )
                let passwordResult = await importPasswords()
                comprehensiveResult.credentialsImported = passwordResult.imported
                pendingConflicts = passwordResult.conflicts
                completedSteps += 1
                progressReporter(Double(completedSteps) / Double(totalSteps), "Passwords imported")
            }

            // Scan extensions
            if options.importExtensions {
                progressReporter(
                    Double(completedSteps) / Double(totalSteps),
                    "Scanning extensions...",
                )
                let extensions = await scanExtensions()
                comprehensiveResult.extensionsFound = extensions.count
                comprehensiveResult.extensionsList = extensions
                completedSteps += 1
                progressReporter(Double(completedSteps) / Double(totalSteps), "Extensions scanned")
            }

            progressReporter(1.0, "Complete!")

        } catch let error as ImportError {
            importError = error
        } catch {
            importError = .parseError(error.localizedDescription)
        }

        return Result(
            result: comprehensiveResult,
            pendingConflicts: pendingConflicts,
            error: importError,
        )
    }

    // MARK: - Import Type Count

    private func countSelectedImportTypes() -> Int {
        var count = 0
        if options.importBookmarks { count += 1 }
        if options.importHistory { count += 1 }
        if options.importPasswords { count += 1 }
        if options.importExtensions { count += 1 }
        return max(1, count)
    }
}

// MARK: - Bookmark Import

private extension ComprehensiveImporter {
    func importBookmarks(
        importActor: ImportDataActor,
        progressReporter: ProgressReporter,
        totalSteps: Int,
        completedSteps: Int,
    ) async throws -> ImportResult {
        let folders: [ImportedFolder]

        if let bookmarksURL = safariExport?.bookmarksURL {
            let importer = HTMLBookmarkImporter()
            folders = try await importer.importBookmarks(from: bookmarksURL)
        } else if let htmlURL = htmlFileURL {
            let importer = HTMLBookmarkImporter()
            folders = try await importer.importBookmarks(from: htmlURL)
        } else if let browser, let profile {
            guard let importer = ImporterFactory.importer(for: browser) else {
                throw ImportError.unsupportedFormat
            }
            folders = try await importer.importBookmarks(from: profile)
        } else {
            throw ImportError.noBookmarksFound
        }

        // Fetch existing URLs on the import actor (background thread)
        let existingURLs = await importActor.fetchExistingBookmarkURLs()

        return await importFolders(
            folders,
            existingURLs: existingURLs,
            progressReporter: progressReporter,
            totalSteps: totalSteps,
            completedSteps: completedSteps,
        )
    }

    func importFolders(
        _ folders: [ImportedFolder],
        existingURLs: Set<URL>,
        progressReporter: ProgressReporter,
        totalSteps: Int,
        completedSteps: Int,
    ) async -> ImportResult {
        var bookmarksImported = 0
        var foldersCreated = 0
        var duplicatesSkipped = 0
        var failedBookmarks: [ImportResult.FailedBookmark] = []

        let totalBookmarks = folders.reduce(0) { $0 + $1.totalBookmarkCount }
        var processedBookmarks = 0

        for folder in folders {
            let stats = await importFolder(
                folder,
                parent: nil,
                existingURLs: existingURLs,
                totalBookmarks: totalBookmarks,
                processedBookmarks: &processedBookmarks,
                failedBookmarks: &failedBookmarks,
                isInFavoritesFolder: folder.isFavoritesFolder,
                progressReporter: progressReporter,
                totalSteps: totalSteps,
                completedSteps: completedSteps,
            )

            bookmarksImported += stats.bookmarksImported
            foldersCreated += stats.foldersCreated
            duplicatesSkipped += stats.duplicatesSkipped
        }

        return ImportResult(
            bookmarksImported: bookmarksImported,
            foldersCreated: foldersCreated,
            duplicatesSkipped: duplicatesSkipped,
            failedBookmarks: failedBookmarks,
        )
    }

    struct FolderImportStats {
        var bookmarksImported = 0
        var foldersCreated = 0
        var duplicatesSkipped = 0
    }

    func importFolder(
        _ folder: ImportedFolder,
        parent: BookmarkFolder?,
        existingURLs: Set<URL>,
        totalBookmarks: Int,
        processedBookmarks: inout Int,
        failedBookmarks: inout [ImportResult.FailedBookmark],
        isInFavoritesFolder: Bool = false,
        progressReporter: ProgressReporter,
        totalSteps: Int,
        completedSteps: Int,
    ) async -> FolderImportStats {
        var stats = FolderImportStats()

        let targetFolder: BookmarkFolder?
        let currentDepth = parent?.depth ?? -1

        if currentDepth < 2 {
            do {
                targetFolder = try bookmarksManager.createFolder(
                    name: folder.name,
                    parent: parent,
                )
                stats.foldersCreated += 1

                // Add folder to favorites if it's within a favorites folder
                if isInFavoritesFolder {
                    bookmarksManager.addFolderToFavorites(targetFolder!)
                }
            } catch {
                targetFolder = parent
            }
        } else {
            targetFolder = parent
        }

        for bookmark in folder.bookmarks {
            processedBookmarks += 1
            updateBookmarkProgress(
                processed: processedBookmarks,
                total: totalBookmarks,
                progressReporter: progressReporter,
                totalSteps: totalSteps,
                completedSteps: completedSteps,
            )

            if existingURLs.contains(bookmark.url) {
                stats.duplicatesSkipped += 1
                continue
            }

            // Mark as favorite shortcut if importing from a favorites folder
            bookmarksManager.createBookmark(
                url: bookmark.url,
                title: bookmark.title,
                folder: targetFolder,
                isFavorite: isInFavoritesFolder,
                favoriteMode: .shortcut,
            )
            stats.bookmarksImported += 1
        }

        for subfolder in folder.subfolders {
            let subStats = await importFolder(
                subfolder,
                parent: targetFolder,
                existingURLs: existingURLs,
                totalBookmarks: totalBookmarks,
                processedBookmarks: &processedBookmarks,
                failedBookmarks: &failedBookmarks,
                isInFavoritesFolder: isInFavoritesFolder,
                progressReporter: progressReporter,
                totalSteps: totalSteps,
                completedSteps: completedSteps,
            )

            stats.bookmarksImported += subStats.bookmarksImported
            stats.foldersCreated += subStats.foldersCreated
            stats.duplicatesSkipped += subStats.duplicatesSkipped
        }

        return stats
    }

    func updateBookmarkProgress(
        processed: Int,
        total: Int,
        progressReporter: ProgressReporter,
        totalSteps: Int,
        completedSteps: Int,
    ) {
        let bookmarkPhaseWeight = 1.0 / Double(totalSteps)
        let baseProgress = Double(completedSteps) / Double(totalSteps)
        let phaseProgress = bookmarkPhaseWeight * (Double(processed) / Double(max(1, total)))
        progressReporter(
            baseProgress + phaseProgress,
            "Importing bookmark \(processed) of \(total)...",
        )
    }
}

// MARK: - History Import

private extension ComprehensiveImporter {
    func importHistory(importActor: ImportDataActor) async -> Int {
        do {
            let entries: [ImportedHistoryEntry]

            if let historyURL = safariExport?.historyURL {
                entries = try await SafariHistoryJSONImporter.importHistory(
                    from: historyURL,
                    dateRange: options.historyTimeRange,
                )
            } else if let browser, let profile,
                      let importer = HistoryImporterFactory.createImporter(for: browser)
            {
                entries = try await importer.importHistory(
                    from: profile,
                    dateRange: options.historyTimeRange,
                )
            } else {
                return 0
            }

            let importedCount = try await importActor.importHistoryEntries(entries)
            return importedCount
        } catch {
            Logger.error("History import failed: \(error)", category: Logger.data)
            return 0
        }
    }
}

// MARK: - Password Import

private extension ComprehensiveImporter {
    struct PasswordImportResult {
        let imported: Int
        let conflicts: [PasswordsManager.CredentialConflict]
    }

    func importPasswords() async -> PasswordImportResult {
        do {
            let credentials: [ImportedCredential]

            if let passwordsURL = safariExport?.passwordsURL {
                let importer = CSVPasswordImporter()
                credentials = try await importer.importPasswords(from: passwordsURL)
            } else {
                switch options.passwordImportMethod {
                case .direct:
                    credentials = try await importPasswordsDirectly()
                case .csv:
                    guard let csvURL = options.passwordCSVFileURL else {
                        Logger.error("No CSV file selected for password import", category: Logger.autoFill)
                        return PasswordImportResult(imported: 0, conflicts: [])
                    }
                    _ = csvURL.startAccessingSecurityScopedResource()
                    let importer = CSVPasswordImporter()
                    credentials = try await importer.importPasswords(from: csvURL)
                }
            }

            var importedCount = 0
            var conflicts: [PasswordsManager.CredentialConflict] = []

            for credential in credentials {
                if let conflict = passwordsManager.checkForConflict(credential) {
                    conflicts.append(conflict)
                } else {
                    do {
                        try passwordsManager.importCredential(credential)
                        importedCount += 1
                    } catch {
                        Logger.warning(
                            "Failed to import credential for \(credential.domain): \(error)",
                            category: Logger.autoFill,
                        )
                    }
                }
            }

            return PasswordImportResult(imported: importedCount, conflicts: conflicts)
        } catch {
            Logger.error("Password import failed: \(error)", category: Logger.autoFill)
            return PasswordImportResult(imported: 0, conflicts: [])
        }
    }

    func importPasswordsDirectly() async throws -> [ImportedCredential] {
        guard let browser,
              let profile,
              browser.supportsDirectPasswordImport
        else {
            throw ImportError.notImplemented("Direct password import for this browser")
        }

        let importer = DirectChromiumPasswordImporter(browser: browser)
        return try await importer.importPasswords(from: profile.path)
    }
}

// MARK: - Extension Scanning

private extension ComprehensiveImporter {
    func scanExtensions() async -> [ImportedExtension] {
        do {
            let extensions: [ImportedExtension]

            if let extensionsURL = safariExport?.extensionsURL {
                extensions = try await SafariExtensionJSONImporter.importExtensions(
                    from: extensionsURL,
                )
            } else if let browser, let profile,
                      let importer = ExtensionImporterFactory.createImporter(for: browser)
            {
                extensions = try await importer.importExtensions(from: profile)
            } else {
                return []
            }

            for ext in extensions {
                Logger.debug(
                    "Found extension: \(ext.name) v\(ext.version ?? "?") [\(ext.isEnabled ? "enabled" : "disabled")]",
                    category: Logger.data,
                )
            }

            return extensions
        } catch {
            Logger.error("Extension scan failed: \(error)", category: Logger.data)
            return []
        }
    }
}
