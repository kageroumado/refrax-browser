import Foundation

/// Contents available in a Safari export zip file.
///
/// Safari's File > Export Browsing Data creates a zip containing
/// standardized files for each data type. This struct tracks which
/// files were found and their temporary extracted paths.
struct SafariExportContents: Sendable, Equatable {
    /// Path to extracted Bookmarks.html (Netscape bookmark format).
    var bookmarksURL: URL?

    /// Path to extracted History.json.
    var historyURL: URL?

    /// Path to extracted Passwords.csv (Safari CSV format).
    var passwordsURL: URL?

    /// Path to extracted Extensions.json.
    var extensionsURL: URL?

    /// The temporary directory containing extracted files.
    let extractionDirectory: URL

    /// Data types available in the export.
    var availableDataTypes: Set<ImportDataType> {
        var types: Set<ImportDataType> = []
        if bookmarksURL != nil { types.insert(.bookmarks) }
        if historyURL != nil { types.insert(.history) }
        if passwordsURL != nil { types.insert(.passwords) }
        if extensionsURL != nil { types.insert(.extensions) }
        return types
    }

    /// Cleans up extracted files.
    func cleanup() {
        try? FileManager.default.removeItem(at: extractionDirectory)
    }
}

/// Extracts and parses Safari export zip files.
///
/// Safari's File > Export Browsing Data creates a zip containing:
/// - `Bookmarks.html` — Netscape bookmark format
/// - `History.json` — JSON array of history entries
/// - `Passwords.csv` — CSV with `Title,URL,Username,Password,Notes,OTPAuth`
/// - `Extensions.json` — JSON array of installed extensions
enum SafariExportParser {
    /// Extracts a Safari export zip and returns the available contents.
    ///
    /// - Parameter zipURL: URL of the Safari export zip file.
    /// - Returns: The extracted contents with paths to available data files.
    static func parse(zipURL: URL) async throws -> SafariExportContents {
        let extractionDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("safari_export_\(UUID().uuidString)")

        try FileManager.default.createDirectory(
            at: extractionDir,
            withIntermediateDirectories: true,
        )

        try await extractZip(from: zipURL, to: extractionDir)

        // Safari zips extract into a named subdirectory (e.g. "Safari Export 2026-03-18/").
        // Find the actual directory containing the data files.
        let dataDir = try findDataDirectory(in: extractionDir)

        var contents = SafariExportContents(extractionDirectory: extractionDir)

        let bookmarksURL = dataDir.appendingPathComponent("Bookmarks.html")
        if FileManager.default.fileExists(atPath: bookmarksURL.path) {
            contents.bookmarksURL = bookmarksURL
        }

        let historyURL = dataDir.appendingPathComponent("History.json")
        if FileManager.default.fileExists(atPath: historyURL.path) {
            contents.historyURL = historyURL
        }

        let passwordsURL = dataDir.appendingPathComponent("Passwords.csv")
        if FileManager.default.fileExists(atPath: passwordsURL.path) {
            contents.passwordsURL = passwordsURL
        }

        let extensionsURL = dataDir.appendingPathComponent("Extensions.json")
        if FileManager.default.fileExists(atPath: extensionsURL.path) {
            contents.extensionsURL = extensionsURL
        }

        guard !contents.availableDataTypes.isEmpty else {
            contents.cleanup()
            throw ImportError.parseError(
                "The selected file does not appear to be a Safari export. "
                    + "Use Safari's File → Export Browsing Data to create the export."
            )
        }

        return contents
    }

    /// Finds the directory containing Safari export data files.
    ///
    /// Safari's zip extracts into a named subdirectory. This method checks
    /// the extraction directory itself first, then looks for a single
    /// subdirectory containing the expected files.
    private static func findDataDirectory(in extractionDir: URL) throws -> URL {
        // Check if files are directly in the extraction directory
        if FileManager.default.fileExists(
            atPath: extractionDir.appendingPathComponent("History.json").path
        ) {
            return extractionDir
        }

        // Look for a subdirectory containing the data files
        let contents = try FileManager.default.contentsOfDirectory(
            at: extractionDir,
            includingPropertiesForKeys: [.isDirectoryKey],
        )

        for item in contents {
            let isDirectory = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDirectory {
                // Check if this subdirectory has any Safari export files
                let hasHistory = FileManager.default.fileExists(
                    atPath: item.appendingPathComponent("History.json").path
                )
                let hasBookmarks = FileManager.default.fileExists(
                    atPath: item.appendingPathComponent("Bookmarks.html").path
                )
                let hasPasswords = FileManager.default.fileExists(
                    atPath: item.appendingPathComponent("Passwords.csv").path
                )

                if hasHistory || hasBookmarks || hasPasswords {
                    return item
                }
            }
        }

        return extractionDir
    }

    /// Extracts a zip file using `ditto` (Foundation has no native zip API).
    private static func extractZip(from zipURL: URL, to directory: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zipURL.path, directory.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            throw ImportError.parseError("Failed to extract Safari export: \(errorMessage)")
        }
    }
}
