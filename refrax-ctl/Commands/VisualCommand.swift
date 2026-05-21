import ArgumentParser
import Foundation
import RefraxProtocol

struct VisualCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "visual",
        abstract: "Visual agent feedback",
        subcommands: [
            Highlight.self,
            Cursor.self,
            Click.self,
            ScrollTo.self,
            Clear.self,
        ],
    )

    struct Highlight: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "highlight",
            abstract: "Highlight an element on the page",
            discussion: """
            Highlights a page element using its reference ID. Styles: \
            standard, aboutToAct, reading.
            
            Examples:
              refrax-ctl visual highlight e5
              refrax-ctl visual highlight e5 --style aboutToAct
              refrax-ctl visual highlight e12 --style reading
            """,
        )

        @Argument(help: "Element reference ID")
        var ref: String

        @Option(name: .long, help: "Highlight style: standard, aboutToAct, reading")
        var style: String?

        func run() async throws {
            try sendAndHandle(
                .visualHighlight(.init(ref: ref, style: style)),
            )
        }
    }

    struct Cursor: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "cursor",
            abstract: "Show or move the agent cursor",
            discussion: """
            Displays the agent cursor at the specified coordinates.
            
            Examples:
              refrax-ctl visual cursor 500 300
              refrax-ctl visual cursor 100.5 200.5
            """,
        )

        @Argument(help: "X coordinate")
        var x: Double

        @Argument(help: "Y coordinate")
        var y: Double

        func run() async throws {
            try sendAndHandle(
                .visualCursor(.init(x: x, y: y)),
            )
        }
    }

    struct Click: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "click",
            abstract: "Animate a click on an element",
            discussion: """
            Moves the agent cursor to the element and shows a click animation.
            
            Examples:
              refrax-ctl visual click e5
            """,
        )

        @Argument(help: "Element reference ID")
        var ref: String

        func run() async throws {
            try sendAndHandle(
                .visualClick(.init(ref: ref)),
            )
        }
    }

    struct ScrollTo: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "scroll-to",
            abstract: "Smooth scroll to an element or position",
            discussion: """
            Scrolls the page to bring an element into view, or to a specific \
            Y position.
            
            Examples:
              refrax-ctl visual scroll-to --ref e5
              refrax-ctl visual scroll-to --y 500
            """,
        )

        @Option(name: .long, help: "Element reference ID to scroll to")
        var ref: String?

        @Option(name: .long, help: "Y coordinate to scroll to")
        var y: Double?

        func run() async throws {
            try sendAndHandle(
                .visualScrollTo(.init(ref: ref, y: y)),
            )
        }
    }

    struct Clear: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "clear",
            abstract: "Clear all visual feedback",
            discussion: """
            Removes all highlights and hides the agent cursor.
            
            Examples:
              refrax-ctl visual clear
            """,
        )

        func run() async throws {
            try sendAndHandle(.visualClear)
        }
    }
}
