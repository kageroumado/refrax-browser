import ArgumentParser
import Foundation
import RefraxProtocol

struct GroupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "group",
        abstract: "Manage tab groups",
        subcommands: [
            List.self,
            Create.self,
            Delete.self,
            Rename.self,
            Color.self,
            Icon.self,
            ToggleCollapsed.self,
        ],
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List tab groups",
            discussion: """
            Lists all tab groups, optionally filtered by space.
            
            Examples:
              refrax-ctl group list
              refrax-ctl group list --space ABC123
              refrax-ctl group list --json
            """,
        )

        @Option(name: .long, help: "Filter by space ID")
        var space: String?

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(
                .groupList(.init(spaceID: space)),
                json: json,
            )
        }
    }

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a new tab group",
            discussion: """
            Creates a new tab group with the given name and optional \
            color and icon.
            
            Examples:
              refrax-ctl group create "Research"
              refrax-ctl group create "Work" --color blue --icon briefcase
              refrax-ctl group create "Reading" --space ABC123
            """,
        )

        @Argument(help: "Name for the new group")
        var name: String

        @Option(name: .long, help: "Group color")
        var color: String?

        @Option(name: .long, help: "Group icon name")
        var icon: String?

        @Option(name: .long, help: "Space ID to create group in")
        var space: String?

        func run() async throws {
            try sendAndHandle(
                .groupCreate(.init(name: name, color: color, icon: icon, spaceID: space)),
            )
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a tab group",
            discussion: """
            Deletes a tab group. By default, tabs are ungrouped. Use \
            --close-tabs to close all tabs in the group.
            
            Examples:
              refrax-ctl group delete ABC123
              refrax-ctl group delete ABC123 --close-tabs
            """,
        )

        @Argument(help: "Group ID to delete")
        var id: String

        @Flag(name: .long, help: "Close all tabs in the group")
        var closeTabs = false

        func run() async throws {
            try sendAndHandle(
                .groupDelete(.init(id: id, closeTabs: closeTabs ? true : nil)),
            )
        }
    }

    struct Rename: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "rename",
            abstract: "Rename a tab group",
            discussion: """
            Sets a new name for the specified tab group.
            
            Examples:
              refrax-ctl group rename ABC123 "New Name"
            """,
        )

        @Argument(help: "Group ID to rename")
        var id: String

        @Argument(help: "New name for the group")
        var name: String

        func run() async throws {
            try sendAndHandle(
                .groupRename(.init(id: id, name: name)),
            )
        }
    }

    struct Color: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "color",
            abstract: "Set a tab group's color",
            discussion: """
            Changes the color of the specified tab group.
            
            Examples:
              refrax-ctl group color ABC123 blue
              refrax-ctl group color ABC123 red
            """,
        )

        @Argument(help: "Group ID")
        var id: String

        @Argument(help: "Color name")
        var color: String

        func run() async throws {
            try sendAndHandle(
                .groupSetColor(.init(id: id, color: color)),
            )
        }
    }

    struct Icon: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "icon",
            abstract: "Set a tab group's icon",
            discussion: """
            Changes the icon of the specified tab group.
            
            Examples:
              refrax-ctl group icon ABC123 briefcase
              refrax-ctl group icon ABC123 globe
            """,
        )

        @Argument(help: "Group ID")
        var id: String

        @Argument(help: "Icon name (SF Symbol)")
        var icon: String

        func run() async throws {
            try sendAndHandle(
                .groupSetIcon(.init(id: id, icon: icon)),
            )
        }
    }

    struct ToggleCollapsed: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "collapse",
            abstract: "Toggle group collapsed state",
            discussion: """
            Toggles whether the group is collapsed or expanded in the sidebar.
            
            Examples:
              refrax-ctl group collapse ABC123
            """,
        )

        @Argument(help: "Group ID to toggle")
        var id: String

        func run() async throws {
            try sendAndHandle(
                .groupToggleCollapsed(.init(id: id)),
            )
        }
    }
}
