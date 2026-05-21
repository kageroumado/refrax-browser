import ArgumentParser
import Foundation
import RefraxProtocol

struct FindElementsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "find-elements",
        abstract: "Search for elements by text, role, or tag",
        discussion: """
        Searches the page for elements matching the given criteria. \
        Returns matching elements with ref IDs for use in click, type, etc.
        
        Examples:
          refrax-ctl find-elements --text "Submit"
          refrax-ctl find-elements --role button
          refrax-ctl find-elements --text "Add to Cart" --role button
          refrax-ctl find-elements --tag input --limit 5
        """,
    )

    @Option(name: .long, help: "Text content to search for (case-insensitive)")
    var text: String?

    @Option(name: .long, help: "ARIA role to filter by (e.g., button, link, textbox)")
    var role: String?

    @Option(name: .long, help: "HTML tag to filter by (e.g., a, button, input)")
    var tag: String?

    @Option(name: .long, help: "Maximum results (default: 10)")
    var limit: Int?

    @Option(name: .long, help: "Target tab ID")
    var tab: String?

    @Option(name: .long, help: "Target page ID")
    var page: String?

    @Flag(name: .long, help: "Output as JSON")
    var json = false

    func run() async throws {
        try sendAndHandle(
            .findElements(.init(
                text: text,
                role: role,
                tag: tag,
                limit: limit,
                tabID: tab,
                pageID: page,
            )),
            json: json,
        )
    }
}
