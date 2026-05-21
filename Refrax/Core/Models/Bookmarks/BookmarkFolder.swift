import Foundation
import SwiftData
import SwiftUI

/// A hierarchical folder for organizing bookmarks.
///
/// `BookmarkFolder` provides Chrome-style hierarchical organization with up to 3 levels
/// of nesting. Folders can contain bookmarks and other folders, and can themselves be
/// favorited to appear in the sidebar as navigable tiles.
///
/// ## Hierarchy Rules
///
/// - **Maximum depth**: 3 levels (root → folder → subfolder)
/// - **Validation**: Creating deeper nesting throws an error
/// - **Depth calculation**: Computed by traversing parent chain
///
/// ## Favorites Display
///
/// Like bookmarks, folders can be favorited and displayed as tiles in the sidebar.
/// Clicking a folder tile opens a menu showing contained bookmarks and subfolders.
/// Subfolders in the menu are also expandable via nested menus.
///
/// ## Visual Styling
///
/// Folders have customizable colors that:
/// - Tint the folder tile background
/// - Apply `.tint()` to the opened menu for visual consistency
/// - Are inherited by contained bookmarks in list views
///
/// ## Usage
///
/// ```swift
/// let workFolder = BookmarkFolder(name: "Work", color: "#007AFF")
/// let projectsFolder = BookmarkFolder(name: "Projects", color: "#FF9500", parent: workFolder)
/// ```
@Model
final class BookmarkFolder {
    // MARK: - Identity

    /// Unique identifier for the folder
    @Attribute(.unique, .preserveValueOnDeletion)
    var id: UUID
    
    /// When the folder was created
    var createdAt: Date
    
    /// Last time the folder properties were modified
    var lastModified: Date
    
    // MARK: - Content
    
    /// Display name of the folder
    var name: String
    
    /// Custom icon (SF Symbol, emoji, or image)
    ///
    /// Stored as JSON string. Use ``customIcon`` computed property to access.
    var customIconJSON: String?
    
    /// Hex color for folder theming (e.g., "#007AFF")
    var color: String
    
    // MARK: - Hierarchy
    
    /// ID of parent folder (nil = root level)
    var parentFolderID: UUID?
    
    /// Position within parent folder
    ///
    /// Used for ordering folders in lists and menus.
    var position: Int
    
    // MARK: - Favorites Display
    
    /// Whether this folder appears in the sidebar favorites grid
    var isFavorite: Bool
    
    /// Position in favorites grid (encoded as row * 1000 + column)
    ///
    /// Use ``favoritePosition`` computed property for 2D coordinates.
    var favoritePositionValue: Int
    
    // MARK: - Relationships

    /// Bookmarks contained in this folder.
    ///
    /// Cascade delete: bookmarks are deleted when the folder is deleted.
    @Relationship(deleteRule: .cascade)
    var bookmarks: [Bookmark]

    /// Subfolders contained in this folder.
    ///
    /// Cascade delete: child folders (and their contents) are deleted when
    /// the parent folder is deleted.
    @Relationship(deleteRule: .cascade, inverse: \BookmarkFolder.parentFolder)
    var childFolders: [BookmarkFolder]
    
    var parentFolder: BookmarkFolder?
    
    // MARK: - Initialization
    
    /// Create a new bookmark folder.
    ///
    /// - Parameters:
    ///   - name: Display name for the folder
    ///   - color: Hex color string (e.g., "#007AFF")
    ///   - iconName: Optional custom icon (SF Symbol or emoji)
    ///   - parent: Optional parent folder (nil = root level)
    ///   - position: Position within parent (default: 0)
    ///   - isFavorite: Whether to show in sidebar favorites (default: false)
    ///   - favoritePosition: Grid position if favorited (default: 0,0)
    init(
        name: String,
        color: String = "#808080",
        iconName: String? = nil,
        parent: BookmarkFolder? = nil,
        position: Int = 0,
        isFavorite: Bool = false,
        favoritePosition: FavoritePosition = FavoritePosition(row: 0, col: 0),
    ) {
        self.id = UUID()
        self.createdAt = Date()
        self.lastModified = Date()
        
        self.name = name
        self.color = color
        self.position = position
        
        self.parentFolder = parent
        self.parentFolderID = parent?.id
        
        self.isFavorite = isFavorite
        self.favoritePositionValue = favoritePosition.rawValue
        
        self.bookmarks = []
        self.childFolders = []
        
        // Set default icon based on name
        if let iconName {
            if BookmarkIcon.isValidEmoji(iconName) {
                self.customIcon = .emoji(iconName)
            } else if BookmarkIcon.isValidSFSymbol(iconName) {
                self.customIcon = .sfSymbol(iconName)
            }
        }
    }
    
