import Foundation

/// The `refrax-ctl` flags that precede the subcommand.
///
/// Parsing stops at the first argument that is not a global flag, so a subcommand's own
/// arguments reach it untouched, including text to type that happens to read `-v` or
/// `--timeout`.
public struct CLIGlobalFlags: Equatable, Sendable {
    public var quiet = false
    public var verbose = false
    public var printVersion = false
    public var timeout = 30
    public var retry = 0
    public var retryDelay: TimeInterval = 1.0

    /// The arguments from the subcommand on, for ArgumentParser.
    public var remainingArguments: [String] = []

    public init() {}

    /// Reads the global flags from the front of `arguments` (the process arguments without
    /// the executable name).
    public static func parse(_ arguments: [String]) -> CLIGlobalFlags {
        var flags = CLIGlobalFlags()
        var index = arguments.startIndex

        scan: while index < arguments.endIndex {
            let argument = arguments[index]
            let value = index + 1 < arguments.endIndex ? arguments[index + 1] : nil
            switch argument {
            case "--version":
                flags.printVersion = true
            case "-q", "--quiet":
                flags.quiet = true
            case "-v", "--verbose":
                flags.verbose = true
            case "--timeout":
                guard let value else { break scan }
                flags.timeout = Int(value) ?? flags.timeout
                index += 1
            case "--retry":
                guard let value else { break scan }
                flags.retry = Int(value) ?? flags.retry
                index += 1
            case "--retry-delay":
                guard let value else { break scan }
                flags.retryDelay = TimeInterval(value) ?? flags.retryDelay
                index += 1
            default:
                break scan
            }
            index += 1
        }

        flags.remainingArguments = Array(arguments[index...])
        return flags
    }
}
