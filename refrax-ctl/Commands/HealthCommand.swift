import ArgumentParser
import Foundation
import RefraxProtocol

struct HealthCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "health",
        abstract: "Show browser health and status information",
        discussion: """
        Returns detailed health information including app version, protocol \
        version, memory usage, tab/window/space counts, and uptime.
        
        Examples:
          refrax-ctl health
          refrax-ctl health --json
        """,
    )

    @Flag(name: .long, help: "Output raw JSON")
    var json = false

    func run() async throws {
        try sendAndHandle(.health, json: json)
    }
}
