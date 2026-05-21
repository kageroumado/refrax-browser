import Foundation

/// Manages the aria2c daemon process lifecycle.
///
/// Spawns aria2c as a subprocess with RPC enabled for controlling downloads.
/// The daemon runs as a background process and communicates via JSON-RPC.
///
/// ## Sandbox Considerations
///
/// For sandboxed apps, the aria2c binary must be:
/// 1. Bundled inside the app (Contents/MacOS/aria2c or Contents/Helpers/)
/// 2. Signed with `com.apple.security.inherit` entitlement
/// 3. Code signed with your Developer ID
///
/// ## Usage
///
/// ```swift
/// let daemon = Aria2Daemon()
/// try await daemon.start()
///
/// // Use Aria2RPC to control downloads
/// let rpc = Aria2RPC(secret: daemon.secret)
///
/// // When done
/// await daemon.stop()
/// ```
actor Aria2Daemon {
    // MARK: - Types

    enum Error: Swift.Error, LocalizedError {
        case binaryNotFound
        case alreadyRunning
        case notRunning
        case startupFailed(String)
        case terminationFailed

        var errorDescription: String? {
            switch self {
            case .binaryNotFound:
                "aria2c binary not found"
            case .alreadyRunning:
                "aria2c daemon is already running"
            case .notRunning:
                "aria2c daemon is not running"
            case let .startupFailed(message):
                "aria2c startup failed: \(message)"
            case .terminationFailed:
                "Failed to terminate aria2c daemon"
            }
        }
    }

    enum State: Sendable {
        case stopped
        case starting
        case running
        case stopping
    }

    // MARK: - Properties

    /// Current daemon state.
    private(set) var state: State = .stopped

    /// RPC port the daemon is listening on.
    let port: Int

    /// RPC secret for authentication.
    let secret: String

    /// The daemon process.
    private var process: Process?

    /// Output pipe for monitoring.
    private var outputPipe: Pipe?

    /// Path to aria2c binary.
    private let binaryPath: String

    /// Path to PID file for crash recovery.
    private var pidFilePath: String {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let aria2Dir = appSupport.appendingPathComponent("Refrax/aria2", isDirectory: true)
        try? FileManager.default.createDirectory(at: aria2Dir, withIntermediateDirectories: true)
        return aria2Dir.appendingPathComponent("daemon.pid").path
    }

    // MARK: - Initialization

    /// Creates a daemon manager.
    ///
    /// - Parameters:
    ///   - port: RPC port (default: 6800).
    ///   - secret: RPC secret (default: auto-generated).
    ///   - binaryPath: Path to aria2c binary (default: bundled or system).
    init(
        port: Int = 6_800,
        secret: String? = nil,
        binaryPath: String? = nil,
    ) {
        self.port = port
        self.secret = secret ?? UUID().uuidString
        self.binaryPath = binaryPath ?? Self.findBinary()
    }

    /// Custom configuration for the daemon.
    private var configuration: Configuration?

    // MARK: - Lifecycle

    /// Starts the aria2c daemon with default arguments.
    ///
    /// - Parameter waitForReady: Wait for RPC to be available (default: true).
    /// - Throws: If the daemon fails to start.
    func start(waitForReady: Bool = true) async throws {
        try await start(configuration: nil, waitForReady: waitForReady)
    }

    /// Starts the aria2c daemon with custom configuration.
    ///
    /// - Parameters:
    ///   - configuration: Custom configuration for the daemon.
    ///   - waitForReady: Wait for RPC to be available (default: true).
    /// - Throws: If the daemon fails to start.
    func start(configuration: Configuration?, waitForReady: Bool = true) async throws {
        guard state == .stopped else {
            throw Error.alreadyRunning
        }

        guard FileManager.default.fileExists(atPath: binaryPath) else {
            throw Error.binaryNotFound
        }

        state = .starting
        self.configuration = configuration

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = configuration?.toArguments() ?? buildArguments()

        // Capture output for debugging
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        // Handle termination
        process.terminationHandler = { [weak self] _ in
            Task { await self?.handleTermination() }
        }

        do {
            try process.run()
        } catch {
            state = .stopped
            throw Error.startupFailed(error.localizedDescription)
        }

        self.process = process
        self.outputPipe = outputPipe

        // Write PID file for crash recovery
        writePidFile(pid: process.processIdentifier)

        // Wait for RPC to be available
        if waitForReady {
            let rpc = Aria2RPC(port: port, secret: secret)
            var attempts = 0
            let maxAttempts = 20 // 2 seconds total

            do {
                while attempts < maxAttempts {
                    if await rpc.isRunning() {
                        state = .running
                        return
                    }
                    try await Task.sleep(for: .milliseconds(100))
                    attempts += 1
                }
            } catch {
                // Task cancelled during polling — clean up the process we started
                cleanup()
                throw error
            }

            // Startup timed out
            await stop()
            throw Error.startupFailed("RPC server did not respond")
        } else {
            state = .running
        }
    }

    /// Stops the aria2c daemon gracefully.
    func stop() async {
        guard state == .running || state == .starting else { return }

        state = .stopping

        // Try graceful shutdown via RPC first
        let rpc = Aria2RPC(port: port, secret: secret)
        do {
            try await rpc.shutdown()
            // Wait for process to exit
            try await Task.sleep(for: .milliseconds(500))
        } catch {
            // RPC failed, force terminate
        }

        // Force terminate if still running
        if let process, process.isRunning {
            process.terminate()

            // Wait briefly for termination
            try? await Task.sleep(for: .milliseconds(200))

            // Force kill if still alive
            if process.isRunning {
                process.interrupt() // SIGINT
            }
        }

        cleanup()
    }

    /// Force stops the daemon immediately.
    func forceStop() {
        if let process, process.isRunning {
            process.terminate()
        }
        cleanup()
    }

    // MARK: - Status

    /// Whether the daemon is currently running.
    var isRunning: Bool {
        state == .running && (process?.isRunning ?? false)
    }

    /// Creates an RPC client connected to this daemon.
    func createRPCClient() -> Aria2RPC {
        Aria2RPC(port: port, secret: secret)
    }

    // MARK: - Private

    private func buildArguments() -> [String] {
        [
            "--enable-rpc",
            "--rpc-listen-port=\(port)",
            "--rpc-secret=\(secret)",
            "--rpc-listen-all=false", // Security: localhost only
            "--rpc-allow-origin-all=false", // Security: no CORS
            "--continue=true", // Enable resume by default
            "--max-connection-per-server=16",
            "--split=16",
            "--min-split-size=1M",
            "--max-concurrent-downloads=5",
            "--file-allocation=falloc", // Fast allocation on APFS
            "--disk-cache=64M",
            "--quiet=true", // Minimal console output
            "--console-log-level=warn",
        ]
    }

    private func handleTermination() {
        if state == .running {
            // Unexpected termination
            Logger.warning("aria2c daemon terminated unexpectedly", category: Logger.downloads)
        }
        cleanup()
    }

    private func cleanup() {
        process = nil
        outputPipe = nil
        state = .stopped
        removePidFile()
    }

    // MARK: - PID File Management

    /// Writes the daemon PID to a file for crash recovery.
    private func writePidFile(pid: Int32) {
        do {
            try "\(pid)".write(toFile: pidFilePath, atomically: true, encoding: .utf8)
        } catch {
            Logger.warning("Failed to write aria2 PID file: \(error)", category: Logger.downloads)
        }
    }

    /// Removes the PID file.
    private func removePidFile() {
        try? FileManager.default.removeItem(atPath: pidFilePath)
    }

    /// Reads the PID from the PID file.
    private func readPidFile() -> Int32? {
        guard let content = try? String(contentsOfFile: pidFilePath, encoding: .utf8),
              let pid = Int32(content.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return nil
        }
        return pid
    }

    /// Checks if a process with the given PID is running.
    private func isProcessRunning(pid: Int32) -> Bool {
        // kill with signal 0 checks if process exists without sending a signal
        kill(pid, 0) == 0
    }

    /// Cleans up any stale daemon process from a previous crash.
    ///
    /// Call this on app launch before starting a new daemon.
    func cleanupStaleDaemon() async {
        guard let pid = readPidFile() else { return }

        if isProcessRunning(pid: pid) {
            Logger.warning("Found stale aria2 daemon (PID \(pid)), terminating", category: Logger.downloads)
            // Try graceful termination first
            kill(pid, SIGTERM)

            // Wait briefly then force kill if needed
            try? await Task.sleep(for: .milliseconds(500))
            if isProcessRunning(pid: pid) {
                kill(pid, SIGKILL)
            }
        }

        removePidFile()
    }

    /// Finds the best available aria2c binary.
    ///
    /// Uses ``BundledBinaryResolver`` to check both the app-bundled binary
    /// (`Resources/Binaries/aria2c`) and system installations, returning
    /// whichever has the higher version.
    private static func findBinary() -> String {
        BundledBinaryResolver.resolve(
            resourceName: "aria2c",
            systemPaths: [
                "/opt/homebrew/bin/aria2c",
                "/usr/local/bin/aria2c",
                "/opt/local/bin/aria2c",
            ],
            versionParser: BundledBinaryResolver.parseAria2Version,
        ) ?? "/usr/local/bin/aria2c"
    }
}

