import ArgumentParser
import Foundation
import RefraxProtocol

struct TypeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "type",
        abstract: "Type text into the focused or specified element",
    )

    @Argument(help: "Text to type")
    var text: String

    @Option(name: .long, help: "Target element ref ID")
    var element: String?

    func run() async throws {
        try sendAndHandle(
            .type(.init(text: text, elementRef: element)),
        )
    }
}
