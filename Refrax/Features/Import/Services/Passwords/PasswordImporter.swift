import Foundation
import SQLite3

/// Protocol for importing passwords from external sources.
///
/// Implementers parse browser-specific password export formats and convert
/// them to `ImportedCredential` structures that can be saved to the Keychain.
protocol PasswordImporter: Sendable {
    /// Imports credentials from a file.
    ///
    /// - Parameter fileURL: URL of the file to import.
    /// - Returns: Array of imported credentials.
    func importPasswords(from fileURL: URL) async throws -> [ImportedCredential]
}

/// Factory for creating the appropriate password importer.
enum PasswordImporterFactory {
    /// Creates a password importer for CSV files.
    ///
    /// Attempts to detect the CSV format automatically based on headers.
    static func createCSVImporter() -> any PasswordImporter {
        CSVPasswordImporter()
    }

    /// Creates a password importer for the specified browser (stub).
    ///
    /// Direct browser password import is not yet implemented. Users should
    /// export passwords to CSV and use `createCSVImporter()` instead.
    ///
    /// - Parameter browser: The browser to import from.
    /// - Returns: A password importer, or `nil` if unsupported.
    static func createDirectImporter(for browser: ThirdPartyBrowser) -> (any PasswordImporter)? {
        switch browser {
        case .chrome, .chromeBeta, .chromeCanary, .brave, .edge:
            DirectChromiumPasswordImporter(browser: browser)
        case .safari:
            DirectSafariPasswordImporter()
        default:
            nil
        }
    }
}

// MARK: - Direct Chromium Importer

/// Imports passwords directly from Chromium-based browser databases.
///
/// This importer reads encrypted passwords from the browser's SQLite database
/// and decrypts them using the Safe Storage key from the macOS Keychain.
///
/// ## Security Model
///
/// 1. The user must grant folder access via NSOpenPanel (no Full Disk Access needed)
/// 2. The browser's Safe Storage key is retrieved from Keychain (user prompted)
/// 3. Passwords are decrypted in memory and immediately stored in Refrax's Keychain
/// 4. No plaintext passwords are written to disk
///
/// ## Supported Browsers
///
/// - Google Chrome (all channels)
/// - Microsoft Edge
/// - Brave Browser
/// - Opera
/// - Vivaldi
/// - Arc Browser
///
/// ## Database Schema
///
/// The `Login Data` SQLite database contains a `logins` table:
/// - `origin_url`: The website URL
/// - `username_value`: The username/email
/// - `password_value`: AES-encrypted password data
/// - `date_created`: Creation timestamp (Windows FILETIME format)
/// - `date_last_used`: Last use timestamp (Windows FILETIME format)
final class DirectChromiumPasswordImporter: PasswordImporter, @unchecked Sendable {
    let browser: ThirdPartyBrowser
    private let decryptor: ChromiumPasswordDecryptor

    init(browser: ThirdPartyBrowser) {
        self.browser = browser
        self.decryptor = ChromiumPasswordDecryptor(browser: browser)
    }

    /// Imports passwords from a browser profile directory.
    ///
    /// - Parameter profileURL: URL to the browser's profile directory containing `Login Data`.
    /// - Returns: Array of imported credentials.
    /// - Throws: `ImportError` if import fails.
    func importPasswords(from profileURL: URL) async throws -> [ImportedCredential] {
        guard browser.supportsDirectPasswordImport else {
            throw ImportError.notImplemented(
                "Direct password import from \(browser.displayName)",
            )
        }

        let loginDataURL = profileURL.appendingPathComponent("Login Data")

        guard FileManager.default.fileExists(atPath: loginDataURL.path) else {
            throw ImportError.fileNotFound(loginDataURL.path)
        }

        // Copy database to temp location (browser may have it locked)
        let tempDB = try copyDatabaseToTemp(loginDataURL)
        defer { cleanupTempFiles(tempDB) }

        // Open and read the database
        let connection = try openDatabase(at: tempDB)
        defer { sqlite3_close(connection) }

        // Get the decryption key
        let passphrase = try decryptor.getSafeStoragePassword()
        let key = try decryptor.deriveKey(from: passphrase)

        // Query and decrypt passwords
        return try queryAndDecryptPasswords(db: connection, key: key)
    }
}

