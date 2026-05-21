import ArgumentParser
import Foundation
import RefraxProtocol

struct HoverCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hover",
        abstract: "Hover over an element to trigger hover states",
        discussion: """
        Moves the mouse over an element without clicking. Triggers hover \
        states, tooltips, and dropdown menus. Elements are auto-scrolled \
        into view when using a ref ID.
        
        Examples:
          refrax-ctl hover e5
          refrax-ctl hover --coords 100,200
          refrax-ctl hover e5 --page DEF456
        """,
    )

    @Argument(help: "Element ref ID to hover over")
    var refID: String?

    @Option(name: .long, help: "Coordinates as X,Y (e.g. 100,200)")
    var coords: String?

    @Option(name: .long, help: "Target tab ID")
    var tab: String?

    @Option(name: .long, help: "Page ID (for multi-page tabs)")
    var page: String?

    func run() async throws {
        var x: Double?
        var y: Double?

        if let coords {
            let parts = coords.split(separator: ",")
            guard parts.count == 2,
                  let px = Double(parts[0]),
                  let py = Double(parts[1])
            else {
                printError("Invalid coordinates '\(coords)'. Use format: X,Y (e.g. 100,200)")
                _Exit(1)
            }
            x = px
            y = py
        }

        guard refID != nil || (x != nil && y != nil) else {
            printError("Provide either a ref ID or --coords X,Y")
            _Exit(1)
        }

        try sendAndHandle(
            .hover(.init(ref: refID, x: x, y: y, tabID: tab, pageID: page)),
        )
    }
}
