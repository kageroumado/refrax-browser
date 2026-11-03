import Foundation
import RefraxProtocol

/// Global CLI configuration, set once during argument parsing before
/// ArgumentParser processes the remaining arguments.
///
/// Uses `nonisolated(unsafe)` because these are set exactly once at startup
/// in the main entry point, before any concurrent work begins.
enum CLIConfig {
    nonisolated(unsafe) static var quiet = false
    nonisolated(unsafe) static var verbose = false
    nonisolated(unsafe) static var timeout = 30
    nonisolated(unsafe) static var retry = 0
    nonisolated(unsafe) static var retryDelay: TimeInterval = 1.0

    /// Parsed arguments with global flags stripped (for ArgumentParser).
    nonisolated(unsafe) static var remainingArgs: [String] = []

    /// Reads the global flags that precede the subcommand (see ``CLIGlobalFlags``) and
    /// stores the rest for ArgumentParser.
    static func parseGlobalFlags() {
        let flags = CLIGlobalFlags.parse(Array(CommandLine.arguments.dropFirst()))

        if flags.printVersion {
            let v = ControlProtocolVersion.current.rawValue
            print("refrax-ctl v\(v) (protocol: \(v))")
            _Exit(0)
        }

        quiet = flags.quiet
        verbose = flags.verbose
        timeout = flags.timeout
        retry = flags.retry
        retryDelay = flags.retryDelay
        remainingArgs = flags.remainingArguments
    }
}
