import Foundation
import SwiftData

/// Exports Refrax bookmarks to Netscape HTML and JSON formats.
///
/// The exported HTML file is compatible with all major browsers and can be
/// imported into Chrome, Firefox, Safari, Edge, and other browsers. The JSON
/// format preserves Refrax-specific metadata like colors, tags, and favorites.
///
/// ## HTML Format
///
/// The exported HTML follows the Netscape bookmark file format:
///
/// ```html
/// <!DOCTYPE NETSCAPE-Bookmark-file-1>
/// <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
/// <TITLE>Bookmarks</TITLE>
/// <H1>Bookmarks</H1>
/// <DL><p>
///     <DT><H3 ADD_DATE="..." LAST_MODIFIED="...">Folder Name</H3>
///     <DL><p>
///         <DT><A HREF="..." ADD_DATE="...">Bookmark Title</A>
///     </DL><p>
/// </DL><p>
/// ```
///
/// ## JSON Format
///
/// Preserves full Refrax metadata:
/// ```json
/// {
///   "version": 1,
///   "exportedAt": "2025-01-13T...",
///   "source": "Refrax",
///   "folders": [...],
///   "rootBookmarks": [...]
/// }
/// ```
///
/// ## Usage
///
/// ```swift
/// let exporter = BookmarkExporter(modelContainer: container)
/// let htmlURL = try await exporter.exportToHTML()
/// let jsonURL = try await exporter.exportToJSON()
/// ```
///
/// - SeeAlso: [Netscape Bookmark File Format](https://docs.fileformat.com/web/html/#bookmark-file-format)
final class BookmarkExporter {
    private let modelContainer: ModelContainer

    /// Creates a bookmark exporter.
    ///
    /// - Parameter modelContainer: The SwiftData container to fetch bookmarks from.
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    /// Result of a bookmark export operation.
    struct ExportResult: Sendable {
        /// URL of the exported file.
        let url: URL
        /// Number of bookmarks exported.
        let count: Int
    }

    /// Exports all bookmarks to an HTML file.
    ///
    /// Fetches bookmark data on the main actor, then builds HTML and writes to disk
    /// on a background thread to avoid blocking the UI.
    ///
    /// - Returns: Export result with URL of the temporary HTML file and bookmark count.
    /// - Throws: Error if export fails.
    func exportToHTML() async throws -> ExportResult {
        let exportData = try collectExportData()
        let count = exportData.totalBookmarkCount
        let url = try await Task.detached(priority: .userInitiated) {
            try Self.buildAndWriteHTML(from: exportData)
        }.value
        return ExportResult(url: url, count: count)
    }

    /// Exports all bookmarks to a JSON file.
    ///
    /// Preserves Refrax-specific metadata including colors, tags, and favorites.
    ///
    /// - Returns: Export result with URL of the temporary JSON file and bookmark count.
    /// - Throws: Error if export fails.
    func exportToJSON() async throws -> ExportResult {
        let exportData = try collectExportData()
        let count = exportData.totalBookmarkCount
        // Encode JSON on MainActor where the types are isolated
        let jsonData = try Self.encodeJSON(from: exportData)
        let url = try await Task.detached(priority: .userInitiated) {
            try Self.writeJSONFile(jsonData)
        }.value
        return ExportResult(url: url, count: count)
    }

    /// Returns the total number of bookmarks that would be exported.
    ///
    /// - Returns: Count of all bookmarks across all folders.
    func countBookmarks() throws -> Int {
        let exportData = try collectExportData()
        return exportData.totalBookmarkCount
    }
}

// MARK: - Export Data Types

private extension BookmarkExporter {
    /// Sendable DTO for bookmark data.
    struct BookmarkData: Sendable {
        let id: UUID
        let title: String
        let url: URL
        let createdAt: Date
        let isFavorite: Bool
        let tags: [String]
    }

    /// Sendable DTO for folder data with nested structure.
    struct FolderData: Sendable {
        let id: UUID
        let name: String
        let color: String
        let position: Int
        let createdAt: Date
        let lastModified: Date
        let isFavorite: Bool
        let bookmarks: [BookmarkData]
        let childFolders: [FolderData]

        var totalBookmarkCount: Int {
            bookmarks.count + childFolders.reduce(0) { $0 + $1.totalBookmarkCount }
        }
    }

    /// Container for all export data.
    struct ExportData: Sendable {
        let rootBookmarks: [BookmarkData]
        let rootFolders: [FolderData]

