import Foundation
import SwiftData
import SwiftUI
import Testing

@testable import Refrax

// MARK: - Bookmark Regression Tests

/// Tests for BookmarksManager functionality that could regress when implementing
/// offline content (2.19), smart bookmarks (2.20), and related features.
@Suite("Bookmark Regression", .tags(.tabManager), .serialized)
@MainActor
struct BookmarkRegressionTests {
    // MARK: - Bookmark Creation Tests

    @Test("Create bookmark with URL and title")
    func createBookmarkWithURLAndTitle() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Example Site",
        )

        #expect(bookmark.url.absoluteString == "https://example.com")
        #expect(bookmark.title == "Example Site")
    }

    @Test("Bookmark has unique ID")
    func bookmarkHasUniqueID() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark1 = env.bookmarksManager.createBookmark(
            url: URL(string: "https://one.com")!,
            title: "One",
        )
        let bookmark2 = env.bookmarksManager.createBookmark(
            url: URL(string: "https://two.com")!,
            title: "Two",
        )

        #expect(bookmark1.id != bookmark2.id)
    }

    @Test("Bookmark persists to database")
    func bookmarkPersistsToDatabase() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://persist.com")!,
            title: "Persistent",
        )
        let bookmarkID = bookmark.id

        try env.modelContext.save()

        let descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == bookmarkID })
        let fetched = try env.modelContext.fetch(descriptor)

        #expect(fetched.count == 1)
        #expect(fetched.first?.title == "Persistent")
    }

    // MARK: - Bookmark Folder Tests

    @Test("Bookmark folder can be created")
    func bookmarkFolderCreated() throws {
        let env = try TabManagerTestEnvironment()

        let folder = try env.bookmarksManager.createFolder(name: "Test Folder")

        #expect(folder.name == "Test Folder")
    }

    @Test("Bookmark can be added to folder")
    func bookmarkAddedToFolder() throws {
        let env = try TabManagerTestEnvironment()

        let folder = try env.bookmarksManager.createFolder(name: "My Folder")
        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Example",
            folder: folder,
        )

        #expect(bookmark.folder?.id == folder.id)
    }

    @Test("Root bookmarks have no folder")
    func rootBookmarksNoFolder() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://root.com")!,
            title: "Root Bookmark",
        )

        #expect(bookmark.folder == nil)
    }

    // MARK: - Favorites Tests

    @Test("Bookmark can be added to favorites")
    func bookmarkAddedToFavorites() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://favorite.com")!,
            title: "Favorite",
        )

        env.bookmarksManager.addToFavorites(bookmark)

        let favorites = env.bookmarksManager.favorites
        #expect(favorites.contains { item in
            switch item.type {
            case let .liveFavorite(fav, _):
                fav.id == bookmark.id
            case let .shortcut(fav):
                fav.id == bookmark.id
            default:
                false
            }
        })
    }

    @Test("Removing from favorites works")
    func removeFromFavorites() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://removefav.com")!,
            title: "To Remove",
        )

        env.bookmarksManager.addToFavorites(bookmark)
        env.bookmarksManager.removeFromFavorites(bookmark)

        let favorites = env.bookmarksManager.favorites
        #expect(!favorites.contains { item in
            switch item.type {
            case let .liveFavorite(fav, _):
                fav.id == bookmark.id
            case let .shortcut(fav):
                fav.id == bookmark.id
            default:
                false
            }
        })
    }

    // MARK: - Bookmark Update Tests

    @Test("Bookmark title can be updated")
    func bookmarkTitleUpdated() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "Original",
        )

        bookmark.title = "Updated Title"

        #expect(bookmark.title == "Updated Title")
    }

    @Test("Bookmark URL can be updated")
    func bookmarkURLUpdated() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://original.com")!,
            title: "Test",
        )

        bookmark.url = URL(string: "https://updated.com")!

        #expect(bookmark.url.absoluteString == "https://updated.com")
    }

    // MARK: - Bookmark Deletion Tests

    @Test("Bookmark can be deleted")
    func bookmarkDeleted() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://delete.com")!,
            title: "To Delete",
        )
        let bookmarkID = bookmark.id

        env.bookmarksManager.deleteBookmark(bookmark)

        try env.modelContext.save()

        let descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == bookmarkID })
        let fetched = try env.modelContext.fetch(descriptor)

        #expect(fetched.isEmpty)
    }

    @Test("Deleting folder with deleteContents deletes contents")
    func deletingFolderDeletesContents() throws {
        let env = try TabManagerTestEnvironment()
        let context = env.modelContext

        let folder = try env.bookmarksManager.createFolder(name: "Delete Folder")
        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://child.com")!,
            title: "Child Bookmark",
            folder: folder,
        )
        let bookmarkID = bookmark.id

        // deleteContents: true required to delete bookmarks (default is false which orphans)
        env.bookmarksManager.deleteFolder(folder, deleteContents: true)

        try context.save()

        let descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == bookmarkID })
        let fetched = try context.fetch(descriptor)

        // Bookmark should be deleted with folder when deleteContents: true
        #expect(fetched.isEmpty)
    }

    // MARK: - Bookmark Search Tests

    @Test("Search finds bookmark by title")
    func searchFindsByTitle() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://searchable.com")!,
            title: "Searchable Bookmark",
        )
        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://other.com")!,
            title: "Other Bookmark",
        )

        let results = env.bookmarksManager.search(query: "searchable")

        #expect(results.count == 1)
        #expect(results.first?.title == "Searchable Bookmark")
    }

    @Test("Search finds bookmark by URL")
    func searchFindsByURL() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://findme.com/page")!,
            title: "Generic Title",
        )

        let results = env.bookmarksManager.search(query: "findme")

        #expect(!results.isEmpty)
    }

    @Test("Search is case insensitive")
    func searchCaseInsensitive() throws {
        let env = try TabManagerTestEnvironment()

        _ = env.bookmarksManager.createBookmark(
            url: URL(string: "https://example.com")!,
            title: "UPPERCASE TITLE",
        )

        let results = env.bookmarksManager.search(query: "uppercase")

        #expect(!results.isEmpty)
    }

    // MARK: - Bookmark Favicon Tests

    @Test("Bookmark favicon data persists")
    func bookmarkFaviconPersists() throws {
        let env = try TabManagerTestEnvironment()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://withicon.com")!,
            title: "With Icon",
        )

        let faviconData = Data([0x89, 0x50, 0x4E, 0x47])
        bookmark.faviconData = faviconData
        let bookmarkID = bookmark.id

        try env.modelContext.save()

        let descriptor = FetchDescriptor<Bookmark>(predicate: #Predicate { $0.id == bookmarkID })
        let fetched = try env.modelContext.fetch(descriptor)

        #expect(fetched.first?.faviconData == faviconData)
    }

    // MARK: - Linked Bookmark Tests

    @Test("Tab can link to bookmark")
    func tabLinksToBookmark() throws {
        let env = try TabManagerTestEnvironment()
        let space = env.makeSpace()

        let bookmark = env.bookmarksManager.createBookmark(
            url: URL(string: "https://linked.com")!,
            title: "Linked",
        )

        let tab = env.tabManager.createTab(
            url: URL(string: "https://linked.com")!,
            in: space,
            makeActive: false,
        )
        tab.linkedBookmark = bookmark

        #expect(tab.linkedBookmark?.id == bookmark.id)
    }
}
