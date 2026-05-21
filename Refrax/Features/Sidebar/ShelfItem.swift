import Foundation
import UniformTypeIdentifiers

/// A single item stored in the global shelf.
///
/// Shelf items are dragged into the sidebar footer and stored in Application Support.
/// They can be dragged back out to other applications.
struct ShelfItem: Identifiable, Codable, Hashable {
    let id: UUID
    let type: ShelfItemType
    let fileName: String
    let displayName: String
    /// Original path for aliases (files >= 10MB stored as bookmarks)
    let originalPath: URL?
    let createdAt: Date
    let fileSize: Int64

    /// File extension for display purposes.
    var fileExtension: String {
        URL(fileURLWithPath: fileName).pathExtension.lowercased()
    }

    /// Whether this item is an alias to a file stored elsewhere.
    var isAlias: Bool {
        type == .alias
    }
}

// MARK: - ShelfItemType

/// The type of content stored in a shelf item.
enum ShelfItemType: String, Codable, Hashable {
    /// Plain text stored as .textClipping (Apple's native plist format)
    case text
    /// Image file (png, jpg, gif, etc.)
    case image
    /// Other file types (copied to shelf directory)
    case file
    /// Bookmark/alias to a large file (>= 10MB)
    case alias

    /// System icon name for this item type.
    var systemImage: String {
        switch self {
        case .text: "doc.text"
        case .image: "photo"
        case .file: "doc"
        case .alias: "link"
        }
    }

    /// UTType for this item when dragging out.
    var contentType: UTType {
        switch self {
        case .text: .plainText
        case .image: .image
        case .file: .data
        case .alias: .fileURL
        }
    }
}
