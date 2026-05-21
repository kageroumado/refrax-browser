import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for BookmarksManager operations.
    @Tag static var bookmarksManager: Self
}

// MARK: - BookmarksManager Bookmark CRUD Tests

@Suite("BookmarksManager Bookmark CRUD", .tags(.bookmarksManager), .serialized)
@MainActor
struct BookmarksManagerBookmarkTests {
    @Test("Create basic bookmark")
    func createBasicBookmark() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Example",
            isFavorite: false,
        )

        #expect(bookmark.title == "Example")
        #expect(bookmark.url.absoluteString == "https://example.com")
        #expect(!bookmark.isFavorite)
    }

    @Test("Create bookmark with folder")
    func createBookmarkWithFolder() throws {
        let env = try TabManagerTestEnvironment()

        let folder = try env.bookmarksManager.createFolder(name: "Work")
        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://work.example.com")!,
            title: "Work Site",
            folder: folder,
        )

        #expect(bookmark.folder?.id == folder.id)
        #expect(folder.bookmarks.contains(where: { $0.id == bookmark.id }))
    }

    @Test("Create bookmark with tags")
    func createBookmarkWithTags() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Tagged",
            tags: ["work", "important"],
        )

        #expect(bookmark.tags.count == 2)
        #expect(bookmark.tags.contains("work"))
        #expect(bookmark.tags.contains("important"))
    }

    @Test("Create bookmark with space ID")
    func createBookmarkWithSpaceID() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Space Bookmark",
            spaceID: space.id,
        )

        #expect(bookmark.spaceID == space.id)
    }

    @Test("Delete bookmark")
    func deleteBookmark() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "To Delete",
        )
        let bookmarkID = bookmark.id

        env.bookmarksManager.deleteBookmark(bookmark)

        // Bookmark should be deleted from context
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.id == bookmarkID },
        )
        let found = try? env.modelContext.fetch(descriptor)
        #expect(found?.isEmpty ?? true)
    }

    @Test("Update bookmark title")
    func updateBookmarkTitle() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Original",
        )

        env.bookmarksManager.updateBookmark(bookmark, title: "Updated Title")

        #expect(bookmark.title == "Updated Title")
    }

    @Test("Update bookmark URL")
    func updateBookmarkURL() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://old.example.com")!,
            title: "Site",
        )

        let newURL = URL(string: "https://new.example.com")!
        env.bookmarksManager.updateBookmark(bookmark, url: newURL)

        #expect(bookmark.url == newURL)
    }

    @Test("Update bookmark tags")
    func updateBookmarkTags() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Tagged",
            tags: ["old"],
        )

        env.bookmarksManager.updateBookmark(bookmark, tags: ["new", "updated"])

        #expect(bookmark.tags.count == 2)
        #expect(bookmark.tags.contains("new"))
        #expect(!bookmark.tags.contains("old"))
    }
}

// MARK: - BookmarksManager Folder Tests

@Suite("BookmarksManager Folder", .tags(.bookmarksManager), .serialized)
@MainActor
struct BookmarksManagerFolderTests {
    @Test("Create root folder")
    func createRootFolder() throws {
        let env = try TabManagerTestEnvironment()

        let folder = try env.bookmarksManager.createFolder(name: "Root Folder")

        #expect(folder.name == "Root Folder")
        #expect(folder.parentFolder == nil)
        #expect(folder.depth == 0)
    }

    @Test("Create nested folder")
    func createNestedFolder() throws {
        let env = try TabManagerTestEnvironment()

        let parent = try env.bookmarksManager.createFolder(name: "Parent")
        let child = try env.bookmarksManager.createFolder(name: "Child", parent: parent)

        #expect(child.parentFolder?.id == parent.id)
        #expect(child.depth == 1)
        #expect(parent.childFolders.contains(where: { $0.id == child.id }))
    }

