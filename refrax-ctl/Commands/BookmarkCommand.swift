import ArgumentParser
import Foundation
import RefraxProtocol

struct BookmarkCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "bookmark",
        abstract: "Manage bookmarks",
        subcommands: [
            List.self,
            Add.self,
            Delete.self,
            Favorite.self,
            Unfavorite.self,
            Folders.self,
            CreateFolder.self,
        ],
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List bookmarks",
            discussion: """
            Lists bookmarks, optionally filtered by folder or search query.
            
            Examples:
              refrax-ctl bookmark list
              refrax-ctl bookmark list --folder ABC123
              refrax-ctl bookmark list --query "swift"
              refrax-ctl bookmark list --json
            """,
        )

        @Option(name: .long, help: "Filter by folder ID")
        var folder: String?

        @Option(name: .long, help: "Search query")
        var query: String?

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(
                .bookmarkList(.init(folderID: folder, query: query)),
                json: json,
            )
        }
    }

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add a bookmark",
            discussion: """
            Creates a new bookmark with the specified URL.
            
            Examples:
              refrax-ctl bookmark add "https://example.com"
              refrax-ctl bookmark add "https://example.com" --title "Example"
              refrax-ctl bookmark add "https://example.com" --folder ABC123 --favorite
            """,
        )

        @Argument(help: "URL to bookmark")
        var url: String

        @Option(name: .long, help: "Bookmark title")
        var title: String?

        @Option(name: .long, help: "Folder ID to place bookmark in")
        var folder: String?

        @Flag(name: .long, help: "Also add to favorites")
        var favorite = false

        func run() async throws {
            try sendAndHandle(
                .bookmarkCreate(.init(
                    url: url,
                    title: title,
                    folderID: folder,
                    favorite: favorite ? true : nil,
                )),
            )
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a bookmark",
            discussion: """
            Removes the specified bookmark.
            
            Examples:
              refrax-ctl bookmark delete ABC123
            """,
        )

        @Argument(help: "Bookmark ID to delete")
        var id: String

        func run() async throws {
            try sendAndHandle(.bookmarkDelete(.init(id: id)))
        }
    }

    struct Favorite: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "favorite",
            abstract: "Add a bookmark to favorites",
            discussion: """
            Marks the specified bookmark as a favorite.
            
            Examples:
              refrax-ctl bookmark favorite ABC123
            """,
        )

        @Argument(help: "Bookmark ID to favorite")
        var id: String

        func run() async throws {
            try sendAndHandle(.bookmarkFavorite(.init(id: id)))
        }
    }

    struct Unfavorite: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "unfavorite",
            abstract: "Remove a bookmark from favorites",
            discussion: """
            Removes the specified bookmark from favorites.
            
            Examples:
              refrax-ctl bookmark unfavorite ABC123
            """,
        )

        @Argument(help: "Bookmark ID to unfavorite")
        var id: String

        func run() async throws {
            try sendAndHandle(.bookmarkUnfavorite(.init(id: id)))
        }
    }

    struct Folders: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "folders",
            abstract: "List bookmark folders",
            discussion: """
            Lists all bookmark folders.
            
            Examples:
              refrax-ctl bookmark folders
              refrax-ctl bookmark folders --json
            """,
        )

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(.bookmarkFolderList, json: json)
        }
    }

    struct CreateFolder: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create-folder",
            abstract: "Create a bookmark folder",
            discussion: """
            Creates a new bookmark folder.
            
            Examples:
              refrax-ctl bookmark create-folder "Work"
              refrax-ctl bookmark create-folder "Nested" --parent ABC123
            """,
        )

        @Argument(help: "Folder name")
        var name: String

        @Option(name: .long, help: "Parent folder ID")
        var parent: String?

        func run() async throws {
            try sendAndHandle(
                .bookmarkFolderCreate(.init(name: name, parentID: parent)),
            )
        }
    }
}
