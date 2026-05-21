import AppKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// Manages global shelf item storage and retrieval.
///
/// Items are stored globally (not per-space) in Application Support/Shelf/.
/// The shelf accepts non-URL drops (text, images, files) and supports drag-out
/// to other applications via `NSItemProvider`.
///
/// ## Storage Strategy
///
/// | Content Type | Storage Format | Notes |
/// |--------------|----------------|-------|
/// | Plain text   | `.textClipping` | Apple native plist format |
/// | Images       | Original format | Preserves .png, .jpg, .gif, etc. |
/// | Files < 10MB | Copy | Preserves original extension |
/// | Files ≥ 10MB | `.alias` | Bookmark data for original location |
///
/// ## Architecture
///
/// ```
/// SidebarDropReceiver (shelf content detected)
///         │
///         ▼
///   ShelfManager.addItem(from:)
///         │
///         ├── Copy/store to ~/Library/Application Support/.../Shelf/
///         ├── Update items list
///         └── Persist metadata to shelf-metadata.json
///                    │
///                    ▼
///              ShelfPanel UI (via @Observable)
/// ```
@Observable
@MainActor
final class ShelfManager {
    // MARK: - Constants

    private enum Constants: Sendable {
        /// Maximum file size before creating an alias instead of copying (10MB).
        nonisolated static let maxCopySize: Int64 = 10 * 1_024 * 1_024
        /// Metadata file name.
        nonisolated static let metadataFileName = "shelf-metadata.json"
    }

    // MARK: - Properties

    /// All shelf items, sorted by creation date (newest first).
    private(set) var items: [ShelfItem] = []

    /// Whether the shelf panel is expanded.
    var isExpanded: Bool = false

    // TODO: Add toast feedback when ToastManager is implemented

    /// Whether there are any items in the shelf.
    var hasItems: Bool {
        !items.isEmpty
    }

    /// The shelf storage directory.
    nonisolated static let shelfDirectory: URL = {
        let directory = Directories.appStorage.appendingPathComponent("Shelf", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }()

    /// Path to metadata file.
    private nonisolated static var metadataPath: URL {
        shelfDirectory.appendingPathComponent(Constants.metadataFileName)
    }

    // MARK: - Initialization

    init() {
        Task {
            await loadItems()
        }
    }

    // MARK: - Loading

    /// Loads shelf items from disk on initialization.
    func loadItems() async {
        // Try to load from metadata file first
        let metadataURL = Self.metadataPath
        let loadedData = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: metadataURL)
        }.value

