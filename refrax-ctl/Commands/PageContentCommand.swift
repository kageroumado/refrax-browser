import ArgumentParser
import Foundation
import RefraxProtocol

struct PageContentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "page-content",
        abstract: "Get the content of a page",
    )

    @Option(name: .long, help: "Tab ref (ID, index, title, URL, active/first/last/next/prev)")
    var tab: String?

    @Option(name: .long, help: "Page ID (for multi-page tabs)")
    var page: String?

    @Option(name: .long, help: "Content scope: viewport, full, main, html, or text")
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
