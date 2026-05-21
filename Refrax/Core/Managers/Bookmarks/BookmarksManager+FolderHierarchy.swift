import Foundation

// MARK: - Folder Hierarchy Helpers

extension BookmarksManager {
    /// Check if a folder is a descendant of another folder.
    ///
    /// - Parameters:
    ///   - folder: Potential descendant
    ///   - ancestor: Potential ancestor
    /// - Returns: True if folder is nested under ancestor
    func isDescendant(_ folder: BookmarkFolder, of ancestor: BookmarkFolder) -> Bool {
        var current = folder.parentFolder
        while let parent = current {
            if parent.id == ancestor.id {
                return true
            }
            current = parent.parentFolder
        }
        return false
    }

    /// Calculate maximum depth of a folder's subtree.
    ///
    /// - Parameter folder: Root folder of subtree
    /// - Returns: Maximum nesting depth within this folder
    func calculateSubtreeDepth(_ folder: BookmarkFolder) -> Int {
        guard !folder.childFolders.isEmpty else { return 0 }

        let childDepths = folder.childFolders.map { calculateSubtreeDepth($0) }
        return (childDepths.max() ?? 0) + 1
    }
}
