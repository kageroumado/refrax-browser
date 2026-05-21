import Foundation
import SQLite3
import SwiftData

/// Granular database recovery using raw SQLite inspection.
///
/// Replaces the all-or-nothing wipe approach with selective table deletion.
/// Opens the `.store` file directly via SQLite3 C API to diagnose which
/// model tables are schema-incompatible, then drops only those tables.
/// SwiftData recreates empty tables on next `ModelContainer` init.
///
/// ## Strategy
///
/// 1. **Backup**: Copy entire store directory before any modifications
/// 2. **Diagnose**: Open raw SQLite, compare table schemas against expected
/// 3. **Categorize**: Split models into healthy vs incompatible
/// 4. **Selective reset**: `DROP TABLE` for incompatible models only
/// 5. **Verify**: Attempt `ModelContainer` creation again
nonisolated enum DatabaseRecoveryService: Sendable {
    // MARK: - Types

    /// Result of diagnosing a database store against expected schema.
    nonisolated struct DiagnosisResult: Sendable {
        let healthyModels: [ModelStatus]
        let incompatibleModels: [ModelStatus]
        let error: String
    }

    /// Status of a single model table in the database.
    nonisolated struct ModelStatus: Sendable {
        let name: String
        let displayName: String
        let rowCount: Int
        /// Empty for healthy models; describes the incompatibility for broken ones.
        let reason: String
    }

    /// Metadata about a model type for categorization and display.
    nonisolated struct ModelCategory: Sendable {
        let tableName: String
        let displayName: String
        let description: String
        let risk: Risk

        nonisolated enum Risk: Sendable {
            /// Schema rarely changes. Represents important user data.
            case low
            /// Layout/organizational data. Some loss acceptable.
            case medium
            /// Schema evolves frequently. Settings gain new properties each release.
            case high
        }
    }

    // MARK: - Model Categories

    /// All known model categories with human-readable descriptions and risk levels.
    ///
    /// Risk levels guide the recovery UI: low-risk models contain valuable user data
    /// worth preserving, while high-risk models contain settings that evolve frequently
    /// and are easy to recreate.
    static let modelCategories: [ModelCategory] = [
        // Low risk: user data worth preserving
        ModelCategory(
            tableName: "HistoryEntry",
            displayName: "History",
            description: "Browsing history entries",
            risk: .low,
        ),
        ModelCategory(
            tableName: "Bookmark",
            displayName: "Bookmarks",
            description: "Saved bookmarks",
            risk: .low,
        ),
        ModelCategory(
            tableName: "BookmarkFolder",
            displayName: "Bookmark Folders",
            description: "Bookmark folder structure",
            risk: .low,
        ),
        ModelCategory(
            tableName: "CachedFavicon",
            displayName: "Favicons",
            description: "Cached site icons",
            risk: .low,
        ),
        ModelCategory(
            tableName: "Download",
            displayName: "Downloads",
            description: "Download history records",
            risk: .low,
        ),
        ModelCategory(
            tableName: "UserScript",
            displayName: "User Scripts",
            description: "Custom JavaScript user scripts",
            risk: .low,
        ),
        ModelCategory(
            tableName: "UserStyle",
            displayName: "User Styles",
            description: "Custom CSS user styles",
            risk: .low,
        ),
        ModelCategory(
            tableName: "UserScriptStorage",
            displayName: "User Script Storage",
            description: "Persistent storage for user scripts",
            risk: .low,
        ),
        ModelCategory(
            tableName: "CustomSearchEngine",
            displayName: "Custom Search Engines",
            description: "User-added search engines",
            risk: .low,
        ),
        ModelCategory(
            tableName: "AppShortcut",
            displayName: "App Shortcuts",
            description: "Pinned web app shortcuts",
            risk: .low,
        ),
        ModelCategory(
            tableName: "DomainTimeEntry",
            displayName: "Screen Time Data",
            description: "Domain usage tracking entries",
            risk: .low,
        ),

        // Medium risk: organizational data
        ModelCategory(
            tableName: "Tab",
            displayName: "Tabs",
            description: "Open browser tabs",
            risk: .medium,
        ),
        ModelCategory(
            tableName: "TabPage",
            displayName: "Tab Pages",
            description: "Individual pages within tabs",
            risk: .medium,
        ),
        ModelCategory(
            tableName: "Space",
            displayName: "Spaces",
            description: "Workspace containers",
            risk: .medium,
        ),
        ModelCategory(
            tableName: "TabGroup",
            displayName: "Tab Groups",
            description: "Grouped tab collections",
            risk: .medium,
        ),
        ModelCategory(
            tableName: "TabSnapshot",
            displayName: "Tab Snapshots",
            description: "Session snapshot headers",
            risk: .medium,
        ),
        ModelCategory(
            tableName: "TabSnapshotItem",
            displayName: "Tab Snapshot Items",
            description: "Individual tab states in snapshots",
            risk: .medium,
        ),
        ModelCategory(
            tableName: "BrowsingContext",
            displayName: "Browsing Contexts",
            description: "Isolated browsing contexts",
            risk: .medium,
        ),
        ModelCategory(
            tableName: "SavedFilter",
            displayName: "Saved Filters",
            description: "Custom tab filter presets",
            risk: .medium,
        ),

        // High risk: settings that evolve frequently
        ModelCategory(
            tableName: "BrowserSettings",
            displayName: "Settings",
            description: "Custom browser preferences",
            risk: .high,
        ),
        ModelCategory(
            tableName: "SiteSettings",
            displayName: "Site Settings",
            description: "Per-site overrides",
            risk: .high,
        ),
        ModelCategory(
            tableName: "PrivacyProtectionSettings",
            displayName: "Privacy Settings",
            description: "Privacy protection configuration",
            risk: .high,
        ),
        ModelCategory(
            tableName: "CustomRedirect",
            displayName: "Custom Redirects",
            description: "URL redirect rules",
            risk: .high,
        ),
        ModelCategory(
            tableName: "AppRedirectRule",
            displayName: "App Redirect Rules",
            description: "Rules for opening URLs in other apps",
            risk: .high,
        ),
        ModelCategory(
            tableName: "ArchiveRule",
            displayName: "Archive Rules",
            description: "Automatic tab archival rules",
            risk: .high,
        ),
        ModelCategory(
            tableName: "DomainTimeLimit",
            displayName: "Time Limits",
            description: "Domain usage time limits",
            risk: .high,
        ),
    ]

    /// Lookup table for model categories by table name.
    private static let categoriesByName: [String: ModelCategory] = Dictionary(uniqueKeysWithValues: modelCategories.map { ($0.tableName, $0) })

    // MARK: - Diagnosis

    /// Opens the raw SQLite store and diagnoses which model tables are schema-incompatible.
    ///
    /// Compares each table's column definitions against the expected schema. Tables with
    /// missing required columns or type mismatches are marked incompatible.
    ///
    /// Callers pass SwiftData entity and property names (e.g., "BrowserSettings",
    /// "checkForUpdatesAutomatically"). This method translates to Core Data's SQLite
    /// naming convention (`Z` prefix + uppercase) for comparison.
    ///
    /// - Parameters:
    ///   - storeURL: Path to the `.store` file.
    ///   - expectedSchema: Array of entity names with their expected property names.
    /// - Returns: Diagnosis result categorizing models as healthy or incompatible.
    static func diagnose(
        storeURL: URL,
        expectedSchema: [(tableName: String, columns: [String])],
    ) -> DiagnosisResult {
        var db: OpaquePointer?

        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        let status = sqlite3_open_v2(storeURL.path, &db, flags, nil)
        guard status == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(db)
            return DiagnosisResult(
                healthyModels: [],
                incompatibleModels: [],
                error: "Failed to open database: \(message)",
            )
        }

        defer { sqlite3_close(db) }

        let existingTables = queryTableNames(in: db)
        var healthy: [ModelStatus] = []
        var incompatible: [ModelStatus] = []

        for expected in expectedSchema {
            let displayName = categoriesByName[expected.tableName]?.displayName ?? expected.tableName
            let sqliteTableName = coreDataTableName(for: expected.tableName)

            guard existingTables.contains(sqliteTableName) else {
                incompatible.append(ModelStatus(
                    name: expected.tableName,
                    displayName: displayName,
                    rowCount: 0,
                    reason: "Table missing from database",
                ))
                continue
            }

            let existingColumns = queryColumnNames(for: sqliteTableName, in: db)
            let expectedSQLiteColumns = Set(expected.columns.map { coreDataColumnName(for: $0) })
            let missingColumns = expectedSQLiteColumns.filter { !existingColumns.contains($0) }
            let count = rowCount(for: sqliteTableName, in: db)

            if missingColumns.isEmpty {
                healthy.append(ModelStatus(
                    name: expected.tableName,
                    displayName: displayName,
                    rowCount: count,
                    reason: "",
                ))
            } else {
                let originalMissing = expected.columns.filter { column in
                    !existingColumns.contains(coreDataColumnName(for: column))
                }
                incompatible.append(ModelStatus(
                    name: expected.tableName,
                    displayName: displayName,
                    rowCount: count,
                    reason: "Missing columns: \(originalMissing.joined(separator: ", "))",
                ))
            }
        }

        return DiagnosisResult(
            healthyModels: healthy,
            incompatibleModels: incompatible,
            error: "",
        )
    }

    // MARK: - Core Data Naming

    /// Translates a SwiftData entity name to its Core Data SQLite table name.
    ///
    /// Core Data prefixes all entity table names with "Z" and uppercases them.
    /// e.g., "BrowserSettings" → "ZBROWSERSETTINGS"
    private static func coreDataTableName(for entityName: String) -> String {
        "Z\(entityName.uppercased())"
    }

    /// Translates a SwiftData property name to its Core Data SQLite column name.
    ///
    /// Core Data prefixes all attribute column names with "Z" and uppercases them.
    /// e.g., "checkForUpdatesAutomatically" → "ZCHECKFORUPDATESAUTOMATICALLY"
    private static func coreDataColumnName(for propertyName: String) -> String {
        "Z\(propertyName.uppercased())"
    }

    // MARK: - Migration Logging

    /// Snapshots the current SQLite schema (table names → column names) before migration.
    ///
    /// Call this before `ModelContainer` creation, then pass the result to
    /// ``logMigrationChanges(preMigration:schema:)`` after success.
    static func snapshotSchema(storeURL: URL) -> [String: Set<String>]? {
        guard FileManager.default.fileExists(atPath: storeURL.path) else { return nil }

        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(storeURL.path, &db, flags, nil) == SQLITE_OK, let db else {
            sqlite3_close(db)
            return nil
        }
        defer { sqlite3_close(db) }

        var snapshot: [String: Set<String>] = [:]
        let tables = queryTableNames(in: db)
        for table in tables where table.hasPrefix("Z") && table != "Z_METADATA" && table != "Z_PRIMARYKEY" && table != "Z_MODELCACHE" {
            snapshot[table] = queryColumnNames(for: table, in: db)
        }
        return snapshot
    }

    /// Compares a pre-migration schema snapshot against the current SwiftData schema
    /// and logs any tables or columns that were added during migration.
    ///
    /// - Parameters:
    ///   - preMigration: Snapshot from ``snapshotSchema(storeURL:)``, or `nil` for fresh databases.
    ///   - schema: The current SwiftData schema.
    static func logMigrationChanges(
        preMigration: [String: Set<String>]?,
        schema: Schema,
    ) {
        guard let preMigration else {
            Logger.info("Database created (fresh install)", category: Logger.storage)
            return
        }

        var newTables: [String] = []
        var addedColumns: [(entity: String, columns: [String])] = []

        for entity in schema.entities {
            let sqliteTable = coreDataTableName(for: entity.name)
            let expectedColumns = Set(entity.properties.compactMap { property -> String? in
                guard property is Schema.Attribute else { return nil }
                return coreDataColumnName(for: property.name)
            })

            guard let existingColumns = preMigration[sqliteTable] else {
                newTables.append(entity.name)
                continue
            }

            let added = expectedColumns.subtracting(existingColumns)
            if !added.isEmpty {
                let propertyNames = added.map { column in
                    String(column.dropFirst()).lowercased()
                }.sorted()
                addedColumns.append((entity: entity.name, columns: propertyNames))
            }
        }

        if newTables.isEmpty, addedColumns.isEmpty {
            Logger.info("Database schema up to date, no migration needed", category: Logger.storage)
            return
        }

        if !newTables.isEmpty {
            Logger.info(
                "Migration added \(newTables.count) new table(s): \(newTables.joined(separator: ", "))",
                category: Logger.storage,
            )
        }

        for entry in addedColumns {
            Logger.info(
                "Migration added \(entry.columns.count) column(s) to \(entry.entity): \(entry.columns.joined(separator: ", "))",
                category: Logger.storage,
            )
        }
    }

    // MARK: - Backup

    /// Creates a timestamped backup of the store and its auxiliary files.
    ///
    /// Copies the `.store` file and any associated `-wal` and `-shm` files to
    /// `Directories.appStorage/"Backups"/YYYY-MM-DD_HHmmss/`.
    ///
    /// - Parameter storeURL: Path to the `.store` file.
    /// - Returns: URL of the backup directory.
    @discardableResult
    static func backup(storeURL: URL) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmmss"
        let timestamp = formatter.string(from: Date.now)

        let backupDir = DatabaseBackupService.backupsDirectory
            .appendingPathComponent(timestamp, isDirectory: true)

        let fm = FileManager.default
        try fm.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let storeDirectory = storeURL.deletingLastPathComponent()
        let storeName = storeURL.lastPathComponent

        let filesToCopy = [
            storeName,
            "\(storeName)-wal",
            "\(storeName)-shm",
        ]

        for filename in filesToCopy {
            let source = storeDirectory.appendingPathComponent(filename)
            if fm.fileExists(atPath: source.path) {
                let destination = backupDir.appendingPathComponent(filename)
                try fm.copyItem(at: source, to: destination)
            }
        }

        Logger.info("Database backup created at \(backupDir.path)", category: Logger.storage)
        return backupDir
    }

    // MARK: - Selective Reset

    /// Drops SQLite tables for specified model types.
    ///
    /// Callers pass SwiftData entity names (e.g., "BrowserSettings"). This method
    /// translates to Core Data's `Z`-prefixed naming before executing `DROP TABLE`.
    /// SwiftData recreates empty tables on next `ModelContainer` initialization.
    /// Always call ``backup(storeURL:)`` before this method.
    ///
    /// - Parameters:
    ///   - tableNames: SwiftData entity names of tables to drop.
    ///   - storeURL: Path to the `.store` file.
    static func resetModels(_ tableNames: [String], storeURL: URL) throws {
        var db: OpaquePointer?

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_NOMUTEX
        let status = sqlite3_open_v2(storeURL.path, &db, flags, nil)
        guard status == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            sqlite3_close(db)
            throw RecoveryError.cannotOpenDatabase(message)
        }

        defer { sqlite3_close(db) }

        for tableName in tableNames {
            let sqliteTableName = coreDataTableName(for: tableName)
            let sanitized = sqliteTableName.replacingOccurrences(of: "\"", with: "\"\"")
            let sql = "DROP TABLE IF EXISTS \"\(sanitized)\""

            var errorMessage: UnsafeMutablePointer<CChar>?
            let result = sqlite3_exec(db, sql, nil, nil, &errorMessage)

            if result != SQLITE_OK {
                let message = errorMessage.map { String(cString: $0) } ?? "Unknown error"
                sqlite3_free(errorMessage)
                throw RecoveryError.dropTableFailed(tableName, message)
            }

            Logger.info("Dropped table: \(tableName)", category: Logger.storage)
        }
    }

    // MARK: - Errors

    nonisolated enum RecoveryError: LocalizedError, Sendable {
        case cannotOpenDatabase(String)
        case dropTableFailed(String, String)

        var errorDescription: String? {
            switch self {
            case let .cannotOpenDatabase(reason):
                "Cannot open database: \(reason)"
            case let .dropTableFailed(table, reason):
                "Failed to drop table '\(table)': \(reason)"
            }
        }
    }

    // MARK: - Private Helpers

    /// Queries `sqlite_master` for all user table names.
    private static func queryTableNames(in db: OpaquePointer) -> Set<String> {
        var names: Set<String> = []
        var stmt: OpaquePointer?

        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return names
        }

        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            if let cString = sqlite3_column_text(stmt, 0) {
                names.insert(String(cString: cString))
            }
        }

        return names
    }

    /// Queries `PRAGMA table_info` for column names of a given table.
    private static func queryColumnNames(
        for tableName: String,
        in db: OpaquePointer,
    ) -> Set<String> {
        var columns: Set<String> = []
        var stmt: OpaquePointer?

        let sanitized = tableName.replacingOccurrences(of: "\"", with: "\"\"")
        let sql = "PRAGMA table_info(\"\(sanitized)\")"
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return columns
        }

        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            // Column index 1 is the column name in PRAGMA table_info
            if let cString = sqlite3_column_text(stmt, 1) {
                columns.insert(String(cString: cString))
            }
        }

        return columns
    }

    /// Returns the row count for a table, or 0 on error.
    private static func rowCount(for tableName: String, in db: OpaquePointer) -> Int {
        var stmt: OpaquePointer?

        let sanitized = tableName.replacingOccurrences(of: "\"", with: "\"\"")
        let sql = "SELECT COUNT(*) FROM \"\(sanitized)\""
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return 0
        }

        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int64(stmt, 0))
    }
}
