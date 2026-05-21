import ArgumentParser
import Foundation
import RefraxProtocol

struct RefPaneCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "refpane",
        abstract: "Control the reference pane",
        subcommands: [
            Show.self,
            Hide.self,
            Toggle.self,
            Add.self,
            CloseTab.self,
            ListTabs.self,
            ActivateTab.self,
            ToMain.self,
        ],
    )

    // MARK: - Existing (refactored to subcommands)

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Show the reference pane",
            discussion: """
            Opens the reference pane if it is hidden.
            
            Examples:
              refrax-ctl refpane show
            """,
        )

        func run() async throws {
            try sendAndHandle(.refPaneShow)
        }
    }

    struct Hide: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "hide",
            abstract: "Hide the reference pane",
            discussion: """
            Hides the reference pane if it is visible.
            
            Examples:
              refrax-ctl refpane hide
            """,
        )

        func run() async throws {
            try sendAndHandle(.refPaneHide)
        }
    }

    struct Toggle: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "toggle",
            abstract: "Toggle the reference pane",
            discussion: """
            Toggles the reference pane visibility.
            
            Examples:
              refrax-ctl refpane toggle
            """,
        )

        func run() async throws {
            try sendAndHandle(.refPaneToggle)
        }
    }

    // MARK: - Tier 1D: Reference Pane Extended

    struct Add: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "add",
            abstract: "Add a URL to the reference pane",
            discussion: """
            Opens a new tab in the reference pane with the specified URL.
            
            Examples:
              refrax-ctl refpane add "https://example.com"
              refrax-ctl refpane add "https://docs.swift.org" --title "Swift Docs"
            """,
        )

        @Argument(help: "URL to open in the reference pane")
        var url: String

        @Option(name: .long, help: "Custom title for the reference tab")
        var title: String?

        func run() async throws {
            try sendAndHandle(
                .refPaneAddTab(.init(url: url, title: title)),
            )
        }
    }

    struct CloseTab: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "close",
            abstract: "Close a reference pane tab",
            discussion: """
            Closes the specified tab in the reference pane.
            
            Examples:
              refrax-ctl refpane close ABC123
            """,
        )

        @Argument(help: "Reference tab ID to close")
        var id: String

        func run() async throws {
            try sendAndHandle(.refPaneCloseTab(.init(id: id)))
        }
    }

    struct ListTabs: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "list",
            abstract: "List reference pane tabs",
            discussion: """
            Lists all tabs currently open in the reference pane.
            
            Examples:
              refrax-ctl refpane list
              refrax-ctl refpane list --json
            """,
        )

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(.refPaneListTabs, json: json)
        }
    }

    struct ActivateTab: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "activate",
            abstract: "Activate a reference pane tab",
            discussion: """
            Switches to the specified tab in the reference pane.
            
            Examples:
              refrax-ctl refpane activate ABC123
            """,
        )

        @Argument(help: "Reference tab ID to activate")
        var id: String

        func run() async throws {
            try sendAndHandle(.refPaneActivateTab(.init(id: id)))
        }
    }

    struct ToMain: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "to-main",
            abstract: "Move a reference tab to the main area",
            discussion: """
            Moves a tab from the reference pane into the main tab area.
            
            Examples:
              refrax-ctl refpane to-main ABC123
            """,
        )

        @Argument(help: "Reference tab ID to move to main area")
        var id: String

        func run() async throws {
            try sendAndHandle(.refPaneMoveToMain(.init(id: id)))
        }
    }
}
