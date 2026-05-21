import Foundation
import Testing

@testable import Refrax

// MARK: - Test Tags

extension Tag {
    /// Tests for real browser bookmark export parsing.
    @Tag static var realBrowserExport: Self
}

// MARK: - Chrome Export Tests

@Suite("Chrome Export", .tags(.realBrowserExport))
@MainActor
struct ChromeExportTests {
    @Test("Parse Chrome export structure")
    func parseStructure() async throws {
        let url = try testResourceURL("Chrome_Bookmarks_Export.html")
        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        // Chrome export has two top-level folders: "Bookmarks Bar" and "Other Bookmarks"
        #expect(folders.count == 2)

        let bookmarksBar = folders.first { $0.name == "Bookmarks Bar" }
        let otherBookmarks = folders.first { $0.name == "Other Bookmarks" }

        #expect(bookmarksBar != nil)
        #expect(otherBookmarks != nil)
    }

    @Test("Bookmarks Bar is marked as favorites folder")
    func bookmarksBarIsFavorites() async throws {
        let url = try testResourceURL("Chrome_Bookmarks_Export.html")
        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        let bookmarksBar = folders.first { $0.name == "Bookmarks Bar" }
        #expect(bookmarksBar?.isFavoritesFolder == true)

        // Other Bookmarks should NOT be marked as favorites
        let otherBookmarks = folders.first { $0.name == "Other Bookmarks" }
        #expect(otherBookmarks?.isFavoritesFolder == false)
    }

    @Test("Parse nested folders in Bookmarks Bar")
    func parseNestedFolders() async throws {
        let url = try testResourceURL("Chrome_Bookmarks_Export.html")
        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        let bookmarksBar = try #require(folders.first { $0.name == "Bookmarks Bar" })

        // Should have "Bar Folder 1" as subfolder and "Apple" as bookmark
        #expect(bookmarksBar.subfolders.count == 1)
        #expect(bookmarksBar.bookmarks.count == 1)
        #expect(bookmarksBar.bookmarks[0].title == "Apple")
        #expect(bookmarksBar.bookmarks[0].url.absoluteString == "https://apple.com/")

        // Nested folder structure
        let barFolder1 = bookmarksBar.subfolders[0]
        #expect(barFolder1.name == "Bar Folder 1")
        #expect(barFolder1.subfolders.count == 1)

        let nestedFolder = barFolder1.subfolders[0]
        #expect(nestedFolder.name == "Bar Folder Nested 1.1")
        #expect(nestedFolder.bookmarks.count == 1)
        #expect(nestedFolder.bookmarks[0].title == "Twitter")
    }

    @Test("Parse Other Bookmarks folder")
    func parseOtherBookmarks() async throws {
        let url = try testResourceURL("Chrome_Bookmarks_Export.html")
        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        let otherBookmarks = try #require(folders.first { $0.name == "Other Bookmarks" })

        #expect(otherBookmarks.bookmarks.count == 2)
        #expect(otherBookmarks.bookmarks.contains { $0.title == "GitHub" })
        #expect(otherBookmarks.bookmarks.contains { $0.title == "Google" })
    }
}

// MARK: - Firefox Export Tests

@Suite("Firefox Export", .tags(.realBrowserExport))
@MainActor
struct FirefoxExportTests {
    @Test("Parse Firefox export structure")
    func parseStructure() async throws {
        let url = try testResourceURL("Firefox_Bookmarks_Export.html")
        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        // Firefox export has two folders: "Mozilla Firefox" and "Development"
        #expect(folders.count == 2)

        let mozillaFolder = folders.first { $0.name == "Mozilla Firefox" }
        let devFolder = folders.first { $0.name == "Development" }

        #expect(mozillaFolder != nil)
        #expect(devFolder != nil)
    }

    @Test("Firefox folders are not favorites by default")
    func noFavoritesFolders() async throws {
        let url = try testResourceURL("Firefox_Bookmarks_Export.html")
        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        // Standard Firefox export doesn't have a favorites/toolbar folder
        for folder in folders {
            #expect(folder.isFavoritesFolder == false)
        }
    }

    @Test("Parse Mozilla Firefox folder bookmarks")
    func parseMozillaBookmarks() async throws {
        let url = try testResourceURL("Firefox_Bookmarks_Export.html")
        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        let mozillaFolder = try #require(folders.first { $0.name == "Mozilla Firefox" })

        #expect(mozillaFolder.bookmarks.count == 3)
        #expect(mozillaFolder.bookmarks.contains { $0.title == "Get Help" })
        #expect(mozillaFolder.bookmarks.contains { $0.title == "Get Involved" })
        #expect(mozillaFolder.bookmarks.contains { $0.title == "About Us" })
    }

    @Test("Parse Development folder bookmarks")
    func parseDevelopmentBookmarks() async throws {
        let url = try testResourceURL("Firefox_Bookmarks_Export.html")
        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        let devFolder = try #require(folders.first { $0.name == "Development" })

        #expect(devFolder.bookmarks.count == 2)
        #expect(devFolder.bookmarks.contains { $0.title == "MDN Web Docs" })
        #expect(devFolder.bookmarks.contains { $0.title == "GitHub" })
    }
}

// MARK: - Safari Export Tests

@Suite("Safari Export", .tags(.realBrowserExport))
@MainActor
struct SafariExportTests {
    @Test("Parse Safari export structure")
    func parseStructure() async throws {
        let url = try testResourceURL("Safari_Bookmarks_Export.html")
        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        // Safari export has: Favorites, Bookmarks Menu, Reading List, Development
        #expect(folders.count >= 3)

        let favorites = folders.first { $0.name == "Favorites" }
        let development = folders.first { $0.name == "Development" }

        #expect(favorites != nil)
        #expect(development != nil)
    }

