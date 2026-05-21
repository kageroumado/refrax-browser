import Foundation

/// Types of data that can be imported from browsers.
enum ImportDataType: String, CaseIterable, Identifiable, Sendable {
    case bookmarks
    case history
    case passwords
    case extensions

    var id: String { rawValue }

    /// Display name for the data type.
    var displayName: String {
        switch self {
        case .bookmarks:
            "Bookmarks"
        case .history:
            "Browsing History"
        case .passwords:
            "Passwords"
        case .extensions:
            "Extensions"
        }
    }

    /// Icon name for the data type.
    var iconName: String {
        switch self {
        case .bookmarks:
            "bookmark.fill"
        case .history:
            "clock.fill"
        case .passwords:
            "key.fill"
        case .extensions:
            "puzzlepiece.extension.fill"
        }
    }

    /// Description of what will be imported.
    var importDescription: String {
        switch self {
        case .bookmarks:
            "Import your saved bookmarks and folders"
        case .history:
            "Import your browsing history"
        case .passwords:
            "Import saved passwords to Keychain"
        case .extensions:
            "View extensions (not yet importable)"
        }
    }
}

/// Configuration for what data to import and how.
///
/// This structure captures all user selections from the import wizard,
/// including which data types to import and any type-specific options.
struct ImportOptions: Sendable, Equatable {
    // MARK: - Data Type Selection

    /// Whether to import bookmarks.
    var importBookmarks: Bool = true

    /// Whether to import browsing history.
    var importHistory: Bool = true

    /// Whether to import passwords.
    var importPasswords: Bool = false

    /// Whether to scan for extensions (display only).
    var importExtensions: Bool = true

    // MARK: - History Options

    /// Time range for history import.
    ///
    /// If `nil`, all available history is imported.
    var historyTimeRange: ClosedRange<Date>?

    /// The earliest date available in the source browser's history.
    var historyMinDate: Date?

    /// The latest date available in the source browser's history.
    var historyMaxDate: Date?

    /// Whether the history date range could not be loaded (e.g., permission denied).
    /// When true, all history will be imported without a date range selector.
    var historyDateRangeUnavailable: Bool = false

    // MARK: - Password Options

    /// The method to use for importing passwords.
    ///
    /// - `.direct`: Import directly from the browser's encrypted database
    /// - `.csv`: Import from a CSV file exported by the user
    var passwordImportMethod: PasswordImportMethod = .direct

    /// URL of the CSV file to import passwords from.
    ///
    /// Set when user selects a CSV file for password import with `.csv` method.
    var passwordCSVFileURL: URL?

    /// Whether password import is ready to proceed.
    ///
    /// For direct import, always ready if the browser supports it.
    /// For CSV import, requires a file to be selected.
    var isPasswordImportReady: Bool {
        switch passwordImportMethod {
        case .direct:
            true
        case .csv:
            passwordCSVFileURL != nil
        }
    }

    // MARK: - Computed Properties

    /// Data types that the user has selected to import.
    var selectedDataTypes: Set<ImportDataType> {
        var types: Set<ImportDataType> = []
        if importBookmarks { types.insert(.bookmarks) }
        if importHistory { types.insert(.history) }
        if importPasswords { types.insert(.passwords) }
        if importExtensions { types.insert(.extensions) }
        return types
    }

    /// Whether any data type is selected for import.
    var hasSelection: Bool {
        importBookmarks || importHistory || importPasswords || importExtensions
    }

    /// Data types available for the selected browser.
    ///
    /// Not all browsers support all data types. This is populated
    /// based on the selected browser and profile.
    var availableDataTypes: Set<ImportDataType> = Set(ImportDataType.allCases)

    // MARK: - Convenience Methods

    /// Returns options with all data types enabled.
    static var all: ImportOptions {
        ImportOptions(
            importBookmarks: true,
            importHistory: true,
            importPasswords: true,
            importExtensions: true,
        )
    }

    /// Returns options with only bookmarks enabled.
    static var bookmarksOnly: ImportOptions {
        ImportOptions(
            importBookmarks: true,
            importHistory: false,
            importPasswords: false,
            importExtensions: false,
        )
    }
}

// MARK: - Browser Data Type Support

extension ThirdPartyBrowser {
    /// Data types that can be imported from this browser.
    var supportedImportTypes: Set<ImportDataType> {
        switch self {
        case .chrome, .chromeBeta, .chromeCanary, .brave, .edge, .opera, .vivaldi, .helium:
            [.bookmarks, .history, .passwords, .extensions]
        case .arc:
            [.bookmarks, .history, .passwords, .extensions]
        case .firefox, .firefoxDeveloper, .zen:
            [.bookmarks, .history, .passwords]
        case .safari:
            [.bookmarks, .history, .passwords, .extensions]
        case .htmlFile:
            [.bookmarks]
        }
    }

    /// Whether this browser supports history import.
    var supportsHistoryImport: Bool {
        supportedImportTypes.contains(.history)
    }

    /// Whether this browser supports extension scanning.
    var supportsExtensionImport: Bool {
        supportedImportTypes.contains(.extensions)
    }
}
