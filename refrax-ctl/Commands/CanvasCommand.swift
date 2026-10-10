import ArgumentParser
import Foundation
import RefraxProtocol

struct CanvasCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "canvas",
        abstract: "Open, read, and drive the tab canvas",
        discussion: """
        The tab canvas is a desk on which every tab of the space is a tile. These \
        commands work with Refrax in the background and target the frontmost \
        browser window, or the first one.
        
        Positions are desk points, origin top-left. Every command that changes the \
        desk waits for its tiles to come to rest and then prints the state.
        """,
        subcommands: [Show.self, Hide.self, State.self, Drag.self, Lab.self],
        defaultSubcommand: State.self,
    )

    struct Show: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "show",
            abstract: "Open the canvas",
        )

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(.canvasShow, json: json)
        }
    }

    struct Hide: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "hide",
            abstract: "Close the canvas, back to the tab that was open",
        )

        func run() async throws {
            try sendAndHandle(.canvasHide)
        }
    }

    struct State: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "state",
            abstract: "Print tiles, zones, magnets, and overlaps",
        )

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(.canvasState, json: json)
        }
    }

    struct Drag: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "drag",
            abstract: "Drag a tile as the pointer would",
            discussion: """
            Moves the tile along an eased path until its top-left corner is at X,Y, \
            pushing any tiles in the way, then lets go. With --fling it is let go at \
            full speed and slides on; past the desk's edge it falls off and the tab \
            closes.
            
            Examples:
              refrax-ctl canvas drag first --to 1200,800
              refrax-ctl canvas drag "Crowd · 7" --to 2400,1500 --duration 1.5
              refrax-ctl canvas drag active --to 5200,900 --fling
              refrax-ctl canvas drag first --to=-400,300 --fling   # negative X needs --to=
            """,
        )

        @Argument(help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
        var tab: String

        @Option(name: .long, help: "Destination of the tile's top-left corner: X,Y")
        var to: String

        @Option(name: .long, help: "Seconds the drag takes (default 0.6)")
        var duration: Double?

        @Flag(name: .long, help: "Let go at full speed")
        var fling = false

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            let parts = to.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
            guard parts.count == 2, let x = parts[0], let y = parts[1] else {
                throw ValidationError("--to takes X,Y, for example --to 1200,800")
            }
            try sendAndHandle(
                .canvasDrag(.init(tab: tab, x: x, y: y, duration: duration, fling: fling ? true : nil)),
                json: json,
            )
        }
    }

    struct Lab: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "lab",
            abstract: "Load a lab scenario into a new space (debug builds)",
            discussion: """
            Builds a fresh space of lab pages laid out to a preset and opens the \
            canvas on it. Scenarios: grid, overlap, zone, topics, crowd, unplaced.
            
            Examples:
              refrax-ctl canvas lab crowd
              refrax-ctl canvas lab overlap --json
            """,
        )

        @Argument(help: "Scenario: grid, overlap, zone, topics, crowd, unplaced")
        var scenario: String

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(.canvasLab(.init(scenario: scenario)), json: json)
        }
    }
}
