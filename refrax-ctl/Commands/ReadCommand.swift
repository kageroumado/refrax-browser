import ArgumentParser
import Foundation
import RefraxProtocol

struct ReadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "read",
        abstract: "Read page content",
        discussion: """
        Reads the content of the active (or specified) tab's page. \
        Alias for page-content.

        Examples:
          refrax-ctl read
          refrax-ctl read --scope text
          refrax-ctl read --tab 3
          refrax-ctl read --tab title:GitHub --scope full
        """,
    )

    @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
    var tab: String?

    @Option(name: .long, help: "Page ID (for multi-page tabs)")
    var page: String?

    @Option(name: .long, help: "Content scope: viewport, full, main, text, or html (default: viewport)")
    var scope: String = "viewport"

    @Flag(name: .long, help: "Bypass page content cache")
    var fresh = false

    func run() async throws {
        let scopeValue = scope == "main" ? "mainContent" : scope
        guard let contentScope = ControlRequest.PageContentParams.Scope(rawValue: scopeValue) else {
            printError("Invalid scope '\(scope)'. Use: viewport, full, main, html, or text")
            _Exit(1)
        }

        try sendAndHandle(
            .pageContent(.init(tabID: tab, pageID: page, scope: contentScope, fresh: fresh ? true : nil)),
        )
    }
}
