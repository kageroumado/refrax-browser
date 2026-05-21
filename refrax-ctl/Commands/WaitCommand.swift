import ArgumentParser
import Foundation

struct WaitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "wait",
        abstract: "Wait for a specified duration",
        discussion: """
        Pauses execution for the given number of seconds. Useful in pipe \
        mode to wait for page loads or animations.
        
        Examples:
          refrax-ctl wait 2
          refrax-ctl wait 0.5
        """,
    )

    @Argument(help: "Duration in seconds (0-30)")
    var seconds: Double

    func run() async throws {
        guard seconds >= 0, seconds <= 30 else {
            printError("Duration must be between 0 and 30 seconds")
            _Exit(1)
        }
        if seconds > 0 {
            try await Task.sleep(for: .milliseconds(Int(seconds * 1_000)))
        }
        print("Waited \(seconds)s")
    }
}
