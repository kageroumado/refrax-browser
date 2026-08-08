import Darwin
import Foundation
import os
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

        acceptTask = Task.detached(priority: .utility) { [weak self] in
            await self?.acceptLoop()
        }
    }

    // MARK: - CLI Helper Installation

    /// Absolute path where the CLI helper is installed for PATH access.
    nonisolated static let cliHelperDestination = "/usr/local/bin/refrax-ctl"

    /// Serializes install-path checks and mutations across concurrent callers,
    /// so two install attempts can't race between checking and copying.
    private nonisolated static let installLock = OSAllocatedUnfairLock()

    private nonisolated static var cliHelperSource: String {
        (Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/Helpers/refrax-ctl")
    }

    /// Compares the CLI helper on PATH against the copy bundled with this build.
    nonisolated static func cliHelperStatus() -> CLIHelperStatus {
        let fm = FileManager.default
        let source = cliHelperSource
        guard fm.fileExists(atPath: source) else { return .missingFromBundle }
        guard fm.fileExists(atPath: cliHelperDestination) else { return .notInstalled }
        return fm.contentsEqual(atPath: source, andPath: cliHelperDestination) ? .upToDate : .outdated
    }

    /// Installs or updates the CLI helper when it can be done without privileges.
    ///
    /// Never prompts: when `/usr/local/bin` isn't user-writable the helper is
    /// left untouched and the returned status reports what's still needed.
    /// Surface that through UI (sidebar button, Settings row) and let the user
    /// trigger ``installCLIHelperWithAuthorization()`` explicitly.
    ///
    /// - Returns: The helper status after the attempt.
    @discardableResult
    @concurrent
    nonisolated static func ensureCLIHelperInstalled() async -> CLIHelperStatus {
        installLock.withLock {
            installUnprivileged()
        }
    }

    /// Installs the CLI helper, escalating with the system administrator
    /// prompt when `/usr/local/bin` isn't user-writable.
    ///
    /// Call only from an explicit user action (the Settings row or the sidebar
    /// install button) — the click is the consent, so no explanatory alert is
    /// shown before the system authentication panel.
    ///
    /// - Returns: `true` when the installed helper matches the bundled one afterwards.
    @concurrent
    nonisolated static func installCLIHelperWithAuthorization() async -> Bool {
        installLock.withLock {
            runAuthorizedInstall()
        }
    }

    /// Escalated install body. Caller must hold `installLock`.
    private nonisolated static func runAuthorizedInstall() -> Bool {
        switch installUnprivileged() {
        case .upToDate:
            return true
        case .missingFromBundle:
            return false
        case .notInstalled, .outdated:
            break
        }

        let script = """
        do shell script "mkdir -p /usr/local/bin && cp -f '\(cliHelperSource)' '\(cliHelperDestination)' && chmod 755 '\(cliHelperDestination)' && xattr -dr com.apple.quarantine '\(cliHelperDestination)'" with administrator privileges
        """

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            os_log(
                "Failed to run escalated CLI install: %{public}@",
                log: logger, type: .error, error.localizedDescription,
            )
            return false
        }

        // osascript exits non-zero when the user cancels the auth prompt;
        // trust the filesystem over the exit code either way
        let installed = cliHelperStatus() == .upToDate
        if installed {
            os_log("CLI helper installed to %{public}@ (escalated)", log: logger, type: .info, cliHelperDestination)
        } else {
            os_log(
                "Escalated CLI install did not complete (osascript status %d)",
                log: logger, type: .error, process.terminationStatus,
            )
        }
        return installed
    }

    /// Unprivileged install attempt. Caller must hold `installLock`.
    private nonisolated static func installUnprivileged() -> CLIHelperStatus {
        let status = cliHelperStatus()
        guard status.needsInstall else { return status }

        let fm = FileManager.default
        let globalBin = (cliHelperDestination as NSString).deletingLastPathComponent

        // Creating the directory without privileges works on some systems
        if !fm.fileExists(atPath: globalBin) {
            try? fm.createDirectory(atPath: globalBin, withIntermediateDirectories: true)
        }

        guard fm.fileExists(atPath: globalBin), fm.isWritableFile(atPath: globalBin) else {
            return status
        }

        copyBinary(from: cliHelperSource, to: cliHelperDestination)
        return cliHelperStatus()
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

        // Skip if the destination already byte-matches the source. Size
        // comparison is not enough: rebuilt helpers can coincide in length
        // while differing in content, and after every app update the helper
        // must be refreshed exactly when its bytes changed.
        if fm.contentsEqual(atPath: source, andPath: destination) {
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

            // A client that disconnects mid-request (e.g. CLI timeout) must surface
            // EPIPE from write(2) rather than raise SIGPIPE, which kills the process.
            var nosigpipe: Int32 = 1
            setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

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

// MARK: - CLI Helper Status

/// Installation state of the `refrax-ctl` binary on PATH relative to the
/// copy bundled with the running build.
nonisolated enum CLIHelperStatus: Equatable {
    /// `/usr/local/bin/refrax-ctl` byte-matches the bundled helper.
    case upToDate
    /// Nothing is installed at `/usr/local/bin/refrax-ctl`.
    case notInstalled
    /// An installed binary exists but differs from the bundled helper.
    case outdated
    /// The app bundle contains no helper (development build without the copy phase).
    case missingFromBundle

    /// Whether an install or update is wanted (and possible from this bundle).
    var needsInstall: Bool {
        self == .notInstalled || self == .outdated
    }
}
