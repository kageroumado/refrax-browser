import Darwin
import Foundation
import OSLog
import RefraxProtocol

/// Manages a Unix domain socket server for the `refrax-ctl` CLI.
///
/// The host listens on `~/Library/Application Support/Refrax/ctl.sock` and accepts
/// connections from the CLI tool. Each connection follows a half-close protocol:
///
/// 1. Client sends a JSON request and calls `shutdown(SHUT_WR)`
/// 2. Server reads the full request, processes it, writes the response
/// 3. Server closes the connection
///
/// ## Security
///
/// Only connections from the same UID are accepted. In prompt mode, unknown
/// binaries trigger an authorization alert via ``ControlAccessManager``.
/// The socket file is created with `chmod 0600` (owner-only read/write).
///
/// ## Threading
///
/// The accept loop and client handlers run on detached tasks at `.utility` priority
/// to avoid blocking the main actor. The actual request processing hops to `@MainActor`
/// via ``RefraxControlServer/decodeAndHandle(_:)``.
actor RefraxControlHost {
    private static let logger = OSLog(subsystem: "website.refrax.browser", category: "control-host")

    private var listenFD: Int32 = -1
    private var acceptTask: Task<Void, Never>?

    private let socketPath: String
    private let maxMessageBytes: Int
    private let requestTimeoutSec: TimeInterval
    private let server: RefraxControlServer
    let accessManager: ControlAccessManager

    /// Creates a control host bound to the default socket path.
    ///
    /// - Parameters:
    ///   - server: The control server that processes decoded requests.
    ///   - accessManager: Manages client authorization decisions.
    ///   - maxMessageBytes: Maximum request/response size. Default 64 MB.
    ///   - requestTimeoutSec: Per-request read/write timeout. Default 30 seconds.
    init(
        server: RefraxControlServer,
        accessManager: ControlAccessManager,
        maxMessageBytes: Int = 64 * 1_024 * 1_024,
        requestTimeoutSec: TimeInterval = 30,
    ) {
        let appSupport = Directories.appStorage.path
        self.socketPath = (appSupport as NSString).appendingPathComponent("ctl.sock")
        self.server = server
        self.accessManager = accessManager
        self.maxMessageBytes = maxMessageBytes
        self.requestTimeoutSec = requestTimeoutSec
    }

    // MARK: - Lifecycle

    /// Starts listening for CLI connections.
    ///
    /// Creates the Unix domain socket, binds it, and launches the accept loop
    /// on a detached utility-priority task.
    func start() {
        guard listenFD == -1 else {
            os_log("Control host already running", log: Self.logger, type: .info)
            return
        }

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            os_log("Failed to create socket: %{public}@", log: Self.logger, type: .error, String(cString: strerror(errno)))
            return
        }

        let parentDir = (socketPath as NSString).deletingLastPathComponent
        let fm = FileManager.default
        if !fm.fileExists(atPath: parentDir) {
            do {
                try fm.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            } catch {
                os_log("Failed to create socket directory: %{public}@", log: Self.logger, type: .error, error.localizedDescription)
                close(fd)
                return
            }
        }

        unlink(socketPath)

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = socketPath.utf8CString
        guard pathBytes.count <= MemoryLayout.size(ofValue: addr.sun_path) else {
            os_log("Socket path too long: %{public}@", log: Self.logger, type: .error, socketPath)
            close(fd)
            return
        }
        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            let raw = UnsafeMutableRawPointer(ptr)
            pathBytes.withUnsafeBufferPointer { buf in
                raw.copyMemory(from: buf.baseAddress!, byteCount: buf.count)
            }
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                bind(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard bindResult == 0 else {
            os_log("Failed to bind socket: %{public}@", log: Self.logger, type: .error, String(cString: strerror(errno)))
            close(fd)
            return
        }

        chmod(socketPath, 0o600)

        guard listen(fd, SOMAXCONN) == 0 else {
            os_log("Failed to listen on socket: %{public}@", log: Self.logger, type: .error, String(cString: strerror(errno)))
            close(fd)
            return
        }

        listenFD = fd
        os_log("Control host listening on %{public}@", log: Self.logger, type: .info, socketPath)

        installCLIHelper()

        acceptTask = Task.detached(priority: .utility) { [weak self] in
            await self?.acceptLoop()
        }
    }

    /// Installs the CLI helper wrapper and symlink.
    private nonisolated func installCLIHelper() {
        Self.installCLIHelper(socketPath: socketPath)
    }

    /// Installs the `refrax-ctl` binary to `/usr/local/bin` so the CLI is in PATH.
    ///
    /// Tries without privileges first. If `/usr/local/bin` doesn't exist or isn't writable,
    /// escalates via `osascript` (admin prompt). Only prompts when the binary is missing
    /// or outdated — subsequent launches skip if already up to date.
    ///
    /// Skips copying if the destination binary is already the same size (up to date).
    /// Safe to call from any thread — uses only POSIX and Foundation file APIs.
    nonisolated static func installCLIHelper(
        socketPath: String = (Directories.appStorage.path as NSString).appendingPathComponent("ctl.sock")
    ) {
        let fm = FileManager.default
        let bundlePath = Bundle.main.bundlePath
        let helperSource = (bundlePath as NSString).appendingPathComponent("Contents/Helpers/refrax-ctl")

        guard fm.fileExists(atPath: helperSource) else {
            os_log("CLI helper not found in bundle", log: logger, type: .error)
            return
        }

        let globalBin = "/usr/local/bin"
        let globalPath = (globalBin as NSString).appendingPathComponent("refrax-ctl")

        // Try creating the directory without privileges (works on some systems)
        if !fm.fileExists(atPath: globalBin) {
            try? fm.createDirectory(atPath: globalBin, withIntermediateDirectories: true)
        }

        if fm.fileExists(atPath: globalBin), fm.isWritableFile(atPath: globalBin) {
            copyBinary(from: helperSource, to: globalPath)
        } else if !fm.fileExists(atPath: globalPath) {
            installCLIHelperWithEscalation()
        } else {
            // Binary exists but may be outdated — check size
            if let srcAttrs = try? fm.attributesOfItem(atPath: helperSource),
               let dstAttrs = try? fm.attributesOfItem(atPath: globalPath),
               let srcSize = srcAttrs[.size] as? UInt64,
               let dstSize = dstAttrs[.size] as? UInt64,
               srcSize != dstSize
            {
                installCLIHelperWithEscalation()
            }
        }
    }

    /// Copies the CLI helper to `/usr/local/bin` using privilege escalation via `osascript`.
    ///
    /// Shows an explanation dialog first, then the macOS authentication prompt if the user
    /// agrees. If declined, logs a warning — the CLI won't be available in PATH.
    ///
    /// - Returns: `true` if the binary was successfully installed.
    @discardableResult
    nonisolated static func installCLIHelperWithEscalation() -> Bool {
        let bundlePath = Bundle.main.bundlePath
        let helperSource = (bundlePath as NSString).appendingPathComponent("Contents/Helpers/refrax-ctl")
        let destination = "/usr/local/bin/refrax-ctl"

        guard FileManager.default.fileExists(atPath: helperSource) else {
            os_log("CLI helper not found in bundle", log: logger, type: .error)
            return false
        }

        // Show explanation dialog on main thread before the system auth prompt
        let userAccepted: Bool = DispatchQueue.main.sync {
            let alert = NSAlert()
            alert.messageText = "Install Command Line Tool"
            alert.informativeText = """
            Refrax needs administrator permission to install its command line tool \
            (refrax-ctl) to /usr/local/bin.

            This tool lets AI agents and scripts control Refrax from the terminal. \
            If you skip this, refrax-ctl won't be available in your PATH and you'll \
            need to install it manually.
            """
            alert.alertStyle = .informational
            alert.icon = NSApp.applicationIconImage
            alert.addButton(withTitle: "Install")
            alert.addButton(withTitle: "Skip")
            return alert.runModal() == .alertFirstButtonReturn
        }

        guard userAccepted else {
            os_log("User declined CLI helper installation", log: logger, type: .info)
            return false
        }

        let script = """
        do shell script "mkdir -p /usr/local/bin && cp -f '\(helperSource)' '\(destination)' && chmod 755 '\(destination)' && xattr -dr com.apple.quarantine '\(destination)'" with administrator privileges
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                os_log("CLI helper installed to %{public}@ (escalated)", log: logger, type: .info, destination)
                return true
            } else {
                os_log(
                    "Escalated CLI install exited with status %d",
                    log: logger, type: .error, process.terminationStatus,
                )
            }
        } catch {
            os_log("Failed to run escalation: %{public}@", log: logger, type: .error, error.localizedDescription)
        }
        return false
    }

    /// Whether the CLI helper is installed at `/usr/local/bin/refrax-ctl`.
    nonisolated static var isCLIHelperInstalledGlobally: Bool {
        FileManager.default.fileExists(atPath: "/usr/local/bin/refrax-ctl")
    }

    /// Strips the quarantine extended attribute so Gatekeeper doesn't prompt on first launch.
    ///
    /// The binary is already Developer ID signed and covered by the DMG's notarization,
    /// but the quarantine xattr propagates from the downloaded DMG through the app bundle
    /// to any files it copies out. Removing it prevents the "not verified" dialog.
    private nonisolated static func removequarantine(_ path: String) {
        removexattr(path, "com.apple.quarantine", 0)
    }

    /// Copies a binary from source to destination, skipping if already up to date.
    nonisolated static func copyBinary(
        from source: String, to destination: String, createDirectory: String? = nil
    ) {
        let fm = FileManager.default

        if let dir = createDirectory {
            try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }

        // Skip if destination binary has the same size (same build)
        if let srcAttrs = try? fm.attributesOfItem(atPath: source),
           let dstAttrs = try? fm.attributesOfItem(atPath: destination),
           let srcSize = srcAttrs[.size] as? UInt64,
           let dstSize = dstAttrs[.size] as? UInt64,
           srcSize == dstSize {
            return
        }

        do {
            if fm.fileExists(atPath: destination) {
                try fm.removeItem(atPath: destination)
            }
            try fm.copyItem(atPath: source, toPath: destination)
            chmod(destination, 0o755)
            removequarantine(destination)
            os_log("CLI helper installed to %{public}@", log: logger, type: .info, destination)
        } catch {
            os_log(
                "Failed to copy CLI helper to %{public}@: %{public}@",
                log: logger, type: .error, destination, error.localizedDescription,
            )
        }
    }

    /// Stops the control host and cleans up the socket.
    func stop() {
        acceptTask?.cancel()
        acceptTask = nil

        if listenFD >= 0 {
            close(listenFD)
            listenFD = -1
        }

        unlink(socketPath)
        os_log("Control host stopped", log: Self.logger, type: .info)
    }

    // MARK: - Accept Loop

    private func acceptLoop() async {
        let fd = listenFD
        while !Task.isCancelled {
            let clientFD = accept(fd, nil, nil)
            guard clientFD >= 0 else {
                if Task.isCancelled { break }
                if errno == EINTR { continue }
                os_log("Accept failed: %{public}@", log: Self.logger, type: .error, String(cString: strerror(errno)))
                continue
            }

            Task.detached(priority: .utility) { [weak self] in
                await self?.handleClient(fd: clientFD)
            }
        }
    }

    // MARK: - Client Handling

    private nonisolated func handleClient(fd clientFD: Int32) async {
        defer { close(clientFD) }

        // Step 1: Verify same-UID (always required)
        guard let pid = peerPID(clientFD), peerHasSameUID(pid) else {
            os_log("Rejected connection from different user", log: Self.logger, type: .error)
            return
        }

        // Step 2: Resolve client identity and authorize via access manager
        let identity = ClientIdentityResolver.resolve(pid: pid)
        guard await accessManager.authorize(identity) else {
            os_log(
                "Rejected unauthorized connection from %{public}@ (%{public}@)",
                log: Self.logger, type: .error, identity.displayName, identity.path,
            )
            return
        }

        // Step 3: Process the request
        guard let requestData = readAll(fd: clientFD) else {
            os_log("Failed to read request", log: Self.logger, type: .error)
            return
        }

        let responseData = await server.decodeAndHandle(requestData)

        if !writeAll(fd: clientFD, data: responseData) {
            os_log("Failed to write response", log: Self.logger, type: .error)
        }
    }

    // MARK: - Peer Verification

    /// Extracts the PID of the connected peer.
    private nonisolated func peerPID(_ clientFD: Int32) -> pid_t? {
        var pid: pid_t = 0
        var pidLen = socklen_t(MemoryLayout<pid_t>.size)
        guard getsockopt(clientFD, SOL_LOCAL, LOCAL_PEERPID, &pid, &pidLen) == 0 else {
            return nil
        }
        return pid
    }

    /// Verifies the peer process is running as the same user.
    private nonisolated func peerHasSameUID(_ pid: pid_t) -> Bool {
        var info = kinfo_proc()
        var infoSize = MemoryLayout<kinfo_proc>.size
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &infoSize, nil, 0) == 0 else {
            return false
        }
        return info.kp_eproc.e_ucred.cr_uid == getuid()
    }

    // MARK: - I/O

    /// Reads all data from the client using poll-based timeouts.
    ///
    /// Uses 250ms poll slices to remain responsive to cancellation,
    /// with an overall deadline based on ``requestTimeoutSec``.
    private nonisolated func readAll(fd: Int32) -> Data? {
        let deadline = Date().addingTimeInterval(requestTimeoutSec)
        var buffer = Data()
        let chunkSize = 65_536
        let chunk = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
        defer { chunk.deallocate() }

        while true {
            if Date() > deadline { return nil }

            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pollResult = poll(&pfd, 1, 250)

            if pollResult < 0 {
                if errno == EINTR { continue }
                return nil
            }

            if pollResult == 0 { continue }

            if pfd.revents & Int16(POLLIN) != 0 {
                let bytesRead = read(fd, chunk, chunkSize)
                if bytesRead < 0 {
                    if errno == EINTR { continue }
                    return nil
                }
                if bytesRead == 0 {
                    return buffer
                }
                buffer.append(chunk, count: bytesRead)
                if buffer.count > maxMessageBytes {
                    return nil
                }
            }

            if pfd.revents & Int16(POLLHUP) != 0 {
                return buffer
            }

            if pfd.revents & (Int16(POLLERR) | Int16(POLLNVAL)) != 0 {
                return nil
            }
        }
    }

    /// Writes all data to the client.
    private nonisolated func writeAll(fd: Int32, data: Data) -> Bool {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return true }
            var offset = 0
            let total = rawBuffer.count

            while offset < total {
                let bytesWritten = write(fd, baseAddress + offset, total - offset)
                if bytesWritten < 0 {
                    if errno == EINTR { continue }
                    return false
                }
                offset += bytesWritten
            }
            return true
        }
    }
}