    @Test("Favorites folder is marked as favorites folder")
    func favoritesIsFavoritesFolder() async throws {
        let url = try testResourceURL("Safari_Bookmarks_Export.html")
        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        let favorites = folders.first { $0.name == "Favorites" }
        #expect(favorites?.isFavoritesFolder == true)

        // Other folders should NOT be marked as favorites
        let development = folders.first { $0.name == "Development" }
        #expect(development?.isFavoritesFolder == false)
    }

    @Test("Parse Favorites folder bookmarks")
    func parseFavoritesBookmarks() async throws {
        let url = try testResourceURL("Safari_Bookmarks_Export.html")
        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        let favorites = try #require(folders.first { $0.name == "Favorites" })

        #expect(favorites.bookmarks.count == 3)
        #expect(favorites.bookmarks.contains { $0.title == "Apple" })
        #expect(favorites.bookmarks.contains { $0.title == "MacRumors" })
        #expect(favorites.bookmarks.contains { $0.title == "The Verge" })
    }

    @Test("Parse Development folder with nested Resources")
    func parseDevelopmentWithNested() async throws {
        let url = try testResourceURL("Safari_Bookmarks_Export.html")
        let importer = HTMLBookmarkImporter()
        let folders = try await importer.importBookmarks(from: url)

        let development = try #require(folders.first { $0.name == "Development" })

        // Development has 2 bookmarks and 1 subfolder
        #expect(development.bookmarks.count == 2)
        #expect(development.bookmarks.contains { $0.title == "Swift.org" })
        #expect(development.bookmarks.contains { $0.title == "Apple Developer" })

        #expect(development.subfolders.count == 1)

        let resources = development.subfolders[0]
        #expect(resources.name == "Resources")
        #expect(resources.bookmarks.count == 2)
        #expect(resources.bookmarks.contains { $0.title == "GitHub" })
        #expect(resources.bookmarks.contains { $0.title == "Stack Overflow" })
    }
}

// MARK: - Cross-Browser Tests

@Suite("Cross-Browser Export", .tags(.realBrowserExport))
@MainActor
struct CrossBrowserExportTests {
    @Test("Total bookmark counts")
    func totalBookmarkCounts() async throws {
        let importer = HTMLBookmarkImporter()

        // Chrome: Apple, Twitter, GitHub, Google = 4 bookmarks
        let chromeURL = try testResourceURL("Chrome_Bookmarks_Export.html")
        let chromeFolders = try await importer.importBookmarks(from: chromeURL)
        let chromeTotal = chromeFolders.reduce(0) { $0 + $1.totalBookmarkCount }
        #expect(chromeTotal == 4)

        // Firefox: Get Help, Get Involved, About Us, MDN, GitHub = 5 bookmarks
        let firefoxURL = try testResourceURL("Firefox_Bookmarks_Export.html")
        let firefoxFolders = try await importer.importBookmarks(from: firefoxURL)
        let firefoxTotal = firefoxFolders.reduce(0) { $0 + $1.totalBookmarkCount }
        #expect(firefoxTotal == 5)

        // Safari: Apple, MacRumors, The Verge, Swift.org, Apple Developer, GitHub, Stack Overflow = 7 bookmarks
        let safariURL = try testResourceURL("Safari_Bookmarks_Export.html")
        let safariFolders = try await importer.importBookmarks(from: safariURL)
        let safariTotal = safariFolders.reduce(0) { $0 + $1.totalBookmarkCount }
        #expect(safariTotal == 7)
    }

    @Test("All exports have valid URLs")
    func allValidURLs() async throws {
        let importer = HTMLBookmarkImporter()
        let testFiles = ["Chrome_Bookmarks_Export.html", "Firefox_Bookmarks_Export.html", "Safari_Bookmarks_Export.html"]

        for file in testFiles {
            let url = try testResourceURL(file)
            let folders = try await importer.importBookmarks(from: url)

            func checkBookmarks(in folder: ImportedFolder) {
                for bookmark in folder.bookmarks {
                    #expect(bookmark.url.scheme != nil, "URL should have scheme: \(bookmark.url)")
                    #expect(bookmark.url.host != nil, "URL should have host: \(bookmark.url)")
                }
                for subfolder in folder.subfolders {
                    checkBookmarks(in: subfolder)
                }
            }

            for folder in folders {
                checkBookmarks(in: folder)
            }
        }
    }
}

// MARK: - Test Helpers

func testResourceURL(_ filename: String) throws -> URL {
    let fileExtension = (filename as NSString).pathExtension
    let baseName = (filename as NSString).deletingPathExtension

    // First try Bundle.module (for SPM)
    #if SWIFT_PACKAGE
        return Bundle.module.url(
            forResource: baseName,
            withExtension: fileExtension,
            subdirectory: "Resources",
        )!
    #else
        // For Xcode projects, look in the test bundle
        let testBundle = Bundle(for: BundleToken.self)
        if let url = testBundle.url(forResource: baseName, withExtension: fileExtension) {
            return url
        }

        // Fallback to direct file path during development
        let directPath = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Resources")
            .appendingPathComponent(filename)

        guard FileManager.default.fileExists(atPath: directPath.path) else {
            throw TestError.resourceNotFound(filename)
        }

        return directPath
    #endif
}

private class BundleToken {}

private enum TestError: Error, LocalizedError {
    case resourceNotFound(String)

    var errorDescription: String? {
        switch self {
        case let .resourceNotFound(name):
            "Test resource not found: \(name)"
        }
    }
}
