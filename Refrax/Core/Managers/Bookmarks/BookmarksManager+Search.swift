import Foundation
import SwiftData

// MARK: - Search & Filter

extension BookmarksManager {
    /// Find a bookmark by its ID.
    ///
    /// - Parameter id: The bookmark's UUID.
    /// - Returns: The bookmark if found, nil otherwise.
    func bookmark(for id: UUID) -> Bookmark? {
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.id == id },
        )

        return try? _modelContext.fetch(descriptor).first
    }

    /// Find a bookmark folder by its ID.
    ///
    /// - Parameter id: The folder's UUID.
    /// - Returns: The folder if found, nil otherwise.
    func folder(for id: UUID) -> BookmarkFolder? {
        let descriptor = FetchDescriptor<BookmarkFolder>(
            predicate: #Predicate { $0.id == id },
        )

        return try? _modelContext.fetch(descriptor).first
    }

    /// Get all bookmarks, optionally limited.
    ///
    /// - Parameter limit: Maximum number of bookmarks to return (default 1000).
    /// - Returns: Array of bookmarks sorted by last visited date.
    func allBookmarks(limit: Int = 1_000) -> [Bookmark] {
        var descriptor = FetchDescriptor<Bookmark>(
            sortBy: [SortDescriptor(\.lastVisited, order: .reverse)],
        )
        descriptor.fetchLimit = limit

        return (try? _modelContext.fetch(descriptor)) ?? []
    }

    /// Search bookmarks by query string.
    ///
    /// Uses the indexed `searchableText` field for efficient database-level
    /// filtering instead of loading all bookmarks into memory.
    ///
    /// - Parameters:
    ///   - query: Search query
    ///   - includeArchived: Whether to include archived bookmarks (future feature)
    ///   - limit: Maximum number of results
    /// - Returns: Array of matching bookmarks, sorted by last visited date
    func search(
        query: String,
        includeArchived _: Bool = false,
        limit: Int = 50,
    ) -> [Bookmark] {
        guard !query.isEmpty else { return [] }

        let lowercasedQuery = query.lowercased()

        var descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { bookmark in
                bookmark.searchableText.contains(lowercasedQuery)
            },
            sortBy: [SortDescriptor(\.lastVisited, order: .reverse)],
        )
        descriptor.fetchLimit = limit

        return (try? _modelContext.fetch(descriptor)) ?? []
    }

    /// Get bookmarks in a specific folder.
    ///
    /// - Parameter folder: Folder to get bookmarks from (nil = root level)
    /// - Returns: Array of bookmarks, sorted by title
    func bookmarks(in folder: BookmarkFolder?) -> [Bookmark] {
        let folderID = folder?.id

        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.folderID == folderID },
            sortBy: [SortDescriptor(\.title)],
        )

        return (try? _modelContext.fetch(descriptor)) ?? []
    }

    /// Get bookmarks with a specific tag.
    ///
    /// - Parameter tag: Tag to filter by
    /// - Returns: Array of tagged bookmarks
    func bookmarks(tagged tag: String) -> [Bookmark] {
        let descriptor = FetchDescriptor<Bookmark>()

        guard let allBookmarks = try? _modelContext.fetch(descriptor) else {
            return []
        }

        let lowercasedTag = tag.lowercased()
        return allBookmarks.filter { bookmark in
            bookmark.tags.contains(where: { $0.lowercased() == lowercasedTag })
        }
    }

    /// Get bookmarks assigned to a specific space.
    ///
    /// - Parameter spaceID: Space ID to filter by
    /// - Returns: Array of space bookmarks
    func bookmarks(for spaceID: UUID) -> [Bookmark] {
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.spaceID == spaceID },
            sortBy: [SortDescriptor(\.title)],
        )

        return (try? _modelContext.fetch(descriptor)) ?? []
    }

    /// Get all root-level folders.
    ///
    /// - Returns: Array of folders with no parent, sorted by position
    func rootFolders() -> [BookmarkFolder] {
        let descriptor = FetchDescriptor<BookmarkFolder>(
            predicate: #Predicate { $0.parentFolderID == nil },
            sortBy: [SortDescriptor(\.position)],
        )

        return (try? _modelContext.fetch(descriptor)) ?? []
    }

    /// Get subfolders of a specific folder.
    ///
    /// - Parameter folder: Parent folder
    /// - Returns: Array of child folders, sorted by position
    func subfolders(of folder: BookmarkFolder) -> [BookmarkFolder] {
        let parentID = folder.id

        let descriptor = FetchDescriptor<BookmarkFolder>(
            predicate: #Predicate { $0.parentFolderID == parentID },
            sortBy: [SortDescriptor(\.position)],
        )

        return (try? _modelContext.fetch(descriptor)) ?? []
    }
}
