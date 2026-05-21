import Foundation

/// A bookmark parsed from an external browser, ready to be imported.
///
/// This structure represents bookmarks from any supported browser format in a
/// normalized form that can be directly imported into Refrax's bookmark system.
///
/// ## Folder Path
///
/// The `folderPath` array represents the hierarchical location of this bookmark
/// in the source browser. For example, a bookmark in "Tech > Swift > Tutorials"
/// would have `folderPath: ["Tech", "Swift", "Tutorials"]`.
///
/// During import, this path is used to recreate the folder structure, respecting
/// Refrax's maximum folder depth of 3 levels.
struct ImportedBookmark: Identifiable, Sendable, Equatable {
    let id: UUID
    let url: URL
    let title: String
    let dateAdded: Date?
    let folderPath: [String]

    init(
        id: UUID = UUID(),
        url: URL,
        title: String,
        dateAdded: Date? = nil,
        folderPath: [String] = [],
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.dateAdded = dateAdded
        self.folderPath = folderPath
    }
}

/// A folder parsed from an external browser containing bookmarks and subfolders.
///
/// This recursive structure mirrors the hierarchical organization of bookmarks
/// in most browsers. During import, the hierarchy is flattened if it exceeds
/// Refrax's maximum depth of 3 levels.
struct ImportedFolder: Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let path: [String]
    var bookmarks: [ImportedBookmark]
    var subfolders: [ImportedFolder]

    /// Whether this folder represents the browser's toolbar/favorites bar.
    ///
    /// When `true`, the folder and its contents should be added to Refrax favorites
    /// during import. This maps to:
    /// - Chrome/Chromium: Bookmarks Bar (PERSONAL_TOOLBAR_FOLDER="true")
    /// - Safari: Favorites folder
    /// - Firefox: Bookmarks Toolbar
    var isFavoritesFolder: Bool

    init(
        id: UUID = UUID(),
        name: String,
        path: [String] = [],
        bookmarks: [ImportedBookmark] = [],
        subfolders: [ImportedFolder] = [],
        isFavoritesFolder: Bool = false,
    ) {
        self.id = id
        self.name = name
        self.path = path
        self.bookmarks = bookmarks
        self.subfolders = subfolders
        self.isFavoritesFolder = isFavoritesFolder
    }

    /// Total number of bookmarks in this folder and all subfolders.
    var totalBookmarkCount: Int {
        bookmarks.count + subfolders.reduce(0) { $0 + $1.totalBookmarkCount }
    }

    /// Total number of folders including this one and all nested subfolders.
    var totalFolderCount: Int {
        1 + subfolders.reduce(0) { $0 + $1.totalFolderCount }
    }
}

/// Result of a bookmark import operation.
///
/// Contains statistics about the import and any errors encountered.
/// Partial success is supported - some bookmarks may import successfully
/// while others fail.
struct ImportResult: Sendable, Equatable {
    /// Number of bookmarks successfully imported.
    let bookmarksImported: Int

    /// Number of folders created during import.
    let foldersCreated: Int

    /// Number of bookmarks skipped because they already exist (duplicate URL).
    let duplicatesSkipped: Int

    /// Bookmarks that failed to import with their associated errors.
    let failedBookmarks: [FailedBookmark]

    /// Whether the import completed entirely successfully.
    var isFullySuccessful: Bool {
        failedBookmarks.isEmpty
    }

    /// A bookmark that failed to import.
    struct FailedBookmark: Identifiable, Sendable, Equatable {
        let id: UUID
        let bookmark: ImportedBookmark
        let reason: String

        init(bookmark: ImportedBookmark, reason: String) {
            self.id = bookmark.id
            self.bookmark = bookmark
            self.reason = reason
        }
    }
}

// MARK: - History Import

/// A history entry parsed from an external browser, ready to be imported.
///
/// Represents a normalized history entry from browsers like Safari or Chrome.
/// Converted to Refrax's `HistoryEntry` model with `isImported = true`.
///
/// ## Visit Count Note
///
/// The `visitCount` field captures how many times the URL was visited in the
/// source browser. However, since Refrax uses a one-entry-per-visit model and
/// we don't have individual timestamps for each visit, imported entries create
/// **one `HistoryEntry` per URL** regardless of visit count.
///
/// The `firstVisited` and `lastVisited` timestamps bracket the visit history,
/// but intermediate visits are not represented.
struct ImportedHistoryEntry: Identifiable, Sendable, Equatable {
    let id: UUID
    let url: URL
    let title: String?

    /// Number of times the URL was visited in the source browser.
    ///
    /// - Note: This value is preserved for reference but does not result in
    ///   multiple `HistoryEntry` records being created.
    let visitCount: Int
    let lastVisited: Date
    let firstVisited: Date?

