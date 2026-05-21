import Foundation
import SwiftData

// MARK: - Folder Operations

extension BookmarksManager {
    /// Create a new bookmark folder.
    ///
    /// - Parameters:
    ///   - name: Display name
    ///   - color: Hex color string
    ///   - iconName: Optional SF Symbol or emoji
    ///   - parent: Optional parent folder
    /// - Returns: The created folder
    /// - Throws: `BookmarkError.maxDepthExceeded` if parent is already at max depth
    @discardableResult
    func createFolder(
        name: String,
        color: String = "#808080",
        iconName: String? = nil,
        parent: BookmarkFolder? = nil,
    ) throws -> BookmarkFolder {
        // Validate max depth
        if let parent, parent.depth >= 2 {
            throw BookmarkError.maxDepthExceeded
        }

        // Calculate next position
        let position: Int
        if let parent {
            position = parent.childFolders.map(\.position).max().map { $0 + 1 } ?? 0
        } else {
            // Root level position
            let descriptor = FetchDescriptor<BookmarkFolder>(
                predicate: #Predicate { $0.parentFolderID == nil },
            )
            let rootFolders = (try? _modelContext.fetch(descriptor)) ?? []
            position = rootFolders.map(\.position).max().map { $0 + 1 } ?? 0
        }

        let folder = BookmarkFolder(
            name: name,
            color: color,
            iconName: iconName,
            parent: parent,
            position: position,
        )

        // Add to parent if specified
        if let parent {
            try parent.addSubfolder(folder)
        }

        // Insert into SwiftData
        _modelContext.insert(folder)
        scheduleSave()

        return folder
    }

    /// Delete a folder and optionally its contents.
    ///
    /// - Parameters:
    ///   - folder: Folder to delete
    ///   - deleteContents: If true, deletes all bookmarks and subfolders. If false, orphans them.
    func deleteFolder(_ folder: BookmarkFolder, deleteContents: Bool = false) {
        if deleteContents {
            // Delete all bookmarks
            for bookmark in folder.bookmarks {
                deleteBookmark(bookmark)
            }

            // Delete all subfolders recursively
            for subfolder in folder.childFolders {
                deleteFolder(subfolder, deleteContents: true)
            }
        } else {
            // Orphan bookmarks (move to root)
            for bookmark in folder.bookmarks {
                bookmark.folderID = nil
                bookmark.folder = nil
            }

            // Orphan subfolders (move to root)
            for subfolder in folder.childFolders {
                subfolder.parentFolderID = nil
                subfolder.parentFolder = nil
            }
        }

        // Remove from parent
        folder.parentFolder?.removeSubfolder(folder)

        // Delete from SwiftData
        _modelContext.delete(folder)
        scheduleSave()

        // Refresh favorites if was favorited
        if folder.isFavorite {
            scheduleRefreshFavoritesCache()
        }

        Logger.info("Folder deleted: \(folder.name)", category: Logger.data)
    }

    /// Move a bookmark to a different folder.
    ///
    /// - Parameters:
    ///   - bookmark: Bookmark to move
    ///   - folder: Target folder (nil = move to root)
    func moveBookmark(_ bookmark: Bookmark, to folder: BookmarkFolder?) {
        // Remove from current folder
        bookmark.folder?.removeBookmark(bookmark)

        // Add to new folder
        folder?.addBookmark(bookmark)

        scheduleSave()
    }

    /// Move a bookmark to a different folder by ID (for drag-and-drop).
    ///
    /// - Parameters:
    ///   - bookmarkID: ID of bookmark to move
    ///   - folder: Target folder (nil = move to root)
    func moveBookmark(_ bookmarkID: UUID, to folder: BookmarkFolder?) {
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.id == bookmarkID },
        )
        guard let bookmark = try? _modelContext.fetch(descriptor).first else {
            Logger.warning("Bookmark not found for move: \(bookmarkID)", category: Logger.data)
            return
        }
        moveBookmark(bookmark, to: folder)
    }

    /// Move multiple bookmarks to a folder by IDs (for batch drag-and-drop).
    ///
    /// - Parameters:
    ///   - bookmarkIDs: IDs of bookmarks to move
    ///   - folder: Target folder (nil = move to root)
    func moveBookmarks(_ bookmarkIDs: [UUID], to folder: BookmarkFolder?) {
        for id in bookmarkIDs {
            moveBookmark(id, to: folder)
        }
    }

    /// Move a folder into another folder.
    ///
    /// - Parameters:
    ///   - folder: Folder to move
    ///   - parent: Target parent folder (nil = move to root)
    /// - Throws: Error if move would exceed max depth or create circular reference
    func moveFolder(_ folder: BookmarkFolder, into parent: BookmarkFolder?) throws {
        // Validate not moving into self
        if let parent, parent.id == folder.id {
            throw BookmarkError.circularReference
        }

        // Validate not moving into descendant
        if let parent, isDescendant(parent, of: folder) {
            throw BookmarkError.circularReference
        }

        // Validate max depth
        let newDepth = (parent?.depth ?? -1) + 1
        let folderSubtreeDepth = calculateSubtreeDepth(folder)
        if newDepth + folderSubtreeDepth > 2 {
            throw BookmarkError.maxDepthExceeded
        }

        // Remove from current parent
        folder.parentFolder?.removeSubfolder(folder)

        // Add to new parent
        if let parent {
            try parent.addSubfolder(folder)
        } else {
            folder.parentFolderID = nil
            folder.parentFolder = nil
        }

        scheduleSave()

        Logger.info("Folder moved: \(folder.name)", category: Logger.data)
    }
}
