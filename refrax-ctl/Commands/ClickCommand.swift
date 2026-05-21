import ArgumentParser
import Foundation
import RefraxProtocol

struct ClickCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "click",
        abstract: "Click an element by ref ID, text, or coordinates",
        discussion: """
        Clicks an element on the page. Elements are auto-scrolled into view \
        before clicking when using a ref ID.
        
        Examples:
          refrax-ctl click e5
          refrax-ctl click e5 --double
          refrax-ctl click e5 --right
          refrax-ctl click --coords 100,200
          refrax-ctl click e5 --modifier cmd
          refrax-ctl click --coords 500,300 --double --modifier shift
          refrax-ctl click "Submit" --fuzzy
          refrax-ctl click e5 --read
          refrax-ctl click "Add to Cart" --fuzzy --read
        """,
    )

    @Argument(help: "Element ref ID to click (or text content with --fuzzy)")
    var refID: String?

    @Option(name: .long, help: "Coordinates as X,Y (e.g. 100,200)")
    var coords: String?

    @Flag(name: .long, help: "Double-click instead of single click")
    var double = false

    @Flag(name: .long, help: "Right-click (context menu)")
    var right = false

    @Option(name: .long, help: "Modifier key: cmd, shift, alt, ctrl")
    var modifier: String?

    @Flag(name: .long, help: "Match element by visible text content instead of ref ID")
    var fuzzy = false

    @Flag(name: .long, help: "Return page content after clicking")
    var read = false

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
            printError("Provide either a ref ID (or text with --fuzzy) or --coords X,Y")
            _Exit(1)
        }

        if fuzzy || read {
            let request = ControlRequest.clickAndRead(.init(
                ref: fuzzy ? nil : refID,
                fuzzyText: fuzzy ? refID : nil,
                x: x,
                y: y,
                scope: nil,
                waitForNavigation: nil,
            ))
            if read {
                // Show full page content
                try sendAndHandle(request)
            } else {
                // Fuzzy click only — suppress page content, just confirm success
                let response = try ControlClient.send(request)
                if case let .error(info) = response {
                    printError(info.message)
                    _Exit(1)
                }
                if !CLIConfig.quiet {
                    print("Clicked element matching \"\(refID ?? "")\"")
                }
            }
        } else {
            let modifiers: [String]? = modifier.map { [$0] }

            try sendAndHandle(
                .click(.init(
                    ref: refID,
                    x: x,
                    y: y,
                    doubleClick: double ? true : nil,
                    rightClick: right ? true : nil,
                    modifiers: modifiers,
                )),
            )
        }
    }
}