    // MARK: - Computed Properties
    
    /// Custom icon (decoded from JSON)
    var customIcon: BookmarkIcon? {
        get {
            BookmarkIcon.from(jsonString: customIconJSON)
        }
        set {
            customIconJSON = newValue?.jsonString
            lastModified = Date()
        }
    }
    
    /// 2D position in favorites grid
    var favoritePosition: FavoritePosition {
        get {
            favoritePositionValue.asFavoritePosition
        }
        set {
            favoritePositionValue = newValue.rawValue
            lastModified = Date()
        }
    }
    
    /// Nesting depth of this folder (0 = root, 1 = subfolder, 2 = nested subfolder)
    var depth: Int {
        var d = 0
        var current = parentFolder
        while current != nil {
            d += 1
            current = current?.parentFolder
        }
        return d
    }
    
    /// Total number of items in this folder (bookmarks + subfolders)
    var itemCount: Int {
        bookmarks.count + childFolders.count
    }
    
    /// Whether this is a root-level folder
    var isRoot: Bool {
        parentFolderID == nil
    }
    
    /// SwiftUI Color resolved from stored color string.
    @MainActor
    var swiftUIColor: Color {
        Color.resolveStoredColor(color)
    }
    
    // MARK: - Modification Methods
    
    /// Rename the folder
    ///
    /// - Parameter newName: New display name
    func rename(_ newName: String) {
        name = newName
        lastModified = Date()
    }
    
    /// Update the folder's color
    ///
    /// - Parameter newColor: New hex color string
    func updateColor(_ newColor: String) {
        color = newColor
        lastModified = Date()
    }
    
    /// Add a bookmark to this folder
    ///
    /// - Parameter bookmark: Bookmark to add
    /// - Note: Updates bookmark's folderID automatically
    func addBookmark(_ bookmark: Bookmark) {
        guard !bookmarks.contains(where: { $0.id == bookmark.id }) else { return }
        bookmarks.append(bookmark)
        bookmark.folderID = id
        bookmark.folder = self
        lastModified = Date()
    }
    
    /// Remove a bookmark from this folder
    ///
    /// - Parameter bookmark: Bookmark to remove
    /// - Note: Sets bookmark's folderID to nil
    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        bookmark.folderID = nil
        bookmark.folder = nil
        lastModified = Date()
    }
    
    /// Add a subfolder to this folder
    ///
    /// - Parameter folder: Subfolder to add
    /// - Throws: Error if nesting would exceed maximum depth
    func addSubfolder(_ folder: BookmarkFolder) throws {
        // Validate maximum depth
        let newDepth = depth + 1
        guard newDepth < 3 else {
            throw BookmarkError.maxDepthExceeded
        }
        
        guard !childFolders.contains(where: { $0.id == folder.id }) else { return }
        
        childFolders.append(folder)
        folder.parentFolderID = id
        folder.parentFolder = self
        lastModified = Date()
    }
    
    /// Remove a subfolder from this folder
    ///
    /// - Parameter folder: Subfolder to remove
    func removeSubfolder(_ folder: BookmarkFolder) {
        childFolders.removeAll { $0.id == folder.id }
        folder.parentFolderID = nil
        folder.parentFolder = nil
        lastModified = Date()
    }
}

// MARK: - Errors

enum BookmarkError: Error, LocalizedError {
    case maxDepthExceeded
    case folderNotFound
    case circularReference
    
    var errorDescription: String? {
        switch self {
        case .maxDepthExceeded:
            "Cannot nest folders more than 3 levels deep"
        case .folderNotFound:
            "The specified folder could not be found"
        case .circularReference:
            "Cannot move folder into itself or its descendants"
        }
    }
}
