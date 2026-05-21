import ArgumentParser
import Foundation
import RefraxProtocol

struct FetchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fetch",
        abstract: "Fetch a web page without creating a tab",
        discussion: """
        Loads a URL in a headless browser context (no tab created) and returns \
        the page content. Uses the browser's cookies and session, content \
        blockers, and privacy settings. The equivalent of curl but with a \
        full browser engine.

        Content scopes:
          viewport  Structured content visible in a 1024x768 viewport (element refs, roles, links)
          full      Structured content for the entire page
          main      Structured content for the main content area only
          text      Plain text (document.body.innerText)
          html      Raw HTML source

        Examples:
          refrax-ctl fetch "https://example.com"
          refrax-ctl fetch "https://example.com" --scope text
          refrax-ctl fetch "https://news.ycombinator.com" --scope full
        """,
    )

    @Argument(help: "URL to fetch")
    var url: String

    @Option(name: .long, help: "Content scope: viewport, full, main, text, or html (default: viewport)")
    var scope: String = "viewport"

    @Option(name: .long, help: "Timeout in seconds (default: 30)")
    var timeout: Int?

    func run() async throws {
        let scopeValue = scope == "main" ? "mainContent" : scope
        guard let contentScope = ControlRequest.PageContentParams.Scope(rawValue: scopeValue) else {
            printError("Invalid scope '\(scope)'. Use: viewport, full, main, html, or text")
            _Exit(1)
        }

        try sendAndHandle(
            .fetch(.init(url: url, scope: contentScope, timeout: timeout)),
        )
    }
}