    @Test("Create deeply nested folder")
    func createDeeplyNestedFolder() throws {
        let env = try TabManagerTestEnvironment()

        let level0 = try env.bookmarksManager.createFolder(name: "Level 0")
        let level1 = try env.bookmarksManager.createFolder(name: "Level 1", parent: level0)
        let level2 = try env.bookmarksManager.createFolder(name: "Level 2", parent: level1)

        #expect(level0.depth == 0)
        #expect(level1.depth == 1)
        #expect(level2.depth == 2)
    }

    @Test("Max depth enforcement")
    func maxDepthEnforcement() throws {
        let env = try TabManagerTestEnvironment()

        let level0 = try env.bookmarksManager.createFolder(name: "Level 0")
        let level1 = try env.bookmarksManager.createFolder(name: "Level 1", parent: level0)
        let level2 = try env.bookmarksManager.createFolder(name: "Level 2", parent: level1)

        #expect(throws: BookmarkError.maxDepthExceeded) {
            _ = try env.bookmarksManager.createFolder(name: "Level 3", parent: level2)
        }
    }

    @Test("Delete folder with contents")
    func deleteFolderWithContents() throws {
        let env = try TabManagerTestEnvironment()

        let folder = try env.bookmarksManager.createFolder(name: "To Delete")
        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "In Folder",
            folder: folder,
        )
        let bookmarkID = bookmark.id

        env.bookmarksManager.deleteFolder(folder, deleteContents: true)

        // Bookmark should also be deleted
        let descriptor = FetchDescriptor<Bookmark>(
            predicate: #Predicate { $0.id == bookmarkID },
        )
        let found = try? env.modelContext.fetch(descriptor)
        #expect(found?.isEmpty ?? true)
    }

    @Test("Delete folder orphans contents when deleteContents false")
    func deleteFolderOrphansContents() throws {
        let env = try TabManagerTestEnvironment()

        let folder = try env.bookmarksManager.createFolder(name: "To Delete")
        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "In Folder",
            folder: folder,
        )

        env.bookmarksManager.deleteFolder(folder, deleteContents: false)

        // Bookmark should be orphaned (no folder)
        #expect(bookmark.folder == nil)
        #expect(bookmark.folderID == nil)
    }

    @Test("Move folder prevents circular reference")
    func moveFolderCircularReference() throws {
        let env = try TabManagerTestEnvironment()

        let parent = try env.bookmarksManager.createFolder(name: "Parent")
        let child = try env.bookmarksManager.createFolder(name: "Child", parent: parent)

        #expect(throws: BookmarkError.circularReference) {
            try env.bookmarksManager.moveFolder(parent, into: child)
        }
    }

    @Test("Move folder prevents self-reference")
    func moveFolderSelfReference() throws {
        let env = try TabManagerTestEnvironment()

        let folder = try env.bookmarksManager.createFolder(name: "Folder")

        #expect(throws: BookmarkError.circularReference) {
            try env.bookmarksManager.moveFolder(folder, into: folder)
        }
    }

    @Test("Move folder respects max depth")
    func moveFolderMaxDepth() throws {
        let env = try TabManagerTestEnvironment()

        let level0 = try env.bookmarksManager.createFolder(name: "Level 0")
        let level1 = try env.bookmarksManager.createFolder(name: "Level 1", parent: level0)

        // Create another branch at depth 1
        let branch1 = try env.bookmarksManager.createFolder(name: "Branch 1")
        let branch1Child = try env.bookmarksManager.createFolder(name: "Branch 1 Child", parent: branch1)

        // Moving branch with child under level1 would exceed depth
        #expect(throws: BookmarkError.maxDepthExceeded) {
            try env.bookmarksManager.moveFolder(branch1, into: level1)
        }

        // But moving branch1Child alone should work
        try env.bookmarksManager.moveFolder(branch1Child, into: level1)
        #expect(branch1Child.parentFolder?.id == level1.id)
    }
}

// MARK: - BookmarksManager Favorites Tests

