import ArgumentParser
import Foundation
import RefraxProtocol

struct CanvasCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "canvas",
        abstract: "Read and drive the floating tabs",
        discussion: """
        The floating tabs are the tabs of the space as cards over the page, revealed \
        while the reveal key is held. These commands work with Refrax in the \
        background and target the frontmost browser window, or the first one.
        
        Positions are window points, origin top-left.
        """,
        subcommands: [State.self, Floating.self],
        defaultSubcommand: State.self,
    )

    struct State: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            commandName: "state",
            abstract: "Print whether the layer is revealed, and every tab's card",
        )

        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            try sendAndHandle(.canvasState, json: json)
        }
    }

    struct Floating: AsyncParsableCommand {
        static let configuration = CommandConfiguration(commandName: "floating", abstract: "Reveal, place, and pin floating tabs")

        @Argument(help: "show, hide, hold, release, pin, unpin, shape, move, resize, dock-left, dock-right, undock")
        var action: String
        @Argument(help: "For shape: icon, tab, or live")
        var shape: String?
        @Option(name: .long, help: "Tab ref for a presentation or position change")
        var tab: String?
        @Option(name: .long, help: "Top-left destination in window points: X,Y")
        var to: String?
        @Option(name: .long, help: "Preview width in window points")
        var width: Double?
        @Option(name: .long, help: "Preview height in window points")
        var height: Double?
        @Flag(name: .long, help: "Output raw JSON")
        var json = false

        func run() async throws {
            guard let action = ControlRequest.FloatingTabsParams.Action(rawValue: action) else {
                throw ValidationError("Use show, hide, hold, release, pin, unpin, shape, move, resize, dock-left, dock-right, or undock")
            }
            var cardShape: ControlRequest.FloatingTabsParams.Shape?
            if action == .shape {
                guard let shape, let value = ControlRequest.FloatingTabsParams.Shape(rawValue: shape) else {
                    throw ValidationError("shape takes icon, tab, or live")
                }
                cardShape = value
            }
            var x: Double?
            var y: Double?
            if let to {
                let parts = to.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
                guard parts.count == 2, let first = parts[0], let second = parts[1], first.isFinite, second.isFinite else {
                    throw ValidationError("--to takes finite X,Y coordinates")
                }
                x = first
                y = second
            }
            try sendAndHandle(.floatingTabs(.init(action: action, tab: tab, x: x, y: y, width: width, height: height, shape: cardShape)), json: json)
        }
    }
}
