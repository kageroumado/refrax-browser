import Foundation
import UniformTypeIdentifiers

/// A single item kept on the File Island's shelf.
///
/// Items are dropped onto the File Island and stored in Application Support.
/// They can be dragged back out to other applications.
struct ShelfItem: Identifiable, Codable, Hashable {
    let id: UUID
    let type: ShelfItemType
    let fileName: String
    let displayName: String
    /// Original path for aliases (files >= 10MB stored as bookmarks)
    let originalPath: URL?
    /// The address a link item opens.
    var url: URL?
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
    /// A web address stored as a .webloc file
    case link

    /// System icon name for this item type.
    var systemImage: String {
        switch self {
        case .text: "text.alignleft"
        case .image: "photo"
        case .file: "doc"
        case .alias: "doc"
        case .link: "link"
        }
    }

    /// What clicking the item does, for its tooltip and accessibility hint.
    var primaryActionTitle: String {
        switch self {
        case .text: "Copy"
        case .link: "Open in a new tab"
        case .image, .file, .alias: "Open"
        }
    }
}