@Suite("BookmarksManager Favorites", .tags(.bookmarksManager), .serialized)
@MainActor
struct BookmarksManagerFavoritesTests {
    @Test("Add to favorites")
    func addToFavorites() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Example",
            isFavorite: false,
        )

        env.bookmarksManager.addToFavorites(bookmark, mode: .shortcut)

        #expect(bookmark.isFavorite)
        #expect(bookmark.favoriteMode == .shortcut)
    }

    @Test("Add to favorites is idempotent")
    func addToFavoritesIdempotent() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Example",
            isFavorite: true,
            favoriteMode: .shortcut,
        )

        let originalPosition = bookmark.favoritePosition

        // Adding again should be no-op
        env.bookmarksManager.addToFavorites(bookmark, mode: .liveFavorite)

        #expect(bookmark.favoriteMode == .shortcut, "Mode should not change")
        #expect(bookmark.favoritePosition == originalPosition)
    }

    @Test("Remove from favorites")
    func removeFromFavorites() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Example",
            isFavorite: true,
            favoriteMode: .shortcut,
        )

        env.bookmarksManager.removeFromFavorites(bookmark)

        #expect(!bookmark.isFavorite)
    }

    @Test("Remove from favorites is idempotent")
    func removeFromFavoritesIdempotent() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Example",
            isFavorite: false,
        )

        // Removing when not favorited should be no-op
        env.bookmarksManager.removeFromFavorites(bookmark)

        #expect(!bookmark.isFavorite)
    }

    @Test("Change favorite mode shortcut to live favorite")
    func changeFavoriteModeToLive() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Example",
            isFavorite: true,
            favoriteMode: .shortcut,
        )

        env.bookmarksManager.changeFavoriteMode(bookmark, to: .liveFavorite)

        #expect(bookmark.favoriteMode == .liveFavorite)
    }

    @Test("Change favorite mode live favorite to shortcut")
    func changeFavoriteModeToShortcut() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Example",
            isFavorite: true,
            favoriteMode: .liveFavorite,
        )

        env.bookmarksManager.changeFavoriteMode(bookmark, to: .shortcut)

        #expect(bookmark.favoriteMode == .shortcut)
    }

    @Test("Change favorite mode is no-op for same mode")
    func changeFavoriteModeSameMode() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Example",
            isFavorite: true,
            favoriteMode: .shortcut,
        )

        env.bookmarksManager.changeFavoriteMode(bookmark, to: .shortcut)

        #expect(bookmark.favoriteMode == .shortcut)
    }

    @Test("Add folder to favorites")
    func addFolderToFavorites() throws {
        let env = try TabManagerTestEnvironment()

        let folder = try env.bookmarksManager.createFolder(name: "Favorite Folder")
        #expect(!folder.isFavorite)

        env.bookmarksManager.addFolderToFavorites(folder)

        #expect(folder.isFavorite)
    }

    @Test("Remove folder from favorites")
    func removeFolderFromFavorites() throws {
        let env = try TabManagerTestEnvironment()

        let folder = try env.bookmarksManager.createFolder(name: "Favorite Folder")
        env.bookmarksManager.addFolderToFavorites(folder)

        env.bookmarksManager.removeFolderFromFavorites(folder)

        #expect(!folder.isFavorite)
    }
}

// MARK: - BookmarksManager Favorites Grid Tests

@Suite("BookmarksManager Favorites Grid", .tags(.bookmarksManager), .serialized)
@MainActor
struct BookmarksManagerFavoritesGridTests {
    @Test("Calculate next favorite position for empty grid")
    func nextPositionEmpty() throws {
        let env = try TabManagerTestEnvironment()

        let position = env.bookmarksManager.calculateNextFavoritePosition()

        #expect(position.row == 0)
        #expect(position.column == 0)
    }

    @Test("Calculate next favorite position fills row first")
    func nextPositionFillsRow() throws {
        let env = try TabManagerTestEnvironment()

        // Add first favorite at (0,0)
        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://one.com")!,
            title: "One",
            isFavorite: true,
            favoriteMode: .shortcut,
        )

        let position = env.bookmarksManager.calculateNextFavoritePosition()

