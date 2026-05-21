import ArgumentParser
import Foundation
import RefraxProtocol

struct SpaceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "space",
        abstract: "Manage browser spaces",
        subcommands: [
            List.self,
            Switch.self,
            Create.self,
            Update.self,
            Delete.self,
        ],
    )

    struct List: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List all spaces",
            discussion: """
            Lists all spaces with their tab counts and active status.
            
            Examples:
              refrax-ctl space list
              refrax-ctl space list --json
            """,
        )

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(.spaceList, json: json)
        }
    }

    struct Switch: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "switch",
            abstract: "Switch to a space",
            discussion: """
            Activates the specified space.
            
            Examples:
              refrax-ctl space switch ABC123
            """,
        )

        @Argument(help: "Space ID to switch to")
        var id: String

        func run() async throws {
            try sendAndHandle(.spaceSwitch(.init(id: id)))
        }
    }

    // MARK: - Tier 2C: Space CRUD

    struct Create: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "create",
            abstract: "Create a new space",
            discussion: """
            Creates a new space with the given name and optional color/icon.
            
            Examples:
              refrax-ctl space create "Work"
              refrax-ctl space create "Personal" --color blue --icon globe
            """,
        )

        @Argument(help: "Name for the new space")
        var name: String

        @Option(name: .long, help: "Space color")
        var color: String?

        @Option(name: .long, help: "Space icon name")
        var icon: String?

        func run() async throws {
            try sendAndHandle(
                .spaceCreate(.init(name: name, color: color, icon: icon)),
            )
        }
    }

    struct Update: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "update",
            abstract: "Update a space's properties",
            discussion: """
            Updates the name and/or color of an existing space.
            
            Examples:
              refrax-ctl space update ABC123 --name "New Name"
              refrax-ctl space update ABC123 --color red
              refrax-ctl space update ABC123 --name "Work" --color blue
            """,
        )

        @Argument(help: "Space ID to update")
        var id: String

        @Option(name: .long, help: "New name")
        var name: String?

        @Option(name: .long, help: "New color")
        var color: String?

        func run() async throws {
            try sendAndHandle(
                .spaceUpdate(.init(id: id, name: name, color: color)),
            )
        }
    }

    struct Delete: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "delete",
            abstract: "Delete a space",
            discussion: """
            Deletes a space. Optionally moves its tabs to another space.
            
            Examples:
              refrax-ctl space delete ABC123
              refrax-ctl space delete ABC123 --move-tabs-to DEF456
            """,
        )

        @Argument(help: "Space ID to delete")
        var id: String

        @Option(name: .long, help: "Space ID to move tabs to before deletion")
        var moveTabsTo: String?

        func run() async throws {
            try sendAndHandle(
                .spaceDelete(.init(id: id, moveTabsTo: moveTabsTo)),
            )
        }
    }
}
