import ArgumentParser
import Foundation
import RefraxProtocol

struct StateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "state",
        abstract: "Get the current browser state",
    )

    @Flag(name: .long, help: "Output raw JSON")
    var json = false

    func run() async throws {
        try sendAndHandle(.state, json: json)
    }
}