    init(
        id: UUID = UUID(),
        url: URL,
        title: String? = nil,
        visitCount: Int = 1,
        lastVisited: Date,
        firstVisited: Date? = nil,
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.visitCount = visitCount
        self.lastVisited = lastVisited
        self.firstVisited = firstVisited
    }
}

// MARK: - Password Import

/// A credential parsed from an external browser or CSV file, ready to be imported.
///
/// This structure contains all the information needed to create a Keychain entry.
/// Sensitive data (password) is stored only in memory during the import process
/// and written directly to the Keychain.
struct ImportedCredential: Identifiable, Sendable, Equatable {
    let id: UUID
    let domain: String
    let username: String
    let password: String
    let dateCreated: Date?
    let dateLastUsed: Date?
    let notes: String?

    init(
        id: UUID = UUID(),
        domain: String,
        username: String,
        password: String,
        dateCreated: Date? = nil,
        dateLastUsed: Date? = nil,
        notes: String? = nil,
    ) {
        self.id = id
        self.domain = domain
        self.username = username
        self.password = password
        self.dateCreated = dateCreated
        self.dateLastUsed = dateLastUsed
        self.notes = notes
    }
}

// MARK: - Extension Import

/// Extension metadata parsed from an external browser.
///
/// Since Refrax doesn't yet support extensions, this structure is used only
/// to display what extensions were found during import. The data is logged
/// for future reference but not actively imported.
struct ImportedExtension: Identifiable, Sendable, Equatable {
    let id: String
    let name: String
    let version: String?
    let description: String?
    let homepageURL: URL?
    let isEnabled: Bool
    let sourceBrowser: ThirdPartyBrowser

    init(
        id: String,
        name: String,
        version: String? = nil,
        description: String? = nil,
        homepageURL: URL? = nil,
        isEnabled: Bool = true,
        sourceBrowser: ThirdPartyBrowser,
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.description = description
        self.homepageURL = homepageURL
        self.isEnabled = isEnabled
        self.sourceBrowser = sourceBrowser
    }
}

// MARK: - Extended Import Result

/// Result of a comprehensive import operation covering all data types.
///
/// Contains statistics for each data type imported and any errors encountered.
struct ComprehensiveImportResult: Sendable, Equatable {
    // Bookmarks
    var bookmarksImported: Int = 0
    var foldersCreated: Int = 0
    var bookmarkDuplicatesSkipped: Int = 0
    var failedBookmarks: [ImportResult.FailedBookmark] = []

    // History
    var historyEntriesImported: Int = 0

    // Passwords
    var credentialsImported: Int = 0
    var credentialConflictsResolved: Int = 0

    // Extensions (for display only)
    var extensionsFound: Int = 0
    var extensionsList: [ImportedExtension] = []

    /// Whether all import operations completed without errors.
    var isFullySuccessful: Bool {
        failedBookmarks.isEmpty
    }

    /// Converts to the legacy `ImportResult` for backwards compatibility.
    var asBookmarkResult: ImportResult {
        ImportResult(
            bookmarksImported: bookmarksImported,
            foldersCreated: foldersCreated,
            duplicatesSkipped: bookmarkDuplicatesSkipped,
            failedBookmarks: failedBookmarks,
        )
    }
}

// MARK: - Import Error

/// Errors that can occur during data import.
///
/// These errors provide specific information about what went wrong during
/// the import process, enabling appropriate user feedback.
enum ImportError: Error, LocalizedError, Sendable {
    /// The expected data file was not found at the specified path.
    case fileNotFound(String)

    /// The data file exists but could not be parsed correctly.
    case parseError(String)

    /// An error occurred while reading the SQLite database (Firefox).
    case databaseError(String)

    /// The app lacks permission to read the data file.
    case permissionDenied(String)

    /// The file format is not recognized or not supported.
    case unsupportedFormat

    /// No bookmarks were found in the source.
    case noBookmarksFound

    /// No history entries were found in the source.
    case noHistoryFound

    /// No credentials were found in the source.
    case noCredentialsFound

    /// The feature is not yet implemented.
    case notImplemented(String)

    var errorDescription: String? {
        switch self {
        case let .fileNotFound(path):
            "File not found: \(path)"
        case let .parseError(detail):
            "Failed to parse data: \(detail)"
        case let .databaseError(detail):
            "Database error: \(detail)"
        case let .permissionDenied(path):
            "Permission denied for: \(path)"
        case .unsupportedFormat:
            "Unsupported file format"
        case .noBookmarksFound:
            "No bookmarks found in the selected source"
        case .noHistoryFound:
            "No history entries found in the selected source"
        case .noCredentialsFound:
            "No credentials found in the file"
        case let .notImplemented(feature):
            "\(feature) is not yet implemented"
        }
    }
}
