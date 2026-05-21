import ArgumentParser
import Foundation
import RefraxProtocol

struct HotkeyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "hotkey",
        abstract: "Send a keyboard shortcut",
    )

    @Argument(help: "Key combination (e.g. \"cmd,k\" or \"cmd,shift,t\")")
    var keys: String

    func run() async throws {
        try sendAndHandle(
            .hotkey(.init(keys: keys)),
        )
    }
}
