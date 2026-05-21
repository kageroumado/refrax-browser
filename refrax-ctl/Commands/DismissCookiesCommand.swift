import ArgumentParser
import Foundation
import RefraxProtocol

struct DismissCookiesCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "dismiss-cookies",
        abstract: "Dismiss cookie consent banners on the current page",
        discussion: """
        Detects and dismisses Cookie Management Platform (CMP) consent \
        banners. By default, uses a privacy-first strategy: reject \
        non-essential cookies first, fall back to accept only if no \
        reject option exists.
        
        Supports IAB TCF, Cookiebot, OneTrust, Usercentrics, Didomi, \
        and generic button-text matching.
        
        Examples:
          refrax-ctl dismiss-cookies
          refrax-ctl dismiss-cookies --accept-all
          refrax-ctl dismiss-cookies --tab 3
        """,
    )

    @Flag(name: .long, help: "Accept all cookies instead of rejecting non-essential ones")
    var acceptAll = false

    @Option(name: .long, help: "Target tab ID")
    var tab: String?

    @Option(name: .long, help: "Page ID (for multi-page tabs)")
    var page: String?

    func run() async throws {
        try sendAndHandle(
            .dismissCookies(.init(acceptAll: acceptAll, tabID: tab, pageID: page)),
        )
    }
}
