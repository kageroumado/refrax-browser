import Darwin
import Foundation
import os
import OSLog
import RefraxProtocol

/// Manages a Unix domain socket server for the `refrax-ctl` CLI.
///
/// The host listens on `ctl.sock` in the app's storage directory and accepts connections
/// from the CLI tool. Each connection follows a half-close protocol:
///
/// 1. Client sends a JSON request and calls `shutdown(SHUT_WR)`
/// 2. Server reads the full request, processes it, writes the response
/// 3. Server closes the connection
///
/// ## Security
///
/// Only connections from the same UID are accepted (`getpeereid`). The peer is then
/// identified by its audit token, and ``ControlAccessManager`` authorizes the app it acts
/// for (see ``ClientIdentity/derive(peer:ownTeamID:inspector:)``). The socket file is created with
/// `chmod 0600` (owner-only read/write). At most ``maxConnections`` clients are served at
/// once; further connections are closed on arrival.
///
/// ## Threading
///
/// A dispatch read source on the listening socket accepts connections off the actor, and
/// each client is handled on a detached task at `.utility` priority. Request processing hops
/// to `@MainActor` via ``RefraxControlServer/decodeAndHandle(_:client:)``.
actor RefraxControlHost {
    private static let logger = OSLog(subsystem: "website.refrax.browser", category: "control-host")

    /// Clients served at once.
    static let maxConnections = 8

    private nonisolated static let acceptQueue = DispatchQueue(label: "website.refrax.browser.control-accept", qos: .utility)

    private var listenFD: Int32 = -1
    private var acceptSource: (any DispatchSourceRead)?

    private let socketPath: String
    private let maxMessageBytes: Int
    private let requestTimeoutSec: TimeInterval
    private let server: RefraxControlServer
    private let inspector = SecurityProcessInspector()
    private let connectionSlots: ConnectionSlots
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
        self.connectionSlots = ConnectionSlots(limit: Self.maxConnections)
    }

    // MARK: - Lifecycle

    /// Starts listening for CLI connections.
    ///
    /// Creates the Unix domain socket, binds it, and starts accepting on a dispatch source.
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

        // The read source signals readiness; accept(2) must then never block the queue.
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: Self.acceptQueue)
        source.setEventHandler { [weak self] in
            self?.acceptPendingConnections(on: fd)
        }
        source.setCancelHandler {
            close(fd)
        }
        source.resume()

        listenFD = fd
        acceptSource = source
        os_log("Control host listening on %{public}@", log: Self.logger, type: .info, socketPath)
    }

    /// Stops accepting connections, closes the listening socket, and removes its file.
    func stop() {
        if listenFD >= 0 {
            shutdown(listenFD, SHUT_RDWR)
        }
        acceptSource?.cancel()
        acceptSource = nil
        listenFD = -1

        unlink(socketPath)
        os_log("Control host stopped", log: Self.logger, type: .info)
    }

    // MARK: - CLI Helper Installation

    // Where the CLI helper is installed. A debug build installs its own helper beside the
    // release one, because a debug helper drives only the debug app.
    #if DEBUG
        nonisolated static let cliHelperDestination = "/usr/local/bin/refrax-ctl-debug"
    #else
        nonisolated static let cliHelperDestination = "/usr/local/bin/refrax-ctl"
    #endif

    /// Serializes install-path checks and mutations across concurrent callers,
    /// so two install attempts can't race between checking and copying.
    private nonisolated static let installLock = OSAllocatedUnfairLock()

    private nonisolated static var cliHelperSource: String {
        (Bundle.main.bundlePath as NSString).appendingPathComponent("Contents/Helpers/refrax-ctl")
    }

    /// AppleScript that copies the helper as root. Paths arrive as `argv`, never in the
    /// script text, and reach the shell through `quoted form of`.
    private nonisolated static let authorizedInstallScript = """
    on run argv
        set sourcePath to quoted form of (item 1 of argv)
        set destinationPath to quoted form of (item 2 of argv)
        set directoryPath to quoted form of (item 3 of argv)
        do shell script "mkdir -p " & directoryPath & " && cp -f " & sourcePath & " " & destinationPath & " && chmod 755 " & destinationPath & " && xattr -dr com.apple.quarantine " & destinationPath with administrator privileges
    end run
    """

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
    /// Surface that through the Settings row and let the user
    /// trigger ``installCLIHelperWithAuthorization()`` explicitly.
    ///
    /// A user-writable copy can be replaced by any process running as the user. A replaced
    /// binary is no longer signed by Refrax's team, so the control server refuses it.
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
    /// Call only from an explicit user action (the Settings row) — the click
    /// is the consent, so no explanatory alert is
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

        let directory = (cliHelperDestination as NSString).deletingLastPathComponent
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", authorizedInstallScript, cliHelperSource, cliHelperDestination, directory]

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
        from source: String, to destination: String, createDirectory: String? = nil,
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

    // MARK: - Accepting

    /// Accepts every connection waiting on the listening socket. Runs on ``acceptQueue``.
    private nonisolated func acceptPendingConnections(on listenFD: Int32) {
        while true {
            let clientFD = accept(listenFD, nil, nil)
            guard clientFD >= 0 else {
                if errno == EINTR {
                    continue
                }
                if errno != EAGAIN, errno != EWOULDBLOCK {
                    os_log("Accept failed: %{public}@", log: Self.logger, type: .error, String(cString: strerror(errno)))
                }
                return
            }

            // An accepted socket inherits O_NONBLOCK; client I/O polls, then blocks.
            _ = fcntl(clientFD, F_SETFL, fcntl(clientFD, F_GETFL) & ~O_NONBLOCK)

            // A client that disconnects mid-request (e.g. CLI timeout) must surface
            // EPIPE from write(2) rather than raise SIGPIPE, which kills the process.
            var nosigpipe: Int32 = 1
            setsockopt(clientFD, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

            guard connectionSlots.acquire() else {
                os_log("Refused connection: %d clients already connected", log: Self.logger, type: .error, Self.maxConnections)
                close(clientFD)
                continue
            }

            let slots = connectionSlots
            Task.detached(priority: .utility) { [weak self] in
                guard let self else {
                    close(clientFD)
                    slots.release()
                    return
                }
                await handleClient(fd: clientFD)
            }
        }
    }

    // MARK: - Client Handling

    private nonisolated func handleClient(fd clientFD: Int32) async {
        defer {
            close(clientFD)
            connectionSlots.release()
        }

        // Step 1: Verify same-UID (always required)
        var peerUID: uid_t = 0
        var peerGID: gid_t = 0
        guard getpeereid(clientFD, &peerUID, &peerGID) == 0, peerUID == getuid() else {
            os_log("Rejected connection from different user", log: Self.logger, type: .error)
            return
        }

        // Step 2: Identify the peer by audit token, derive its host, and authorize the host
        let identity: ClientIdentity
        do throws(ClientIdentity.Refusal) {
            guard let peer = SocketPeer(fileDescriptor: clientFD) else { throw .unidentified }
            identity = try ClientIdentity.derive(peer: .peer(peer), ownTeamID: RefraxCodeSigning.ownTeamID, inspector: inspector)
        } catch {
            os_log("Rejected connection: %{public}@", log: Self.logger, type: .error, error.message)
            refuse(fd: clientFD, code: "untrusted_client", message: error.message)
            return
        }

        guard await accessManager.authorize(identity) else {
            os_log(
                "Rejected unauthorized connection from %{public}@ (%{public}@)",
                log: Self.logger, type: .error, identity.displayName, identity.path,
            )
            refuse(
                fd: clientFD,
                code: "unauthorized",
                message: "Refrax did not allow \(identity.displayName) to control it. Check Settings > Advanced > Control Server.",
            )
            return
        }

        // Step 3: Process the request
        guard let requestData = readAll(fd: clientFD) else {
            os_log("Failed to read request", log: Self.logger, type: .error)
            return
        }

        let responseData = await server.decodeAndHandle(requestData, client: identity)

        if !writeAll(fd: clientFD, data: responseData) {
            os_log("Failed to write response", log: Self.logger, type: .error)
        }
    }

    /// Answers a refused client with an error, after reading its request so the client's
    /// write completes before the socket closes.
    private nonisolated func refuse(fd: Int32, code: String, message: String) {
        _ = readAll(fd: fd)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(ControlResponse.error(CTL.ErrorInfo(code: code, message: message))) else { return }
        _ = writeAll(fd: fd, data: data)
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
            if Date() > deadline {
                return nil
            }

            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let pollResult = poll(&pfd, 1, 250)

            if pollResult < 0 {
                if errno == EINTR {
                    continue
                }
                return nil
            }

            if pollResult == 0 {
                continue
            }

            if pfd.revents & Int16(POLLIN) != 0 {
                let bytesRead = read(fd, chunk, chunkSize)
                if bytesRead < 0 {
                    if errno == EINTR {
                        continue
                    }
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
                    if errno == EINTR {
                        continue
                    }
                    return false
                }
                offset += bytesWritten
            }
            return true
        }
    }
}

// MARK: - Connection Slots

/// Counts clients being served, up to a limit.
final nonisolated class ConnectionSlots: Sendable {
    private let state: OSAllocatedUnfairLock<Int>
    let limit: Int

    init(limit: Int) {
        self.limit = limit
        self.state = OSAllocatedUnfairLock(initialState: 0)
    }

    /// Takes a slot. Returns `false`, taking nothing, when every slot is in use.
    func acquire() -> Bool {
        state.withLock { count in
            guard count < limit else { return false }
            count += 1
            return true
        }
    }

    func release() {
        state.withLock { count in
            count = max(0, count - 1)
        }
    }
}

// MARK: - CLI Helper Status

/// Installation state of the `refrax-ctl` binary on PATH relative to the
/// copy bundled with the running build.
nonisolated enum CLIHelperStatus: Equatable {
    /// The installed helper (``RefraxControlHost/cliHelperDestination``) byte-matches the bundled one.
    case upToDate
    /// Nothing is installed at ``RefraxControlHost/cliHelperDestination``.
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