        #expect(position.row == 0)
        #expect(position.column == 1)
    }

    @Test("Calculate next favorite position wraps to next row")
    func nextPositionWrapsRow() throws {
        let env = try TabManagerTestEnvironment()

        // Fill first row (4 columns)
        for i in 0 ..< 4 {
            _ = env.bookmarksManager.createBookmark(
                url: URL(string: "https://site\(i).com")!,
                title: "Site \(i)",
                isFavorite: true,
                favoriteMode: .shortcut,
            )
        }

        let position = env.bookmarksManager.calculateNextFavoritePosition()

        #expect(position.row == 1)
        #expect(position.column == 0)
    }

    @Test("Normalize favorite positions eliminates gaps")
    func normalizeFavoritePositionsEliminatesGaps() throws {
        let env = try TabManagerTestEnvironment()

        // Create favorites
        let b1 = env.bookmarksManager.createBookmark(
            url: URL(string: "https://one.com")!,
            title: "One",
            isFavorite: true,
            favoriteMode: .shortcut,
        )
        let b2 = env.bookmarksManager.createBookmark(
            url: URL(string: "https://two.com")!,
            title: "Two",
            isFavorite: true,
            favoriteMode: .shortcut,
        )
        let b3 = env.bookmarksManager.createBookmark(
            url: URL(string: "https://three.com")!,
            title: "Three",
            isFavorite: true,
            favoriteMode: .shortcut,
        )

        // Create a gap by manually setting positions
        b1.favoritePosition = FavoritePosition(row: 0, col: 0)
        b2.favoritePosition = FavoritePosition(row: 0, col: 2) // Gap at (0,1)
        b3.favoritePosition = FavoritePosition(row: 1, col: 0)
        env.bookmarksManager.refreshFavoritesCache()

        env.bookmarksManager.normalizeFavoritePositions()

        // After normalization, positions should be sequential
        #expect(b1.favoritePosition == FavoritePosition(row: 0, col: 0))
        #expect(b2.favoritePosition == FavoritePosition(row: 0, col: 1))
        #expect(b3.favoritePosition == FavoritePosition(row: 0, col: 2))
    }
}

// MARK: - BookmarksManager Search Tests

@Suite("BookmarksManager Search", .tags(.bookmarksManager), .serialized)
@MainActor
struct BookmarksManagerSearchTests {
    @Test("Search by title")
    func searchByTitle() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Swift Programming Guide",
        )
        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://other.com")!,
            title: "Other Site",
        )

        let results = env.bookmarksManager.search(query: "swift")

        #expect(results.count == 1)
        #expect(results.first?.title == "Swift Programming Guide")
    }

    @Test("Search by URL")
    func searchByURL() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://github.com/apple/swift")!,
            title: "Swift Repo",
        )
        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Example",
        )

        let results = env.bookmarksManager.search(query: "github")

        #expect(results.count == 1)
        #expect(results.first?.title == "Swift Repo")
    }

    @Test("Search by tag")
    func searchByTag() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Tagged Site",
            tags: ["development", "swift"],
        )
        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://other.com")!,
            title: "Untagged Site",
        )

        let results = env.bookmarksManager.search(query: "development")

        #expect(results.count == 1)
        #expect(results.first?.title == "Tagged Site")
    }

    @Test("Search is case insensitive")
    func searchCaseInsensitive() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "UPPERCASE Title",
        )

        let results = env.bookmarksManager.search(query: "uppercase")

        #expect(results.count == 1)
    }

    @Test("Search empty query returns empty")
    func searchEmptyQuery() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Example",
        )

        let results = env.bookmarksManager.search(query: "")

        #expect(results.isEmpty)
    }

    @Test("Search respects limit")
    func searchRespectsLimit() throws {
        let env = try TabManagerTestEnvironment()

        for i in 0 ..< 10 {
            _ = env.bookmarksManager.createBookmark(
                url: URL(string: "https://site\(i).com")!,
                title: "Site \(i)",
            )
        }

        let results = env.bookmarksManager.search(query: "site", limit: 3)

        #expect(results.count == 3)
    }

    @Test("Get bookmarks in folder")
    func bookmarksInFolder() throws {
        let env = try TabManagerTestEnvironment()

        let folder = try env.bookmarksManager.createFolder(name: "Work")

        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://work1.com")!,
            title: "Work 1",
            folder: folder,
        )
        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://work2.com")!,
            title: "Work 2",
            folder: folder,
        )
        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://personal.com")!,
            title: "Personal",
        )

        let results = env.bookmarksManager.bookmarks(in: folder)

        #expect(results.count == 2)
        #expect(results.allSatisfy { $0.folder?.id == folder.id })
    }

    @Test("Get bookmarks by tag")
    func bookmarksByTag() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://swift1.com")!,
            title: "Swift 1",
            tags: ["swift"],
        )
        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://swift2.com")!,
            title: "Swift 2",
            tags: ["Swift"], // Different case
        )
        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://other.com")!,
            title: "Other",
            tags: ["other"],
        )

        let results = env.bookmarksManager.bookmarks(tagged: "swift")

        #expect(results.count == 2)
    }

    @Test("Get bookmarks for space")
    func bookmarksForSpace() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://space1.com")!,
            title: "Space 1",
            spaceID: space.id,
        )
        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://global.com")!,
            title: "Global",
        )

        let results = env.bookmarksManager.bookmarks(for: space.id)

        #expect(results.count == 1)
        #expect(results.first?.spaceID == space.id)
    }
}