// MARK: - Database Operations

private extension DirectChromiumPasswordImporter {
    func copyDatabaseToTemp(_ sourceDB: URL) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempDB = tempDir.appendingPathComponent("login_import_\(UUID().uuidString).sqlite")

        do {
            try FileManager.default.copyItem(at: sourceDB, to: tempDB)
        } catch {
            throw ImportError.permissionDenied(sourceDB.path)
        }

        // Copy WAL and SHM files if they exist (for WAL mode databases)
        copyWALFilesIfPresent(sourceDB: sourceDB, tempDB: tempDB)

        return tempDB
    }

    func copyWALFilesIfPresent(sourceDB: URL, tempDB: URL) {
        let fileManager = FileManager.default
        let walFile = URL(fileURLWithPath: sourceDB.path + "-wal")
        let shmFile = URL(fileURLWithPath: sourceDB.path + "-shm")

        if fileManager.fileExists(atPath: walFile.path) {
            try? fileManager.copyItem(
                at: walFile,
                to: URL(fileURLWithPath: tempDB.path + "-wal"),
            )
        }

        if fileManager.fileExists(atPath: shmFile.path) {
            try? fileManager.copyItem(
                at: shmFile,
                to: URL(fileURLWithPath: tempDB.path + "-shm"),
            )
        }
    }

    func cleanupTempFiles(_ tempDB: URL) {
        let fileManager = FileManager.default
        try? fileManager.removeItem(at: tempDB)
        try? fileManager.removeItem(at: URL(fileURLWithPath: tempDB.path + "-wal"))
        try? fileManager.removeItem(at: URL(fileURLWithPath: tempDB.path + "-shm"))
    }

    func openDatabase(at url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX

        let result = sqlite3_open_v2(url.path, &db, flags, nil)

        guard result == SQLITE_OK, let connection = db else {
            let errorMessage = db.map { String(cString: sqlite3_errmsg($0)) } ?? "Unknown error"
            throw ImportError.databaseError("Failed to open Login Data: \(errorMessage)")
        }

        return connection
    }
}

// MARK: - Password Query and Decryption

private extension DirectChromiumPasswordImporter {
    func queryAndDecryptPasswords(
        db: OpaquePointer,
        key: Data,
    ) throws -> [ImportedCredential] {
        // Query for login entries
        let query = """
        SELECT origin_url, username_value, password_value, date_created, date_last_used
        FROM logins
        WHERE blacklisted_by_user = 0
        ORDER BY date_last_used DESC
        """

        var statement: OpaquePointer?

        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            let errorMessage = String(cString: sqlite3_errmsg(db))
            throw ImportError.databaseError("Failed to prepare query: \(errorMessage)")
        }
        defer { sqlite3_finalize(statement) }

        var credentials: [ImportedCredential] = []

        while sqlite3_step(statement) == SQLITE_ROW {
            if let credential = parseAndDecryptRow(statement, key: key) {
                credentials.append(credential)
            }
        }

        if credentials.isEmpty {
            throw ImportError.noCredentialsFound
        }

        Logger.info(
            "Imported \(credentials.count) credentials from \(browser.displayName)",
            category: Logger.autoFill,
        )

        return credentials
    }

    func parseAndDecryptRow(
        _ statement: OpaquePointer?,
        key: Data,
    ) -> ImportedCredential? {
        guard let statement else { return nil }

        // Extract URL and username
        guard let originURL = extractString(from: statement, column: 0),
              let username = extractString(from: statement, column: 1),
              !username.isEmpty,
              let domain = extractDomain(from: originURL)
        else {
            return nil
        }

        // Extract and decrypt password
        guard let encryptedData = extractBlob(from: statement, column: 2),
              !encryptedData.isEmpty
        else {
            return nil
        }

        let password: String
        do {
            password = try decryptor.decrypt(encryptedData, with: key)
        } catch {
            Logger.warning(
                "Failed to decrypt password for \(domain): \(error.localizedDescription)",
                category: Logger.autoFill,
            )
            return nil
        }

        guard !password.isEmpty else {
            return nil
        }

        // Extract timestamps
        let dateCreated = chromiumTimeToDate(sqlite3_column_int64(statement, 3))
        let dateLastUsed = chromiumTimeToDate(sqlite3_column_int64(statement, 4))

        return ImportedCredential(
            domain: domain,
            username: username,
            password: password,
            dateCreated: dateCreated,
            dateLastUsed: dateLastUsed.timeIntervalSince1970 > 0 ? dateLastUsed : nil,
        )
    }
}

