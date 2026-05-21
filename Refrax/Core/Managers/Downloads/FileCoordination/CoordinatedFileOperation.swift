import Foundation

/// Provides safe, coordinated file operations for downloads.
///
/// All operations use `NSFileCoordinator` to ensure proper coordination with:
/// - Other processes (Finder, iCloud, Spotlight)
/// - Other parts of the app accessing the same files
/// - System services that may be indexing or syncing files
///
/// ## Why File Coordination Matters
///
/// Without coordination:
/// - Files can be corrupted if written during iCloud sync
/// - Moves can fail if Finder has the file selected
/// - Data loss can occur if user moves file during download
///
/// ## Usage
///
/// ```swift
/// // Safe file move
/// try await CoordinatedFileOperation.move(from: tempURL, to: finalURL)
///
/// // Safe write with options
/// try await CoordinatedFileOperation.write(to: url, options: .forReplacing) { url in
///     try data.write(to: url)
/// }
/// ```
enum CoordinatedFileOperation {
    // MARK: - Errors

    enum Error: Swift.Error, LocalizedError {
        case coordinationFailed(NSError)
        case operationFailed(any Swift.Error)
        case sourceDoesNotExist(URL)
        case destinationExists(URL)

        var errorDescription: String? {
            switch self {
            case let .coordinationFailed(error):
                "File coordination failed: \(error.localizedDescription)"
            case let .operationFailed(error):
                "File operation failed: \(error.localizedDescription)"
            case let .sourceDoesNotExist(url):
                "Source file does not exist: \(url.lastPathComponent)"
            case let .destinationExists(url):
                "Destination already exists: \(url.lastPathComponent)"
            }
        }
    }

    // MARK: - Move Operations

    /// Moves a file from source to destination with full coordination.
    ///
    /// This is the safest way to move download files:
    /// - Coordinates with other processes
    /// - Handles cross-volume moves automatically
    /// - Preserves file metadata
    ///
    /// - Parameters:
    ///   - source: Source file URL.
    ///   - destination: Destination file URL.
    ///   - replacing: If true, replaces existing file at destination.
    /// - Throws: `Error` if coordination or move fails.
    static func move(
        from source: URL,
        to destination: URL,
        replacing: Bool = false,
    ) throws {
        let fm = FileManager.default

        guard fm.fileExists(atPath: source.path) else {
            throw Error.sourceDoesNotExist(source)
        }

        if !replacing, fm.fileExists(atPath: destination.path) {
            throw Error.destinationExists(destination)
        }

        var coordinationError: NSError?
        var operationError: (any Swift.Error)?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: source,
            options: .forMoving,
            writingItemAt: destination,
            options: replacing ? .forReplacing : [],
            error: &coordinationError,
        ) { actualSource, actualDestination in
            do {
                // Remove existing file if replacing
                if replacing, fm.fileExists(atPath: actualDestination.path) {
                    try fm.removeItem(at: actualDestination)
                }

                try fm.moveItem(at: actualSource, to: actualDestination)

                // Notify system of the move INSIDE the coordination block
                // This ensures other coordinators see the notification properly
                coordinator.item(at: actualSource, didMoveTo: actualDestination)
            } catch {
                operationError = error
            }
        }

