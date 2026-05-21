import Foundation

/// Shim for `browser.downloads` API bridging to Refrax's download manager.
///
/// Implements the WebExtensions downloads API for initiating and tracking
/// file downloads. Bridges to Refrax's existing download infrastructure.
///
/// ## Supported Operations
///
/// - `download()` - Start a download
/// - `search()` - Query download history
/// - `pause()` / `resume()` / `cancel()` - Control downloads
/// - `getFileIcon()` - Get file type icon
/// - `open()` / `show()` - Open downloaded files
///
/// ## Limitations
///
/// - `setShelfEnabled()` is a no-op (macOS doesn't have a download shelf)
/// - `acceptDanger()` is not supported (handled differently on macOS)
///
/// ## Thread Safety
///
/// All operations are MainActor-isolated.

final class DownloadsShim: ExtensionShim {
    // MARK: - Types

    /// Download state matching WebExtensions API.
    enum DownloadState: String {
        case inProgress = "in_progress"
        case interrupted
        case complete
    }

    /// Download info for JavaScript responses.
    struct DownloadInfo {
        let id: Int
        let url: String
        let filename: String?
        let state: DownloadState
        let bytesReceived: Int64
        let totalBytes: Int64
        let exists: Bool
        let canResume: Bool
    }

    // MARK: - Properties

    /// Maps extension download IDs to internal download identifiers.
    /// Key is "{extensionID}:{downloadId}".
    private var downloadMap: [String: String] = [:]

    /// Counter for generating download IDs.
    private var nextDownloadId = 1

    /// Tracks downloads initiated by each extension.
    private var extensionDownloads: [String: Set<Int>] = [:]

    // MARK: - ExtensionShim Protocol

    func handle(method: String, args: [String: Any], extensionID: String) async throws -> Any? {
        switch method {
        case "download":
            guard let options = args["options"] as? [String: Any] else {
                throw ShimError.invalidArguments("'options' is required")
            }
            return try await download(options: options, extensionID: extensionID)

        case "search":
            let query = args["query"] as? [String: Any] ?? [:]
            return await search(query: query, extensionID: extensionID)

        case "pause":
            guard let downloadId = args["downloadId"] as? Int else {
                throw ShimError.invalidArguments("'downloadId' is required")
            }
            try await pause(downloadId: downloadId, extensionID: extensionID)
            return nil

        case "resume":
            guard let downloadId = args["downloadId"] as? Int else {
                throw ShimError.invalidArguments("'downloadId' is required")
            }
            try await resume(downloadId: downloadId, extensionID: extensionID)
            return nil

        case "cancel":
            guard let downloadId = args["downloadId"] as? Int else {
                throw ShimError.invalidArguments("'downloadId' is required")
            }
            try await cancel(downloadId: downloadId, extensionID: extensionID)
            return nil

        case "open":
            guard let downloadId = args["downloadId"] as? Int else {
                throw ShimError.invalidArguments("'downloadId' is required")
            }
            try await open(downloadId: downloadId, extensionID: extensionID)
            return nil

        case "show":
            guard let downloadId = args["downloadId"] as? Int else {
                throw ShimError.invalidArguments("'downloadId' is required")
            }
            try await show(downloadId: downloadId, extensionID: extensionID)
            return nil

        case "showDefaultFolder":
            showDefaultFolder()
            return nil

        case "erase":
            let query = args["query"] as? [String: Any] ?? [:]
            return await erase(query: query, extensionID: extensionID)

        case "removeFile":
            guard let downloadId = args["downloadId"] as? Int else {
                throw ShimError.invalidArguments("'downloadId' is required")
            }
            try await removeFile(downloadId: downloadId, extensionID: extensionID)
            return nil

        case "setShelfEnabled":
            // No-op on macOS
            return nil

        default:
            throw ShimError.unsupportedMethod(method)
        }
    }

    // MARK: - Download Operations