// MARK: - BookmarksManager Hierarchy Tests

@Suite("BookmarksManager Hierarchy", .tags(.bookmarksManager), .serialized)
@MainActor
struct BookmarksManagerHierarchyTests {
    @Test("Is descendant detects parent-child")
    func isDescendantParentChild() throws {
        let env = try TabManagerTestEnvironment()

        let parent = try env.bookmarksManager.createFolder(name: "Parent")
        let child = try env.bookmarksManager.createFolder(name: "Child", parent: parent)

        #expect(env.bookmarksManager.isDescendant(child, of: parent))
        #expect(!env.bookmarksManager.isDescendant(parent, of: child))
    }

    @Test("Is descendant detects grandparent")
    func isDescendantGrandparent() throws {
        let env = try TabManagerTestEnvironment()

        let grandparent = try env.bookmarksManager.createFolder(name: "Grandparent")
        let parent = try env.bookmarksManager.createFolder(name: "Parent", parent: grandparent)
        let child = try env.bookmarksManager.createFolder(name: "Child", parent: parent)

        #expect(env.bookmarksManager.isDescendant(child, of: grandparent))
        #expect(env.bookmarksManager.isDescendant(parent, of: grandparent))
    }

    @Test("Is descendant returns false for siblings")
    func isDescendantSiblings() throws {
        let env = try TabManagerTestEnvironment()

        let parent = try env.bookmarksManager.createFolder(name: "Parent")
        let child1 = try env.bookmarksManager.createFolder(name: "Child 1", parent: parent)
        let child2 = try env.bookmarksManager.createFolder(name: "Child 2", parent: parent)

        #expect(!env.bookmarksManager.isDescendant(child1, of: child2))
        #expect(!env.bookmarksManager.isDescendant(child2, of: child1))
    }

    @Test("Calculate subtree depth for leaf")
    func subtreeDepthLeaf() throws {
        let env = try TabManagerTestEnvironment()

        let folder = try env.bookmarksManager.createFolder(name: "Leaf")

        let depth = env.bookmarksManager.calculateSubtreeDepth(folder)

        #expect(depth == 0)
    }

    @Test("Calculate subtree depth with children")
    func subtreeDepthWithChildren() throws {
        let env = try TabManagerTestEnvironment()

        let root = try env.bookmarksManager.createFolder(name: "Root")
        let child = try env.bookmarksManager.createFolder(name: "Child", parent: root)
        _ = try env.bookmarksManager.createFolder(name: "Grandchild", parent: child)

        let depth = env.bookmarksManager.calculateSubtreeDepth(root)

        #expect(depth == 2)
    }