        var totalBookmarkCount: Int {
            rootBookmarks.count + rootFolders.reduce(0) { $0 + $1.totalBookmarkCount }
        }
    }
}

// MARK: - Data Collection (Main Actor)

private extension BookmarkExporter {
    /// Collects bookmark data into Sendable DTOs.
    ///
    /// This runs on the main actor and fetches all bookmark data from SwiftData,
    /// converting it to DTOs that can be safely passed to a background thread.
    func collectExportData() throws -> ExportData {
        let context = modelContainer.mainContext

        let foldersDescriptor = FetchDescriptor<BookmarkFolder>(
            predicate: #Predicate { $0.parentFolderID == nil },
            sortBy: [SortDescriptor(\.position)],
        )
        let rootFolders = try context.fetch(foldersDescriptor)

        let bookmarksDescriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.folderID == nil },
            sortBy: [SortDescriptor(\.title)],
        )
        let rootBookmarks = try context.fetch(bookmarksDescriptor)

        return ExportData(
            rootBookmarks: rootBookmarks.map { convertBookmark($0) },
            rootFolders: rootFolders.map { convertFolder($0) },
        )
    }

    func convertBookmark(_ bookmark: Bookmark) -> BookmarkData {
        BookmarkData(
            id: bookmark.id,
            title: bookmark.title,
            url: bookmark.url,
            createdAt: bookmark.createdAt,
            isFavorite: bookmark.isFavorite,
            tags: bookmark.tags,
        )
    }

    func convertFolder(_ folder: BookmarkFolder) -> FolderData {
        FolderData(
            id: folder.id,
            name: folder.name,
            color: folder.color,
            position: folder.position,
            createdAt: folder.createdAt,
            lastModified: folder.lastModified,
            isFavorite: folder.isFavorite,
            bookmarks: folder.bookmarks.sorted(by: { $0.title < $1.title }).map { convertBookmark($0) },
            childFolders: folder.childFolders.sorted(by: { $0.position < $1.position }).map { convertFolder($0) },
        )
    }
}

// MARK: - HTML Generation (Background Thread)

private extension BookmarkExporter {
    /// Builds HTML and writes to a temporary file.
    ///
    /// This is a nonisolated static method that runs on a background thread with no access
    /// to the main actor or SwiftData models.
    nonisolated static func buildAndWriteHTML(from data: ExportData) throws -> URL {
        var html = buildHTMLHeader()

        for bookmark in data.rootBookmarks {
            html += formatBookmark(bookmark, indent: 1)
        }

        for folder in data.rootFolders {
            html += formatFolder(folder, indent: 1)
        }

        html += buildHTMLFooter()

        let dateString = Date().formatted(.iso8601.year().month().day())

        let fileName = "Refrax_Bookmarks_\(dateString).html"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        try html.write(to: tempURL, atomically: true, encoding: .utf8)

        return tempURL
    }

    nonisolated static func buildHTMLHeader() -> String {
        """
        <!DOCTYPE NETSCAPE-Bookmark-file-1>
        <!-- This is an automatically generated file.
             It will be read and overwritten.
             DO NOT EDIT! -->
        <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
        <TITLE>Refrax Bookmarks</TITLE>
        <H1>Refrax Bookmarks</H1>
        <DL><p>
        
        """
    }

    nonisolated static func buildHTMLFooter() -> String {
        "</DL><p>\n"
    }

    nonisolated static func formatBookmark(_ bookmark: BookmarkData, indent: Int) -> String {
        let indentation = String(repeating: "    ", count: indent)
        let timestamp = Int(bookmark.createdAt.timeIntervalSince1970)
        let escapedTitle = escapeHTML(bookmark.title)
        let escapedURL = escapeHTML(bookmark.url.absoluteString)

        return "\(indentation)<DT><A HREF=\"\(escapedURL)\" ADD_DATE=\"\(timestamp)\">\(escapedTitle)</A>\n"
    }