        if let data = loadedData,
           let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data) {
            items = decoded.sorted { $0.createdAt > $1.createdAt }
            // Validate items still exist on disk
            let originalCount = items.count
            items = items.filter { item in
                let path = storagePath(for: item)
                return FileManager.default.fileExists(atPath: path.path)
            }
            // Persist if any items were removed (files deleted externally)
            if items.count != originalCount {
                persistMetadata()
            }
            return
        }

        // Fallback: scan directory for items (migration from pre-metadata era)
        await scanDirectory()
    }

    /// Scans the shelf directory and reconstructs items list.
    private func scanDirectory() async {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: Self.shelfDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
        ) else { return }

        var loadedItems: [ShelfItem] = []

        for url in files {
            // Skip metadata file
            if url.lastPathComponent == Constants.metadataFileName { continue }

            guard let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey]) else {
                continue
            }

            let fileName = url.lastPathComponent
            let fileSize = Int64(resourceValues.fileSize ?? 0)
            let createdAt = resourceValues.creationDate ?? Date()

            // Parse item ID from filename (format: item-{uuid}.{ext})
            let baseName = url.deletingPathExtension().lastPathComponent
            guard baseName.hasPrefix("item-"),
                  let id = UUID(uuidString: String(baseName.dropFirst(5))) else {
                continue
            }

            let type = determineType(for: url)
            let displayName = await extractDisplayName(from: url, type: type)

            await loadedItems.append(ShelfItem(
                id: id,
                type: type,
                fileName: fileName,
                displayName: displayName,
                originalPath: type == .alias ? resolveAlias(at: url) : nil,
                createdAt: createdAt,
                fileSize: fileSize,
            ))
        }

        items = loadedItems.sorted { $0.createdAt > $1.createdAt }
        persistMetadata()
    }

    /// Determines the item type from file extension.
    private func determineType(for url: URL) -> ShelfItemType {
        let ext = url.pathExtension.lowercased()

        switch ext {
        case "textclipping":
            return .text
        case "alias":
            return .alias
        case "png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "bmp":
            return .image
        default:
            return .file
        }
    }

    /// Extracts a display name from a file.
    private func extractDisplayName(from url: URL, type: ShelfItemType) async -> String {
        if type == .text {
            // Try to extract text content for display (read on background thread)
            let loadedData = await Task.detached(priority: .userInitiated) {
                try? Data(contentsOf: url)
            }.value

            if let data = loadedData,
               let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
               let text = plist["public.utf8-plain-text"] as? String {
                return String(text.prefix(50))
            }
        }
        return url.deletingPathExtension().lastPathComponent
    }

    /// Resolves an alias file to its original URL.
    private func resolveAlias(at url: URL) async -> URL? {
        let bookmarkData = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value

        guard let bookmarkData else { return nil }
        var isStale = false
        return try? URL(
            resolvingBookmarkData: bookmarkData,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale,
        )
    }

    // MARK: - Types

    /// Result of attempting to add a URL to the shelf.
    enum URLAddResult {
        /// Successfully added to shelf.
        case addedToShelf

        /// URL contains HTML content - should open as a new tab instead.
        case openAsTab

        /// Failed to process the URL.
        case failed
    }

    // MARK: - Dependencies

    /// Download manager for downloading URLs with proper cookies.
    private weak var downloadManager: DownloadManager?

    /// Data store for fetching cookies.
    private weak var dataStore: WKWebsiteDataStore?

    /// Continuation for waiting on a specific download completion.
    private var downloadContinuations: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// Configures dependencies for URL downloads.
    ///
    /// Call this after initialization to enable downloading URLs to the shelf.
    func configure(downloadManager: DownloadManager, dataStore: WKWebsiteDataStore) {
        self.downloadManager = downloadManager
        self.dataStore = dataStore

        // Chain completion callback to resume waiting continuations
        // Preserve any existing callback
        let existingCompletedCallback = downloadManager.onDownloadCompleted
        downloadManager.onDownloadCompleted = { [weak self] download in
            existingCompletedCallback?(download)
            self?.handleDownloadFinished(download.id)
        }

        // Also chain failure callback
        let existingFailedCallback = downloadManager.onDownloadFailed
        downloadManager.onDownloadFailed = { [weak self] download, error in
            existingFailedCallback?(download, error)
            self?.handleDownloadFinished(download.id)
        }
    }

    /// Handles download completion (success or failure) by resuming any waiting continuation.
    private func handleDownloadFinished(_ downloadID: UUID) {
        if let continuation = downloadContinuations.removeValue(forKey: downloadID) {
            continuation.resume()
        }
    }

    // MARK: - Adding Items

    /// Adds items from pasteboard providers (called by SidebarDropReceiver).
    func addItem(from providers: [NSItemProvider]) async {
        for provider in providers {
            if let item = await processProvider(provider) {
                items.insert(item, at: 0)
            }
        }
        persistMetadata()
    }

    /// Adds items from an NSPasteboard (for AppKit drag operations).
    func addItem(from pasteboard: NSPasteboard) async {
        // Try text first (but skip if it's just a URL - those should be handled as tabs)
        if let text = pasteboard.string(forType: .string), !text.isEmpty, !looksLikeURL(text) {
            if let item = await saveTextClipping(text: text) {
                items.insert(item, at: 0)
                persistMetadata()
                return
            }
        }

        // Try images
        let imageTypes: [NSPasteboard.PasteboardType] = [
            NSPasteboard.PasteboardType(UTType.png.identifier),
            NSPasteboard.PasteboardType(UTType.tiff.identifier),
            NSPasteboard.PasteboardType(UTType.jpeg.identifier),
            .png,
            .tiff,
        ]

        for imageType in imageTypes {
            if let data = pasteboard.data(forType: imageType),
               let item = await saveImageData(data, extension: imageExtension(for: imageType)) {
                items.insert(item, at: 0)
                persistMetadata()
                return
            }
        }

        // Try file URLs
        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls where url.isFileURL {
                if let item = await saveFile(from: url) {
                    items.insert(item, at: 0)
                }
            }
            persistMetadata()
        }
    }

    /// Attempts to add an item from a web URL by downloading it.
    ///
    /// Probes the URL to determine if it's a downloadable file (image, PDF, etc.)
    /// vs a webpage. If downloadable, downloads with proper cookies and adds to shelf.
    ///
    /// Some servers (like Wikipedia's File: pages) return HTML even for URLs with
    /// image extensions. In such cases, the downloaded content is checked and if
    /// it's HTML, the file is cleaned up and `.openAsTab` is returned.
    ///
    /// - Parameters:
    ///   - url: The URL to potentially download.
    ///   - dataStore: Optional data store for cookies (uses configured default if nil).
    /// - Returns: Result indicating whether item was added to shelf, should open as tab, or failed.
    func addItemFromURL(_ url: URL, dataStore: WKWebsiteDataStore? = nil) async -> URLAddResult {
        guard let downloadManager else {
            Logger.warning("ShelfManager: DownloadManager not configured, cannot download URL", category: Logger.storage)
            return .failed
        }

        // First, check if the URL looks like it might be a download based on extension
        let probeResult = await PopupContentProbe.shared.probe(url, timeout: 3.0)

        switch probeResult {
        case let .download(finalURL, suggestedFilename):
            // Confirmed download - download it and add to shelf
            return await downloadToShelf(
                url: finalURL,
                suggestedFilename: suggestedFilename,
                downloadManager: downloadManager,
                dataStore: dataStore ?? self.dataStore ?? .default(),
            )

        case .webpage:
            // Probe determined it's a webpage - open as tab
            return .openAsTab

        case .unknown:
            // Couldn't determine - let caller handle as tab
            return .openAsTab

        case .skipProbe:
            // URL doesn't look like a download (no download-like extension)
            // But it might still be an image - check common image extensions
            let ext = url.pathExtension.lowercased()
            let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "svg", "ico", "bmp", "tiff"]
            if imageExtensions.contains(ext) {
                // It's an image URL - download and verify it's actually an image
                return await downloadToShelf(
                    url: url,
                    suggestedFilename: url.lastPathComponent,
                    downloadManager: downloadManager,
                    dataStore: dataStore ?? self.dataStore ?? .default(),
                )
            }
            return .openAsTab
        }
    }

    /// File extensions that indicate HTML content.
    ///
    /// The download system adds these extensions based on the actual MIME type
    /// from the HTTP response, making this check more reliable than checking
    /// `download.mimeType` which may be nil.
    private static let htmlExtensions: Set<String> = [
        "html",
        "htm",
        "xhtml",
    ]

    /// Downloads a URL and adds the resulting file to the shelf.
    ///
    /// If the downloaded content turns out to be HTML (e.g., Wikipedia File: pages),
    /// the file is cleaned up and `.openAsTab` is returned.
    private func downloadToShelf(
        url: URL,
        suggestedFilename: String?,
        downloadManager: DownloadManager,
        dataStore: WKWebsiteDataStore,
    ) async -> URLAddResult {
        let filename = suggestedFilename ?? url.lastPathComponent

        // Start the download - it will go to the shelf directory
        do {
            let download = try await downloadManager.startDownload(
                from: url,
                suggestedFilename: filename,
                dataStore: dataStore,
                customDownloadPath: Self.shelfDirectory.path,
            )

            // Wait for download to complete using continuation
            await waitForDownloadCompletion(download)

            // Check if download failed
            guard download.state == .completed else {
                Logger.warning("Download did not complete successfully: \(download.state)", category: Logger.storage)
                return .failed
            }

            let fileURL = download.finalFileURL

            // Check if the actual content is HTML (e.g., Wikipedia File: pages)
            // The download system adds .html extension based on actual MIME type from response,
            // so checking the final extension is more reliable than download.mimeType which may be nil.
            let finalExtension = fileURL.pathExtension.lowercased()
            if Self.htmlExtensions.contains(finalExtension) {
                // Clean up the downloaded HTML file
                try? FileManager.default.removeItem(at: fileURL)
                Logger.info(
                    "Downloaded content is HTML (.\(finalExtension)), not a file. Cleaning up and opening as tab: \(url)",
                    category: Logger.storage,
                )
                return .openAsTab
            }

            // Add to shelf items
            if let item = await createShelfItemFromDownload(fileURL: fileURL, displayName: filename) {
                items.insert(item, at: 0)
                persistMetadata()
                Logger.info("Added downloaded file to shelf: \(filename)", category: Logger.storage)
                return .addedToShelf
            }

            return .failed
        } catch {
            Logger.error("Failed to download URL for shelf: \(error)", category: Logger.storage)
            return .failed
        }
    }

    /// Waits for a download to complete using a continuation.
    ///
    /// Uses the download manager's completion callback instead of polling.
    private func waitForDownloadCompletion(_ download: Download) async {
        // If already complete, return immediately
        guard download.state.isActive else { return }

        // Wait for completion via continuation
        await withCheckedContinuation { continuation in
            downloadContinuations[download.id] = continuation
        }
    }

    /// Creates a ShelfItem from a downloaded file.
    private func createShelfItemFromDownload(fileURL: URL, displayName: String) async -> ShelfItem? {
        let fm = FileManager.default

        // Get file info
        guard let attributes = try? fm.attributesOfItem(atPath: fileURL.path),
              let fileSize = attributes[.size] as? Int64 else {
            return nil
        }

        // Generate shelf item ID and rename file to shelf format
        let id = UUID()
        let ext = fileURL.pathExtension.lowercased()
        let newFileName = ext.isEmpty ? "item-\(id.uuidString)" : "item-\(id.uuidString).\(ext)"
        let newPath = Self.shelfDirectory.appendingPathComponent(newFileName)

        // Rename the downloaded file to shelf format
        do {
            try fm.moveItem(at: fileURL, to: newPath)
        } catch {
            Logger.error("Failed to rename downloaded file for shelf: \(error)", category: Logger.storage)
            return nil
        }

        let type = determineType(for: newPath)

        return ShelfItem(
            id: id,
            type: type,
            fileName: newFileName,
            displayName: displayName,
            originalPath: nil,
            createdAt: Date(),
            fileSize: fileSize,
        )
    }

    /// Processes an NSItemProvider and returns a ShelfItem if successful.
    private func processProvider(_ provider: NSItemProvider) async -> ShelfItem? {
        // Try plain text first
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String {
                return await saveTextClipping(text: text)
            }
        }

        // Try image
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            let imageData = await withCheckedContinuation { continuation in
                _ = provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    continuation.resume(returning: data)
                }
            }
            if let data = imageData {
                return await saveImageData(data, extension: "png")
            }
        }

        // Try file URL
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) as? URL {
                return await saveFile(from: url)
            }
        }

        return nil
    }

    /// Returns file extension for a pasteboard type.
    private func imageExtension(for type: NSPasteboard.PasteboardType) -> String {
        let identifier = type.rawValue
        if identifier == UTType.jpeg.identifier { return "jpg" }
        if identifier == UTType.tiff.identifier || type == .tiff { return "tiff" }
        return "png"
    }

    // MARK: - Saving Items

    /// Saves text as a .textClipping file (Apple's native format).
    private func saveTextClipping(text: String) async -> ShelfItem? {
        let id = UUID()
        let fileName = "item-\(id.uuidString).textClipping"

        // Create textClipping (plist format)
        let clipping: [String: Any] = ["public.utf8-plain-text": text]
        guard let data = try? PropertyListSerialization.data(
            fromPropertyList: clipping,
            format: .binary,
            options: 0,
        ) else { return nil }

        let path = Self.shelfDirectory.appendingPathComponent(fileName)
        do {
            try data.write(to: path)
        } catch {
            Logger.error("Failed to save text clipping: \(error)", category: Logger.storage)
            return nil
        }

        return ShelfItem(
            id: id,
            type: .text,
            fileName: fileName,
            displayName: String(text.prefix(50)),
            originalPath: nil,
            createdAt: Date(),
            fileSize: Int64(data.count),
        )
    }

    /// Saves image data to a file.
    private func saveImageData(_ data: Data, extension ext: String) async -> ShelfItem? {
        let id = UUID()
        let fileName = "item-\(id.uuidString).\(ext)"
        let path = Self.shelfDirectory.appendingPathComponent(fileName)

        do {
            try data.write(to: path)
        } catch {
            Logger.error("Failed to save image: \(error)", category: Logger.storage)
            return nil
        }

        return ShelfItem(
            id: id,
            type: .image,
            fileName: fileName,
            displayName: "Image",
            originalPath: nil,
            createdAt: Date(),
            fileSize: Int64(data.count),
        )
    }

    /// Saves a file, either copying it or creating an alias for large files.
    private func saveFile(from url: URL) async -> ShelfItem? {
        let id = UUID()

        // Get file size
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else {
            return nil
        }

        // Check if file is too large to copy
        if fileSize >= Constants.maxCopySize {
            Logger.info("File too large to copy, storing as alias: \(url.lastPathComponent)", category: Logger.storage)
            return await saveAlias(url: url, id: id)
        }

        // Determine if this is an image
        let ext = url.pathExtension.lowercased()
        let imageExtensions = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "bmp"]
        let type: ShelfItemType = imageExtensions.contains(ext) ? .image : .file

        // Handle files with no extension
        let fileName = ext.isEmpty
            ? "item-\(id.uuidString)"
            : "item-\(id.uuidString).\(ext)"
        let destPath = Self.shelfDirectory.appendingPathComponent(fileName)

        do {
            try FileManager.default.copyItem(at: url, to: destPath)
        } catch {
            Logger.error("Failed to copy file: \(error)", category: Logger.storage)
            return nil
        }

        return ShelfItem(
            id: id,
            type: type,
            fileName: fileName,
            displayName: url.lastPathComponent,
            originalPath: nil,
            createdAt: Date(),
            fileSize: fileSize,
        )
    }

    /// Saves an alias (bookmark) to a large file.
    private func saveAlias(url: URL, id: UUID) async -> ShelfItem? {
        let fileName = "item-\(id.uuidString).alias"
        let destPath = Self.shelfDirectory.appendingPathComponent(fileName)

        // Create bookmark data
        guard let bookmarkData = try? url.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil,
        ) else {
            Logger.error("Failed to create bookmark for: \(url)", category: Logger.storage)
            return nil
        }

        do {
            try bookmarkData.write(to: destPath)
        } catch {
            Logger.error("Failed to save alias: \(error)", category: Logger.storage)
            return nil
        }

        return ShelfItem(
            id: id,
            type: .alias,
            fileName: fileName,
            displayName: url.lastPathComponent,
            originalPath: url,
            createdAt: Date(),
            fileSize: 0,
        )
    }

    // MARK: - Item Actions

    /// Deletes an item from the shelf.
    func deleteItem(_ item: ShelfItem) {
        let path = storagePath(for: item)
        try? FileManager.default.removeItem(at: path)
        items.removeAll { $0.id == item.id }
        persistMetadata()

        // Auto-close panel when empty
        if items.isEmpty {
            isExpanded = false
        }
    }

    /// Moves an item to the Downloads folder.
    func moveToDownloads(_ item: ShelfItem) async {
        let sourcePath = storagePath(for: item)
        let destPath = uniqueDownloadPath(for: item)

        do {
            if item.type == .alias {
                // Resolve alias and copy the original file (read on background thread)
                let bookmarkData = await Task.detached(priority: .userInitiated) {
                    try? Data(contentsOf: sourcePath)
                }.value

                var isStale = false
                guard let data = bookmarkData,
                      let resolvedURL = try? URL(
                          resolvingBookmarkData: data,
                          options: .withSecurityScope,
                          relativeTo: nil,
                          bookmarkDataIsStale: &isStale,
                      ) else {
                    Logger.error("Failed to resolve alias: \(item.fileName)", category: Logger.storage)
                    return
                }
                _ = resolvedURL.startAccessingSecurityScopedResource()
                defer { resolvedURL.stopAccessingSecurityScopedResource() }
                try FileManager.default.copyItem(at: resolvedURL, to: destPath)
            } else if item.type == .text {
                // Extract text and save as .txt file (read on background thread)
                let loadedData = await Task.detached(priority: .userInitiated) {
                    try? Data(contentsOf: sourcePath)
                }.value

                if let data = loadedData,
                   let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                   let text = plist["public.utf8-plain-text"] as? String {
                    try text.write(to: destPath, atomically: true, encoding: .utf8)
                } else {
                    Logger.error("Failed to read text clipping: \(item.fileName)", category: Logger.storage)
                    return
                }
            } else {
                try FileManager.default.copyItem(at: sourcePath, to: destPath)
            }
        } catch {
            Logger.error("Failed to move to Downloads: \(error)", category: Logger.storage)
            return
        }

        deleteItem(item)
    }

    /// Returns a unique path in Downloads, handling filename collisions.
    private func uniqueDownloadPath(for item: ShelfItem) -> URL {
        let fm = FileManager.default
        let downloads = Directories.downloads

        // Determine base name and extension
        let (baseName, ext): (String, String) = {
            if item.type == .text {
                // Text clippings become .txt files with sanitized name
                let sanitized = item.displayName
                    .replacingOccurrences(of: "/", with: "-")
                    .replacingOccurrences(of: ":", with: "-")
                    .prefix(50)
                return (String(sanitized), "txt")
            } else {
                // Use display name with original extension
                let url = URL(fileURLWithPath: item.displayName)
                let ext = url.pathExtension
                let name = url.deletingPathExtension().lastPathComponent
                return (name, ext)
            }
        }()

        // Build filename
        let fileName = ext.isEmpty ? baseName : "\(baseName).\(ext)"
        var destPath = downloads.appendingPathComponent(fileName)

        // Handle collision by appending counter
        var counter = 1
        while fm.fileExists(atPath: destPath.path) {
            let newName = ext.isEmpty ? "\(baseName) \(counter)" : "\(baseName) \(counter).\(ext)"
            destPath = downloads.appendingPathComponent(newName)
            counter += 1
        }

        return destPath
    }

    /// Moves all items to Downloads.
    func moveAllToDownloads() async {
        for item in items {
            await moveToDownloads(item)
        }
    }

    /// Clears all items from the shelf.
    func clearAll() {
        for item in items {
            let path = storagePath(for: item)
            try? FileManager.default.removeItem(at: path)
        }
        items.removeAll()
        persistMetadata()
        isExpanded = false
    }

    // MARK: - Panel Actions

    /// Toggles the shelf panel expansion state.
    func togglePanel() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
            isExpanded.toggle()
        }
    }

    // MARK: - Helpers

    /// Returns the storage path for an item.
    func storagePath(for item: ShelfItem) -> URL {
        Self.shelfDirectory.appendingPathComponent(item.fileName)
    }

    /// Persists metadata to JSON file.
    private func persistMetadata() {
        guard let data = try? JSONEncoder().encode(items) else { return }
        try? data.write(to: Self.metadataPath)
    }

    /// Checks if text looks like a URL (should be handled as a tab, not shelf item).
    private func looksLikeURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Must be a single line
        guard !trimmed.contains("\n") else { return false }
        // Check for URL schemes
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
            return URL(string: trimmed) != nil
        }
        return false
    }

    // MARK: - Item Provider for Drag Out

    /// Creates an NSItemProvider for dragging an item out to other apps.
    func itemProvider(for item: ShelfItem) -> NSItemProvider {
        let provider = NSItemProvider()
        let path = storagePath(for: item)

        switch item.type {
        case .text:
            // Register text with deferred loading (reads file on background thread when drag starts)
            provider.registerDataRepresentation(
                forTypeIdentifier: UTType.plainText.identifier,
                visibility: .all,
            ) { completion in
                Task.detached {
                    guard let data = try? Data(contentsOf: path),
                          let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
                          let text = plist["public.utf8-plain-text"] as? String,
                          let textData = text.data(using: .utf8) else {
                        await MainActor.run {
                            completion(nil, NSError(domain: "ShelfManager", code: 1, userInfo: nil))
                        }
                        return
                    }
                    await MainActor.run {
                        completion(textData, nil)
                    }
                }
                return nil
            }

        case .image, .file:
            let uti = UTType(filenameExtension: path.pathExtension)?.identifier ?? UTType.data.identifier
            provider.registerFileRepresentation(
                forTypeIdentifier: uti,
                visibility: .all,
            ) { completion in
                completion(path, true, nil)
                return nil
            }

        case .alias:
            // Resolve alias with deferred loading (reads file on background thread when drag starts)
            provider.registerFileRepresentation(
                forTypeIdentifier: UTType.fileURL.identifier,
                visibility: .all,
            ) { completion in
                DispatchQueue.global(qos: .userInitiated).async {
                    guard let bookmarkData = try? Data(contentsOf: path) else {
                        completion(nil, false, NSError(domain: "ShelfManager", code: 2, userInfo: nil))
                        return
                    }
                    var isStale = false
                    guard let resolvedURL = try? URL(
                        resolvingBookmarkData: bookmarkData,
                        options: .withSecurityScope,
                        relativeTo: nil,
                        bookmarkDataIsStale: &isStale,
                    ) else {
                        completion(nil, false, NSError(domain: "ShelfManager", code: 3, userInfo: nil))
                        return
                    }
                    completion(resolvedURL, false, nil)
                }
                return nil
            }
        }

        return provider
    }
}
