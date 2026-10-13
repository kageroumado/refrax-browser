import AppKit
import Foundation
import UniformTypeIdentifiers

/// Manages the File Island's shelf: storage, retrieval, and the actions on its items.
///
/// Items are stored globally (not per-space) in Application Support/Shelf/, and one
/// manager is shared by every window. The shelf accepts files, images, text, and links,
/// and its items drag back out to other applications.
///
/// ## Storage Strategy
///
/// | Content Type | Storage Format | Notes |
/// |--------------|----------------|-------|
/// | Plain text   | `.textClipping` | Apple native plist format |
/// | Links        | `.webloc` | Apple native plist format |
/// | Images       | Original format | Preserves .png, .jpg, .gif, etc. |
/// | Files < 10MB | Copy | Preserves original extension |
/// | Files ≥ 10MB | `.alias` | Bookmark data for original location |
///
/// Metadata for every item is kept in `shelf-metadata.json` beside the files.
@Observable
@MainActor
final class ShelfManager {
    // MARK: - Constants

    private enum Constants: Sendable {
        /// Maximum file size before creating an alias instead of copying (10MB).
        nonisolated static let maxCopySize: Int64 = 10 * 1_024 * 1_024
        /// Metadata file name.
        nonisolated static let metadataFileName = "shelf-metadata.json"
        /// The plist key a .textClipping stores its text under.
        nonisolated static let clippingTextKey = "public.utf8-plain-text"
        /// The plist key a .webloc stores its address under.
        nonisolated static let weblocURLKey = "URL"
        nonisolated static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "heif", "tiff", "bmp"]
    }

    // MARK: - Properties

    /// All shelf items, sorted by creation date (newest first).
    private(set) var items: [ShelfItem] = []

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
        Task(name: "Load shelf") {
            await loadItems()
        }
    }

    // MARK: - Loading

    /// Loads shelf items from disk on initialization.
    func loadItems() async {
        let metadataURL = Self.metadataPath
        let loadedData = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: metadataURL)
        }.value

        if let data = loadedData,
           let decoded = try? JSONDecoder().decode([ShelfItem].self, from: data) {
            items = decoded.sorted { $0.createdAt > $1.createdAt }
            // Items whose files were deleted outside the browser leave the shelf.
            let originalCount = items.count
            items = items.filter { FileManager.default.fileExists(atPath: storagePath(for: $0).path) }
            if items.count != originalCount {
                persistMetadata()
            }
            return
        }

        await scanDirectory()
    }

    /// Reconstructs the items list from the files in the shelf directory, for a shelf without metadata.
    private func scanDirectory() async {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(
            at: Self.shelfDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
        ) else { return }

        var loadedItems: [ShelfItem] = []

        for url in files {
            if url.lastPathComponent == Constants.metadataFileName {
                continue
            }

            guard let resourceValues = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey]) else {
                continue
            }

            // Item files are named item-{uuid}.{ext}.
            let baseName = url.deletingPathExtension().lastPathComponent
            guard baseName.hasPrefix("item-"),
                  let id = UUID(uuidString: String(baseName.dropFirst(5))) else {
                continue
            }

            let type = determineType(for: url)
            let contents = await Self.readPlist(at: url)
            await loadedItems.append(ShelfItem(
                id: id,
                type: type,
                fileName: url.lastPathComponent,
                displayName: displayName(for: url, type: type, contents: contents),
                originalPath: type == .alias ? resolveAlias(at: url) : nil,
                url: type == .link ? (contents?[Constants.weblocURLKey] as? String).flatMap(URL.init(string:)) : nil,
                createdAt: resourceValues.creationDate ?? Date(),
                fileSize: Int64(resourceValues.fileSize ?? 0),
            ))
        }

        items = loadedItems.sorted { $0.createdAt > $1.createdAt }
        persistMetadata()
    }

    /// Determines the item type from file extension.
    private func determineType(for url: URL) -> ShelfItemType {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "textclipping": return .text
        case "webloc": return .link
        case "alias": return .alias
        case _ where Constants.imageExtensions.contains(ext): return .image
        default: return .file
        }
    }

    private func displayName(for url: URL, type: ShelfItemType, contents: [String: Any]?) -> String {
        switch type {
        case .text:
            (contents?[Constants.clippingTextKey] as? String).map { String($0.prefix(50)) } ?? url.deletingPathExtension().lastPathComponent
        case .link:
            (contents?[Constants.weblocURLKey] as? String).flatMap(URL.init(string:))?.safeDisplayDomain ?? "Link"
        default:
            url.deletingPathExtension().lastPathComponent
        }
    }

    /// Resolves an alias file to its original URL.
    private func resolveAlias(at url: URL) async -> URL? {
        let bookmarkData = await Task.detached(priority: .userInitiated) {
            try? Data(contentsOf: url)
        }.value
        guard let bookmarkData else { return nil }
        return Self.resolveBookmark(bookmarkData)
    }

    private nonisolated static func resolveBookmark(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(resolvingBookmarkData: data, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    /// Reads a plist-backed item (.textClipping or .webloc) off the main thread.
    private nonisolated static func readPlist(at url: URL) async -> [String: Any]? {
        let data = await Task.detached(priority: .userInitiated) { try? Data(contentsOf: url) }.value
        guard let data else { return nil }
        return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
    }

    // MARK: - Adding Items

    /// Keeps what a drop carries: its files, else its image, else its web address, else its text.
    ///
    /// - Returns: How many items were added.
    @discardableResult
    func add(_ drop: ShelfDrop) async -> Int {
        var added: [ShelfItem] = []
        for url in drop.fileURLs {
            if let item = await saveFile(from: url) {
                added.append(item)
            }
        }
        if added.isEmpty, let image = drop.image, let item = await saveImageData(image.data, extension: image.fileExtension) {
            added.append(item)
        }
        if added.isEmpty, let link = drop.link, let item = await saveLink(link, title: drop.linkTitle) {
            added.append(item)
        }
        if added.isEmpty, let text = drop.text, let item = await saveTextClipping(text: text) {
            added.append(item)
        }
        guard !added.isEmpty else { return 0 }
        items.insert(contentsOf: added.reversed(), at: 0)
        persistMetadata()
        return added.count
    }

    // MARK: - Saving Items

    /// Saves text as a .textClipping file (Apple's native format).
    private func saveTextClipping(text: String) async -> ShelfItem? {
        let id = UUID()
        let fileName = "item-\(id.uuidString).textClipping"
        guard let data = writePlist([Constants.clippingTextKey: text], named: fileName) else { return nil }
        return ShelfItem(
            id: id, type: .text, fileName: fileName, displayName: String(text.prefix(50)),
            originalPath: nil, createdAt: Date(), fileSize: Int64(data.count),
        )
    }

    /// Saves a web address as a .webloc file, named by the page title when the drag carries one.
    private func saveLink(_ url: URL, title: String?) async -> ShelfItem? {
        let id = UUID()
        let fileName = "item-\(id.uuidString).webloc"
        guard let data = writePlist([Constants.weblocURLKey: url.absoluteString], named: fileName) else { return nil }
        let name = title?.trimmingCharacters(in: .whitespacesAndNewlines)
        return ShelfItem(
            id: id, type: .link, fileName: fileName,
            displayName: name.flatMap { $0.isEmpty ? nil : $0 } ?? url.safeDisplayDomain,
            originalPath: nil, url: url, createdAt: Date(), fileSize: Int64(data.count),
        )
    }

    private func writePlist(_ plist: [String: String], named fileName: String) -> Data? {
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0) else { return nil }
        do {
            try data.write(to: Self.shelfDirectory.appendingPathComponent(fileName))
        } catch {
            Logger.error("Failed to save shelf item: \(error)", category: Logger.storage)
            return nil
        }
        return data
    }

    /// Saves image data to a file.
    private func saveImageData(_ data: Data, extension ext: String) async -> ShelfItem? {
        let id = UUID()
        let fileName = "item-\(id.uuidString).\(ext)"
        do {
            try data.write(to: Self.shelfDirectory.appendingPathComponent(fileName))
        } catch {
            Logger.error("Failed to save image: \(error)", category: Logger.storage)
            return nil
        }
        return ShelfItem(
            id: id, type: .image, fileName: fileName, displayName: "Image",
            originalPath: nil, createdAt: Date(), fileSize: Int64(data.count),
        )
    }

    /// Saves a file, either copying it or creating an alias for large files.
    private func saveFile(from url: URL) async -> ShelfItem? {
        let id = UUID()

        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let fileSize = attributes[.size] as? Int64 else {
            return nil
        }

        if fileSize >= Constants.maxCopySize {
            Logger.info("File too large to copy, storing as alias: \(url.lastPathComponent)", category: Logger.storage)
            return await saveAlias(url: url, id: id)
        }

        let ext = url.pathExtension.lowercased()
        let type: ShelfItemType = Constants.imageExtensions.contains(ext) ? .image : .file
        let fileName = ext.isEmpty ? "item-\(id.uuidString)" : "item-\(id.uuidString).\(ext)"

        do {
            try FileManager.default.copyItem(at: url, to: Self.shelfDirectory.appendingPathComponent(fileName))
        } catch {
            Logger.error("Failed to copy file: \(error)", category: Logger.storage)
            return nil
        }

        return ShelfItem(
            id: id, type: type, fileName: fileName, displayName: url.lastPathComponent,
            originalPath: nil, createdAt: Date(), fileSize: fileSize,
        )
    }

    /// Saves an alias (bookmark) to a large file.
    private func saveAlias(url: URL, id: UUID) async -> ShelfItem? {
        let fileName = "item-\(id.uuidString).alias"
        guard let bookmarkData = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) else {
            Logger.error("Failed to create bookmark for: \(url)", category: Logger.storage)
            return nil
        }
        do {
            try bookmarkData.write(to: Self.shelfDirectory.appendingPathComponent(fileName))
        } catch {
            Logger.error("Failed to save alias: \(error)", category: Logger.storage)
            return nil
        }
        return ShelfItem(
            id: id, type: .alias, fileName: fileName, displayName: url.lastPathComponent,
            originalPath: url, createdAt: Date(), fileSize: 0,
        )
    }

    // MARK: - Item Actions

    /// Removes an item from the shelf and deletes its stored file.
    func deleteItem(_ item: ShelfItem) {
        try? FileManager.default.removeItem(at: storagePath(for: item))
        items.removeAll { $0.id == item.id }
        persistMetadata()
    }

    /// Removes every item from the shelf.
    func clearAll() {
        for item in items {
            try? FileManager.default.removeItem(at: storagePath(for: item))
        }
        items.removeAll()
        persistMetadata()
    }

    /// The file an item stands for: the original for an alias, the stored copy otherwise.
    func fileURL(for item: ShelfItem) -> URL? {
        switch item.type {
        case .alias:
            guard let data = try? Data(contentsOf: storagePath(for: item)) else { return item.originalPath }
            return Self.resolveBookmark(data) ?? item.originalPath
        case .image, .file, .text, .link:
            return storagePath(for: item)
        }
    }

    /// Opens a file item with its default application.
    func open(_ item: ShelfItem) {
        guard let url = fileURL(for: item) else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        NSWorkspace.shared.open(url)
    }

    /// Shows the item's file selected in Finder.
    func revealInFinder(_ item: ShelfItem) {
        guard let url = fileURL(for: item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Puts the item on the general pasteboard: its text, its address, or its file.
    func copy(_ item: ShelfItem) async {
        let pasteboard = NSPasteboard.general
        switch item.type {
        case .text:
            guard let text = await text(of: item) else { return }
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
        case .link:
            guard let url = item.url else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])
            pasteboard.setString(url.absoluteString, forType: .string)
        case .image:
            pasteboard.clearContents()
            if let image = NSImage(contentsOf: storagePath(for: item)) {
                pasteboard.writeObjects([image])
            }
        case .file, .alias:
            guard let url = fileURL(for: item) else { return }
            pasteboard.clearContents()
            pasteboard.writeObjects([url as NSURL])
        }
    }

    /// The text a text item holds, read off the main thread.
    func text(of item: ShelfItem) async -> String? {
        guard item.type == .text else { return nil }
        return await Self.readPlist(at: storagePath(for: item))?[Constants.clippingTextKey] as? String
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

    // MARK: - Drag Out

    /// An item provider for dragging an item out: text as text, a link as its address, and a
    /// file under its display name rather than its storage name.
    func dragProvider(for item: ShelfItem) -> NSItemProvider {
        let path = storagePath(for: item)
        switch item.type {
        case .text:
            let provider = NSItemProvider()
            provider.registerDataRepresentation(forTypeIdentifier: UTType.utf8PlainText.identifier, visibility: .all) { completion in
                Task.detached {
                    let text = await Self.readPlist(at: path)?[Constants.clippingTextKey] as? String
                    completion(text?.data(using: .utf8), nil)
                }
                return nil
            }
            return provider
        case .link:
            guard let url = item.url else { return NSItemProvider() }
            let provider = NSItemProvider(object: url as NSURL)
            provider.suggestedName = item.displayName
            return provider
        case .alias:
            guard let url = fileURL(for: item), let provider = NSItemProvider(contentsOf: url) else { return NSItemProvider() }
            return provider
        case .image, .file:
            let provider = NSItemProvider()
            let name = item.displayName
            let type = UTType(filenameExtension: path.pathExtension) ?? .data
            provider.suggestedName = name
            provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { completion in
                DispatchQueue.global(qos: .userInitiated).async {
                    completion(Self.namedCopy(of: path, as: name), false, nil)
                }
                return nil
            }
            return provider
        }
    }

    /// A temporary copy of a stored file under its display name, so the receiver sees that name.
    private nonisolated static func namedCopy(of path: URL, as name: String) -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("RefraxShelf-\(UUID().uuidString)", isDirectory: true)
        let destination = directory.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"))
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try FileManager.default.copyItem(at: path, to: destination)
            return destination
        } catch {
            return path
        }
    }
}

