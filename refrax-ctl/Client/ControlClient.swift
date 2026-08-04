import Darwin
import Foundation
import RefraxProtocol

nonisolated enum ControlClient {
    private static let debugSocketPath =
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Application Support/website.refrax.browser.debug/ctl.sock"
    private static let releaseSocketPath =
        "\(FileManager.default.homeDirectoryForCurrentUser.path)/Library/Application Support/website.refrax.browser/ctl.sock"

    /// The control socket to talk to, resolved fresh on every access.
    ///
    /// A socket file outlives its server process (the app only unlinks it on
    /// clean shutdown), so mere existence proves nothing — a stale debug
    /// ctl.sock would shadow a running release Refrax forever, and every
    /// invocation would then auto-launch the debug build. Prefer whichever
    /// socket actually accepts a connection; with neither alive, return the
    /// release path so the connect attempt and the auto-launch flow agree
    /// on a target.
    static var socketPath: String {
        if isSocketAlive(debugSocketPath) {
            return debugSocketPath
        }
        if isSocketAlive(releaseSocketPath) {
            return releaseSocketPath
        }
        return releaseSocketPath
    }

    /// Whether a control server is currently accepting connections.
    static var isServerReachable: Bool {
        isSocketAlive(debugSocketPath) || isSocketAlive(releaseSocketPath)
    }

    /// Attempts a connection to a Unix socket and reports success.
    private static func isSocketAlive(_ path: String) -> Bool {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        let copied = path.withCString { cstr -> Int in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                pathPtr.withMemoryRebound(to: CChar.self, capacity: capacity) { dest in
                    strlcpy(dest, cstr, capacity)
                }
            }
        }
        guard copied < capacity else { return false }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        return result == 0
    }

    static let maxMessageBytes = 64 * 1_024 * 1_024 // 64MB
    static var timeoutSec: TimeInterval {
        TimeInterval(CLIConfig.timeout)
    }

    /// Sends a request and waits for a response (blocking).
    ///
    /// Retries on connection failures if `CLIConfig.retry > 0`.
    /// Auto-launches Refrax if not running and waits for it to become ready.
    static func send(_ request: ControlRequest) throws -> ControlResponse {
        let encoder = JSONEncoder()
        let requestData = try encoder.encode(request)
        let maxAttempts = CLIConfig.retry + 1

        var lastError: any Error = ControlClientError.notRunning
        var didAutoLaunch = false

        for attempt in 1 ... maxAttempts {
            do {
                let responseData = try sendRaw(requestData)
                let decoder = JSONDecoder()
                return try decoder.decode(ControlResponse.self, from: responseData)
            } catch ControlClientError.notRunning where !didAutoLaunch {
                didAutoLaunch = true
                lastError = ControlClientError.notRunning

                if tryLaunch() {
                    continue
                }

                if attempt < maxAttempts {
                    Thread.sleep(forTimeInterval: CLIConfig.retryDelay)
                }
            } catch let error as ControlClientError where error.isRetryable && attempt < maxAttempts {
                lastError = error
                if CLIConfig.verbose {
                    printInfo("[retry] attempt \(attempt)/\(maxAttempts) failed: \(error.localizedDescription)")
                }
                Thread.sleep(forTimeInterval: CLIConfig.retryDelay)
            } catch {
                throw error
            }
        }
        throw lastError
    }

    /// Launches Refrax and waits for the control socket to accept connections.
    ///
    /// Launches the release build first — a developer working against a debug
    /// build has it running already (its live socket wins in `socketPath`), so
    /// reaching this point means no server is up and the release app is the
    /// right thing to start. The debug bundle is only a fallback for machines
    /// with no installed release build.
    ///
    /// - Returns: `true` if a socket becomes available.
    @discardableResult
    static func tryLaunch() -> Bool {
        printInfo("Refrax is not running. Launching...")

        let bundleIDs = ["website.refrax.browser", "website.refrax.browser.debug"]
        var launched = false

        for bundleID in bundleIDs {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = ["-b", bundleID]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice

            do {
                try process.run()
                process.waitUntilExit()
                if process.terminationStatus == 0 {
                    launched = true
                    if CLIConfig.verbose {
                        printInfo("[launch] launched \(bundleID)")
                    }
                    break
                }
            } catch {
                continue
            }
        }

        guard launched else {
            printInfo("Could not launch Refrax. Is it installed?")
            return false
        }

        // Poll until a server accepts connections (up to 10 seconds).
        // Existence checks would be fooled by a stale socket file.
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if isServerReachable {
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }

        printInfo("Refrax launched but control server did not start within 10s.")
        printInfo("Check that CLI Control is enabled in Refrax Settings > Advanced.")
        return false
    }

    /// Low-level: sends raw bytes and returns raw response bytes.
    static func sendRaw(_ data: Data) throws -> Data {
        // 1. Create socket
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw ControlClientError.socketCreationFailed(errno)
        }
        defer { close(fd) }

        // Disable SIGPIPE
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout.size(ofValue: one)))

        // 2. Connect
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let capacity = MemoryLayout.size(ofValue: addr.sun_path)
        let copied = socketPath.withCString { cstr -> Int in
            withUnsafeMutablePointer(to: &addr.sun_path) { pathPtr in
                pathPtr.withMemoryRebound(to: CChar.self, capacity: capacity) { dest in
                    strlcpy(dest, cstr, capacity)
                }
            }
        }
        guard copied < capacity else {
            throw ControlClientError.pathTooLong
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)

        let connectResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
        guard connectResult == 0 else {
            let err = errno
            switch err {
            case ECONNREFUSED, ENOENT:
                throw ControlClientError.notRunning
            default:
                throw ControlClientError.connectFailed(err)
            }
        }

        // 3. Write request
        try writeAll(fd: fd, data: data)

        // 4. Half-close (signal end of request)
        shutdown(fd, SHUT_WR)

        // 5. Read response with timeout
        return try readAll(fd: fd, maxBytes: maxMessageBytes, timeoutSec: timeoutSec)
    }

    private static func writeAll(fd: Int32, data: Data) throws {
        try data.withUnsafeBytes { buf in
            guard let base = buf.baseAddress else { return }
            var written = 0
            while written < data.count {
                let n = write(fd, base.advanced(by: written), data.count - written)
                if n > 0 {
                    written += n
                    continue
                }
                if n == -1, errno == EINTR { continue }
                throw ControlClientError.writeFailed(errno)
            }
        }
    }

    private static func readAll(fd: Int32, maxBytes: Int, timeoutSec: TimeInterval) throws -> Data {
        let deadline = Date().addingTimeInterval(timeoutSec)
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1_024)

        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                throw ControlClientError.timeout
            }

            var pfd = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
            let sliceMs = max(1.0, min(remaining, 0.25) * 1_000.0)
            let polled = poll(&pfd, 1, Int32(sliceMs))
            if polled == 0 { continue }
            if polled < 0 {
                if errno == EINTR { continue }
                throw ControlClientError.readFailed(errno)
            }

            let n = buffer.withUnsafeMutableBytes { read(fd, $0.baseAddress!, $0.count) }
            if n > 0 {
                data.append(buffer, count: n)
                if data.count > maxBytes {
                    throw ControlClientError.responseTooLarge
                }
                continue
            }

            if n == 0 {
                return data // EOF — response complete
            }

            if errno == EINTR || errno == EAGAIN { continue }
            throw ControlClientError.readFailed(errno)
        }
    }
}

enum ControlClientError: LocalizedError {
    case socketCreationFailed(Int32)
    case pathTooLong
    case notRunning
    case connectFailed(Int32)
    case writeFailed(Int32)
    case readFailed(Int32)
    case timeout
    case responseTooLarge

    var errorDescription: String? {
        switch self {
        case let .socketCreationFailed(e): "Failed to create socket: \(String(cString: strerror(e)))"
        case .pathTooLong: "Socket path too long"
        case .notRunning: "Refrax is not running. Run `refrax-ctl launch` to start it."
        case let .connectFailed(e): "Failed to connect: \(String(cString: strerror(e)))"
        case let .writeFailed(e): "Failed to write: \(String(cString: strerror(e)))"
        case let .readFailed(e): "Failed to read: \(String(cString: strerror(e)))"
        case .timeout: "Request timed out (\(CLIConfig.timeout)s). The operation may still be in progress."
        case .responseTooLarge: "Response exceeds maximum size"
        }
    }

    var isRetryable: Bool {
        switch self {
        case .notRunning, .connectFailed, .timeout: true
        default: false
        }
    }
}