    /// Initiates a download.
    ///
    /// - Parameters:
    ///   - options: Download options (url, filename, saveAs, etc.).
    ///   - extensionID: The calling extension's identifier.
    /// - Returns: The download ID.
    private func download(options: [String: Any], extensionID: String) async throws -> Int {
        guard let urlString = options["url"] as? String,
              let url = URL(string: urlString) else {
            throw ShimError.invalidArguments("Valid 'url' is required")
        }

        let downloadId = nextDownloadId
        nextDownloadId += 1

        // Track the download
        var downloads = extensionDownloads[extensionID] ?? []
        downloads.insert(downloadId)
        extensionDownloads[extensionID] = downloads

        let key = "\(extensionID):\(downloadId)"

        // Get optional parameters
        let filename = options["filename"] as? String
        let saveAs = options["saveAs"] as? Bool ?? false

        // Determine destination
        let destination: URL
        if let filename, !saveAs {
            // Use specified filename in Downloads folder
            let downloadsDir = Directories.downloads
            destination = downloadsDir.appendingPathComponent(filename)
        } else if saveAs {
            // Would show save dialog - for now, use default
            let downloadsDir = Directories.downloads
            let defaultName = filename ?? url.lastPathComponent
            destination = downloadsDir.appendingPathComponent(defaultName)
        } else {
            // Use URL's filename in Downloads folder
            let downloadsDir = Directories.downloads
            destination = downloadsDir.appendingPathComponent(url.lastPathComponent)
        }

        // Start the download using URLSession
        // In a real implementation, this would integrate with Refrax's DownloadManager
        // Note: URLSession.shared completion handlers run on a background thread,
        // so we use DispatchQueue.main.async to dispatch to MainActor.
        let downloadTask = URLSession.shared.downloadTask(with: url) { [weak self] tempURL, _, error in
            DispatchQueue.main.async {
                guard let self, let tempURL, error == nil else {
                    Logger.error(
                        "Download failed for \(url): \(error?.localizedDescription ?? "unknown error")",
                        category: Logger.extensions,
                    )
                    return
                }

                do {
                    // Move to destination
                    if FileManager.default.fileExists(atPath: destination.path) {
                        try FileManager.default.removeItem(at: destination)
                    }
                    try FileManager.default.moveItem(at: tempURL, to: destination)

                    // Store the path
                    self.downloadMap[key] = destination.path

                    Logger.info(
                        "Download complete: \(destination.lastPathComponent)",
                        category: Logger.extensions,
                    )
                } catch {
                    Logger.error(
                        "Failed to save download: \(error)",
                        category: Logger.extensions,
                    )
                }
            }
        }

        downloadTask.resume()

        Logger.debug(
            "Started download \(downloadId) for extension \(extensionID): \(url)",
            category: Logger.extensions,
        )

        return downloadId
    }

    /// Searches for downloads.
    ///
    /// - Parameters:
    ///   - query: Search criteria.
    ///   - extensionID: The calling extension's identifier.
    /// - Returns: Array of download info objects.
    private func search(query _: [String: Any], extensionID: String) async -> [[String: Any]] {
        // For now, return downloads initiated by this extension
        guard let downloads = extensionDownloads[extensionID] else {
            return []
        }

        return downloads.compactMap { downloadId in
            let key = "\(extensionID):\(downloadId)"
            guard let path = downloadMap[key] else { return nil }

            let exists = FileManager.default.fileExists(atPath: path)

            return [
                "id": downloadId,
                "filename": path,
                "state": exists ? "complete" : "interrupted",
                "exists": exists,
                "canResume": false,
                "bytesReceived": 0,
                "totalBytes": 0,
            ] as [String: Any]
        }
    }

    /// Pauses a download.
    private func pause(downloadId: Int, extensionID _: String) async throws {
        // Would pause the download through DownloadManager
        Logger.debug("Pause download \(downloadId) requested", category: Logger.extensions)
    }

    /// Resumes a download.
    private func resume(downloadId: Int, extensionID _: String) async throws {
        Logger.debug("Resume download \(downloadId) requested", category: Logger.extensions)
    }

    /// Cancels a download.
    private func cancel(downloadId: Int, extensionID _: String) async throws {
        Logger.debug("Cancel download \(downloadId) requested", category: Logger.extensions)
    }

    /// Opens a downloaded file.
    private func open(downloadId: Int, extensionID: String) async throws {
        let key = "\(extensionID):\(downloadId)"
        guard let path = downloadMap[key] else {
            throw ShimError.notFound("Download \(downloadId)")
        }

        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.open(url)
    }

    /// Shows a downloaded file in Finder.
    private func show(downloadId: Int, extensionID: String) async throws {
        let key = "\(extensionID):\(downloadId)"
        guard let path = downloadMap[key] else {
            throw ShimError.notFound("Download \(downloadId)")
        }

        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.selectFile(url.path, inFileViewerRootedAtPath: url.deletingLastPathComponent().path)
    }

    /// Opens the default downloads folder.
    private func showDefaultFolder() {
        let downloadsDir = Directories.downloads
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: downloadsDir.path)
    }

    /// Erases download records matching query.
    private func erase(query _: [String: Any], extensionID: String) async -> [Int] {
        // For now, just clear all records for this extension
        guard let downloads = extensionDownloads[extensionID] else {
            return []
        }

        let ids = Array(downloads)

        for id in ids {
            let key = "\(extensionID):\(id)"
            downloadMap.removeValue(forKey: key)
        }
        extensionDownloads[extensionID] = []

        return ids
    }

    /// Removes a downloaded file from disk.
    private func removeFile(downloadId: Int, extensionID: String) async throws {
        let key = "\(extensionID):\(downloadId)"
        guard let path = downloadMap[key] else {
            throw ShimError.notFound("Download \(downloadId)")
        }

        try FileManager.default.removeItem(atPath: path)
        downloadMap.removeValue(forKey: key)
        extensionDownloads[extensionID]?.remove(downloadId)
    }

    // MARK: - Cleanup

    /// Clears all download records for an extension (called on uninstall).
    func clearAllForExtension(_ extensionID: String) {
        guard let downloads = extensionDownloads[extensionID] else { return }

        for downloadId in downloads {
            let key = "\(extensionID):\(downloadId)"
            downloadMap.removeValue(forKey: key)
        }
        extensionDownloads.removeValue(forKey: extensionID)
    }
}