/// What a drop onto the shelf carries, read from the drag pasteboard while the drop is in progress.
struct ShelfDrop: Sendable {
    var fileURLs: [URL] = []
    var image: (data: Data, fileExtension: String)?
    var link: URL?
    var linkTitle: String?
    var text: String?

    /// The pasteboard types the shelf keeps.
    static let acceptedTypes: [NSPasteboard.PasteboardType] = [
        .fileURL, .URL, .string, .png, .tiff,
        NSPasteboard.PasteboardType(UTType.image.identifier),
        NSPasteboard.PasteboardType(UTType.jpeg.identifier),
    ]

    fileprivate static let imageTypes: [(type: NSPasteboard.PasteboardType, fileExtension: String)] = [
        (NSPasteboard.PasteboardType(UTType.png.identifier), "png"),
        (NSPasteboard.PasteboardType(UTType.jpeg.identifier), "jpg"),
        (.tiff, "tiff"),
    ]

    init(pasteboard: NSPasteboard) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        self.fileURLs = urls.filter(\.isFileURL)
        self.image = Self.imageTypes.lazy.compactMap { entry in
            pasteboard.data(forType: entry.type).map { (data: $0, fileExtension: entry.fileExtension) }
        }.first
        let string = pasteboard.string(forType: .string)
        self.link = urls.first(where: \.isWebURL) ?? Self.webURL(in: string)
        self.linkTitle = pasteboard.string(forType: NSPasteboard.PasteboardType("public.url-name"))
        self.text = string.flatMap { $0.isEmpty ? nil : $0 }
    }

    /// Nothing the shelf can keep.
    var isEmpty: Bool {
        fileURLs.isEmpty && image == nil && link == nil && text == nil
    }

    /// What a drag carries, judged from its types and URLs without reading its data.
    struct Kind: Equatable {
        /// Something the shelf can keep.
        let accepts: Bool
        /// A web address and nothing more specific: a link to open rather than a file to keep.
        let isLinkOnly: Bool

        init(pasteboard: NSPasteboard) {
            let types = Set(pasteboard.types ?? [])
            let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
            let hasFiles = urls.contains(where: \.isFileURL)
            let hasImage = !types.isDisjoint(with: ShelfDrop.imageTypes.map(\.type) + [.png, NSPasteboard.PasteboardType(UTType.image.identifier)])
            let hasLink = urls.contains(where: \.isWebURL) || ShelfDrop.webURL(in: pasteboard.string(forType: .string)) != nil
            self.accepts = hasFiles || hasImage || hasLink || types.contains(.string)
            self.isLinkOnly = hasLink && !hasFiles && !hasImage
        }
    }

    /// A single-line http or https address, which the shelf keeps as a link rather than as text.
    fileprivate static func webURL(in text: String?) -> URL? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.contains("\n"),
              let url = URL(string: trimmed), url.isWebURL else { return nil }
        return url
    }
}