// MARK: - SQLite Helpers

private extension DirectChromiumPasswordImporter {
    func extractString(from statement: OpaquePointer?, column: Int32) -> String? {
        guard let textPointer = sqlite3_column_text(statement, column) else {
            return nil
        }
        return String(cString: textPointer)
    }

    func extractBlob(from statement: OpaquePointer?, column: Int32) -> Data? {
        guard let blobPointer = sqlite3_column_blob(statement, column) else {
            return nil
        }
        let blobLength = sqlite3_column_bytes(statement, column)
        guard blobLength > 0 else {
            return nil
        }
        return Data(bytes: blobPointer, count: Int(blobLength))
    }

    func extractDomain(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let host = url.host else {
            return nil
        }
        return host
    }

    /// Converts Chromium time (microseconds since Windows epoch) to Swift Date.
    func chromiumTimeToDate(_ chromiumTime: Int64) -> Date {
        guard chromiumTime > 0 else {
            return Date.distantPast
        }
        let windowsEpochOffset: TimeInterval = 11_644_473_600
        let seconds = Double(chromiumTime) / 1_000_000 - windowsEpochOffset
        return Date(timeIntervalSince1970: seconds)
    }
}

/// Safari password importer that guides users through the CSV export process.
///
/// Safari passwords are stored in iCloud Keychain which cannot be accessed
/// programmatically. Users must export their passwords to CSV manually.
///
/// ## Export Instructions
///
/// **macOS Ventura and later:**
/// 1. Open System Settings → Passwords
/// 2. Authenticate with Touch ID or password
/// 3. Click the ••• menu → Export All Passwords...
/// 4. Save the CSV file
///
/// **macOS Monterey:**
/// 1. Open Safari → Preferences → Passwords
/// 2. Authenticate with Touch ID or password
/// 3. Click the ••• menu → Export All Passwords...
/// 4. Save the CSV file
///
/// The exported CSV uses the format: `Title,URL,Username,Password,Notes,OTPAuth`
final class DirectSafariPasswordImporter: PasswordImporter, Sendable {
    func importPasswords(from fileURL: URL) async throws -> [ImportedCredential] {
        // If a CSV file is provided, delegate to CSV importer
        if fileURL.pathExtension.lowercased() == "csv" {
            let csvImporter = CSVPasswordImporter()
            return try await csvImporter.importPasswords(from: fileURL)
        }

        // Otherwise, throw an error with guidance
        throw ImportError.notImplemented(
            """
            Direct Safari password import is not available. \
            Please export passwords to CSV from System Settings → Passwords.
            """,
        )
    }
}

// MARK: - Password Import Method

/// Methods available for importing passwords.
enum PasswordImportMethod: String, CaseIterable, Identifiable, Sendable {
    /// Import directly from the browser's encrypted database.
    case direct

    /// Import from a CSV file exported by the user.
    case csv

    var id: String { rawValue }

    /// Display name for the import method.
    var displayName: String {
        switch self {
        case .direct:
            "Import Directly"
        case .csv:
            "Import from CSV"
        }
    }

    /// Description of the import method.
    var methodDescription: String {
        switch self {
        case .direct:
            "Securely import passwords directly from the browser (requires Keychain access)"
        case .csv:
            "Import from a CSV file exported from the browser's settings"
        }
    }

    /// Icon for the import method.
    var iconName: String {
        switch self {
        case .direct:
            "arrow.down.doc.fill"
        case .csv:
            "doc.text.fill"
        }
    }
}