        if let error = coordinationError {
            throw Error.coordinationFailed(error)
        }
        if let error = operationError {
            throw Error.operationFailed(error)
        }
    }

    /// Replaces destination file with source file atomically.
    ///
    /// Uses `FileManager.replaceItemAt` for atomic replacement:
    /// - Source file is moved to destination
    /// - Original destination is removed
    /// - Operation is atomic (no partial state)
    ///
    /// - Parameters:
    ///   - destination: The file to replace.
    ///   - source: The replacement file.
    ///   - backupName: Optional backup item name.
    /// - Returns: URL of backup file if created.
    /// - Throws: `Error` if coordination or replacement fails.
    @discardableResult
    static func replace(
        _ destination: URL,
        with source: URL,
        backupItemName: String? = nil,
    ) throws -> URL? {
        var coordinationError: NSError?
        var operationError: (any Swift.Error)?
        var backupURL: URL?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(
            writingItemAt: source,
            options: .forMoving,
            writingItemAt: destination,
            options: .forReplacing,
            error: &coordinationError,
        ) { actualSource, actualDestination in
            do {
                var options: FileManager.ItemReplacementOptions = []
                if backupItemName != nil {
                    options.insert(.withoutDeletingBackupItem)
                }

                backupURL = try FileManager.default.replaceItemAt(
                    actualDestination,
                    withItemAt: actualSource,
                    backupItemName: backupItemName,
                    options: options,
                )
            } catch {
                operationError = error
            }
        }

        if let error = coordinationError {
            throw Error.coordinationFailed(error)
        }
        if let error = operationError {
            throw Error.operationFailed(error)
        }

        return backupURL
    }

    // MARK: - Write Operations

    /// Performs a coordinated write operation.
    ///
    /// - Parameters:
    ///   - url: The file URL to write to.
    ///   - options: Write coordination options.
    ///   - block: The write operation to perform.
    /// - Throws: `Error` if coordination or write fails.
    static func write(
        to url: URL,
        options: NSFileCoordinator.WritingOptions = [],
        block: (URL) throws -> Void,
    ) throws {
        var coordinationError: NSError?
        var operationError: (any Swift.Error)?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinationError) { actualURL in
            do {
                try block(actualURL)
            } catch {
                operationError = error
            }
        }

        if let error = coordinationError {
            throw Error.coordinationFailed(error)
        }
        if let error = operationError {
            throw Error.operationFailed(error)
        }
    }

    /// Performs a coordinated delete operation.
    ///
    /// - Parameter url: The file URL to delete.
    /// - Throws: `Error` if coordination or delete fails.
    static func delete(_ url: URL) throws {
        try write(to: url, options: .forDeleting) { actualURL in
            try FileManager.default.removeItem(at: actualURL)
        }
    }

    // MARK: - Read Operations

    /// Performs a coordinated read operation.
    ///
    /// - Parameters:
    ///   - url: The file URL to read.
    ///   - options: Read coordination options.
    ///   - block: The read operation to perform.
    /// - Returns: The result of the read operation.
    /// - Throws: `Error` if coordination or read fails.
    static func read<T>(
        from url: URL,
        options: NSFileCoordinator.ReadingOptions = [],
        block: (URL) throws -> T,
    ) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, any Swift.Error>?

        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: url, options: options, error: &coordinationError) { actualURL in
            do {
                result = try .success(block(actualURL))
            } catch {
                result = .failure(error)
            }
        }

        if let error = coordinationError {
            throw Error.coordinationFailed(error)
        }

        switch result {
        case let .success(value):
            return value
        case let .failure(error):
            throw Error.operationFailed(error)
        case .none:
            throw Error.operationFailed(CocoaError(.fileReadUnknown))
        }
    }

    // MARK: - Utility Operations

    /// Creates the item replacement directory on the same volume as destination.
    ///
    /// This is critical for efficient downloads:
    /// - Same-volume moves are instant (no copy)
    /// - Prevents "disk full" issues on destination volume
    /// - Uses system-managed temporary location
    ///
    /// - Parameter destination: The final destination URL.
    /// - Returns: URL of the item replacement directory.
    /// - Throws: If directory creation fails.
    static func createItemReplacementDirectory(for destination: URL) throws -> URL {
        try FileManager.default.url(
            for: .itemReplacementDirectory,
            in: .userDomainMask,
            appropriateFor: destination,
            create: true,
        )
    }

    /// Creates an empty placeholder file at the destination.
    ///
    /// Useful for:
    /// - Reserving the filename before download starts
    /// - Setting up file presenters that need an existing file
    /// - Checking write permissions early
    ///
    /// - Parameter url: The file URL to create.
    /// - Parameter hidden: Whether to mark the file as hidden.
    /// - Throws: If file creation fails.
    static func createPlaceholder(at url: URL, hidden: Bool = true) throws {
        try write(to: url, options: .forReplacing) { actualURL in
            let fm = FileManager.default

            // Create parent directory if needed
            let parentDir = actualURL.deletingLastPathComponent()
            if !fm.fileExists(atPath: parentDir.path) {
                try fm.createDirectory(at: parentDir, withIntermediateDirectories: true)
            }

            // Create empty file
            guard fm.createFile(atPath: actualURL.path, contents: nil) else {
                throw CocoaError(.fileWriteNoPermission)
            }

            // Mark as hidden if requested
            if hidden {
                var resourceValues = URLResourceValues()
                resourceValues.isHidden = true
                var mutableURL = actualURL
                try mutableURL.setResourceValues(resourceValues)
            }
        }
    }
}