    @Test("Root folders returns only top-level")
    func rootFoldersTopLevel() throws {
        let env = try TabManagerTestEnvironment()

        let root1 = try env.bookmarksManager.createFolder(name: "Root 1")
        let root2 = try env.bookmarksManager.createFolder(name: "Root 2")
        _ = try env.bookmarksManager.createFolder(name: "Child", parent: root1)

        let roots = env.bookmarksManager.rootFolders()

        #expect(roots.count == 2)
        #expect(roots.contains(where: { $0.id == root1.id }))
        #expect(roots.contains(where: { $0.id == root2.id }))
    }

    @Test("Subfolders returns direct children only")
    func subfoldersDirectChildren() throws {
        let env = try TabManagerTestEnvironment()

        let parent = try env.bookmarksManager.createFolder(name: "Parent")
        let child1 = try env.bookmarksManager.createFolder(name: "Child 1", parent: parent)
        let child2 = try env.bookmarksManager.createFolder(name: "Child 2", parent: parent)
        _ = try env.bookmarksManager.createFolder(name: "Grandchild", parent: child1)

        let subs = env.bookmarksManager.subfolders(of: parent)

        #expect(subs.count == 2)
        #expect(subs.contains(where: { $0.id == child1.id }))
        #expect(subs.contains(where: { $0.id == child2.id }))
    }
}

// MARK: - BookmarksManager Edge Cases

@Suite("BookmarksManager Edge Cases", .tags(.bookmarksManager), .serialized)
@MainActor
struct BookmarksManagerEdgeCaseTests {
    @Test("Delete bookmark from folder updates folder")
    func deleteBookmarkUpdatesFolder() throws {
        let env = try TabManagerTestEnvironment()

        let folder = try env.bookmarksManager.createFolder(name: "Folder")
        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "In Folder",
            folder: folder,
        )

        #expect(folder.bookmarks.count == 1)

        env.bookmarksManager.deleteBookmark(bookmark)

        #expect(folder.bookmarks.isEmpty)
    }

    @Test("Move bookmark between folders")
    func moveBookmarkBetweenFolders() throws {
        let env = try TabManagerTestEnvironment()

        let folder1 = try env.bookmarksManager.createFolder(name: "Folder 1")
        let folder2 = try env.bookmarksManager.createFolder(name: "Folder 2")

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Moving",
            folder: folder1,
        )

        #expect(folder1.bookmarks.count == 1)
        #expect(folder2.bookmarks.isEmpty)

        env.bookmarksManager.moveBookmark(bookmark, to: folder2)

        #expect(folder1.bookmarks.isEmpty)
        #expect(folder2.bookmarks.count == 1)
        #expect(bookmark.folder?.id == folder2.id)
    }

    @Test("Move bookmark to root")
    func moveBookmarkToRoot() throws {
        let env = try TabManagerTestEnvironment()

        let folder = try env.bookmarksManager.createFolder(name: "Folder")
        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "In Folder",
            folder: folder,
        )

        env.bookmarksManager.moveBookmark(bookmark, to: nil)

        #expect(bookmark.folder == nil)
        #expect(folder.bookmarks.isEmpty)
    }

    @Test("Create favorite bookmark gets position")
    func createFavoriteBookmarkGetsPosition() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Favorite",
            isFavorite: true,
            favoriteMode: .shortcut,
        )

        #expect(bookmark.favoritePosition.row >= 0)
        #expect(bookmark.favoritePosition.column >= 0)
    }

    @Test("Favorites cache updates on changes")
    func favoritesCacheUpdates() throws {
        let env = try TabManagerTestEnvironment()

        #expect(env.bookmarksManager.favorites.isEmpty)

        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Favorite",
            isFavorite: true,
            favoriteMode: .shortcut,
        )

        #expect(env.bookmarksManager.favorites.count == 1)
    }
}
