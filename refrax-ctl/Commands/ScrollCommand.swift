import ArgumentParser
import Foundation
import RefraxProtocol

struct ScrollCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scroll",
        abstract: "Scroll the page or scroll an element into view",
        discussion: """
        Scroll the page in a direction, or scroll a specific element into view.
        
        Examples:
          refrax-ctl scroll down
          refrax-ctl scroll up --amount 1000
          refrax-ctl scroll --ref e5
          refrax-ctl scroll left --amount 200
          refrax-ctl scroll down --page DEF456
        """,
    )

    @Argument(help: "Direction: up, down, left, or right")
    var direction: String?

    @Option(name: .long, help: "Scroll amount in pixels (default: 500)")
    var amount: Int = 500

    @Option(name: .long, help: "Element ref ID to scroll into view")
    var ref: String?

    @Option(name: .long, help: "Target tab ID")
    var tab: String?

    @Option(name: .long, help: "Page ID (for multi-page tabs)")
    var page: String?

    func run() async throws {
        if ref == nil, direction == nil {
            printError("Provide either a direction (up/down/left/right) or --ref REF_ID")
            _Exit(1)
        }

        if let direction, ref == nil {
            let validDirections = ["up", "down", "left", "right"]
            guard validDirections.contains(direction) else {
                printError("Invalid direction '\(direction)'. Use: up, down, left, or right")
                _Exit(1)
            }
        }

        try sendAndHandle(
            .scroll(.init(direction: direction, amount: amount, ref: ref, tabID: tab, pageID: page)),
        )
    }
}
