import Foundation

/// Provides async wrappers for file coordination and quarantine operations.
///
/// Since `CoordinatedFileOperation` and `QuarantineManager` are MainActor-isolated
/// (due to project-wide default isolation), this actor provides async wrappers
/// that properly await the MainActor context. While this doesn't move file I/O
/// to a background thread, it does allow callers to use async/await syntax and
/// integrate cleanly with actor-based code.
///
/// Note: For true background file operations, the underlying utilities would
/// need to be marked `nonisolated`.
///
/// ## Usage
///
/// ```swift
/// let fileOps = FileOperationActor()
///
/// // Move a downloaded file to its final destination
/// try await fileOps.move(from: tempURL, to: destinationURL)
///
/// // Set quarantine attributes
/// try await fileOps.setQuarantine(on: fileURL, downloadURL: sourceURL)
/// ```
actor FileOperationActor {
    // MARK: - Move Operations

    /// Moves a file from source to destination with full coordination.
    ///
    /// - Parameters:
    ///   - source: Source file URL.
    ///   - destination: Destination file URL.
    ///   - replacing: If true, replaces existing file at destination.
    /// - Throws: `CoordinatedFileOperation.Error` if coordination or move fails.
    func move(
        from source: URL,
        to destination: URL,
        replacing: Bool = false,
    ) async throws {
        try await MainActor.run {
            try CoordinatedFileOperation.move(
                from: source,
                to: destination,
                replacing: replacing,
            )
        }
    }

    /// Replaces destination file with source file atomically.
    ///
    /// - Parameters:
    ///   - destination: The file to replace.
    ///   - source: The replacement file.
    ///   - backupItemName: Optional backup item name.
    /// - Returns: URL of backup file if created.
    /// - Throws: `CoordinatedFileOperation.Error` if coordination or replacement fails.
    @discardableResult
    func replace(
        _ destination: URL,
        with source: URL,
        backupItemName: String? = nil,
    ) async throws -> URL? {
        try await MainActor.run {
            try CoordinatedFileOperation.replace(
                destination,
                with: source,
                backupItemName: backupItemName,
            )
        }
    }

    /// Deletes a file with coordination.
    ///
    /// - Parameter url: The file URL to delete.
    /// - Throws: `CoordinatedFileOperation.Error` if coordination or delete fails.
    func delete(_ url: URL) async throws {
        try await MainActor.run {
            try CoordinatedFileOperation.delete(url)
        }
    }

    // MARK: - Quarantine Operations

    /// Sets quarantine attributes on a downloaded file.
    ///
    /// - Parameters:
    ///   - url: The downloaded file URL.
    ///   - downloadURL: The URL the file was downloaded from.
    ///   - originURL: The page that linked to the download (referrer).
    /// - Throws: If setting the attribute fails.
    func setQuarantine(
        on url: URL,
        downloadURL: URL? = nil,
        originURL: URL? = nil,
    ) async throws {
        try await MainActor.run {
            try QuarantineManager.setQuarantine(
                onFileAt: url,
                downloadedFrom: downloadURL,
                originPage: originURL,
            )
        }
    }

    /// Removes quarantine attributes from a file.
    ///
    /// - Parameter url: The file URL.
    /// - Throws: If removing the attribute fails.
    func removeQuarantine(from url: URL) async throws {
        try await MainActor.run {
            try QuarantineManager.removeQuarantine(from: url)
        }
    }

    // MARK: - Utility Operations

    /// Creates a placeholder file at the destination.
    ///
    /// - Parameters:
    ///   - url: The file URL to create.
    ///   - hidden: Whether to mark the file as hidden.
    /// - Throws: If file creation fails.
    func createPlaceholder(at url: URL, hidden: Bool = true) async throws {
        try await MainActor.run {
            try CoordinatedFileOperation.createPlaceholder(at: url, hidden: hidden)
        }
    }
}