// MARK: - Configuration

extension Aria2Daemon {
    /// Configuration for aria2 daemon.
    struct Configuration: Sendable {
        /// RPC port.
        var port: Int = 6_800

        /// RPC secret token.
        var secret: String?

        /// Maximum concurrent downloads.
        var maxConcurrentDownloads: Int = 5

        /// Connections per server.
        var connectionsPerServer: Int = 16

        /// Minimum chunk size for splitting.
        var minSplitSize: String = "1M"

        /// Disk cache size.
        var diskCache: String = "64M"

        /// Download directory.
        var downloadDirectory: String?

        /// Whether to enable BitTorrent support.
        ///
        /// When enabled, adds DHT, peer exchange, and other BitTorrent settings.
        var enableBitTorrent: Bool = false

        /// Path to save session file for resuming downloads across restarts.
        var sessionFile: String?

        init() {}

        func toArguments() -> [String] {
            var args = [
                "--enable-rpc",
                "--rpc-listen-port=\(port)",
                "--rpc-listen-all=false",
                "--rpc-allow-origin-all=false",
                "--continue=true",
                "--max-connection-per-server=\(connectionsPerServer)",
                "--split=\(connectionsPerServer)",
                "--min-split-size=\(minSplitSize)",
                "--max-concurrent-downloads=\(maxConcurrentDownloads)",
                "--disk-cache=\(diskCache)",
                "--file-allocation=falloc",
                "--quiet=true",
                "--console-log-level=warn",
            ]

            if let secret {
                args.append("--rpc-secret=\(secret)")
            }

            if let dir = downloadDirectory {
                args.append("--dir=\(dir)")
            }

            if enableBitTorrent {
                // Enable DHT for finding peers without trackers
                args.append("--enable-dht=true")
                args.append("--dht-listen-port=6881-6999")

                // Enable peer exchange for better peer discovery
                args.append("--enable-peer-exchange=true")

                // Enable Local Peer Discovery (LPD) for LAN peers
                args.append("--bt-enable-lpd=true")

                // Limit peers to avoid overwhelming connections
                args.append("--bt-max-peers=50")

                // Don't seed by default - users can change this
                args.append("--seed-ratio=0.0")
                args.append("--seed-time=0")

                // Follow torrent metadata for organization
                args.append("--bt-metadata-only=false")
                args.append("--follow-torrent=mem")
            }

            if let sessionFile {
                args.append("--save-session=\(sessionFile)")
                args.append("--save-session-interval=60")
                // Load previous session on start
                args.append("--input-file=\(sessionFile)")
            }

            return args
        }
    }
}
