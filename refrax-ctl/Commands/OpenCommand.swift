import ArgumentParser
import Foundation
import RefraxProtocol

struct OpenCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "open",
        abstract: "Open a URL in a new tab",
        discussion: """
        Opens a new tab and navigates to the given URL. Alias for tab open.

        Examples:
          refrax-ctl open "https://example.com"
          refrax-ctl open "https://example.com" --activate
          refrax-ctl open "https://example.com" --space ABC123
        """,
    )

    @Argument(help: "URL to open")
    var url: String

    @Option(name: .long, help: "Space ID to open the tab in")
    var space: String?

    @Flag(name: .long, help: "Activate the new tab")
    var activate = false

    func run() async throws {
        try sendAndHandle(
            .tabOpen(.init(url: url, spaceID: space, activate: activate ? true : nil)),
        )
    }
}
