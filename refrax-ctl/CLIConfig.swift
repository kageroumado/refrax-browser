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

    /// Extracts global flags from the process arguments and stores the
    /// cleaned argument list for ArgumentParser to process.
    static func parseGlobalFlags() {
        var args = Array(CommandLine.arguments.dropFirst())

        // --version (print and exit immediately)
        if args.contains("--version") {
            let v = ControlProtocolVersion.v1.rawValue
            print("refrax-ctl v\(v) (protocol: \(v))")
            _Exit(0)
        }

        // --quiet / -q
        if let idx = args.firstIndex(of: "--quiet") { args.remove(at: idx); quiet = true }
        if let idx = args.firstIndex(of: "-q") { args.remove(at: idx); quiet = true }

        // --verbose / -v
        if let idx = args.firstIndex(of: "--verbose") { args.remove(at: idx); verbose = true }
        if let idx = args.firstIndex(of: "-v") { args.remove(at: idx); verbose = true }

        // --timeout N
        if let idx = args.firstIndex(of: "--timeout"), idx + 1 < args.count {
            timeout = Int(args[idx + 1]) ?? 30
            args.remove(at: idx + 1)
            args.remove(at: idx)
        }

        // --retry N
        if let idx = args.firstIndex(of: "--retry"), idx + 1 < args.count {
            retry = Int(args[idx + 1]) ?? 0
            args.remove(at: idx + 1)
            args.remove(at: idx)
        }

        // --retry-delay SECONDS
        if let idx = args.firstIndex(of: "--retry-delay"), idx + 1 < args.count {
            retryDelay = Double(args[idx + 1]) ?? 1.0
            args.remove(at: idx + 1)
            args.remove(at: idx)
        }

        remainingArgs = args
    }
}
