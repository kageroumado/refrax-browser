import ArgumentParser
import Foundation

struct LaunchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "launch",
        abstract: "Launch Refrax and wait for the control server to become ready",
    )

    func run() async throws {
        // Quick check if Refrax is already reachable
        if ControlClient.isServerReachable {
            print("Refrax is already running.")
            return
        }

        if ControlClient.tryLaunch() {
            print("Refrax is ready.")
        } else {
            throw ExitCode.failure
        }
    }
}
