import ArgumentParser
import Foundation
import RefraxProtocol

struct PingCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ping",
        abstract: "Check if Refrax is running and responsive",
    )

    func run() async throws {
        try sendAndHandle(.ping)
    }
}
