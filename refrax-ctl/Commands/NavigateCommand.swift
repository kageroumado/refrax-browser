import ArgumentParser
import Foundation
import RefraxProtocol

struct NavigateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "navigate",
        abstract: "Open a URL in a new tab",
        discussion: """
        Creates a new tab and navigates to the URL. Use --wait to block until \
        the page finishes loading, or --read to also return page content.

        To navigate within an existing tab, use `tab navigate` instead.

        Examples:
          refrax-ctl navigate "https://example.com"
          refrax-ctl navigate "https://example.com" --activate
          refrax-ctl navigate "https://example.com" --wait
          refrax-ctl navigate "https://example.com" --read
          refrax-ctl navigate "https://example.com" --read --scope text
        """,
    )

    @Argument(help: "URL to navigate to")
    var url: String

    @Flag(name: .long, help: "Activate the new tab")
    var activate = false

    @Flag(name: .long, help: "Wait for the page to finish loading")
    var wait = false

    @Flag(name: .long, help: "Return page content after navigation (implies --wait)")
    var read = false

    @Option(name: .long, help: "Content scope for --read (viewport/full/main/text/html)")
    var scope: String?

    @Option(name: .long, help: "Timeout in seconds for --wait/--read (default: 30)")
    var timeout: Int?

    @Option(name: .long, help: "Space ID to open the tab in")
    var space: String?

    func run() async throws {
        var contentScope: ControlRequest.PageContentParams.Scope?
        if let scope {
            let scopeValue = scope == "main" ? "mainContent" : scope
            guard let parsed = ControlRequest.PageContentParams.Scope(rawValue: scopeValue) else {
                printError("Invalid scope '\(scope)'. Use: viewport, full, main, html, or text")
                _Exit(1)
            }
            contentScope = parsed
        }

        try sendAndHandle(
            .navigateNewTab(.init(
                url: url,
                scope: read ? contentScope : nil,
                timeout: timeout,
                activate: activate ? true : nil,
                wait: (wait || read) ? true : nil,
                spaceID: space
            )),
        )
    }
}