    nonisolated static func formatFolder(_ folder: FolderData, indent: Int) -> String {
        let indentation = String(repeating: "    ", count: indent)
        let addTimestamp = Int(folder.createdAt.timeIntervalSince1970)
        let modifiedTimestamp = Int(folder.lastModified.timeIntervalSince1970)
        let escapedName = escapeHTML(folder.name)

        // Mark favorite folders as personal toolbar (bookmarks bar) for browser compatibility
        let toolbarAttr = folder.isFavorite ? " PERSONAL_TOOLBAR_FOLDER=\"true\"" : ""

        // Use array join instead of += to avoid O(n²) string concatenation
        let header =
            "\(indentation)<DT><H3 ADD_DATE=\"\(addTimestamp)\" LAST_MODIFIED=\"\(modifiedTimestamp)\"\(toolbarAttr)>\(escapedName)</H3>\n"
        let opening = "\(indentation)<DL><p>\n"
        let bookmarks = folder.bookmarks.map { formatBookmark($0, indent: indent + 1) }.joined()
        let subfolders = folder.childFolders.map { formatFolder($0, indent: indent + 1) }.joined()
        let closing = "\(indentation)</DL><p>\n"

        return header + opening + bookmarks + subfolders + closing
    }

    nonisolated static func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}

// MARK: - JSON Generation

private extension BookmarkExporter {
    /// Encodes export data to JSON. Runs on MainActor where types are isolated.
    static func encodeJSON(from data: ExportData) throws -> Data {
        let exportData = BookmarkExportData(
            exportedAt: Date(),
            folders: data.rootFolders.map { jsonFolder(from: $0) },
            rootBookmarks: data.rootBookmarks.map { jsonBookmark(from: $0) },
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(exportData)
    }

    /// Writes JSON data to a temporary file. Runs on background thread.
    nonisolated static func writeJSONFile(_ jsonData: Data) throws -> URL {
        let dateString = Date().formatted(.iso8601.year().month().day())

        let fileName = "Refrax_Bookmarks_\(dateString).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)

        try jsonData.write(to: tempURL)

        return tempURL
    }

    static func jsonBookmark(from bookmark: BookmarkData) -> ExportedBookmark {
        ExportedBookmark(
            id: bookmark.id,
            url: bookmark.url,
            title: bookmark.title,
            dateAdded: bookmark.createdAt,
            isFavorite: bookmark.isFavorite,
            tags: bookmark.tags,
        )
    }

    static func jsonFolder(from folder: FolderData) -> ExportedFolder {
        ExportedFolder(
            id: folder.id,
            name: folder.name,
            color: folder.color,
            isFavorite: folder.isFavorite,
            createdAt: folder.createdAt,
            children: buildJSONChildren(from: folder),
        )
    }

    static func buildJSONChildren(from folder: FolderData) -> [ExportedItem] {
        var children: [ExportedItem] = []

        for bookmark in folder.bookmarks {
            children.append(.bookmark(jsonBookmark(from: bookmark)))
        }

        for subfolder in folder.childFolders {
            children.append(.folder(jsonFolder(from: subfolder)))
        }

        return children
    }
}

// MARK: - JSON Export Models

/// Root structure for JSON bookmark export.
struct BookmarkExportData: Codable, Sendable {
    /// Export format version for future compatibility.
    var version: Int = 1

    /// When the export was created.
    let exportedAt: Date

    /// Source application identifier.
    var source: String = "Refrax"

    /// Top-level folders with nested hierarchy.
    let folders: [ExportedFolder]

    /// Bookmarks not in any folder.
    let rootBookmarks: [ExportedBookmark]
}

/// Exported folder with nested children.
struct ExportedFolder: Codable, Sendable {
    let id: UUID
    let name: String
    let color: String?
    let isFavorite: Bool
    let createdAt: Date
    let children: [ExportedItem]
}

/// Union type for folder children (bookmarks or nested folders).
enum ExportedItem: Codable, Sendable {
    case folder(ExportedFolder)
    case bookmark(ExportedBookmark)

    private enum CodingKeys: String, CodingKey {
        case type
        case data
    }

    private enum ItemType: String, Codable {
        case folder
        case bookmark
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .folder(folder):
            try container.encode(ItemType.folder, forKey: .type)
            try container.encode(folder, forKey: .data)
        case let .bookmark(bookmark):
            try container.encode(ItemType.bookmark, forKey: .type)
            try container.encode(bookmark, forKey: .data)
        }
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)
        switch type {
        case .folder:
            self = try .folder(container.decode(ExportedFolder.self, forKey: .data))
        case .bookmark:
            self = try .bookmark(container.decode(ExportedBookmark.self, forKey: .data))
        }
    }
}

/// Exported bookmark with full metadata.
struct ExportedBookmark: Codable, Sendable {
    let id: UUID
    let url: URL
    let title: String
    let dateAdded: Date
    let isFavorite: Bool
    let tags: [String]
}
